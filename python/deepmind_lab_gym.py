import time
import os
import functools
import numbers
import itertools
import getpass
import random
import string
import warnings
import inspect
import copy

import numpy as np
import cv2
import deepmind_lab
import gym
from gym.envs.registration import register
import logging
from collections import namedtuple

from top_view_renderer import TopView, MatplotlibVisualizer
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

curr_mod_dir = os.path.dirname(
    os.path.abspath(os.path.dirname(__file__) or '.'))

### Calls a function only once and remembers the return value
_called_once = dict()
def call_once(func, *args, **kwargs):
    key = "{}({},{})".format(func, args, kwargs)
    global _called_once
    if key not in _called_once:
        _called_once[key] = ret = func(*args, **kwargs)
        return ret
    return _called_once[key]

ActionMapperParams = namedtuple('ActionMapperParams', ['inc_mat', 'rel_mask_mat'])

# Learning to navigate (MiPaViICLR2017) like action mapping 
# Quote
# ```
# The action space is discrete, yet allows finegrained control,
# comprising 8 actions: the agent can rotate in small increments,
# accelerate forward or backward or sideways, or induce rotational
# acceleration while moving
# ```
L2NActMapParams_v0 = ActionMapperParams(
    # Look left, look right, acc left, acc right,
    # acc left, acc right, acc back, acc forward
    inc_mat = np.array([
        [  10.0 ,-10.0, 10.0 ,-10.0 ,  0.  ,  0.   ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  0.  ,  0.  ,  0.  ,  0.   ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  0.  ,  0.  ,  0.5 , -0.5  ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  0.  ,  0.  ,  0.  ,  0.   ,  0.5 , -0.5 ]
        , [ 0.  ,  0. ,  0.  ,  0.  ,  0.  ,  0.   ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  0.  ,  0.  ,  0.  ,  0.   ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  0.  ,  0.  ,  0.  ,  0.   ,  0.  ,  0.  ]
    ])
    ,
    rel_mask_mat = np.array([
        [   0.  ,  0. ,  1.  ,  1.   ,  1.  ,  1.   ,  1.  ,  1.  ]
        , [ 0.  ,  0. ,  1.  ,  1.   ,  1.  ,  1.   ,  1.  ,  1.  ]
        , [ 0.  ,  0. ,  1.  ,  1.   ,  1.  ,  1.   ,  1.  ,  1.  ]
        , [ 0.  ,  0. ,  1.  ,  1.   ,  1.  ,  1.   ,  1.  ,  1.  ]
        , [ 0.  ,  0. ,  0.  ,  0.   ,  0.  ,  0.   ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  0.  ,  0.   ,  0.  ,  0.   ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  0.  ,  0.   ,  0.  ,  0.   ,  0.  ,  0.  ]
    ])
)

ManhattanWorldActMap_v0 = ActionMapperParams(
    # Look left, look right, acc left, acc right,
    # acc left, acc right, acc back, acc forward
    inc_mat = np.array([
        [  426   , -426 ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  1   , -1.  ]
        , [ 0.  ,  0. ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  0.  ,  0.  ]
    ])
    ,
    rel_mask_mat = np.array([
        [   0.  ,  0. ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  0.  ,  0.  ]
        , [ 0.  ,  0. ,  0.  ,  0.  ]
    ])
)

