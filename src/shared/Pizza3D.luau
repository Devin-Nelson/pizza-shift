--!strict
-- 3D pizza builder shared by the client minigames (built up piece by piece)
-- and the server (whole pizzas riding the oven / waiting on the cut table).
--
-- `frame` is an upright CFrame at the crust's center: the pizza lies in its
-- XZ plane, Y is up. Every piece is welded to the anchored crust, so moving
-- or tweening the crust moves the whole pizza.

local Config = require(script.Parent.Config)

local Pizza3D = {}
Pizza3D.__index = Pizza3D

-- A pizza at any point in the make process: leave out a layer that hasn't been added yet.
export type Spec = {
	size: string,
	sauce: number?, -- 0..1 coverage (nil = not sauced yet)
	cheese: number?, -- 0..1+ ratio of the target portion (nil = not cheesed yet)
	toppings: { [string]: number }?,
	seed: number?,
	baked: boolean?,
}

local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> Y
local CRUST_RAW = Config.IngredientColors.Dough
local CRUST_BAKED = Color3.fromRGB(205, 140, 60)
local CHEESE_RAW = Config.IngredientColors.Cheese
local CHEESE_BAKED = Color3.fromRGB(240, 185, 80)
local THICK = 0.12

Pizza3D.FLAT = FLAT

