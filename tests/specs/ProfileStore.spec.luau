--!nocheck
local ProfileStore = Runtime:Get("ServerScriptService/Server/Data/ProfileStore")
local Schema = Runtime:Get("ServerScriptService/Server/Data/Schema")
local Config = Runtime:Get("ReplicatedStorage/Shared/Config")

local NOW = 1_800_000_000
local clock = NOW

local function makeStore(jobId, adapter, extra)
	local options = {
		Adapter = adapter,
		JobId = jobId,
		KeyPrefix = "player_",
		LockTimeoutSeconds = Config.Data.SessionLockTimeoutSeconds,
		Load = { MaxAttempts = 3, BaseBackoffSeconds = 0, MaxBackoffSeconds = 0 },
		Save = { MaxAttempts = 3, BaseBackoffSeconds = 0, MaxBackoffSeconds = 0 },
		Clock = function()
			return clock
		end,
		Sleep = function() end,
	}
	for key, value in extra or {} do
		options[key] = value
	end
	return ProfileStore.new(options)
end

local function existingRecord(userId, coins, lock)
	local data = Schema.Default(userId, NOW - 1000)
	data.Currency.Earned = coins
	data.Stats.Eliminations = 42
	return { Data = data, Lock = lock }
end

describe("ProfileStore", function()
	beforeEach(function()
		clock = NOW
	end)

	it("creates a default profile with the starter loadout for a new player", function()
		local adapter = MemoryDataStore.new()
		local profile, failure = makeStore("A", adapter):Load(1)
		expect(failure).toBeNil()
		expect(profile.Created).toBe(true)
		expect(profile.Data.SchemaVersion).toBe(Schema.CurrentVersion)
		expect(profile.Data.Inventory.Weapons.classic_ar_vanguard).never.toBeNil()
		expect(adapter.Data.player_1.Lock.JobId).toBe("A")
		expect(adapter.LastUserIds[1]).toBe(1)
	end)

	it("loads existing data without overwriting it with defaults", function()
		local adapter = MemoryDataStore.new()
		adapter.Data.player_7 = existingRecord(7, 1234, nil)
		local profile = makeStore("A", adapter):Load(7)
		expect(profile.Created).toBe(false)
		expect(profile.Data.Currency.Earned).toBe(1234)
		expect(profile.Data.Stats.Eliminations).toBe(42)
	end)

	it("refuses to load a profile locked by another live server and does not write", function()
		local adapter = MemoryDataStore.new()
		adapter.Data.player_7 = existingRecord(7, 500, { JobId = "B", Time = NOW - 10 })
		local profile, failure = makeStore("A", adapter):Load(7)
		expect(profile).toBeNil()
		expect(failure).toBe("Locked")
		expect(adapter.Writes).toBe(0)
		expect(adapter.Data.player_7.Lock.JobId).toBe("B")
		expect(adapter.Data.player_7.Data.Currency.Earned).toBe(500)
	end)

	it("acquires the lock once the other server releases it during retries", function()
		local adapter = MemoryDataStore.new()
		adapter.Data.player_7 = existingRecord(7, 500, { JobId = "B", Time = NOW - 10 })
		local calls = 0
		adapter.BeforeTransform = function(store, key)
			calls += 1
			if calls == 2 then
				store.Data[key].Lock = nil -- server B finished its release save
			end
		end
		local profile = makeStore("A", adapter):Load(7)
		expect(profile).never.toBeNil()
		expect(profile.Data.Currency.Earned).toBe(500)
	end)

	it("takes over an abandoned (stale) lock from a crashed server", function()
		local adapter = MemoryDataStore.new()
		local stale = NOW - Config.Data.SessionLockTimeoutSeconds - 1
		adapter.Data.player_7 = existingRecord(7, 500, { JobId = "Crashed", Time = stale })
		local profile = makeStore("A", adapter):Load(7)
		expect(profile).never.toBeNil()
		expect(adapter.Data.player_7.Lock.JobId).toBe("A")
		expect(profile.Data.Currency.Earned).toBe(500)
	end)

	it("failed data loads cannot erase existing profiles (store outage)", function()
		local adapter = MemoryDataStore.new()
		adapter.Data.player_7 = existingRecord(7, 999, nil)
		adapter.FailNext = 10
		local profile, failure = makeStore("A", adapter):Load(7)
		expect(profile).toBeNil()
		expect(failure).toBe("StoreError")
		expect(adapter.Writes).toBe(0)
		expect(adapter.Data.player_7.Data.Currency.Earned).toBe(999)
	end)

	it("recovers from a transient outage via retry", function()
		local adapter = MemoryDataStore.new()
		adapter.Data.player_7 = existingRecord(7, 999, nil)
		adapter.FailNext = 2
		local profile = makeStore("A", adapter):Load(7)
		expect(profile.Data.Currency.Earned).toBe(999)
	end)

	it("never overwrites corrupt records", function()
		local adapter = MemoryDataStore.new()
		adapter.Data.player_7 = "garbage"
		local profile, failure = makeStore("A", adapter):Load(7)
		expect(profile).toBeNil()
		expect(failure).toBe("Corrupt")
		expect(adapter.Data.player_7).toBe("garbage")
		expect(adapter.Calls).toBe(1) -- not retried
	end)

	it("refuses data written by a newer schema version", function()
		local adapter = MemoryDataStore.new()
		local record = existingRecord(7, 5, nil)
		record.Data.SchemaVersion = Schema.CurrentVersion + 1
		adapter.Data.player_7 = record
		local profile, failure = makeStore("A", adapter):Load(7)
		expect(profile).toBeNil()
		expect(failure).toBe("FutureVersion")
		expect(adapter.Writes).toBe(0)
	end)

	it("applies migrations in order and reconciles new fields", function()
		local adapter = MemoryDataStore.new()
		local record = existingRecord(7, 300, nil)
		record.Data.SchemaVersion = 1
		record.Data.Settings = nil -- simulate an old record missing a section
		adapter.Data.player_7 = record
		local migrations = {
			[1] = function(data)
				data.Currency.Earned *= 2
				return data
			end,
			[2] = function(data)
				data.Renamed = true
				return data
			end,
		}
		local profile = makeStore("A", adapter, { Migrations = migrations, CurrentVersion = 3 }):Load(7)
		expect(profile.Data.SchemaVersion).toBe(3)
		expect(profile.Data.Currency.Earned).toBe(600)
		expect(profile.Data.Renamed).toBe(true)
		expect(profile.Data.Settings).never.toBeNil()
		expect(profile.Data.Stats.Eliminations).toBe(42)
	end)

	it("does not write when a migration fails", function()
		local adapter = MemoryDataStore.new()
		adapter.Data.player_7 = existingRecord(7, 300, nil)
		local migrations = {
			[1] = function()
				error("boom")
			end,
		}
		local profile, failure =
			makeStore("A", adapter, { Migrations = migrations, CurrentVersion = 2 }):Load(7)
		expect(profile).toBeNil()
		expect(failure).toBe("MigrationFailed")
		expect(adapter.Writes).toBe(0)
		expect(adapter.Data.player_7.Data.SchemaVersion).toBe(1)
	end)

	it("saves while keeping the lock, and releases it on leave", function()
		local adapter = MemoryDataStore.new()
		local store = makeStore("A", adapter)
		local profile = store:Load(3)
		profile.Data.Currency.Earned = 75
		expect(store:Save(profile, false)).toBe("Saved")
		expect(adapter.Data.player_3.Data.Currency.Earned).toBe(75)
		expect(adapter.Data.player_3.Lock.JobId).toBe("A")
		expect(store:Save(profile, true)).toBe("Saved")
		expect(adapter.Data.player_3.Lock).toBeNil()
		expect(profile.Active).toBe(false)
		expect(store:Save(profile, false)).toBe("Inactive")
	end)

	it("refuses to save when another server has taken the lock", function()
		local adapter = MemoryDataStore.new()
		local store = makeStore("A", adapter)
		local profile = store:Load(3)
		adapter.Data.player_3.Lock = { JobId = "B", Time = NOW }
		adapter.Data.player_3.Data.Currency.Earned = 10
		profile.Data.Currency.Earned = 99999
		expect(store:Save(profile, false)).toBe("LockLost")
		expect(profile.LockLost).toBe(true)
		expect(adapter.Data.player_3.Data.Currency.Earned).toBe(10)
	end)

	it("a second server cannot load while the first holds the session", function()
		local adapter = MemoryDataStore.new()
		local first = makeStore("A", adapter)
		local second = makeStore("B", adapter)
		expect(first:Load(5)).never.toBeNil()
		local profile, failure = second:Load(5)
		expect(profile).toBeNil()
		expect(failure).toBe("Locked")
	end)
end)
