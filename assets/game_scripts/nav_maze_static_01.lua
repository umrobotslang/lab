local factory = require 'factories.random_goal_factory'

local entityLayer = [[
*********************
* *   *             *
* * * * *** *** *****
* * *   *       *   *
* * *****     * * * *
*   *   *     * * * *
* *** * ******* * * *
* *   * * * *     * *
* * *** * * ******* *
*   *     *         *
*********************
]]
return factory.createLevelApi{
    mapName = 'nav_maze_static_01',
    entityLayer = entityLayer,
    episodeLengthSeconds = 60,
    staticGoalLocation = {10, 10}
}
