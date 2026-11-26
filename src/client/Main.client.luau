--!strict
-- Client entry point: boots every controller through the shared Loader.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage.Shared.Util.Loader)

local modules = Loader.RequireChildren(script.Parent.Controllers)
Loader.Boot(modules, {
	OnStartError = function(name, err)
		warn(`[Client] {name}.Start failed: {err}`)
	end,
})
