--!strict
--[[
	Security and administrative audit trail (spec §25, §26).
	Phase 2 scope: structured, bounded in-memory log per server plus logger output, so every security
	event is recorded with who/what/when/evidence. Phase 8 adds durable cross-server storage and the
	admin dashboard reader (see docs/SECURITY.md, backlog SEC-08).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Util.Logger)

export type Record = {
	Time: number,
	Category: "Security" | "Data" | "Admin" | "Economy",
	Event: string,
	UserId: number?,
	Context: { [string]: any }?,
}

local MAX_RECORDS = 500
local log = Logger.new("Audit")

local AuditService = {
	Name = "AuditService",
	_records = {} :: { Record },
}

function AuditService.Record(
	self: typeof(AuditService),
	category: "Security" | "Data" | "Admin" | "Economy",
	event: string,
	userId: number?,
	context: { [string]: any }?
)
	local record: Record =
		{ Time = os.time(), Category = category, Event = event, UserId = userId, Context = context }
	table.insert(self._records, record)
	if #self._records > MAX_RECORDS then
		table.remove(self._records, 1)
	end
	local merged = if context then table.clone(context) else {}
	merged.userId = userId
	log:Warn(`{category}:{event}`, merged)
end

function AuditService.Recent(self: typeof(AuditService), count: number): { Record }
	local result = {}
	for index = math.max(1, #self._records - count + 1), #self._records do
		table.insert(result, self._records[index])
	end
	return result
end

return AuditService
