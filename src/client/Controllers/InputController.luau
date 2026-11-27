--!strict
--[[
	Input abstraction (spec §6). Maps Config.Input actions to keyboard/mouse, gamepad and touch
	(ContextActionService touch buttons) and exposes them as Began/Ended signals so gameplay code
	never reads raw keys.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Bindings = require(ReplicatedStorage.Shared.Bindings)
local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

export type InputFamily = "KeyboardMouse" | "Gamepad" | "Touch"

local InputController = {
	Name = "InputController",
	Began = Signal.new() :: Signal.Signal<string>,
	Ended = Signal.new() :: Signal.Signal<string>,
	FamilyChanged = Signal.new() :: Signal.Signal<InputFamily>,
	Family = "KeyboardMouse" :: InputFamily,
}

local down: { [string]: boolean } = {}
local ACTION_PREFIX = "Crossblade_"

local function classify(inputType: Enum.UserInputType): InputFamily?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif string.find(inputType.Name, "Gamepad") then
		return "Gamepad"
	elseif inputType == Enum.UserInputType.Keyboard or string.find(inputType.Name, "Mouse") then
		return "KeyboardMouse"
	end
	return nil
end

function InputController.IsDown(_self: typeof(InputController), action: string): boolean
	return down[action] == true
end

local function inputsFor(action: string, bindings: Bindings.Bindings?): { any }
	local binding = Config.Input[action]
	local override = bindings and bindings[action]
	if override == nil then
		local inputs = {}
		for _, input in binding.Keyboard do
			table.insert(inputs, input)
		end
		for _, input in binding.Gamepad do
			table.insert(inputs, input)
		end
		return inputs
	end
	local keyboard, gamepad = Bindings.Effective(bindings, action)
	return Bindings.ToInputs(keyboard, gamepad)
end

-- (Re)binds every action. Called at start and whenever saved bindings change (remapping).
function InputController.Rebind(self: typeof(InputController), bindings: Bindings.Bindings?)
	for action, binding in Config.Input do
		local name = ACTION_PREFIX .. action
		ContextActionService:UnbindAction(name)
		if down[action] then
			down[action] = false
			self.Ended:Fire(action)
		end
		ContextActionService:BindActionAtPriority(
			name,
			function(_, state: Enum.UserInputState)
				if state == Enum.UserInputState.Begin then
					down[action] = true
					self.Began:Fire(action)
				elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
					if down[action] then
						down[action] = false
						self.Ended:Fire(action)
					end
				end
				-- Pass mouse buttons through so GUI and the default camera still see them when needed.
				return Enum.ContextActionResult.Pass
			end,
			binding.Touch ~= nil,
			Enum.ContextActionPriority.High.Value,
			table.unpack(inputsFor(action, bindings))
		)
		if binding.Touch then
			ContextActionService:SetTitle(name, binding.Touch.Title)
			ContextActionService:SetPosition(name, binding.Touch.Position)
		end
	end
end

function InputController.Start(self: typeof(InputController))
	self:Rebind(nil)

	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.UserInputType == Enum.UserInputType.MouseWheel then
			self.Began:Fire("NextWeapon")
		end
	end)

	local function updateFamily(inputType: Enum.UserInputType)
		local family = classify(inputType)
		if family and family ~= self.Family then
			self.Family = family
			self.FamilyChanged:Fire(family)
		end
	end
	UserInputService.LastInputTypeChanged:Connect(updateFamily)
	updateFamily(UserInputService:GetLastInputType())
end

return InputController
