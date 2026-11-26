--!strict
-- Resolves which data environment this server belongs to (spec §24: separate dev/staging/prod data).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

export type Name = "Development" | "Staging" | "Production"

local Environment = {}

function Environment.Current(): Name
	if RunService:IsStudio() then
		return "Development"
	end
	-- Unknown places default to Development so a misconfigured place can never touch production data.
	return Config.Data.Environments[game.PlaceId] or "Development"
end

function Environment.StoreName(): string
	return `{Config.Data.StoreBaseName}_{Environment.Current()}`
end

return Environment
