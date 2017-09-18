local random = require 'common.random'
local factory = require 'factories.text_random_spawn_factory'
local mapName = 'training-09x09-0001'

local entityLayer_01 = [[
*********
*P*AAG*A*
*AAA***A*
*AAA*AAA*
*AA**A*A*
*A*AAA*A*
*A*****A*
*AAAAAAA*
*********
]]

return factory.createLevelApi{
    mapName = mapName
    , entityLayer = entityLayer_01
    , episodeLengthSeconds = 30 
    , scatteredRewardDensity = 0.25
    , minSpawnGoalDistance = 0
    , numMaps = 1 
}
