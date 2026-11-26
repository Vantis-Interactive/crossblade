--!strict
-- Shared client UI state: whether a menu currently owns the cursor and input.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local UIState = {
	MenuOpen = false,
	Changed = Signal.new() :: Signal.Signal<boolean>,
}

function UIState.SetMenuOpen(open: boolean)
	if UIState.MenuOpen ~= open then
		UIState.MenuOpen = open
		UIState.Changed:Fire(open)
	end
end

return UIState
