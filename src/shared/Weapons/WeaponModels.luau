--!strict
--[[
	TEMPORARY DEVELOPMENT ASSETS (tracked in docs/ASSET_MANIFEST.md as DEV-MODEL-001..003).
	Builds simple primitive-part weapon models from data so the vertical slice is playable before
	original weapon meshes exist. Replace by pointing ModelProfile at authored models in Phase 9;
	no combat code depends on this geometry.
]]

export type PartSpec =
	{ Name: string, Size: Vector3, Offset: Vector3, Color: Color3, Material: Enum.Material }
export type Profile = { Parts: { PartSpec }, Muzzle: Vector3, Grip: CFrame }

local METAL = Color3.fromRGB(58, 62, 60)
local OLIVE = Color3.fromRGB(96, 110, 62)
local STEEL = Color3.fromRGB(170, 176, 180)

local Profiles: { [string]: Profile } = {
	Rifle = {
		Parts = {
			{
				Name = "Body",
				Size = Vector3.new(0.35, 0.45, 2.2),
				Offset = Vector3.new(0, 0, -0.6),
				Color = METAL,
				Material = Enum.Material.Metal,
			},
			{
				Name = "Barrel",
				Size = Vector3.new(0.14, 0.14, 1.2),
				Offset = Vector3.new(0, 0.08, -2.25),
				Color = METAL,
				Material = Enum.Material.Metal,
			},
			{
				Name = "Stock",
				Size = Vector3.new(0.3, 0.5, 0.8),
				Offset = Vector3.new(0, -0.1, 0.85),
				Color = OLIVE,
				Material = Enum.Material.SmoothPlastic,
			},
			{
				Name = "Magazine",
				Size = Vector3.new(0.22, 0.7, 0.35),
				Offset = Vector3.new(0, -0.5, -0.8),
				Color = OLIVE,
				Material = Enum.Material.SmoothPlastic,
			},
			{
				Name = "Grip",
				Size = Vector3.new(0.2, 0.55, 0.28),
				Offset = Vector3.new(0, -0.45, -0.05),
				Color = METAL,
				Material = Enum.Material.SmoothPlastic,
			},
		},
		Muzzle = Vector3.new(0, 0.08, -2.9),
		Grip = CFrame.new(0, -0.45, -0.05),
	},
	Pistol = {
		Parts = {
			{
				Name = "Slide",
				Size = Vector3.new(0.22, 0.26, 0.95),
				Offset = Vector3.new(0, 0.12, -0.35),
				Color = METAL,
				Material = Enum.Material.Metal,
			},
			{
				Name = "Grip",
				Size = Vector3.new(0.2, 0.55, 0.3),
				Offset = Vector3.new(0, -0.2, 0),
				Color = OLIVE,
				Material = Enum.Material.SmoothPlastic,
			},
		},
		Muzzle = Vector3.new(0, 0.12, -0.85),
		Grip = CFrame.new(0, -0.2, 0),
	},
	Knife = {
		Parts = {
			{
				Name = "Blade",
				Size = Vector3.new(0.06, 0.22, 1.0),
				Offset = Vector3.new(0, 0, -0.75),
				Color = STEEL,
				Material = Enum.Material.Metal,
			},
			{
				Name = "Handle",
				Size = Vector3.new(0.14, 0.2, 0.5),
				Offset = Vector3.new(0, 0, 0),
				Color = OLIVE,
				Material = Enum.Material.SmoothPlastic,
			},
		},
		Muzzle = Vector3.new(0, 0, -1.25),
		Grip = CFrame.new(0, 0, 0),
	},
}

local WeaponModels = {}

WeaponModels.Profiles = Profiles

-- Builds an unanchored, non-colliding, massless model whose PrimaryPart is "Handle" at the grip.
function WeaponModels.Build(profileName: string, weaponId: string): Model
	local profile = Profiles[profileName] or Profiles.Rifle
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
		local part = Instance.new("Part")
		part.Name = spec.Name
		part.Size = spec.Size
		part.Color = spec.Color
		part.Material = spec.Material
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		part.CFrame = profile.Grip:Inverse() * CFrame.new(spec.Offset)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part
		part.Parent = model
	end

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = (profile.Grip:Inverse() * CFrame.new(profile.Muzzle)).Position
	muzzle.Parent = handle

	model:SetAttribute("WeaponId", weaponId)
	return model
end

return WeaponModels
