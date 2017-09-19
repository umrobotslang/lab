local game = require 'dmlab.system.game'
local maze_gen = require 'dmlab.system.maze_generation'
local random = require 'common.random'
local pickups = require 'common.pickups'
local helpers = require 'common.helpers'
local custom_observations = require 'decorators.custom_observations'
local pickup_observations = require 'decorators.pickup_observations'
local timeout = require 'decorators.timeout'
local tensor = require 'dmlab.system.tensor'

local logger = helpers.Logger:new{level = helpers.Logger.NONE}
local factory = {}
ENTITY_TYPES = {"G", "A", "P"}


local function intpairkey(r, c)
   return string.format("%d %d", r, c)
end

-----------------------------------------------------------------
-- SubEpisode:
-- A SubEpisode lasts the agents hits a goal or time runs out
-----------------------------------------------------------------

local SubEpisode = {}
function SubEpisode:new(o)
    o = o or {}   -- create object if user does not provide one
    o.api = o.api or error("need api")
    o.maze = o.maze or error("need maze")
    o.episode = o.episode or error("need episode")
    setmetatable(o, self)
    self.__index = self

    -- Initialize SubEpisode
    o._newSpawnVars = o:newSpawnVars()
    return o
end

function SubEpisode:newSpawnVars()
    --Create goal and apple locations
    local api = self.api
    local goal_location = self.episode.goal_location
    local goalr, goalc = unpack(goal_location)
    local goal_location_key = intpairkey(goalr, goalc)
    local all_spawn_locations = self.maze.getOtherLocationsExceptKey("P", goal_location_key)
    local fruit_locations = self.maze.getOtherLocationsExceptKey("A", goal_location_key)

    -- Choose a spawn location
    local spawn_location_index = random.uniformInt(1, #api._all_spawn_locations)
    local spawn_location = all_spawn_locations[spawn_location_index]
    
    -- Chose fruit locations based on input probability
    local maxFruit = math.floor(api.scatteredRewardDensity *
                                   #api._fruit_locations + 0.5)
    
    -- Number of possible apple locations 
    local newSpawnVars = {}
    local spawn_location_key = api:text_row_col_to_map_key(
       spawn_location[1], spawn_location[2])
    for i, fruit_location in ipairs(fruit_locations) do
       --make sure not to include goal location
       local fruit_location_key = api:text_row_col_to_map_key(
             fruit_location[1], fruit_location[2])
       if (fruit_location_key ~= spawn_location_key) then
          if i > maxFruit then
             break
          end
          newSpawnVars[fruit_location_key] = {
             classname = 'apple_reward',
             location = fruit_location, 
             origin = fruit_location_key .. ' 30',
             id = tostring(i+2)
          }
       end

    end

    logger:debug("Chosen spawn location: " .. spawn_location_key)
    newSpawnVars[spawn_location_key] = {
       classname = 'info_player_start',
       location = spawn_location, 
       origin = spawn_location_key .. ' 30',
       id="1"
    }

    -- Choose a goal location
    local goal_location_key = self.api:text_row_col_to_map_key(
       goal_location[1], goal_location[2])
    logger:debug("Chosen goal location: " .. goal_location_key)
    newSpawnVars[goal_location_key] = {
       classname = 'goal',
       location = goal_location, 
       origin = goal_location_key .. ' 20',
       id="2"
    }
    return newSpawnVars
end

function SubEpisode:getSpawnVarByLoc(coords)
   local origin_2D = coords[1] .. " " .. coords[2]
   return self._newSpawnVars[origin_2D]
end

-----------------------------------------------------------------
-- Episode:
-- An episode lasts till the time runs out
-----------------------------------------------------------------
Episode = { SubEpisode = PSubEpisode }
function Episode:new(o)
    o = o or {}   -- create object if user does not provide one
    o.maze = o.maze or error('need maze')
    o.goal_location = o.goal_location or error('need goal location')
    o.api = o.api or error('need api')
    o.subepisode = self.SubEpisode:new{ api = api, maze = maze, episode = o }
    o.time_remaining = api.episodeLengthSeconds
    setmetatable(o, self)
    self.__index = self
    return o
end

function Episode:getMapName()
   return self.maze.mapName
end

function Episode:hasFinished(time_seconds)
   if time_seconds then
      self.time_remaining = (self.api.episodeLengthSeconds - time_seconds)
   end
   return (self.time_remaining <= 0)
end

function Episode:newSubEpisode()
   self.subepisode = self.SubEpisode:new{
      api = api , episode = episode, maze = maze}
end

function Episode:getSpawnVarByLoc()
   return self.subepisode:getSpawnVarByLoc()
end

function Episode:getSpawnVars()
   return self.subepisode._newSpawnVars
end


-----------------------------------------------------------------
-- Maze:
-- A maze is all the information about occupied and unoccupied regions
-- and also the information that comes form parsing entityLayer
-----------------------------------------------------------------
local Maze = {}
function Maze:new(o)
    o = o or {}   -- create object if user does not provide one
    o.mapName = o.mapName or error("Need mapName")
    o.entityLayer = o.entityLayer or error("Need entityLayer")
    o.api = o.api or error("Need api")
    setmetatable(o, self)
    self.__index = self

    -- Initialize maze
    o:parseEntityLayer()
    return o
end

function Maze:parseEntityLayer()
    self.cppmaze = maze_gen.MazeGeneration{entity = self.entityLayer}
    for i, entity in ipairs(ENTITY_TYPES) do
       if self.api.random_spawn_random_goal then
          self.possibleLocations[entity], self.otherLocationsExceptKey[entity] =
             helpers.parseAllLocations(self.cppmaze, intpairkey)
       else
          self.possibleLocations[entity], self.otherLocationsExceptKey[entity] =
             helpers.parsePossibleGoalLocations(self.cppmaze, intpairkey, entity)
       end
    end
    -- self.possibleLocations
    -- Contains a mapping of entity type -> (row,col) where the entity type is allowed to be placed.
    -- self.otherLocationsExceptKey
    -- Contains a mapping of entity type -> 'row col' -> {(row, col)} other location except key.
end

function Maze:sampleEntityLocation(entity)
   local idx = random.uniformInt(1, #self.possibleLocations[entity])
   return self.possibleLocations[entity][idx]
end

function Maze:getOtherLocationsExceptKey(entity, key)
   return self.otherLocationsExceptKey[entity][key] or self.possibleLocations[entity]
end

--[[ Creates a Nav Maze Random Goal.
Keyword arguments:

*   `mapName` (string) - Name of map to load.
*   `entityLayer` (string) - Text representation of the maze.
*   `episodeLengthSeconds` (number, default 600) - Episode length in seconds.
*   `scatteredRewardDensity` (number, default 0.1) - Density of rewards.
]]
function factory.createLevelApi(kwargs)
   kwargs.maxapples = kwargs.maxapples or 50
  
  local api = {Episode = Episode, Maze = Maze}

  function api:text_row_col_to_map_xy(row, col)
      return helpers.text_row_col_to_map_xy(row, col, api.height)
  end
  function api:map_xy_to_text_row_col(x, y)
      return helpers.map_xy_to_text_row_col(x, y, api.height)
  end

  function api:text_row_col_to_map_key(row, col)
    local x, y = api:text_row_col_to_map_xy(row, col)
    local key = x .. ' ' .. y
    return key
  end

  function api:init(params)
    -- initialize parameters from python
    api.height = tonumber(params["rows"])
    api.width = tonumber(params["cols"])
    
    --Random spawn, random goal or fixed spawn, fixed goal
    api.random_spawn_random_goal = params["random_spawn_random_goal"] == "True"
    
    --Initialize all mapnames nad mapstrings as lists
    api.mapnames = helpers.split(params["mapnames"] or error("Need mapnames"), ",")
    api.mapstrings = helpers.split(params["mapstrings"] or error("Need mapstrings"), ",")

    -- We will create a maze object as required
    api.mazes = {}


    -- A sub-class to keep track of variables that have life-time of a sub-episode i.e. period between spawning and hitting a goal
    local mapIdx = helpers.find(kwargs.mapName, api.mapnames)
    if mapIdx < 1 then
       error(string.format("Unable to find %s in \n %s", kwargs.mapName, params.mapnames))
    end
    
    api.episode = api.Episode:new{
       api = api
       , maze = api.getMaze(mapIdx)
       , goal_location = api.getMaze(mapIdx):sampleEntityLocation("G")}
    
    -- Used to create nextMapNames
	api.scatteredRewardDensity = tonumber(params["apple_prob"])
    api.episodeLengthSeconds = tonumber(params["episode_length_seconds"])
    api.minSpawnGoalDistance = 0
  end

  function api:createPickup(class_name)
    return pickups.defaults[class_name]
  end
  
  function api:start(episode, seed)
    random.seed(seed)
  end
 
  function api:hasEpisodeFinished(time_seconds)
     return api.episode.hasFinished(time_seconds)
  end
  
  function api:updateSpawnVars(spawnVars)
    local classname = spawnVars.classname
    if classname == 'apple_reward' or classname == 'goal' 
        or classname == 'info_player_start' then
      local coords = {}
      for x in spawnVars.origin:gmatch("%S+") do
          coords[#coords + 1] = x
      end
      local updated_spawn_vars = api.episode.getSpawnVarByLoc(coords)
      return updated_spawn_vars
    end
	
    return spawnVars
  end

  function api:getMaze(mazeidx)
     mazeidx = mazeidx or random.uniformInt(1, #api.mapnames)
     if not api.mazes[mazeidx] then
        api.mazes[mazeidx] = api.Maze:new{
           mapName = api.mapnames[mazeidx]
           , entityLayer = api.mapstrings[mazeidx]
           , api = api}
     end
     return api.mazes[mazeidx]
  end

  function api:getAppleLocations()
     local apple_locations = {}
     for k, v in pairs(api.episode:getSpawnVars()) do
        if v.apple_reward ~= nil then
           apple_locations[#apple_locations + 1] = v.location
        end
     end
     return apple_locations
  end

  function api:nextMap()
     -- reload the same map
    if api.episode.hasFinished() then
        -- Start a new episode
        api.episode = api.Episode:new{
           api = api
           , goal_location = api.getMaze():sampleEntityLocation("G")
           , maze = api.mazes[chosenMap]}
    else
       api.episode:newSubEpisode()
    end
    
    -- Return the chosen mapname
    return api.episode:getMapName()
  end

  pickup_observations.decorate(api, { maxapples = kwargs.maxapples })
  custom_observations.decorate(api)
  timeout.decorate(api, kwargs.episodeLengthSeconds)
  
  return api
end

return factory
