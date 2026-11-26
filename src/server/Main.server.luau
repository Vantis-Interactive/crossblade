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

local modules = Loader.RequireChildren(script.Parent.Services)
table.insert(modules, require(script.Parent.Core.Net) :: any)

local started = os.clock()
Loader.Boot(modules, {
	OnStartError = function(name, err)
		log:Error(`{name}.Start failed`, { error = err })
	end,
})
log:Info("server booted", { modules = #modules, ms = math.floor((os.clock() - started) * 1000) })