class L2NActionMapper(object):
    """ 
    """
    DEEPMIND_ACTION_DIM = 7
    ACTIONS = namedtuple('ACTIONS'
                         , """ROT_LEFT ROT_RIGHT 
                         ACC_ROT_LEFT ACC_ROT_RIGHT
                         ACC_STRAFE_LEFT ACC_STRAFE_RIGHT
                         ACC_MOVE_FORWARD ACC_MOVE_BACK""".split())(
                             *range(8))
    def __init__(self, inc_mat, rel_mask_mat):
        assert self.DEEPMIND_ACTION_DIM == inc_mat.shape[0]
        assert self.DEEPMIND_ACTION_DIM == rel_mask_mat.shape[0]
        self.INPUT_ACTION_SIZE = inc_mat.shape[1]
        assert self.INPUT_ACTION_SIZE == rel_mask_mat.shape[1]
        self.inc_mat = inc_mat
        self.rel_mask_mat = rel_mask_mat

    def initial_deepmind_velocities(self):
        return np.zeros(self.DEEPMIND_ACTION_DIM)

    def to_deepmind_action_space(self, action_index, current_velocities):
        """
        >>> am = L2NActionMapper(L2NActMapParams_v0.inc_mat, L2NActMapParams_v0.rel_mask_mat)
        >>> cv = np.zeros(am.DEEPMIND_ACTION_DIM)
        >>> cv = am.to_deepmind_action_space(0, cv)
        >>> np.allclose(cv
        ...             , [ 10,  0. ,  0. ,  0. ,  0. ,  0. ,  0. ])
        True
        >>> cv = am.to_deepmind_action_space(2, cv)
        >>> np.allclose(cv
        ...             , [ 20,  0. ,  0. ,  0. ,  0. ,  0. ,  0. ])
        True
        >>> cv = am.to_deepmind_action_space(4, cv)
        >>> np.allclose(cv
        ...             , [ 20,  0. ,  0.5,  0. ,  0. ,  0. ,  0. ])
        True
        >>> cv = am.to_deepmind_action_space(6, cv)
        >>> np.allclose(cv
        ...             , [ 20,  0. ,  0.5,  0.5 ,  0. ,  0. ,  0. ])
        True
        >>> cv = am.to_deepmind_action_space(7, cv)
        >>> np.allclose(cv
        ...             , [ 20,  0. ,  0.5,  0.0 ,  0. ,  0. ,  0. ])
        True
        >>> cv  = am.to_deepmind_action_space(5, cv)
        >>> np.allclose(cv
        ...             , [ 20,  0. ,  0.0,  0.0 ,  0. ,  0. ,  0. ])
        True
        >>> cv = am.to_deepmind_action_space(3, cv)
        >>> np.allclose(cv
        ...             , [ 10,  0. ,  0.0,  0.0 ,  0. ,  0. ,  0. ])
        True
        """
        if action_index >= self.INPUT_ACTION_SIZE:
            raise ValueError("Bad action {}".format(action_index))

        action = np.zeros(self.INPUT_ACTION_SIZE)
        action[action_index] = 1
        deepmind_action = np.zeros(self.DEEPMIND_ACTION_DIM)
        deepmind_action = self.inc_mat.dot(action) \
                              + self.rel_mask_mat.dot(action) * current_velocities
        return deepmind_action


