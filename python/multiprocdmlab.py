from __future__ import print_function
import os.path as op
import os
import glob
import sys
from  multiprocessing import Process, Pipe
import time
import socket
import signal
from contextlib import closing

import numpy as np

from deepmind_lab_gym import DeepmindLab

def get_free_port(host='127.0.0.1'):
    with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as s:
        s.bind((host, 0))
        port = s.getsockname()[1]
    return port

def default_entity_root():
    return op.join((op.dirname(__file__) or '.'), '../assets/entityLayers')

def entity_dir(entity_root, mode,rows, cols):
    # Set in maps and map names
    entitydir = op.join(entity_root, "%02dx%02d" %(rows, cols),
                            mode, "entityLayers")
    return entitydir

def mapname_from_entity_file(entity_file, mode, rows, cols, withvariations=False):
    # Send in mapnames and corresponding entity-files as comma separated strings
    var = "var-" if withvariations else ""
    mapname_prepend = "%s-%02dx%02d-%s" %(mode, rows, cols, var)
    return mapname_prepend + os.path.basename(entity_file).replace(".entityLayer","")

def entity_files(entitydir, mode, rows, cols):
    entitydirpath = entity_dir(entitydir, mode, rows, cols)
    entityfiles = glob.glob(entitydirpath + "/*.entityLayer")
    return entityfiles

def maps_from_config(config):
    entitydir = config.get("entitydir", default_entity_root())
    rows, cols, mode, num_maps, withvariations = [
        config[k] for k in "rows  cols  mode num_maps withvariations".split()]

    entityfiles = entity_files(entitydir, mode, rows, cols)
    if num_maps:
        entityfiles = sorted(entityfiles)[:num_maps]

    mapnames = [mapname_from_entity_file(f, mode, rows, cols, withvariations)
                for f in entityfiles]
    mapstrings = [open(e).read() for e in entityfiles]
    return mapnames, mapstrings
    
class RandomMazesDMLab(object):
    def __init__(self, level_script, config, actionmap, **kwargs):
        if "mapnames" not in config or "mapstrings" not in config:
            mapnames, mapstrings = maps_from_config(config)
            config["mapnames"] = ",".join(mapnames)
            config["mapstrings"] = ",".join(mapstrings)
        else:
            self.mapnames = config["mapnames"].split(",")
            self.mapstrings = config["mapstrings"].split(",")

        self.env = DeepmindLab(level_script, config, actionmap, **kwargs)

    def __getattr__(self, attr):
        return getattr(self.env, attr)


class ZMQConn(object):
    def __init__(self, hostport, isserver=True):
        import zmq
        context = zmq.Context.instance()
        self.isserver = isserver
        if isserver:
            self.socket = context.socket(zmq.REP)
            self.socket_uri = "tcp://%s:%d" % hostport
            self.socket.bind(self.socket_uri)
        else:
            self.socket = context.socket(zmq.REQ)
            self.socket_uri = "tcp://%s:%d" % hostport
            self.socket.connect(self.socket_uri)

            
    def recv(self):
        return self.socket.recv_pyobj()

    def send(self, msg):
        return self.socket.send_pyobj(msg)

    def close(self):
        self.socket.close()

def ZMQPipe(other_host):
    receiver_host = '127.0.0.1'
    receiver_port = get_free_port()
    return (ZMQConn((receiver_host, receiver_port), isserver=False)
            , ZMQConn((receiver_host, receiver_port), isserver=True))

def worker_target(conn, env_class, env_args, env_kwargs, worker_name):
    for sig in signal.SIGHUP, signal.SIGINT, signal.SIGTERM:
        signal.signal(sig, lambda *args: 0)
    m_name = ""  
    env = env_class(*env_args, **env_kwargs)
    while m_name != 'worker.quit':
        m_name, m_args, m_kwargs = conn.recv()
        if m_name == 'worker.quit':
            conn.send("quiting")
            break
        assert isinstance(m_args, tuple), "{} {} {}".format(m_name, m_args, m_kwargs)
        assert isinstance(m_kwargs, dict), "{} {} {}".format(m_name, m_args, m_kwargs)

        if m_name != '__getattr__':
            res = getattr(env, m_name)(*m_args, **m_kwargs)
        else:
            res = getattr(env, m_args[0])
        conn.send((m_name, res))
    conn.close()
    os._exit(0)

class CountingConnection(object):
    def __init__(self, conn):
        self.conn = conn
        self.async_requests = 0

    def send(self, msg):
        self.async_requests += 1
        return self.conn.send(msg)

    def recv(self):
        self.async_requests -= 1
        return self.conn.recv()

    def flush(self):
        while self.async_requests >= 1:
            _ = self.recv()

    def __getattr__(self, attr):
        return getattr(self.conn, attr)

        
