local random = require 'common.random'
local factory = require 'factories.text_random_goal_factory'

-- Requirements for entityLayer while makeMap
-- (Handled by entityLayer:gsub("[GAP ]", "P", 1):gsub("[GAP ]", "A"))
-- 1. Atleast one "P"
-- 2. All probable locations should be have A
--
-- Requirements for entityLayer while using it to generate randomGoals
-- 1. Place G where you want the possible goal locations to be
-- 2. The robot will spawn at some random location at distance > 8 from chosen G
-- 3. Apples will be replace with Apple at scatteredRewardDensity probability
local entityLayer_13 = [[
*******AAAA
*G*G  *AAAA
* *** *AAAA
* *A* *AAAA
* *** *****
*    P    *
***** *** *
AAAA* *A*G*
AAAA* *****
AAAA*    G*
AAAA*******
]]

local variationsLayer_13 = [[
*******FFFF
*C*DEE*FFFF
*C***E*FFFF
*C*F*E*FFFF
*E***E*****
*EEEEEEEEE*
*****E***E*
FFFF*E*F*B*
FFFF*E*****
FFFF*EEAAA*
FFFF*******
]]

local entityLayer = entityLayer_13
local variationsLayer = variationsLayer_13

local mapName = 'star_map_random_goal_13'
local create_new_map = false
if create_new_map then
    local make_map = require 'common.make_map'
    make_map.makeMap(mapName
                     , entityLayer:gsub("[GA ]", "P", 1):gsub("[GA ]", "A")
                     , variationsLayer)
end

return factory.createLevelApi{
    mapName = mapName
    , entityLayer = entityLayer
    , episodeLengthSeconds = 60
    , scatteredRewardDensity = 0.2
}