class ActionMapper(object):
    ACTION_SPACE_INC = np.array([
        [  50.0 ,-50.0 ,  0.  ,  0.  ]#,  0.  ,  0.  ,  0.  ,  0.  ,  0.  , 0.  ,  0.  ]
        , [ 0.  ,  0.  ,  0.  ,  0.  ]#,  0.  ,  0.  ,  .25 , -.25 ,  0.  , 0.  ,  0.  ]
        , [ 0.  ,  0.  ,  0.  ,  0.  ]#,  0.05, -0.05,  0.  ,  0.  ,  0.  , 0.  ,  0.  ]
        , [ 0.  ,  0.  ,  3   , -3   ]#,  0.  ,  0.  ,  0.  ,  0.  ,  0.  , 0.  ,  0.  ]
        , [ 0.  ,  0.  ,  0.  ,  0.  ]#,  0.  ,  0.  ,  0.  ,  0.  ,  1.  , 0.  ,  0.  ]
        , [ 0.  ,  0.  ,  0.  ,  0.  ]#,  0.  ,  0.  ,  0.  ,  0.  ,  0.  , 1.  ,  0.  ]
        , [ 0.  ,  0.  ,  0.  ,  0.  ]#,  0.  ,  0.  ,  0.  ,  0.  ,  0.  , 0.  ,  1.  ]
    ])
    # Look left, look right, look down, look up,
    # Move left, move right, move back, move forward
    INPUT_ACTION_SIZE = 4 
    DEEPMIND_ACTION_DIM = 7
    ACTIONS = namedtuple('ACTIONS'
                         , """ROT_LEFT ROT_RIGHT 
                         MOVE_FORWARD MOVE_BACK""".split())(
                             *range(INPUT_ACTION_SIZE))
    def __init__(self, mm_type):
        assert self.DEEPMIND_ACTION_DIM == self.ACTION_SPACE_INC.shape[0]
        assert self.INPUT_ACTION_SIZE == self.ACTION_SPACE_INC.shape[1]
        self.mm_type = mm_type

    def to_deepmind_action_space(self, action_index, current_velocities):
        """
        >>> am = ActionMapper('acceleration')
        >>> cv = np.zeros(am.DEEPMIND_ACTION_DIM)
        >>> cv = am.to_deepmind_action_space(0, cv)
        >>> np.allclose(cv
        ...             , [25, 0, 0, 0, 0, 0, 0])
        True
        >>> cv = am.to_deepmind_action_space(1, cv)
        >>> np.allclose(cv
        ...             , [0, 0, 0, 0, 0, 0, 0])
        True
        >>> cv = am.to_deepmind_action_space(2, cv)
        >>> np.allclose(cv
        ...             , [0, 0, 0, 0.5, 0, 0, 0])
        True
        >>> cv = am.to_deepmind_action_space(3, cv)
        >>> np.allclose(cv
        ...             , [0, 0, 0, 0.0, 0, 0, 0])
        True
        >>> ad = ActionMapper('discrete')
        >>> np.allclose(ad.to_deepmind_action_space(0, cv)
        ...             , [50, 0, 0, 0, 0, 0, 0])
        True
        >>> np.allclose(ad.to_deepmind_action_space(1, cv)
        ...             , [-50, 0, 0, 0, 0, 0, 0])
        True
        >>> np.allclose(ad.to_deepmind_action_space(2, cv)
        ...             , [0, 0, 0, 1.0, 0, 0, 0])
        True
        >>> np.allclose(ad.to_deepmind_action_space(3, cv)
        ...             , [0, 0, 0, -1.0, 0, 0, 0])
        True
        """
        if action_index >= self.INPUT_ACTION_SIZE:
            raise ValueError("Bad action {}".format(action_index))
        action = np.zeros(self.INPUT_ACTION_SIZE)
        action[action_index] = 1
        velocity_increments = self.ACTION_SPACE_INC.dot(action)
        deepmind_action = np.zeros(self.DEEPMIND_ACTION_DIM)
        if self.mm_type == 'acceleration':
            current_velocities[:4] += velocity_increments[:4] * 0.5
            deepmind_action[:4] = current_velocities[:4]
        elif self.mm_type == 'discrete':
            deepmind_action[:4] = velocity_increments[:4]
        else:
            assert "Bad motion model type {}".format(self.mm_type)

        deepmind_action[4:7] = velocity_increments[4:]
        return deepmind_action

    def initial_deepmind_velocities(self):
        return np.zeros(self.DEEPMIND_ACTION_DIM)

