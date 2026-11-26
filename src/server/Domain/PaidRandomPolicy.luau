--!strict
--[[
	Paid randomized item eligibility (spec §14). Fails closed: purchased currency may be spent on
	crates only when PolicyService was queried successfully AND reported no restriction. Any error,
	missing field or unexpected value means "not allowed".
]]

export type Status = "Allowed" | "Restricted" | "Unknown"

local PaidRandomPolicy = {}

function PaidRandomPolicy.Decide(ok: boolean, info: any): Status
	if not ok or type(info) ~= "table" then
		return "Unknown"
	end
	local restricted = info.ArePaidRandomItemsRestricted
	if restricted == false then
		return "Allowed"
	elseif restricted == true then
		return "Restricted"
	end
	return "Unknown"
end

function PaidRandomPolicy.AllowsPurchasedCurrency(status: Status?): boolean
	return status == "Allowed"
end

return PaidRandomPolicy
