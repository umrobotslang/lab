local pickup_observations = require 'decorators.pickup_observations'
local game = require 'dmlab.system.game'
local random = require 'common.random'
local pickups = require 'common.pickups'
local helpers = require 'common.helpers'
local custom_observations = require 'decorators.custom_observations'
local timeout = require 'decorators.timeout'

local factory = {}

--[[ Creates a Seek Avoid API.
Keyword arguments:

*   `mapName` (string) - Name of map to load.
*   `episodeLengthSeconds` (number) - Episode length in seconds.
*   `scatteredrewarddensity` (number) - Probability of apple actually appearing in map.
*   `spawnVarscount` (number) - Number of info_player_start or non-goal
                                pickups in in the map
]]
function factory.createLevelApi(kwargs)
  assert(kwargs.mapName and kwargs.episodeLengthSeconds)

  local api = {}

  function api:init(params)
     api.mapName = kwargs.mapName
     api.episodeLengthSeconds = tonumber(
        params.episode_length_seconds or tostring(kwargs.episodeLengthSeconds))
     api.scatteredRewardDensity = tonumber(params.apple_prob or "0.25")
     api.spawnVarsCount = kwargs.spawnVarsCount or error("Need spawn vars")
     _ = params.game_seed or error("Need game_seed")
     random.seed(params.game_seed)
  end

  function api:createPickup(class_name)
    return pickups.defaults[class_name]
  end

  function api:start(episode, seed, params)
    -- random.seed(seed)
    api._has_goal = false
    api.info_player_start_idx = random.uniformInt(1, api.spawnVarsCount)
    api._count = 0
    api._finish_count = 0
    api._spawn_var_idx = 0
  end

  function api:pickup(spawn_id)
    api._count = api._count + 1
    if not api._has_goal and api._count == api._finish_count then
      game:finishMap()
    end
  end

  function api:updateSpawnVars(spawnVars)
    local classname = spawnVars.classname

    -- Replace the info_player_start_idx's spawn var with 
    if spawnVars.classname ~= "goal" then
        if api._spawn_var_idx == api.info_player_start_idx then
           spawnVars.classname = "info_player_start"
        elseif spawnVars.classname == "info_player_start" then
           spawnVars.classname = "apple_reward"
        else
           -- do nothing
        end
        -- Increment only if spawnVars is non-goal
        api._spawn_var_idx = api._spawn_var_idx + 1
    end

    local pickup = pickups.defaults[spawnVars.classname]
    if pickup then
      if pickup.type == pickups.type.kReward and pickup.quantity > 0 then
        api._finish_count = api._finish_count + 1
        spawnVars.id = tostring(api._finish_count)
      end
      if pickup.type == pickups.type.kGoal then
        api._has_goal = true
      end
    end

    if spawnVars.classname == "apple_reward" then
       spawnVars = (random.uniformReal(0, 1) < api.scatteredRewardDensity) and
          spawnVars or nil
    end
    return spawnVars
  end

  function api:nextMap()
    local mapName = api.mapName
    --print("Looking for mapName " .. mapName)
    return mapName
  end

  pickup_observations.decorate(api)
  custom_observations.decorate(api)
  timeout.decorate(api, kwargs.episodeLengthSeconds)
  return api
end

return factory
