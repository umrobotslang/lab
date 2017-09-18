local game = require 'dmlab.system.game'
local maze_gen = require 'dmlab.system.maze_generation'
local random = require 'common.random'
local pickups = require 'common.pickups'
local helpers = require 'common.helpers'
local custom_observations = require 'decorators.custom_observations'
local timeout = require 'decorators.timeout'
local tensor = require 'dmlab.system.tensor'

local logger = helpers.Logger:new{level = helpers.Logger.NONE}
local factory = {}
local goal_found_custom_obs = { name = 'GOAL.FOUND', type = 'Doubles', shape = {1} }
local goal_location_custom_obs = { name = 'GOAL.LOC', type = 'Doubles', shape = {2} }
local apple_location_custom_obs = { name = 'APPLES.LOC', type = 'Doubles', shape = {50, 2} }

local fruit_locations_list = {}

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

function split(str, pat)
   local t = {}  -- NOTE: use {n = 0} in Lua-5.0
   local fpat = "(.-)" .. pat
   local last_end = 1
   local s, e, cap = str:find(fpat, 1)
   while s do
      if s ~= 1 or cap ~= "" then
         table.insert(t,cap)
      end
      last_end = e+1
      s, e, cap = str:find(fpat, last_end)
   end
   if last_end <= #str then
      cap = str:sub(last_end)
      table.insert(t, cap)
   end
   return t
end

