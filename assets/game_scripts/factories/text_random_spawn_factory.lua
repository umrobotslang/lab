local game = require 'dmlab.system.game'
local maze_gen = require 'dmlab.system.maze_generation'
local random = require 'common.random'
local pickups = require 'common.pickups'
local helpers = require 'common.helpers'
local make_map = require 'common.make_map'
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
    local goal_location = self:getGoalLocation()
    local fruit_locations = self.maze:getOtherLocationsExceptKey("A", goal_location_key)

    -- Choose a spawn location
    local spawn_location = self:getSpawnLocation()
    
    -- Chose fruit locations based on input probability
    local maxFruit = math.floor(api.scatteredRewardDensity *
                                   #fruit_locations + 0.5)
    
    -- Number of possible apple locations 
    local newSpawnVars = {}
    local spawn_location_key = api:text_row_col_to_map_key(
       spawn_location[1], spawn_location[2])
    helpers.shuffleInPlace(fruit_locations)
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
             origin = fruit_location_key .. ' 30',
             id = tostring(i+2)
          }
       end

    end

    logger:debug("Chosen spawn location: " .. spawn_location_key)
    newSpawnVars[spawn_location_key] = {
       classname = 'info_player_start',
       origin = spawn_location_key .. ' 30',
       id="1"
    }

    -- Choose a goal location
    local goal_location_key = self.api:text_row_col_to_map_key(
       goal_location[1], goal_location[2])
    logger:debug("Chosen goal location: " .. goal_location_key)
    newSpawnVars[goal_location_key] = {
       classname = 'goal',
       origin = goal_location_key .. ' 20',
       id="2"
    }

    return newSpawnVars
end

function SubEpisode:getSpawnVarByLoc(coords)
   local origin_2D = coords[1] .. " " .. coords[2]
   return self._newSpawnVars[origin_2D]
end

function SubEpisode:getGoalLocation()
   return self.api.compute_goal_location(self) or error("Need some goal location")
end

function SubEpisode:getSpawnLocation()
   return self.api.compute_spawn_location(self)
end


-----------------------------------------------------------------
-- Episode:
-- An episode lasts till the time runs out
-----------------------------------------------------------------
Episode = { SubEpisode = SubEpisode }
function Episode:new(o)
    o = o or {}   -- create object if user does not provide one
    o.maze = o.maze or error('need maze')
    o.api = o.api or error('need api')
    o.subepisode = self.SubEpisode:new{ api = o.api, maze = o.maze, episode = o }
    o.time_remaining = o.api.episodeLengthSeconds
    setmetatable(o, self)
    self.__index = self
    return o
end

function Episode:getGoalLocation()
   return self.subepisode:getGoalLocation()
end

function Episode:getSpawnLocation()
   return self.subepisode:getSpawnLocation()
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
      api = self.api , episode = self, maze = self.maze}
end

function Episode:getSpawnVarByLoc(coords)
   return self.subepisode:getSpawnVarByLoc(coords)
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
    -- Contains a mapping of entity type -> (row,col) where the entity type is allowed to be placed.
    self.possibleLocations = {}
    -- Contains a mapping of entity type -> 'row col' -> {(row, col)} other location except key.
    self.otherLocationsExceptKey = {}
    for i, entity in ipairs(ENTITY_TYPES) do
       if self.api.all_entities_swappable then
          self.possibleLocations[entity], self.otherLocationsExceptKey[entity] =
             helpers.parseAllLocations(self.cppmaze, intpairkey)
       else
          self.possibleLocations[entity], self.otherLocationsExceptKey[entity] =
             helpers.parsePossibleGoalLocations(self.cppmaze, intpairkey, entity)
       end
    end
end

