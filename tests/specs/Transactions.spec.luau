--!nocheck
local Transactions = Runtime:Get("ServerScriptService/Server/Data/Transactions")
local Schema = Runtime:Get("ServerScriptService/Server/Data/Schema")

describe("Transactions", function()
	it("repeated transaction requests cannot duplicate rewards", function()
		local data = Schema.Default(1, 0)
		local function grant(draft)
			draft.Currency.Earned += 100
		end
		expect(Transactions.Apply(data, "tx-1", 1, 200, grant)).toBe("Applied")
		expect(Transactions.Apply(data, "tx-1", 2, 200, grant)).toBe("AlreadyApplied")
		expect(Transactions.Apply(data, "tx-1", 3, 200, grant)).toBe("AlreadyApplied")
		expect(data.Currency.Earned).toBe(100)
	end)

	it("is all-or-nothing: a failing mutation leaves the profile untouched", function()
		local data = Schema.Default(1, 0)
		data.Currency.Earned = 1000
		local outcome = Transactions.Apply(data, "crate-1", 1, 200, function(draft)
			draft.Currency.Earned -= 250 -- debit applied...
			error("reward pool empty") -- ...then the grant fails
		end)
		expect(outcome).toBe("Failed")
		expect(data.Currency.Earned).toBe(1000)
		expect(Transactions.IsApplied(data, "crate-1")).toBe(false)
	end)

	it("keeps the processed transaction list bounded, evicting the oldest", function()
		local data = Schema.Default(1, 0)
		for i = 1, 10 do
			Transactions.Apply(data, "tx-" .. i, i, 5, function() end)
		end
		local count = 0
		for _ in data.ProcessedTransactions do
			count += 1
		end
		expect(count).toBe(5)
		expect(Transactions.IsApplied(data, "tx-10")).toBe(true)
		expect(Transactions.IsApplied(data, "tx-1")).toBe(false)
	end)
end)