function factory.createLevelApi(kwargs)
  local maze  
  local possibleGoalLocations_all = {}
  local otherGoalLocations_all = {}
  local possibleAppleLocations_all = {}
  local otherAppleLocations_all = {}
  local possibleSpawnLocations_all = {}
  local otherSpawnLocations_all = {}

  for i = 1,kwargs.numMaps do
    possibleGoalLocations_all[i]  = nil
    otherGoalLocations_all[i]     = nil
    possibleAppleLocations_all[i] = nil
    otherAppleLocations_all[i]    = nil
    possibleSpawnLocations_all[i] = nil
    otherSpawnLocations_all[i]    = nil
  end
  
  local height, width
  local possibleGoalLocations, otherGoalLocations   
  local possibleAppleLocations, otherAppleLocations 
  local possibleSpawnLocations, otherSpawnLocations 

  --Flag to help with next map loading
  --Starting at true = start with a random episode (not 000)
  local episode_has_finished_flag = true

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

  -- map name
  -- map names and correspond map strings
  local mapnames
  local mapstrings
  local random_spawn_random_goal

  function api:init(params)
    -- initialize parameters from python
    height = tonumber(params["rows"])
    width = tonumber(params["cols"])
    
    --Random spawn, random goal or fixed spawn, fixed goal
    random_spawn_random_goal = params["random_spawn_random_goal"] == "True"
    
    --Initialize all mapnames nad mapstrings as lists
    mapnames = split(params["mapnames"], ",")
    mapstrings = split(params["mapstrings"], ",")
    
    -- Used to create nextMapNames
	kwargs.scatteredRewardDensity = tonumber(params["apple_prob"])
    kwargs.episodeLengthSeconds = tonumber(params["episode_length_seconds"])
    kwargs.minSpawnGoalDistance = 0
  end

  function api:createPickup(class_name)
    return pickups.defaults[class_name]
  end

  
  function api:start(episode, seed)
    random.seed(seed)
    api._finish_count = 0
  end
 
  function api:pickup(spawn_id)
    if spawn_id == 2 then
        api._goal_found = 1 -- true
        api._obs_value[ goal_found_custom_obs.name ] =
            tensor.DoubleTensor{api._goal_found}
    else
        v = 0
        fruit_locations_list[(tonumber(spawn_id)-2)*2-1] = 0
        fruit_locations_list[(tonumber(spawn_id)-2)*2]  = 0
        api._obs_value[ apple_location_custom_obs.name ] = tensor.DoubleTensor(50, 2):apply(
                function() v = v + 1 return fruit_locations_list[v] end)
    end
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
    -- Goal location unfound to begin with
    api._goal_found = 0 -- false (sending doubles for now) 

    -- Select next mapname
    local nextMapName
    if not episode_has_finished_flag then
        -- reload the same map
        nextMapName = kwargs.mapName 
    else
        -- Reset episode finishing flag
        episode_has_finished_flag = false
        
        -- For new map name, reset possible locations
        local chosenMap
        chosenMap = random.uniformInt(1, #mapnames)
        
        nextMapName = mapnames[chosenMap]
        
        -- Store nextMapName in current mapname for future reloading
        kwargs.mapName = nextMapName
        -- Store array of locations pertaining to specific entityMaps
        if not possibleGoalLocations_all[chosenMap] then
            maze = maze_gen.MazeGeneration{entity = mapstrings[chosenMap]}
            
            if random_spawn_random_goal then
                possibleGoalLocations_all[chosenMap], otherGoalLocations_all[chosenMap] = 
                    helpers.parseAllLocations(maze, intpairkey)
                possibleAppleLocations_all[chosenMap], otherAppleLocations_all[chosenMap] = 
                    helpers.parseAllLocations(maze, intpairkey)
                possibleSpawnLocations_all[chosenMap], otherSpawnLocations_all[chosenMap] = 
                    helpers.parseAllLocations(maze, intpairkey)
            else
                possibleGoalLocations_all[chosenMap], otherGoalLocations_all[chosenMap] = 
                    helpers.parsePossibleGoalLocations(maze, intpairkey)
                possibleAppleLocations_all[chosenMap], otherAppleLocations_all[chosenMap] = 
                    helpers.parsePossibleAppleLocations(maze, intpairkey)
                possibleSpawnLocations_all[chosenMap], otherSpawnLocations_all[chosenMap] = 
                    helpers.parsePossibleSpawnLocations(maze, intpairkey)
            end
        end

        -- Use array to reload spawn and fruit points
        possibleGoalLocations = possibleGoalLocations_all[chosenMap]
        otherGoalLocations = otherGoalLocations_all[chosenMap]
        possibleAppleLocations = possibleAppleLocations_all[chosenMap]
        otherAppleLocations = otherAppleLocations_all[chosenMap]
        possibleSpawnLocations = possibleSpawnLocations_all[chosenMap]
        otherSpawnLocations = otherSpawnLocations_all[chosenMap]
        
        -- Set goal location
        local chosen_goal_index = random.uniformInt(
                                    1, #possibleGoalLocations)
        local goal_location = possibleGoalLocations[chosen_goal_index]
        api._goal = goal_location
    end
    
    --Episode finishing flags
    api._hasEpisodeFinished = false
        
    --Create goal and apple locations
    local goal_location
    local all_spawn_locations = {}
    local fruit_locations = {}
    local fruit_locations_reverse = {}
    
    while true do
        maze:visitFill{cell = api._goal, func = function(row, col, distance)
        logger:debug(string.format("Visiting (%d, %d): %d", row, col, distance))
        -- Axis is flipped in DeepMind Lab.
        local key = text_row_col_to_map_key(row, col, intpairkey)
        local direct_key = string.format("%d %d", row, col)
        
        -- Fill in goal location
        if distance == 0 then
          goal_location = key
        end
        -- Fill in fruit locations
        if distance > 0 and otherAppleLocations[direct_key] then
          fruit_locations[#fruit_locations + 1] = key
        end
        -- Fill in spawn locations
        if distance > 0 and otherSpawnLocations[direct_key] then
          all_spawn_locations[#all_spawn_locations + 1] = key
        end

        logger:debug("Checking key " .. direct_key)
      end}
      helpers.shuffleInPlace(fruit_locations)
      api._goal_location = goal_location
      api._fruit_locations = fruit_locations

      if #all_spawn_locations == 0 then
            local chosen_goal_index = random.uniformInt(
                1, #possibleGoalLocations)
            local goal_location = possibleGoalLocations[chosen_goal_index]
            api._goal = goal_location
            print("FIX ME: GOAL INITIALIZED BADLY")
            print(chosen_goal_index)
            print(goal_location)
      else
            break
      end
    end

    api._all_spawn_locations = all_spawn_locations
    api._newSpawnVars = {}


    -- Chose fruit locations based on input probability
    local maxFruit = math.floor(kwargs.scatteredRewardDensity *
                                #api._fruit_locations + 0.5)
                                
    -- Choose a spawn location
    local spawn_location = api._all_spawn_locations[
                                random.uniformInt(1, #api._all_spawn_locations)]
    
    -- Number of possible apple locations 
    fruit_locations_list = {}
    for i, fruit_location in ipairs(api._fruit_locations) do
      
      --make sure not to include goal location
      if fruit_location ~= spawn_location then
        if i > maxFruit then
          break
        end
        api._newSpawnVars[fruit_location] = {
            classname = 'apple_reward',
            origin = fruit_location .. ' 30',
            id = tostring(i+2)
        }

        -- Not a fan of splitting a string that was formed from numbers
        -- but am doing it right now in the interest of time
        words = {}
        for word in fruit_location:gmatch("%w+") do table.insert(words, word) end
            fruit_locations_list[i*2-1] = tonumber(words[1])
            fruit_locations_list[i*2] = tonumber(words[2])
        end

    end

    logger:debug("Chosen spawn location: " .. spawn_location)
    api._newSpawnVars[spawn_location] = {
        classname = 'info_player_start',
        origin = spawn_location .. ' 30',
        id="1"
    }

    -- Choose a goal location
    logger:debug("Chosen goal location: " .. api._goal_location)
    api._newSpawnVars[api._goal_location] = {
        classname = 'goal',
        origin = api._goal_location .. ' 20',
        id="2"
    }
    
    -- Add custom obsevations
    api._obs_value = {}
    
    -- Add Goal locations
    words = {}
    for word in api._goal_location:gmatch("%w+") do table.insert(words, word) end
    
    api._obs_value[ goal_location_custom_obs.name ] =
        tensor.DoubleTensor{tonumber(words[1]), tonumber(words[2])}
    
    api._obs_value[ goal_found_custom_obs.name ] =
        tensor.DoubleTensor{api._goal_found}

    -- Add chosen apple locations
    v = 0
    api._obs_value[ apple_location_custom_obs.name ] = tensor.DoubleTensor(50, 2):apply(
            function() v = v + 1 return fruit_locations_list[v] end)

    -- Return the chosen mapname
    return nextMapName
  end

  -- Add new obs to the observation specs
  local customObservationSpec = api.customObservationSpec
  function api:customObservationSpec()
    -- This is called before api:init so it should depend on constant things
    local specs = customObservationSpec and customObservationSpec(api) or {}
    -- Add goal location 
    specs[#specs + 1] = goal_location_custom_obs
    -- Add apple locations
    specs[#specs + 1] = apple_location_custom_obs
    -- Add goal found spec
    specs[#specs + 1] = goal_found_custom_obs
    return specs
  end

  -- Return GOAL.LOC/APPLES.LOC value when requested
  local customObservation = api.customObservation
  function api:customObservation(name)
    return api._obs_value[name] or customObservation(api, name)
  end

  custom_observations.decorate(api)
  timeout.decorate(api, kwargs.episodeLengthSeconds)
  
  return api
end

return factory
