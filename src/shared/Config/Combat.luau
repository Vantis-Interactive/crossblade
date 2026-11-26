--!strict
-- Server-side combat validation and feedback tuning (spec §9, §10).
local Combat = {
	LagCompensation = {
		-- Position history sampling for rewinding targets.
		SampleRate = 20, -- samples per second
		HistorySeconds = 1.0,
		-- Hard bound on how far back the server will rewind, regardless of reported latency.
		MaxRewindSeconds = 0.35,
		-- Client timestamps may lead server time by at most this much (clock sync jitter).
		MaxFutureSeconds = 0.05,
	},

	Validation = {
		-- Max distance between the reported shot origin and the shooter's (rewound) head.
		MaxOriginDeviation = 4.5,
		-- Extra radius added to standardized hitboxes when verifying a reported hit.
		HitboxTolerance = 0.9,
		-- Headshots are only confirmed if the ray passes within this inflation of the head sphere.
		-- Deliberately tighter than HitboxTolerance so latency tolerance cannot manufacture headshots.
		HeadshotTolerance = 0.45,
		-- Max angle (degrees) between a reported shot direction and the server-derived hit direction,
		-- in addition to the weapon's spread.
		DirectionToleranceDegrees = 4.0,
		-- Line-of-sight checks stop this many studs short of the hit point to avoid false positives
		-- caused by the target's own geometry.
		LineOfSightEndPadding = 0.5,
	},

	Assists = {
		MinimumDamage = 40,
		WindowSeconds = 10,
	},

	Killstreaks = {
		AnnounceAt = { 3, 5, 7, 10, 15, 20 },
	},

	Melee = {
		-- Extra reach and cone allowance for latency when validating knife attacks.
		RangeTolerance = 1.5,
		ConeToleranceDegrees = 15,
	},

	-- Requests per player are bounded independently of weapon fire rate as a second line of defence.
	FireTokenBurst = 3,
}

return table.freeze(Combat)
