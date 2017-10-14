local factory = require 'factories.random_goal_factory'

local entityLayer = [[
*******************************
*         *             *     *
* ******* *** * ***** *** *** *
* *           * *   * *     * *
* *********** *** * *** ***** *
*   *           * *     *     *
* * *           * ******* *****
* * *           * *     * *   *
*** *           * *     * *** *
*               * *     *   * *
* ***           * *     ***** *
*   *           * *         * *
* * * *********** ******* * * *
* *   *         * *   *   *   *
* * * * ***** *** * * * *******
* * * * *     *   * * *       *
* * *** * ***** *** * ******* *
* *     *           *         *
*******************************
]]

return factory.createLevelApi{
    mapName = 'nav_maze_static_02',
    entityLayer = entityLayer,
    episodeLengthSeconds = 150,
    staticGoalLocation = {10, 30}
}
