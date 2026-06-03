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
local silent = false
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
        elseif(arg == "silent") then
            silent = true
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

--Write if not silent
local function writeb(...)
    if(not silent) then
        write(...)
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
    "common/cmd_manager.lua",
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
    writeb("[" .. i .. "/" .. #filesNeeded .. "] Fetching '" .. fileName .. "' ")
    if(not loader:get(fileName)) then
        table.insert(fails, fileName)
        writeb("FAIL\n")
    else
        writeb("OK\n")
    end
end

if(#fails > 0) then
    writeb("Failled to fetch " .. #fails .. "/" .. #filesNeeded .. " files\n")
    for _, fileName in pairs(fails) do
        writeb("X ")
        writeb(fileName)
        writeb("\n")
    end
    return
end

--Copy this to stasis dir for updates
if(not fs.exists("treevar/stasis/installer.lua")) then
    fs.copy(shell.getRunningProgram(), "treevar/stasis/installer.lua")
end

--Prepend dir to get actual entry point path
if(loader.dir ~= nil) then
    entryPoint = loader.dir .. "/" .. entryPoint
end

--Create startup file
if(createStartup) then
    writeb("Creating startup file\n")
    --Create startup folder if NX
    if(not fs.exists("/startup")) then
        fs.makeDir("/startup")
    end
    local startFile = fs.open("/startup/stasis_loader.lua", "w")
    startFile.write("local retVal = \"restart\"\n")
    startFile.write("while(retVal == \"restart\") do\n")
    startFile.write("local stasis = loadfile(\"" .. entryPoint .. "\")\n")
    startFile.write("setfenv(stasis, getfenv())\n")
    startFile.write("retVal = stasis()\n")
    startFile.write("end\n")
    startFile.close()
end

--Move config if it exists
if(fs.exists("stasis/data/user.cfg")) then
    fs.copy("stasis/data/user.cfg", "treevar/stasis/data/user.cfg")
    writeb("Moved config to new location\n")
end

writeb("Done\n")

--Execute program
if(runAfterInstall) then
    if(createStartup) then
        shell.run("/startup/stasis_loader.lua")
    else
        shell.run(entryPoint)
    end
end