class Episode(object):
    def __init__(self, mpdmlab):
        self.step_counter = 0
        self.current_worker_idx = 0

        self.goal_found = False

        self.conn, self.queue = self.create(mpdmlab)

    def worker_conn(self):
        return self.conn[self.current_worker_idx]

    def create(self, mpdmlab):
        next_pipes = [Pipe()
                 for _ in range(mpdmlab.num_workers)]
        next_episode_config = mpdmlab.dmlab_config().copy()
        mapidx = np.random.randint(len(mpdmlab.mapnames))
        next_episode_config.update(
            dict(mapnames = ",".join(mpdmlab.mapnames[mapidx:mapidx+1])
                 , mapstrings = ",".join(mpdmlab.mapstrings[mapidx:mapidx+1])
                 , compute_goal_location = "fixedindex:%d" % np.random.randint(100)
                 , compute_spawn_location = "random_per_subepisode"))
        next_episode_conn = [client for client, server in next_pipes]
        next_episode_workernames = [
            "{}-{}".format(mpdmlab.mapnames[mapidx], i)
            for i in range(len(next_pipes))]
        next_episode_kwargs = [mpdmlab.dmlab_kwargs.copy()
                               for _ in next_pipes]
        for kw in next_episode_kwargs:
            kw["init_game_seed"] = np.random.randint(1000)

        next_episode_queue = [
            Process(
                target=worker_target
                , args=(server , mpdmlab.deepmind_lab_class
                        , (mpdmlab.dmlab_args[0] , next_episode_config, mpdmlab.dmlab_args[2])
                        , kw , worker_name))
            for kw, worker_name, (client, server) in 
            zip(next_episode_kwargs, next_episode_workernames, next_pipes)]
        for wp in next_episode_queue:
            wp.start()
        return map(CountingConnection, next_episode_conn), next_episode_queue


    def call_sync(self, m_name, m_args=(), m_kwargs={}):
        self.worker_conn().flush()
        self.worker_conn().send((m_name, m_args, m_kwargs))
        m_name_recv, m_res = self.worker_conn().recv()
        assert m_name_recv == m_name
        return m_res

    def call_async(self, m_name, m_args=(), m_kwargs={}):
        self.worker_conn().send((m_name, m_args, m_kwargs))
        self.current_worker_idx = (
            self.current_worker_idx + 1) % len(self.queue)

    def close(self, terminate=False):
        for idx, conn in enumerate(self.conn):
            conn.send(("worker.quit", (), {}))
            
        for conn in self.conn:
            conn.flush()
            conn.close()

        if terminate:
            for wp in self.queue:
                wp.terminate()
        for wp in self.queue:
            wp.join()

class MultiProcDeepmindLab(object):
    process_class = Process
    def __init__(self, deepmind_lab_class, *args, **kwargs):
        self.deepmind_lab_class = deepmind_lab_class
        self.num_workers = kwargs.pop("mpdmlab_workers")
        self.dmlab_args = args
        self.dmlab_kwargs = kwargs

        self.episode_num_steps = self.dmlab_config()["episode_length_seconds"] * self.dmlab_config()["fps"]
        self.mapnames, self.mapstrings, dlconfig = self.process_config(
            self.dmlab_config())
        self.dmlab_args = (self.dmlab_args[0], dlconfig, self.dmlab_args[2])

        # Episodes
        self.current = Episode(self)
        self.next = Episode(self)
        self.last_obs = (np.zeros(()), 0, 0, {})
        # time.sleep(5)

    def dmlab_config(self):
        return self.dmlab_args[1]

    def process_config(self, config):
        if "mapnames" not in config or "mapstrings" not in config:
            mapnames, mapstrings = maps_from_config(config)
            config["mapnames"] = ",".join(mapnames)
            config["mapstrings"] = ",".join(mapstrings)
        else:
            mapnames = config["mapnames"].split(",")
            mapstrings = config["mapstrings"].split(",")
        return mapnames, mapstrings, config

    def step(self, act):
        self.current.step_counter += 1
        if self.current.step_counter >= self.episode_num_steps:
            # Make an async reset call
            self.reset()
            obs, rew, done, info = self.last_obs
            return obs, rew, True, info

        if self.current.goal_found:
            self.current.goal_found = False
            self.current.call_async("step", (act,), {})
            obs, rew, done, info = self.last_obs
            return obs, rew, done, info
        else:
            obs, rew, done, info = self.current.call_sync(
                "step", (act,), {})
            self.current.goal_found = (info['GOAL.FOUND'][0] == 1)
            assert not done, "We should never get 'done'"
            self.last_obs = (obs, rew, done, info.copy())
            return (obs, rew, done, info)

    def reset(self):
        # Do not need to call actual reset because we are going to
        # throw away the process and restart a new one.
        self.current.close()
        self.current = self.next
        self.next = Episode(self)
        return self.last_obs[0], self.last_obs[-1]

    @property
    def unwrapped(self):
        return self

    def configure(self, *args, **kwargs):
        return self.current.call_sync("configure", args, kwargs)

    def observations(self):
        obs, info = self.current.call_sync("observations")
        return obs, info

    def __getattr__(self, attr):
        if attr in "metadata action_space observation_space reward_range _configured".split():
            return self.current.call_sync("__getattr__", (attr,))
        elif attr in "close seed render".split():
            return self.current.call_sync(attr)
        else:
            raise AttributeError("No attr %s" % attr)

    def __del__(self):
        self.current.close(terminate=True)
        self.next.close(terminate=True)
        del self.current
        del self.next

