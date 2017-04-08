import time
import os
import functools
import numbers
import itertools
import getpass

import numpy as np
import deepmind_lab
import gym
from gym.envs.registration import register
import logging
from collections import namedtuple
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

ActionMapperParams = namedtuple('ActionMapperParams', ['inc_mat', 'rel_mask_mat'])

# Learning to navigate (MiPaViICLR2017) like action mapping 
# Quote
# ```
# The action space is discrete, yet allows finegrained control,
# comprising 8 actions: the agent can rotate in small increments,
# accelerate forward or backward or sideways, or induce rotational
# acceleration while moving
# ```
L2NActionMapper_v0 = ActionMapperParams(
    # Look left, look right, acc left, acc right,
    # acc left, acc right, acc back, acc forward
    inc_mat = np.array([
        [   2.5 , -2.5,  2.5 , -2.5 ,  0.  ,  0.   ,  0.  ,  0.  ]
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

class L2NActionMapper(object):
    """ 
    """
    DEEPMIND_ACTION_DIM = 7
    def __init__(self, inc_mat, rel_mask_mat):
        assert self.DEEPMIND_ACTION_DIM == inc_mat.shape[0]
        assert self.DEEPMIND_ACTION_DIM == rel_mask_mat.shape[0]
        self.input_action_size = inc_mat.shape[1]
        assert self.input_action_size == rel_mask_mat.shape[1]
        self.inc_mat = inc_mat
        self.rel_mask_mat = rel_mask_mat
        self._current_velocities = np.zeros(self.DEEPMIND_ACTION_DIM) # roll pitch y x jump fire

    def to_deepmind_action_space(self, action_index):
        """
        >>> act_space = L2NActionMapper(L2NActionMapper_v0.inc_mat, L2NActionMapper_v0.rel_mask_mat)
        >>> act_space.to_deepmind_action_space(8, [2, 0, 0, 0])
        array([2, 0, 0, 0, 1, 0, 0], dtype=int32)
        >>> act_space.to_deepmind_action_space(0, [2, 0, 0, 0])
        array([4, 0, 0, 0, 1, 0, 0], dtype=int32)
        """
        current_velocities = self._current_velocities
        action = np.zeros(self.INPUT_ACTION_SIZE)
        action[action_index] = 1
        deepmind_action = np.zeros(self.DEEPMIND_ACTION_DIM)
        deepmind_action[:4] = self.inc_mat.dot(action) \
                              + self.rel_mask_mat.dot(action) * current_velocities
        deepmind_action[4:7] = velocity_increments[4:]
        self._current_velocities = deepmind_action
        return deepmind_action


class ActionMapper(object):
    ACTION_SPACE_INC = np.array([
        [   2.5 , -2.5 ,  0.  ,  0.  ]#,  0.  ,  0.  ,  0.  ,  0.  ,  0.  , 0.  ,  0.  ]
        , [ 0.  ,  0.  ,  0.  ,  0.  ]#,  0.  ,  0.  ,  .25 , -.25 ,  0.  , 0.  ,  0.  ]
        , [ 0.  ,  0.  ,  0.  ,  0.  ]#,  0.05, -0.05,  0.  ,  0.  ,  0.  , 0.  ,  0.  ]
        , [ 0.  ,  0.  ,  0.1 , -0.1 ]#,  0.  ,  0.  ,  0.  ,  0.  ,  0.  , 0.  ,  0.  ]
        , [ 0.  ,  0.  ,  0.  ,  0.  ]#,  0.  ,  0.  ,  0.  ,  0.  ,  1.  , 0.  ,  0.  ]
        , [ 0.  ,  0.  ,  0.  ,  0.  ]#,  0.  ,  0.  ,  0.  ,  0.  ,  0.  , 1.  ,  0.  ]
        , [ 0.  ,  0.  ,  0.  ,  0.  ]#,  0.  ,  0.  ,  0.  ,  0.  ,  0.  , 0.  ,  1.  ]
    ])
    # Look left, look right, look down, look up,
    # Move left, move right, move back, move forward
    INPUT_ACTION_SIZE = 4 
    DEEPMIND_ACTION_DIM = 7
    def __init__(self, mm_type):
        assert self.DEEPMIND_ACTION_DIM == self.ACTION_SPACE_INC.shape[0]
        assert self.INPUT_ACTION_SIZE == self.ACTION_SPACE_INC.shape[1]
        self.mm_type = mm_type
        self._current_velocities = np.zeros(4) # roll pitch y x

    def to_deepmind_action_space(self, action_index, scale_inc=1.0):
        """
        >>> act_space = ActionMapper('acceleration')
        >>> act_space.to_deepmind_action_space(8, [2, 0, 0, 0])
        array([2, 0, 0, 0, 1, 0, 0], dtype=int32)
        >>> act_space.to_deepmind_action_space(0, [2, 0, 0, 0])
        array([4, 0, 0, 0, 1, 0, 0], dtype=int32)
        """
        current_velocities = self._current_velocities
        action = np.zeros(self.INPUT_ACTION_SIZE)
        action[action_index] = 1
        velocity_increments = self.ACTION_SPACE_INC.dot(action)
        deepmind_action = np.zeros(self.DEEPMIND_ACTION_DIM)
        if self.mm_type == 'acceleration':
            current_velocities += velocity_increments[:4]
            deepmind_action[:4] = current_velocities
        elif self.mm_type == 'discrete':
            deepmind_action[:4] = velocity_increments[:4] * 10
        else:
            assert "Bad motion model type {}".format(self.mm_type)

        deepmind_action[4:7] = velocity_increments[4:]
        self._current_velocities = deepmind_action[:4]
        return deepmind_action

class ActionSpace(gym.Space):
    ACT_LOOK_YAW   = 'LOOK_LEFT_RIGHT_PIXELS_PER_FRAME'
    ACT_LOOK_PITCH = 'LOOK_DOWN_UP_PIXELS_PER_FRAME'
    ACT_MOVE_Y     = 'STRAFE_LEFT_RIGHT'
    ACT_MOVE_X     = 'MOVE_BACK_FORWARD'
    ACT_FIRE       = 'FIRE'
    ACT_JUMP       = 'JUMP'
    ACT_CROUCH     = 'CROUCH'
    ACTION_SET     = [ACT_LOOK_YAW, ACT_LOOK_PITCH, ACT_MOVE_Y,
                      ACT_MOVE_X, ACT_FIRE, ACT_JUMP, ACT_CROUCH]

    def __init__(self, action_spec, config, action_mapper):
        assert all(a['name'] == act
                   for a, act in zip(action_spec, self.ACTION_SET)), \
                       "Unexpected action spec {}".format(action_spec)

        self.action_spec = action_spec
        self.frame_width = config['width']
        self.frame_height = config['height']
        self.frame_per_sec = config['fps']

        self.indices = {a['name']: i for i, a in enumerate(self.action_spec)}
        self.mins = np.array([a['min'] for a in self.action_spec])
        self.maxs = np.array([a['max'] for a in self.action_spec])
        self.mins[self.indices[self.ACT_LOOK_YAW]] = -8
        self.maxs[self.indices[self.ACT_LOOK_YAW]] = 8

        self._action_mapper = action_mapper

    def size(self):
        """ size of action space """
        return self._action_mapper.INPUT_ACTION_SIZE

    @property
    def n(self):
        return self.size()

    def sample(self, seed=0):
        """
        Uniformly randomly sample a random elemnt of this space
        """
        return np.random.randint(self.size(), seed=seed)

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

    def to_deepmind_action_space(self, action_index):
        return self.clip_action(
            self._action_mapper.to_deepmind_action_space(action_index))

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

class CallMethodsWithCtxt(object):
    """
    Call methods of a given object with a given context
    """
    def __init__(self, obj, ctxt):
        self._call_method_with_ctxt_obj = obj
        self._call_method_with_ctxt_ctxt = ctxt

    def __getattr__(self, attr):
        val = getattr(self._call_method_with_ctxt_obj, attr)
        if callable(val):
            # Define a function that calls the
            # val function within the context
            def wrap(*args, **kwargs):
                with self._call_method_with_ctxt_ctxt:
                    return val(*args, **kwargs)
            # Return the wrapped function instead
            return wrap
        else:
            # if the original value was not a callable (function or
            # class or bultin) return it as it is.
            return val

    def __setattr__(self, attr, val):
        if attr not in ['_call_method_with_ctxt_obj'
                        , '_call_method_with_ctxt_ctxt']:
            setattr(self._call_method_with_ctxt_obj, attr, val)
        else:
            # https://docs.python.org/2/reference/datamodel.html#object.__setattr__
            #
            # If __setattr__() wants to assign to an instance
            # attribute, it should not simply execute self.name =
            # value - this would cause a recursive call to
            # itself. Instead, it should insert the value in the
            # dictionary of instance attributes, e.g.,
            # self.__dict__[name] = value. For new-style classes,
            # rather than accessing the instance dictionary, it should
            # call the base class method with the same name, for
            # example, object.__setattr__(self, name, value).
            object.__setattr__(self, attr, val)

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
    metadata = {'render.modes': ['human']}
    observation_type = 'RGB_INTERLACED'
    def __init__(self, level_script, config, action_mapper):
        self._curr_mod_dir = os.path.dirname(__file__) or '.'
        with ChDirCtxt(self._curr_mod_dir):
            dlenv = deepmind_lab.Lab(level_script
                                            , [self.observation_type]
                                            , {k: str(v)
                                               for k, v in config.items()})
        # Wraps all the callable methods so that they are called from
        # the current module directory
        self._dl_env = CallMethodsWithCtxt(dlenv
                                           , ChDirCtxt(self._curr_mod_dir))
        self._dl_env.reset()

        self._action_space = ActionSpace(self._dl_env.action_spec(), config
                                         , action_mapper)
        self._obs_space = ObservationSpace([
            ospace for ospace in self._dl_env.observation_spec()
            if ospace['name'] == self.observation_type][0])
        self._last_obs = self._obs_space.make_null()
        self._img_save_index = 0

    def _next_image_file(self):
        filename = '/tmp/{user}/{klass}/{index:04d}.png'.format(
            user=getpass.getuser()
            , klass=self.__class__.__name__
            , index=self._img_save_index)
        if self._img_save_index == 0:
            if not os.path.exists(os.path.dirname(filename)):
                os.makedirs(os.path.dirname(filename))
        self._img_save_index += 1
        self._img_save_index = self._img_save_index % 10000
        return filename

    @property
    def action_space(self):
        return self._action_space

    @property
    def observation_space(self):
        return self._obs_space

    @property
    def reward_range(self):
        return [-1, 1]

    def _observations(self):
        if self._dl_env.is_running():
            self._last_obs = self._dl_env.observations()[self.observation_type]
            assert self._obs_space.contains(self._last_obs), \
                'Observations outside observation space'
        else:
            self._last_obs = self._obs_space.make_null()
        return self._last_obs

    def _step(self, action):
        # Input checking
        if not self._action_space.contains(action):
            raise ValueError('Action out of action space')

        # Start of method logic
        deepmind_lab_actions = self._action_space.to_deepmind_action_space(
            action)
        reward = self._dl_env.step(deepmind_lab_actions , num_steps=1)
        episode_over = (not self._dl_env.is_running())
        observations = self._observations()
        
        # output checking
        assert isinstance(reward, numbers.Number), \
            'Reward outside numbers'
        assert isinstance(episode_over, bool), \
            'episode_over is not a bool'
        return observations, reward, episode_over, {}

    def _reset(self):
        self._dl_env.reset()
        return self._observations()

    def _render(self, mode='human', close=False):
        if close:
            return

        import cv2
        if self._last_obs is not None:
            im = cv2.cvtColor(self._last_obs, cv2.COLOR_RGB2BGR)
            cv2.imshow("c",im)
            cv2.imwrite(self._next_image_file(), im)
            cv2.waitKey(1)

    def _seed(self, seed=None):
        if seed is not None:
            np.random.seed(seed)

#class DeepmindLab(LogMethodCalls):
#    def __init__(self, *args, **kwargs):
#        LogMethodCalls.__init__(self, _DeepmindLab(*args, **kwargs))
DeepmindLab = _DeepmindLab

class DeepmindLabDemoMap(DeepmindLab):
    def __init__(self):
        DeepmindLab.__init__(self, 'tests/demo_map'
                             , dict(width=80, height=80, fps=60))
register(
    id='{}-v1'.format(DeepmindLabDemoMap.__name__),
    entry_point='{}:{}'.format(__name__, DeepmindLabDemoMap.__name__)
)

ACT_MAP_LIST = [(mm_type[:1].upper(), ActionMapper(mm_type))
                   for mm_type in ['acceleration', 'discrete']] + \
                       [('L2N', L2NActionMapper(L2NActionMapper_v0.inc_mat
                                                , L2NActionMapper_v0.rel_mask_mat))]
MAP_LEVEL_SCRIPTS = """lt_space_bounce_hard     
                       nav_maze_random_goal_01  random_maze
                       nav_maze_random_goal_02
                       lt_chasm            nav_maze_random_goal_03  stairway_to_melon
                       lt_hallway_slope    nav_maze_static_01       
                       lt_horseshoe_color  nav_maze_static_02 nav_maze_static_03
                       seekavoid_arena_01""".split()

def register_all():
    for level_script, (am_name, act_map) in itertools.product(MAP_LEVEL_SCRIPTS, ACT_MAP_LIST):
        entry_point_name = "DeepmindLab" + am_name + '_' + level_script 
        globals()[entry_point_name] = \
            functools.partial(DeepmindLab
                              , level_script, dict(width=80, height=80, fps=60)
                              , act_map)
        env_id = '{}-v1'.format(entry_point_name.replace("_", "-"))
        print("Registering {}".format(env_id))
        register(
            id=env_id
            , entry_point='{}:{}'.format(__name__, entry_point_name)
        )

register_all()
