--!strict
--[[
	Weapon collections (spec §11). Purely cosmetic: a collection supplies the finish colour applied to
	a weapon's model. "Starter" weapons belong to Classic. Seasonal collections (Halloween, Winter,
	Anniversary) are added with their season content (Phase 12) and are intentionally absent here.
]]
export type Collection = { Id: string, DisplayName: string, Finish: Color3, Accent: Color3 }

local Collections: { [string]: Collection } = {
	Classic = {
		Id = "Classic",
		DisplayName = "Classic",
		Finish = Color3.fromRGB(70, 74, 72),
		Accent = Color3.fromRGB(96, 110, 62),
	},
	Tactical = {
		Id = "Tactical",
		DisplayName = "Tactical",
		Finish = Color3.fromRGB(88, 92, 70),
		Accent = Color3.fromRGB(150, 140, 100),
	},
	Inferno = {
		Id = "Inferno",
		DisplayName = "Inferno",
		Finish = Color3.fromRGB(120, 40, 26),
		Accent = Color3.fromRGB(255, 140, 40),
	},
	Arctic = {
		Id = "Arctic",
		DisplayName = "Arctic",
		Finish = Color3.fromRGB(210, 222, 230),
		Accent = Color3.fromRGB(120, 190, 235),
	},
	Cyberpunk = {
		Id = "Cyberpunk",
		DisplayName = "Cyberpunk",
		Finish = Color3.fromRGB(30, 26, 48),
		Accent = Color3.fromRGB(255, 60, 200),
	},
	Shadow = {
		Id = "Shadow",
		DisplayName = "Shadow",
		Finish = Color3.fromRGB(22, 22, 26),
		Accent = Color3.fromRGB(110, 90, 150),
	},
	Galaxy = {
		Id = "Galaxy",
		DisplayName = "Galaxy",
		Finish = Color3.fromRGB(36, 30, 80),
		Accent = Color3.fromRGB(150, 120, 255),
	},
	Celestial = {
		Id = "Celestial",
		DisplayName = "Celestial",
		Finish = Color3.fromRGB(235, 225, 190),
		Accent = Color3.fromRGB(120, 235, 235),
	},
}

for _, collection in Collections do
	table.freeze(collection)
end

return table.freeze(Collections)
