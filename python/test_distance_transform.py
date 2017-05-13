import numpy as np
import top_view_renderer as top_view_renderer

import getpass
import os
from os.path import join as pjoin, dirname
currdir = pjoin(dirname(__file__ or '.'))
import unittest

class TestDistanceTransform(unittest.TestCase):
    def setUp(self):
        em = top_view_renderer.EntityMap(
            pjoin(currdir,
                "../assets/game_scripts/small_star_map_random_goal_01.entityLayer"))
        self.distance_transform = dt = top_view_renderer.DistanceTransform()
        wall_coord = list(em.wall_coordinates_from_string())
        dt.set_wall_coordinates(wall_coord)
        self.blocksize = np.asarray((100, 100))
        self.top_view = top_view_renderer.TopView(
            assets_top_dir=pjoin(currdir , "..")
            , level_script="small_star_map_random_goal_01")
        self.top_view.draw()

    def tearDown(self):
        self.distance_transform = None

        filename = "/tmp/{}_top_view_test.png".format(getpass.getuser())
        print("Writing figure to file {}".format(filename))
        fig = self.top_view.draw()
        self.top_view.print_figure(fig , filename , dpi=80)

    def test_distance_transform(self):
        point_dist = [(np.asarray((333, 333)), 46.6690475583)
                      , (np.asarray((233, 333)), 33) 
                      , (np.asarray((131, 332)), 31)
                      , (np.asarray((135, 466)), 34)]
        for i, (point, exp_dist) in enumerate(point_dist):
            dist = self.distance_transform.distance(point, self.blocksize)
            #print ("Distance: {}".format(dist))
            self.assertAlmostEqual(dist, exp_dist
                             , msg='Incorrect distance {} for {}'.format(dist
                                                                     , point))
            self.top_view.get_axes().plot(
                point[0], point[1], '*')


if __name__ == '__main__':
    unittest.main()
