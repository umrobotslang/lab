local maze_gen = require 'dmlab.system.maze_generation'
local game = require 'dmlab.system.game'
local random = require 'common.random'
local pickups = require 'common.pickups'
local helpers = require 'common.helpers'
local custom_observations = require 'decorators.custom_observations'
local timeout = require 'decorators.timeout'

local Logger = {}
function Logger:new(o)
   o = o or {}
   setmetatable(o, self)
   self.__index = self
   return o
end
function Logger:debug(msg)
   if self._debug then
      print(msg)
   end
end
local logger = Logger:new{_debug = true}

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
    random.seed(seed)
    local height, width = maze:size()
    -- don't know why (may because odd is wall, even is free space)
    height = (height - 1) / 2 
    width = (width - 1) / 2

    local possible_goal_locations = {}
    local chosen_goal_idx = 1
    local rooms = maze:findRooms('*')
    for i = 1, #rooms do
       rooms[i]:visit(
          function (r, c)
             local ecell = maze:getEntityCell(r, c)
             logger:debug("r:" .. r .. "; c:" .. c .. "; ecell:" .. ecell)
             if ecell == 'G' then
                --maze:setEntityCell(r, c, ' ')
                possible_goal_locations[#possible_goal_locations + 1] = {r,c}
             end
          end)
    end
    if #possible_goal_locations >= 1 then
        assert(#possible_goal_locations >= 1, "Need at least one G in the rooms")
        logger:debug("possible goal locations are "
                 .. tostring(#possible_goal_locations))
        chosen_goal_idx = random.uniformInt(1, #possible_goal_locations)
        logger:debug("Chosen goal index is " .. tostring(chosen_goal_idx))
        api._goal = possible_goal_locations[chosen_goal_idx]
        logger:debug("Chosen goal is " .. helpers.dir(api._goal))
    else
       assert(false, "Provide atleast one goal")
        api._goal = {random.uniformInt(1, height) * 2,
                     random.uniformInt(1, width) * 2}
    end

    local goal_location
    local all_spawn_locations = {}
    local fruit_locations = {}
    local fruit_locations_reverse = {}
    maze:visitFill{cell = api._goal, func = function(row, col, distance)
      logger:debug("row:" .. row .. "; col:" .. col .. "; dist:" .. distance)
      if row % 2 == 1 or col % 2 == 1 then
        return
      end
      row = row / 2 - 1
      col = col / 2 - 1
      -- Axis is flipped in DeepMind Lab.
      row = height - row - 1
      local key = ''.. (col * 100 + 50) .. ' ' .. (row * 100 + 50) .. ' '

      if distance <= 2 then
        goal_location = key .. '20'
      end
      if distance > 0 then
        fruit_locations[#fruit_locations + 1] = key .. '20'
      end
      if distance > 8 then
        all_spawn_locations[#all_spawn_locations + 1] = key .. '30'
      end
    end}
    helpers.shuffleInPlace(fruit_locations)
    api._goal_location = goal_location
    api._fruit_locations = fruit_locations
    if #all_spawn_locations > 0 then
       api._all_spawn_locations = all_spawn_locations
    else
       table.remove(possible_goal_locations, chosen_goal_idx)
       api._all_spawn_locations = possible_goal_locations
    end
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

    return kwargs.mapName
  end

  custom_observations.decorate(api)
  timeout.decorate(api, kwargs.episodeLengthSeconds)
  return api
end

return factory
