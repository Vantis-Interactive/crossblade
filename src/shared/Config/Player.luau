--!strict
--[[
	Player and character configuration.
	All players share identical movement and hitbox values (spec §6). Avatars are cosmetic only:
	combat hit detection uses the standardized hitbox below, never avatar part geometry.
]]

local Player = {
	MaxHealth = 150,
	-- No automatic regeneration exists anywhere in the codebase (spec §7). Recovery is pickups only.
	HealthRegeneration = false,

	Movement = {
		WalkSpeed = 16,
		RunSpeed = 22,
		JumpPower = 50,
	},

	-- Standardized combat hitbox, expressed in HumanoidRootPart object space (studs).
	-- Body: vertical capsule between BodyBottom and BodyTop with BodyRadius.
	-- Head: sphere centred at HeadOffset with HeadRadius.
	Hitbox = {
		BodyBottom = -2.4,
		BodyTop = 1.1,
		BodyRadius = 1.15,
		HeadOffset = 1.85,
		HeadRadius = 0.75,
	},
}

return table.freeze(Player)
