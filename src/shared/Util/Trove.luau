--!strict
-- Tracks connections, instances and cleanup callbacks so lifetimes (a character, a match) end cleanly.

local Trove = {}
Trove.__index = Trove

export type Trove = typeof(setmetatable({} :: { _items: { any } }, Trove))

function Trove.new(): Trove
	return setmetatable({ _items = {} }, Trove)
end

function Trove.Add<T>(self: Trove, item: T): T
	table.insert(self._items, item)
	return item
end

function Trove.Connect(self: Trove, signal: RBXScriptSignal, handler: (...any) -> ()): RBXScriptConnection
	local connection = signal:Connect(handler)
	table.insert(self._items, connection)
	return connection
end

local function cleanupItem(item: any)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		pcall(task.cancel, item)
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		end
	end
end

function Trove.Clean(self: Trove)
	local items = self._items
	self._items = {}
	for index = #items, 1, -1 do
		local ok, err = pcall(cleanupItem, items[index])
		if not ok then
			warn(`[Trove] cleanup failed: {err}`)
		end
	end
end

Trove.Destroy = Trove.Clean

return Trove
