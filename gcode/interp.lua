-- Copyright (c) 2026 treevar. All rights reserved.
-- Licensed under a modified MIT License <https://github.com/treevar/mc-cc/blob/main/LICENSE>

--GCode(Fanuc) interpreter for a turtle
local GCode = require("gcode.map")
local Util = require("common.util")

Interp = {
    curBlock = { --Current block values
        
    },
    state = { --Machine state
        x = 0,
        y = 0,
        z = 0,
        heading = 0,
        plane = GCode.plane.XZ, 
        wcs = {
            [1] = {x = 0, y = 0, z = 0},
            [2] = {x = 0, y = 0, z = 0},
            [3] = {x = 0, y = 0, z = 0},
            [4] = {x = 0, y = 0, z = 0},
            [5] = {x = 0, y = 0, z = 0},
            [6] = {x = 0, y = 0, z = 0},
        },
        modal = {
            [GCode.modal.WCS] = GCode.wcsIdx.G54
        },
        halted = GCode.haltType.NONE,
    },
    programStack = {
        --[[
        {
            name = "01900.nc",
            lineArgs = {
                #1 = 34,
                #2 = 5,
                ...
                #6 = 3
            }, --Args passed on line that called this
            lineNum = 0
        }
        ]]
    },
    haltMsg = ""
}

Interp.__index = Interp

function Interp:new()
    local o = {}
    setmetatable(o, self)
    return o
end

function Interp.constructErrMsg(err, idx)
    return err .. " at pos " .. idx
end

--Can be called to signal that the machine should halt
function Interp:halt(haltType, reason, idx)
    if(type(idx) == "number") then
        self.haltMsg = Interp.constructErrMsg(reason, idx)
    else
        self.haltMsg = reason
    end
    self.state.halted = haltType
end

