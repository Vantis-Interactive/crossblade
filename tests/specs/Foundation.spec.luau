--!nocheck
local Loader = Runtime:Get("ReplicatedStorage/Shared/Util/Loader")
local RateLimiter = Runtime:Get("ReplicatedStorage/Shared/Util/RateLimiter")
local Retry = Runtime:Get("ReplicatedStorage/Shared/Util/Retry")
local TableUtil = Runtime:Get("ReplicatedStorage/Shared/Util/TableUtil")
local Settings = Runtime:Get("ReplicatedStorage/Shared/Settings")
local Config = Runtime:Get("ReplicatedStorage/Shared/Config")

local function sync(fn)
	fn()
end

describe("Loader", function()
	it("initializes dependencies before dependents, then starts all", function()
		local order = {}
		local function module(name, deps)
			return {
				Name = name,
				Dependencies = deps,
				Init = function()
					table.insert(order, "init:" .. name)
				end,
				Start = function()
					table.insert(order, "start:" .. name)
				end,
			}
		end
		Loader.Boot({ module("C", { "B" }), module("A"), module("B", { "A" }) }, { Spawn = sync })
		expect(order).toEqual({ "init:A", "init:B", "init:C", "start:A", "start:B", "start:C" })
	end)

	it("rejects dependency cycles and unknown dependencies", function()
		expect(function()
			Loader.Sort({ { Name = "A", Dependencies = { "B" } }, { Name = "B", Dependencies = { "A" } } })
		end).toThrow("dependency cycle")
		expect(function()
			Loader.Sort({ { Name = "A", Dependencies = { "Missing" } } })
		end).toThrow("unknown module")
	end)

	it("fails boot when an Init fails, but isolates Start failures", function()
		expect(function()
			Loader.Boot(
				{ {
					Name = "Bad",
					Init = function()
						error("nope")
					end,
				} },
				{ Spawn = sync }
			)
		end).toThrow("Bad.Init failed")
		local failed = nil
		Loader.Boot({ {
			Name = "Flaky",
			Start = function()
				error("later")
			end,
		} }, {
			Spawn = sync,
			OnStartError = function(name)
				failed = name
			end,
		})
		expect(failed).toBe("Flaky")
	end)
end)

describe("RateLimiter", function()
	it("allows bursts up to capacity then refills over time", function()
		local limiter = RateLimiter.new(3, 1)
		expect(limiter:Consume("p", 0)).toBe(true)
		expect(limiter:Consume("p", 0)).toBe(true)
		expect(limiter:Consume("p", 0)).toBe(true)
		expect(limiter:Consume("p", 0)).toBe(false)
		expect(limiter:Consume("p", 1)).toBe(true)
		expect(limiter:Consume("other", 0)).toBe(true)
	end)
end)

describe("Retry", function()
	it("retries with exponential backoff until success", function()
		local sleeps = {}
		local attempts = 0
		local ok, value, used = Retry.Call({
			MaxAttempts = 5,
			BaseBackoffSeconds = 1,
			MaxBackoffSeconds = 3,
			Sleep = function(s)
				table.insert(sleeps, s)
			end,
			Random = function()
				return 0
			end,
		}, function()
			attempts += 1
			if attempts < 4 then
				error("transient")
			end
			return "done"
		end)
		expect(ok).toBe(true)
		expect(value).toBe("done")
		expect(used).toBe(4)
		expect(sleeps).toEqual({ 1, 2, 3 })
	end)

	it("stops early for non-retryable errors", function()
		local attempts = 0
		local ok = Retry.Call({
			MaxAttempts = 5,
			BaseBackoffSeconds = 0,
			MaxBackoffSeconds = 0,
			Sleep = function() end,
			ShouldRetry = function()
				return false
			end,
		}, function()
			attempts += 1
			error("fatal")
		end)
		expect(ok).toBe(false)
		expect(attempts).toBe(1)
	end)
end)

describe("TableUtil.Reconcile", function()
	it("adds missing keys without overwriting existing values", function()
		local target = { A = 1, Nested = { Keep = "yes" } }
		local added = TableUtil.Reconcile(target, { A = 99, B = 2, Nested = { Keep = "no", New = true } })
		expect(target.A).toBe(1)
		expect(target.B).toBe(2)
		expect(target.Nested.Keep).toBe("yes")
		expect(target.Nested.New).toBe(true)
		expect(added).toBe(2)
	end)
end)

describe("Settings", function()
	it("clamps field of view and sensitivity to competitive limits", function()
		local s = Settings.Sanitize({ FieldOfView = 170, Sensitivity = -5, CrosshairSize = 1000 })
		expect(s.FieldOfView).toBe(Config.Camera.FieldOfView.Max)
		expect(s.Sensitivity).toBe(Config.Camera.Sensitivity.Min)
		expect(s.CrosshairSize).toBe(40)
	end)
	it("replaces invalid values with defaults", function()
		local s = Settings.Sanitize({
			Perspective = "Overhead",
			CrosshairColor = "Plaid",
			ReducedMotion = "yes",
			FieldOfView = 0 / 0,
		})
		local d = Settings.Defaults()
		expect(s.Perspective).toBe(d.Perspective)
		expect(s.CrosshairColor).toBe(d.CrosshairColor)
		expect(s.ReducedMotion).toBe(d.ReducedMotion)
		expect(s.FieldOfView).toBe(d.FieldOfView)
		expect(Settings.Sanitize(nil)).toEqual(d)
	end)
end)

describe("Game mode configuration", function()
	local M = Config.GameModes
	it("matches the specified Free-for-All rules", function()
		expect(M.FreeForAll.DurationSeconds).toBe(900)
		expect(M.FreeForAll.RespawnDelaySeconds).toBe(3)
		expect(M.FreeForAll.MaxPlayers).toBe(20)
		expect(M.FreeForAll.SpawnProtectionSeconds).toBe(5)
	end)
	it("matches the specified Team Deathmatch and duel rules", function()
		expect(M.TeamDeathmatch.DurationSeconds).toBe(600)
		expect(M.TeamDeathmatch.ScoreLimit).toBe(50)
		expect(M.TeamDeathmatch.RespawnDelaySeconds).toBe(5)
		expect(M.CasualDuel1v1.RoundsToWin * 2 - 1).toBe(5)
		expect(M.CasualDuelTeam.RoundsToWin * 2 - 1).toBe(7)
		expect(M.RankedDuel.RoundsToWin * 2 - 1).toBe(9)
	end)
	it("private matches cannot generate normal progression rewards", function()
		expect(M.Private.AwardsProgression).toBe(false)
	end)
end)
