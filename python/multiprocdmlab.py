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

def maps_from_config(config):
    entitydir = config.get(
        "entitydir",
        op.join((op.dirname(__file__) or '.'), '../assets/entityLayers'))
    rows, cols, mode, num_maps = [
        config[k] for k in "rows  cols  mode num_maps".split()]

    # Set in maps and map names
    entitydir = op.join(entitydir, "%02dx%02d" %(rows, cols),
                            mode, "entityLayers")

    # Send in mapnames and corresponding entity-files as comma separated strings
    mapname_prepend = "%s-%02dx%02d-" %(mode, rows, cols)
    entityfiles = sorted(glob.glob(entitydir + '/*'))[:num_maps]
    mapnames = [mapname_prepend + os.path.basename(f).replace(".entityLayer","")\
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

class MultiProcDeepmindLab(object):
    process_class = Process
    def __init__(self, deepmind_lab_class, *args, **kwargs):
        self.deepmind_lab_class = deepmind_lab_class
        self.num_workers = kwargs.pop("mpdmlab_workers")
        self.dmlab_args = args
        self.dmlab_kwargs = kwargs

        self.episode_num_steps = self.dmlab_config()["episode_length_seconds"] * self.dmlab_config()["fps"]
        self.episode_step_counter = 0
        self.current_worker_idx = 0
        self.pending_recv_requests = [0] * self.num_workers
        self.mproc_last_goal_found = False
        self.mproc_last_obs = (np.zeros(()), 0, 0, {})

        self.process_config()
        (self.current_conn, self.current_queue
        ) = self.create_new_episode_queue()
        (self.next_episode_conn, self.next_episode_queue
        ) = self.create_new_episode_queue()
        time.sleep(5)

    def dmlab_config(self):
        return self.dmlab_args[1]

    def process_config(self):
        config = self.dmlab_config()
        if "mapnames" not in config or "mapstrings" not in config:
            self.mapnames, self.mapstrings = maps_from_config(config)
            config["mapnames"] = ",".join(self.mapnames)
            config["mapstrings"] = ",".join(self.mapstrings)
        else:
            self.mapnames = config["mapnames"].split(",")
            self.mapstrings = config["mapstrings"].split(",")

    def create_new_episode_queue(self):
        next_pipes = [Pipe()
                 for _ in range(self.num_workers)]
        next_episode_config = self.dmlab_config().copy()
        mapidx = np.random.randint(len(self.mapnames))
        next_episode_config.update(
            dict(mapnames = ",".join(self.mapnames[mapidx:mapidx+1])
                 , mapstrings = ",".join(self.mapstrings[mapidx:mapidx+1])
                 , compute_goal_location = "fixedindex:%d" % np.random.randint(100)
                 , compute_spawn_location = "random_per_subepisode"))
        next_episode_conn = [client for client, server in next_pipes]
        next_episode_workernames = [
                "{}-{}".format(self.mapnames[mapidx], i) for i in range(len(next_pipes))]
        next_episode_kwargs = [self.dmlab_kwargs.copy() for _ in next_pipes]
        for kw in next_episode_kwargs:
            kw["init_game_seed"] = np.random.randint(1000)

        next_episode_queue = [
            Process(
                target=worker_target
                , args=(server , self.deepmind_lab_class
                        , (self.dmlab_args[0] , next_episode_config, self.dmlab_args[2])
                        , kw , worker_name))
            for kw, worker_name, (client, server) in 
            zip(next_episode_kwargs, next_episode_workernames, next_pipes)]
        for wp in next_episode_queue:
            wp.start()
        return next_episode_conn, next_episode_queue

    def close_current_queue(self):
        for conn in self.current_conn:
            conn.send(("worker.quit", (), {}))
        for conn in self.current_conn:
            conn.close()

        #for wp in self.current_queue:
        #    print("terminate", file=sys.stderr)
        #    wp.terminate()
        for wp in self.current_queue:
            wp.join()

    def current_worker_conn(self):
        return self.current_conn[self.current_worker_idx]

    def flush_recv_queue(self):
        while self.pending_recv_requests[self.current_worker_idx] > 0:
            _, _ = self.current_worker_conn().recv()
            self.pending_recv_requests[self.current_worker_idx] -= 1

    def call_sync(self, m_name, m_args=(), m_kwargs={}):
        self.flush_recv_queue()
        self.current_worker_conn().send((m_name, m_args, m_kwargs))
        m_name_recv, m_res = self.current_worker_conn().recv()
        assert m_name_recv == m_name
        return m_res

    def call_async(self, m_name, m_args=(), m_kwargs={}):
        self.current_worker_conn().send((m_name, m_args, m_kwargs))
        self.pending_recv_requests[self.current_worker_idx] += 1
        self.current_worker_idx = (
            self.current_worker_idx + 1) % len(self.current_queue)

    def step(self, act):
        self.episode_step_counter += 1
        if self.episode_step_counter >= self.episode_num_steps:
            # Make an async reset call
            self.reset()
            return self.mproc_last_obs[0], self.mproc_last_obs[1], True, self.mproc_last_obs[3]

        if self.mproc_last_goal_found:
            self.call_async("step", (act,), {})
            self.sub_episode_reset()
            return self.mproc_last_obs
        else:
            obs, rew, done, info = self.call_sync(
                "step", (act,), {})
            self.mproc_last_goal_found = (info['GOAL.FOUND'][0] == 1)
            assert not done, "We should never get 'done'"
            self.mproc_last_obs = obs, rew, done, info.copy()
            return obs, rew, done, info

    def sub_episode_reset(self):
        self.mproc_last_goal_found = False

    def reset(self):
        # Do not need to call actual reset because we are going to
        # throw away the process and restart a new one.
        self.sub_episode_reset()
        self.close_current_queue()
        (self.current_conn, self.current_queue
        ) = (self.next_episode_conn, self.next_episode_queue)
        (self.next_episode_conn, self.next_episode_queue
        ) = self.create_new_episode_queue()
        self.episode_step_counter = 0
        self.pending_recv_requests = [0] * self.num_workers
        return self.mproc_last_obs[0], self.mproc_last_obs[-1]

    @property
    def unwrapped(self):
        return self

    def configure(self, *args, **kwargs):
        return self.call_sync("configure", args, kwargs)

    def observations(self):
        obs, info = self.call_sync("observations")
        return obs, info

    def __getattr__(self, attr):
        if attr in "metadata action_space observation_space reward_range _configured".split():
            return self.call_sync("__getattr__", (attr,))
        elif attr in "close seed render".split():
            return self.call_sync(attr)
        else:
            raise AttributeError("No attr %s" % attr)

    def __del__(self):
        self.close_current_queue()
        (self.current_conn, self.current_queue
        ) = (self.next_episode_conn, self.next_episode_queue)
        self.close_current_queue()
