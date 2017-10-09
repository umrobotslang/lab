local maze_gen = require 'dmlab.system.maze_generation'
local game = require 'dmlab.system.game'
local random = require 'common.random'
local pickups = require 'common.pickups'
local helpers = require 'common.helpers'
local custom_observations = require 'decorators.custom_observations'
local pickup_observations = require 'decorators.pickup_observations'
local timeout = require 'decorators.timeout'

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
  local api = {}

  function api:init(params)
     api.mapName = kwargs.mapName
     if params.mapstrings ~= nil then
        print("[WARNING]: Ignoring mapstrings")
     end
     api.entityLayer = kwargs.entityLayer
     api.episodeLengthSeconds = tonumber(
        params.episode_length_seconds or tostring(kwargs.episodeLengthSeconds))
     api.scatteredRewardDensity = params.apple_prob or kwargs.scatteredRewardDensity
     api.minSpawnGoalDistance = tonumber(params.minSpawnGoalDistance or "8")
     _ = params.game_seed or error("Need game_seed")
     random.seed(params.game_seed)

     api.maze = maze_gen.MazeGeneration{entity = api.entityLayer}
  end
  
  function api:createPickup(class_name)
    return pickups.defaults[class_name]
  end

  function api:start(episode, seed, params)
    api._time_remaining = api.episodeLengthSeconds
    -- random.seed(seed)
    local height, width = api.maze:size()
    height = (height - 1) / 2
    width = (width - 1) / 2

    api._goal = {random.uniformInt(1, height) * 2,
                 random.uniformInt(1, width) * 2}

    local goal_location
    local all_spawn_locations = {}
    local fruit_locations = {}
    local fruit_locations_reverse = {}
    api.maze:visitFill{cell = api._goal, func = function(
                             textrow, textcol, distance)
      -- Text maze has twice as many columns and rows as the actual maze
      -- The odd rows/cols in text maze are walls while even are free space
      -- The actual maze has no wall thickness so all coordinates is free space.
      if textrow % 2 == 1 or textcol % 2 == 1 then
        return
      end
      local row = textrow / 2 - 1
      local col = textcol / 2 - 1
      -- Axis is flipped in DeepMind Lab.
      row = height - row - 1
      local key = ''.. (col * 100 + 50) .. ' ' .. (row * 100 + 50) .. ' '

      if distance == 0 then
        goal_location = key .. '20'
      end
      if distance > 0 then
        fruit_locations[#fruit_locations + 1] = key .. '20'
      end
      if distance > api.minSpawnGoalDistance then
        all_spawn_locations[#all_spawn_locations + 1] = key .. '30'
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
    if classname == 'apple_reward' then
      return api._newSpawnVars[spawnVars.origin]
    elseif classname == 'info_player_start' then
      return api._newSpawnVarsPlayerStart
    end
    return spawnVars
  end

  function api:hasEpisodeFinished(time_seconds)
    api._time_remaining = api.episodeLengthSeconds - time_seconds
    return api._time_remaining <= 0
  end

  function api:nextMap()
    api._newSpawnVars = {}

    local maxFruit = math.floor(api.scatteredRewardDensity *
                                #api._fruit_locations + 0.5)

    for i, fruit_location in ipairs(api._fruit_locations) do
      if i > maxFruit then
        break
      end
      api._newSpawnVars[fruit_location] = {
          classname = 'apple_reward',
          origin = fruit_location
      }
    end

    local spawn_location = api._all_spawn_locations[
                                random.uniformInt(1, #api._all_spawn_locations)]
    api._newSpawnVarsPlayerStart = {
        classname = 'info_player_start',
        origin = spawn_location
    }

    api._newSpawnVars[api._goal_location] = {
        classname = 'goal',
        origin = api._goal_location
    }

    local mapName = api.mapName
    return mapName
  end

  pickup_observations.decorate(api)
  custom_observations.decorate(api)
  timeout.decorate(api, api.episodeLengthSeconds)
  return api
end

return factory
