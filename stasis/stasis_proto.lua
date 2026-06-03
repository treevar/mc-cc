-- Copyright (c) 2026 treevar. All rights reserved.
-- Licensed under a modified MIT License <https://github.com/treevar/mc-cc/blob/main/LICENSE>
--Follows standard proto structure
Stasis_Proto = {
    CLIENT_PROTO = "stasis_res",
    SERVER_PROTO = "stasis",
    VERSION = "1",
    CMD = {
        PING = "ping", --Ping node, returns pong
        INFO = "info", --Get info about node, returns location and if authed
        TP = "tp", --Teleport to node
        UPDATE = "update", --Redownload files to node
    },
}

Stasis_Proto.decoders = { --Functions to decode each cmd type, returns decoded data or nil if failed
    [Stasis_Proto.CMD.PING] = {
        allowedStatus = {200},
        fn = function(isClient, pckt) return pckt.data end
    },
    [Stasis_Proto.CMD.TP] = {
        allowedStatus = {200},
        fn = function(isClient, pckt) 
            if(isClient) then
                return pckt.data
            end
            return {userID = pckt.data} 
        end
    },
    [Stasis_Proto.CMD.INFO] = {
        allowedStatus = {200},
        fn = function(isClient, pckt) 
            if(isClient) then
                if(not pckt.data.loc or not pckt.data.authed) then
                    return nil
                end
                return { loc = pckt.data.loc, authed = pckt.data.authed }
            end
            return {userID = pckt.data}
        end
    },
    [Stasis_Proto.CMD.UPDATE] = {
        allowedStatus = {200},
        fn = function(isClient, pckt) return pckt.data end
    },
}

Stasis_Proto.encoders = { --Functions to encode data for each cmd type, returns nil if failed
    [Stasis_Proto.CMD.PING] = {
        allowedStatus = {200},
        fn = function(isClient, data) return data[1] end
    },
    [Stasis_Proto.CMD.TP] = {
        allowedStatus = {200},
        fn = function(isClient, data) return data[1] end
    },
    [Stasis_Proto.CMD.INFO] = {
        allowedStatus = {200},
        fn = function(isClient, data)
            if(not isClient) then
                local loc = data[1]
                local authed = data[2]
                if(not loc or not authed) then
                    return nil
                end
                return {loc = loc, authed = authed}
            else
                return data[1] --User ID
            end
        end
    },
    [Stasis_Proto.CMD.UPDATE] = {
        allowedStatus = {200},
        fn = function(isClient, data) return data[1] end
    },
}

return Stasis_Proto