--!strict
--[[
	Server entry point. Boots Core and Services through the shared Loader (dependency-ordered Init,
	then Start). Any Init failure aborts boot loudly rather than running a half-wired server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage.Shared.Util.Loader)
local Logger = require(ReplicatedStorage.Shared.Util.Logger)

local log = Logger.new("Boot")

-- Spawning is owned by SpawnService (also set in default.project.json).
Players.CharacterAutoLoads = false

local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)

-- Services may declare Roles = { "Hub" } / { "Arena" }; services without Roles run everywhere.
local modules = {}
for _, module in Loader.RequireChildren(script.Parent.Services) do
	local roles = (module :: any).Roles
	if roles == nil or table.find(roles, PlaceConfig.Role) then
		table.insert(modules, module)
	end
end
table.insert(modules, require(script.Parent.Core.Net) :: any)

local started = os.clock()
Loader.Boot(modules, {
	OnStartError = function(name, err)
		log:Error(`{name}.Start failed`, { error = err })
	end,
})
log:Info("server booted", {
	role = PlaceConfig.Role,
	mode = PlaceConfig.Mode,
	modules = #modules,
	ms = math.floor((os.clock() - started) * 1000),
})
