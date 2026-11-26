--!strict
-- Persistence configuration (spec §24).
local Data = {
	-- Data store names are suffixed by environment so development never touches production.
	StoreBaseName = "Crossblade_PlayerData",
	KeyPrefix = "player_",

	AutosaveIntervalSeconds = 60,
	-- A session lock older than this is considered abandoned (crashed server) and may be taken over.
	-- Must comfortably exceed AutosaveIntervalSeconds, since autosave refreshes the lock.
	SessionLockTimeoutSeconds = 300,

	Load = {
		MaxAttempts = 6,
		BaseBackoffSeconds = 1,
		MaxBackoffSeconds = 8,
	},
	Save = {
		MaxAttempts = 4,
		BaseBackoffSeconds = 1,
		MaxBackoffSeconds = 6,
	},
	-- Autosaves are skipped (not final saves) when the request budget drops below this value.
	MinimumAutosaveBudget = 5,

	-- Bounded lists stored in the profile.
	Limits = {
		ProcessedTransactions = 200,
	},

	-- Map of PlaceId -> environment. Unknown places (including unpublished/local files) use "Development"
	-- so that a misconfigured place can never write to production data.
	Environments = {
		-- [1234567890] = "Production", -- configure real PlaceIds before release
	} :: { [number]: "Development" | "Staging" | "Production" },
}

return table.freeze(Data)
