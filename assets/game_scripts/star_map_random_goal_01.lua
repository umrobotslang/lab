local factory = require 'factories.random_goal_factory'

local entityLayer = [[
       *****
       *   *
       *** *
   ***   * *    ***
   * *   * *    * *
   * *   * *    * *
   * *   * *    * *
   * ***** ****** *
   *              *
   ******* ********
         * *
         * *
         * *
       *** *
       *   *
       *****
]]

return factory.createLevelApi{
    mapName = 'star_map_random_goal_01',
    entityLayer = entityLayer,
    episodeLengthSeconds = 60
}
