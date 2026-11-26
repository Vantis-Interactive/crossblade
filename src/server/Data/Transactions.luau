--!strict
--[[
	Idempotent, all-or-nothing profile mutations (spec §13, §24).

	Apply(data, transactionId, ...) runs `mutate` against a deep copy. Only if it returns without error
	is the copy committed and the transaction id recorded. A transaction id that was already applied is
	a no-op, so retried requests and replayed receipts cannot duplicate rewards.

	Note: this makes the in-memory profile mutation atomic and idempotent. Durable idempotency across
	servers comes from the session lock (one server owns a profile at a time) plus the processed ids
	being saved in the same record as the balances they changed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TableUtil = require(ReplicatedStorage.Shared.Util.TableUtil)

export type Outcome = "Applied" | "AlreadyApplied" | "Failed"

local Transactions = {}

function Transactions.IsApplied(data: { [string]: any }, transactionId: string): boolean
	return data.ProcessedTransactions[transactionId] ~= nil
end

local function prune(processed: { [string]: number }, limit: number)
	local count = TableUtil.Count(processed)
	if count <= limit then
		return
	end
	local entries = {}
	for id, time in processed do
		table.insert(entries, { Id = id, Time = time })
	end
	table.sort(entries, function(a, b)
		return a.Time < b.Time
	end)
	for index = 1, count - limit do
		processed[entries[index].Id] = nil
	end
end

function Transactions.Apply(
	data: { [string]: any },
	transactionId: string,
	now: number,
	limit: number,
	mutate: (draft: { [string]: any }) -> ()
): (Outcome, string?)
	if Transactions.IsApplied(data, transactionId) then
		return "AlreadyApplied", nil
	end
	local draft = TableUtil.DeepCopy(data)
	local ok, err = pcall(mutate, draft)
	if not ok then
		return "Failed", tostring(err)
	end
	draft.ProcessedTransactions[transactionId] = now
	prune(draft.ProcessedTransactions, limit)
	-- Commit: replace contents in place so existing references to `data` see the new state.
	table.clear(data)
	for key, value in draft do
		data[key] = value
	end
	return "Applied", nil
end

return Transactions
