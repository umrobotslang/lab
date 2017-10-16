local tensor = require 'dmlab.system.tensor'
local game = require 'dmlab.system.game'
local helpers = require 'common.helpers'
local MAXAPPLES = 80
local pickup_observations = {}
local obs = {}
local obsSpec = {}

local goal_found_custom_obs = { name = 'GOAL.FOUND', type = 'Bytes', shape = {1} }
local goal_location_custom_obs = { name = 'GOAL.LOC', type = 'Bytes', shape = {2} }
local apple_location_custom_obs = {
   name = 'APPLES.LOC', type = 'Doubles', shape = {MAXAPPLES, 2} }
local pickup_observations = {goal_found_custom_obs, goal_location_custom_obs, apple_location_custom_obs}

function pickup_observations.add_spec(name, type, shape, callback)
  obsSpec[#obsSpec + 1] = {name = name, type = type, shape = shape}
  obs[name] = callback
end


local PickupObs = {}
function PickupObs:new(o)
   o = o or {}
   o.api = o.api or error("Need api")
   o.obs_value = o.obs_value or {}
   setmetatable(o, self)
   self.__index = self
   o:initObs()
   return o
end

function _default_getAppleLocations(api)
   local apple_locations = {}
   local maxapples = api.maxapples or apple_location_custom_obs.shape[1]
   for i = 1,maxapples do
      apple_locations[i] = {0, 0}
   end
   return apple_locations
end

local _DefaultEpisode = {}

function _DefaultEpisode:new(o)
   o = o or {}
   setmetatable(o, self)
   self.__index = self
   return o
end
function _DefaultEpisode:getGoalLocation()
   return {1, 1}
end

function PickupObs:initObs()
   self.obs_value[ goal_found_custom_obs.name ] = tensor.ByteTensor{0}
   getAppleLocations = self.api.getAppleLocations or _default_getAppleLocations
   local apple_locations = getAppleLocations(self.api)
   local v = 0
   self.obs_value[ apple_location_custom_obs.name ] = tensor.DoubleTensor(
      self.api.maxapples or apple_location_custom_obs.shape[1], 2)
   for i, v in ipairs(apple_locations) do
      self.obs_value[ apple_location_custom_obs.name ](i, 1):val(v[1])
      self.obs_value[ apple_location_custom_obs.name ](i, 2):val(v[2])
   end
end

-- Decorate the api with a player translation velocity and angular velocity
-- observation. These observations are relative to the player.
function pickup_observations.decorate(api)
   local init = api.init
   function api:init(params)
     local ret  = init and init(api, params)
    -- Add custom obsevations
     apple_location_custom_obs.shape = { api.maxapples or apple_location_custom_obs.shape[1], 2 }
     for i, v in ipairs(pickup_observations) do
        pickup_observations.add_spec(
           v.name, v.type, v.shape,
           function ()  return api:getobs(v.name) end)
     end
     api.pickupobs = PickupObs:new{ api = api }
     api.episode = api.episode or _DefaultEpisode:new()
     return ret
  end

  function api:getobs(obsname)
     if obsname == goal_location_custom_obs.name then
        local goal_loc = api.episode:getGoalLocation()
        return tensor.ByteTensor{goal_loc[1], goal_loc[2]}
     elseif (obsname == goal_found_custom_obs.name or
                obsname == apple_location_custom_obs.name)
     then
        return api.pickupobs.obs_value[obsname]
     end
  end
 
  local oldApiPickup = api.pickup
  function api:pickup(spawn_id)
    if spawn_id == 2 then
       api.pickupobs.obs_value[ goal_found_custom_obs.name ](1):val(1)
    elseif spawn_id >= 3 then
       spawn_id = tonumber(spawn_id)
       api.pickupobs.obs_value[ apple_location_custom_obs.name ](
          (spawn_id - 2), 1):val(0)
       api.pickupobs.obs_value[ apple_location_custom_obs.name ](
          (spawn_id - 2), 2):val(0)
    end
    return oldApiPickup and oldApiPickup(api, spawn_id)
  end 

  local oldApiNextMap = api.nextMap
  function api:nextMap()
     local mapName = oldApiNextMap(api)
     api.pickupobs = PickupObs:new{ api = api }
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
     return api:getobs(name) or (customObservation and customObservation(api, name))
  end
end

return pickup_observations
