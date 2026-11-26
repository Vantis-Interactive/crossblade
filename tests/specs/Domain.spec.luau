--!nocheck
local Config = Runtime:Get("ReplicatedStorage/Shared/Config")
local DamageLedger = Runtime:Get("ServerScriptService/Server/Domain/DamageLedger")
local SpawnSelector = Runtime:Get("ServerScriptService/Server/Domain/SpawnSelector")
local MovementValidator = Runtime:Get("ServerScriptService/Server/Domain/MovementValidator")
local SuspicionScore = Runtime:Get("ServerScriptService/Server/Domain/SuspicionScore")
local MatchRules = Runtime:Get("ServerScriptService/Server/Domain/MatchRules")

describe("DamageLedger assists", function()
	local A = Config.Combat.Assists
	it("credits other attackers above the damage threshold within the window", function()
		local ledger = DamageLedger.new()
		DamageLedger.Record(ledger, 1, 2, 60, 0) -- assister
		DamageLedger.Record(ledger, 1, 3, 20, 0) -- too little damage
		DamageLedger.Record(ledger, 1, 4, 90, 1) -- killer
		local assists = DamageLedger.Assists(ledger, 1, 4, 2, A.MinimumDamage, A.WindowSeconds)
		expect(assists).toEqual({ 2 })
	end)
	it("excludes stale damage and self-damage", function()
		local ledger = DamageLedger.new()
		DamageLedger.Record(ledger, 1, 2, 100, 0)
		DamageLedger.Record(ledger, 1, 1, 100, 0)
		expect(#DamageLedger.Assists(ledger, 1, 4, A.WindowSeconds + 1, A.MinimumDamage, A.WindowSeconds)).toBe(
			0
		)
	end)
	it("forgets departed players", function()
		local ledger = DamageLedger.new()
		DamageLedger.Record(ledger, 1, 2, 100, 0)
		DamageLedger.ForgetPlayer(ledger, 2)
		expect(#DamageLedger.Assists(ledger, 1, nil, 0, 1, 100)).toBe(0)
	end)
end)

describe("SpawnSelector", function()
	local W = Config.Spawning
	local spawns = {
		{ Id = "near", Position = Vector3.new(10, 0, 0) },
		{ Id = "far", Position = Vector3.new(200, 0, 0) },
		{ Id = "mid", Position = Vector3.new(80, 0, 0) },
	}
	local function input(overrides)
		local base = {
			Spawns = spawns,
			Enemies = { Vector3.new(0, 0, 0) },
			RecentDeaths = {},
			LastUsed = {},
			Now = 100,
			Weights = W,
			Random = function()
				return 0
			end,
		}
		for k, v in overrides or {} do
			base[k] = v
		end
		return base
	end

	it("prefers spawns far from opponents", function()
		expect(SpawnSelector.Select(input()).Id).toBe("far")
	end)
	it("avoids recently used spawns (anti spawn-camping)", function()
		local used = input({ LastUsed = { far = 99 } })
		local fresh = input()
		local usedScore = SpawnSelector.Score(spawns[2], used)
		local freshScore = SpawnSelector.Score(spawns[2], fresh)
		expect(freshScore - usedScore).toBe(W.RecentUse.Penalty)
		local strict = table.clone(W)
		strict.ChoiceMargin = 0
		local chosen = SpawnSelector.Select(input({ LastUsed = { far = 99 }, Weights = strict }))
		expect(chosen.Id).toBe("mid")
	end)
	it("avoids spawns near recent eliminations", function()
		local chosen = SpawnSelector.Select(input({
			RecentDeaths = {
				{ Position = Vector3.new(200, 0, 0), Time = 99 },
				{ Position = Vector3.new(200, 0, 0), Time = 99 },
			},
		}))
		expect(chosen.Id).toBe("mid")
	end)
	it("avoids spawns in an opponent's line of sight", function()
		local chosen = SpawnSelector.Select(input({
			Spawns = {
				{ Id = "a", Position = Vector3.new(120, 0, 0) },
				{ Id = "b", Position = Vector3.new(0, 0, 125) },
			},
			LineOfSight = function(_, to)
				return to.X > 100
			end,
		}))
		expect(chosen.Id).toBe("b")
	end)
	it("never picks an unsafe spawn while a safe one exists", function()
		local chosen = SpawnSelector.Select(input({
			Spawns = {
				{ Id = "unsafe", Position = Vector3.new(5, 0, 0) },
				{ Id = "safe", Position = Vector3.new(40, 0, 0) },
			},
			LastUsed = { safe = 99 },
		}))
		expect(chosen.Id).toBe("safe")
	end)
	it("still returns a spawn when every spawn is unsafe", function()
		local chosen =
			SpawnSelector.Select(input({ Spawns = { { Id = "only", Position = Vector3.new(1, 0, 0) } } }))
		expect(chosen.Id).toBe("only")
	end)
	it("returns nil with no spawns", function()
		expect(SpawnSelector.Select(input({ Spawns = {} }))).toBeNil()
	end)
end)

describe("MovementValidator", function()
	local M = Config.AntiCheat.Movement
	local limits = {
		RunSpeed = Config.Player.Movement.RunSpeed,
		SpeedToleranceMultiplier = M.SpeedToleranceMultiplier,
		SpeedToleranceFlat = M.SpeedToleranceFlat,
		CorrectionMultiplier = M.CorrectionMultiplier,
		MaxRiseSpeed = M.MaxRiseSpeed,
		FlagsBeforeSuspicion = M.FlagsBeforeSuspicion,
		FlagWindowSeconds = M.FlagWindowSeconds,
	}

	it("accepts running at full speed and free falling", function()
		local state = MovementValidator.new()
		MovementValidator.Sample(state, Vector3.new(0, 100, 0), 0, limits)
		expect((MovementValidator.Sample(state, Vector3.new(limits.RunSpeed * 0.25, 100, 0), 0.25, limits))).toBe(
			"Ok"
		)
		expect((MovementValidator.Sample(state, Vector3.new(limits.RunSpeed * 0.5, 40, 0), 0.5, limits))).toBe(
			"Ok"
		)
	end)

	it("flags speed hacks and only reports suspicion after repeated flags", function()
		local state = MovementValidator.new()
		local x = 0
		MovementValidator.Sample(state, Vector3.new(x, 0, 0), 0, limits)
		local reachedAt = nil
		for i = 1, 5 do
			x += 50 * 0.25 -- 50 studs/s
			local verdict, _, reached =
				MovementValidator.Sample(state, Vector3.new(x, 0, 0), i * 0.25, limits)
			expect(verdict).toBe("Flag")
			if reached and reachedAt == nil then
				reachedAt = i
			end
		end
		expect(reachedAt).toBe(limits.FlagsBeforeSuspicion)
	end)

	it("corrects teleports back to the last valid position", function()
		local state = MovementValidator.new()
		MovementValidator.Sample(state, Vector3.new(0, 0, 0), 0, limits)
		MovementValidator.Sample(state, Vector3.new(2, 0, 0), 0.25, limits)
		local verdict = MovementValidator.Sample(state, Vector3.new(500, 0, 0), 0.5, limits)
		expect(verdict).toBe("Correct")
		expect(state.LastValid.X).toBe(2)
	end)

	it("does not flag server-initiated teleports during the grace period", function()
		local state = MovementValidator.new()
		MovementValidator.Sample(state, Vector3.new(0, 0, 0), 0, limits)
		MovementValidator.Teleported(state, Vector3.new(800, 0, 0), 0.1, M.TeleportGraceSeconds)
		expect((MovementValidator.Sample(state, Vector3.new(801, 0, 0), 0.3, limits))).toBe("Ok")
	end)
end)

describe("SuspicionScore", function()
	it("accumulates and decays over time", function()
		local state = SuspicionScore.new(0)
		SuspicionScore.Add(state, "InvalidShot", 30, 0, 10)
		expect(SuspicionScore.Current(state, 60, 10)).toBeNear(20, 1e-9)
		expect(SuspicionScore.Current(state, 600, 10)).toBe(0)
	end)
end)

describe("MatchRules", function()
	it("ranks by eliminations, then deaths, then assists", function()
		local a = MatchRules.NewEntry(1, "a", 1)
		local b = MatchRules.NewEntry(2, "b", 2)
		local c = MatchRules.NewEntry(3, "c", 3)
		a.Eliminations, b.Eliminations, c.Eliminations = 5, 5, 7
		a.Deaths, b.Deaths = 3, 1
		local ranked = MatchRules.Rank({ a, b, c })
		expect(ranked[1].UserId).toBe(3)
		expect(ranked[2].UserId).toBe(2)
		expect(ranked[3].UserId).toBe(1)
	end)

	it("tracks streaks and announces configured thresholds", function()
		local killer = MatchRules.NewEntry(1, "k", 1)
		local announced = {}
		for i = 1, 5 do
			local victim = MatchRules.NewEntry(100 + i, "v", 2)
			local streak =
				MatchRules.RecordElimination(killer, victim, {}, Config.Combat.Killstreaks.AnnounceAt)
			if streak then
				table.insert(announced, streak)
			end
		end
		expect(announced).toEqual({ 3, 5 })
		expect(killer.BestStreak).toBe(5)
	end)

	it("environmental deaths count as deaths without crediting anyone", function()
		local victim = MatchRules.NewEntry(1, "v", 1)
		victim.Streak = 4
		expect(MatchRules.RecordElimination(nil, victim, {}, { 3 })).toBeNil()
		expect(victim.Deaths).toBe(1)
		expect(victim.Streak).toBe(0)
	end)
end)
