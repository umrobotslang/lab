local map_maker = require 'dmlab.system.map_maker'

local make_map = {}

function make_map.getpid()
  local f = assert(io.open("/proc/self/stat", "r"))
  local pid = f:read("*number")
  return pid
end

local LEVEL_DATA = string.format('/tmp/dmlab_level_data_%d', make_map.getpid())

local pickups = {
    A = 'apple_reward',
    L = 'lemon_reward',
    G = 'goal',
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