class ActionSpace(gym.Space):
    def __init__(self, action_spec, config, action_mapper):
        self.action_spec = action_spec
        self.frame_width = config['width']
        self.frame_height = config['height']
        self.frame_per_sec = config['fps']

        self.indices = {a['name']: i for i, a in enumerate(self.action_spec)}
        self.mins = np.array([a['min'] for a in self.action_spec])
        self.maxs = np.array([a['max'] for a in self.action_spec])

        self._action_mapper = action_mapper

    def actions(self):
        return self._action_mapper.ACTIONS

    def size(self):
        """ size of action space """
        return self._action_mapper.INPUT_ACTION_SIZE

    @property
    def n(self):
        return self.size()

    def sample(self):
        """
        Uniformly randomly sample a random elemnt of this space
        """
        return np.random.randint(self.size())

    def contains(self, x):
        """
        Return boolean specifying if x is a valid
        member of this space
        """
        return x in range(self.size())

    def to_jsonable(self, sample_n):
        """Convert a batch of samples from this space to a JSONable data type."""
        # By default, assume identity is JSONable
        return sample_n

    def from_jsonable(self, sample_n):
        """Convert a JSONable data type to a batch of samples from this space."""
        # By default, assume identity is JSONable
        return sample_n

    def clip_action(self, action):
        return np.clip(action, self.mins, self.maxs).astype(np.intc)

    def to_deepmind_action_space(self, action_index, current_velocities):
        return self.clip_action(
            self._action_mapper.to_deepmind_action_space(
                action_index, current_velocities))

class ObservationSpace(gym.Space):
    def __init__(self, obs_spec):
        self._obs_spec = obs_spec
        self._img_shape = obs_spec['shape']
        self._img_dtype = obs_spec['dtype']
        self._channel_dim_last = ('RGB_INTERLACED' == obs_spec
                              or 'RGBD_INTERLACED' == obs_spec)

    @property
    def shape(self):
        return self._img_shape

    def sample(self, seed=0):
        """
        Uniformly randomly sample a random elemnt of this space
        """
        return np.random.randint(0, high=np.iinfo(self._img_dtype).max
                                 , size=self._img_shape)
    def make_null(self):
        return np.zeros(self._img_shape, dtype=np.uint8)

    def contains(self, x):
        """
        Return boolean specifying if x is a valid
        member of this space
        """
        return (x.ndim == 3 and x.shape == self._img_shape
                and x.dtype == self._img_dtype)

    def to_jsonable(self, sample_n):
        """Convert a batch of samples from this space to a JSONable data type."""
        # By default, assume identity is JSONable
        return sample_n

    def from_jsonable(self, sample_n):
        """Convert a JSONable data type to a batch of samples from this space."""
        # By default, assume identity is JSONable
        return sample_n

class ChDirCtxt(object):
    """ Temporarily change directory for a bunch of commands and then
    come back to where you were.
    """
    def __init__(self, new_dir):
        self.old_dir = None
        self.new_dir = new_dir
        
    def __enter__(self):
        self.old_dir = os.getcwd()
        os.chdir(self.new_dir)

    def __exit__(self, *args):
        os.chdir(self.old_dir)

class LogMethodCalls(object):
    def __init__(self, obj):
        self._LogMethodCalls_obj = obj

    def __getattr__(self, attr):
        val = getattr(self._LogMethodCalls_obj, attr)
        if callable(val):
            # Define a function that calls the
            # val function within the context
            def wrap(*args, **kwargs):
                logger.debug("Called: {attr}({args}, {kwargs})".format(
                    attr=attr, args=args, kwargs=kwargs))
                return val(*args, **kwargs)
            # Return the wrapped function instead
            return wrap
        else:
            # if the original value was not a callable (function or
            # class or bultin) return it as it is.
            logger.debug("Requested {attr}".format(attr=attr))
            return val

    def __setattr__(self, attr, val):
        logger.debug("Setting {attr} = {val}".format(attr=attr, val=val))
        if attr not in ['_LogMethodCalls_obj']:
            setattr(self._LogMethodCalls_obj, attr, val)
        else:
            object.__setattr__(self, attr, val)


