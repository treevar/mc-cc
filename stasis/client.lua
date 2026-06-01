-- Copyright (c) 2026 treevar. All rights reserved.
-- Licensed under a modified MIT License <https://github.com/treevar/mc-cc/blob/main/LICENSE>
package.path = package.path .. ";/?.lua" --Properly find packages no matter location
--Imports
local Config = require("common.config")
local Log = require("common.log")
local Util = require("common.util")
local Stasis_Proto = require("stasis_proto")
local Proto_Manager = require("common.proto_manager")
--Peripherals
local modem = peripheral.find("modem", function(name, per) return per.isWireless() end) or nil
--Dirs
local appDir = "/stasis"
local dataDir = appDir .. "/data"
--Instances
local log = Log:new(dataDir .. "/latest.log", Log.Level.DEBUG)
local config = Config:new(dataDir .. "/user.cfg", log)
local stasisNetMgr = Proto_Manager:new(Stasis_Proto, true, 1, log)
--Local settings
local shouldRun = true
--Contains info of nodes found
local nodes = {}
--Commands
local terminalCmd = {}
local redNetCmd = {}

--Print info about node
local function printNode(id)
    local n = nodes[id]
    if(not n) then
        return
    end
    print(n.id .. ": '" .. n.loc .. "' " .. n.authed)
end

--Print all nodes with header
local function printNodes(nodes)
    print("ID  Loc  Authed")
    for id, n in pairs(nodes) do
        printNode(id)
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
            write('.')
        elseif(type(node) == "string") then
            write('x')
            log:log(Log.Level.WARN, "Failed to query node " .. nID .. ": " .. node)
        else
        end
    end
    print("")
    printNodes(nodes)
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
    if(terminalCmd[cmd]) then
        terminalCmd[cmd](input)
    else
        print("Unknown command")
    end
end

--Terminal Cmd Callbacks
terminalCmd["exit"] = function(cmd)
    shouldRun = false
end

terminalCmd["nodes"] = function(cmd)
    findNodes()
end

terminalCmd["list"] = function(cmd)
    printNodes(nodes)
end

terminalCmd["tp"] = function(cmd)
    if(#cmd < 2) then
        print("Usage:")
        print("tp [node_id/location]")
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
end

--Admin CMD
terminalCmd["tpas"] = function(cmd)
    if(not config:has("admin")) then
        return
    end
    if(#cmd < 3) then
        print("Usage:")
        print("tpas [node_id/location] [user_id]")
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
end

terminalCmd["ping"] = function(cmd)
    if(#cmd < 2) then
        print("Usage:")
        print("ping [node_id/location]")
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
end

terminalCmd["help"] = function(cmd)
    print("Commands:")
    print(" nodes \n  Search for nodes")
    print(" list \n  List found nodes")
    print(" tp [node_id/location] \n  Teleport to node")
    print(" ping [node_id/location] \n  Ping node")
    print(" exit \n  Exit the program")
    print(" help \n  Show this message")
end


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
    config:set("user_id", userID)
end

if(not config:has("timeout")) then
    config:set("timeout", 2)
end

if(not config:has("max_id_len")) then
    config:set("max_id_len", 20)
end

config:save()

stasisNetMgr.timeout = config:get("timeout")

print("Logged in as", config:get("user_id"))
findNodes()

while shouldRun do
    write("sc> ")
    handleInput(Util.split(read(), ' '))
end