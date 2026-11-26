--!strict
--[[
	TEMPORARY DEVELOPMENT ASSETS (tracked in docs/ASSET_MANIFEST.md as DEV-MODEL-001..003).
	Builds simple primitive-part weapon models from data so the vertical slice is playable before
	original weapon meshes exist. Replace by pointing ModelProfile at authored models in Phase 9;
	no combat code depends on this geometry.
]]

export type Role = "Finish" | "Accent" | "Steel"
export type PartSpec = { Name: string, Size: Vector3, Offset: Vector3, Role: Role, Material: Enum.Material }
export type Profile = { Parts: { PartSpec }, Muzzle: Vector3, Grip: CFrame }

local Config = require(script.Parent.Parent.Config)

local DEFAULT_FINISH = Color3.fromRGB(58, 62, 60)
local DEFAULT_ACCENT = Color3.fromRGB(96, 110, 62)
local STEEL = Color3.fromRGB(170, 176, 180)
local METAL = Enum.Material.Metal
local PLASTIC = Enum.Material.SmoothPlastic

local function part(
	name: string,
	size: Vector3,
	offset: Vector3,
	role: Role,
	material: Enum.Material?
): PartSpec
	return { Name = name, Size = size, Offset = offset, Role = role, Material = material or METAL }
end

local Profiles: { [string]: Profile } = {
	Rifle = {
		Parts = {
			part("Body", Vector3.new(0.35, 0.45, 2.2), Vector3.new(0, 0, -0.6), "Finish"),
			part("Barrel", Vector3.new(0.14, 0.14, 1.2), Vector3.new(0, 0.08, -2.25), "Steel"),
			part("Stock", Vector3.new(0.3, 0.5, 0.8), Vector3.new(0, -0.1, 0.85), "Accent", PLASTIC),
			part("Magazine", Vector3.new(0.22, 0.7, 0.35), Vector3.new(0, -0.5, -0.8), "Accent", PLASTIC),
			part("Grip", Vector3.new(0.2, 0.55, 0.28), Vector3.new(0, -0.45, -0.05), "Finish", PLASTIC),
		},
		Muzzle = Vector3.new(0, 0.08, -2.9),
		Grip = CFrame.new(0, -0.45, -0.05),
	},
	SMG = {
		Parts = {
			part("Body", Vector3.new(0.32, 0.42, 1.5), Vector3.new(0, 0, -0.4), "Finish"),
			part("Barrel", Vector3.new(0.12, 0.12, 0.5), Vector3.new(0, 0.06, -1.4), "Steel"),
			part("Magazine", Vector3.new(0.18, 0.9, 0.25), Vector3.new(0, -0.6, -0.55), "Accent", PLASTIC),
			part("Grip", Vector3.new(0.2, 0.5, 0.26), Vector3.new(0, -0.4, 0), "Finish", PLASTIC),
		},
		Muzzle = Vector3.new(0, 0.06, -1.7),
		Grip = CFrame.new(0, -0.4, 0),
	},
	Shotgun = {
		Parts = {
			part("Body", Vector3.new(0.36, 0.42, 1.6), Vector3.new(0, 0, -0.4), "Finish"),
			part("Barrel", Vector3.new(0.2, 0.2, 1.5), Vector3.new(0, 0.1, -1.9), "Steel"),
			part("Pump", Vector3.new(0.28, 0.24, 0.6), Vector3.new(0, -0.12, -1.6), "Accent", PLASTIC),
			part(
				"Stock",
				Vector3.new(0.3, 0.5, 0.9),
				Vector3.new(0, -0.12, 0.85),
				"Accent",
				Enum.Material.Wood
			),
			part("Grip", Vector3.new(0.2, 0.5, 0.28), Vector3.new(0, -0.42, 0), "Finish", PLASTIC),
		},
		Muzzle = Vector3.new(0, 0.1, -2.7),
		Grip = CFrame.new(0, -0.42, 0),
	},
	Sniper = {
		Parts = {
			part("Body", Vector3.new(0.32, 0.4, 2.4), Vector3.new(0, 0, -0.5), "Finish"),
			part("Barrel", Vector3.new(0.12, 0.12, 1.8), Vector3.new(0, 0.06, -2.6), "Steel"),
			part("Scope", Vector3.new(0.2, 0.2, 0.9), Vector3.new(0, 0.38, -0.6), "Steel"),
			part("Stock", Vector3.new(0.3, 0.55, 1.0), Vector3.new(0, -0.1, 1.05), "Accent", PLASTIC),
			part("Grip", Vector3.new(0.2, 0.5, 0.28), Vector3.new(0, -0.42, 0.1), "Finish", PLASTIC),
		},
		Muzzle = Vector3.new(0, 0.06, -3.5),
		Grip = CFrame.new(0, -0.42, 0.1),
	},
	Pistol = {
		Parts = {
			part("Slide", Vector3.new(0.22, 0.26, 0.95), Vector3.new(0, 0.12, -0.35), "Finish"),
			part("Grip", Vector3.new(0.2, 0.55, 0.3), Vector3.new(0, -0.2, 0), "Accent", PLASTIC),
		},
		Muzzle = Vector3.new(0, 0.12, -0.85),
		Grip = CFrame.new(0, -0.2, 0),
	},
	Revolver = {
		Parts = {
			part("Frame", Vector3.new(0.22, 0.3, 0.6), Vector3.new(0, 0.12, -0.25), "Finish"),
			part("Cylinder", Vector3.new(0.3, 0.3, 0.3), Vector3.new(0, 0.1, -0.3), "Steel"),
			part("Barrel", Vector3.new(0.12, 0.12, 0.7), Vector3.new(0, 0.18, -0.85), "Steel"),
			part(
				"Grip",
				Vector3.new(0.2, 0.55, 0.3),
				Vector3.new(0, -0.2, 0.05),
				"Accent",
				Enum.Material.Wood
			),
		},
		Muzzle = Vector3.new(0, 0.18, -1.2),
		Grip = CFrame.new(0, -0.2, 0.05),
	},
	Knife = {
		Parts = {
			part("Blade", Vector3.new(0.06, 0.22, 1.0), Vector3.new(0, 0, -0.75), "Steel"),
			part("Guard", Vector3.new(0.1, 0.36, 0.06), Vector3.new(0, 0, -0.26), "Finish"),
			part("Handle", Vector3.new(0.14, 0.2, 0.5), Vector3.new(0, 0, 0), "Accent", PLASTIC),
		},
		Muzzle = Vector3.new(0, 0, -1.25),
		Grip = CFrame.new(0, 0, 0),
	},
}

