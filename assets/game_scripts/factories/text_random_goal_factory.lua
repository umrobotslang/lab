local maze_gen = require 'dmlab.system.maze_generation'
local random = require 'common.random'
local pickups = require 'common.pickups'
local helpers = require 'common.helpers'
local custom_observations = require 'decorators.custom_observations'
local timeout = require 'decorators.timeout'
local tensor = require 'dmlab.system.tensor'
local pursuit_test_mode = require 'decorators.pursuit_test_mode'

local logger = helpers.Logger:new{level = helpers.Logger.NONE}
local factory = {}
local goal_location_custom_obs = { name = 'GOAL.LOC', type = 'Doubles', shape = {2} }
local function intpairkey(r, c)
   return string.format("%d %d", r, c)
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
  kwargs.minSpawnGoalDistance = kwargs.minSpawnGoalDistance or 3
  local maze = maze_gen.MazeGeneration{entity = kwargs.entityLayer}
  local possibleGoalLocations, otherGoalLocations = helpers.parsePossibleGoalLocations(maze, intpairkey)
  local possibleAppleLocations, otherAppleLocations = helpers.parsePossibleAppleLocations(maze, intpairkey)

  local height, width = maze:size()
  local function text_row_col_to_map_xy(row, col)
      return helpers.text_row_col_to_map_xy(row, col, height)
  end

  local function map_xy_to_text_row_col(x, y)
      return helpers.map_xy_to_text_row_col(x, y, height)
  end

  local function text_row_col_to_map_key(row, col)
    local x, y = text_row_col_to_map_xy(row, col)
    local key = x .. ' ' .. y
    return key
  end

  local api = {}

  function api:createPickup(class_name)
    return pickups.defaults[class_name]
  end

  function api:start(episode, seed)
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
      local key = text_row_col_to_map_key(row, col, intpairkey)

      if distance == 0 then
        goal_location = key
      end
      if distance > 0 then
        fruit_locations[#fruit_locations + 1] = key
      end
      local direct_key = intpairkey(row, col)
      logger:debug(string.format("Checking key %s distance %f isdistance %s isapple %s", direct_key, distance,tostring(distance > kwargs.minSpawnGoalDistance), tostring(otherAppleLocations[direct_key] ~= nil)))
      if distance > kwargs.minSpawnGoalDistance and
         otherAppleLocations[direct_key]
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

  function api:updateSpawnVars(spawnVars)
    local classname = spawnVars.classname
    -- logger:debug("Got : " .. helpers.dir(spawnVars))
    if classname == 'apple_reward' or classname == 'goal' 
        or classname == 'info_player_start' then
      local coords = {}
      for x in spawnVars.origin:gmatch("%S+") do
          coords[#coords + 1] = x
      end
      local origin_2D = coords[1] .. " " .. coords[2]
      local updated_spawn_vars = api._newSpawnVars[origin_2D]
      -- logger:debug("Updated : " .. helpers.dir(updated_spawn_vars))
      return updated_spawn_vars
    end
    return spawnVars
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
    api._newSpawnVars[spawn_location] = {
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
  pursuit_test_mode.decorate(api,
    { blankMapName = kwargs.blankMapName })
  return api
end

return factory
