local make_map = require 'common.make_map'
local pickups = require 'common.pickups'
local custom_observations = require 'decorators.custom_observations'
local timeout = require 'decorators.timeout'
local api = {}

function api:start(episode, seed)
  make_map.seedRng(seed)
  api._count = 0
  api.mapName = "star_map_small_02"
  -- -- The map has been created and dropped into the assets/maps/ folder
  --   local entityLevel = [[
  --  ******
  --  * A A*
  --  *  * *    
  --  ****A*
  -- ***** *    
  -- * G**A* 
  -- * *** *****
  -- *A A A A  *
  -- ***** *** *
  --     *A**P *
  --     * *****
  --     *A****   
  --     * * G*
  --     *A  A*
  --     ******
  --   ]]
  --   api.mapName = make_map.makeMap(api.mapName, entityLevel)
end

function api:commandLine(oldCommandLine)
  return make_map.commandLine(oldCommandLine)
end

function api:createPickup(className)
  return pickups.defaults[className]
end

function api:nextMap()
   return api.mapName
end

local episodeLengthSeconds = 60
custom_observations.decorate(api)
timeout.decorate(api, episodeLengthSeconds)
return api
