--!strict
--[[
	Coins, XP rewards and wallet state (spec §13, §15).

	Every grant is ONE idempotent transaction (Data/Transactions) that applies, together:
	hourly anti-farming caps, the earned-coin credit, XP and any level rewards, and statistics.
	Transaction ids are derived from the server, round and death sequence, so re-processing an event
	can never pay twice. Earned and purchased balances are kept separate (Shared/Economy/Wallet).

	Rewards are disabled in modes with AwardsProgression = false (private matches) and in
	player-owned private servers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Leveling = require(ReplicatedStorage.Shared.Economy.Leveling)
local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local Wallet = require(ReplicatedStorage.Shared.Economy.Wallet)
local RewardPolicy = require(script.Parent.Parent.Domain.RewardPolicy)

local log = Logger.new("Economy")
local E = Config.Economy

local EconomyService = {
	Name = "EconomyService",
	Dependencies = {
		"Net",
		"PlayerDataService",
		"MatchService",
		"ProgressionService",
		"InventoryService",
		"PolicyComplianceService",
		"AuditService",
	},
	ActiveCrates = {} :: { string }, -- set by CrateService at Init
}

local guard = RewardPolicy.NewGuard()
local net: any
local playerData: any
local match: any
local progression: any
local inventory: any
local policy: any
local audit: any
local serverTag = ""

local function rewardsEnabled(): boolean
	if not match:Mode().AwardsProgression then
		return false
	end
	if E.AntiFarming.DisableInOwnedPrivateServers and game.PrivateServerOwnerId ~= 0 then
		return false
	end
	return true
end

local function population(): number
	local count = 0
	for _, player in Players:GetPlayers() do
		if playerData:GetProfile(player) then
			count += 1
		end
	end
	return count
end

function EconomyService.State(_self: typeof(EconomyService), player: Player): { [string]: any }?
	local profile = playerData:GetProfile(player)
	if profile == nil then
		return nil
	end
	local data = profile.Data
	local info = Leveling.Info(data.Progression.LifetimeXP)
	local items = inventory:Snapshot(player)
	return {
		Coins = Wallet.Total(data.Currency),
		Earned = data.Currency.Earned,
		Purchased = data.Currency.Purchased,
		PurchasedUsableForCrates = policy:PurchasedCurrencyAllowedForCrates(player),
		Level = info.Level,
		XPIntoLevel = info.IntoLevel,
		XPForNext = info.ForNext,
		Prestige = data.Progression.Prestige,
		Owned = items and items.Owned or {},
		Loadout = items and items.Loadout or {},
		ActiveCrates = EconomyService.ActiveCrates,
		RewardsEnabled = rewardsEnabled(),
	}
end

function EconomyService.PushState(self: typeof(EconomyService), player: Player)
	local state = self:State(player)
	if state then
		net.Fire("EconomyState", player, state)
	end
end

--[[
	Grants coins and XP in one transaction. `capped` applies the hourly match-reward caps.
	Returns the transaction outcome.
]]
function EconomyService.Grant(
	self: typeof(EconomyService),
	player: Player,
	transactionId: string,
	coins: number,
	xp: number,
	reasons: { string },
	capped: boolean
): string
	local applied = { Coins = 0, XP = 0, LevelsGained = 0, LevelCoins = 0 }
	local outcome = playerData:ApplyTransaction(player, transactionId, function(draft)
		local allowedCoins, allowedXP = coins, xp
		if capped then
			allowedCoins, allowedXP =
				RewardPolicy.ApplyHourlyCap(draft.Economy, os.time(), coins, xp, E.AntiFarming)
		end
		Wallet.CreditEarned(draft.Currency, allowedCoins)
		draft.Stats.CoinsEarned += allowedCoins
		local levels = progression:ApplyXP(draft, allowedXP)
		applied.Coins, applied.XP = allowedCoins, levels.Granted
		applied.LevelsGained, applied.LevelCoins = levels.LevelsGained, levels.RewardCoins
	end)
	if outcome == "Applied" and (applied.Coins < coins or applied.XP < xp) then
		audit:Record("Economy", "RewardCapped", player.UserId, {
			tx = transactionId,
			coins = `{applied.Coins}/{coins}`,
			xp = `{applied.XP}/{xp}`,
		})
	end
	if outcome == "Applied" and (applied.Coins > 0 or applied.XP > 0) then
		progression:Sync(player)
		playerData:RequestSave(player)
		self:PushState(player)
		net.Fire("Reward", player, {
			Coins = applied.Coins,
			XP = applied.XP,
			Reasons = reasons,
			LevelsGained = applied.LevelsGained,
			LevelCoins = applied.LevelCoins,
			Level = player:GetAttribute("Level"),
			Capped = applied.Coins < coins or applied.XP < xp,
		})
	end
	return outcome
end

local function onEliminationScored(event: any, killerStreak: number, roundId: number, sequence: number)
	local assistIds = {}
	for _, assister in event.Assists do
		table.insert(assistIds, assister.UserId)
	end
	local grants = RewardPolicy.Evaluate({
		KillerId = event.Killer and event.Killer.UserId,
		VictimId = event.Victim.UserId,
		Kind = event.Kind,
		Headshot = event.Headshot,
		AssistIds = assistIds,
		KillerStreak = killerStreak,
	}, {
		Enabled = rewardsEnabled(),
		Population = population(),
		Now = os.clock(),
		Guard = guard,
		Rewards = E.Rewards,
		Experience = E.Experience,
		AntiFarming = E.AntiFarming,
	})
	for userId, grant in grants do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			EconomyService:Grant(
				player,
				`elim:{serverTag}:{roundId}:{sequence}:{userId}`,
				grant.Coins,
				grant.XP,
				grant.Reasons,
				true
			)
		end
	end
end

local function onRoundFinished(ranked: { any }, roundId: number)
	if not rewardsEnabled() or population() < E.AntiFarming.MinPlayersForRewards then
		return
	end
	for rank, entry in ranked do
		local player = Players:GetPlayerByUserId(entry.UserId)
		if player then
			local xp = E.Experience.MatchCompleted
			local coins = 0
			local reasons = { "MatchCompleted" }
			if rank == 1 and entry.Eliminations > 0 then
				xp += E.Experience.FirstPlace
				coins += E.Rewards.FreeForAllFirstPlace
				table.insert(reasons, "FirstPlace")
			end
			EconomyService:Grant(
				player,
				`round:{serverTag}:{roundId}:{entry.UserId}`,
				coins,
				xp,
				reasons,
				true
			)
		end
	end
end

function EconomyService.Init(self: typeof(EconomyService), registry: { [string]: any })
	net = registry.Net
	playerData = registry.PlayerDataService
	match = registry.MatchService
	progression = registry.ProgressionService
	inventory = registry.InventoryService
	policy = registry.PolicyComplianceService
	audit = registry.AuditService
	serverTag = if game.JobId ~= "" then game.JobId else `studio{os.time()}`

	match.EliminationScored:Connect(onEliminationScored)
	match.RoundFinished:Connect(onRoundFinished)
	playerData.ProfileLoaded:Connect(function(player: Player)
		self:PushState(player)
	end)
	inventory.Changed:Connect(function(player: Player)
		self:PushState(player)
	end)
	policy.StatusChanged:Connect(function(player: Player)
		self:PushState(player)
	end)
	net.OnInvoke("GetEconomy", function(player: Player)
		return self:State(player)
	end)
	log:Info("economy ready", { rewardsEnabled = rewardsEnabled() })
end

return EconomyService
