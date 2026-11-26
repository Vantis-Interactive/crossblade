--!strict
--[[
	Shared client UI state. Several menus can be open at once (settings over the collection window);
	input and the cursor are released while ANY menu is open.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local open: { [string]: boolean } = {}

local UIState = {
	MenuOpen = false,
	Changed = Signal.new() :: Signal.Signal<boolean>,
}

function UIState.SetMenuOpen(name: string, isOpen: boolean)
	open[name] = if isOpen then true else nil
	local any = next(open) ~= nil
	if any ~= UIState.MenuOpen then
		UIState.MenuOpen = any
		UIState.Changed:Fire(any)
	end
end

function UIState.IsOpen(name: string): boolean
	return open[name] == true
end

return UIState
