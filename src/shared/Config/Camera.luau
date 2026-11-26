--!strict
-- Camera configuration (spec §6). FOV is bounded to competitive limits for every player.
local Camera = {
	DefaultPerspective = "ThirdPerson" :: "FirstPerson" | "ThirdPerson",

	FieldOfView = { Min = 70, Max = 100, Default = 80 },
	Sensitivity = { Min = 0.1, Max = 3.0, Default = 1.0 },
	-- Aiming sensitivity is a multiplier applied while aiming down sights.
	AimSensitivityMultiplier = { Min = 0.1, Max = 1.5, Default = 0.75 },

	ThirdPerson = {
		Distance = 9,
		ShoulderOffset = Vector3.new(2.25, 1.1, 0),
		-- Camera collision: shoulder offset is shortened when geometry is in the way.
		CollisionPadding = 0.4,
	},
	FirstPerson = {
		Distance = 0.5,
	},

	Recoil = {
		RecoveryPerSecond = 6.0, -- degrees of recoil recovered per second
	},
}

return table.freeze(Camera)
