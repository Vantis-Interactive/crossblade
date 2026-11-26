--!strict
--[[
	Experience places (spec §4 "Experience architecture"). Each place is built from its own Rojo
	project file in places/ and identifies itself through ReplicatedStorage.PlaceConfig attributes
	(read by Shared/PlaceConfig).

	PlaceIds are 0 until the places are published under the owner's account (directive §2.17). While a
	destination's PlaceId is 0, teleporting to it is refused with a clear message; nothing is faked.
]]

export type Destination = { Id: string, DisplayName: string, PlaceId: number, Mode: string? }

local Places = {
	Destinations = {
		Hub = { Id = "Hub", DisplayName = "Social Hub", PlaceId = 0 },
		FreeForAll = { Id = "FreeForAll", DisplayName = "Free-for-All", PlaceId = 0, Mode = "FreeForAll" },
		TeamDeathmatch = {
			Id = "TeamDeathmatch",
			DisplayName = "Team Deathmatch",
			PlaceId = 0,
			Mode = "TeamDeathmatch",
		},
		CasualDuel1v1 = {
			Id = "CasualDuel1v1",
			DisplayName = "Duel 1v1",
			PlaceId = 0,
			Mode = "CasualDuel1v1",
		},
		CasualDuelTeam = {
			Id = "CasualDuelTeam",
			DisplayName = "Team Duel 2v2",
			PlaceId = 0,
			Mode = "CasualDuelTeam",
		},
	} :: { [string]: Destination },
	-- Display order in the Play menu.
	PlayOrder = { "FreeForAll", "TeamDeathmatch", "CasualDuel1v1", "CasualDuelTeam" },
	Teleport = { MaxAttempts = 3, BaseBackoffSeconds = 1, MaxBackoffSeconds = 4 },
}

return table.freeze(Places)
