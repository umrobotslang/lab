# What are these lua scripts
These lua scripts are called by the game's C code and provide
customizability to the games without modifying the C code for each
game.

# What are the interfaces provided
This documentation is not meant to be complete. For more details look in the file
`../../deepmind/engine/context.cc`

## API Interface:
Each lua script must return an object called that should may have
the following member functions.

### API.init(settings)
This is the first function that is called after loading the lua
script. This function can be used to make any initializations for rest of
the functions. The return values do not directly affect the game.

Params: settings is table with string key value pairs that were passed as
config to the DeepmindLab python wrapper but were not used by any of
intermediate configuration stages.
       

### obs_spec = API.customObservationSpec()
This function is called by the C-code after the init function.
Expected to Return a list of specifications that defines additional
observations specifications.
Look at sample implementation in decorators/custom_observations.lua
return { { name = 'POSE', type = 'Doubles', shape = {6} } }

### obs = API.customObservation(name)
This function is called by the Python API whenever observation() is requested
with one of the "name" as defined by the customObservationSpec. The return value
should be the intended value of the observation at that point in the game.
The return data type should match as specified the customObservationSpec.
The observation is converted into numpy array of given shape and
type and return to the python API.

Params: name : Name of the custom observation

Expected Return: observation of declared type and shape.
  
### API.start(episode, seed)
Called when python API start() (on start of each episode) is called.

Params:
* episode: Episode ID
* seed   : Random seed provided to the Python API.
  
### to_end_or_not = API.hasEpisodeFinished(time_in_seconds)
Called after every frame (step of the game),

Params: time_in_seconds : time in seconds depending upon fps

Expected return: true to end the episide, false to continue
  
### new_cmd_line = API.commandLine(old_cmd_line)
This function is called after start(episode_id, seed) but only once.
The game engine is started by calling Com_Init(command_line) which is
ioquak3 funciton. Additional flags can be added to the command line
through this function.

Params: old_cmd_line : Command line so far

Expected Return value: new_cmd_line : Modified command line if needed.

### map_file_name = API.nextMap()
This function is called whenever a new map is to be loaded i.e. at the start
of the game and after the agent has found the "goal".

Expected return value: map_file_name : The map file name without the
.map extension. This map will be loaded a that particular stage of the game.
  
### new_spawn_vars = API.updateSpawnVars(spawnVars)
This function is used to modify the apples, lemons, goals and info_player_start
parts of the map. This function is triggered well inside the game
when the game is being loaded (../../engine/code/game/g_spawn.c).

Params: spawnVars : A table with two keys: classname and origin. Example:
{ classname = 'goal|apple_reward|info_player_start|... '
, origin = '150 950 30' }
"classname" describes one of the entityTypes in the map.
"origin" is a string that describes the position of the entity.

Expected return value: new_spawn_vars : A modified table of spawnVars or nil.
Returning nil deletes any item at that particular 'origin'.
While modifying the spawnVars, the origin is usually left unmodified.
  
### class_properties = API.createPickup(class_name)
Whether a particular class of entity (like goal|apple_reward) is
pickable or not.

Params : class_name as received from the *.map

Expected return : A table of class_properties. Look at
common/pickup.lua to see the default class properties for
different classnames. The following keys are expected in class_properties

- name[256] : Item name (for printing on pickup)
- class_name[256] : name of the class of entity (spawning name)
- model_name[256] : path to 3D model file
- int quantity : for reward how much, for ammo how much, or duration of powerup.
- int type : One of the 11 integer types like goal = 10, reward =
  9, ammo=2 etc.
- int tag : Optional tag for the item.

For more detailed usage look at file: engine/code/game/bg_public.h and engine/code/game/bg_misc.c

### can_pickup = API.canPickup(entity_id)
Checked for entity_id, whether it can be picked or not.

### respawn_time = API.pickup(entity_id)
Called for before every pickup action. When will this entity respawn
after being picked up.

### bot_properties = API.addBots()
Called after start(episiode_id, seed)

Expected return: bot_properties : A table for each of the bot
properties with following keys.
- char name[] : bot name
- double skill : skill level
- char team[] : team name

### API.modifyTexture(name, texture)
Called with name and texture to be modified. Override the texture
values to modify the texture.

Params:
* name : string name of the texture
* texture : h x w x 4 patch of RGBA texture.
 
### message_properties = API.screenMessages(screen_width, screen_height, line_height, max_string_length)
Add messages to the game screen.

Expected return value: A list of tables with message properties as following keys:
- message : String of message
- int x : X-coordinate 
- int y : Y-coordinate
- int alignment : 0 for left, 1  for right, 2 for center
  
## Other helper classes and functions
* dmlab.system.tensor.DoubleTensor(*args)
* dmlab.system.tensor.ByteTensor(*args)
* dmlab.system.game.playerInfo()
* dmlab.system.maze_generation.MazeGeneration(params)
* dmlab.system.map_maker
* dmlab.system.random

