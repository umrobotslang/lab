local tensor = require 'dmlab.system.tensor'
local game = require 'dmlab.system.game'
local custom_observations = {}
local obs = {}
local obsSpec = {}

function custom_observations.add_spec(name, type, shape, callback)
  obsSpec[#obsSpec + 1] = {name = name, type = type, shape = shape}
  obs[name] = callback
end

local function deg2rad(d)
  return d / 180.0 * math.pi
end
local function pose()
  local info = game:playerInfo()
  local x = info.pos[1]
  local y = info.pos[2]
  local z = info.pos[3]
  local pitch = deg2rad(info.angles[1])
  local yaw = deg2rad(info.angles[2])
  local roll = deg2rad(info.angles[3])
  return tensor.DoubleTensor{x, y, z, pitch, yaw, roll}
end

local function velocity()
  local info = game:playerInfo()
  local a = info.angles[2] / 180.0 * math.pi
  local s = math.sin(a)
  local c = math.cos(a)
  local velx = info.vel[1] * c + info.vel[2] * s
  local vely = -info.vel[1] * s + info.vel[2] * c
  return tensor.DoubleTensor{velx, vely, info.vel[3]}
end

local function angularVelocity()
  return tensor.DoubleTensor(game:playerInfo().anglesVel)
end

-- Decorate the api with a player translation velocity and angular velocity
-- observation. These observations are relative to the player.
function custom_observations.decorate(api)
  local init = api.init
  function api:init(params)
    custom_observations.add_spec('VEL.TRANS', 'Doubles', {3}, velocity)
    custom_observations.add_spec('VEL.ROT', 'Doubles', {3}, angularVelocity)
    custom_observations.add_spec('POSE', 'Doubles', {6}, pose)
    return init and init(api, params)
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

return custom_observations
