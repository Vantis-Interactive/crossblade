--!nocheck
local Config = Runtime:Get("ReplicatedStorage/Shared/Config")
local CrateOdds = Runtime:Get("ReplicatedStorage/Shared/Economy/CrateOdds")
local Leveling = Runtime:Get("ReplicatedStorage/Shared/Economy/Leveling")
local Wallet = Runtime:Get("ReplicatedStorage/Shared/Economy/Wallet")
local CrateOpening = Runtime:Get("ServerScriptService/Server/Domain/CrateOpening")
local PaidRandomPolicy = Runtime:Get("ServerScriptService/Server/Domain/PaidRandomPolicy")
local RewardPolicy = Runtime:Get("ServerScriptService/Server/Domain/RewardPolicy")
local Transactions = Runtime:Get("ServerScriptService/Server/Data/Transactions")
local Schema = Runtime:Get("ServerScriptService/Server/Data/Schema")

local E = Config.Economy
local CRATES = Config.Crates.Crates

local function openArgs(crateId, roll, requestId, allowPurchased)
	local crate = CRATES[crateId]
	return {
		CrateId = crateId,
		Price = crate.Price,
		Distribution = CrateOdds.Build(crate),
		Roll = roll,
		RequestId = requestId,
		Now = 1000,
		AllowPurchased = allowPurchased,
		Compensation = E.DuplicateCompensation,
		HistoryLimit = E.CrateHistoryLimit,
	}
end

describe("Crate configuration", function()
	it("uses the specified prices and standard distribution", function()
		local expected = {
			basic = 250,
			premium = 750,
			legendary = 2500,
			mythical = 5000,
			knife = 500,
			pistol = 500,
			rifle = 750,
			shotgun = 750,
			sniper = 1000,
			inferno = 1500,
			arctic = 1500,
			cyberpunk = 2000,
			galaxy = 2500,
		}
		for id, price in expected do
			expect(CRATES[id].Price).toBe(price)
		end
		expect(Config.Crates.Standard).toEqual({
			Common = 40,
			Uncommon = 25,
			Rare = 18,
			Epic = 10,
			Legendary = 5,
			Mythical = 1.8,
			Celestial = 0.2,
		})
		expect(CRATES.basic.Odds).toBe(Config.Crates.Standard)
	end)

	it("every crate passes validation (pool, odds, price, compensation, economic impact)", function()
		for id, crate in CRATES do
			local problems = CrateOdds.Validate(crate, CrateOdds.Build(crate))
			if #problems > 0 then
				error(`{id}: {table.concat(problems, "; ")}`)
			end
		end
	end)

	it("crates cannot generate net coins for a player who owns everything", function()
		for _, crate in CRATES do
			local expected = CrateOdds.ExpectedCompensation(CrateOdds.Build(crate), E.DuplicateCompensation)
			expect(expected).toBeLessThan(crate.Price)
		end
		expect(CrateOdds.ExpectedCompensation(CrateOdds.Build(CRATES.basic), E.DuplicateCompensation)).toBeNear(
			245,
			1e-9
		)
	end)

	it("validation rejects broken crates", function()
		local base = CRATES.basic
		local function check(overrides)
			local crate = table.clone(base)
			for k, v in overrides do
				crate[k] = v
			end
			return #CrateOdds.Validate(crate, CrateOdds.Build(crate))
		end
		expect(check({ Odds = { Common = 50, Rare = 40 } })).toBeGreaterThan(0) -- sums to 90
		expect(check({ Price = 10 })).toBeGreaterThan(0) -- compensation exceeds price
		expect(check({ Price = 0 })).toBeGreaterThan(0)
		expect(check({ Filter = { Collection = "Shadow" } })).toBeGreaterThan(0) -- rarities with no items
	end)

	it("starter weapons are never in a crate pool", function()
		for _, crate in CRATES do
			for _, entry in CrateOdds.Build(crate).Entries do
				expect(Config.Catalog.Entries[entry.WeaponId].Starter).toBe(false)
			end
		end
	end)

	it("disclosed per-item odds sum to each rarity's configured share", function()
		for _, crate in CRATES do
			local distribution = CrateOdds.Build(crate)
			for rarity, percent in crate.Odds do
				expect(CrateOdds.RarityTotal(distribution, rarity) * 100).toBeNear(percent, 1e-9)
			end
		end
	end)
end)

