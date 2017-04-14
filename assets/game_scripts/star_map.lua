local make_map = require 'common.make_map'
local pickups = require 'common.pickups'
local api = {}

function api:start(episode, seed)
  make_map.seedRng(seed)
  api._count = 0
  map = [[
       *****
       *L  *
       *** *
   ***   * *    ***
   *G*   * *    *P*
   * *   * *    * *
   * *   * *    * *
   * ***** ****** *
   *              *
   ******* ********
         * *
         * *
         * *
       *** *
       *A  *
       *****
  ]]
  api._star_map = make_map.makeMap("star_map", map)
end

function api:commandLine(oldCommandLine)
  return make_map.commandLine(oldCommandLine)
end

function api:createPickup(className)
  return pickups.defaults[className]
end

function api:nextMap()
   return api._star_map
end

return api
