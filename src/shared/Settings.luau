--!strict
--[[
	Player settings defaults and sanitization. Shared so the client can apply settings immediately and
	the server can persist them; the server always sanitizes before saving (never trusts the client).
]]

local Bindings = require(script.Parent.Bindings)
local Config = require(script.Parent.Config)

export type Settings = {
	FieldOfView: number,
	Sensitivity: number,
	AimSensitivity: number,
	Perspective: "FirstPerson" | "ThirdPerson",
	CrosshairStyle: "Cross" | "Dot" | "Circle",
	CrosshairColor: "White" | "Green" | "Yellow" | "Cyan" | "Magenta",
	CrosshairSize: number,
	ReducedMotion: boolean,
	DamageNumbers: boolean,
	Bindings: Bindings.Bindings,
}

local Settings = {}

Settings.CrosshairColors = table.freeze({
	White = Color3.fromRGB(255, 255, 255),
	Green = Color3.fromRGB(120, 255, 120),
	Yellow = Color3.fromRGB(255, 230, 90),
	Cyan = Color3.fromRGB(90, 230, 255),
	Magenta = Color3.fromRGB(255, 110, 230),
})

function Settings.Defaults(): Settings
	local camera = Config.Camera
	return {
		FieldOfView = camera.FieldOfView.Default,
		Sensitivity = camera.Sensitivity.Default,
		AimSensitivity = camera.AimSensitivityMultiplier.Default,
		Perspective = camera.DefaultPerspective,
		CrosshairStyle = "Cross",
		CrosshairColor = "White",
		CrosshairSize = 12,
		ReducedMotion = false,
		DamageNumbers = Config.FeatureFlags.DamageNumbers,
		Bindings = {},
	}
end

local function oneOf<T>(value: any, allowed: { [any]: any }, fallback: T): T
	if type(value) == "string" and allowed[value] ~= nil then
		return value :: any
	end
	return fallback
end

local function bounded(value: any, min: number, max: number, fallback: number): number
	if type(value) ~= "number" or value ~= value then
		return fallback
	end
	return math.clamp(value, min, max)
end

-- Returns a fully valid Settings table from arbitrary input, falling back to defaults per field.
function Settings.Sanitize(input: any): Settings
	local defaults = Settings.Defaults()
	if type(input) ~= "table" then
		return defaults
	end
	local camera = Config.Camera
	return {
		FieldOfView = bounded(
			input.FieldOfView,
			camera.FieldOfView.Min,
			camera.FieldOfView.Max,
			defaults.FieldOfView
		),
		Sensitivity = bounded(
			input.Sensitivity,
			camera.Sensitivity.Min,
			camera.Sensitivity.Max,
			defaults.Sensitivity
		),
		AimSensitivity = bounded(
			input.AimSensitivity,
			camera.AimSensitivityMultiplier.Min,
			camera.AimSensitivityMultiplier.Max,
			defaults.AimSensitivity
		),
		Perspective = oneOf(
			input.Perspective,
			{ FirstPerson = true, ThirdPerson = true },
			defaults.Perspective
		),
		CrosshairStyle = oneOf(
			input.CrosshairStyle,
			{ Cross = true, Dot = true, Circle = true },
			defaults.CrosshairStyle
		),
		CrosshairColor = oneOf(input.CrosshairColor, Settings.CrosshairColors, defaults.CrosshairColor),
		CrosshairSize = math.floor(bounded(input.CrosshairSize, 4, 40, defaults.CrosshairSize)),
		ReducedMotion = if type(input.ReducedMotion) == "boolean"
			then input.ReducedMotion
			else defaults.ReducedMotion,
		DamageNumbers = if type(input.DamageNumbers) == "boolean"
			then input.DamageNumbers
			else defaults.DamageNumbers,
		Bindings = Bindings.Sanitize(input.Bindings),
	}
end

return Settings