describe("Crate selection equals disclosed odds", function()
	it("stratified rolls reproduce every item's probability exactly", function()
		local N = 100000
		for _, crate in CRATES do
			local distribution = CrateOdds.Build(crate)
			local counts = {}
			for i = 1, N do
				local entry = CrateOdds.Select(distribution, (i - 0.5) / N)
				counts[entry.WeaponId] = (counts[entry.WeaponId] or 0) + 1
			end
			for _, entry in distribution.Entries do
				expect(math.abs((counts[entry.WeaponId] or 0) - entry.Probability * N)).toBeAtMost(1)
			end
		end
	end)

	it("seeded random rolls pass a chi-squared goodness-of-fit test", function()
		math.randomseed(20261126)
		local distribution = CrateOdds.Build(CRATES.basic)
		local N = 200000
		local counts = {}
		for _ = 1, N do
			local entry = CrateOdds.Select(distribution, math.random())
			counts[entry.WeaponId] = (counts[entry.WeaponId] or 0) + 1
		end
		local chi = 0
		for _, entry in distribution.Entries do
			local expected = entry.Probability * N
			chi += ((counts[entry.WeaponId] or 0) - expected) ^ 2 / expected
		end
		-- df = entries - 1; critical value at p = 0.001 for df <= 40 is below 73.4.
		expect(#distribution.Entries).toBeAtMost(41)
		expect(chi).toBeLessThan(73.4)
	end)

	it("rejects rolls outside [0, 1)", function()
		local distribution = CrateOdds.Build(CRATES.basic)
		expect(function()
			CrateOdds.Select(distribution, 1)
		end).toThrow("roll out of range")
	end)
end)

describe("Crate opening", function()
	local function profile(earned, purchased)
		local data = Schema.Default(1, 0)
		data.Currency.Earned = earned
		data.Currency.Purchased = purchased or 0
		return data
	end

	it("grants a new weapon and debits the price", function()
		local data = profile(1000)
		local result
		Transactions.Apply(data, "crate:a", 1, 200, function(draft)
			result = CrateOpening.Open(draft, openArgs("basic", 0.0001, "a", false))
		end)
		expect(result.Duplicate).toBe(false)
		expect(data.Inventory.Weapons[result.WeaponId]).never.toBeNil()
		expect(data.Currency.Earned).toBe(750)
		expect(data.Stats.CratesOpened).toBe(1)
	end)

	it("duplicate crate rewards provide exactly the configured compensation", function()
		for _, rarity in Config.Rarity.Order do
			local crate = CRATES.knife
			local distribution = CrateOdds.Build(crate)
			-- Find a roll that selects an item of this rarity.
			local roll, chosen = nil, nil
			local cumulative = 0
			for _, entry in distribution.Entries do
				if entry.Rarity == rarity and roll == nil then
					roll, chosen = cumulative + entry.Probability / 2, entry.WeaponId
				end
				cumulative += entry.Probability
			end
			local data = profile(crate.Price)
			data.Inventory.Weapons[chosen] = { AcquiredAt = 0, Source = "Test" }
			local result
			Transactions.Apply(data, "crate:" .. rarity, 1, 200, function(draft)
				result = CrateOpening.Open(draft, openArgs("knife", roll, rarity, false))
			end)
			expect(result.Duplicate).toBe(true)
			expect(result.Compensation).toBe(E.DuplicateCompensation[rarity])
			expect(data.Currency.Earned).toBe(E.DuplicateCompensation[rarity])
		end
	end)

	it("a replayed request cannot charge or reward twice", function()
		local data = profile(1000)
		local function attempt()
			return Transactions.Apply(data, "crate:req-1", 1, 200, function(draft)
				CrateOpening.Open(draft, openArgs("basic", 0.5, "req-1", false))
			end)
		end
		expect(attempt()).toBe("Applied")
		expect(attempt()).toBe("AlreadyApplied")
		expect(data.Currency.Earned).toBe(750)
		expect(data.Stats.CratesOpened).toBe(1)
		expect(CrateOpening.FindResult(data, "req-1")).never.toBeNil()
	end)

	it("is atomic: insufficient funds leave the profile untouched", function()
		local data = profile(100)
		local before = Schema.Default(1, 0)
		local outcome, err = Transactions.Apply(data, "crate:poor", 1, 200, function(draft)
			CrateOpening.Open(draft, openArgs("basic", 0.5, "poor", false))
		end)
		expect(outcome).toBe("Failed")
		expect(err).toBe("InsufficientFunds")
		expect(data.Currency.Earned).toBe(100)
		expect(data.Stats.CratesOpened).toBe(before.Stats.CratesOpened)
		expect(#data.CrateHistory).toBe(0)
	end)

	it("ineligible users cannot spend purchased coins on paid randomized rewards", function()
		local data = profile(100, 5000)
		local outcome, err = Transactions.Apply(data, "crate:ineligible", 1, 200, function(draft)
			CrateOpening.Open(draft, openArgs("basic", 0.5, "ineligible", false))
		end)
		expect(outcome).toBe("Failed")
		expect(err).toBe("InsufficientEarnedFunds")
		expect(data.Currency.Purchased).toBe(5000)
	end)

	it("eligible users spend earned coins first, then purchased", function()
		local data = profile(100, 5000)
		local result
		Transactions.Apply(data, "crate:eligible", 1, 200, function(draft)
			result = CrateOpening.Open(draft, openArgs("basic", 0.5, "eligible", true))
		end)
		expect(result.FromEarned).toBe(100)
		expect(result.FromPurchased).toBe(150)
		expect(data.Currency.Purchased).toBe(4850)
	end)

	it("keeps crate history bounded", function()
		local data = profile(250 * 60)
		for i = 1, 60 do
			Transactions.Apply(data, "crate:h" .. i, i, 200, function(draft)
				CrateOpening.Open(draft, openArgs("basic", 0.5, "h" .. i, false))
			end)
		end
		expect(#data.CrateHistory).toBe(E.CrateHistoryLimit)
	end)
end)

describe("Paid random item policy (fail closed)", function()
	it("allows purchased currency only for a successful, unrestricted lookup", function()
		expect(PaidRandomPolicy.Decide(true, { ArePaidRandomItemsRestricted = false })).toBe("Allowed")
		expect(PaidRandomPolicy.AllowsPurchasedCurrency("Allowed")).toBe(true)
	end)
	it("blocks restricted users", function()
		expect(PaidRandomPolicy.Decide(true, { ArePaidRandomItemsRestricted = true })).toBe("Restricted")
		expect(PaidRandomPolicy.AllowsPurchasedCurrency("Restricted")).toBe(false)
	end)
	it("failed policy lookups block restricted purchases", function()
		expect(PaidRandomPolicy.Decide(false, "HTTP 500")).toBe("Unknown")
		expect(PaidRandomPolicy.Decide(true, nil)).toBe("Unknown")
		expect(PaidRandomPolicy.Decide(true, {})).toBe("Unknown")
		expect(PaidRandomPolicy.Decide(true, { ArePaidRandomItemsRestricted = "no" })).toBe("Unknown")
		expect(PaidRandomPolicy.AllowsPurchasedCurrency("Unknown")).toBe(false)
		expect(PaidRandomPolicy.AllowsPurchasedCurrency(nil)).toBe(false)
	end)
end)

describe("Wallet", function()
	it("reports one total while keeping balances separate", function()
		local currency = { Earned = 30, Purchased = 70 }
		expect(Wallet.Total(currency)).toBe(100)
		expect(Wallet.Spendable(currency, false)).toBe(30)
	end)
	it("rejects fractional or negative amounts", function()
		expect(function()
			Wallet.CreditEarned({ Earned = 0, Purchased = 0 }, -5)
		end).toThrow()
		expect(function()
			Wallet.Debit({ Earned = 10, Purchased = 0 }, 1.5, false)
		end).toThrow()
	end)
end)

describe("Leveling", function()
	it("follows the configured curve", function()
		expect(Leveling.XPForNext(1)).toBe(1000)
		expect(Leveling.XPForNext(2)).toBe(1100)
		expect(Leveling.Info(999).Level).toBe(1)
		expect(Leveling.Info(1000).Level).toBe(2)
		expect(Leveling.Info(2100).Level).toBe(3)
		expect(Leveling.Info(1e9).Level).toBe(Config.Progression.MaxLevel)
		expect(Leveling.Info(1e9).AtMax).toBe(true)
	end)
	it("pays level rewards once, including milestone bonuses", function()
		local progression = { LifetimeXP = 0, Level = 1, HighestRewardedLevel = 1 }
		local xpToTen = 0
		for level = 1, 9 do
			xpToTen += Leveling.XPForNext(level)
		end
		local result = Leveling.ApplyXP(progression, xpToTen)
		expect(progression.Level).toBe(10)
		expect(result.LevelsGained).toBe(9)
		expect(result.RewardCoins).toBe(9 * 100 + 400)
		-- A prestige-style reset of Level cannot re-pay rewards for levels already rewarded.
		progression.Level = 1
		progression.LifetimeXP = 0
		local again = Leveling.ApplyXP(progression, xpToTen)
		expect(again.RewardCoins).toBe(0)
	end)
	it("ignores negative and fractional XP", function()
		local progression = { LifetimeXP = 0, Level = 1, HighestRewardedLevel = 1 }
		expect(Leveling.ApplyXP(progression, -500).Granted).toBe(0)
		expect(Leveling.ApplyXP(progression, 10.9).Granted).toBe(10)
	end)
end)

describe("RewardPolicy", function()
	local function context(overrides)
		local c = {
			Enabled = true,
			Population = 4,
			Now = 100,
			Guard = RewardPolicy.NewGuard(),
			Rewards = E.Rewards,
			Experience = E.Experience,
			AntiFarming = E.AntiFarming,
		}
		for k, v in overrides or {} do
			c[k] = v
		end
		return c
	end
	local function event(overrides)
		local e = {
			KillerId = 1,
			VictimId = 2,
			Kind = "Firearm",
			Headshot = false,
			AssistIds = {},
			KillerStreak = 1,
		}
		for k, v in overrides or {} do
			e[k] = v
		end
		return e
	end

	it("pays the specified elimination, headshot and assist coins", function()
		expect(RewardPolicy.Evaluate(event(), context())[1].Coins).toBe(25)
		expect(RewardPolicy.Evaluate(event({ Kind = "Knife" }), context())[1].Coins).toBe(35)
		expect(RewardPolicy.Evaluate(event({ Kind = "ThrownKnife" }), context())[1].Coins).toBe(35)
		expect(RewardPolicy.Evaluate(event({ Headshot = true }), context())[1].Coins).toBe(35)
		local grants = RewardPolicy.Evaluate(event({ AssistIds = { 3 } }), context())
		expect(grants[3].Coins).toBe(10)
	end)

	it("pays the five-elimination streak bonus", function()
		expect(RewardPolicy.Evaluate(event({ KillerStreak = 5 }), context())[1].Coins).toBe(25 + 50)
		expect(RewardPolicy.Evaluate(event({ KillerStreak = 10 }), context())[1].Coins).toBe(25 + 50)
		expect(RewardPolicy.Evaluate(event({ KillerStreak = 6 }), context())[1].Coins).toBe(25)
	end)

	it("pays nothing for self, environmental or disabled-mode eliminations", function()
		expect(next(RewardPolicy.Evaluate(event({ KillerId = 2 }), context()))).toBeNil()
		local environmental = event({ Kind = "Environment" })
		environmental.KillerId = nil
		expect(next(RewardPolicy.Evaluate(environmental, context()))).toBeNil()
		expect(next(RewardPolicy.Evaluate(event(), context({ Enabled = false })))).toBeNil()
		expect(next(RewardPolicy.Evaluate(event(), context({ Population = 1 })))).toBeNil()
	end)

	it("stops rewarding repeated farming of the same victim", function()
		local c = context()
		local limit = E.AntiFarming.RepeatVictim
		for _ = 1, limit.MaxRewarded do
			expect(RewardPolicy.Evaluate(event(), c)[1]).never.toBeNil()
		end
		expect(next(RewardPolicy.Evaluate(event(), c))).toBeNil()
		-- A different victim is still rewarded, and the pair recovers after the window.
		expect(RewardPolicy.Evaluate(event({ VictimId = 9 }), c)[1]).never.toBeNil()
		c.Now += limit.WindowSeconds + 1
		expect(RewardPolicy.Evaluate(event(), c)[1]).never.toBeNil()
	end)

	it("caps match rewards per rolling hour", function()
		local economy = { HourStart = 0, HourCoins = 0, HourXP = 0 }
		local cap = E.AntiFarming.HourlyCoinCap
		local coins = RewardPolicy.ApplyHourlyCap(economy, 10, cap - 5, 0, E.AntiFarming)
		expect(coins).toBe(cap - 5)
		expect((RewardPolicy.ApplyHourlyCap(economy, 20, 25, 0, E.AntiFarming))).toBe(5)
		expect((RewardPolicy.ApplyHourlyCap(economy, 30, 25, 0, E.AntiFarming))).toBe(0)
		expect((RewardPolicy.ApplyHourlyCap(economy, 3700, 25, 0, E.AntiFarming))).toBe(25)
	end)
end)

describe("Schema v2 migration", function()
	it("upgrades a v1 profile without retroactive level rewards and keeps existing data", function()
		local v1 = Schema.Default(5, 0)
		v1.SchemaVersion = 1
		v1.Progression = { LifetimeXP = 50000, Level = 30, Prestige = 0 }
		v1.CrateHistory = nil
		v1.Economy = nil
		v1.Currency.Earned = 777
		local result = Schema.Migrate(v1, 5, 10)
		expect(result.Ok).toBe(true)
		expect(result.Data.SchemaVersion).toBe(2)
		expect(result.Data.Progression.HighestRewardedLevel).toBe(30)
		expect(result.Data.Currency.Earned).toBe(777)
		expect(type(result.Data.CrateHistory)).toBe("table")
		expect(result.Data.Economy.HourCoins).toBe(0)
	end)
end)