function Maze:sampleEntityLocation(entity)
   local idx = random.uniformInt(1, #self.possibleLocations[entity])
   return self.possibleLocations[entity][idx]
end

function Maze:getOtherLocationsExceptKey(entity, key)
   return self.otherLocationsExceptKey[entity][key] or self.possibleLocations[entity]
end

local ComputeGoalLocation = {}
function ComputeGoalLocation.random_per_episode(subepisode)
   if subepisode.episode.goal_location == nil then
        subepisode.episode.goal_location = subepisode.maze:sampleEntityLocation("G")
   end
   return subepisode.episode.goal_location
end

function ComputeGoalLocation.fixedindex(subepisode)
   if subepisode.episode.goal_location == nil then
      local possibleGoalLocations = subepisode.maze.possibleLocations["G"]
      local idx = 1 + (tonumber(subepisode.api.compute_goal_location_args) % #possibleGoalLocations )
      subepisode.episode.goal_location = possibleGoalLocations[idx] or error("Need some goal location")
   end
   return subepisode.episode.goal_location or error("Need some goal location")
end


function ComputeGoalLocation.fixed(subepisode)
   if subepisode.goal_location == nil then
      local goal_loc = {}
      for i, v in ipairs(helpers.split(api.compute_goal_location_args, ",")) do
         goal_loc[i] = tonumber(v)
      end
      subepisode.goal_location = {goal_loc[1], goal_loc[2]}
   end
   return subepisode.goal_location
end


local ComputeSpawnLocation = {}
function ComputeSpawnLocation.random_per_subepisode(subepisode)
   if subepisode.spawn_location == nil then
      subepisode.episode.spawn_location = nil
      local goal_location = subepisode:getGoalLocation()
      local goal_location_key = intpairkey(unpack(goal_location))
      local all_spawn_locations = subepisode.maze:getOtherLocationsExceptKey("P", goal_location_key)
      local spawn_location_index = random.uniformInt(1, #all_spawn_locations)
      subepisode.spawn_location = all_spawn_locations[spawn_location_index]
   end
   return subepisode.spawn_location
end

function ComputeSpawnLocation.fixed(subepisode)
   if subepisode.spawn_location == nil then
      local spawn_loc = {}
      for i, v in ipairs(helpers.split(api.compute_spawn_location_args, ",")) do
         spawn_loc[i] = tonumber(v)
      end
      subepisode.spawn_location = {spawn_loc[1], spawn_loc[2]}
   end
   return subepisode.spawn_location
end


--[[ Creates a Nav Maze Random Goal.
Keyword arguments:

*   `mapName` (string) - Name of map to load.
*   `entityLayer` (string) - Text representation of the maze.
*   `episodeLengthSeconds` (number, default 600) - Episode length in seconds.
*   `scatteredRewardDensity` (number, default 0.1) - Density of rewards.
]]
function factory.createLevelApi(kwargs)
  
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
    api.maxapples = params.maxapples or 50
    _ = params.game_seed or error("Need game_seed")
    random.seed(params.game_seed)
    
    --Random spawn, random goal or fixed spawn, fixed goal
    api.all_entities_swappable = params.random_spawn_random_goal ~= "False"
    api.make_map = (params.make_map == "True")
    
    --Initialize all mapnames nad mapstrings as lists
    api.mapnames = helpers.split(
       params.mapnames or error("Need mapnames") , ",")
    api.mapstrings = helpers.split(
       params.mapstrings or error("Need mapstrings") , ",")
    
    if params.variationsLayers then
       api.variationsLayers = helpers.split(params.variationsLayers, ",")
    end

    -- More parameters
	api.scatteredRewardDensity = tonumber(params["apple_prob"] or "0.25")
    api.episodeLengthSeconds = tonumber(params["episode_length_seconds"] or "20")
    api.minSpawnGoalDistance = tonumber(params.minSpawnGoalDistance or "0")

    -- How to compute the goal location
    local compute_goal_location, cgl_args = unpack(
       helpers.split(
          params.compute_goal_location or "random_per_episode", ":"))
    api.compute_goal_location = ComputeGoalLocation[compute_goal_location] or
       error("Bad compute_goal_location " .. compute_goal_location)
    api.compute_goal_location_args = cgl_args

    -- How to compute the spawn location
    local compute_spawn_location, csl_args = unpack(
       helpers.split(
          params.compute_spawn_location or "random_per_subepisode", ":"))
    api.compute_spawn_location = ComputeSpawnLocation[compute_spawn_location] or
       error("Bad compute_spawn_location " .. compute_spawn_location)
    api.compute_spawn_location_args = csl_args

    -- Compute the height and width of the first map
    local mapstring1 = api.mapstrings[1] or error("Need atleast one mapstring")
    local maplines = helpers.split(mapstring1, "\n")
    api.height = #maplines
    api.width = maplines[1]:len()
    

    local maze = api:getMaze()
    api.episode = api.Episode:new{
       api = api
       , maze = maze }
  end

  function api:createPickup(class_name)
    return pickups.defaults[class_name]
  end
  
  function api:start(episode, seed)
      --print("seed :" .. seed)
      -- random.seed()
  end
 
  function api:hasEpisodeFinished(time_seconds)
     return api.episode:hasFinished(time_seconds)
  end
  
  function api:updateSpawnVars(spawnVars)
    local classname = spawnVars.classname
    if classname == 'apple_reward' or classname == 'goal' 
        or classname == 'info_player_start' then
      local coords = {}
      for x in spawnVars.origin:gmatch("%S+") do
          coords[#coords + 1] = x
      end
      local updated_spawn_vars = api.episode:getSpawnVarByLoc(coords)
      return updated_spawn_vars
    end
	
    return spawnVars
  end

  function api:getMaze(mazeidx)
     mazeidx = mazeidx or random.uniformInt(1, #api.mapnames)
     api.mazes = api.mazes or {}
     if api.mazes[mazeidx] == nil then
        if api.make_map then
           mapName = api.mapnames[mazeidx]
           entityLayer = api.mapstrings[mazeidx]
           variationsLayer = api.variationsLayers[mazeidx]
           local made = make_map.makeMap(mapName, entityLayer, variationsLayer)
           print("made map : " .. made)
        end
        api.mazes[mazeidx] = api.Maze:new{
           mapName = api.mapnames[mazeidx]
           , entityLayer = api.mapstrings[mazeidx]
           , api = api}
     end
     return api.mazes[mazeidx]
  end

  function api:commandLine(oldCommandLine)
     -- Adds tmp path to the searchable directories for maps
     return make_map.commandLine(oldCommandLine)
  end

  function api:getAppleLocations()
    local apple_locations = {}
    for k, v in pairs(api.episode:getSpawnVars()) do
        if v.classname == "apple_reward"  then
            local coords = {}
            for x in k:gmatch("%S+") do
                coords[#coords + 1] = tonumber(x)
            end
            apple_locations[tonumber(v.id) - 2] = {coords[1], coords[2]}
        end
    end
    return apple_locations
  end

  function api:nextMap()
     -- reload the same map
    if api.episode:hasFinished() then
        -- Start a new episode
        local maze = api:getMaze()
        api.episode = api.Episode:new{
           api = api
           , maze = maze}
    else
       api.episode:newSubEpisode()
    end
    
    -- Return the chosen mapname
    local nMapName = api.episode:getMapName()
    -- print("Looking for map: " .. nMapName)
    return nMapName
  end

  pickup_observations.decorate(api)
  custom_observations.decorate(api)
  -- Although we handle the episode timeout ourselves so that we can
  -- reinitialize the maze with new map and new goal.
  -- But the timeout decorator is useful in terms of displaying time as a message.
  timeout.decorate(api, api.episodeLengthSeconds)
  
  return api
end

return factory
