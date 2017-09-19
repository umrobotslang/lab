local tensor = require 'dmlab.system.tensor'
local game = require 'dmlab.system.game'
local pickup_observations = {}
local obs = {}
local obsSpec = {}

local goal_found_custom_obs = { name = 'GOAL.FOUND', type = 'Doubles', shape = {1} }
local goal_location_custom_obs = { name = 'GOAL.LOC', type = 'Doubles', shape = {2} }
local apple_location_custom_obs = { name = 'APPLES.LOC', spawn_id = 1, type = 'Doubles', shape = {50, 2} }
local pickup_observations = {goal_found_custom_obs, goal_location_custom_obs, apple_location_custom_obs}
local class2spawnid = { goal = 2, apple_reward = function (prev) return prev + 1 end }

local SpawnId = {}
function SpawnId:new(o)
   o = o or {}
   o.counter = { info_player_start = 1, goal = 2, apple_reward = 3 }
   setmetatable(o, self)
   self.__index = self
   return o
end

function SpawnId:next(classname)
   local ret = o.counter.classname
   o.counter.classname = o.counter.classname + 1
   return ret
end

function pickup_observations.add_spec(name, type, shape, callback)
  obsSpec[#obsSpec + 1] = {name = name, type = type, shape = shape}
  obs[name] = callback
end


local PickupObs = {}
function PickupObs:new(o)
   o = o or {}
   o.api = o.api or error("Need api")
   o.maxapples = o.maxapples or error("Need maxapples")
   o.obs_value = o.obs_value or {}
   setmetatable(o, self)
   self.__index = self
   return o
end

function PickupObs:initObs()
   self.obs_value[ goal_found_custom_obs.name ] = tensor.DoubleTensor{0}
   local apple_locations = self.api:getAppleLocations()
   local v = 0
   self.obs_value[ apple_location_custom_obs.name ] = tensor.DoubleTensor(
      options.maxapples, 2)
   for i, v in ipairs(apple_locations) do
      self.obs_value[ apple_location_custom_obs.name ](i, 0):val(v[1])
      self.obs_value[ apple_location_custom_obs.name ](i, 1):val(v[2])
   end
end

-- Decorate the api with a player translation velocity and angular velocity
-- observation. These observations are relative to the player.
function pickup_observations.decorate(api, options)
   local init = api.init
   function api:init(params)
    -- Add custom obsevations
     apple_location_custom_obs.shape = { options.maxapples, 2 }
     for i, v in ipairs(pickup_observations) do
        pickup_observations.add_spec(
           v.name, v.type, v.shape,
           function ()  return api:getobs(v.name) end)
     end
     api.pickupobs = PickupObs:new{ api = api, maxapples = options.maxapples }
    return init and init(api, params)
  end

  function api:getobs(obsname)
     if obsname == goal_location_custom_obs.name then
        local goal_loc = api.episode.goal_location
        return tensor.DoubleTensor{goal_loc[1], goal_loc[2]}
     elseif (obsname == goal_found_custom_obs.name or
                obsname == apple_location_custom_obs.name)
     then
        return api.episode.subepiso.obs_value[obsname]
     else
        error(string.format("Unknown observation name : %s", obsname))
     end
  end
 
  local oldApiPickup = api.pickup
  function api:pickup(spawn_id)
    if spawn_id == 2 then
       api.pickupobs.obs_value[ goal_found_custom_obs.name ](1):val(1)
    elseif spawn_id >= 3 then
       spawn_id = tonumber(spawn_id)
       api.pickupobs.obs_value[ apple_location_custom_obs.name ](
          (spawn_id - 3), 0):val(0)
       api.pickupobs.obs_value[ apple_location_custom_obs.name ](
          (spawn_id - 3), 1):val(0)
    end
    oldApiPickup(api, spawn_id)
  end 

  local oldApiNextMap = api.nextMap
  function api:nextMap()
     local mapName = oldApiNextMap(api)
     api.pickupobs = PickupObs:new{ api = api, maxapples = options.maxapples }
     return mapName
  end

  local customObservationSpec = api.customObservationSpec
  function api:customObservationSpec()
    local specs = customObservationSpec and customObservationSpec(api) or {}
    for i, spec in ipairs(obsSpec) do
      specs[#specs + 1] = spec
    end
    return specs
  end

  local customObservation = api.customObservation
  function api:customObservation(name)
    cobs = obs[name] and obs[name]() or customObservation(api, name)
    if name == 'POSE' then
       api.last_pose = cobs
    end
    return cobs
  end
end

return pickup_observations
