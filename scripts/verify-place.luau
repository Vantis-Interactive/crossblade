--!nocheck
--[[
	Structural smoke test of the Rojo-built place file:  lune run scripts/verify-place build/crossblade.rbxl
	Deserializes the place with Lune's Roblox library and asserts the instance tree and service
	properties that the game depends on at runtime.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local path = process.args[1] or "build/crossblade.rbxl"
local game = roblox.deserializePlace(fs.readFile(path))
local failures = {}

local function find(pathString)
	local node = game
	for _, name in string.split(pathString, ".") do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function expectClass(pathString, className)
	local node = find(pathString)
	if node == nil then
		table.insert(failures, `missing {pathString}`)
	elseif node.ClassName ~= className then
		table.insert(failures, `{pathString} is {node.ClassName}, expected {className}`)
	end
end

expectClass("ReplicatedStorage.Shared", "Folder")
expectClass("ReplicatedStorage.Shared.Config", "ModuleScript")
expectClass("ReplicatedStorage.Shared.Config.Weapons.Archetypes", "ModuleScript")
expectClass("ReplicatedStorage.Shared.Net.Contracts", "ModuleScript")
expectClass("ServerScriptService.Server.Main", "Script")
expectClass("ServerScriptService.Server.Core.Net", "ModuleScript")
expectClass("ServerScriptService.Server.Services.CombatService", "ModuleScript")
expectClass("StarterPlayer.StarterPlayerScripts.Client.Main", "LocalScript")
expectClass("StarterPlayer.StarterPlayerScripts.Client.Controllers.HUDController", "ModuleScript")
expectClass("StarterPlayer.StarterCharacterScripts.Health", "Script")

local players = game:GetService("Players")
if players.CharacterAutoLoads ~= false then
	table.insert(failures, "Players.CharacterAutoLoads must be false (SpawnService owns spawning)")
end

-- No Script/LocalScript may live under ReplicatedStorage, and no server code may replicate.
for _, descendant in game:GetService("ReplicatedStorage"):GetDescendants() do
	if descendant.ClassName == "Script" or descendant.ClassName == "LocalScript" then
		table.insert(failures, `executable script in ReplicatedStorage: {descendant:GetFullName()}`)
	end
end

local REQUIRED_SERVICES = {
	"AmmunitionService",
	"AntiCheatService",
	"AuditService",
	"CombatService",
	"CrateService",
	"DamageService",
	"EconomyService",
	"HealthService",
	"InventoryService",
	"MapService",
	"MatchService",
	"PickupService",
	"PlayerDataService",
	"PolicyComplianceService",
	"ProgressionService",
	"ProjectileService",
	"SpawnService",
	"WeaponService",
}
for _, name in REQUIRED_SERVICES do
	expectClass("ServerScriptService.Server.Services." .. name, "ModuleScript")
end
local count = #REQUIRED_SERVICES

if #failures > 0 then
	for _, failure in failures do
		print("FAIL  " .. failure)
	end
	process.exit(1)
end
print(`place structure OK ({count} server services) - {path}`)
