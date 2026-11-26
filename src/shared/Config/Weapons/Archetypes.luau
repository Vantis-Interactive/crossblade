--!strict
--[[
	Weapon archetypes (spec §8). Every collectible weapon references exactly one archetype, and ALL
	combat statistics come from the archetype. Collectibles never carry combat stats of their own,
	which is how "higher rarity must not indicate greater combat power" is enforced structurally.

	Damage values are the provisional base values from the specification. Distances are in studs.
]]

export type Category = "Primary" | "Secondary" | "Knife"
export type FireMode = "Automatic" | "SemiAutomatic"

export type FirearmStats = {
	Damage: number, -- per pellet when Pellets > 1
	Pellets: number,
	HeadshotMultiplier: number,
	FireMode: FireMode,
	RoundsPerMinute: number,
	MagazineSize: number,
	MaxReserve: number,
	ReloadSeconds: number,
	EquipSeconds: number,
	Range: number,
	FalloffStart: number,
	FalloffEnd: number,
	MinDamageMultiplier: number,
	HipSpreadDegrees: number,
	AimSpreadDegrees: number,
	AimFieldOfView: number,
	RecoilPitchDegrees: number,
	RecoilYawDegrees: number,
}

export type MeleeAttackStats = {
	Damage: number,
	CooldownSeconds: number,
	Range: number,
	ConeDegrees: number,
}

export type ThrowStats = {
	Damage: number,
	HeadshotMultiplier: number,
	CooldownSeconds: number,
	Speed: number,
	Gravity: number,
	MaxFlightSeconds: number,
	-- Seconds a landed knife remains in the world awaiting recovery before it despawns.
	-- After despawn the owner must use a knife station or respawn.
	GroundLifetimeSeconds: number,
	RecoverRadius: number,
}

export type KnifeStats = {
	Slash: MeleeAttackStats,
	Stab: MeleeAttackStats,
	Throw: ThrowStats,
	EquipSeconds: number,
}

export type Archetype = {
	Id: string,
	DisplayName: string,
	Category: Category,
	Firearm: FirearmStats?,
	Knife: KnifeStats?,
}

local function firearm(stats: FirearmStats): FirearmStats
	return table.freeze(stats)
end

local function knife(
	stab: number,
	stabCooldown: number,
	slash: number,
	slashCooldown: number,
	throwCooldown: number
): KnifeStats
	return table.freeze({
		Stab = table.freeze({ Damage = stab, CooldownSeconds = stabCooldown, Range = 6.5, ConeDegrees = 50 }),
		Slash = table.freeze({ Damage = slash, CooldownSeconds = slashCooldown, Range = 7, ConeDegrees = 70 }),
		Throw = table.freeze({
			Damage = stab,
			HeadshotMultiplier = 1.5,
			CooldownSeconds = throwCooldown,
			Speed = 140,
			Gravity = 40,
			MaxFlightSeconds = 2.5,
			GroundLifetimeSeconds = 30,
			RecoverRadius = 5,
		}),
		EquipSeconds = 0.25,
	})
end

