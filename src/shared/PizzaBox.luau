--!strict
-- A pizza box blank (the user's reference, 2026-10-21): the die-cut sheet's
-- panels and how each folds. Flat on the cut table's stacks until the pizza
-- on it is cut; then the side walls rise, the front and back walls rise with
-- their corner tabs folding in, the side walls' and the front wall's inner
-- layers fold over the tabs, and the lid (on the back wall) closes with its
-- side flaps and front tuck flap folding down. The server builds the flat
-- top blank of each stack from these panels (StationArt); the cut minigame
-- folds its own copy (tools/blender/cut_table.py draws the same outline).
--
-- Frames: the root is the base panel's top surface at its centre, +Z toward
-- the back (the lid's hinge), Y up. Each panel hangs off a hinge line (its
-- frame's X axis) and runs along its frame's +Z; folding turns +Z toward +Y
-- (the board's inside face).

local PizzaBox = {}

PizzaBox.Wall = 0.2 -- wall height (the cut minigame's WallHeight)
PizzaBox.Thick = 0.025 -- the board
PizzaBox.Time = 1.45 -- seconds for the whole fold

export type Panel = {
	name: string,
	parent: number?, -- index into the list (nil: the base)
	hinge: CFrame, -- in the parent's frame
	width: number, -- along the hinge
	length: number, -- away from it
	fold: number, -- degrees when the box is shut
	from: number, -- seconds into the fold when it starts turning
	to: number, -- and when it's done
}

local W, T = PizzaBox.Wall, PizzaBox.Thick

local function yaw(deg: number): CFrame
	return CFrame.Angles(0, math.rad(deg), 0)
end

-- The panels of a box for a pizza box `bs` across (Config.BoxSize).
function PizzaBox.panels(bs: number): { Panel }
	local list: { Panel } = {
		{ name = "Base", parent = nil, hinge = CFrame.identity, width = bs, length = bs, fold = 0, from = 0, to = 0 },
	}
	local function add(p: Panel): number
		table.insert(list, p)
		return #list
	end
	for _, s in { 1, -1 } do
		local side = add({ name = "Side", parent = 1, hinge = CFrame.new(s * bs / 2, 0, 0) * yaw(s * 90), width = bs, length = W, fold = 90, from = 0, to = 0.3 })
		add({ name = "SideFlap", parent = side, hinge = CFrame.new(0, 0, W), width = bs - 0.04, length = W - 0.01, fold = 180, from = 0.55, to = 0.85 })
	end
	local front = add({ name = "Front", parent = 1, hinge = CFrame.new(0, 0, -bs / 2) * yaw(180), width = bs - 4 * T, length = W, fold = 90, from = 0.25, to = 0.55 })
	local back = add({ name = "Back", parent = 1, hinge = CFrame.new(0, 0, bs / 2), width = bs - 4 * T, length = W, fold = 90, from = 0.25, to = 0.55 })
	for _, wall in { front, back } do
		for _, s in { 1, -1 } do
			-- Corner tabs: they fold in along the side walls, inside the side walls' inner layer.
			add({ name = "Tab", parent = wall, hinge = CFrame.new(s * (bs / 2 - 2 * T), 0, W / 2) * yaw(s * 90), width = W - 0.04, length = W - 0.02, fold = 90, from = 0.35, to = 0.55 })
		end
	end
	add({ name = "FrontFlap", parent = front, hinge = CFrame.new(0, 0, W), width = bs - 0.12, length = W - 0.01, fold = 180, from = 0.6, to = 0.9 })
	local lidLen = bs - 2 * T -- it closes inside the front wall's inner layer
	local lid = add({ name = "Lid", parent = back, hinge = CFrame.new(0, 0, W), width = bs + 2 * T, length = lidLen, fold = 90, from = 0.95, to = 1.45 })
	for _, s in { 1, -1 } do
		add({ name = "LidFlap", parent = lid, hinge = CFrame.new(s * (bs / 2 + T), 0, lidLen / 2) * yaw(s * 90), width = bs - 0.3, length = W - 0.03, fold = 90, from = 0.95, to = 1.2 })
	end
	add({ name = "Tuck", parent = lid, hinge = CFrame.new(0, 0, lidLen), width = bs - 0.12, length = W - 0.03, fold = 90, from = 1.05, to = 1.35 })
	return list
end

-- The flat blank's width and depth.
function PizzaBox.blankSize(bs: number): (number, number)
	return bs + 4 * W - 0.02, 2 * bs + 4 * W - 2 * T - 0.04
end

-- How far the base's centre sits behind the blank's front edge (the front
-- wall's inner layer is the front-most panel).
function PizzaBox.trayFromFront(bs: number): number
	return bs / 2 + 2 * W - 0.01
end

local function ease(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Each panel's part CFrame (centre) at `t` seconds into the fold (0 = flat),
-- for a box whose base top-centre is `root`. Parts are width x Thick x length.
function PizzaBox.pose(panels: { Panel }, root: CFrame, t: number): { CFrame }
	local frames: { CFrame } = {} -- each panel's folded frame (origin on its hinge)
	local out: { CFrame } = {}
	for i, p in panels do
		local parent = p.parent
		if not parent then
			frames[i] = root -- the base's children hinge from its centre
			out[i] = root * CFrame.new(0, -T / 2, 0)
		else
			local parentFrame = frames[parent]
			local angle = p.fold * ease((t - p.from) / math.max(p.to - p.from, 1e-3))
			local frame = parentFrame * p.hinge * CFrame.Angles(math.rad(-angle), 0, 0)
			frames[i] = frame
			out[i] = frame * CFrame.new(0, -T / 2, p.length / 2)
		end
	end
	return out
end

-- The panel's part size.
function PizzaBox.size(p: Panel): Vector3
	return Vector3.new(p.width, T, p.length)
end

return PizzaBox