class _DeepmindLab(gym.Env):
    metadata = {'render.modes': ['human', 'file', 'return']}
    RGB_OBS_TYPE = 'RGB_INTERLACED'
    VELT_OBS_TYPE = 'VEL.TRANS'
    VELR_OBS_TYPE = 'VEL.ROT'
    RGBD_OBS_TYPE = 'RGBD_INTERLACED'
    POSE_OBS_TYPE = 'POSE'
    GOAL_OBS_TYPE = 'GOAL.LOC'
    def __init__(self, level_script, config, action_mapper
                 , enable_velocity=False
                 , enable_depth=True
                 , additional_observation_types = []
                 , init_game_seed=0
                 , apple_prob = 0.25
                 , num_maps = 1
                 , rows = 9
                 , cols = 9
                 , mode = "training"
                 , episode_length_seconds=30
                 , worker_id = -1
                 , entitydir="/z/home/shurjo/implicit-mapping/maps"):
        
        # init_game_seed should be random (is messing with experiments)
        init_game_seed = int(1e7*random.random())

        self.observation_types = [self.RGB_OBS_TYPE]
        self.enable_depth = enable_depth
        self.enable_velocity = enable_velocity
        self.level_script = level_script
        self.lab_config = config
        self.action_mapper = action_mapper
        self.additional_observation_types = additional_observation_types

        if self.enable_velocity:
            self.observation_types += [self.VELT_OBS_TYPE
                                       , self.VELR_OBS_TYPE]

        if self.enable_depth:
            self.observation_types.remove(self.RGB_OBS_TYPE)
            self.observation_types.append(self.RGBD_OBS_TYPE)

        self.curr_mod_dir = curr_mod_dir
        self._dl_env = None
        self._action_space = None
        self._obs_space = None
        self._obs_spec = None
        self._current_velocities = action_mapper.initial_deepmind_velocities()
        self._last_obs = None
        self._last_info = {}
        self._step_source = None
        self.img_save_file_template = '/tmp/{user}/{klass}/{level_script}/{index:05d}.png'
        self.init_game_seed = init_game_seed

        # Additional params to be fed in to simulation
        self.apple_prob = apple_prob
        self.num_maps = num_maps
        self.rows = rows
        self.cols = cols
        self.mode = mode
        self.episode_length_seconds = episode_length_seconds
        self.entitydir = entitydir
        self.worker_id = worker_id

    def force_unset_dl_env(self):
        "Assumes you know what you are doing"
        self._dl_env = None

    def environment_name(self):
        return self._dm_lab_env().environment_name()

    def _dm_lab_reset(self):
        init_game_seed = int(1e7*random.random())
        with self._chdir_mod_ctxt:
            self._dm_lab_env().reset(init_game_seed)

    def _dm_lab_step(self, *args, **kwargs):
        with self._chdir_mod_ctxt:
            return self._dm_lab_env().step(*args, **kwargs)

    def _dm_lab_env(self):
        # Delayed initialization of lab env so that one can override
        # various parameters
        if self._dl_env is None:
            # While loading the map the directory should be changed because
            # that's when the maps get loaded.
            with ChDirCtxt(curr_mod_dir):
                input_dict = {k:str(v) for k,v in self.lab_config.items()}

                # More config params
                input_dict['apple_prob'] = str(self.apple_prob)
                input_dict['num_maps'] = str(self.num_maps)
                input_dict['rows'] = str(self.rows)
                input_dict['cols'] = str(self.cols)
                input_dict['mode'] = self.mode
                input_dict['episode_length_seconds'] = str(self.episode_length_seconds)
                input_dict['entitydir'] = self.entitydir
                input_dict['worker_id'] = str(self.worker_id)

                observation_types = self.observation_types \
                                            + self.additional_observation_types
                dlenv = deepmind_lab.Lab(self.level_script
                                         , observation_types
                                         , input_dict)
            # Wraps all the callable methods so that they are called from
            # the current module directory
            self._dl_env = dlenv
            self._chdir_mod_ctxt = ChDirCtxt(curr_mod_dir)
            self._dm_lab_reset()
        return self._dl_env

    def _null_observations(self):
        obs = {}
        for oname in self.observation_types + self.additional_observation_types:
            ospec = self.observation_spec()[oname]
            obs[oname] = (np.zeros(ospec['shape'], ospec['dtype'])
                          if oname != self.RGB_OBS_TYPE
                          else self._obs_space.make_null())
        return obs

    def _next_image_file(self):
        filename = self.img_save_file_template.format(
            user=getpass.getuser()
            , klass=self.__class__.__name__
            , level_script = self.level_script
            , index=self._step_source.get_current_step() % 100000)
        if not os.path.exists(os.path.dirname(filename)):
            os.makedirs(os.path.dirname(filename))
        return filename

    def _configure(self, step_source, *args, **kwargs):
        self._step_source = step_source
        try:
            _ = step_source.get_current_step
        except AttributeError:
            raise ValueError("Need to be able to call model.get_current_step")

    @property
    def action_space(self):
        if self._action_space is None:
            self._action_space = ActionSpace(self._dm_lab_env().action_spec()
                                             , self.lab_config
                                             , self.action_mapper)
        return self._action_space

    def observation_spec(self):
        if self._obs_spec is None:
            self._obs_spec = dict(
                [(o['name'], o) for o in self._dm_lab_env().observation_spec()])
        return self._obs_spec

    @property
    def observation_space(self):
        if self._obs_space is None:
            self._obs_space = ObservationSpace(
                self.observation_spec()[self.RGB_OBS_TYPE])
        return self._obs_space

    @property
    def reward_range(self):
        return [-1, 100]

    def _observations(self):
        if self._dm_lab_env().is_running():
            obs = self._dm_lab_env().observations()
        else:
            obs = self._null_observations()

        if self.enable_depth:
            self._last_obs = obs[self.RGBD_OBS_TYPE][:, :, :3]
            self._last_info['depth'] = obs[self.RGBD_OBS_TYPE][:, :, 3]
        else:
            self._last_obs = obs[self.RGB_OBS_TYPE]

        if self.enable_velocity:
            self._last_info['vel'] = np.hstack((obs[self.VELT_OBS_TYPE]
                                                , obs[self.VELR_OBS_TYPE]))
        for ot in self.additional_observation_types:
            self._last_info[ot] = obs[ot]
        
        # Store current environment name
        self._last_info['env_name'] = self.environment_name()

        assert self._obs_space.contains(self._last_obs), \
            'Observations outside observation space'
        return self._last_obs, self._last_info

    def _step(self, action):
        #FIXME: Bad way 
        if isinstance(action, tuple):
            action, num_steps = action
        else:
            num_steps = 1

        # Input checking
        if not self._action_space.contains(action):
            raise ValueError('Action out of action space')

        # Start of method logic
        deepmind_lab_actions = self._action_space.to_deepmind_action_space(
            action, self._current_velocities)
        self._current_velocities = deepmind_lab_actions
        reward = self._dm_lab_step(deepmind_lab_actions
                                   , num_steps=num_steps)
        episode_over = (not self._dm_lab_env().is_running())
        observations, info = self._observations()

        # output checking
        assert isinstance(reward, numbers.Number), \
            'Reward outside numbers'
        assert isinstance(episode_over, bool), \
            'episode_over is not a bool'
        return observations, reward, episode_over, info

    def _reset(self):
        self._dm_lab_reset()
        # Reset the velocities
        self._current_velocities = \
                            self.action_mapper.initial_deepmind_velocities()
        obs, info = self._observations()

        # Return env name (we often switch between new envs)
        info['env_name'] = self.environment_name()
        return obs, info

    def _render(self, mode='return', close=False):
        if close:
            return

        if self._last_obs is None:
            return
        im = cv2.cvtColor(self._last_obs, cv2.COLOR_RGB2BGR)
        if mode == 'return':
            pass
        elif mode == 'human':
            #cv2.imshow("c",im)
            #cv2.waitKey(1)
            pass
        elif mode == 'file':
            warnings.warn("""mode = file is deprecated. Use mode =
            return and write on your own write to file logic.  You may
            want to use class MatplotlibVisualizer to render or
            print_figure""", warnings.DeprecationWarning)
            imfile = self._next_image_file()
            cv2.imwrite(imfile, im)
        else:
            raise ValueError("bad mode: {}".format(mode))
        return im

    def _seed(self, seed=None):
        if seed is not None:
            np.random.seed(seed)
        self.init_game_seed = seed

