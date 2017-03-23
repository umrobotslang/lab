import time
import os

import numpy as np
import deepmind_lab
import gym
from gym.envs.registration import register

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
    ACTION_SPACE_INC = np.array([
        [   2.5 , -2.5 ,  0.  ,  0.  ,  0.  ,  0.  ,  0.  ,  0.  ,  0.  , 0.  ,  0.  ]
        , [ 0.  ,  0.  ,  2.5 , -2.5 ,  0.  ,  0.  ,  0.  ,  0.  ,  0.  , 0.  ,  0.  ]
        , [ 0.  ,  0.  ,  0.  ,  0.  ,  0.01, -0.01,  0.  ,  0.  ,  0.  , 0.  ,  0.  ]
        , [ 0.  ,  0.  ,  0.  ,  0.  ,  0.  ,  0.  ,  0.01, -0.01,  0.  , 0.  ,  0.  ]
        , [ 0.  ,  0.  ,  0.  ,  0.  ,  0.  ,  0.  ,  0.  ,  0.  ,  1.  , 0.  ,  0.  ]
        , [ 0.  ,  0.  ,  0.  ,  0.  ,  0.  ,  0.  ,  0.  ,  0.  ,  0.  , 1.  ,  0.  ]
        , [ 0.  ,  0.  ,  0.  ,  0.  ,  0.  ,  0.  ,  0.  ,  0.  ,  0.  , 0.  ,  1.  ]])
    DEEPMIND_ACTION_DIM = 7
    INPUT_ACTION_SIZE = 11

    def __init__(self, action_spec, config):
        assert self.DEEPMIND_ACTION_DIM == self.ACTION_SPACE_INC.shape[0]
        assert self.INPUT_ACTION_SIZE == self.ACTION_SPACE_INC.shape[1]
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

    def action_space_inc(self):
        act_space_inc = self.ACTION_SPACE_INC.copy()
        act_space_inc[:2, :] *= self.frame_width / self.frame_per_sec
        act_space_inc[2:4, :] *= self.frame_width / self.frame_per_sec
        return act_space_inc

    def size(self):
        """ size of action space """
        return self.INPUT_ACTION_SIZE

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

    def to_deepmind_action_space(self, action_index, current_velocities):
        """
        >>> act_spec = [
        ...    {'max': 512, 'min': -512, 'name': 'LOOK_LEFT_RIGHT_PIXELS_PER_FRAME'},
        ...    {'max': 512, 'min': -512, 'name': 'LOOK_DOWN_UP_PIXELS_PER_FRAME'},
        ...    {'max': 1, 'min': -1, 'name': 'STRAFE_LEFT_RIGHT'},
        ...    {'max': 1, 'min': -1, 'name': 'MOVE_BACK_FORWARD'},
        ...    {'max': 1, 'min': 0, 'name': 'FIRE'},
        ...    {'max': 1, 'min': 0, 'name': 'JUMP'},
        ...    {'max': 1, 'min': 0, 'name': 'CROUCH'}]
        >>> act_space = ActionSpace(act_spec, dict(width=80, height=80, fps=60))
        >>> act_space.to_deepmind_action_space(8, [2, 0, 0, 0])
        array([2, 0, 0, 0, 1, 0, 0], dtype=int32)
        >>> act_space.to_deepmind_action_space(0, [2, 0, 0, 0])
        array([4, 0, 0, 0, 1, 0, 0], dtype=int32)
        """
        action = np.zeros(self.size())
        action[action_index] = 1
        velocity_increments = self.action_space_inc().dot(action)
        current_velocities += velocity_increments[:4]
        deepmind_action = np.zeros(self.DEEPMIND_ACTION_DIM)
        deepmind_action[:4] = current_velocities
        deepmind_action[4:7] = velocity_increments[4:]
        return self.clip_action(deepmind_action)

class ObservationSpace(gym.Space):
    def __init__(self, obs_spec):
        self._obs_spec = obs_spec
        self._img_shape = obs_spec['shape']
        self._img_dtype = obs_spec['dtype']
        self._channel_dim_last = ('RGB_INTERLACED' == obs_spec
                              or 'RGBD_INTERLACED' == obs_spec)

    def sample(self, seed=0):
        """
        Uniformly randomly sample a random elemnt of this space
        """
        return np.random.randint(0, high=np.iinfo(self._img_dtype).max
                                 , size=self._img_shape)

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


class DeepmindLab(gym.Env):
    metadata = {'render.modes': ['human']}
    observation_type = 'RGB_INTERLACED'
    def __init__(self, level_script, config):
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

        self._action_space = ActionSpace(self._dl_env.action_spec(), config)
        self._obs_space = ObservationSpace([
            ospace for ospace in self._dl_env.observation_spec()
            if ospace['name'] == self.observation_type][0])
        self._current_velocities = np.zeros(4) # roll pitch y x

    @property
    def action_space(self):
        return self._action_space

    @property
    def observation_space(self):
        return self._obs_space

    @property
    def reward_range(self):
        return [-1, 1]

    def _step(self, action):
        deepmind_lab_actions = self._action_space.to_deepmind_action_space(
            action , self._current_velocities)
        reward = self._dl_env.step(deepmind_lab_actions , num_steps=1)
        episode_over = (not self._dl_env.is_running())
        self._last_obs = self._dl_env.observations()
        return self._last_obs['RGB_INTERLACED'], reward, episode_over, {}

    def _reset(self):
        self._dl_env.reset()
        self._last_obs = self._dl_env.observations()
        return self._last_obs['RGB_INTERLACED']

    def _render(self, mode='human', close=False):
        if close:
            return

        import cv2
        cv2.imshow("c", self._last_obs['RGB_INTERLACED'])
        cv2.waitKey(1)

    def _seed(self, seed=None):
        if seed is not None:
            np.random.seed(seed)

class DeepmindLabDemoMap(DeepmindLab):
    def __init__(self):
        DeepmindLab.__init__(self, 'tests/demo_map'
                             , dict(width=80, height=80, fps=60))

register(
    id='{}-v0'.format(DeepmindLabDemoMap.__name__),
    entry_point='{}:{}'.format(__name__, DeepmindLabDemoMap.__name__)
)
