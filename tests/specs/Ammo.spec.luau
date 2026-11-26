--!nocheck
local AmmoState = Runtime:Get("ReplicatedStorage/Shared/Combat/AmmoState")
local Archetypes = Runtime:Get("ReplicatedStorage/Shared/Config/Weapons/Archetypes")

describe("AmmoState", function()
	it("a player cannot fire without ammunition", function()
		local state = AmmoState.new(2, 0, 1)
		expect(AmmoState.Consume(state, 0)).toBe(true)
		expect(AmmoState.Consume(state, 0)).toBe(true)
		expect(AmmoState.Consume(state, 0)).toBe(false)
		local ok, reason = AmmoState.CanFire(state, 0)
		expect(ok).toBe(false)
		expect(reason).toBe("Empty")
		expect(state.Magazine).toBe(0)
	end)

	it("cannot reload with an empty reserve or a full magazine", function()
		local empty = AmmoState.new(5, 0, 1)
		empty.Magazine = 1
		expect(select(2, AmmoState.StartReload(empty, 0))).toBe("NoReserve")
		local full = AmmoState.new(5, 10, 1)
		expect(select(2, AmmoState.StartReload(full, 0))).toBe("MagazineFull")
	end)

	it("blocks firing during reload and completes exactly at the reload time", function()
		local state = AmmoState.new(30, 90, 2.2)
		state.Magazine = 10
		expect(AmmoState.StartReload(state, 5)).toBe(true)
		expect(select(2, AmmoState.CanFire(state, 6))).toBe("Reloading")
		expect(AmmoState.IsReloading(state, 7.19)).toBe(true)
		expect(AmmoState.CanFire(state, 7.2)).toBe(true)
		expect(state.Magazine).toBe(30)
		expect(state.Reserve).toBe(70)
	end)

	it("moves only what the reserve holds", function()
		local state = AmmoState.new(30, 90, 1)
		state.Magazine = 0
		state.Reserve = 12
		AmmoState.StartReload(state, 0)
		AmmoState.Update(state, 1)
		expect(state.Magazine).toBe(12)
		expect(state.Reserve).toBe(0)
	end)

	it("cancelling a reload moves no rounds", function()
		local state = AmmoState.new(30, 90, 1)
		state.Magazine = 3
		AmmoState.StartReload(state, 0)
		AmmoState.CancelReload(state)
		AmmoState.Update(state, 5)
		expect(state.Magazine).toBe(3)
		expect(state.Reserve).toBe(90)
	end)

	it("caps reserve refills at the maximum and rejects negative amounts", function()
		local state = AmmoState.new(30, 90, 1)
		state.Reserve = 80
		expect(AmmoState.AddReserve(state, 30)).toBe(10)
		expect(state.Reserve).toBe(90)
		expect(AmmoState.AddReserve(state, -50)).toBe(0)
		expect(AmmoState.IsReserveFull(state)).toBe(true)
	end)

	it("archetype magazine and reserve sizes match the specification", function()
		local expected = {
			AssaultRifle = { 30, 90 },
			SubmachineGun = { 25, 75 },
			Shotgun = { 6, 18 },
			SniperRifle = { 5, 15 },
			Pistol = { 12, 36 },
			Revolver = { 6, 18 },
		}
		for id, sizes in expected do
			local firearm = Archetypes[id].Firearm
			expect(firearm.MagazineSize).toBe(sizes[1])
			expect(firearm.MaxReserve).toBe(sizes[2])
		end
	end)
end)