class TopViewDeepmindLab(gym.Wrapper):
    def __init__(self, env=None
                 , wall_penalty_scale=0
                 , wall_penalty_max=0
                 , wall_penalty_max_dist=1
                 , method="3D"):

        assert isinstance(env, _DeepmindLab), "Depends on env = _DeepmindLab"
        self.method = method
        self.old_additional_observation_types = \
            copy.copy(env.additional_observation_types)
        needed_obs_types = [env.POSE_OBS_TYPE , env.GOAL_OBS_TYPE]
        env.additional_observation_types += needed_obs_types
        obs_not_supported = False
        try:
            super(TopViewDeepmindLab, self).__init__(env=env)
            self._top_view = TopView(assets_top_dir=env.curr_mod_dir, 
                                     level_script=env.environment_name(),
                                     method=self.method)
        except ValueError, err:
            the_right_kind_exception = any(
                "Unknown observation" in str(err) and obs in str(err)
                for obs in needed_obs_types)
            if not the_right_kind_exception:
                print(" obs {} not in err".format(needed_obs_types))
                raise
            env.additional_observation_types = self.old_additional_observation_types
            # Reinitializing without top-view
            super(TopViewDeepmindLab,  self).__init__(env=env)
            self._top_view = TopView(assets_top_dir=env.curr_mod_dir, 
                                     level_script=env.environment_name(),
                                     method=self.method)
            assert not self._top_view.supported(), 'Entity file and GOAL.LOC both should be available'
            warnings.warn("Top view not supported because"
                          + " observation type '{}'".format(env.GOAL_OBS_TYPE)
                          + " is not supported."
                          + " entity_layer_file not there {}".format(
                              self._top_view._entity_file()))

        self.wall_penalty_max = wall_penalty_max
        self.wall_penalty_max_inv_dist = 1.0
        self.wall_penalty_min_inv_dist = 1.0 / wall_penalty_max_dist

    def _wall_penalty(self, point):
        penalty = 0
        if self.wall_penalty_max:
            dist = self._top_view.distance(point)
            wmax = self.wall_penalty_max
            inv_max = self.wall_penalty_max_inv_dist
            inv_min = self.wall_penalty_min_inv_dist
            inv_dist = max(min(1.0/(dist or 1), inv_max), inv_min)
            penalty = (inv_dist -inv_min) * (wmax - 0) / (inv_max - inv_min) + 0
        return penalty
        
    def _step(self, action):
        obs, reward, done, info = self.env._step(action)
        if self._top_view.supported():
            pose = info[self.env.POSE_OBS_TYPE]
            reward = reward - self._wall_penalty(pose[:2])
            self._top_view.add_pose(pose, reward=reward)
            self._top_view.add_goal(info[self.env.GOAL_OBS_TYPE])
            for obs_type in (self.env.POSE_OBS_TYPE, self.env.GOAL_OBS_TYPE):
                if obs_type not in self.old_additional_observation_types:
                    del info[obs_type]

        return obs, reward, done, info

    def _reset(self):
        obs = self.env._reset()
        self._top_view = TopView(assets_top_dir=self.env.curr_mod_dir, 
                                 level_script=self.env.environment_name(),
                                 method=self.method)
        return obs

    def _render(self, mode='human', close=False):
        if close:
            return
        im = self.env._render(mode=mode, close=close)
        self._top_view.set_entity_layer(self.env.environment_name())
        if not self._top_view.supported():
            warnings.warn("Top view not supported because "
                    + "{0} file not found".format(
                        self._top_view._entity_file()))

        if mode == 'return':
            fig = self._top_view.draw()
        elif mode == 'human':
            fig = self._top_view.draw()
            if fig:
                self._top_view.render(fig)
        elif mode == 'file':
            fig = self._top_view.draw()
            if fig:
                dpi = self.env.lab_config['height'] / fig.get_size_inches()[0]
                self._top_view.print_figure(
                    fig
                    , os.path.join(os.path.dirname(imfile),
                                "top_view_{}".format(os.path.basename(imfile)))
                    , dpi=dpi)
        else:
            raise ValueError("bad mode: {}".format(mode))
        return (im, fig)

    def __getattr__(self, attr):
        return getattr(self.env, attr)

