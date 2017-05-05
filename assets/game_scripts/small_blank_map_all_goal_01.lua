local maze_gen = require 'dmlab.system.maze_generation'
local helpers = require 'common.helpers'
local custom_observations = require 'decorators.custom_observations'
local timeout = require 'decorators.timeout'

local entityLayer = [[
*******
* G   *
*G    *
*  P  *
*    G*
*   G *
*******
]]
local episodeLengthSeconds = 20

local maze = maze_gen.MazeGeneration{entity = entityLayer}
local map_height, map_width = maze:size()
local api = {}

function api:init(params)
  if params and params.spawn_origin then
    api._info_player_start = {
       classname = "info_player_start"
       , origin = params.spawn_origin .. ' 30' }
    if params.spawn_angle then
       api._info_player_start["angle"] = params.spawn_angle
       api._info_player_start["randomAngleRange"] = '0'
    end
  end

  if params and params.goal_loc then
      local coords = {}
      for x in params.goal_loc:gmatch("%S+") do
          coords[#coords + 1] = tonumber(x)
      end
      local x, y = helpers.text_row_col_to_map_key(
        coords[1], coords[2], map_height)
      api._goal_loc = {
          classname = "goal"
          , origin = '' .. x .. ' ' .. y
      }
  end
end

function api:nextMap()
   return "small_blank_map_all_goal_01"
end

function api:updateSpawnVars(spawnVars)
  if spawnVars.classname == "info_player_start" then
     return api._info_player_start or spawnVars
  elseif spawnVars.classname == "goal" then
      if api._goal_loc and spawnVars.origin == api._goal_loc.origin then
          return api._goal_loc
      else
          return
      end
  end
  return spawnVars
end

custom_observations.decorate(api)
timeout.decorate(api, episodeLengthSeconds)
return api
