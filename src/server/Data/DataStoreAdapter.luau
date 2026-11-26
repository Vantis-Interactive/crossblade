--!strict
--[[
	Production adapter from ProfileStore to Roblox DataStoreService. Environment-suffixed store names
	keep Development, Staging and Production data fully separate (spec §24).
]]

local DataStoreService = game:GetService("DataStoreService")

local DataStoreAdapter = {}
DataStoreAdapter.__index = DataStoreAdapter

function DataStoreAdapter.new(storeName: string)
	local store = DataStoreService:GetDataStore(storeName)
	return setmetatable({ _store = store }, DataStoreAdapter)
end

function DataStoreAdapter.UpdateAsync(
	self: any,
	key: string,
	transform: (old: any) -> any,
	userIds: { number }
): any
	return self._store:UpdateAsync(key, function(old: any)
		local newValue = transform(old)
		if newValue == nil then
			return nil
		end
		-- Associating UserIds supports Roblox right-to-erasure tooling.
		return newValue, userIds
	end)
end

-- Performs one real read. Used in Studio only, where GetDataStore can succeed while every request
-- fails because "Enable Studio Access to API Services" is off.
function DataStoreAdapter.Probe(self: any)
	self._store:GetAsync("__crossblade_probe")
end

function DataStoreAdapter.Budget(): number
	return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
end

return DataStoreAdapter
