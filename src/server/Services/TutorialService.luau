--!strict
--[[
	Guided tutorial (spec §27), hub only. First-time players start automatically; anyone can replay
	from the Training station. Step order and checks come from Config.Tutorial and are enforced by
	Domain/TutorialProgress: combat steps complete only from server-observed gameplay (dummy hits,
	reloads, knife recovery, pickups, crate opening, loadout change). The reward (500 coins + one
	Basic Crate token) is granted once per account through EconomyService.GrantTutorialReward.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local TutorialProgress = require(script.Parent.Parent.Domain.TutorialProgress)

local T = Config.Tutorial

local TutorialService = {
	Name = "TutorialService",
	Roles = { "Hub" },
	Dependencies = {
		"Net",
		"PlayerDataService",
		"EconomyService",
		"TrainingService",
		"WeaponService",
		"PickupService",
		"CrateService",
		"InventoryService",
		"HealthService",
		"AmmunitionService",
		"AuditService",
	},
}

type Session = { Progress: TutorialProgress.State, Pickups: { [string]: boolean } }

local sessions: { [Player]: Session } = {}
local net: any
local playerData: any
local economy: any
local health: any
local ammunition: any
local weapons: any
local audit: any

local function data(player: Player): { [string]: any }?
	local profile = playerData:GetProfile(player)
	return profile and profile.Data
end

local function push(player: Player)
	local session = sessions[player]
	local saved = data(player)
	local step = session and TutorialProgress.Current(session.Progress, T.Steps)
	net.Fire("TutorialState", player, {
		Active = step ~= nil,
		Index = if session then session.Progress.Index else nil,
		StepId = step and step.Id,
		Total = #T.Steps,
		Completed = saved ~= nil and saved.Tutorial.Completed,
		RewardClaimed = saved ~= nil and saved.Tutorial.RewardClaimed,
	})
end

local function prepare(player: Player)
	local session = sessions[player]
	local step = session and TutorialProgress.Current(session.Progress, T.Steps)
	if step and step.Prepare == "Drain" then
		table.clear(session.Pickups)
		health:Drain(player, T.DrainHealth)
		for _, slot in { "Primary", "Secondary" } do
			local state = ammunition:Get(player, slot)
			if state then
				state.Reserve = 0 -- so the ammo pack in the training zone is useful
			end
		end
		weapons:PushState(player)
	end
end

local function apply(player: Player, result: TutorialProgress.Result)
	if not result.Advanced then
		return
	end
	if result.GrantReward then
		economy:GrantTutorialReward(player, T.Reward.Coins, T.Reward.CrateId, T.Reward.Crates)
	end
	if result.Finished then
		sessions[player] = nil
		local saved = data(player)
		if saved and not saved.Tutorial.Completed then
			playerData:Update(player, function(profileData)
				profileData.Tutorial.Completed = true
			end)
			playerData:RequestSave(player)
			audit:Record("Data", "TutorialCompleted", player.UserId, nil)
		end
	else
		prepare(player)
	end
	push(player)
end

local function event(player: Player, name: string)
	local session = sessions[player]
	local saved = data(player)
	if session and saved then
		apply(
			player,
			TutorialProgress.ServerEvent(session.Progress, T.Steps, name, saved.Tutorial.RewardClaimed)
		)
	end
end

local function start(player: Player)
	sessions[player] = { Progress = TutorialProgress.new(), Pickups = {} }
	push(player)
end

function TutorialService.Init(_self: typeof(TutorialService), registry: { [string]: any })
	net = registry.Net
	playerData = registry.PlayerDataService
	economy = registry.EconomyService
	health = registry.HealthService
	ammunition = registry.AmmunitionService
	weapons = registry.WeaponService
	audit = registry.AuditService

	playerData.ProfileLoaded:Connect(function(player: Player, profile: any)
		if not profile.Data.Tutorial.Completed then
			start(player)
		else
			push(player)
		end
	end)

	net.OnEvent("TutorialAction", function(player: Player, payload: any)
		local saved = data(player)
		if saved == nil then
			return
		end
		if payload.Action == "Start" then
			start(player)
		elseif payload.Action == "Exit" then
			-- Only replays can be abandoned; first-time players must complete the tutorial.
			if saved.Tutorial.Completed then
				sessions[player] = nil
				push(player)
			end
		elseif payload.Action == "Complete" and payload.Step then
			local session = sessions[player]
			if session then
				apply(
					player,
					TutorialProgress.ClientComplete(
						session.Progress,
						T.Steps,
						payload.Step,
						saved.Tutorial.RewardClaimed
					)
				)
			end
		end
	end)

	registry.TrainingService.DummyHit:Connect(function(player: Player, kind: string)
		if kind == "Firearm" then
			event(player, "DummyHitFirearm")
		elseif kind == "Knife" then
			event(player, "DummyHitKnife")
		end
	end)
	registry.WeaponService.Reloaded:Connect(function(player: Player)
		event(player, "Reload")
	end)
	registry.WeaponService.KnifeRecovered:Connect(function(player: Player)
		event(player, "KnifeRecovered")
	end)
	registry.PickupService.PickupConsumed:Connect(function(player: Player, kind: string)
		local session = sessions[player]
		if session then
			session.Pickups[kind] = true
			if session.Pickups.Health and session.Pickups.Ammo then
				event(player, "Pickups")
			end
		end
	end)
	registry.CrateService.CrateOpened:Connect(function(player: Player)
		event(player, "CrateOpened")
	end)
	registry.InventoryService.Changed:Connect(function(player: Player)
		event(player, "LoadoutChanged")
	end)
end

function TutorialService.Start(_self: typeof(TutorialService))
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end

return TutorialService
