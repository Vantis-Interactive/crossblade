--!strict
--[[
	Map pickups (spec §7, §8, §17). Health packs, ammunition and knife replacement stations are
	validated and consumed by the server only. Proximity is evaluated on the server from the
	character's root position; clients cannot trigger or claim pickups.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local PickupState = require(script.Parent.Parent.Domain.PickupState)

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local log = Logger.new("Pickup")
local P = Config.Pickups

type Entry = { Part: BasePart, State: PickupState.Pickup }

local PickupService = {
	Name = "PickupService",
	Dependencies = {
		"Net",
		"MapService",
		"HealthService",
		"AmmunitionService",
		"WeaponService",
		"MatchService",
	},
	-- (player, kind: "Health" | "Ammo" | "Knife")
	PickupConsumed = Signal.new() :: Signal.Signal<Player, string>,
}

local entries: { Entry } = {}
local stations: { BasePart } = {}
local stationCooldown: { [Player]: number } = {}
local net: any
local mapService: any
local health: any
local ammunition: any
local weapons: any
local match: any

local function setVisual(entry: Entry, available: boolean)
	if entry.Part:GetAttribute("Available") == available then
		return
	end
	entry.Part:SetAttribute("Available", available)
	entry.Part.Transparency = if available then 0.1 else 0.85
end

local function withinReach(rootPosition: Vector3, part: BasePart): boolean
	local delta = part.Position - rootPosition
	return Vector3.new(delta.X, 0, delta.Z).Magnitude <= P.PickupRadius
		and math.abs(delta.Y) <= P.PickupHeight
end

local function poll()
	local now = os.clock()
	for _, entry in entries do
		setVisual(entry, PickupState.IsAvailable(entry.State, now))
	end
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and health:IsAlive(player) and match:IsCombatAllowed(player) then
			for _, entry in entries do
				if PickupState.IsAvailable(entry.State, now) and withinReach(root.Position, entry.Part) then
					local state = entry.State
					if state.Kind == "Health" then
						local current = health:GetHealth(player)
						local consumed, target =
							PickupState.TryHeal(state, current, Config.Player.MaxHealth, now)
						if consumed then
							health:Heal(player, target - current)
							net.Fire(
								"Notification",
								player,
								{ Kind = "Pickup", Text = `+{math.floor(target - current)} HP` }
							)
							PickupService.PickupConsumed:Fire(player, "Health")
						end
					else
						local consumed = PickupState.TryAmmo(state, now, function()
							return ammunition:Refill(player, P.Ammo.MagazinesPerPickup)
						end)
						if consumed then
							weapons:PushState(player)
							net.Fire("Notification", player, { Kind = "Pickup", Text = "+AMMO" })
							PickupService.PickupConsumed:Fire(player, "Ammo")
						end
					end
					setVisual(entry, PickupState.IsAvailable(entry.State, now))
				end
			end
			for _, station in stations do
				if withinReach(root.Position, station) and now >= (stationCooldown[player] or 0) then
					if weapons:ReplaceKnife(player) then
						stationCooldown[player] = now + P.KnifeStation.CooldownSeconds
						net.Fire("Notification", player, { Kind = "Pickup", Text = "KNIFE REPLACED" })
						PickupService.PickupConsumed:Fire(player, "Knife")
					end
				end
			end
		end
	end
end

function PickupService.Init(_self: typeof(PickupService), registry: { [string]: any })
	net = registry.Net
	mapService = registry.MapService
	health = registry.HealthService
	ammunition = registry.AmmunitionService
	weapons = registry.WeaponService
	match = registry.MatchService
end

local function rebuild()
	table.clear(entries)
	for index, part in mapService:GetTagged("Health") do
		local size = part:GetAttribute("Size")
		local cfg = (P.Health :: any)[size]
		if cfg == nil then
			log:Warn(
				"health pickup with unknown Size attribute ignored",
				{ part = part:GetFullName(), size = size }
			)
		else
			table.insert(entries, {
				Part = part,
				State = PickupState.new(`health{index}`, "Health", cfg.Amount, cfg.RespawnSeconds),
			})
		end
	end
	for index, part in mapService:GetTagged("Ammo") do
		table.insert(entries, {
			Part = part,
			State = PickupState.new(`ammo{index}`, "Ammo", P.Ammo.MagazinesPerPickup, P.Ammo.RespawnSeconds),
		})
	end
	stations = mapService:GetTagged("KnifeStation")
	log:Info("pickups ready", { pickups = #entries, stations = #stations })
end

function PickupService.Start(_self: typeof(PickupService))
	rebuild()
	mapService.MapChanged:Connect(rebuild)

	Players.PlayerRemoving:Connect(function(player)
		stationCooldown[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(P.PollIntervalSeconds)
			local ok, err = pcall(poll)
			if not ok then
				log:Error("pickup poll failed", { error = err })
			end
		end
	end)
end

return PickupService
