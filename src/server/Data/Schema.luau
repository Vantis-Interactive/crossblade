--!strict
--[[
	Versioned player data schema (spec §24). See docs/DATA_SCHEMA.md.

	Rules:
	  - SchemaVersion is bumped for every structural change, with a migration from the previous version.
	  - Migrations are pure functions vN -> vN+1, applied in order, never skipped.
	  - New optional fields are added by Reconcile (missing keys only; existing values never touched).
	  - Data from a NEWER schema than this server understands is refused (never downgraded/overwritten),
	    which protects data during staggered server updates.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage.Shared.Settings)
local TableUtil = require(ReplicatedStorage.Shared.Util.TableUtil)
local WeaponCatalog = require(ReplicatedStorage.Shared.Weapons.WeaponCatalog)

local Schema = {}

Schema.CurrentVersion = 1

export type PlayerData = { [string]: any }

function Schema.Default(userId: number, now: number): PlayerData
	local starter = WeaponCatalog.StarterLoadout()
	local weapons = {}
	for _, weaponId in starter do
		weapons[weaponId] = { AcquiredAt = now, Source = "Starter" }
	end
	return {
		UserId = userId,
		SchemaVersion = Schema.CurrentVersion,
		CreatedAt = now,
		UpdatedAt = now,
		-- Earned and purchased currency are accounted separately (spec §13), shown as one wallet.
		Currency = { Earned = 0, Purchased = 0 },
		Progression = { LifetimeXP = 0, Level = 1, Prestige = 0 },
		Inventory = { Weapons = weapons },
		Customization = {},
		Loadouts = {
			ActivePreset = 1,
			Presets = { { Primary = starter.Primary, Secondary = starter.Secondary, Knife = starter.Knife } },
		},
		Achievements = {},
		Titles = { Owned = {}, Equipped = "" },
		Mastery = {},
		Competitive = {
			Rating = 1000,
			Deviation = 350,
			Season = 0,
			CurrentDivision = "",
			HighestDivision = "",
		},
		Stats = {
			Eliminations = 0,
			Deaths = 0,
			Assists = 0,
			ShotsFired = 0,
			ShotsHit = 0,
			Headshots = 0,
			KnifeEliminations = 0,
			KnivesThrown = 0,
			KnivesHit = 0,
			DamageDealt = 0,
			HighestKillstreak = 0,
			Wins = 0,
			Losses = 0,
			MatchesPlayed = 0,
			CoinsEarned = 0,
			CratesOpened = 0,
		},
		WeaponStats = {},
		MatchHistory = {},
		Challenges = {},
		BattlePass = {},
		Purchases = { Receipts = {} },
		Entitlements = {},
		Settings = Settings.Defaults(),
		Tutorial = { Completed = false, RewardClaimed = false },
		LoginRewards = { LastClaimDay = 0, Streak = 0 },
		Moderation = { Warnings = 0 },
		ProcessedTransactions = {},
	}
end

-- Migration table: Migrations[n] upgrades a version-n record to version n+1.
-- Example for a future change:  Migrations[1] = function(data) data.NewField = ...; return data end
Schema.Migrations = {} :: { [number]: (PlayerData) -> PlayerData }

export type MigrateResult = { Ok: boolean, Data: PlayerData?, Reason: string?, Migrated: boolean }

function Schema.Migrate(
	data: any,
	userId: number,
	now: number,
	migrations: { [number]: (PlayerData) -> PlayerData }?,
	currentVersion: number?
): MigrateResult
	local chain = migrations or Schema.Migrations
	local target = currentVersion or Schema.CurrentVersion
	if type(data) ~= "table" then
		return { Ok = false, Reason = "NotATable", Migrated = false }
	end
	local version = data.SchemaVersion
	if type(version) ~= "number" or version < 1 or version % 1 ~= 0 then
		return { Ok = false, Reason = "InvalidVersion", Migrated = false }
	end
	if version > target then
		return { Ok = false, Reason = "FutureVersion", Migrated = false }
	end
	local working = TableUtil.DeepCopy(data)
	local migrated = false
	while working.SchemaVersion < target do
		local step = chain[working.SchemaVersion]
		if step == nil then
			return { Ok = false, Reason = `MissingMigration{working.SchemaVersion}`, Migrated = false }
		end
		local from = working.SchemaVersion
		local ok, result = pcall(step, working)
		if not ok or type(result) ~= "table" then
			return { Ok = false, Reason = `MigrationFailed{from}`, Migrated = false }
		end
		working = result
		working.SchemaVersion = from + 1
		migrated = true
	end
	if working.UserId ~= userId then
		return { Ok = false, Reason = "UserIdMismatch", Migrated = false }
	end
	local added = TableUtil.Reconcile(working, Schema.Default(userId, now))
	return { Ok = true, Data = working, Migrated = migrated or added > 0 }
end

return Schema
