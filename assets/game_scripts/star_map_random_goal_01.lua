local make_map = require 'common.make_map'
local factory = require 'factories.hinted_random_goal_factory'

local entityLayer = [[
********* 
*  *    *      
* G* G* *      
* ***** ****
*          *
******* ** *
      * *G *
      * *  *
      * ****
      * *G *     
      *    * 
      ******
]]

return factory.createLevelApi{
    --mapName = make_map.makeMap("star_map_random_goal_04", entityLayer),
    mapName = "star_map_random_goal_04",
    entityLayer = entityLayer,
    episodeLengthSeconds = 60
}