local Archetypes: { [string]: Archetype } = {
	AssaultRifle = {
		Id = "AssaultRifle",
		DisplayName = "Assault Rifle",
		Category = "Primary",
		Firearm = firearm({
			Damage = 25,
			Pellets = 1,
			HeadshotMultiplier = 1.5,
			FireMode = "Automatic",
			RoundsPerMinute = 600,
			MagazineSize = 30,
			MaxReserve = 90,
			ReloadSeconds = 2.2,
			EquipSeconds = 0.45,
			Range = 300,
			FalloffStart = 60,
			FalloffEnd = 180,
			MinDamageMultiplier = 0.7,
			HipSpreadDegrees = 2.0,
			AimSpreadDegrees = 0.6,
			AimFieldOfView = 55,
			RecoilPitchDegrees = 0.9,
			RecoilYawDegrees = 0.35,
		}),
	},
	SubmachineGun = {
		Id = "SubmachineGun",
		DisplayName = "SMG",
		Category = "Primary",
		Firearm = firearm({
			Damage = 18,
			Pellets = 1,
			HeadshotMultiplier = 1.4,
			FireMode = "Automatic",
			RoundsPerMinute = 850,
			MagazineSize = 25,
			MaxReserve = 75,
			ReloadSeconds = 1.9,
			EquipSeconds = 0.35,
			Range = 180,
			FalloffStart = 25,
			FalloffEnd = 90,
			MinDamageMultiplier = 0.6,
			HipSpreadDegrees = 2.6,
			AimSpreadDegrees = 1.1,
			AimFieldOfView = 62,
			RecoilPitchDegrees = 0.7,
			RecoilYawDegrees = 0.45,
		}),
	},
	Shotgun = {
		Id = "Shotgun",
		DisplayName = "Shotgun",
		Category = "Primary",
		-- 8 pellets x 12.5 = 100 damage maximum at close range ("up to 100").
		Firearm = firearm({
			Damage = 12.5,
			Pellets = 8,
			HeadshotMultiplier = 1.0,
			FireMode = "SemiAutomatic",
			RoundsPerMinute = 70,
			MagazineSize = 6,
			MaxReserve = 18,
			ReloadSeconds = 3.0,
			EquipSeconds = 0.5,
			Range = 80,
			FalloffStart = 10,
			FalloffEnd = 40,
			MinDamageMultiplier = 0.3,
			HipSpreadDegrees = 6.0,
			AimSpreadDegrees = 4.5,
			AimFieldOfView = 68,
			RecoilPitchDegrees = 4.0,
			RecoilYawDegrees = 1.0,
		}),
	},
	SniperRifle = {
		Id = "SniperRifle",
		DisplayName = "Sniper Rifle",
		Category = "Primary",
		Firearm = firearm({
			Damage = 100,
			Pellets = 1,
			HeadshotMultiplier = 2.0,
			FireMode = "SemiAutomatic",
			RoundsPerMinute = 45,
			MagazineSize = 5,
			MaxReserve = 15,
			ReloadSeconds = 3.2,
			EquipSeconds = 0.7,
			Range = 1000,
			FalloffStart = 1000,
			FalloffEnd = 1000,
			MinDamageMultiplier = 1.0,
			HipSpreadDegrees = 8.0,
			AimSpreadDegrees = 0.0,
			AimFieldOfView = 25,
			RecoilPitchDegrees = 5.0,
			RecoilYawDegrees = 0.8,
		}),
	},
	Pistol = {
		Id = "Pistol",
		DisplayName = "Pistol",
		Category = "Secondary",
		Firearm = firearm({
			Damage = 35,
			Pellets = 1,
			HeadshotMultiplier = 1.5,
			FireMode = "SemiAutomatic",
			RoundsPerMinute = 400,
			MagazineSize = 12,
			MaxReserve = 36,
			ReloadSeconds = 1.6,
			EquipSeconds = 0.3,
			Range = 200,
			FalloffStart = 30,
			FalloffEnd = 100,
			MinDamageMultiplier = 0.65,
			HipSpreadDegrees = 1.5,
			AimSpreadDegrees = 0.5,
			AimFieldOfView = 65,
			RecoilPitchDegrees = 1.6,
			RecoilYawDegrees = 0.4,
		}),
	},
	Revolver = {
		Id = "Revolver",
		DisplayName = "Revolver",
		Category = "Secondary",
		Firearm = firearm({
			Damage = 60,
			Pellets = 1,
			HeadshotMultiplier = 1.6,
			FireMode = "SemiAutomatic",
			RoundsPerMinute = 120,
			MagazineSize = 6,
			MaxReserve = 18,
			ReloadSeconds = 2.6,
			EquipSeconds = 0.35,
			Range = 250,
			FalloffStart = 40,
			FalloffEnd = 140,
			MinDamageMultiplier = 0.7,
			HipSpreadDegrees = 2.0,
			AimSpreadDegrees = 0.4,
			AimFieldOfView = 60,
			RecoilPitchDegrees = 3.5,
			RecoilYawDegrees = 0.6,
		}),
	},
	Dagger = {
		Id = "Dagger",
		DisplayName = "Dagger",
		Category = "Knife",
		Knife = knife(60, 0.7, 36, 0.38, 1.0),
	},
	Karambit = {
		Id = "Karambit",
		DisplayName = "Karambit",
		Category = "Knife",
		Knife = knife(45, 0.5, 30, 0.3, 0.9),
	},
	ButterflyKnife = {
		Id = "ButterflyKnife",
		DisplayName = "Butterfly Knife",
		Category = "Knife",
		Knife = knife(50, 0.6, 32, 0.33, 0.95),
	},
	CombatKnife = {
		Id = "CombatKnife",
		DisplayName = "Combat Knife",
		Category = "Knife",
		Knife = knife(75, 0.9, 45, 0.45, 1.1),
	},
}

for _, archetype in Archetypes do
	table.freeze(archetype)
end

return table.freeze(Archetypes)