class DeepmindLab(TopViewDeepmindLab):
    def __init__(self, *args, **kwargs):
        P = type(self).mro()[1]
        wrapper_kwargs = {
            k : kwargs.pop(k)
            for k in inspect.getargspec(P.__init__).args[2:]
            if k in kwargs }
        wrapper_kwargs.update(dict(env=_DeepmindLab(*args, **kwargs)))
        P.__init__(self, **wrapper_kwargs)

ActionMapperDiscrete = ActionMapper("discrete")
ActionMapperAcceleration = ActionMapper("acceleration")
L2NActionMapper_v0 = L2NActionMapper(L2NActMapParams_v0.inc_mat
                                     , L2NActMapParams_v0.rel_mask_mat)
ManhattanWorldActionMapper_v0 = L2NActionMapper(ManhattanWorldActMap_v0.inc_mat
                                        , ManhattanWorldActMap_v0.rel_mask_mat)

def register_gym_env(entry_point_name, dl_args, dl_kwargs):
    globals()[entry_point_name] = \
        functools.partial(DeepmindLab
                          , *dl_args, **dl_kwargs)
    env_id = '{}-v1'.format(entry_point_name.replace("_", "-"))
    register(
        id=env_id
        , entry_point='{}:{}'.format(__name__, entry_point_name)
    )
    return env_id

