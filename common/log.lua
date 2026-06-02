-- Copyright (c) 2026 treevar. All rights reserved.
-- Licensed under a modified MIT License <https://github.com/treevar/mc-cc/blob/main/LICENSE>
Log = {fileName = "log.txt", curLogLevel = 0, enabled = true}

Log.Level = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
    FATAL = 5
}

Log.LevelStr = {
    [Log.Level.DEBUG] = "DEBUG",
    [Log.Level.INFO] = "INFO",
    [Log.Level.WARN] = "WARN",
    [Log.Level.ERROR] = "ERROR",
    [Log.Level.FATAL] = "FATAL"
}

function Log:new(fileName, logLevel)
    o = {}
    setmetatable(o, self)
    self.__index = self
    o.fileName = fileName
    o.curLogLevel = logLevel or Log.Level.WARN
    o.enabled = true
    return o
end

function Log:log(level, ...)
    if (not self.enabled or level < 0 or level > #Log.LevelStr or level < self.curLogLevel) then
        return
    end
    local file = fs.open(self.fileName, "a")
    file.writeLine("[" .. Log.LevelStr[level] .. "] " .. table.concat({...}, " "))
    file.close()
end

function Log:clear()
    local file = fs.open(self.fileName, "w")
    file.write("")
    file.close()
end

return Log