local function newPart(name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

-- Topping piece styles: size, shape, material, random yaw?
local STYLES: { [string]: { size: Vector3, shape: Enum.PartType?, material: Enum.Material?, yaw: boolean } } = {
	Pepperoni = { size = Vector3.new(0.03, 0.26, 0.26), shape = Enum.PartType.Cylinder, yaw = false },
	Ham = { size = Vector3.new(0.2, 0.03, 0.2), yaw = true },
	Pineapple = { size = Vector3.new(0.16, 0.06, 0.11), yaw = true },
	Peppers = { size = Vector3.new(0.3, 0.035, 0.06), yaw = true },
	Mushrooms = { size = Vector3.new(0.035, 0.22, 0.22), shape = Enum.PartType.Cylinder, material = Enum.Material.Plastic, yaw = false },
	Olives = { size = Vector3.new(0.04, 0.14, 0.14), shape = Enum.PartType.Cylinder, yaw = false },
}

export type Pizza = typeof(setmetatable({} :: {
	model: Model,
	crust: Part,
	diameter: number,
	thickness: number,
	sauceCount: number,
	cheese: Part?,
	pieces: { [string]: { BasePart } },
	cuts: { BasePart },
}, Pizza3D))

function Pizza3D.new(frame: CFrame, diameter: number, parent: Instance?, thickness: number?): Pizza
	local model = Instance.new("Model")
	model.Name = "Pizza3D"
	local t = thickness or THICK
	local crust = newPart("Crust", Vector3.new(t, diameter, diameter), CRUST_RAW, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	crust.Anchored = true
	crust.CFrame = frame * FLAT
	crust.Parent = model
	model.PrimaryPart = crust
	model.Parent = parent or workspace
	local self = setmetatable({
		model = model,
		crust = crust,
		diameter = diameter,
		thickness = t,
		sauceCount = 0,
		cheese = nil,
		pieces = {},
		cuts = {},
	}, Pizza3D)
	return self
end

-- Upright frame at the crust center (follows the crust if it moves).
function Pizza3D.frame(self: Pizza): CFrame
	return self.crust.CFrame * FLAT:Inverse()
end

function Pizza3D.top(self: Pizza): number
	return self.thickness / 2
end

function Pizza3D._attach(self: Pizza, part: BasePart, localCF: CFrame)
	part.CFrame = self:frame() * localCF
	part.Anchored = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = self.crust
	weld.Part1 = part
	weld.Parent = part
	part.Parent = self.model
end

-- Dough stage: resize the crust (no pieces are attached yet).
function Pizza3D.setDough(self: Pizza, diameter: number, thickness: number)
	local frame = self:frame()
	self.diameter = diameter
	self.thickness = thickness
	self.crust.Size = Vector3.new(thickness, diameter, diameter)
	self.crust.CFrame = frame * FLAT
end

-- A splat of sauce at local (x, z) with radius r.
function Pizza3D.addSauce(self: Pizza, x: number, z: number, r: number)
	self.sauceCount += 1
	local layer = (self.sauceCount % 6) * 0.002
	local splat = newPart("Sauce", Vector3.new(0.02, r * 2, r * 2), Config.IngredientColors.Sauce, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	self:_attach(splat, CFrame.new(x, self:top() + 0.01 + layer, z) * FLAT)
end

function Pizza3D.setSauceFull(self: Pizza, coverage: number)
	local d = self.diameter * Config.Sauce.Coverage * math.clamp(0.5 + coverage * 0.5, 0.5, 1)
	local disc = newPart("Sauce", Vector3.new(0.02, d, d), Config.IngredientColors.Sauce, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	self:_attach(disc, CFrame.new(0, self:top() + 0.01, 0) * FLAT)
end

-- Cheese layer; ratio 0 = none, 1 = full portion (more = thicker, opaque).
function Pizza3D.setCheese(self: Pizza, ratio: number)
	if not self.cheese then
		local d = self.diameter * 0.84
		local layer = newPart("Cheese", Vector3.new(0.03, d, d), CHEESE_RAW, Enum.Material.Sand, Enum.PartType.Cylinder)
		self:_attach(layer, CFrame.new(0, self:top() + 0.03, 0) * FLAT)
		self.cheese = layer
	end
	local cheese = self.cheese :: Part
	cheese.Transparency = 1 - math.clamp(ratio, 0, 1) * 0.95
end

function Pizza3D.addTopping(self: Pizza, name: string, x: number, z: number, rng: Random?): BasePart
	local style = STYLES[name] or STYLES.Pepperoni
	local r = rng or Random.new()
	local piece = newPart(name, style.size, Config.IngredientColors[name] or Color3.new(1, 0, 0), style.material, style.shape)
	local yaw = if style.yaw then r:NextNumber(0, math.pi * 2) else 0
	local lift = self:top() + 0.06 + r:NextNumber(0, 0.02)
	local cf = CFrame.new(x, lift, z) * CFrame.Angles(0, yaw, 0)
	if style.shape == Enum.PartType.Cylinder then
		cf *= FLAT
	end
	self:_attach(piece, cf)
	self.pieces[name] = self.pieces[name] or {}
	table.insert(self.pieces[name], piece)
	return piece
end

function Pizza3D.removeTopping(self: Pizza, name: string, count: number): number
	local list = self.pieces[name]
	local removed = 0
	while list and #list > 0 and removed < count do
		local p = table.remove(list) :: BasePart
		p:Destroy()
		removed += 1
	end
	return removed
end

function Pizza3D.count(self: Pizza, name: string): number
	local list = self.pieces[name]
	return if list then #list else 0
end

-- A cut line across the whole pizza at `degrees` (yaw).
function Pizza3D.addCut(self: Pizza, degrees: number)
	local line = newPart("Cut", Vector3.new(self.diameter * 0.98, 0.02, 0.035), Color3.fromRGB(110, 60, 25))
	self:_attach(line, CFrame.Angles(0, math.rad(degrees), 0) * CFrame.new(0, self:top() + 0.1, 0))
	table.insert(self.cuts, line)
end

function Pizza3D.setBaked(self: Pizza, baked: boolean)
	self.crust.Color = if baked then CRUST_BAKED else CRUST_RAW
	if self.cheese then
		self.cheese.Color = if baked then CHEESE_BAKED else CHEESE_RAW
	end
end

-- Random point inside the topping area (uniform over the disc).
function Pizza3D.randomPoint(self: Pizza, rng: Random): (number, number)
	local a = rng:NextNumber(0, math.pi * 2)
	local r = math.sqrt(rng:NextNumber()) * self.diameter * 0.39
	return math.cos(a) * r, math.sin(a) * r
end

function Pizza3D.Destroy(self: Pizza)
	self.model:Destroy()
end

-- Builds a pizza in one go with whatever layers the spec has (unbaked unless
-- spec.baked). Same seed = same topping layout.
function Pizza3D.fromSpec(frame: CFrame, spec: Spec, parent: Instance?): Pizza
	local diameter = Config.PizzaDiameter[spec.size] or 2.4
	local pizza = Pizza3D.new(frame, diameter, parent)
	if spec.sauce then
		pizza:setSauceFull(spec.sauce)
	end
	if spec.cheese then
		pizza:setCheese(spec.cheese)
	end
	local rng = Random.new(spec.seed or 1)
	if spec.toppings then
		for _, name in Config.Toppings do
			local n = math.clamp(math.floor(spec.toppings[name] or 0), 0, 80)
			for _ = 1, n do
				local x, z = pizza:randomPoint(rng)
				pizza:addTopping(name, x, z, rng)
			end
		end
	end
	pizza:setBaked(spec.baked == true)
	return pizza
end

-- Moves a pizza model (from any builder) so its crust center sits at `frame`.
function Pizza3D.place(model: Model, frame: CFrame)
	model:PivotTo(frame * FLAT)
end

return Pizza3D