def random_string(N):
    return ''.join(random.choice(string.ascii_uppercase + string.digits) for _ in range(N))

def register_and_make(*args, **kwargs):
    name  = random_string(5)
    entry_point_name = "DeepmindLab" + name
    env_id = register_gym_env(entry_point_name, args, kwargs)
    return gym.make(env_id)

if __name__ == '__main__':
    class A(object):
        def get_current_step(self):
            return 1

    # level_script = "seekavoid_arena_01"
    # env = DeepmindLab(level_script
    #                   , dict(height=336, width=336, fps=60)
    #                   , ActionMapperDiscrete
    #                   , enable_velocity = True
    #                   , enable_depth = False)
    # env.configure(A())
    # for _ in range(100):
    #     obs, reward, done, info = env.step(env.action_space.sample())
    #     im, fig = env.render(mode='human')
    #     assert fig is None
    #     cv2.imwrite("/tmp/{user}_{level_script}_test.png".format(
    #         user=getpass.getuser()
    #         , level_script=level_script)
    #         , im)

    # obs = env.reset()
    level_script = "small_star_map_random_goal_01"
    env = DeepmindLab(level_script
                      , dict(height=336, width=336, fps=60)
                      , ActionMapperDiscrete
                      , enable_velocity = True
                      , enable_depth = False
                      , additional_observation_types = [_DeepmindLab.GOAL_OBS_TYPE])
    env.configure(A())
    
    mplibvis = MatplotlibVisualizer()
    for _ in range(100):
        obs, reward, done, info = env.step(env.action_space.sample())
        im, fig = env.render(mode='human')
        im_filename = "/tmp/{user}_{level_script}_test.png".format(
            user=getpass.getuser()
            , level_script=level_script)
        print("Writing to filename : {}".format(im_filename))
        cv2.imwrite(im_filename , im)
        fig_filename = "/tmp/{user}_{level_script}_top_view_test.png".format(
                                  user=getpass.getuser()
                                  , level_script=level_script)
        print("Writing to filename : {}".format(fig_filename))
        mplibvis.print_figure(fig , fig_filename , dpi=84)
    obs = env.reset()