function Interp:_terminate()
    local prog = self.programStack[#self.programStack]
    local hType = self.state.halted
    write("[HALT] ")
    if(hType == GCode.haltType.MACHINE) then write("Machine")
    elseif(hType == GCode.haltType.STOP) then write("Program")
    elseif(hType == GCode.haltType.WAIT) then write("Wait (this shouldnt be here)")
    else write("(Unknown Type)")
    end
    print(" halted on line " .. prog.lineNum .. " in program " .. prog.name)
    if(hType == GCode.haltType.STOP) then
        error("Program terminated successfully", 0)
    end
    error(self.haltMsg, 0)
end

function Interp:resetHalt()
    self.state.halted = GCode.haltType.NONE
    self.haltMsg = ""
end

function Interp:getParamRaw(letter, stateIfNil)
    local val = self.curBlock.args[letter]
    if(val ~= nil) then return nil end
    if(stateIfNil) then return self.state[letter] end
    return nil
end

function Interp:getParam(cmd, letter, stateIfNil)
    local val = self:getParamRaw(letter, stateIfNil)
    if(val == nil) then return nil end
    if(not cmd.round) then
        return math.floor()
    end
    return nil
end

Interp.handler = {
    G04 = function(cmd, interp)
        local P = interp:getParam("P")
        if(P < 0) then
            interp:halt(GCode.haltType.MACHINE, "Invalid P value")
            return
        end
        sleep(P)
    end,
    G10 = function(cmd, interp)
        local L = interp:getParam("L")
        local P = interp:getParam("P", true)
        local validVal = {
            [2] = true, --WCS
        }
        if(not validVal[L]) then
            interp:halt(GCode.haltType.MACHINE, "Invalid L value")
            return
        end
        if(not P or P < 1 or P > 6) then
            interp:halt(GCode.haltType.MACHINE, "Invalid P value")
            return
        end
        local wcs = interp.state.wcs[P]
    end
}

--Validation

function Interp.getMissingArg(cmd, args)
    if(cmd.reqArgs and #cmd.reqArgs > 0) then
        for k, v in pairs(cmd.reqArgs) do
            if(not args[v.c]) then return v end
        end
    end
    return nil
end

--Validates that the command follows proper syntax
--If atleast one syntax violation is found, the index of the first violation will be returned
--Otherwise returns nil
function Interp.getBadSyntaxIndex(line)
    if(line == nil) then return nil end
    if(#line == 0) then return nil end
    --Syntax validation
    local patterns = {
        "^[^" .. GCode.validParamsStr .."]",                --Starts with a non valid char (Must start with a letter)
        "[^%d" .. GCode.validLettersStr .. "%.]",            --Match any that are NOT digit, valid, or dot
        string.rep("[" .. GCode.validLettersStr .. "]", 2),  --Match multiple concurrent letters 
        "[%D]%.",                                   --Dot trailing a non digit
        "%.[%D]",                                   --Dot preceding a non digit
        --"%.0-[123456789]" --Non zero following dot
    }
    local lowestIdx = nil
    for _, p in pairs(patterns) do
        local idx = string.find(line, p)
        if(idx and idx < lowestIdx) then lowestIdx = idx end
    end

    --Return if syntax error
    if(lowestIdx) then return lowestIdx end

    return lowestIdx
end

function Interp.roundParam(p, val)
    local intPart, decPart = math.modf(val)
    if(not p.float and decPart > 0) then return nil end
    if(p.round) then
        val = math.floor(val + 0.5)
    end
    return val
end

function Interp.roundParams(cmd, params)
    if(not params) then return nil end
    for k, v in pairs(cmd.reqArgs) do
        if(params[v.c] ~= nil) then
            params[v.c] = Interp.roundParam(v, params[v.c])
            if(params[v.c] == nil) then return v.c end
        end
    end
    for k, v in pairs(cmd.optArgs) do
         if(params[v.c] ~= nil) then
            params[v.c] = Interp.roundParam(v, params[v.c])
            if(params[v.c] == nil) then return v.c end
        end
    end
    return nil
end

function Interp.verifySubProgCall(parsed)
    local usedParams = {}

    --Helper to add all used params
    local addParams = function(cmd)
        if(cmd.str == "M98") then return end
        if(cmd.reqArgs) then
            for k, v in pairs(cmd.reqArgs) do
                usedParams[v.c] = true
            end
        end
        if(cmd.optArgs) then
            for k, v in pairs(cmd.optArgs) do
                usedParams[v.c] = true
            end
        end
    end

    --Add all params
    for _, cmd in pairs(parsed.nonModal) do
        addParams(cmd)
    end
    for _, cmd in pairs(parsed.modal) do
        addParams(cmd)
    end

    --Check if there's any params that cmds use
    for k, v in pairs(parsed.args) do
        if(usedParams[k]) then return false end
    end

    return true
end

function Interp.isBadLine(parsed)
    local retObj = {
        badCmd = nil,
        failureStr = ""
    }
    --Check param values
    local cmdFn = function(cmd)
        local missingArg = Interp.getMissingArg(cmd, parsed.args)
        if(missingArg) then
            retObj.badCmd = cmd
            retObj.failureStr = "Missing '" .. missingArg.c .. "' for cmd " .. cmd.str
        else
            local badParam = Interp.roundParams(cmd, parsed.args)
            if(badParam) then
                retObj.badCmd = cmd
                retObj.failureStr = "Non-int value for non-rounding param '" .. badParam .. "'"
            end
        end
    end
    local hasSubCall = false
    local hasSubRet = false
    for k, v in pairs(parsed.nonModal) do
        if(v.str == "M98") then hasSubCall = true
        elseif(v.str == "M99") then hasSubRet = true
        else
            cmdFn(v)
            if(retObj.badCmd) then return retObj end
        end
    end
    for k, v in pairs(parsed.modal) do
        cmdFn(v)
        if(retObj.badCmd) then return retObj end
    end
    --Verify subprogram call
    if(hasSubCall) then
        if(hasSubRet) then
            retObj.badCmd = "M99"
            retObj.failureStr = GCode.error.SUBPROG_CALL_RETURN
        elseif(not Interp.verifySubProgCall(parsed)) then
            retObj.badCmd = "M98"
            retObj.failureStr = GCode.error.SUBPROG_PARAM
        end
    end
    return retObj
end

--Parsing

--Removed comments and WS from the line 
function Interp.cleanLine(line)
    local clean = ""
    if(line ~= nil) then 
        clean = line
        if(clean:sub(1, 1) == "/") then return "" end --Skip 'block-skip' blocks for now
        clean = line:gsub("%s", "") --Rm WS
        clean = clean:gsub("%(.-%)", "") --Rm comments
        --Rm everything after EOB char
        local semiCPos = clean:find(";", 1, true)
        if(semiCPos) then
            clean = clean:sub(1, semiCPos-1)
        end
    end
    return clean
end

--Parse entire line
function Interp.parseLine(line)
    local retObj = {
        modal = {},
        nonModal = {},
        args = {},
        parsingStr = "", --Actual string we parse (all WS rm)
        badIdx = nil, --Index (of parsingStr) of parsing failure
        failureStr = "" --Reason for failure
    }

    if(type(line) ~= "string" or #line == 0) then return retObj end --Empty line

    local pString = Interp.cleanLine(line)
    retObj.parsingStr = pString

    retObj.badIdx = Interp.getBadSyntaxIndex(pString)
    if(retObj.badIdx ~= nil) then
        retObj.failureStr = GCode.error.SYNTAX
        return retObj
    end
    local curLetter = string.sub(pString, 1, 1)

    local curPartStart = 1

    local loopFn = function(i)
        local part = pString:sub(curPartStart, i-1)
        local cmd = GCode.cmd[part]
        if(cmd ~= nil) then
            if(cmd.modal) then
                retObj.modal[cmd.modal] = cmd
            else
                table.insert(retObj.nonModal)
            end
        else --Parameter
            if(GCode.allCmdLettersStr:find(curLetter, 1, true)) then
                retObj.badIdx = curPartStart
                retObj.failureStr = GCode.error.CMD_UNKNOWN
                return
            end
            retObj.args[curLetter] = tonumber(pString:sub(curPartStart+1, i-1))
        end
    end

    for i = 2, #pString do
        if(retObj.badIdx ~= nil) then return retObj end --Last loop iter caused parsing failure
        local c = pString:sub(i, i)
        if(c:match("%a")) then --Letter
            loopFn(i)
            curLetter = c
            curPartStart = i
        end
    end

    loopFn(#pString + 1) --Add last cmd

    return retObj
end

function Interp:execCmd(cmd)
    if(not cmd) then return end
    --Update modal
    if(cmd.modal) then
        self.state.modal[cmd.modal] = cmd
    end
    --Exec
    local handler = Interp.handler[cmd.str]
    if(handler) then handler(cmd, self) end
end

function Interp:handleNonModal()
    local cmds = self.curBlock.nonModal
    if(cmds == nil or #cmds == 0) then return end
    local handler = nil
    for _, cmd in pairs(cmds) do
        self:execCmd(cmd)
        if(self.state.halted) then return end
    end
end

function Interp:handleModal()
    local order = {
        GCode.modal.WCS,
        GCode.modal.PLANE,
        GCode.modal.SCALE,
        GCode.modal.DISTANCE,
        GCode.modal.MOTION,
        GCode.modal.PROG_FLOW
    }
    local cmd = nil
    local handler = nil
    for _, modal in pairs(order) do
        cmd = self.curBlock.modal[modal]
        self:execCmd(cmd)
        if(self.state.halted) then return end
    end
end

function Interp:execLine(parsedLine)
    if(parsedLine == nil) then return end
    self.curBlock = parsedLine
    self:handleNonModal()
    if(self.state.halted) then return end
    self:handleModal()
    if(self.state.halted) then return end
    self:calcTarget()
    self:handleMove()
    self:updateRegisters()
end

function Interp:lineFn(line)
    if(not line or #line == 0) then return end
    --Parse
    local parsed = Interp.parseLine(line)
    if(parsed.badIdx ~= nil) then
        local idx = parsed.badIdx
        if(idx == 0) then idx = nil end
        self:halt(GCode.haltType.MACHINE, parsed.failureStr, idx)
        return
    end
    --Verify
    local bad = Interp.isBadLine(parsed)
    if(bad) then
        self:halt(GCode.haltType.MACHINE, "(" .. bad.cmd.str .. "): " .. bad.failureStr)
        return
    end
    --Exec
    self:execLine(parsed)
end

function Interp:_getCurProg()
    return self.programStack[#self.programStack]
end

function Interp:_incLineNum(n)
    if(not n) then n = 1 end
    local prog = self:_getCurProg()
    prog.lineNum = prog.lineNum + n
end

function Interp:_pushProg(name, lineNum)
    table.insert(self.programStack, {name = name, lineNum = lineNum or 1})
end

function Interp:_popProg()
    table.remove(self.programStack)
end

function Interp:read(fileName, perLineFunc)
    self:_pushProg(fileName)
    if(fileName == nil or #fileName == 0 or not fs.exists(fileName)) then
        self:halt(GCode.haltType.MACHINE, GCode.error.FILE_NX)
        return
    end
    local file = fs.open(fileName)
    if(file == nil) then
        self:halt(GCode.haltType.MACHINE, GCode.error.FILE_OPEN)
        return
    end

    --Skip program ident header
    self:_incLineNum()
    local line = file.readLine()
    if(line and line:sub(1, 1) == "O") then
        line = file.readLine()
        self:_incLineNum()
    end

    --Exec
    while line do
        perLineFunc(line)
        if(self.state.halted == GCode.haltType.MACHINE or self.state.halted == GCode.haltType.STOP) then --Machine halted, terminate
            file.close()
            self:_terminate()
            return
        elseif(self.state.halted == GCode.haltType.WAIT) then
            local curProg = self:_getCurProg()
            print("(" .. curProg.name .. ")")
            print("Halt & Wait called on line " .. curProg.lineNum)
            write("Press 'Enter' to continue...")
            read() --Wait for user input
            self:resetHalt()
        end
        self:_incLineNum()
        line = file.readLine()
    end
    file.close()
    self:_popProg()
end