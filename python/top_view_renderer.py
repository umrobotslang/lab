import os
import getpass
import logging

import numpy as np
import matplotlib as mplib
from matplotlib.backends.backend_agg import FigureCanvasAgg
from matplotlib.backends import pylab_setup

class EntityMap(object):
    def __init__(self, entity_layer_file):
        self.entity_layer_file = entity_layer_file
        self._entity_layer_lines = None
        self._width = None
    
    def entity_layer_lines(self):
        if self._entity_layer_lines is None: 
            with open(self.entity_layer_file) as ef:
                self._entity_layer_lines = ef.readlines()
        return self._entity_layer_lines

    def wall_coordinates_from_string(self, size=(100, 100)):
        wall_coords = []
        for row, line in enumerate(self.entity_layer_lines()):
            row_inv = self.height() - row - 1
            for col, char in enumerate(line):
                if char == "*":
                    yield (col * size[0], row_inv * size[1])

    def height(self):
        return len(self.entity_layer_lines())

    def width(self):
        if self._width is None:
            self._width = max(len(l) for l in self.entity_layer_lines()) - 1
        return self._width


class MatplotlibVisualizer(object):
    def __init__(self):
        self._render_fig_manager = None
        self._render_backend_mod = None

    def render(self, fig):
        if self._render_fig_manager is None:
            # Chooses the backend_mod based on matplotlib configuration
            self._render_backend_mod = pylab_setup()[0]
            mplib.interactive(True)
            self._render_fig_manager = \
                self._render_backend_mod.new_figure_manager_given_figure(1, fig)
        self._render_fig_manager.canvas.figure = fig
        self._render_fig_manager.canvas.draw()
        self._render_backend_mod.show(block=False)
        return self._render_fig_manager

    def print_figure(self, fig, filename, dpi):
        FigureCanvasAgg(fig).print_figure(filename, dpi=dpi)

class TopView(object):
    def __init__(self, assets_top_dir=None, level_script=None, draw_fq=20):
        self._ax = None
        self.draw_fq = draw_fq
        self.assets_top_dir = assets_top_dir
        self.level_script = level_script
        self.block_size = np.asarray((100, 100))
        self._entity_map = EntityMap(self._entity_file())
        self._top_view_episode_map = TopViewEpisodeMap(self)
        self._mplib_visualizer = MatplotlibVisualizer()

    def set_entity_layer(self, entity_layer):
        self.level_script = entity_layer

    def render(self, fig):
        self._mplib_visualizer.render(fig)

    def print_figure(self, fig, filename, dpi):
        self._mplib_visualizer.print_figure(fig, filename, dpi)
        
    def supported(self):
        return os.path.exists(self._entity_file())

    def _make_axes(self):
        fig = mplib.figure.Figure(figsize=(4,4))
        # TODO: axes width/height are assumed to be in 1:1 ratio
        # and expected to be handled in by set_aspect later. This is
        # problematic because we depend on matplotlib magic
        ax = fig.gca() if fig.axes else fig.add_axes([0, 0, 1, 1])
        return ax

    def get_axes(self):
        if self._ax is None:
            self._ax = self._make_axes()
        return self._ax

    def _entity_file(self):
        return os.path.join(
            self.assets_top_dir
            , "assets/game_scripts/{}.entityLayer".format(self.level_script))
    
    def add_pose(self, pose):
        if self.supported():
            self._top_view_episode_map.add_pose(pose)

    def add_goal(self, goal_loc):
        if self.supported():
            self._top_view_episode_map.add_goal(goal_loc)

    def draw(self):
        if self.supported():
            self._top_view_episode_map.draw()
            return self.get_axes().figure
    
    def reset(self):
        if self.supported():
            self._top_view_episode_map = TopViewEpisodeMap(self)

class TopViewEpisodeMap(object):
    def __init__(self, top_view):
        self._top_view = top_view
        self._entity_map = top_view._entity_map
        self.poses2D = np.empty((0,3)) # x,y,yaw
        self._goal_loc = None
        self._drawn_once = False

    def add_pose(self, pose):
        self.poses2D = np.vstack((self.poses2D, (pose[0], pose[1], pose[4])))

    def add_goal(self, goal_loc):
        self._goal_loc = goal_loc

    def draw(self):
        if self.poses2D.shape[0] % self.draw_fq == 0:
            self._draw() 

    def map_height(self):
        return self._entity_map.height()

    def map_width(self):
        return self._entity_map.width()
        
    def wall_coordinates_from_string(self, **kwargs):
        return self._entity_map.wall_coordinates_from_string(**kwargs)
    
    @property
    def block_size(self):
        return self._top_view.block_size
    
    def get_axes(self):
        return self._top_view.get_axes()

    def _goal_patch(self, coord):
        goal_size = self.block_size * 0.67
        goal_pos_offset = (self.block_size - goal_size) / 2
        return mplib.patches.Rectangle( coord+goal_pos_offset,
            goal_size[0], goal_size[1] , color='g' , fill=True)
    
    def _draw_goal(self, ax):
        goal_loc = self._goal_loc
        xyblocks = np.asarray((goal_loc[1] - 1, self.map_height() - goal_loc[0]))
        xy = xyblocks * self.block_size
        ax.add_patch(self._goal_patch(xy))
        self._goal_drawn = True
        
    def _wall_patch(self, coord):
        return mplib.patches.Rectangle(
                coord, self.block_size[0], self.block_size[1]
                , fill=True)

    def _draw_map(self, ax):
        for coord in self.wall_coordinates_from_string(size=self.block_size):
            ax.add_patch(self._wall_patch(coord))

    def draw(self):
        self._draw_once()
        self.get_axes().plot(self.poses2D[:, 0], self.poses2D[:, 1], 'b,')
        self.poses2D = self.poses2D[-1:, :]
        
    def _draw_once(self):
        if self._goal_loc is None:
            # Do not draw yet, the goal loc is not avaliable
            return
        if not self._drawn_once:
            ax = self._top_view.get_axes()
            ax.clear()
            # Do not use ax.axis('equal') because it sets adjustable='datalim'
            # which cases xlim/ylim to change later.
            ax.set_aspect('equal', adjustable='box')
            ax.set_autoscale_on(False)
            ax.autoscale_view(tight=True)
            ax.set_xlim(0, self.map_width() * self.block_size[0])
            ax.set_ylim(0, self.map_height() * self.block_size[1])
            self._draw_map(ax)
            self._draw_goal(ax)
            self._drawn_once = True

if __name__ == '__main__':
    # Test top view rendering
    assets_top_dir = os.path.join(
        os.path.dirname(__file__ or "."), "..")
    level_script = "small_star_map_random_goal_01"
    top_view = TopView(assets_top_dir, level_script)
    assert top_view.supported(), "should be supported"
    top_view.reset()
    for _ in range(100):
        pose = np.random.rand(6) * top_view._entity_map.height() * top_view.block_size[1]
        # print("Adding pose {}".format(pose)) 
        top_view.add_pose(pose) 
        goal_loc = [[2, 3],[3, 2], [6, 8], [8,6]][np.random.choice(4)]
        # print("Adding goal at {}".format(goal_loc))
        top_view.add_goal(goal_loc) 
    fig = top_view.draw()
    top_view.render(fig)
    filename = "/tmp/{}_top_view_test.png".format(getpass.getuser())
    print("Writing figure to file {}".format(filename))
    top_view.print_figure(fig , filename , dpi=80)

