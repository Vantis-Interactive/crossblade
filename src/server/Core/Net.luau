--!strict
--[[
	Server networking layer. Creates every remote declared in Shared/Net/Contracts and is the ONLY
	place OnServerEvent / OnServerInvoke are connected.

	For each incoming request, before the service handler runs:
	  1. exactly one payload argument is required,
	  2. the per-player, per-remote token bucket must allow it,
	  3. the payload must satisfy the declared schema.
	Failures are dropped and reported through Net.Violation (consumed by AntiCheatService).
	Handler errors are caught and logged; they never propagate to the client.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Contracts = require(ReplicatedStorage.Shared.Net.Contracts)
local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local RateLimiter = require(ReplicatedStorage.Shared.Util.RateLimiter)
local Schema = require(ReplicatedStorage.Shared.Net.Schema)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local log = Logger.new("Net")

local Net = {
	Name = "Net",
	-- (player, kind: "RateLimitExceeded" | "MalformedPayload", remoteName, detail)
	Violation = Signal.new() :: Signal.Signal<Player, string, string, string?>,
}

local remotes: { [string]: Instance } = {}
local limiters: { [string]: RateLimiter.RateLimiter } = {}

local function create(name: string, kind: Contracts.RemoteKind, folder: Folder)
	assert(remotes[name] == nil, `duplicate remote {name}`)
	local className = if kind == "Function"
		then "RemoteFunction"
		elseif kind == "UnreliableEvent" then "UnreliableRemoteEvent"
		else "RemoteEvent"
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
	remotes[name] = remote
end

function Net.Init(_self)
	local folder = Instance.new("Folder")
	folder.Name = Contracts.FolderName
	for name, contract in Contracts.ClientToServer do
		create(name, contract.Kind, folder)
		limiters[name] = RateLimiter.new(contract.RateCapacity, contract.RatePerSecond)
	end
	for name, contract in Contracts.ServerToClient do
		create(name, contract.Kind, folder)
	end
	folder.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(player)
		for _, limiter in limiters do
			limiter:Reset(player)
		end
	end)
end

function Net.Now(): number
	return Workspace:GetServerTimeNow()
end

-- Returns the validated payload or nil (and reports why).
local function admit(name: string, player: Player, ...: any): any
	local contract = Contracts.ClientToServer[name]
	if select("#", ...) ~= 1 then
		Net.Violation:Fire(player, "MalformedPayload", name, "argument count")
		return nil
	end
	if not limiters[name]:Consume(player, Net.Now()) then
		Net.Violation:Fire(player, "RateLimitExceeded", name, nil)
		return nil
	end
	local payload = ...
	local ok, reason = Schema.Check(contract.Payload, payload)
	if not ok then
		Net.Violation:Fire(player, "MalformedPayload", name, reason)
		return nil
	end
	return payload
end

function Net.OnEvent(name: string, handler: (player: Player, payload: any) -> ())
	local contract = Contracts.ClientToServer[name]
	assert(contract and contract.Kind ~= "Function", `{name} is not a client event`)
	local remote = remotes[name] :: any
	remote.OnServerEvent:Connect(function(player: Player, ...)
		local payload = admit(name, player, ...)
		if payload == nil then
			return
		end
		local ok, err = pcall(handler, player, payload)
		if not ok then
			log:Error(`handler {name} failed`, { player = player.UserId, error = err })
		end
	end)
end

function Net.OnInvoke(name: string, handler: (player: Player, payload: any) -> any)
	local contract = Contracts.ClientToServer[name]
	assert(contract and contract.Kind == "Function", `{name} is not a client function`)
	local remote = remotes[name] :: RemoteFunction
	remote.OnServerInvoke = function(player: Player, ...)
		local payload = admit(name, player, ...)
		if payload == nil then
			return nil
		end
		local ok, result = pcall(handler, player, payload)
		if not ok then
			log:Error(`invoke {name} failed`, { player = player.UserId, error = result })
			return nil
		end
		return result
	end
end

local function serverRemote(name: string): any
	assert(Contracts.ServerToClient[name], `{name} is not a server->client remote`)
	return remotes[name]
end

function Net.Fire(name: string, player: Player, payload: any)
	serverRemote(name):FireClient(player, payload)
end

function Net.FireAll(name: string, payload: any)
	serverRemote(name):FireAllClients(payload)
end

function Net.FireAllExcept(name: string, except: Player, payload: any)
	local remote = serverRemote(name)
	for _, player in Players:GetPlayers() do
		if player ~= except then
			remote:FireClient(player, payload)
		end
	end
end

return Net
