local random = require 'common.random'
local factory = require 'factories.text_random_spawn_factory'

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
*********
*PAAAAAA*
*A**AA*A*
*AAA*A*A*
*AAA*A*A*
*AAAAAAA*
*A*A***A*
*G*AAAAA*
*********
]]

local variationsLayer_01 = [[
CCCSSSSSS
CCCSSSSSO
CCGGSSSOO
IIGGGSOOO
IILLLLBBB
ILLLLLBBB
LLLLLEBBB
LLLLEEEBB
LLLEEEEEB
]]

local entityLayer = entityLayer_01
local variationsLayer = variationsLayer_01

local mapName = 'random_mazes_100_intra_9x9_033'
local numMaps = 100
local chosenMap = random.uniformInt(0, numMaps-1)
local nextMapName = mapName--string.format('random_map_%03d', chosenMap)

local create_new_map = false
if create_new_map then
    local make_map = require 'common.make_map'
    make_map.makeMap(mapName
                     , entityLayer
                     , variationsLayer)
end

return factory.createLevelApi{
    mapName = mapName
    , blankMapName = 'random_mazes_100_intra_9x9_033_blank_name'
    , entityLayer = entityLayer
    , episodeLengthSeconds = 30 
    , scatteredRewardDensity = 0.25
    , minSpawnGoalDistance = 0
    , numMaps = numMaps
    , mapdir = 'random_mazes_100_intra_9x9'
}