--!strict
-- Minimal synchronous signal used for in-process events between services/controllers.
-- Handlers run in order of connection; a failing handler is logged and does not stop the others.

export type Connection = { Connected: boolean, Disconnect: (self: Connection) -> () }

local Signal = {}
Signal.__index = Signal

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({ _handlers = {} :: { any } }, Signal)
	return (self :: any) :: Signal<T...>
end

function Signal.Connect(self: any, handler: (...any) -> ()): Connection
	local entry = { Handler = handler }
	local connection = { Connected = true } :: any
	function connection.Disconnect(conn: any)
		if not conn.Connected then
			return
		end
		conn.Connected = false
		local index = table.find(self._handlers, entry)
		if index then
			table.remove(self._handlers, index)
		end
	end
	table.insert(self._handlers, entry)
	return connection
end

function Signal.Once(self: any, handler: (...any) -> ()): Connection
	local connection: Connection
	connection = Signal.Connect(self, function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal.Fire(self: any, ...: any)
	-- Snapshot so handlers may disconnect during dispatch.
	local snapshot = table.clone(self._handlers)
	for _, entry in snapshot do
		local ok, err = pcall(entry.Handler, ...)
		if not ok then
			warn(`[Signal] handler error: {err}`)
		end
	end
end

function Signal.DisconnectAll(self: any)
	table.clear(self._handlers)
end

return Signal
