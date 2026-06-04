-- Copyright (c) 2026 treevar. All rights reserved.
-- Licensed under a modified MIT License <https://github.com/treevar/mc-cc/blob/main/LICENSE>
local Util = require("treevar.common.util")
Cmd_Manager = {handler = {}, authFunc = nil}

function Cmd_Manager:new()
    local o = {}
    setmetatable(o, self)
    o.handler = {}
    o.handler.help = {
        name = "help",
        fn = nil,
        args = {
            {name = "cmd", type = "string"}
        },
        help = "Display cmd info"
    }
    self.__index = self
    return o
end

function Cmd_Manager:register(cmd, expectArgs, fn, help, tags)
    self.handler[cmd] = {
        name = cmd,
        fn = fn,
        args = expectArgs or {},
        help = help,
        tags = tags or {},
    }
end

function Cmd_Manager.getHelpHeader(handler)
    if(not handler) then
        return "Unknown Command"
    end
    local str = handler.name
    if(not handler.args or #handler.args == 0) then
        return str
    end
    for _, arg in pairs(handler.args) do
        local encloseChar = {"[", "]"}
        if(arg.literal) then encloseChar = {"(", ")"}
        elseif(not arg.req) then encloseChar = {"{", "}"} end
        str = str .. " " .. encloseChar[1] .. arg.name .. encloseChar[2]
    end
    return str
end

function Cmd_Manager:_defHelpFn(cmd, args)
    local cmdPerPage = 5
    local page = 1
    local printCmd = function(c, noPrint)
        if(self.authFunc == nil or self.authFunc(c)) then
            if(not noPrint) then 
                print(" " .. Cmd_Manager.getHelpHeader(c))
                print("  " .. c.help)
            end
            return true
        end
        return false
    end
    if(#args == 2) then
        page = tonumber(args[2])
        if(page == nil) then
            if(not printCmd(self.handler[args[2]])) then
                print("help: Unknown Command")
            end
            return
        end
    end
    local authedFnCnt = 0
    for _, cmd in pairs(self.handler) do
        if(printCmd(cmd, true)) then authedFnCnt = authedFnCnt + 1 end
    end
    local maxPage = math.ceil(authedFnCnt / cmdPerPage)
    if(page > maxPage) then
        print("Bad page number")
        return
    end
    local screenWidth = 51
    if(pocket) then screenWidth = 26 end
    print(Util.center("Help " .. tostring(page) .. "/" .. tostring(maxPage), screenWidth))
    local skipNum = (page-1) * cmdPerPage
    local skipped = 0
    local printed = 0
    for cmdName, cmd in pairs(self.handler) do
        if(skipped < skipNum) then
            if(printCmd(cmd, true)) then skipped = skipped + 1 end
        elseif(printed < cmdPerPage) then
            if(printCmd(cmd)) then printed = printed + 1 end
        end
    end 
end

function Cmd_Manager:unregister(cmd)
    self.handler[cmd] = nil
end

function Cmd_Manager.verifyArgs(cmd, args)
    --Veryify arg count
    if(#cmd.args < #args-1) then
        return false, "More args provided than expected"
    end
    local reqCnt = 0
    for _, arg in pairs(cmd.args) do
        if(arg.req) then reqCnt = reqCnt + 1 end
    end
    if(#args-1 < reqCnt) then
        return false, "Expected " .. reqCnt .. " args, got " .. #args-1
    end
    return true
end

function Cmd_Manager:call(cmdName, ...)
    local args = {...}
    local retObj = {
        success = false,
        msg = nil,
        ret = nil,
        authed = false,
    }
    local handler = self.handler[cmdName]
    if(not handler) then
        retObj.msg = "Unknown command: " .. cmdName
        return retObj
    end
    
    if(cmdName ~= "help" and not self.authFunc(handler)) then
        retObj.msg = "Unknown command: " .. cmdName
        return retObj
    end

    retObj.authed = true

    local suc, err = Cmd_Manager.verifyArgs(handler, args)
    if(not suc) then 
        retObj.msg = err
        return retObj
    end
    
    
    retObj.success = true
    if(cmdName == "help" and handler.fn == nil) then
        retObj.ret = self:_defHelpFn(handler, args)
    else
        retObj.ret = handler.fn(handler, args)
    end

    return retObj
end

function Cmd_Manager:handle(str)
    if(not str or #str == 0) then
        return nil
    end
    local parts = Util.split(str, " ")
    local cmd = parts[1]
    local ret = self:call(cmd, table.unpack(parts))
    if(ret.success) then return ret.ret end
    print(ret.msg)
    local handler = self.handler[cmd]
    if(ret.authed and handler) then
        print("Usage:")
        print(Cmd_Manager.getHelpHeader(handler))
        print(handler.help)
    end
end

return Cmd_Manager