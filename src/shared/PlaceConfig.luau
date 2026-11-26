--!strict
--[[
	Identity of the running place, read from ReplicatedStorage.PlaceConfig (a Configuration instance
	whose attributes each places/*.project.json sets). Defaults to a Free-for-All arena so the
	default project keeps working.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Role = "Hub" | "Arena"

local instance = ReplicatedStorage:FindFirstChild("PlaceConfig")

local function attribute(name: string): any
	return if instance then instance:GetAttribute(name) else nil
end

local role = attribute("Role")
local mode = attribute("Mode")
local teamSize = attribute("TeamSize")

return table.freeze({
	Role = (if role == "Hub" then "Hub" else "Arena") :: Role,
	Mode = if type(mode) == "string" then mode elseif role == "Hub" then "Lobby" else "FreeForAll",
	TeamSize = if type(teamSize) == "number" then teamSize else nil,
	Map = attribute("Map"),
})
