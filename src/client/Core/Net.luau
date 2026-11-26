--!strict
-- Client networking wrapper over the remotes created by the server Net layer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Contracts = require(ReplicatedStorage.Shared.Net.Contracts)

local Net = {}

local folder = ReplicatedStorage:WaitForChild(Contracts.FolderName)

local function remote(name: string): any
	return folder:WaitForChild(name)
end

function Net.Fire(name: string, payload: any)
	assert(Contracts.ClientToServer[name], `{name} is not a client->server remote`)
	remote(name):FireServer(payload)
end

function Net.Invoke(name: string, payload: any): any
	local contract = Contracts.ClientToServer[name]
	assert(contract and contract.Kind == "Function", `{name} is not a client function`)
	local ok, result = pcall(function()
		return remote(name):InvokeServer(payload)
	end)
	return if ok then result else nil
end

function Net.On(name: string, handler: (payload: any) -> ()): RBXScriptConnection
	assert(Contracts.ServerToClient[name], `{name} is not a server->client remote`)
	return remote(name).OnClientEvent:Connect(handler)
end

-- Synchronized server clock; used for every timestamp sent to the server.
function Net.Now(): number
	return Workspace:GetServerTimeNow()
end

return Net
