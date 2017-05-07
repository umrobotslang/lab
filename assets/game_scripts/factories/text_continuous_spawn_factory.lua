local maze_gen = require 'dmlab.system.maze_generation'
local game = require 'dmlab.system.game'
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

local function rad2deg(r)
  return r * 180.0 / math.pi
end

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
  kwargs.minSpawnGoalDistance = kwargs.minSpawnGoalDistance or 8
  local maze = maze_gen.MazeGeneration{entity = kwargs.entityLayer}
  local possibleGoalLocations, otherGoalLocations = helpers.parsePossibleGoalLocations(maze, intpairkey)
  local api = {}

  -- Add GOAL.LOC to the observation specs
  local customObservationSpec = api.customObservationSpec
  function api:customObservationSpec()
    -- This is called before api:init so it should depend on constant things
    local specs = customObservationSpec and customObservationSpec(api) or {}
    specs[#specs + 1] = goal_location_custom_obs
    return specs
  end

  function api:createPickup(class_name)
    return pickups.defaults[class_name]
  end

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

  function api:start(episode, seed, params)
    api._time_remaining = kwargs.episodeLengthSeconds
    random.seed(seed)

    local fruit_locations = {}
    local fruit_locations_reverse = {}
    local height, width = maze:size()
    maze:visitFill{cell = possibleGoalLocations[1]
                   , func = function(row, col, distance)
      logger:debug(string.format("Visiting (%d, %d): %d", row, col, distance))

      if distance > 0 and
         not otherGoalLocations[intpairkey(row, col)]
      then
         fruit_locations[#fruit_locations + 1] = text_row_col_to_map_key(row, col)
      end
    end}
    helpers.shuffleInPlace(fruit_locations)
    api._fruit_locations = fruit_locations
    local spawn_row, spawn_col = unpack(
       possibleGoalLocations[random.uniformInt(1, #possibleGoalLocations)])
    local spawn_x, spawn_y = text_row_col_to_map_xy(spawn_row, spawn_col)
    api.last_pose = tensor.DoubleTensor{spawn_x, spawn_y, 0, 0, 0, 0}
    local candidate_goal_locations = otherGoalLocations[
       intpairkey(spawn_row, spawn_col)]
    local goal_loc = candidate_goal_locations[
       random.uniformInt(1, #candidate_goal_locations)]
    api._obs_value = {}
    api._obs_value[ goal_location_custom_obs.name ] = tensor.DoubleTensor{unpack(goal_loc)}
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
    local spawn_row, spawn_col = unpack(
       possibleGoalLocations[random.uniformInt(1, #possibleGoalLocations)])
    local spawn_x, spawn_y = text_row_col_to_map_xy(spawn_row, spawn_col)
    api.last_pose = tensor.DoubleTensor{spawn_x, spawn_y, 0, 0, 0, 0}
    api._time_remaining = kwargs.episodeLengthSeconds - time_seconds
    return api._time_remaining <= 0
  end

  function api:nextMap()
    local x, y = api.last_pose(1):val(), api.last_pose(2):val()
    local spawn_key = x .. ' ' .. y
    logger:debug("spawn_key: " .. spawn_key)
    local spawn_row, spawn_col = map_xy_to_text_row_col(x, y)
    logger:debug("spawn_row: " .. spawn_row .. " spawn_col: " .. spawn_col)
    local candidate_goal_locations = otherGoalLocations[
       intpairkey(spawn_row, spawn_col)]
    local goal_loc = candidate_goal_locations[
       random.uniformInt(1, #candidate_goal_locations)]
    
    -- Add custom obsevations
    api._obs_value[ goal_location_custom_obs.name ] =
       tensor.DoubleTensor{unpack(goal_loc)}
    local goal_key = text_row_col_to_map_key(unpack(goal_loc))

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

    logger:debug("Chosen spawn location: " .. spawn_key)
    api._newSpawnVarsPlayerStart = {
       classname = 'info_player_start'
       , origin = spawn_key .. ' 30'
       , angle = '' .. rad2deg(api.last_pose(5):val())
       , randomAngleRange = '0'
    }

    logger:debug("Chosen goal location: " .. goal_key)
    api._newSpawnVars[goal_key] = {
        classname = 'goal',
        origin = goal_key .. ' 20'
    }

    return kwargs.mapName
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
