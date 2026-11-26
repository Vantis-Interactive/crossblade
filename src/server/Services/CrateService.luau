--!strict
--[[
	Crates (spec §14).
	  - At boot, every configured crate's pool, odds, price, compensation and expected economic impact
	    are validated (Shared/Economy/CrateOdds.Validate). Invalid crates are never offered.
	  - The reward is chosen on the server with Random; the client only animates the returned result.
	  - Opening is one atomic, idempotent transaction keyed by the client's RequestId: a retried or
	    replayed request returns the original result and never charges or rewards twice.
	  - Purchased coins are spendable only for policy-eligible players (fail closed); earned coins
	    are always the free, gameplay-based path.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local CrateOdds = require(ReplicatedStorage.Shared.Economy.CrateOdds)
local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local CrateOpening = require(script.Parent.Parent.Domain.CrateOpening)

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local log = Logger.new("Crate")

local CrateService = {
	Name = "CrateService",
	Dependencies = { "Net", "PlayerDataService", "EconomyService", "PolicyComplianceService", "AuditService" },
	CrateOpened = Signal.new() :: Signal.Signal<Player, any>,
}

local distributions: { [string]: CrateOdds.Distribution } = {}
local rng = Random.new()
local net: any
local playerData: any
local economy: any
local policy: any
local audit: any

local function open(player: Player, payload: any): { [string]: any }
	local crate = Config.Crates.Crates[payload.CrateId]
	local distribution = distributions[payload.CrateId]
	if crate == nil or distribution == nil then
		return { Ok = false, Reason = "UnknownCrate" }
	end
	local requestId: string = payload.RequestId
	if #requestId < 8 or string.match(requestId, "^[%w%-]+$") == nil then
		return { Ok = false, Reason = "BadRequest" }
	end
	local profile = playerData:GetProfile(player)
	if profile == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end

	local allowPurchased = policy:PurchasedCurrencyAllowedForCrates(player)
	local roll = rng:NextNumber()
	local result: CrateOpening.Result? = nil
	local outcome, err = playerData:ApplyTransaction(player, `crate:{requestId}`, function(draft)
		result = CrateOpening.Open(draft, {
			CrateId = crate.Id,
			Price = crate.Price,
			Distribution = distribution,
			Roll = roll,
			RequestId = requestId,
			Now = os.time(),
			AllowPurchased = allowPurchased,
			Compensation = Config.Economy.DuplicateCompensation,
			HistoryLimit = Config.Economy.CrateHistoryLimit,
			UseToken = payload.UseToken == true,
		})
	end)

	if outcome == "AlreadyApplied" then
		local previous = CrateOpening.FindResult(profile.Data, requestId)
		if previous then
			return { Ok = true, Replayed = true, Result = previous }
		end
		return { Ok = false, Reason = "AlreadyProcessed" }
	elseif outcome ~= "Applied" or result == nil then
		return { Ok = false, Reason = err or "Failed" }
	end
	local applied = result :: CrateOpening.Result
	audit:Record("Economy", "CrateOpened", player.UserId, {
		crate = crate.Id,
		weapon = applied.WeaponId,
		rarity = applied.Rarity,
		duplicate = applied.Duplicate,
		compensation = applied.Compensation,
		fromPurchased = applied.FromPurchased,
		token = applied.UsedToken,
	})
	CrateService.CrateOpened:Fire(player, applied)
	playerData:RequestSave(player)
	economy:PushState(player)
	return { Ok = true, Replayed = false, Result = applied }
end

function CrateService.Init(_self: typeof(CrateService), registry: { [string]: any })
	net = registry.Net
	playerData = registry.PlayerDataService
	economy = registry.EconomyService
	policy = registry.PolicyComplianceService
	audit = registry.AuditService

	local active = {}
	for id, crate in Config.Crates.Crates do
		local distribution = CrateOdds.Build(crate)
		local problems = CrateOdds.Validate(crate, distribution)
		if #problems == 0 then
			distributions[id] = distribution
			table.insert(active, id)
		else
			log:Error(
				"crate failed validation and is disabled",
				{ crate = id, problems = table.concat(problems, "; ") }
			)
			audit:Record(
				"Economy",
				"CrateDisabled",
				nil,
				{ crate = id, problems = table.concat(problems, "; ") }
			)
		end
	end
	table.sort(active, function(a, b)
		return Config.Crates.Crates[a].Order < Config.Crates.Crates[b].Order
	end)
	economy.ActiveCrates = active
	log:Info("crates validated", { active = #active })

	net.OnInvoke("OpenCrate", open)
end

return CrateService
