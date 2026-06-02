-- Copyright (c) 2026 treevar. All rights reserved.
-- Licensed under a modified MIT License <https://github.com/treevar/mc-cc/blob/main/LICENSE>
local util = require("common.util")
local Log = require("common.log")

Config = {fileName = "default.cfg", data = {}, logger = nil}

function Config:new(fileName, logger)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.fileName = fileName
    o.logger = logger
    o.data = {}
    return o
end

function Config:_log(level, ...)
    if self.logger then
        self.logger:log(level, ...)
    end
end

function Config.isValidType(cfgEntry, val)
    if(not cfgEntry.types) then
        return true
    end
    for _, t in pairs(cfgEntry.types) do
        if(t == "any" or t == type(val)) then
            return true
        end
    end
    return false
end

function Config:_updateAll()
    for key, v in pairs(self.data) do
        if(type(v) ~= "table" or (v.value == nil and v.types == nil)) then
            local oldVal = v
            self.data[key] = {}
            self.data[key].value = oldVal
            self.data[key].types = type(oldVal)
            self:_log(Log.Level.DEBUG, "Updated old config entry " .. key .. ": " .. tostring(oldVal) .. " to new format")
        elseif(self.data[key].types == nil) then
            self.data[key].types = types or {"any"}
        end
    end
end

function Config:load(fileName)
    fileName = fileName or self.fileName
    if fs.exists(fileName) then
        local file = fs.open(fileName, "r")
        local content = file.readAll()
        file.close()
        
        local loadedData = textutils.unserialize(content)
        if loadedData then
            -- Clear existing data in the original table
            self:clear()
            -- Populate original table with new data
            for k, v in pairs(loadedData) do self.data[k] = v end
        end
        self:_updateAll()
        self:_log(Log.Level.INFO, "Loaded config from " .. fileName)
        return true
    else
        self:_log(Log.Level.WARN, "Config file '" .. fileName .. "' not found")
        return false
    end
end


function Config:save(fileName)
    fileName = fileName or self.fileName
    local file = fs.open(fileName, "w")
    file.write(textutils.serialize(self.data))
    file.close()
    self:_log(Log.Level.INFO, "Saved config to ", fileName)
end

function Config:has(key)
    return self.data[key] ~= nil and self.data[key].value ~= nil
end

function Config:get(key)
    return self.data[key].value
end

function Config:getTypes(key)
    return self.data[key].types
end

--Set a config value.
--Used to create new config entries as well, if types is supplied on first set then it will check types on future sets
--If types is not supplied on first set then any type is allowed
--Adding 'any' to types allows any type for that entry
--Returns whether the set was successful.
function Config:set(key, value, types)
    if(type(types) == "string") then
        types = {types}
    end
    if(self.data[key] == nil) then
        self.data[key] = {
            value = value,
            types = types or {"any"}
        }
    end
    if(Config.isValidType(self.data[key], value)) then
        self.data[key].value = value
        self:_log(Log.Level.DEBUG, "Updated config " .. key .. ": " .. tostring(value or "nil"))
        return true
    end
    self:_log(Log.Level.WARN, "Bad type for config " .. key .. ": " .. tostring(value or "nil") .. " (expected " .. table.concat(self.data[key].types, " or ") .. ")")
    return false
end

function Config:clear()
    for k in pairs(self.data) do self.data[k] = nil end
end

return Config