--!nocheck
local Loadout = Runtime:Get("ServerScriptService/Server/Domain/Loadout")
local Schema = Runtime:Get("ServerScriptService/Server/Data/Schema")

describe("Loadout.Resolve", function()
	it("resolves a valid owned preset unchanged", function()
		local data = Schema.Default(1, 0)
		local loadout, problems = Loadout.Resolve(data.Inventory.Weapons, data.Loadouts.Presets[1])
		expect(#problems).toBe(0)
		expect(loadout.Primary).toBe("classic_ar_vanguard")
	end)

	it("a player cannot attack with an unowned weapon: unowned preset entries are replaced", function()
		local inventory = { classic_pistol_warden = {}, classic_knife_ranger = {} } -- rifle not owned
		local loadout, problems = Loadout.Resolve(inventory, {
			Primary = "classic_ar_vanguard",
			Secondary = "classic_pistol_warden",
			Knife = "classic_knife_ranger",
		})
		expect(#problems).toBe(1)
		expect(problems[1].Reason).toBe("NotOwned")
		expect(loadout.Primary).toBe("classic_ar_vanguard") -- starter fallback, always granted
	end)

	it("rejects unknown ids and weapons placed in the wrong slot", function()
		local data = Schema.Default(1, 0)
		local loadout, problems = Loadout.Resolve(data.Inventory.Weapons, {
			Primary = "classic_knife_ranger",
			Secondary = "made_up_gun",
			Knife = 42,
		})
		expect(#problems).toBe(3)
		expect(problems[1].Reason).toBe("WrongSlot")
		expect(loadout.Primary).toBe("classic_ar_vanguard")
		expect(loadout.Secondary).toBe("classic_pistol_warden")
		expect(loadout.Knife).toBe("classic_knife_ranger")
	end)

	it("handles a missing preset or inventory", function()
		local loadout = Loadout.Resolve(nil, nil)
		expect(loadout.Knife).toBe("classic_knife_ranger")
	end)
end)
