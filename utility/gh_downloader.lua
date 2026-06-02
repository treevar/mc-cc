package.path = package.path .. ";/?.lua"

local Github = require("treevar.common.gh_loader")
local Util = require("treevar.common.util")

local loader = Github:new("treevar", "mc-cc", "main")

local userIn = nil

local shouldRun = true

print("[GH fileName] {local file}")

while shouldRun do
    userIn = Util.prompt("Enter file: ")
    if(userIn == "..") then --Not allowed in url, so it can safely be used to exit
        shouldRun = false
    else
        print("Fetching...")
        local args = Util.split(userIn, ' ')
        if(not loader:get(args[1], args[2])) then
            print("Unable to fetch file")
        else
            print("OK")
        end
    end
end