local random = require 'common.random'
-- Common utilities.

local helpers = {}
-- Shuffles an array in place. (Uses the 'common.random'.)
function helpers.shuffleInPlace(array)
  for i = 1, #array - 1 do
    local j = random.uniformInt(i, #array)
    array[j], array[i] = array[i], array[j]
  end

  return array
end

-- Returns a shuffled copy of an array. (Uses the 'common.random'.)
function helpers.shuffle(array)
  local ret = {}
  for i, obj in ipairs(array) do
    ret[i] = obj
  end
  return helpers.shuffleInPlace(ret)
end

-- Returns an array of strings split according to single character separator.
-- Skips empty fields.
function helpers.split(str, sep)
  words = {}
  for word in string.gmatch(str, '([^' .. sep .. ']+)') do
      words[#words + 1] = word
  end
  return words
end

------------------------------------------------------------------------
-- based on:
-- "Dir (objects introspection like Python's dir) - Lua"
-- http://snipplr.com/view/13085/
-- (added iteration through getmetatable of userdata, and recursive call)
-- make a global function here (in case it's needed in requires)
--- Returns string representation of object obj
-- @return String representation of obj
------------------------------------------------------------------------
function helpers.dir(obj,level, maxlevel)
  local s,t = '', type(obj)

  level = level or ' '
  maxlevel = maxlevel or 5
  if string.len(level) > maxlevel then
     return '...'
  end

  if (t=='nil') or (t=='boolean') or (t=='number') or (t=='string') then
    s = tostring(obj)
    if t=='string' then
      s = '"' .. s .. '"'
    end
  elseif t=='function' then s='function'
  elseif t=='userdata' then
    s='userdata'
    for n,v in pairs(getmetatable(obj)) do  s = s .. " (" .. n .. "," .. helpers.dir(v) .. ")" end
  elseif t=='thread' then s='thread'
  elseif t=='table' then
    s = '{'
    for k,v in pairs(obj) do
      local k_str = tostring(k)
      if type(k)=='string' then
        k_str = '["' .. k_str .. '"]'
      end
      s = s .. k_str .. ' = ' .. helpers.dir(v,level .. level) .. ', '
    end
    s = string.sub(s, 1, -3)
    s = s .. '}'
  end
  return s
end

local BLOCKSIZE = 100
function helpers.text_row_col_to_map_xy(row, col, height)
  -- Axis is flipped in DeepMind Lab.
  return ((col - 0.5) * BLOCKSIZE), ((height - row + 0.5) * BLOCKSIZE)
end

function helpers.map_xy_to_text_row_col(x, y, height)
  -- Axis is flipped in DeepMind Lab.
  return (height - math.floor(y/BLOCKSIZE)), math.floor(x/BLOCKSIZE) + 1
end


function helpers.parsePossibleGoalLocations(maze, intpairkey, entity, checkcellfunc)
    entity = entity or "G"
    checkcellfunc = checkcellfunc or function (entityCell) return entityCell == entity end
    local height, width = maze:size()
    local possibleGoalLocations = {}
    for r = 1,height do
        for c = 1,width do
           if checkcellfunc(maze:getEntityCell(r, c)) then
                possibleGoalLocations[#possibleGoalLocations + 1] = {r, c}
            end
        end
    end
    local otherGoalLocations = {}
    for i = 1,#possibleGoalLocations do
       local r,c = unpack(possibleGoalLocations[i])
       local rc_key = intpairkey(r, c)
       local pgl = { unpack(possibleGoalLocations) }
       table.remove(pgl, i)
       --print(string.format("Found G at (%d, %d) '%s'", r, c, rc_key))
       otherGoalLocations[rc_key] = pgl
    end
    return possibleGoalLocations, otherGoalLocations
end

function helpers.parsePossibleSpawnLocations(maze, intpairkey)
<<<<<<< HEAD
    local height, width = maze:size()
    local possibleGoalLocations = {}
    for r = 1,height do
        for c = 1,width do
            if maze:getEntityCell(r, c) == "P" then
                possibleGoalLocations[#possibleGoalLocations + 1] = {r, c}
                --print(string.format("Found G at (%d, %d)", r, c))
            end
        end
    end
    local otherGoalLocations = {}
    for i = 1,#possibleGoalLocations do
       local r,c = unpack(possibleGoalLocations[i])
       local rc_key = intpairkey(r, c)
       local pgl = { unpack(possibleGoalLocations) }
       table.remove(pgl, i)
       otherGoalLocations[rc_key] = pgl
    end
    return possibleGoalLocations, otherGoalLocations
end

function helpers.parseAllLocations(maze, intpairkey)
    local height, width = maze:size()
    local possibleGoalLocations = {}
    for r = 1,height do
        for c = 1,width do
            if maze:getEntityCell(r, c) == " " then
                possibleGoalLocations[#possibleGoalLocations + 1] = {r, c}
                --print(string.format("Found G at (%d, %d)", r, c))
            end
            if maze:getEntityCell(r, c) == "A" then
                possibleGoalLocations[#possibleGoalLocations + 1] = {r, c}
                --print(string.format("Found G at (%d, %d)", r, c))
            end
            if maze:getEntityCell(r, c) == "G" then
                possibleGoalLocations[#possibleGoalLocations + 1] = {r, c}
                --print(string.format("Found G at (%d, %d)", r, c))
            end
        end
    end
    local otherGoalLocations = {}
    for i = 1,#possibleGoalLocations do
       local r,c = unpack(possibleGoalLocations[i])
       local rc_key = intpairkey(r, c)
       local pgl = { unpack(possibleGoalLocations) }
       table.remove(pgl, i)
       otherGoalLocations[rc_key] = pgl
    end
    return possibleGoalLocations, otherGoalLocations
end

function helpers.parsePossibleAppleLocations(maze, intpairkey)
    local height, width = maze:size()
    local possibleGoalLocations = {}
    for r = 1,height do
        for c = 1,width do
            if maze:getEntityCell(r, c) == "A" then
                possibleGoalLocations[#possibleGoalLocations + 1] = {r, c}
                --print(string.format("Found G at (%d, %d)", r, c))
            end
        end
    end
    local otherGoalLocations = {}
    for i = 1,#possibleGoalLocations do
       local r,c = unpack(possibleGoalLocations[i])
       local rc_key = intpairkey(r, c)
       local pgl = { unpack(possibleGoalLocations) }
       table.remove(pgl, i)
       otherGoalLocations[rc_key] = pgl
    end
    return possibleGoalLocations, otherGoalLocations
=======
   return helpers.parsePossibleGoalLocations(maze, intpairkey, "P")
end

function helpers.parseAllLocations(maze, intpairkey)
   return helpers.parsePossibleGoalLocations(
      maze, intpairkey, "P"
      , function (entityCell) return entityCell == " " or entityCell == "A" or entityCell == "G" end)
end

function helpers.parsePossibleAppleLocations(maze, intpairkey)
   return helpers.parsePossibleGoalLocations(maze,intpairkey, "A")
>>>>>>> f045865e8ef04871934b78020b6cd58258fe6036
end


local Logger = {}
Logger.DEBUG = 3
Logger.NONE = 0
function Logger:new(o)
   o = o or {level = Logger.DEBUG}
   setmetatable(o, self)
   self.__index = self
   return o
end
function Logger:debug(msg)
   if self.level >= Logger.DEBUG then
      print("[DEBUG]:" .. msg)
   end
end
helpers.Logger = Logger

return helpers
