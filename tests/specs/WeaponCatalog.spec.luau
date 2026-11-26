--!nocheck
local fs = require("@lune/fs")
local Config = Runtime:Get("ReplicatedStorage/Shared/Config")
local WeaponCatalog = Runtime:Get("ReplicatedStorage/Shared/Weapons/WeaponCatalog")
local DamageCalculator = Runtime:Get("ReplicatedStorage/Shared/Combat/DamageCalculator")

describe("WeaponCatalog", function()
	it("passes structural validation", function()
		local problems = WeaponCatalog.Validate()
		expect(#problems).toBe(0)
	end)

	it("provides a complete starter loadout of primary, secondary and knife", function()
		local loadout = WeaponCatalog.StarterLoadout()
		expect(WeaponCatalog.SlotFor(loadout.Primary)).toBe("Primary")
		expect(WeaponCatalog.SlotFor(loadout.Secondary)).toBe("Secondary")
		expect(WeaponCatalog.SlotFor(loadout.Knife)).toBe("Knife")
	end)

	it("weapon rarity does not automatically increase combat power", function()
		-- Stats are returned by archetype identity: the rarity of the entry cannot reach them.
		for id, entry in Config.Catalog.Entries do
			local archetype = Config.Archetypes[entry.Archetype]
			expect(WeaponCatalog.GetFirearmStats(id)).toBe(archetype.Firearm)
			expect(WeaponCatalog.GetKnifeStats(id)).toBe(archetype.Knife)
		end
	end)

	it("no combat module reads rarity", function()
		local roots = { "src/shared/Combat", "src/server/Domain", "src/server/Services" }
		local offenders = {}
		local function scan(directory)
			for _, entry in fs.readDir(directory) do
				local path = directory .. "/" .. entry
				if fs.isDir(path) then
					scan(path)
				elseif string.find(fs.readFile(path), "Rarity", 1, true) then
					table.insert(offenders, path)
				end
			end
		end
		for _, directory in roots do
			scan(Runtime.Root .. "/" .. directory)
		end
		expect(#offenders).toBe(0)
	end)

	it("base damage values match the specification", function()
		local A = Config.Archetypes
		expect(A.AssaultRifle.Firearm.Damage).toBe(25)
		expect(A.SubmachineGun.Firearm.Damage).toBe(18)
		expect(A.SniperRifle.Firearm.Damage).toBe(100)
		expect(A.Pistol.Firearm.Damage).toBe(35)
		expect(A.Revolver.Firearm.Damage).toBe(60)
		expect(A.Dagger.Knife.Stab.Damage).toBe(60)
		expect(A.Karambit.Knife.Stab.Damage).toBe(45)
		expect(A.ButterflyKnife.Knife.Stab.Damage).toBe(50)
		expect(A.CombatKnife.Knife.Stab.Damage).toBe(75)
		local shotgun = A.Shotgun.Firearm
		expect(shotgun.Damage * shotgun.Pellets).toBe(100)
	end)

	it("every rarity tier has a non-colour symbol", function()
		local seen = {}
		for _, id in Config.Rarity.Order do
			local tier = Config.Rarity.Tiers[id]
			expect(type(tier.Symbol)).toBe("string")
			expect(seen[tier.Symbol]).toBeNil()
			seen[tier.Symbol] = true
		end
	end)
end)

describe("DamageCalculator", function()
	local A = Config.Archetypes

	it("applies full damage before falloff and the minimum after", function()
		local ar = A.AssaultRifle.Firearm
		expect(DamageCalculator.Firearm(ar, 10, "Body")).toBe(25)
		expect(DamageCalculator.Firearm(ar, ar.FalloffEnd + 1, "Body")).toBe(17.5)
		expect(DamageCalculator.Firearm(ar, 120, "Body")).toBe(21.3)
	end)

	it("applies the configured headshot multiplier", function()
		local ar = A.AssaultRifle.Firearm
		expect(DamageCalculator.Firearm(ar, 10, "Head")).toBe(37.5)
		expect(DamageCalculator.Firearm(A.SniperRifle.Firearm, 500, "Head")).toBe(200)
	end)

	it("returns zero beyond range", function()
		local pistol = A.Pistol.Firearm
		expect(DamageCalculator.Firearm(pistol, pistol.Range + 1, "Head")).toBe(0)
	end)

	it("caps shotgun damage at 100 at close range", function()
		local shotgun = A.Shotgun.Firearm
		local total = 0
		for _ = 1, shotgun.Pellets do
			total += DamageCalculator.Firearm(shotgun, 5, "Head")
		end
		expect(total).toBe(100)
	end)
end)
