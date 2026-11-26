--!strict
-- Player levels and XP (spec §15). Applied inside economy transactions; see Shared/Economy/Leveling.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Leveling = require(ReplicatedStorage.Shared.Economy.Leveling)
local Wallet = require(ReplicatedStorage.Shared.Economy.Wallet)

local ProgressionService = {
	Name = "ProgressionService",
	Dependencies = { "PlayerDataService" },
}

local playerData: any

function ProgressionService.Init(_self: typeof(ProgressionService), registry: { [string]: any })
	playerData = registry.PlayerDataService
	playerData.ProfileLoaded:Connect(function(player: Player, profile: any)
		player:SetAttribute("Level", profile.Data.Progression.Level)
	end)
end

-- Adds XP to a transaction draft and credits any level rewards into the same draft (atomic).
function ProgressionService.ApplyXP(
	_self: typeof(ProgressionService),
	draft: { [string]: any },
	amount: number
): Leveling.ApplyResult
	local result = Leveling.ApplyXP(draft.Progression, amount)
	if result.RewardCoins > 0 then
		Wallet.CreditEarned(draft.Currency, result.RewardCoins)
		draft.Stats.CoinsEarned += result.RewardCoins
	end
	return result
end

function ProgressionService.Info(_self: typeof(ProgressionService), player: Player): Leveling.LevelInfo?
	local profile = playerData:GetProfile(player)
	return profile and Leveling.Info(profile.Data.Progression.LifetimeXP)
end

-- Mirrors the level onto the player for scoreboards and the elimination screen.
function ProgressionService.Sync(_self: typeof(ProgressionService), player: Player)
	local profile = playerData:GetProfile(player)
	if profile then
		player:SetAttribute("Level", profile.Data.Progression.Level)
	end
end

return ProgressionService
