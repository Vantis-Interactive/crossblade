--!strict
--[[
	Guided tutorial (spec §27). Steps run in order. Check:
	  "Client"  - the client reports completion (movement, camera, informational steps)
	  "Server"  - completion is observed by the server from real gameplay events (Event names below)
	The reward is granted once, on completing the step marked GrantsReward (500 coins + 1 Basic Crate,
	SPEC values). Later steps teach spending it.
]]

export type Step = {
	Id: string,
	Title: string,
	Text: string,
	Check: "Client" | "Server",
	Event: string?,
	Prepare: string?,
	GrantsReward: boolean?,
}

local Steps: { Step } = {
	{
		Id = "Move",
		Title = "Movement",
		Text = "Walk (WASD / left stick), sprint (Shift / L3) and jump (Space / A).",
		Check = "Client",
	},
	{
		Id = "Camera",
		Title = "Camera",
		Text = "Switch between first and third person (V / R3 / CAM).",
		Check = "Client",
	},
	{
		Id = "Weapons",
		Title = "Weapon selection",
		Text = "Switch to your pistol (2) and your knife (3), or cycle with Q / Y.",
		Check = "Client",
	},
	{
		Id = "Shoot",
		Title = "Aim and shoot",
		Text = "Equip a gun, aim (right mouse / L2) and hit a training dummy at the range.",
		Check = "Server",
		Event = "DummyHitFirearm",
	},
	{
		Id = "Reload",
		Title = "Reloading",
		Text = "Reload your gun (R / X). Ammunition is limited: watch your reserve.",
		Check = "Server",
		Event = "Reload",
	},
	{
		Id = "Knife",
		Title = "Knife attacks",
		Text = "Equip your knife and hit a dummy: slash (left mouse / R2) or stab (right mouse / L2).",
		Check = "Server",
		Event = "DummyHitKnife",
	},
	{
		Id = "Throw",
		Title = "Throw and recover",
		Text = "Throw your knife (G / B), then walk over it to pick it back up.",
		Check = "Server",
		Event = "KnifeRecovered",
	},
	{
		Id = "Pickups",
		Title = "Health and ammo",
		Text = "You took some damage. Collect a health pack and an ammo pack in the training zone.",
		Check = "Server",
		Event = "Pickups",
		Prepare = "Drain",
	},
	{
		Id = "Coins",
		Title = "Coins and XP",
		Text = "Eliminations, assists and wins earn coins and XP. Here is your reward: 500 coins and a Basic Crate.",
		Check = "Client",
		GrantsReward = true,
	},
	{
		Id = "Crate",
		Title = "Open a crate",
		Text = "Open Collection (I / D-pad up) > Crates and open your free Basic Crate.",
		Check = "Server",
		Event = "CrateOpened",
	},
	{
		Id = "Loadout",
		Title = "Customize your loadout",
		Text = "In Collection > Armory, equip a different weapon in any slot.",
		Check = "Server",
		Event = "LoadoutChanged",
	},
	{
		Id = "Matchmaking",
		Title = "Find a match",
		Text = "Walk into a portal or press PLAY to join a match. You're ready.",
		Check = "Client",
	},
}

for _, step in Steps do
	table.freeze(step)
end

return table.freeze({
	Steps = table.freeze(Steps),
	Reward = table.freeze({ Coins = 500, CrateId = "basic", Crates = 1 }),
	-- Health drained (non-lethally) before the Pickups step so a health pack is useful.
	DrainHealth = 60,
})
