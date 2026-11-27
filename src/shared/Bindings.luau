--!strict
--[[
	Input remapping (spec §6, §19 "platform-specific controls"). Players may override the keyboard/
	mouse and gamepad input for any action in Config.Input. Overrides are stored by name, validated
	against an allow-list (movement, jump, menu and system keys can never be taken), and rejected if
	they would collide with another action's effective binding. Shared so the client previews exactly
	what the server will accept.
]]

local Config = require(script.Parent.Config)

export type Override = { Keyboard: string?, Gamepad: string? }
export type Bindings = { [string]: Override }

local Bindings = {}

local KEYBOARD_ALLOWED: { [string]: boolean } = {}
for _, name in
	{
		"Q",
		"E",
		"R",
		"T",
		"Y",
		"U",
		"I",
		"O",
		"P",
		"F",
		"G",
		"H",
		"J",
		"K",
		"L",
		"Z",
		"X",
		"C",
		"V",
		"B",
		"N",
		"M",
		"One",
		"Two",
		"Three",
		"Four",
		"Five",
		"Six",
		"Seven",
		"Eight",
		"Nine",
		"Zero",
		"LeftShift",
		"LeftControl",
		"LeftAlt",
		"Tab",
		"CapsLock",
		"MouseButton1",
		"MouseButton2",
		"MouseButton3",
	}
do
	KEYBOARD_ALLOWED[name] = true
end

local GAMEPAD_ALLOWED: { [string]: boolean } = {}
for _, name in
	{
		"ButtonX",
		"ButtonY",
		"ButtonB",
		"ButtonL1",
		"ButtonR1",
		"ButtonL2",
		"ButtonR2",
		"ButtonL3",
		"ButtonR3",
		"DPadUp",
		"DPadDown",
		"DPadLeft",
		"DPadRight",
		"ButtonSelect",
	}
do
	GAMEPAD_ALLOWED[name] = true
end

Bindings.KeyboardAllowed = table.freeze(KEYBOARD_ALLOWED)
Bindings.GamepadAllowed = table.freeze(GAMEPAD_ALLOWED)

local function defaultName(inputs: { any }): string?
	local first = inputs[1]
	return first and first.Name
end

function Bindings.Actions(): { string }
	local list = {}
	for action in Config.Input do
		table.insert(list, action)
	end
	table.sort(list)
	return list
end

-- Effective input names for an action after overrides: (keyboard name?, gamepad name?).
function Bindings.Effective(bindings: Bindings?, action: string): (string?, string?)
	local binding = Config.Input[action]
	local override = bindings and bindings[action]
	local keyboard = if override and override.Keyboard
		then override.Keyboard
		else defaultName(binding.Keyboard)
	local gamepad = if override and override.Gamepad then override.Gamepad else defaultName(binding.Gamepad)
	return keyboard, gamepad
end

-- Which action (other than `except`) currently uses this input name, if any.
function Bindings.UsedBy(
	bindings: Bindings?,
	family: "Keyboard" | "Gamepad",
	name: string,
	except: string?
): string?
	for _, action in Bindings.Actions() do
		if action ~= except then
			local keyboard, gamepad = Bindings.Effective(bindings, action)
			if (family == "Keyboard" and keyboard == name) or (family == "Gamepad" and gamepad == name) then
				return action
			end
		end
	end
	return nil
end

-- Accepts a dictionary { Action = { Keyboard, Gamepad } } or the wire array form; returns valid overrides.
function Bindings.Sanitize(input: any): Bindings
	local result: Bindings = {}
	if type(input) ~= "table" then
		return result
	end
	local entries: { [string]: any } = {}
	for key, value in input do
		if type(key) == "number" and type(value) == "table" and type(value.Action) == "string" then
			entries[value.Action] = value
		elseif type(key) == "string" and type(value) == "table" then
			entries[key] = value
		end
	end
	local actions = {}
	for action in entries do
		if Config.Input[action] then
			table.insert(actions, action)
		end
	end
	table.sort(actions)
	-- Candidate overrides with allowed inputs only.
	for _, action in actions do
		local entry = entries[action]
		local override: Override = {}
		if type(entry.Keyboard) == "string" and KEYBOARD_ALLOWED[entry.Keyboard] then
			override.Keyboard = entry.Keyboard
		end
		if type(entry.Gamepad) == "string" and GAMEPAD_ALLOWED[entry.Gamepad] then
			override.Gamepad = entry.Gamepad
		end
		if override.Keyboard or override.Gamepad then
			result[action] = override
		end
	end
	-- Order-independent conflict resolution: drop any override whose input is also used by another
	-- action's effective binding, and repeat until stable (dropping can expose a default again).
	-- Swaps (A takes B's key while B takes another key) are therefore accepted.
	local changed = true
	while changed do
		changed = false
		for _, action in actions do
			local override = result[action]
			if override then
				if override.Keyboard and Bindings.UsedBy(result, "Keyboard", override.Keyboard, action) then
					override.Keyboard = nil
					changed = true
				end
				if override.Gamepad and Bindings.UsedBy(result, "Gamepad", override.Gamepad, action) then
					override.Gamepad = nil
					changed = true
				end
				if override.Keyboard == nil and override.Gamepad == nil then
					result[action] = nil
				end
			end
		end
	end
	return result
end

function Bindings.ToWire(bindings: Bindings): { { [string]: any } }
	local list = {}
	for _, action in Bindings.Actions() do
		local override = bindings[action]
		if override then
			table.insert(list, { Action = action, Keyboard = override.Keyboard, Gamepad = override.Gamepad })
		end
	end
	return list
end

-- Resolves names to Enum inputs for ContextActionService (KeyCode or UserInputType for mouse buttons).
function Bindings.ToInputs(keyboard: string?, gamepad: string?): { any }
	local inputs = {}
	if keyboard then
		local mouse = string.match(keyboard, "^MouseButton%d$")
		local ok, value = pcall(function()
			return if mouse then (Enum.UserInputType :: any)[keyboard] else (Enum.KeyCode :: any)[keyboard]
		end)
		if ok and value then
			table.insert(inputs, value)
		end
	end
	if gamepad then
		local ok, value = pcall(function()
			return (Enum.KeyCode :: any)[gamepad]
		end)
		if ok and value then
			table.insert(inputs, value)
		end
	end
	return inputs
end

return Bindings
