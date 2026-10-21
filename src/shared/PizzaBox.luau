--!strict
-- Pizza box blanks for the cut table (the user's reference, 2026-10-21): each
-- die-cut sheet's panels and how they fold. Flat on the cut table's stacks
-- until the pizza on one is cut; then the side walls rise, the front and back
-- walls rise with their corner tabs folding in, the side walls' and the front
-- wall's inner layers fold over the tabs, and the lid (on the back wall)
-- closes with its side flaps and front tuck flap folding down. (Sides, once
-- they're on the menu, go in the Small boxes: the user.)
-- The server lays each stack's top blank flat from these panels (StationArt);
-- the cut minigame folds its own copy (tools/blender/pizzabox.py mirrors this
-- for the stacks; keep the two in step).
--
-- Frames: the root is the base panel's top surface at its centre, +Z toward
-- the back (the lid's hinge), Y up. Each panel hangs off a hinge line (its
-- frame's X axis) and runs along its frame's +Z; folding turns +Z toward +Y
-- (the board's inside face).

local PizzaBox = {}

PizzaBox.Wall = 0.2 -- a pizza box's wall height
PizzaBox.Thick = 0.025 -- the board
PizzaBox.Time = 1.45 -- seconds for the whole fold

-- A box: its base (w across, d front to back) and wall height h.
export type Kind = { w: number, d: number, h: number }

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

local T = PizzaBox.Thick

-- A pizza box `bs` across (Config.BoxSize).
function PizzaBox.pizza(bs: number): Kind
	return { w = bs, d = bs, h = PizzaBox.Wall }
end

local function yaw(deg: number): CFrame
	return CFrame.Angles(0, math.rad(deg), 0)
end

function PizzaBox.panels(k: Kind): { Panel }
	local w, d, h = k.w, k.d, k.h
	local inner = 2 * T -- the tabs sit inside the side walls' inner layers
	local list: { Panel } = {
		{ name = "Base", parent = nil, hinge = CFrame.identity, width = w, length = d, fold = 0, from = 0, to = 0 },
	}
	local function add(p: Panel): number
		table.insert(list, p)
		return #list
	end
	for _, s in { 1, -1 } do
		local side = add({ name = "Side", parent = 1, hinge = CFrame.new(s * w / 2, 0, 0) * yaw(s * 90), width = d, length = h, fold = 90, from = 0, to = 0.3 })
		add({ name = "SideFlap", parent = side, hinge = CFrame.new(0, 0, h), width = d - 0.04, length = h - 0.01, fold = 180, from = 0.55, to = 0.85 })
	end
	local front = add({ name = "Front", parent = 1, hinge = CFrame.new(0, 0, -d / 2) * yaw(180), width = w - 2 * inner, length = h, fold = 90, from = 0.25, to = 0.55 })
	local back = add({ name = "Back", parent = 1, hinge = CFrame.new(0, 0, d / 2), width = w - 2 * inner, length = h, fold = 90, from = 0.25, to = 0.55 })
	for _, wall in { front, back } do
		for _, s in { 1, -1 } do
			-- Corner tabs: they fold in along the side walls (short of the box's middle).
			add({ name = "Tab", parent = wall, hinge = CFrame.new(s * (w / 2 - inner), 0, h / 2) * yaw(s * 90), width = h - 0.04, length = math.min(h - 0.02, d / 2 - 0.03), fold = 90, from = 0.35, to = 0.55 })
		end
	end
	add({ name = "FrontFlap", parent = front, hinge = CFrame.new(0, 0, h), width = w - 0.12, length = h - 0.01, fold = 180, from = 0.6, to = 0.9 })
	local lidLen = d - 2 * T -- it closes inside the front wall
	local lid = add({ name = "Lid", parent = back, hinge = CFrame.new(0, 0, h), width = w + 2 * T, length = lidLen, fold = 90, from = 0.95, to = 1.45 })
	for _, s in { 1, -1 } do
		add({ name = "LidFlap", parent = lid, hinge = CFrame.new(s * (w / 2 + T), 0, lidLen / 2) * yaw(s * 90), width = math.max(d - 0.3, d * 0.6), length = h - 0.03, fold = 90, from = 0.95, to = 1.2 })
	end
	add({ name = "Tuck", parent = lid, hinge = CFrame.new(0, 0, lidLen), width = w - 0.12, length = h - 0.03, fold = 90, from = 1.05, to = 1.35 })
	return list
end

-- The flat blank's width and depth.
function PizzaBox.blankSize(k: Kind): (number, number)
	return k.w + 4 * k.h - 0.02, 2 * k.d + 4 * k.h - 2 * T - 0.04
end

-- How far the base's centre sits behind the blank's front edge.
function PizzaBox.trayFromFront(k: Kind): number
	return k.d / 2 + 2 * k.h - 0.01
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
			local angle = p.fold * ease((t - p.from) / math.max(p.to - p.from, 1e-3))
			local frame = frames[parent] * p.hinge * CFrame.Angles(math.rad(-angle), 0, 0)
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
