local make_map = require 'common.make_map'
local pickups = require 'common.pickups'
local timeout = require 'decorators.timeout'
local tensor = require 'dmlab.system.tensor'
local custom_observations = require 'decorators.custom_observations'
local api = {}
local goal_location_custom_obs = { name = 'GOAL.LOC', type = 'Doubles', shape = {2} }

function api:start(episode, seed)
  make_map.seedRng(seed)
  api._count = 0
  api.mapName = "i_maze_fungi"
  -- The map has been created and dropped into the assets/maps/ folder
  local entityLevel = [[
*********
**G   F**
**** ****
**** ****
**** ****
**** ****
**** ****
**P   S**
*********
]]
--api._star_map = make_map.makeMap(api.mapName, entityLevel)
end

function api:commandLine(oldCommandLine)
  return make_map.commandLine(oldCommandLine)
end

function api:createPickup(className)
  local p = pickups.defaults[className]
  if (api.mapName == "i_maze_fungi") then
      if (className == "fungi_reward") then
          p.quantity = 10
      elseif (className == "goal") then
          p.quantity = -10
      end
  else
      if (className == "fungi_reward") then
          p.quantity = -10
      elseif (className == "goal") then
          p.quantity = 10
      end
  end
  return p
end

function api:nextMap()
    if (api.mapName == "i_maze_goal") then
        api.mapName = "i_maze_fungi"
    else
        api.mapName = "i_maze_goal"
    end
    return api.mapName
end

-- Add GOAL.LOC to the observation specs
local customObservationSpec = api.customObservationSpec
function api:customObservationSpec()
    -- This is called before api:init so it should depend on constant things
    local specs = customObservationSpec and customObservationSpec(api) or {}
    specs[#specs + 1] = goal_location_custom_obs
    return specs
end

api._obs_value = {}
if (api.mapName == "i_maze_goal") then
    api._obs_value[goal_location_custom_obs.name] = tensor.DoubleTensor{2, 3}
else
    api._obs_value[goal_location_custom_obs.name] = tensor.DoubleTensor{2, 7}
end
local customObservation = api.customObservation
function api:customObservation(name)
    return api._obs_value[name] or customObservation(api, name)
end

timeout.decorate(api, 20)
custom_observations.decorate(api)

return api
