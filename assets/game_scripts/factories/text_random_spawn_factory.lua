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

local open = io.open
-- v. bad practice (hardcoding file basepath)
local mapdirectory = "/z/home/shurjo/implicit-mapping/deepmind-lab/assets/game_scripts/"

local function read_file(path)
    local file = open(path, "rb") -- r read mode and b binary mode
    if not file then return nil end
    local content = file:read "*a" -- *a or *all reads the whole file
    file:close()
    return content
end

local function getEntityLayer(mapname)
  local filename = mapdirectory .. mapname .. ".entityLayer"
  return read_file(filename);
end

function factory.createLevelApi(kwargs)
  kwargs.scatteredRewardDensity = kwargs.scatteredRewardDensity or 0.1
  kwargs.episodeLengthSeconds = kwargs.episodeLengthSeconds or 600
  kwargs.minSpawnGoalDistance = kwargs.minSpawnGoalDistance or 8
  local maze = maze_gen.MazeGeneration{entity = kwargs.entityLayer}
  
  local possibleGoalLocations_all = {}, otherGoalLocations_all = {}
  local possibleAppleLocations_all = {}, otherAppleLocations_all = {}
  for i = 1,kwargs.numMaps do
    possibleGoalLocations_all[i]  = nil
    otherGoalLocations_all[i]     = nil
    possibleAppleLocations_all[i] = nil
    otherAppleLocations_all[i]    = nil
  end
  
  local possibleGoalLocations, otherGoalLocations   
  local possibleAppleLocations, otherAppleLocations 

  --Flag to help with next map loading
  --Starting at true = start with a random episode (not 000)
  local ignore_first_reset = true
  local episode_has_finished_flag = true

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
  end

  function api:hasEpisodeFinished(time_seconds)
    api._time_remaining = kwargs.episodeLengthSeconds - time_seconds
    api._hasEpisodeFinished = api._time_remaining <=0 
    if api._hasEpisodeFinished then
        episode_has_finished_flag = true 
    end
    return api._hasEpisodeFinished
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
     
    -- Select next mapname
    local nextMapName
    if ignore_first_reset or episode_has_finished_flag then
        if ignore_first_reset then
            ignore_first_reset = false
        elseif episode_has_finished_flag then
            episode_has_finished_flag = false
        end
        
        -- For new map name, reset possible locations
        local chosenMap = random.uniformInt(1, kwargs.numMaps)
        nextMapName = string.format('%s_%03d', kwargs.mapdir, chosenMap)
        
        maze = maze_gen.MazeGeneration{entity = getEntityLayer(nextMapName)}
        possibleGoalLocations, otherGoalLocations = 
           helpers.parsePossibleGoalLocations(maze, intpairkey)
        possibleAppleLocations, otherAppleLocations = 
           helpers.parsePossibleAppleLocations(maze, intpairkey)
    
    else
        nextMapName = kwargs.mapName 
    end

    --maze = maze_gen.MazeGeneration{entity = kwargs.entityLayer}
    --possibleGoalLocations, otherGoalLocations = 
    --   helpers.parsePossibleGoalLocations(maze, intpairkey)
    --possibleAppleLocations, otherAppleLocations = 
    --   helpers.parsePossibleAppleLocations(maze, intpairkey)
    
    -- Choose corresponding goal location    
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

    --Episode finishing flags
    api._hasEpisodeFinished = false
    
    -- Add custom obsevations
    api._obs_value = {}
    api._obs_value[ goal_location_custom_obs.name ] =
        tensor.DoubleTensor{api._goal[1], api._goal[2]}

    --Create goal and apple locations
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
      local direct_key = string.format("%d %d", row, col)
      logger:debug("Checking key " .. direct_key)
      if distance > kwargs.minSpawnGoalDistance and
         otherAppleLocations[direct_key] and 
         row > 1 and row < height and
         col > 1 and col < width
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
    api._newSpawnVars = {}


    -- Chose fruit locations based on input probability
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

    -- Choose a spawn location
    local spawn_location = api._all_spawn_locations[
                                random.uniformInt(1, #api._all_spawn_locations)]
    logger:debug("Chosen spawn location: " .. spawn_location)
    api._newSpawnVars[spawn_location] = {
        classname = 'info_player_start',
        origin = spawn_location .. ' 30'
    }

    -- Choose a goal location
    logger:debug("Chosen goal location: " .. api._goal_location)
    api._newSpawnVars[api._goal_location] = {
        classname = 'goal',
        origin = api._goal_location .. ' 20'
    }
    
    -- Return the chosen mapname
    return nextMapName
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
