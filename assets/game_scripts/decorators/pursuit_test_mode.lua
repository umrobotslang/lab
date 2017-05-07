local game = require 'dmlab.system.game'
local tensor = require 'dmlab.system.tensor'

local Pursuit = {}
function Pursuit:new(o)
   assert(o.test_mode ~= nil, "need test_mode")
   assert(o.api ~= nil, "need api")
   assert(o._wrapped_nextMap ~= nil, "need _wrapped_nextMap")
   if o.test_mode then
       assert(o.test_mode.localization_phase_steps
       , "Need localization_phase_steps")
       assert(o.test_mode.blank_map_name , "Need map_name")
   end
   setmetatable(o, self)
   self.__index = self
   o.num_steps = 0
   return o
end

function Pursuit:onNextFrame()
    local map_finished = false
    if self.num_steps == self.test_mode.localization_phase_steps then
        map_finished = true
        game:finishMap()
    end
    self.num_steps = self.num_steps + 1
    if map_finished then
        assert(not self:isLocalizationPhase(), "localization phase should end")
        assert(self:justEndedLocalizationPhase(), "yes we justEndedLocalizationPhase")
    end
end

function Pursuit:justEndedLocalizationPhase()
    return self.num_steps == (self.test_mode.localization_phase_steps + 1)
end

function Pursuit:isLocalizationPhase()
    return self.test_mode and (self.num_steps <= self.test_mode.localization_phase_steps)
end

function Pursuit:nextMap()
    local next_map_val = nil
    if (not self.test_mode) or self:isLocalizationPhase() then
        next_map_val = self._wrapped_nextMap(self.api)
    else
        next_map_val = self.test_mode.blank_map_name
    end
    return next_map_val
end


local function decorate(api, kwargs)
  local empty_func = function (...) end
  local init = api.init or empty_func
  local nextMap = api.nextMap or empty_func
  function api:init(params)
    local test_mode = false
    if params.test_mode then
      test_mode = {}
      test_mode.blank_map_name = kwargs.blankMapName
      assert(test_mode.blank_map_name, "Need blankMapName for test mode")
      test_mode.localization_phase_steps = tonumber(
        params.localization_phase_steps or "10")
      assert(test_mode.localization_phase_steps
          , "Need localizationPhaseSteps for test mode")
    end
    api._pursuit_args = {test_mode = test_mode, api = api, _wrapped_nextMap = nextMap}
    api._pursuit = Pursuit:new(api._pursuit_args)
    api.last_pose = tensor.DoubleTensor{0, 0, 0, 0, 0, 0}
    return init(api, params)
  end


  local hasEpisodeFinished = api.hasEpisodeFinished or empty_func
  function api:hasEpisodeFinished(time_seconds)
      api._pursuit:onNextFrame()
      return hasEpisodeFinished(api, time_seconds)
  end

  local nextMap = api.nextMap or empty_func
  function api:nextMap()
    if api._pursuit.test_mode and api._pursuit:justEndedLocalizationPhase() then
      -- Do not reset pursuit if we just ended localization phase
      api._newSpawnVarsPlayerStart = {
          classname = 'info_player_start'
          , origin = api.last_pose(1):val() .. ' ' .. api.last_pose(2):val() .. ' 30'
          , angle = '' .. api.last_pose(5):val()
          , randomAngleRange = '0'
      }
      -- Retain the old goal location and apple locations
      api._newSpawnVars = api._newSpawnVars
    else
      api._pursuit = Pursuit:new(api._pursuit_args)
    end
    local next_map_val =  api._pursuit:nextMap()
    return next_map_val
  end
end

return { decorate = decorate }
