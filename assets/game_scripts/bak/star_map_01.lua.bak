local make_map = require 'common.make_map'
local pickups = require 'common.pickups'
local api = {}

function api:start(episode, seed)
  make_map.seedRng(seed)
  api._count = 0
  api.mapName = "star_map_01"
  -- -- The map has been created and dropped into the assets/maps/ folder
  -- local entityLevel = [[
  --      *****
  --      *L  *
  --      *** *
  --  ***   * *    ***
  --  *G*   * *    *P*
  --  * *   * *    * *
  --  * *   * *    * *
  --  * ***** ****** *
  --  *              *
  --  ******* ********
  --        * *
  --        * *
  --        * *
  --      *** *
  --      *A  *
  --      *****
  -- ]]
  -- api._star_map = make_map.makeMap(api.mapName, entityLevel)
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

return api
