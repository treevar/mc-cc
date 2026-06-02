-- Copyright (c) 2026 treevar. All rights reserved.
-- Licensed under a modified MIT License <https://github.com/treevar/mc-cc/blob/main/LICENSE>
local function isSide(side)
    return  side == "top" or 
            side == "bottom" or 
            side == "left" or
            side == "right" or
            side == "front" or
            side == "back"
end

--Splits a string on the supplied char, c
--Returns an array of strings
local function split(str, c)
    local prevPos = 1
    local ret = {}
    while(prevPos and prevPos <= #str) do
        local newPos = string.find(str, c, prevPos, true)
        if(newPos) then 
            newPos = newPos - 1 
        else
            newPos = #str
        end
        table.insert(ret, string.sub(str, prevPos, newPos))
        prevPos = newPos + 1 + #c -- + 1 for the -1 earlier and +c to get past sep
    end
    return ret
end

--Pad str to be len chars long with char (defaults to space)
local function pad(str, len, char)
    if(type(str) ~= "string") then
        str = tostring(str)
    end
    char = char or " "
    if(str == nil or #str >= len) then return str end
    return str .. string.rep(char, len - #str)
end

--Shiorten str to len chars, adding a , to the end if it was shortened
local function shorten(str, len)
    if(type(str) ~= "string") then
        str = tostring(str)
    end
    if(str == nil or #str <= len) then return str end
    return string.sub(str, 1, len - 1) .. ","
end

--Returns whether the supplied name is valid
--No space, comma, or empty names allowed
local function isValidName(name)
    if(not name or #name == 0) then
        return false
    end
    if(string.find(name, "[ ,]")) then
        return false    
    end
    return true
end

--Returns whether the table contains the value
local function tableContains(table, val)
    for _, v in pairs(table) do
        if(v == val) then
            return true
        end
    end
    return false
end

--Prompt for input and returns the input
--If validVals is supplied then input is a value in it
local function prompt(prompt, validVals)
    local valid = false
    local userIn = nil
    while (not valid) do
        write(prompt)
        userIn = read()
        if(#userIn ~= 0) then
            if(validVals == nil or tableContains(validVals, userIn)) then
                valid = true
            end
        end
    end
    return userIn
end

return {isSide = isSide, split = split, pad = pad, shorten = shorten, isValidName = isValidName, tableContains = tableContains, prompt = prompt}