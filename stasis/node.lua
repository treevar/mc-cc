-- Copyright (c) 2026 treevar. All rights reserved.
-- Licensed under a modified MIT License <https://github.com/treevar/mc-cc/blob/main/LICENSE>
package.path = package.path .. ";/?.lua" --Properly find packages no matter location
--Imports
local Util = require("treevar.common.util")
local Config = require("treevar.common.config")
local Log = require("treevar.common.log")
local Stasis_Proto = require("stasis_proto")
local Proto_Manager = require("treevar.common.proto_manager")
--Peripherals
local modem = peripheral.find("modem", function(name, peripheral) return peripheral.isWireless() end)
local relay = {}
local wrappedRelay = peripheral.find("redstone_relay", function(name, r)
    if(Util.isSide(name)) then
        relay[name] = r
    else
        local id = string.sub(name, #"redstone_relay_" + 1, #name)
        relay[id] = r
    end
    return true
end)
--Dirs
local appDir = "/treevar/stasis"
local dataDir = appDir .. "/data"
--Instances
local log = Log:new(dataDir .. "/latest.log", Log.Level.DEBUG)
local config = Config:new(dataDir .. "/user.cfg", log)
local stasisNetMgr = Proto_Manager:new(Stasis_Proto, false, 1, log)
--Commands
local redNetCmd = {}
local terminalCmd = {}
--User config keys
local userConfigKeys = {
    "loc",
    "def_state",
    "trigger_time",
    "timeout",
}
--Array of trigger tasks
local triggerTasks = {}
--Local settings
local netCodeActive = true
local shouldRun = true

--Returns the user mapped to relayIdx's side
--Returns nil if none found
local function sideToUsr(relayIdx, side)
    if(Util.isSide(side)) then
        for key, value in pairs(config:get("map")) do
            if(value.relayIdx == relayIdx and value.side == side) then 
                return key
            end
        end
    end
    return nil
end

--Sets a redstone relay to the default state
local function initRedstoneRelay(relayIdx, state)
    local r = relay[relayIdx]
    if (r == nil) then
        log:log(log.Level.WARN, "Attempted to initialize nonexistant relay ID " .. tostring(relayIdx))
        return
    end
    r.setOutput("top", state)
    r.setOutput("bottom", state)
    r.setOutput("left", state)
    r.setOutput("right", state)
    r.setOutput("front", state)
    r.setOutput("back", state)
    log:log(log.Level.INFO, "Initialized relay ID " .. tostring(relayIdx) .. " to state " .. tostring(state))
end

--Queries other nodes and returns whether any have the supplied name
local function nodeNameExists(name)
    local node = stasisNetMgr:lookup(name)
    if(node) then
        log:log(Log.Level.DEBUG, "Found existing node with name '" .. name .. "' at ID " .. node)
        return true
    end
    return false
end

--Print current user to relay/side mapping
local function printMappings(map)
    print(Util.pad("User", 21) .. Util.pad("Relay", 7) .. "Side")
    for k, v in pairs(map) do
        --max user is 20 chars + 1 space, relay is 6 chars (bottom) + 1 space, side has more than enough space
        print(Util.pad(k, 21) .. Util.pad(v.relayIdx, 7) .. v.side)
    end
end

--Pulse stasis
local function triggerStasis(relayIdx, side)
    local relay = relay[relayIdx]
    if(relay == nil) then
        log:log(Log.Level.WARN, "Attempted to trigger nonexistant relay ID " .. relayIdx)
        return
    end

    local defState = config:get("def_state")
    relay.setOutput(side, not defState)
    log:log(Log.Level.INFO, "Triggered side " .. side .. " on relay " .. relayIdx)
    --Wait to trigger redstone
    local tTime = config:get("trigger_time")
    local start = os.clock()
    while os.clock() - start < tTime do
        coroutine.yield()
    end 
    relay.setOutput(side, defState)
end

--Advance trigger task timers
local function tickTasks()
    for i = #triggerTasks, 1, -1 do
        local task = triggerTasks[i]
        local suc, err = coroutine.resume(task)
        if(not suc) then
            log:log(Log.Level.ERROR, "Trigger task failed with err: " .. err)
            table.remove(triggerTasks, i)
        elseif(coroutine.status(task) == "dead") then
            table.remove(triggerTasks, i)
        end
    end
end

--Process rednet message
local function procRednet()
    while true do
        tickTasks()
        if(netCodeActive) then
            local req = stasisNetMgr:recv()
            if(req) then
                if(not req.cmd or not req.decoded) then
                    log:log(Log.Level.WARN, "Received invalid message from " .. req.id .. ": " .. textutils.serialize(req.data))
                --print("Received cmd '" .. req.cmd .. "' from " .. req.id .. " with data: " .. textutils.serialize(req.decoded))
                elseif(redNetCmd[req.cmd]) then
                    sleep(0.1) --Small delay so client doesn't immediately timeout while waiting for response
                    redNetCmd[req.cmd](req)
                else
                    log:log(Log.Level.WARN, "Received message with unknown cmd '" .. req.cmd .. "' from " .. req.id)
                    stasisNetMgr:send(req.id, 404, req.cmd, "Unknown command")
                end
            end
        else
            --Yield
            sleep(0.1)
        end
    end
end

--Process terminal input
local function procTerminal()
    while shouldRun do
        write(config:get("loc") .. "> ")
        local cmd = Util.split(read(), ' ') --Yields
        if(#cmd > 0) then
            local termCmd = terminalCmd[cmd[1]]
            if(termCmd) then
                if(termCmd.debug and not config:get("debug")) then
                    print("Debug cmds are disabled")
                else
                    termCmd.fn(cmd)
                end
            else
                print("Unknown command")
            end
        end
    end
end

--Rednet Cmd Callbacks

redNetCmd[Stasis_Proto.CMD.PING] = function(pckt)
    stasisNetMgr:send(pckt.id, 200, Stasis_Proto.CMD.PING, "pong")
end

redNetCmd[Stasis_Proto.CMD.INFO] = function(pckt)
    if(pckt.decoded.userID == nil) then
        stasisNetMgr:send(pckt.id, 400, Stasis_Proto.CMD.TP, "No user ID provided")
        return
    end
    local user = config:get("map")[pckt.decoded.userID]
    local status = "0"
    if(user ~= nil) then
        status = "1"
    end
    stasisNetMgr:send(pckt.id, 200, Stasis_Proto.CMD.INFO, config:get("loc"), status)
end

redNetCmd[Stasis_Proto.CMD.TP] = function(pckt)
    if(pckt.decoded.userID == nil) then
        stasisNetMgr:send(pckt.id, 400, Stasis_Proto.CMD.TP, "No user ID provided")
        return
    end
    local user = config:get("map")[pckt.decoded.userID]
    if(user == nil) then
        stasisNetMgr:send(pckt.id, 401, Stasis_Proto.CMD.TP, "User not set on node")
    else
        stasisNetMgr:send(pckt.id, 200, Stasis_Proto.CMD.TP, "Triggering")
        --Create coroutine so execution isnt paused
        local task = coroutine.create(function()
            triggerStasis(user.relayIdx, user.side)
        end)
        table.insert(triggerTasks, task)
    end
end

--Terminal Cmd Callbacks

terminalCmd["help"] = {
    fn = function(cmd)
        if(#cmd == 1) then
            print("Commands:")
            for name, cmd in pairs(terminalCmd) do
                --Only print enabled commands
                if(not cmd.debug or config:get("debug")) then
                    print(" " .. cmd.helpName)
                    print("  " .. cmd.helpStr)
                end
            end
        else
            local cmdHelp = terminalCmd[cmd[2]]
            if(not cmdHelp or (cmd.debug and not config:get("debug"))) then
                print("help: Unknown command '" .. cmd[2] .. "'")
            else
                print(" " .. cmdHelp.helpName)
                print("  " .. cmdHelp.helpStr)
            end
        end
    end,
    debug = false,
    helpName = "help {cmd}",
    helpStr = "Print cmd info",
}


terminalCmd["exit"] = {
    fn = function(cmd)
        shouldRun = false
    end,
    debug = false,
    helpName = "exit",
    helpStr = "Exit the program",
}

terminalCmd["set"] = {
    fn = function(cmd)
        if(#cmd < 4) then
            print("Invalid usage")
            print("Correct is", terminalCmd["set"].helpName)
            return
        end
        local userID = cmd[2]
        local side = cmd[3]
        local relayIdx = cmd[4]
        if(not Util.isSide(side)) then
            print("Invalid side")
            return
        end
        if(relay[relayIdx] == nil) then
            print("Invalid relay ID")
            return
        end
        local curSideUsr = sideToUsr(relayIdx, side)
        if(curSideUsr) then
            print("Side already registered to", curSideUsr)
            print("clear must be called on the user/side before set")
            return
        end
        log:log(log.Level.INFO, "Set " .. userID .. " to relay " .. relayIdx .. ", side " .. side)
        config.data["map"].value[userID] = { relayIdx = relayIdx, side = side }
        config:save()
    end,
    debug = false,
    helpName = "set [user_id] [side] [relay_id]",
    helpStr = "Sets a user ID to a relay/side"
}

terminalCmd["clear"] = {
    fn = function(cmd)
        if(#cmd < 3 or (#cmd < 3 and cmd[2] == "user") or (#cmd < 4 and cmd[2] == "side")) then
            print("Invalid usage, correct is " .. terminalCmd["clear"].helpName)
            return
        end
        if(cmd[2] == "side") then
            if(not Util.isSide(cmd[3])) then
                print("Invalid side")
                return
            end
            local relayIdx = cmd[4]
            if(relay[relayIdx] == nil) then
                print("Invalid relay ID")
                return
            end
            local curUsr = sideToUsr(relayIdx, cmd[3])
            if(curUsr) then
                config.data["map"].value[curUsr] = nil
                config:save()
                log:log(log.Level.INFO, "Relay " .. relayIdx .. ": Cleared side " .. cmd[3] .. " registered to " .. curUsr)
            end
        elseif(cmd[2] == "user") then
            config.data["map"].value[cmd[3]] = nil
            log:log(log.Level.INFO, "Cleared user " .. cmd[3])
            config:save()
        else
            print("Invalid usage, correct is " .. terminalCmd["clear"].helpName)
        end
    end,
    debug = false,
    helpName = "clear (user/side) [userID/side] {relay_id}",
    helpStr = "Clear a user or side mapping"
}

terminalCmd["save"] = {
    fn = function(cmd)
        config:save()
    end,
    debug = true,
    helpName = "save",
    helpStr = "Save config to disk"
}

terminalCmd["config"] = {
    fn = function(cmd)
        if(#cmd == 1) then
            print("Config:")
            for _, key in pairs(userConfigKeys) do
                print(" " .. key .. ": " .. tostring(config:get(key)))
            end
        elseif(#cmd < 4) then
            local key = cmd[2]
            local value = cmd[3]
            if(not Util.tableContains(userConfigKeys, key)) then
                print("Unknown config key '" .. key .. "'")
                return
            end
            if(value) then
                value = config:coerce(key, value)
                if(config:set(key, value)) then
                    config:save()
                    print("Set '" .. key .. "' to '" .. tostring(value) .. "'")
                else
                    print("Bad value")
                end
            else
                print(" " .. key .. ": " .. tostring(config:get(key)))
            end
        else
            print("Usage:")
            print(terminalCmd["config"].helpName)
        end
    end,
    debug = false,
    helpName = "config {key} {value}",
    helpStr = "View or set config values",
}

terminalCmd["map"] = {
    fn = function(cmd)
        print("Mappings:")
        printMappings(config:get("map"))
    end,
    debug = false,
    helpName = "map",
    helpStr = "Print user to relay/side mappings"
}

terminalCmd["relays"] = {
    fn = function(cmd)
        print("Relays:")
        for id, r in pairs(relay) do
            print(id)
        end
    end,
    debug = false,
    helpName = "rednet",
    helpStr = "Print available relays and their IDs"
}

terminalCmd["net"] = {
    fn = function(cmd)
        stasisNetMgr:host(config:get("loc"))
        netCodeActive = true
    end,
    debug = true,
    helpName = "net",
    helpStr = "Enable rednet"
}

terminalCmd["nonet"] = {
    fn = function(cmd)
        stasisNetMgr:unhost()
        netCodeActive = false
    end,
    debug = true,
    helpName = "nonet",
    helpStr = "Disable rednet"
}

--Main
--Make folder for data if NX
if(not fs.exists(dataDir)) then
    fs.makeDir(dataDir)
end

shell.setDir(appDir)

--Load Config
log:clear()
config:load()

--Set max id length
config:add("max_id_len", 20, "number")
--Timeout for net cmds
config:add("timeout", 1, "number")
--Time to trigger redtone relay for
--0.2 is min to trigger trapdoor
config:add("trigger_time", 0.2, "number")
--Enable debug commands
config:add("debug", false, "boolean")
--Map of users to relay
config:add("map", {}, "table")
--Default state of relay
--true will result in output flipping when computer is turned on
config:add("def_state", false, "boolean")
--Name of this location
if(not config:has("loc")) then
    write("Enter the name of this location: ")
    local maxLen = config:get("max_id_len")
    local nameUnique = false
    local name = nil
    while not nameUnique do
        name = read()
        if(#name == 0) then
        elseif(#name > maxLen) then
            print("Name is too long, max is " .. maxLen)
        elseif(not Util.isValidName(name)) then
            print("Name can't contain spaces, try again")
        elseif(nodeNameExists(name)) then
            print("Name already taken by another node, try again")
        elseif(#name ~= 0) then
            nameUnique = true
        end
    end
    config:set("loc", name, "string")
end

config:save()
stasisNetMgr.timeout = config:get("timeout")

--Main

print("Logged in to node '" .. config:get("loc") .. "'")

--Init Peripherals
if modem == nil then
    log:log(log.Level.FATAL, "Modem not found")
    print("Wireless Modem not found, can't start the stasis service")
    return
else
    rednet.open(peripheral.getName(modem))
    print("Rednet modem initialized on " .. peripheral.getName(modem))
end

if (wrappedRelay == nil) then
    log:log(log.Level.FATAL, "Redstone relay not found")
    print("Atleast one redstone relay is needed to start the stasis service")
    return
end

--Init Relays
for i, r in pairs(relay) do
    print("Initializing redstone_relay_" .. i)
    initRedstoneRelay(i, config:get("def_state"))
end

print("Current Mappings:")
printMappings(config:get("map"))

stasisNetMgr:host(config:get("loc"))
print("Hosting stasis service")
--Start Net and Cmd Threads
parallel.waitForAny(procRednet, procTerminal)

--Cleanup
stasisNetMgr:unhost()
print("Goodbye")