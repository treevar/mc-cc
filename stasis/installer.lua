-- Copyright (c) 2026 treevar. All rights reserved.
-- Licensed under a modified MIT License <https://github.com/treevar/mc-cc/blob/main/LICENSE>
--Stasis Installer
package.path = package.path .. ";/?.lua"
--Process args
local args = { ... }
local ghCfg = {
    user = "treevar",
    repo = "mc-cc",
    branch = "main",
}
local isClient = nil
local createStartup = true
local runAfterInstall = false
if(#args > 0) then
    for _, arg in pairs(args) do
        if(arg == "nostartup") then
            createStartup = false
        elseif(arg == "run") then
            runAfterInstall = true
        elseif(arg == "node") then
            isClient = false
        elseif(arg == "client") then
            isClient = true
        end
    end 
end

if(isClient == nil) then
    if(pocket) then
        isClient = true
    else
        isClient = false
    end
end

--Load GitHub Loader
--URL for GitHub Loader package
local url = "https://raw.githubusercontent.com/" .. ghCfg.user .. "/" .. ghCfg.repo .. "/refs/heads/" .. ghCfg.branch .. "/common/gh_loader.lua"
local response = http.get(url)

if not response then
    error("Failed to download gh_loader from GitHub!")
end

local content = response.readAll()
response.close()

if(not fs.exists(ghCfg.user)) then
    fs.makeDir(ghCfg.user)
end

if(not fs.exists(fs.combine(ghCfg.user, "common"))) then
    fs.makeDir(fs.combine(ghCfg.user, "common"))
end

local file = fs.open(fs.combine(ghCfg.user, "common/gh_loader.lua"), "w")
file.write(content)
file.close()

local Github = require("treevar.common.gh_loader")
local loader = Github:new(ghCfg.user, ghCfg.repo, ghCfg.branch)
loader.dir = ghCfg.user --Save all files to treevar folder to avoid cluttering root and to allow easy deletion of all files by deleting the folder

local filesNeeded = {
    "common/config.lua",
    "common/log.lua",
    "common/proto_manager.lua",
    "common/util.lua",
    "stasis/stasis_proto.lua"
}

--Add proper entry point file
local entryPoint = ""

if(isClient) then 
    entryPoint = "stasis/client.lua"
else
    entryPoint = "stasis/node.lua"
end

table.insert(filesNeeded, entryPoint)

--Fetch files
local fails = {}
for i, fileName in pairs(filesNeeded) do
    write("[" .. i .. "/" .. #filesNeeded .. "] Fetching '" .. fileName .. "' ")
    if(not loader:get(fileName)) then
        table.insert(fails, fileName)
        write("FAIL\n")
    else
        write("OK\n")
    end
end

if(#fails > 0) then
    print("Failled to fetch " .. #fails .. "/" .. #filesNeeded .. " files")
    for _, fileName in pairs(fails) do
        write("X ")
        print(fileName)
    end
    return
end

--Prepend dir to get actual entry point path
if(loader.dir ~= nil) then
    entryPoint = loader.dir .. "/" .. entryPoint
end

--Create startup file
if(createStartup) then
    print("Creating startup file")
    --Create startup folder if NX
    if(not fs.exists("/startup")) then
        fs.makeDir("/startup")
    end
    local startFile = fs.open("/startup/stasis_loader.lua", "w")
    startFile.write("shell.run(\"" .. entryPoint .. "\")")
    startFile.close()
end

--Move config if it exists
if(fs.exists("stasis/data/user.cfg")) then
    fs.copy("stasis/data/user.cfg", "treevar/stasis/data/user.cfg")
    print("Moved config to new location")
end

print("Done")

--Execute program
if(runAfterInstall) then
    shell.run(entryPoint)
end