local function palette(weaponId: string): (Color3, Color3)
	local entry = Config.Catalog.Entries[weaponId]
	local collection = entry and Config.Collections[entry.Collection]
	if collection then
		return collection.Finish, collection.Accent
	end
	return DEFAULT_FINISH, DEFAULT_ACCENT
end

local WeaponModels = {}

WeaponModels.Profiles = Profiles

-- Builds an unanchored, non-colliding, massless model whose PrimaryPart is "Handle" at the grip.
function WeaponModels.Build(profileName: string, weaponId: string): Model
	local profile = Profiles[profileName] or Profiles.Rifle
	local finish, accent = palette(weaponId)
	local model = Instance.new("Model")
	model.Name = weaponId

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.1, 0.1, 0.1)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.CFrame = CFrame.new()
	handle.Parent = model
	model.PrimaryPart = handle

	for _, spec in profile.Parts do
		local piece = Instance.new("Part")
		piece.Name = spec.Name
		piece.Size = spec.Size
		piece.Color = if spec.Role == "Finish" then finish elseif spec.Role == "Accent" then accent else STEEL
		piece.Material = spec.Material
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.Massless = true
		piece.CastShadow = false
		piece.CFrame = profile.Grip:Inverse() * CFrame.new(spec.Offset)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = piece
		weld.Parent = piece
		piece.Parent = model
	end

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = (profile.Grip:Inverse() * CFrame.new(profile.Muzzle)).Position
	muzzle.Parent = handle

	model:SetAttribute("WeaponId", weaponId)
	return model
end

return WeaponModels
