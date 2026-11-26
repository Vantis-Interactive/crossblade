--!strict
-- Map pickup configuration (spec §7, §8). Health never exceeds Player.MaxHealth.
local Pickups = {
	Health = {
		Small = { Amount = 25, RespawnSeconds = 10 },
		Medium = { Amount = 50, RespawnSeconds = 20 },
		Large = { Amount = 100, RespawnSeconds = 30 },
	},
	Ammo = {
		-- Each ammo pickup adds this many magazines' worth of rounds to every firearm's reserve,
		-- capped at that weapon's maximum reserve.
		MagazinesPerPickup = 1,
		RespawnSeconds = 15,
	},
	KnifeStation = {
		-- Per-player cooldown between knife replacements at a station.
		CooldownSeconds = 2,
	},
	-- Horizontal and vertical pickup radii (studs) from the HumanoidRootPart.
	PickupRadius = 4,
	PickupHeight = 5,
	-- How often the server evaluates pickup proximity.
	PollIntervalSeconds = 0.1,
}

return table.freeze(Pickups)
