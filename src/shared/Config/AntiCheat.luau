--!strict
-- Anti-cheat thresholds (spec §25). Signals feed a decaying suspicion score; nothing here bans anyone.
local AntiCheat = {
	Movement = {
		SampleIntervalSeconds = 0.25,
		-- Horizontal speed allowed relative to the configured run speed before a sample is flagged.
		SpeedToleranceMultiplier = 1.45,
		-- Flat allowance (studs/s) for network jitter and physics corrections.
		SpeedToleranceFlat = 6,
		-- Samples must be flagged this many times within the window before suspicion is added.
		FlagsBeforeSuspicion = 3,
		FlagWindowSeconds = 3,
		-- A single sample this far over the limit is corrected (player returned to last valid position).
		CorrectionMultiplier = 3.0,
		-- Grace period after any server-initiated teleport (spawn, correction).
		TeleportGraceSeconds = 1.0,
		-- Vertical rise speed allowed (jumping / ramps).
		MaxRiseSpeed = 60,
	},
	Suspicion = {
		DecayPerMinute = 10,
		Weights = {
			RateLimitExceeded = 2,
			MalformedPayload = 5,
			InvalidShot = 3,
			ImpossibleFireRate = 4,
			UnownedWeapon = 15,
			SpeedViolation = 6,
		},
		-- Above this score the player is flagged for moderator review (logged as a security alert).
		ReviewThreshold = 60,
		-- Above this score the player is removed from the current server. Not a ban.
		KickThreshold = 150,
	},
}

return table.freeze(AntiCheat)
