local random = require 'common.random'
local factory = require 'factories.text_continuous_spawn_factory'

-- Requirements for entityLayer while makeMap
-- (Handled by entityLayer:gsub("[GAP ]", "P", 1):gsub("[GAP ]", "A"))
-- 1. Atleast one "P"
-- 2. All probable locations should be have A
--
-- Requirements for entityLayer while using it to generate randomGoals
-- 1. Place G where you want the possible goal locations to be
-- 2. The robot will spawn at some random location at distance > 8 from chosen G
-- 3. Apples will be replace with Apple at scatteredRewardDensity probability
local entityLayer_01 = [[
*****AA
**G *AA
*G* ***
*  P  *
*** *G*
AA* G**
AA*****
]]

local variationsLayer_01 = [[
*****AA
**DE*AA
*F*E***
*EEEEE*
***E*C*
AA*EB**
AA*****
]]

local entityLayer = entityLayer_01
local variationsLayer = variationsLayer_01

local mapName = 'small_star_map_random_goal_01'
local create_new_map = false 
if create_new_map then
    local make_map = require 'common.make_map'
    make_map.makeMap(mapName
                     , entityLayer:gsub("[GA ]", "P", 1):gsub("[GA ]", "A")
                     , variationsLayer)
end

return factory.createLevelApi{
    mapName = mapName
    , blankMapName = 'small_blank_map_all_goal_01'
    , entityLayer = entityLayer
    , episodeLengthSeconds = 20
    , scatteredRewardDensity = 1.0 
}
