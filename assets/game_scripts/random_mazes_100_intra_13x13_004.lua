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
*************
*PAAAAAA*AAA*
*A*A***A***A*
*A*AAA*AAAAA*
*A*AAA*****A*
*AAAAAAA*AAA*
***A**AA*AAA*
*AAAAA*A*AAA*
*A*AAAAA*****
*AAAAA*A*AAG*
*AA*A*AA*A***
*AAAAA*AAAAA*
*************
]]

local variationsLayer_01 = [[
UUUUGGGGWWWWW
UUUUGGGGWWWWW
UUUUGGGGWWWWW
UUUUGGGGWWWWW
UUUUGGGGWWWWW
UUUUGGGGWWWWW
QUUUGGGGWWWWK
QQQUGGGRRRRKK
QQQQGGGRRRKKK
QQQQQGPPPPKKK
QQQQQQEEEEKKK
QQQQQEEEEEEKK
QQQQQEEEEEEEK
]]

local entityLayer = entityLayer_01
local variationsLayer = variationsLayer_01

local mapName = 'random_mazes_100_intra_13x13_004'
local numMaps = 100
local chosenMap = random.uniformInt(0, numMaps-1)
local nextMapName = mapName--string.format('random_map_%03d', chosenMap)

local create_new_map = true
if create_new_map then
    local make_map = require 'common.make_map'
    make_map.makeMap(mapName
                     , entityLayer
                     , variationsLayer)
end

return factory.createLevelApi{
    mapName = mapName
    , blankMapName = 'random_mazes_100_intra_13x13_004_blank_name'
    , entityLayer = entityLayer
    , episodeLengthSeconds = 0.1 
    , scatteredRewardDensity = 0.25
    , minSpawnGoalDistance = 0
    , numMaps = numMaps
    , mapdir = 'random_mazes_100_intra_13x13'
}