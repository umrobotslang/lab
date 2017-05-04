local maze_gen = require 'dmlab.system.maze_generation'
local game = require 'dmlab.system.game'
local random = require 'common.random'
local pickups = require 'common.pickups'
local helpers = require 'common.helpers'
local custom_observations = require 'decorators.custom_observations'
local timeout = require 'decorators.timeout'
local tensor = require 'dmlab.system.tensor'

local logger = helpers.Logger:new{level = helpers.Logger.NONE}
local factory = {}
local goal_location_custom_obs = { name = 'GOAL.LOC', type = 'Doubles', shape = {2} }
local function parsePossibleGoalLocations(maze)
    local height, width = maze:size()
    local possibleGoalLocations = {}
    for r = 1,height do
        for c = 1,width do
            if maze:getEntityCell(r, c) == "G" then
                possibleGoalLocations[#possibleGoalLocations + 1] = {r, c}
                logger:debug(string.format("Found G at (%d, %d)", r, c))
            end
        end
    end
    local goalLocationKeySet = {}
    for i = 1,#possibleGoalLocations do
       local r,c = unpack(possibleGoalLocations[i])
       local rc_key = string.format("%d %d", r, c)
       logger:debug("Inserting key : " .. rc_key)
       goalLocationKeySet[rc_key] = true
    end
    return possibleGoalLocations, goalLocationKeySet
end

--[[ Creates a Nav Maze Random Goal.
Keyword arguments:

*   `mapName` (string) - Name of map to load.
*   `entityLayer` (string) - Text representation of the maze.
*   `episodeLengthSeconds` (number, default 600) - Episode length in seconds.
*   `scatteredRewardDensity` (number, default 0.1) - Density of rewards.
]]

function factory.createLevelApi(kwargs)
  kwargs.scatteredRewardDensity = kwargs.scatteredRewardDensity or 0.1
  kwargs.episodeLengthSeconds = kwargs.episodeLengthSeconds or 600
  kwargs.minSpawnGoalDistance = kwargs.minSpawnGoalDistance or 8
  local maze = maze_gen.MazeGeneration{entity = kwargs.entityLayer}
  local possibleGoalLocations, goalLocationKeySet = parsePossibleGoalLocations(maze)
  local api = {}

  function api:createPickup(class_name)
    return pickups.defaults[class_name]
  end
  
  function api:start(episode, seed, params)
    api._time_remaining = kwargs.episodeLengthSeconds
    random.seed(seed)
    local height, width = maze:size()
    if next(possibleGoalLocations) ~= nil then
        local chosen_goal_index = random.uniformInt(
            1, #possibleGoalLocations)
        local goal_location = possibleGoalLocations[chosen_goal_index]
        api._goal = goal_location
    else
        api._goal = {random.uniformInt(1, height),
                    random.uniformInt(1, width)}
    end
    
    -- Add custom obsevations
    api._obs_value = {}
    api._obs_value[ goal_location_custom_obs.name ] =
        tensor.DoubleTensor{api._goal[1], api._goal[2]}

    local goal_location
    local all_spawn_locations = {}
    local fruit_locations = {}
    local fruit_locations_reverse = {}
    maze:visitFill{cell = api._goal, func = function(row, col, distance)
      logger:debug(string.format("Visiting (%d, %d): %d", row, col, distance))
      -- Axis is flipped in DeepMind Lab.
      local key = ''.. (col * 100 - 50) .. ' ' .. (
         (height - row + 1) * 100 - 50)

      if distance == 0 then
        goal_location = key
      end
      if distance > 0 then
        fruit_locations[#fruit_locations + 1] = key
      end
      local direct_key = string.format("%d %d", row, col)
      logger:debug("Checking key " .. direct_key)
      if distance > kwargs.minSpawnGoalDistance and
         goalLocationKeySet[direct_key]
      then
        logger:debug(
            string.format("possible spawn location :(%d, %d): ", row, col)
                    .. key)
        all_spawn_locations[#all_spawn_locations + 1] = key
      end
    end}
    helpers.shuffleInPlace(fruit_locations)
    api._goal_location = goal_location
    api._fruit_locations = fruit_locations

    if #all_spawn_locations == 0 then
        error("Unable to find any spawn location, consider decreasing minSpawnGoalDistance")
    end
    api._all_spawn_locations = all_spawn_locations
  end

  function api:pickup(spawn_id)
    api._count = api._count + 1
    if api._count == api._finish_count then
      game:finishMap()
    end
  end

  function api:updateSpawnVars(spawnVars)
    local classname = spawnVars.classname
    if classname == 'apple_reward' or classname == 'goal' then
      local coords = {}
      for x in spawnVars.origin:gmatch("%S+") do
          coords[#coords + 1] = x
      end
      local origin_2D = coords[1] .. " " .. coords[2]
      local updated_spawn_vars = api._newSpawnVars[origin_2D]
      return updated_spawn_vars
    elseif classname == 'info_player_start' then
      return api._newSpawnVarsPlayerStart
    end
    return spawnVars
  end

  function api:hasEpisodeFinished(time_seconds)
    api._time_remaining = kwargs.episodeLengthSeconds - time_seconds
    return api._time_remaining <= 0
  end

  function api:nextMap()
    api._newSpawnVars = {}

    local maxFruit = math.floor(kwargs.scatteredRewardDensity *
                                #api._fruit_locations + 0.5)
    for i, fruit_location in ipairs(api._fruit_locations) do
      if i > maxFruit then
        break
      end
      api._newSpawnVars[fruit_location] = {
          classname = 'apple_reward',
          origin = fruit_location .. ' 30'
      }
    end

    local spawn_location = api._all_spawn_locations[
                                random.uniformInt(1, #api._all_spawn_locations)]
    logger:debug("Chosen spawn location: " .. spawn_location)
    api._newSpawnVarsPlayerStart = {
        classname = 'info_player_start',
        origin = spawn_location .. ' 30'
    }

    logger:debug("Chosen goal location: " .. api._goal_location)
    api._newSpawnVars[api._goal_location] = {
        classname = 'goal',
        origin = api._goal_location .. ' 20'
    }

    return kwargs.mapName
  end

  -- Add GOAL.LOC to the observation specs
  local customObservationSpec = api.customObservationSpec
  function api:customObservationSpec()
    -- This is called before api:init so it should depend on constant things
    local specs = customObservationSpec and customObservationSpec(api) or {}
    specs[#specs + 1] = goal_location_custom_obs
    return specs
  end

  -- Return GOAL.LOC value when requested
  local customObservation = api.customObservation
  function api:customObservation(name)
    return api._obs_value[name] or customObservation(api, name)
  end

  custom_observations.decorate(api)
  timeout.decorate(api, kwargs.episodeLengthSeconds)
  return api
end

return factory
