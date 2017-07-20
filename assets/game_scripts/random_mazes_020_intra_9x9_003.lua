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
*PAAAA*A*
*A*A*A*A*
*A*A*A*A*
*A*A*A*A*
*A*A*G*A*
*A*A***A*
*AAAAAAA*
*********
]]

local variationsLayer_01 = [[
OOOOLLLTT
OOOOLLLTT
OOOOLLLTT
KOOOLLLTT
KKOOLLLTT
KKKBBBBVV
QQQQAAAVV
QQQQAAAAV
QQQQAAAAA
]]

local entityLayer = entityLayer_01
local variationsLayer = variationsLayer_01

local mapName = 'random_mazes_020_intra_9x9_003'
local numMaps = 20
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
    , blankMapName = 'random_mazes_020_intra_9x9_003_blank_name'
    , entityLayer = entityLayer
    , episodeLengthSeconds = 30 
    , scatteredRewardDensity = 0.50
    , minSpawnGoalDistance = 0
    , numMaps = numMaps
    , mapdir = 'random_mazes_020_intra_9x9'
}