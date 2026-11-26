--!strict
-- Client entry point: boots every controller through the shared Loader.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage.Shared.Util.Loader)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)

-- Controllers may declare Roles = { "Hub" }; controllers without Roles run in every place.
local modules = {}
for _, module in Loader.RequireChildren(script.Parent.Controllers) do
	local roles = (module :: any).Roles
	if roles == nil or table.find(roles, PlaceConfig.Role) then
		table.insert(modules, module)
	end
end
Loader.Boot(modules, {
	OnStartError = function(name, err)
		warn(`[Client] {name}.Start failed: {err}`)
	end,
})
