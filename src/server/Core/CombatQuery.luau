--!strict
--[[
	World queries used for combat validation. Line-of-sight ignores every character (hitboxes are
	standardized, avatar geometry is cosmetic) and anything with CanQuery = false (pickups, weapon
	models, projectiles, effects).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CombatQuery = {}

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

local function refreshFilter()
	local exclude = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
end

-- True if nothing solid lies between `from` and `to`.
function CombatQuery.LineOfSight(from: Vector3, to: Vector3): boolean
	local delta = to - from
	if delta.Magnitude < 1e-3 then
		return true
	end
	refreshFilter()
	return Workspace:Raycast(from, delta, params) == nil
end

-- First world hit along a segment (characters excluded), or nil.
function CombatQuery.Raycast(from: Vector3, delta: Vector3): RaycastResult?
	refreshFilter()
	return Workspace:Raycast(from, delta, params)
end

return CombatQuery
