-- Copyright (c) 2026 treevar. All rights reserved.
-- Licensed under a modified MIT License <https://github.com/treevar/mc-cc/blob/main/LICENSE>
local Log = require("treevar.common.log")
Proto_Manager = {PROTO = nil, _isClient = nil, timeout = 2, logger = nil}

local function statusAllowed(status, allowed)
    for _, s in pairs(allowed) do
        if(s == status) then
            return true
        end
    end
    return false
end

function Proto_Manager:new(proto, isClient, timeout, logger)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.PROTO = proto
    o._isClient = isClient
    o.timeout = timeout
    o.logger = logger
    return o
end

function Proto_Manager:_log(level, ...)
    if self.logger then
        self.logger:log(level, "Proto:", ...)
    end
end

--Appends version to proto and returns it
--This is the actual protocol used on rednet
--if isClient is true then the client proto is returned, else the server proto is
--if isClient is nil then self._isClient is used
function Proto_Manager:getProtoString(isClient)
    if(isClient == nil) then
        isClient = self._isClient
    end
    local proto = self.PROTO.SERVER_PROTO
    if(isClient) then
        proto = self.PROTO.CLIENT_PROTO
    end
    return proto .. self.PROTO.VERSION
end

function Proto_Manager:decode(pckt)
    if(not pckt or not pckt.cmd or not pckt.status or not pckt.id) then
        self:_log(Log.Level.WARN, "Invalid packet to decode: " .. textutils.serialize(pckt))
    end

    local decoder = self.PROTO.decoders[pckt.cmd]
    if(not decoder or not decoder.fn) then
        self:_log(Log.Level.WARN, "No decoder for cmd " .. pckt.cmd)
        return nil
    end

    if(not statusAllowed(pckt.status, decoder.allowedStatus)) then
        if(pckt.data == nil) then
            return tostring(pckt.status)
        else
            return pckt.data
        end
    end
    
    local decoded = decoder.fn(self._isClient, pckt)
    if(decoded == nil) then
        self:_log(Log.Level.WARN, "Invalid data for cmd " .. pckt.cmd .. ": " .. textutils.serialize(pckt.data))
    end
    return decoded
end

function Proto_Manager:encode(cmd, status, dat)
    if(not cmd) then
        self:_log(Log.Level.WARN, "Tried to encode nil cmd")
        return nil
    end
    local encoder = self.PROTO.encoders[cmd]
    if(not encoder or not encoder.fn) then
        self:_log(Log.Level.WARN, "No encoder for cmd " .. cmd)
        return nil
    end
    if(not statusAllowed(status, encoder.allowedStatus)) then --Error status, just return data as is (if it exists) or status as string if not
        if(dat == nil) then
            return tostring(status)
        else
            if(type(dat) == "table") then
                return dat[1]
            elseif(type(dat) == "string" or type(dat) == "number") then
                return dat
            else
                self:_log(Log.Level.WARN, "Tried to encode non-string/number/table data with status " .. status .. ": " .. textutils.serialize(dat))
                return tostring(status)
            end
        end
    end
    
    return encoder.fn(self._isClient, dat)
end

--Sends a packet to a machine, cmd is the command type, ... is the data to encode for that command (varies by cmd)
function Proto_Manager:send(id, status, cmd, ...)
    if(not id or not cmd or not status) then
        self:_log(Log.Level.WARN, "Tried to send message with nil id/cmd/status: " .. textutils.serialize({id, cmd, status}))
        return false
    end
    local dat = { ... }
    local encoded = self:encode(cmd, status, dat)
    local sendMsg = { cmd = cmd, status = status, data = encoded }
    local proto = self:getProtoString(not self._isClient) --Inverse because we need to send to the other proto
    rednet.send(id, sendMsg, proto)
    self:_log(Log.Level.DEBUG, "Sent message with proto " .. proto .. " to " .. id .. ": " .. textutils.serialize(sendMsg))
    return true
end

--Receive a packet, returns decoded data or nil if failed
function Proto_Manager:recv(expectID)
    local proto = self:getProtoString()
    local id, pckt = rednet.receive(proto, self.timeout)
    if(id ~= nil) then
        self:_log(Log.Level.DEBUG, "Received message with proto " .. proto .. " from " .. id .. ": " .. textutils.serialize(pckt or "nil"))
    end
    
    if(not id or not pckt or (expectID and id ~= expectID)) then
        return nil
    end

    if(pckt.status == nil or pckt.cmd == nil) then
        return nil
    end

    --Attach ID to pckt so decoders can use it if needed
    pckt.id = id

    local res = {id = id, status = pckt.status, cmd = pckt.cmd, data = pckt.data, decoded = self:decode(pckt)}
    return res
end

function Proto_Manager:host(hostname)
    --Clients shouldnt be hosting, so force to server proto
    local proto = self:getProtoString(false)
    rednet.host(proto, hostname)
end

function Proto_Manager:unhost()
    local proto = self:getProtoString(false)
    rednet.unhost(proto)
end

--Lookup devices hosting the server protocol
function Proto_Manager:lookup(host)
    local proto = self:getProtoString(false)
    return rednet.lookup(proto, host)
end

return Proto_Manager