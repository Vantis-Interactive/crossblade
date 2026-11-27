--!strict
--[[
	What kind of server this is (spec §19). Loaded once by Main BEFORE services boot (it may yield).
	  Public       - ordinary server of the place's mode (Roblox fills it)
	  Reserved     - created by matchmaking or a private match; its roster and settings come from the
	                 match record keyed by game.PrivateServerId. Teleport data is never trusted.
	  OwnedPrivate - a player-owned Roblox private server (no progression, see EconomyService)
	If a reserved server cannot read its record, Failed is set and players are returned to the hub.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local Retry = require(ReplicatedStorage.Shared.Util.Retry)

local log = Logger.new("MatchContext")

export type Record = {
	Destination: string,
	Mode: string,
	Teams: { [string]: { number } },
	Private: boolean,
	BaseMode: string?,
	Settings: { [string]: any }?,
	AccessCode: string,
	PlaceId: number,
	CreatedAt: number,
}

local MatchContext = {
	Kind = "Public" :: "Public" | "Reserved" | "OwnedPrivate",
	Record = nil :: Record?,
	Failed = false,
	Loaded = false,
}

function MatchContext.IsReserved(): boolean
	return MatchContext.Kind == "Reserved"
end

function MatchContext.IsPrivateMatch(): boolean
	return MatchContext.Record ~= nil and (MatchContext.Record :: Record).Private
end

function MatchContext.Load()
	if MatchContext.Loaded then
		return
	end
	MatchContext.Loaded = true
	if game.PrivateServerId == "" then
		return
	end
	if game.PrivateServerOwnerId ~= 0 then
		MatchContext.Kind = "OwnedPrivate"
		return
	end
	MatchContext.Kind = "Reserved"
	local ok, record = Retry.Call(
		{ MaxAttempts = 4, BaseBackoffSeconds = 1, MaxBackoffSeconds = 4 },
		function()
			local MemoryStoreAdapter = require(script.Parent.Parent.Matchmaking.MemoryStoreAdapter) :: any
			return MemoryStoreAdapter.Map(Config.Matchmaking.StoreNames.Matches)
				:GetAsync(game.PrivateServerId)
		end
	)
	if ok and type(record) == "table" and type(record.Teams) == "table" and type(record.Mode) == "string" then
		MatchContext.Record = record
		log:Info("reserved match record loaded", { mode = record.Mode, private = record.Private })
	else
		MatchContext.Failed = true
		log:Error(
			"reserved server has no readable match record; players will be returned",
			{ error = if ok then "missing" else record }
		)
	end
end

-- Mode config for this server: the place's mode, or a private-match variant built from settings.
function MatchContext.ModeConfig(placeMode: string): { [string]: any }?
	local record = MatchContext.Record
	if record == nil then
		return Config.GameModes[placeMode]
	end
	if not record.Private then
		return Config.GameModes[record.Mode]
	end
	local base = Config.GameModes[record.BaseMode or "FreeForAll"]
	if base == nil then
		return nil
	end
	local settings = record.Settings or {}
	local mode = table.clone(base)
	mode.Id = "Private"
	mode.DisplayName = `Private {base.DisplayName}`
	mode.AwardsProgression = false -- private matches never award progression (spec §5)
	mode.MapVote = false
	mode.CountdownSeconds = 5
	if type(settings.DurationMinutes) == "number" then
		mode.DurationSeconds = settings.DurationMinutes * 60
	end
	if base.Kind == "TeamDeathmatch" and type(settings.ScoreLimit) == "number" then
		mode.ScoreLimit = settings.ScoreLimit
	end
	return table.freeze(mode)
end

return MatchContext
