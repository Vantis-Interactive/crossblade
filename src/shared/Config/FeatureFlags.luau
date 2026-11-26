--!strict
--[[
	Static feature flag defaults. Phase 12 adds a remote override source (versioned content config);
	until then these are the effective values. Disabling a flag must leave the game playable.
]]
local FeatureFlags = {
	ThrownKnives = true,
	DamageNumbers = true,
	MovementAntiCheatCorrection = true,
	KickOnSuspicion = false, -- kept off until thresholds are tuned against real play data
}

return table.freeze(FeatureFlags)
