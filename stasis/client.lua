-- Copyright (c) 2026 treevar. All rights reserved.
-- Licensed under a modified MIT License <https://github.com/treevar/mc-cc/blob/main/LICENSE>
package.path = package.path .. ";/?.lua" --Properly find packages no matter location
--Imports
local Config = require("treevar.common.config")
local Log = require("treevar.common.log")
local Util = require("treevar.common.util")
local Stasis_Proto = require("stasis_proto")
local Proto_Manager = require("treevar.common.proto_manager")
--Peripherals
local modem = peripheral.find("modem", function(name, per) return per.isWireless() end) or nil
--Dirs
local appDir = "treevar/stasis"
local dataDir = appDir .. "/data"
--Instances
local log = Log:new(dataDir .. "/latest.log", Log.Level.DEBUG)
local config = Config:new(dataDir .. "/user.cfg", log)
local stasisNetMgr = Proto_Manager:new(Stasis_Proto, true, 1, log)
--Local settings
local shouldRun = true
--Contains info of nodes found
local nodes = {}
local nodeIDs = {}
--Commands
local terminalCmd = {}
local redNetCmd = {}
--User editable config
local userConfigKeys = {
    "user_id",
    "timeout",
    "show_unauthed",
}

--Print info about node
local function printNode(id)
    local n = nodes[id]
    if(not n) then
        return
    end
    --max id is 5 chars, auth is 1 char, 2 space chars, screen is 26 chars, so loc gets 18 chars
    print(Util.pad(n.id, 6) .. Util.shorten(Util.pad(n.loc, 19), 19) .. n.authed)
end

--Print all nodes with header
local function printNodes()
    print(Util.pad("ID", 6) .. Util.pad("Location", 14) .. "Authed")
    for _, id in pairs(nodeIDs) do
        if(config:get("show_unauthed") or nodes[id].authed == "1") then
            printNode(id)
        end
    end
end

--Pings node and rerturns if it responded
local function pingNode(id, timeout)
    stasisNetMgr:send(id, 200, Stasis_Proto.CMD.PING, "ping")
    local res = stasisNetMgr:recv(id)
    if(res.status == 200 and res.decoded == "pong") then
        return true
    end
    return false
end

--Get info from node and return it, returns nil if failed
local function queryNode(id, userID)
    --Need user id to see if we're authed
    if(not userID) then
        return "User ID not set, can't query"
    end
    stasisNetMgr:send(id, 200, Stasis_Proto.CMD.INFO, userID)
    local res = stasisNetMgr:recv(id)
    if (not res) then
        return "Timeout while waiting for response"
    end
    if(res.status ~= 200) then
        return "Error response from node: " .. res.data
    end

    if(not res.decoded.loc or not res.decoded.authed) then
        return "Invalid response from node"
    end
    return {id = id, loc = res.decoded.loc, authed = res.decoded.authed}
end

