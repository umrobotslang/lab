local maze_gen = require 'dmlab.system.maze_generation'
local game = require 'dmlab.system.game'
local random = require 'common.random'
local pickups = require 'common.pickups'
local helpers = require 'common.helpers'
local custom_observations = require 'decorators.custom_observations'
local timeout = require 'decorators.timeout'

local logger = helpers.Logger:new{level = helpers.Logger.NONE}
local factory = {}

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
  local maze = maze_gen.MazeGeneration{entity = kwargs.entityLayer}
  local api = {}

  function api:createPickup(class_name)
    return pickups.defaults[class_name]
  end

  function api:start(episode, seed, params)
    api._time_remaining = kwargs.episodeLengthSeconds
    random.seed(seed + 13)
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

    if next(possibleGoalLocations) ~= nil then
        local chosen_goal_index = random.uniformInt(
            1, #possibleGoalLocations)
        local goal_location = possibleGoalLocations[chosen_goal_index]
        api._goal = goal_location
    else
        api._goal = {random.uniformInt(1, height),
                    random.uniformInt(1, width)}
    end

    local goal_location
    local all_spawn_locations = {}
    local fruit_locations = {}
    local fruit_locations_reverse = {}
    maze:visitFill{cell = api._goal, func = function(row, col, distance)
      -- logger:debug(string.format("Visiting (%d, %d): %d", row, col, distance))
      -- Axis is flipped in DeepMind Lab.
      row = height - row + 1
      local key = ''.. (col * 100 - 50) .. ' ' .. (row * 100 - 50)

      if distance == 0 then
        goal_location = key
      end
      if distance > 0 then
        fruit_locations[#fruit_locations + 1] = key
      end
      if distance > 8 then
          logger:debug(string.format("possible spawn location :(%d, %d): ", row, col)
                    .. key)
        all_spawn_locations[#all_spawn_locations + 1] = key
      end
    end}
    helpers.shuffleInPlace(fruit_locations)
    api._goal_location = goal_location
    api._fruit_locations = fruit_locations
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
    logger:debug("existing: " .. helpers.dir(spawnVars))
    if classname == 'apple_reward' or classname == 'goal' then
      local coords = {}
      for x in spawnVars.origin:gmatch("%S+") do
          coords[#coords + 1] = x
      end
      local origin_2D = coords[1] .. " " .. coords[2]
      local updated_spawn_vars = api._newSpawnVars[origin_2D]
      if not updated_spawn_vars then
        logger:debug("origin: " .. origin_2D .. " not found in table:"
                         .. helpers.dir(api._newSpawnVars))
      end
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

  custom_observations.decorate(api)
  timeout.decorate(api, kwargs.episodeLengthSeconds)
  return api
end

return factory
