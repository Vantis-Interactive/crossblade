--!strict
--[[
	Session-locked player profile persistence (spec §24). Pure logic over an injected store adapter.

	Stored record (the "envelope"):
	  { Data = <PlayerData>, Lock = { JobId = string, Time = number } | nil }

	Guarantees:
	  - A profile is loaded by at most one server at a time (session lock). A lock older than
	    SessionLockTimeoutSeconds is treated as abandoned (crashed server) and may be taken over.
	  - A failed or refused load NEVER writes defaults over an existing record. Defaults are created
	    only when the key is genuinely empty.
	  - Corrupt records and records from a future schema version are left untouched and the load fails.
	  - Saves verify the lock is still owned by this server; if another server took over, the save is
	    refused and the profile is marked lost so the caller can remove the player safely.
	  - UpdateAsync transforms are re-entrant: all outcome variables are reset on each invocation,
	    because Roblox may call the transform more than once under contention.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Retry = require(ReplicatedStorage.Shared.Util.Retry)
local TableUtil = require(ReplicatedStorage.Shared.Util.TableUtil)
local Schema = require(script.Parent.Schema)

export type Adapter = {
	-- Mirrors GlobalDataStore:UpdateAsync. Returning nil from transform cancels the write.
	UpdateAsync: (self: Adapter, key: string, transform: (old: any) -> any, userIds: { number }) -> any,
}

export type RetryPolicy = { MaxAttempts: number, BaseBackoffSeconds: number, MaxBackoffSeconds: number }

export type Options = {
	Adapter: Adapter,
	JobId: string,
	KeyPrefix: string,
	LockTimeoutSeconds: number,
	Load: RetryPolicy,
	Save: RetryPolicy,
	Clock: () -> number, -- wall-clock seconds (os.time) shared across servers
	Sleep: ((seconds: number) -> ())?,
	Migrations: { [number]: (Schema.PlayerData) -> Schema.PlayerData }?,
	CurrentVersion: number?,
}

export type Profile = {
	UserId: number,
	Key: string,
	Data: Schema.PlayerData,
	Active: boolean, -- false once released or lost; inactive profiles are never saved again
	LockLost: boolean,
	Created: boolean,
}

export type LoadFailure = "Locked" | "Corrupt" | "FutureVersion" | "MigrationFailed" | "StoreError"

local ProfileStore = {}
ProfileStore.__index = ProfileStore

export type ProfileStore = typeof(setmetatable({} :: { _options: Options }, ProfileStore))

-- Thrown inside a retried call to trigger another attempt for a lock held elsewhere.
local LOCKED_SENTINEL = "__PROFILE_LOCKED__"

function ProfileStore.new(options: Options): ProfileStore
	return setmetatable({ _options = options }, ProfileStore)
end

function ProfileStore.KeyFor(self: ProfileStore, userId: number): string
	return self._options.KeyPrefix .. tostring(userId)
end

function ProfileStore.Load(self: ProfileStore, userId: number): (Profile?, LoadFailure?, string?)
	local options = self._options
	local key = self:KeyFor(userId)
	local outcome: string = "StoreError"
	local detail: string? = nil
	local loadedData: Schema.PlayerData? = nil
	local created = false

	local function transform(old: any): any
		-- Reset per invocation (UpdateAsync may retry the transform).
		outcome, detail, loadedData, created = "StoreError", nil, nil, false
		local now = options.Clock()
		if old == nil then
			local fresh = Schema.Default(userId, now)
			outcome, loadedData, created = "Loaded", fresh, true
			return { Data = fresh, Lock = { JobId = options.JobId, Time = now } }
		end
		if type(old) ~= "table" or type(old.Data) ~= "table" then
			outcome = "Corrupt"
			return nil
		end
		local lock = old.Lock
		if type(lock) == "table" and lock.JobId ~= options.JobId and type(lock.Time) == "number" then
			if now - lock.Time < options.LockTimeoutSeconds then
				outcome = "Locked"
				return nil
			end
		end
		local migration = Schema.Migrate(old.Data, userId, now, options.Migrations, options.CurrentVersion)
		if not migration.Ok then
			outcome = if migration.Reason == "FutureVersion" then "FutureVersion" else "MigrationFailed"
			detail = migration.Reason
			return nil
		end
		outcome, loadedData = "Loaded", migration.Data
		return { Data = migration.Data, Lock = { JobId = options.JobId, Time = now } }
	end

	local ok, err = Retry.Call({
		MaxAttempts = options.Load.MaxAttempts,
		BaseBackoffSeconds = options.Load.BaseBackoffSeconds,
		MaxBackoffSeconds = options.Load.MaxBackoffSeconds,
		Sleep = options.Sleep,
		ShouldRetry = function(problem)
			-- Locked (another server still saving) and store errors are transient; data problems are not.
			return problem == LOCKED_SENTINEL
				or not (outcome == "Corrupt" or outcome == "FutureVersion" or outcome == "MigrationFailed")
		end,
	}, function()
		outcome = "StoreError" -- an adapter error before the transform runs must not reuse a stale outcome
		options.Adapter:UpdateAsync(key, transform, { userId })
		if outcome == "Locked" then
			error(LOCKED_SENTINEL, 0)
		elseif outcome ~= "Loaded" then
			error(outcome, 0)
		end
		return true
	end)

	if ok and loadedData ~= nil then
		return {
			UserId = userId,
			Key = key,
			Data = loadedData,
			Active = true,
			LockLost = false,
			Created = created,
		},
			nil,
			nil
	end
	if outcome == "Locked" or err == LOCKED_SENTINEL then
		return nil, "Locked", nil
	elseif outcome == "Corrupt" or outcome == "FutureVersion" or outcome == "MigrationFailed" then
		return nil, outcome :: LoadFailure, detail
	end
	return nil, "StoreError", tostring(err)
end

export type SaveResult = "Saved" | "LockLost" | "Inactive" | "StoreError"

-- Saves the profile. With release = true the session lock is cleared and the profile deactivated.
function ProfileStore.Save(self: ProfileStore, profile: Profile, release: boolean): (SaveResult, string?)
	if not profile.Active then
		return "Inactive", nil
	end
	local options = self._options
	local lockLost = false
	local snapshot = TableUtil.DeepCopy(profile.Data)

	local function transform(old: any): any
		lockLost = false
		if type(old) == "table" and type(old.Lock) == "table" and old.Lock.JobId ~= options.JobId then
			lockLost = true
			return nil
		end
		local now = options.Clock()
		snapshot.UpdatedAt = now
		return { Data = snapshot, Lock = if release then nil else { JobId = options.JobId, Time = now } }
	end

	local ok, err = Retry.Call({
		MaxAttempts = options.Save.MaxAttempts,
		BaseBackoffSeconds = options.Save.BaseBackoffSeconds,
		MaxBackoffSeconds = options.Save.MaxBackoffSeconds,
		Sleep = options.Sleep,
	}, function()
		options.Adapter:UpdateAsync(profile.Key, transform, { profile.UserId })
		return true
	end)

	if lockLost then
		profile.Active = false
		profile.LockLost = true
		return "LockLost", nil
	end
	if not ok then
		return "StoreError", tostring(err)
	end
	if release then
		profile.Active = false
	end
	return "Saved", nil
end

return ProfileStore