--Finds all nodes currently online and queries them
local function findNodes()
    nodes = {}
    nodeIDs = {}
    print("Searching...")
    local sNodes = { stasisNetMgr:lookup() }
    print("Found", #sNodes, "nodes")
    if(#sNodes == 0) then
        return
    end
    write("Querying nodes...")
    for _, nID in pairs(sNodes) do
        local node = queryNode(nID, config:get("user_id"))
        if(type(node) == "table") then
            nodes[nID] = node
            table.insert(nodeIDs, nID)
            write('.')
        elseif(type(node) == "string") then
            write('x')
            log:log(Log.Level.WARN, "Failed to query node " .. nID .. ": " .. node)
        else
        end
    end
    table.sort(nodeIDs)
    print("")
    printNodes()
end

--Resolve id/location to node
--Prioritizes ID over name
local function resolveNode(input)
    local id = tonumber(input)
    --Check ID first
    if(id ~= nil) then
        if(nodes[id] ~= nil) then
            return nodes[id]
        end
    end
    --Check loc if ID wasnt found
    for nID, n in pairs(nodes) do
        if(n.loc == input) then
            return n
        end
    end
    return nil
end

--Handle terminal input
local function handleInput(input)
    if(#input == 0) then
        return
    end
    local cmd = input[1]
    local tCmd = terminalCmd[cmd]
    --Hide admin commands from non admins
    if(tCmd and (not tCmd.admin or config:has("admin"))) then
        tCmd.fn(input)
    else
        print("Unknown command")
    end
end

--Terminal Cmd Callbacks
terminalCmd["exit"] = {
    fn = function(cmd)
        shouldRun = false
    end,
    helpName = "exit",
    helpStr = "Exit gracefully",
}

terminalCmd["nodes"] = {
    fn = function(cmd)
        findNodes()
    end,
    helpName = "nodes",
    helpStr = "Search for nodes",
}

terminalCmd["list"] = {
    fn = function(cmd)
        printNodes()
    end,
    helpName = "list",
    helpStr = "List found nodes"
}

terminalCmd["tp"] = {
    fn = function(cmd)
        if(#cmd < 2) then
            print("Usage:")
            print(terminalCmd["tp"].helpName)
            return
        end
        local node = resolveNode(cmd[2])
        if(not node) then
            print("Node not found")
            return
        end
        if(node.authed ~= "1") then
            print("Node not authed")
            return
        end
        stasisNetMgr:send(node.id, 200, Stasis_Proto.CMD.TP, config:get("user_id"))
        local res = stasisNetMgr:recv(node.id)
        if(not res or res.status ~= 200) then
            print("Failed to teleport")
        end
    end,
    helpName = "tp [node_id/location]",
    helpStr = "TP to a node",
}

--Admin CMD
terminalCmd["tpas"] = {
    fn = function(cmd)
        if(not config:has("admin")) then
            return
        end
        if(#cmd < 3) then
            print("Usage:")
            print(terminalCmd["tpas"].helpName)
            return
        end
        local node = resolveNode(cmd[2])
        if(not node) then
            print("Node not found")
            return
        end
        stasisNetMgr:send(node.id, 200, Stasis_Proto.CMD.TP, cmd[3])
        local res = stasisNetMgr:recv(node.id)
        if(not res) then
            print("Failed to teleport")
        elseif(res.status ~= 200) then
            print(res.data)
        else
            print("Teleported " .. cmd[3] .. " to " .. node.loc)
        end
    end,
    helpName = "tpas [node_id/location] [user_id]",
    helpStr = "TP another user to a node",
}

terminalCmd["ping"] = {
    fn = function(cmd)
        if(#cmd < 2) then
            print("Usage:")
            print(terminalCmd["ping"].helpName)
            return
        end
        local node = resolveNode(cmd[2])
        if(not node) then
            print("Node not found")
            return
        end
        if(pingNode(node.id)) then
            print("Node [" .. node.id .. "] " .. node.loc .. " is online")
        else
            print("Node [" .. node.id .. "] " .. node.loc .. " is offline")
        end
    end,
    hide = true,
    helpName = "ping [node_id/location]",
    helpStr = "Ping a node",
}

terminalCmd["help"] = {
    fn = function(cmd)
        if(#cmd == 1) then
            print("Commands:")
            for name, cmd in pairs(terminalCmd) do
                --Only print enabled commands
                if(not cmd.admin or config:get("admin")) then
                    print(" " .. cmd.helpName)
                    print("  " .. cmd.helpStr)
                end
            end
        else
            local cmdHelp = terminalCmd[cmd[2]]
            if(not cmdHelp or (cmd.admin and not config:has("admin"))) then
                print("help: Unknown command '" .. cmd[2] .. "'")
            else
                print(" " .. cmdHelp.helpName)
                print("  " .. cmdHelp.helpStr)
            end
        end
    end,
    helpName = "help {cmd}",
    helpStr = "Print cmd info",
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
                if(config:set(key, value)) then
                    config:save()
                    print("Set '" .. key .. "' to '" .. value .. "'")
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
    helpName = "config {key} {value}",
    helpStr = "View or set config values",
}


--Main

if(not fs.exists(dataDir)) then
    fs.makeDir(dataDir)
end

shell.setDir(appDir)

log:clear()
config:load()

--Init Peripherals
if modem == nil then
    log:log(log.Level.FATAL, "Modem not found")
    print("Install a modem with 'equip' while a modem is in your inventory")
    return
else
    rednet.open(peripheral.getName(modem))
end

if(not config:has("timeout")) then
    config:set("timeout", 2, "number")
end

if(not config:has("show_unauthed")) then
    config:set("show_unauthed", true, "boolean")
end

if(not config:has("max_id_len")) then
    config:set("max_id_len", 20, "number")
end

if(not config:has("user_id")) then
    write("Enter your user ID: ")
    local maxLen = config:get("max_id_len")
    local nameGood = false
    local userID = nil
    while not nameGood do
        userID = read()
        if(#userID == 0) then
        elseif(#userID > maxLen) then
            print("Name is too long, max is " .. maxLen)
        elseif(not Util.isValidName(userID)) then
            print("User ID can't contain spaces, try again")
        else
            nameGood = true
        end
    end
    config:set("user_id", userID, "string")
end

config:save()

stasisNetMgr.timeout = config:get("timeout")

print("Logged in as", config:get("user_id"))
findNodes()

while shouldRun do
    write("sc> ")
    handleInput(Util.split(read(), ' '))
end