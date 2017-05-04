local map_maker = require 'dmlab.system.map_maker'

local make_map = {}
make_map.proxy_userdata = newproxy(true)
make_map.proxy_mt = getmetatable(make_map.proxy_userdata)

function make_map.getpid()
  local f = assert(io.open("/proc/self/stat", "r"))
  local pid = f:read("*number")
  return pid
end

--local LEVEL_DATA = string.format('/tmp/dmlab_level_data_%d', make_map.getpid())
local LEVEL_DATA = string.format('/tmp/dmlab_level_data_%d', 0)
make_map.proxy_mt.__gc = function (proxy)
   --local cmd = 'rm -rf ' .. LEVEL_DATA .. '/baselab'
   --print("executing " .. cmd)
   --os.remove(cmd)
end

-- See definitions in pickups.lua
local pickups = {
    A = 'apple_reward',
    L = 'lemon_reward',
    S = 'strawberry_reward',
    F = 'fungi_reward',
    W = 'watermelon_goal',
    G = 'goal',
    M = 'Mango',
}

function make_map.makeMap(mapName, mapEntityLayer, mapVariationsLayer)
  os.execute('mkdir -p ' .. LEVEL_DATA .. '/baselab')
  assert(mapName)
  map_maker:mapFromTextLevel{
      entityLayer = mapEntityLayer,
      variationsLayer = mapVariationsLayer,
      outputDir = LEVEL_DATA .. '/baselab',
      mapName = mapName,
      callback = function(i, j, c, maker)
        if pickups[c] then
          return maker:makeEntity(i, j, pickups[c])
        end
      end
  }
  return mapName
end

function make_map.commandLine(old_command_line)
  return old_command_line .. '+set sv_pure 0 +set fs_steampath ' .. LEVEL_DATA
end

function make_map.seedRng(value)
  map_maker:randomGen():seed(value)
end

return make_map
