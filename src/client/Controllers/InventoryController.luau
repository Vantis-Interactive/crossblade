--!strict
--[[
	Client mirror of the player's economy and inventory (spec §12–§14): wallet, level/XP, owned
	weapons, loadout and active crates. All mutations are requests to the server, which is
	authoritative; this controller never changes balances or ownership locally.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Net = require(script.Parent.Parent.Core.Net)

local InventoryController = {
	Name = "InventoryController",
	State = nil :: { [string]: any }?,
	Changed = Signal.new() :: Signal.Signal<{ [string]: any }>,
	Reward = Signal.new() :: Signal.Signal<{ [string]: any }>,
}

function InventoryController.Owns(self: typeof(InventoryController), weaponId: string): boolean
	local state = self.State
	return state ~= nil and table.find(state.Owned, weaponId) ~= nil
end

function InventoryController.Apply(self: typeof(InventoryController), state: { [string]: any })
	self.State = state
	self.Changed:Fire(state)
end

-- Requests a loadout change for one slot (server validates ownership; applies next spawn).
function InventoryController.SetLoadout(self: typeof(InventoryController), slot: string, weaponId: string)
	local state = self.State
	if state == nil then
		return
	end
	local loadout = table.clone(state.Loadout)
	loadout[slot] = weaponId
	Net.Fire(
		"SetLoadout",
		{ Primary = loadout.Primary, Secondary = loadout.Secondary, Knife = loadout.Knife }
	)
end

--[[
	Opens a crate. One RequestId is generated per purchase and reused for the retry, so a lost
	response can never cause a second charge: the server answers the retry with the original result.
]]
function InventoryController.OpenCrate(
	_self: typeof(InventoryController),
	crateId: string,
	useToken: boolean?
): { [string]: any }
	local requestId = HttpService:GenerateGUID(false)
	for attempt = 1, 2 do
		local response =
			Net.Invoke("OpenCrate", { CrateId = crateId, RequestId = requestId, UseToken = useToken == true })
		if response then
			return response
		end
		if attempt == 1 then
			task.wait(1)
		end
	end
	return { Ok = false, Reason = "NoResponse" }
end

function InventoryController.Start(self: typeof(InventoryController))
	Net.On("EconomyState", function(state)
		self:Apply(state)
	end)
	Net.On("Reward", function(payload)
		self.Reward:Fire(payload)
	end)
	for _ = 1, 30 do
		if self.State then
			return
		end
		local state = Net.Invoke("GetEconomy", {})
		if state then
			self:Apply(state)
			return
		end
		task.wait(1)
	end
end

return InventoryController
