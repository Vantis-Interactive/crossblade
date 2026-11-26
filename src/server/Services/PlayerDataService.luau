--!strict
--[[
	Player lifecycle and persistence (spec §24). Owns the session-locked profile for every player.

	Lifecycle:
	  PlayerAdded     -> Load (session lock). Failure => player is kicked with a clear message; nothing
	                     is ever written for a failed load.
	  Autosave        -> every AutosaveIntervalSeconds, budget permitting; refreshes the lock.
	  PlayerRemoving  -> ProfileReleasing fires (services flush), then save + release lock.
	  BindToClose     -> save + release every profile in parallel before shutdown.
	  Lock lost       -> another server owns the profile; we stop saving and remove the player.

	Studio note: if DataStores are not reachable in Studio (unpublished place, API access disabled),
	the service runs in an explicit, loudly-reported "StudioEphemeral" mode where nothing persists.
	This mode can never activate outside Studio; live servers fail closed (players are kicked).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local Settings = require(ReplicatedStorage.Shared.Settings)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local DataStoreAdapter = require(script.Parent.Parent.Data.DataStoreAdapter)
local Environment = require(script.Parent.Parent.Core.Environment)
local ProfileStore = require(script.Parent.Parent.Data.ProfileStore)
local Transactions = require(script.Parent.Parent.Data.Transactions)

local log = Logger.new("PlayerData")

local KICK_MESSAGES = {
	Locked = "Your data is still being saved by another server. Please rejoin in a moment.",
	Corrupt = "We could not read your saved data safely. Please contact support; nothing was changed.",
	FutureVersion = "This server is out of date. Please rejoin to reach an updated server.",
	MigrationFailed = "Your data could not be upgraded safely. Please contact support; nothing was changed.",
	StoreError = "Roblox data services are unavailable right now. Please rejoin shortly.",
	LockLost = "Your session was opened on another server.",
}

local PlayerDataService = {
	Name = "PlayerDataService",
	Dependencies = { "Net", "AuditService" },
	ProfileLoaded = Signal.new() :: Signal.Signal<Player, ProfileStore.Profile>,
	-- Fired before the final save so services can write session state into the profile.
	ProfileReleasing = Signal.new() :: Signal.Signal<Player, ProfileStore.Profile>,
	Mode = "Persistent" :: "Persistent" | "StudioEphemeral",
}

local profiles: { [Player]: ProfileStore.Profile } = {}
local loading: { [Player]: boolean } = {}
local store: ProfileStore.ProfileStore
local net: any
local audit: any
local shuttingDown = false
local saveScheduled: { [Player]: boolean } = {}

-- Explicit Studio-only, non-persistent adapter. Never constructed outside Studio.
local function studioEphemeralAdapter()
	assert(RunService:IsStudio(), "ephemeral data mode is Studio-only")
	local data: { [string]: any } = {}
	return {
		UpdateAsync = function(_self, key: string, transform: (any) -> any, _userIds: { number })
			local result = transform(data[key])
			if result ~= nil then
				data[key] = result
			end
			return data[key]
		end,
	}
end

local function createAdapter(): any
	local storeName = Environment.StoreName()
	local ok, adapterOrError = pcall(function()
		local adapter = DataStoreAdapter.new(storeName)
		-- Probe access early so Studio without API access is detected at boot, not on first join.
		if RunService:IsStudio() then
			adapter:Probe()
		end
		return adapter
	end)
	if ok then
		log:Info("using DataStore", { store = storeName, environment = Environment.Current() })
		return adapterOrError
	end
	if RunService:IsStudio() then
		PlayerDataService.Mode = "StudioEphemeral"
		log:Warn(
			"DataStores unavailable in Studio; running in NON-PERSISTENT mode",
			{ error = adapterOrError }
		)
		return studioEphemeralAdapter()
	end
	-- Live server without DataStore access: boot anyway with an adapter that refuses every request,
	-- so each load fails closed (player kicked, nothing written) instead of aborting the whole server.
	log:Error("DataStore initialisation failed on a live server", { error = adapterOrError })
	local reason = tostring(adapterOrError)
	return {
		UpdateAsync = function()
			error(`DataStore unavailable: {reason}`)
		end,
	}
end

local function kick(player: Player, reason: string)
	audit:Record("Data", "KickedForData", player.UserId, { reason = reason })
	player:Kick(KICK_MESSAGES[reason] or KICK_MESSAGES.StoreError)
end

local function onPlayerAdded(player: Player)
	if profiles[player] or loading[player] then
		return
	end
	loading[player] = true
	local profile, failure, detail = store:Load(player.UserId)
	loading[player] = nil
	if profile == nil then
		log:Warn("profile load failed", { player = player.UserId, failure = failure, detail = detail })
		if player.Parent == Players then
			kick(player, failure or "StoreError")
		end
		return
	end
	if player.Parent ~= Players then
		-- Left while loading: release immediately without keeping anything.
		store:Save(profile, true)
		return
	end
	profiles[player] = profile
	player:SetAttribute("Level", profile.Data.Progression.Level)
	player:SetAttribute("DataLoaded", true)
	log:Info("profile loaded", { player = player.UserId, created = profile.Created })
	PlayerDataService.ProfileLoaded:Fire(player, profile)
	if PlayerDataService.Mode == "StudioEphemeral" then
		net.Fire("Notification", player, {
			Kind = "Warning",
			Text = "Studio: DataStores unavailable. Progress in this session will NOT be saved.",
		})
	end
end

local function release(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return
	end
	PlayerDataService.ProfileReleasing:Fire(player, profile)
	profiles[player] = nil
	saveScheduled[player] = nil
	local result, err = store:Save(profile, true)
	if result ~= "Saved" then
		log:Error("final save failed", { player = player.UserId, result = result, error = err })
		audit:Record("Data", "FinalSaveFailed", player.UserId, { result = result, error = err })
	end
end

local function autosaveLoop()
	while not shuttingDown do
		task.wait(Config.Data.AutosaveIntervalSeconds)
		for player, profile in profiles do
			if
				PlayerDataService.Mode == "Persistent"
				and DataStoreAdapter.Budget() < Config.Data.MinimumAutosaveBudget
			then
				log:Warn("autosave deferred: low request budget")
				break
			end
			local result, err = store:Save(profile, false)
			if result == "LockLost" then
				profiles[player] = nil
				kick(player, "LockLost")
			elseif result == "StoreError" then
				log:Warn("autosave failed; will retry next cycle", { player = player.UserId, error = err })
			end
		end
	end
end

function PlayerDataService.Init(_self: typeof(PlayerDataService), registry: { [string]: any })
	net = registry.Net
	audit = registry.AuditService
	store = ProfileStore.new({
		Adapter = createAdapter(),
		JobId = if game.JobId ~= "" then game.JobId else `studio-{os.time()}-{math.random(1, 1e6)}`,
		KeyPrefix = Config.Data.KeyPrefix,
		LockTimeoutSeconds = Config.Data.SessionLockTimeoutSeconds,
		Load = Config.Data.Load,
		Save = Config.Data.Save,
		Clock = os.time,
	})

	net.OnEvent("SaveSettings", function(player: Player, payload: any)
		local profile = profiles[player]
		if profile == nil then
			return
		end
		local sanitized = Settings.Sanitize(payload)
		profile.Data.Settings = sanitized
		net.Fire("SettingsApplied", player, sanitized)
	end)
end

function PlayerDataService.Start(_self: typeof(PlayerDataService))
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(release)
	for _, player in Players:GetPlayers() do
		-- Deferred so every service has finished Start before the first ProfileLoaded fires.
		task.defer(onPlayerAdded, player)
	end
	game:BindToClose(function()
		shuttingDown = true
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				release(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
	task.spawn(autosaveLoop)
end

function PlayerDataService.GetProfile(_self: typeof(PlayerDataService), player: Player): ProfileStore.Profile?
	local profile = profiles[player]
	if profile and profile.Active then
		return profile
	end
	return nil
end

-- Schedules a save soon (debounced). Used after economy mutations so they persist promptly.
function PlayerDataService.RequestSave(_self: typeof(PlayerDataService), player: Player)
	if saveScheduled[player] or shuttingDown then
		return
	end
	saveScheduled[player] = true
	task.delay(Config.Data.PrioritySaveDelaySeconds, function()
		saveScheduled[player] = nil
		local profile = profiles[player]
		if profile == nil or not profile.Active then
			return
		end
		local result, err = store:Save(profile, false)
		if result == "LockLost" then
			profiles[player] = nil
			kick(player, "LockLost")
		elseif result == "StoreError" then
			log:Warn("priority save failed; autosave will retry", { player = player.UserId, error = err })
		end
	end)
end

-- Mutates a loaded profile. Returns false if the profile is not loaded (never creates data).
function PlayerDataService.Update(
	self: typeof(PlayerDataService),
	player: Player,
	mutate: (data: { [string]: any }) -> ()
): boolean
	local profile = self:GetProfile(player)
	if profile == nil then
		return false
	end
	local ok, err = pcall(mutate, profile.Data)
	if not ok then
		log:Error("profile update failed", { player = player.UserId, error = err })
		return false
	end
	return true
end

-- Idempotent all-or-nothing mutation keyed by transaction id (see Data/Transactions).
function PlayerDataService.ApplyTransaction(
	self: typeof(PlayerDataService),
	player: Player,
	transactionId: string,
	mutate: (draft: { [string]: any }) -> ()
): (Transactions.Outcome, string?)
	local profile = self:GetProfile(player)
	if profile == nil then
		return "Failed", "NotLoaded"
	end
	local outcome, err = Transactions.Apply(
		profile.Data,
		transactionId,
		os.time(),
		Config.Data.Limits.ProcessedTransactions,
		mutate
	)
	if outcome == "Failed" then
		log:Warn("transaction failed", { player = player.UserId, tx = transactionId, error = err })
	end
	return outcome, err
end

return PlayerDataService
