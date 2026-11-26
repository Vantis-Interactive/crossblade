--!strict
--[[
	Input bindings (spec §6, §20). One action list, three input families. Touch buttons are created
	for actions with a Touch entry. Remapping UI is a Phase 5 deliverable; these are the defaults.
]]

export type Binding = {
	Keyboard: { Enum.KeyCode | Enum.UserInputType },
	Gamepad: { Enum.KeyCode },
	Touch: { Title: string, Position: UDim2 }?,
}

local Input: { [string]: Binding } = {
	Fire = {
		Keyboard = { Enum.UserInputType.MouseButton1 },
		Gamepad = { Enum.KeyCode.ButtonR2 },
		Touch = { Title = "FIRE", Position = UDim2.new(1, -170, 1, -230) },
	},
	Aim = {
		Keyboard = { Enum.UserInputType.MouseButton2 },
		Gamepad = { Enum.KeyCode.ButtonL2 },
		Touch = { Title = "AIM", Position = UDim2.new(1, -250, 1, -150) },
	},
	Reload = {
		Keyboard = { Enum.KeyCode.R },
		Gamepad = { Enum.KeyCode.ButtonX },
		Touch = { Title = "RLD", Position = UDim2.new(1, -95, 1, -300) },
	},
	NextWeapon = {
		Keyboard = { Enum.KeyCode.Q },
		Gamepad = { Enum.KeyCode.ButtonY },
		Touch = { Title = "SWAP", Position = UDim2.new(1, -170, 1, -310) },
	},
	SlotPrimary = { Keyboard = { Enum.KeyCode.One }, Gamepad = {} },
	SlotSecondary = { Keyboard = { Enum.KeyCode.Two }, Gamepad = {} },
	SlotKnife = { Keyboard = { Enum.KeyCode.Three }, Gamepad = { Enum.KeyCode.DPadRight } },
	ThrowKnife = {
		Keyboard = { Enum.KeyCode.G },
		Gamepad = { Enum.KeyCode.ButtonB },
		Touch = { Title = "THROW", Position = UDim2.new(1, -250, 1, -240) },
	},
	Inspect = { Keyboard = { Enum.KeyCode.F }, Gamepad = { Enum.KeyCode.DPadDown } },
	Sprint = { Keyboard = { Enum.KeyCode.LeftShift }, Gamepad = { Enum.KeyCode.ButtonL3 } },
	TogglePerspective = {
		Keyboard = { Enum.KeyCode.V },
		Gamepad = { Enum.KeyCode.ButtonR3 },
		Touch = { Title = "CAM", Position = UDim2.new(1, -95, 1, -380) },
	},
	Scoreboard = { Keyboard = { Enum.KeyCode.Tab }, Gamepad = { Enum.KeyCode.DPadLeft } },
	Settings = { Keyboard = { Enum.KeyCode.P }, Gamepad = { Enum.KeyCode.ButtonSelect } },
	Collection = { Keyboard = { Enum.KeyCode.I }, Gamepad = { Enum.KeyCode.DPadUp } },
}

return table.freeze(Input)
