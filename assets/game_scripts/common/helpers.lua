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
function helpers.dir(obj,level)
  local s,t = '', type(obj)

  level = level or ' '
  if string.len(level) > 5 then
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

local Logger = {}
Logger.DEBUG = 3
Logger.NONE = 0
function Logger:new(o)
   o = o or {level = DEBUG}
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
