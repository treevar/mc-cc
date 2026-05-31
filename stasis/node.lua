-- Copyright (c) 2026 treevar. All rights reserved.
-- Licensed under a modified MIT License <https://github.com/treevar/mc-cc/blob/main/LICENSE>
package.path = package.path .. ";/?.lua"
local Util = require("common.util")
local Config = require("common.config")
local Log = require("common.log")
local Stasis_Proto = require("stasis_proto")
local Proto_Manager = require("common.proto_manager")

local modem = peripheral.find("modem", function(name, peripheral) return peripheral.isWireless() end)
local relay = {}
local wrappedRelay = peripheral.find("redstone_relay", function(name, r)
    if(Util.isSide(name)) then
        relay[name] = r
    else
        local idx = string.sub(name, #"redstone_relay_" + 1, #name)
        relay[idx] = r
    end
    return true
end)

local appDir = "/stasis"
local dataDir = appDir .. "/data"

local log = Log:new(dataDir .. "/latest.log", Log.Level.DEBUG)
local config = Config:new(dataDir .. "/user.cfg", log)
local stasisNetMgr = Proto_Manager:new(Stasis_Proto, false, 1, log)

local redNetCmd = {}
local terminalCmd = {}

local triggerTasks = {}

local netCodeActive = true
local shouldRun = true

local function sideToUsr(relayIdx, side)
    if(Util.isSide(side)) then
        for key, value in pairs(config:get("map")) do
            if(value.relayIdx ~= relayIdx) then
                return nil
            end
            if(value.side == side) then 
                return key
            end
        end
    end
    return nil
end

local function initRedstoneRelay(relayIdx, state)
    r = relay[relayIdx]
    if (relay == nil) then
        log:log(log.Level.WARN, "Attempted to initialize nonexistant relay index", tostring(relayIdx))
        return
    end
    r.setOutput("top", state)
    r.setOutput("bottom", state)
    r.setOutput("left", state)
    r.setOutput("right", state)
    r.setOutput("front", state)
    r.setOutput("back", state)
    log:log(log.Level.INFO, "Initialized relay index", relayIdx, "to state", state)
end

local function nodeNameExists(name)
    local node = stasisNetMgr:lookup(name)
    if(node) then
        log:log(Log.Level.DEBUG, "Found existing node with name '" .. name .. "' at ID " .. node)
        return true
    end
    return false
end

local function printMappings(map)
    print("User   Relay Side")
    for k, v in pairs(map) do
        print(k .. " " .. v.relayIdx .. "     " .. v.side)
    end
end

--Pulse stasis
local function triggerStasis(relayIdx, side)
    local relay = relay[relayIdx]
    if(relay == nil) then
        log:log(Log.Level.WARN, "Attempted to trigger nonexistant relay index " .. relayIdx)
        return
    end
    local defState = config:get("def_state")
    relay.setOutput(side, not defState)
    log:log(Log.Level.INFO, "Triggered side", side, "on relay", relayIdx)
    --Wait to trigger redstone
    local tTime = config:get("trigger_time")
    local start = os.clock()
    while os.clock() - start < tTime do
        coroutine.yield()
    end 
    relay.setOutput(side, defState)
end

local function tickTasks()
    for i = #triggerTasks, 1, -1 do
        local task = triggerTasks[i]
        local suc, err = coroutine.resume(task)
        if(not suc) then
            log:log(Log.Level.ERROR, "Trigger task failed with err:", err)
            table.remove(triggerTasks, i)
        elseif(coroutine.status(task) == "dead") then
            table.remove(triggerTasks, i)
        end
    end
end

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

local function procTerminal()
    while shouldRun do
        write(config:get("loc") .. "> ")
        local cmd = Util.split(read(), ' ') --Yields
        if(#cmd > 0) then
            if(terminalCmd[cmd[1]]) then
                terminalCmd[cmd[1]](cmd)
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
    --print("Received INFO cmd with data: " .. textutils.serialize(pckt))
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

terminalCmd["help"] = function(cmd)
    print("Commands:")
    print(" exit \n  Exit the program")
    print(" set [userID] [side] [relay Idx] \n  Set a user ID to a relay and side")
    print(" clear (user/side) [userID/side] [relay idx if side] \n  Clear a user or side mapping")
    print(" save \n  Save config to disk")
    print(" config [key] {value} \n  Get or set config values")
    print(" map \n  Print user to relay/side mappings")
    print(" relays \n  Print available relays and their indexes")
end


terminalCmd["exit"] = function(cmd)
    shouldRun = false
end

terminalCmd["set"] = function(cmd)
    if(#cmd < 4) then
        print("Invalid usage, correct is set [userID] [side] [relay Idx]")
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
        print("Invalid relay index")
        return
    end
    local curSideUsr = sideToUsr(relayIdx, side)
    if(curSideUsr) then
        print("Side already registered to ", curSideUsr)
        print("clear must be called on the user/side before set")
        return
    end
    log:log(log.Level.INFO, "Set " .. userID .. " to relay " .. relayIdx .. ", side " .. side)
    config:get("map")[userID] = { relayIdx = relayIdx, side = side }
    config:save()
end

terminalCmd["clear"] = function(cmd)
    if(#cmd < 2 or (#cmd < 3 and cmd[2] == "user") or (#cmd < 4 and cmd[2] == "side")) then
        print("Invalid usage, correct is clear (user/side) [user/side] [relay idx if side]")
        return
    end
    if(cmd[2] == "side") then
        if(not Util.isSide(cmd[3])) then
            print("Invalid side")
            return
        end
        local relayIdx = cmd[4]
        if(relay[relayIdx] == nil) then
            print("Invalid relay index")
            return
        end
        local curUsr = sideToUsr(relayIdx, cmd[3])
        if(curUsr) then
            config:get("map")[curUsr] = nil
            config:save()
            log:log(log.Level.INFO, "Relay " .. relayIdx .. ": Cleared side " .. cmd[3] .. " registered to " .. curUsr)
        end
    else --User
        config:get("map")[cmd[3]] = nil
        log:log(log.Level.INFO, "Cleared user " .. cmd[3])
        config:save()
    end
end

terminalCmd["save"] = function(cmd)
    config:save()
end

terminalCmd["config"] = function(cmd)
    if(#cmd == 1) then
        print("Config:")
        print(textutils.serialise(config.data))
        return
    end
    local key = cmd[2]
    if(#cmd == 3) then
        local value = cmd[3]
        config:set(key, value)
    else
        print("Value: ", config:get(key))
    end
end

terminalCmd["map"] = function(cmd)
    print("Mappings:")
    printMappings(config:get("map"))
end

terminalCmd["relays"] = function(cmd)
    print("Relays:")
    for idx, r in pairs(relay) do
        print(idx)
    end
end

terminalCmd["net"] = function(cmd)
    stasisNetMgr:host(config:get("loc"))
    netCodeActive = true
end

terminalCmd["nonet"] = function(cmd)
    stasisNetMgr:unhost()
    netCodeActive = false
end

--Main

if(not fs.exists(dataDir)) then
    fs.makeDir(dataDir)
end

shell.setDir(appDir)

--Load Config
log:clear()
config:load()

if(not config:has("loc")) then
    write("Enter the name of this location: ")
    local nameUnique = false
    local name = nil
    while not nameUnique do
        name = read()
        if(not Util.isValidName(name)) then
            print("Name can't contain spaces, try again")
        elseif(nodeNameExists(name)) then
            print("Name already taken by another node, try again")
        elseif(#name ~= 0) then
            nameUnique = true
        end
    end
    config:set("loc", name)
end

if(not config:has("map")) then
    config:set("map", {})
end

if(not config:has("def_state")) then
    config:set("def_state", false)
end

if(not config:has("timeout")) then
    config:set("timeout", 1)
end

if(not config:has("trigger_time")) then
    config:set("trigger_time", 0.2)
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