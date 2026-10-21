--!strict
-- Station meshes modelled in Blender (tools/blender/<station>.py), uploaded as
-- one Model per station. `id` is the inner Mesh asset of each MeshPart in that
-- Model (AssetService:CreateMeshPartAsync needs it, not the Model's id); `size`
-- and `at` (its bounding-box centre, art-local, worker at -Z) come from the
-- script's <station>.json. Instanced meshes (trays, balls) are built at the
-- origin and placed by StationArt. `images` are Image assets (never Decals).

export type Mesh = { id: number, size: Vector3, at: Vector3 }
export type Station = { model: number, meshes: { [string]: Mesh }, images: { [string]: number } }

local MeshBank: { [string]: Station } = {
	-- tools/blender/stretch_table.py (2026-10-20, v2: its edge and splash mitred to the sauce corner)
	StretchTable = {
		model = 102903462893601,
		meshes = {
			Steel = { id = 122874590212438, size = Vector3.new(12.7277, 3.85, 4.47), at = Vector3.new(0.0138, 1.925, -0.035) },
			Rubber = { id = 72861686830050, size = Vector3.new(10.565, 0.16, 3.15), at = Vector3.new(-0.6025, 0.08, 0.1) },
			Dollies = { id = 88400879921150, size = Vector3.new(7.11, 0.17, 3.41), at = Vector3.new(-2.5, 0.265, 0.1) },
			Bin = { id = 136433825176172, size = Vector3.new(2.24, 2.48, 3.12), at = Vector3.new(3.8, 1.46, -0.01) },
			Tray = { id = 126610142674011, size = Vector3.new(2.2667, 0.4041, 3.29), at = Vector3.new(0, 0.173, 0) },
			Ball1 = { id = 84469288388921, size = Vector3.new(0.9893, 0.373, 1.0049), at = Vector3.new(0.001, 0.1865, 0.0033) },
			Ball2 = { id = 101221130902483, size = Vector3.new(1.0136, 0.3733, 0.9862), at = Vector3.new(0.0025, 0.1866, -0.0055) },
			Ball3 = { id = 88324986857931, size = Vector3.new(0.993, 0.3704, 1.0081), at = Vector3.new(0.0046, 0.1852, -0.0005) },
		},
		images = { Dust = 136882393122317 }, -- cornmeal_dust.png
	},
	-- tools/blender/sauce_table.py (2026-10-20): the corner and sauce tables, racks,
	-- tub, sauce; Screen, Spoodle and SpoodleGrip are instanced (built at the origin).
	SauceTable = {
		model = 100034173372479,
		meshes = {
			Steel = { id = 85050565124219, size = Vector3.new(11.0, 4.5442, 5.7553), at = Vector3.new(-2.6681, 2.2721, -0.5277) },
			Rubber = { id = 136148209806681, size = Vector3.new(4.5036, 0.03, 4.6131), at = Vector3.new(-4.4989, 3.415, -1.5669) },
			Racks = { id = 94977680343123, size = Vector3.new(4.3988, 3.7999, 4.5059), at = Vector3.new(-4.4989, 5.3, -1.5669) },
			Tubs = { id = 119147149478954, size = Vector3.new(1.68, 1.15, 1.68), at = Vector3.new(1.9819, 3.975, 1.44) },
			Sauce = { id = 91356831210512, size = Vector3.new(2.7551, 1.0174, 3.963), at = Vector3.new(1.3981, 3.9127, 0.2535) },
			Grips = { id = 93925145203382, size = Vector3.new(0.3865, 0.4042, 0.783), at = Vector3.new(2.3498, 4.6855, 0.446) },
			Screen = { id = 106073527826474, size = Vector3.new(1, 0.032, 1), at = Vector3.new(0, 0.004, 0) },
			Spoodle = { id = 82826663149747, size = Vector3.new(0.552, 0.3678, 1.3682), at = Vector3.new(0, 0.0989, -0.4081) },
			SpoodleGrip = { id = 125920579067167, size = Vector3.new(0.17, 0.2229, 0.8599), at = Vector3.new(0, 0.3287, -1.5082) },
		},
		images = { Screen = 92132235698139 }, -- screen_mesh.png
	},
	-- tools/blender/makeline.py (2026-10-20, v2: four sections long, the sides at
	-- the end of the rail; v3 2026-10-21: the canopy level): the rail in the user's order (cheese, pepperoni,
	-- two-pan columns, pasta, wings, SuperCakes); each Food_<x> becomes Pan_<x>.
	MakeLine = {
		model = 104204682244129,
		meshes = {
			Steel = { id = 119201090410040, size = Vector3.new(13.6, 4.47, 4.805), at = Vector3.new(0, 2.635, 0.4975) },
			Dark = { id = 139564250463947, size = Vector3.new(13.5, 3.22, 4.61), at = Vector3.new(0, 1.61, 0.595) },
			Pans = { id = 78898056674307, size = Vector3.new(13.0236, 0.3494, 1.1799), at = Vector3.new(-0.015, 3.4903, 1.85) },
			Food_Cheese = { id = 80526987556222, size = Vector3.new(3.1711, 0.121, 1.0211), at = Vector3.new(-4.875, 3.583, 1.85) },
			Food_Pepperoni = { id = 134360942290783, size = Vector3.new(0.9541, 0.1367, 1.0182), at = Vector3.new(-2.6721, 3.5855, 1.85) },
			Food_Ham = { id = 95961204783689, size = Vector3.new(0.9488, 0.1184, 0.4545), at = Vector3.new(-1.58, 3.5751, 1.5695) },
			Food_Pineapple = { id = 98352388310135, size = Vector3.new(0.9488, 0.1252, 0.4454), at = Vector3.new(-1.58, 3.5693, 2.135) },
			Food_Peppers = { id = 136849721956291, size = Vector3.new(0.9488, 0.1011, 0.4454), at = Vector3.new(-0.4867, 3.5647, 1.565) },
			Food_Mushrooms = { id = 134110855147219, size = Vector3.new(0.9488, 0.135, 0.4454), at = Vector3.new(0.6067, 3.5666, 1.565) },
			Food_Olives = { id = 101154435965875, size = Vector3.new(0.9502, 0.0989, 0.4468), at = Vector3.new(0.6067, 3.5709, 2.135) },
			Food_Onions = { id = 134488195753543, size = Vector3.new(0.9488, 0.1166, 0.4454), at = Vector3.new(-0.4867, 3.5648, 2.135) },
			Food_Chicken = { id = 128491866423818, size = Vector3.new(0.9488, 0.1374, 0.4454), at = Vector3.new(1.7, 3.5682, 2.135) },
			Food_Sausage = { id = 107782271686167, size = Vector3.new(0.9488, 0.1158, 0.4454), at = Vector3.new(1.7, 3.5622, 1.565) },
			Food_Pasta = { id = 87562673718788, size = Vector3.new(1.2732, 0.1632, 1.0189), at = Vector3.new(2.9556, 3.5683, 1.8517) },
			Food_Wings = { id = 136504995861624, size = Vector3.new(1.2535, 0.2582, 0.9958), at = Vector3.new(4.3733, 3.5169, 1.85) },
			Food_SuperCakes = { id = 93512345599977, size = Vector3.new(1.0223, 0.29, 0.9223), at = Vector3.new(5.7911, 3.495, 1.85) },
		},
		images = {},
	},
	-- tools/blender/ready_rack.py (2026-10-20): the 15-screen rack (the sauce
	-- corner's) on a square table at the makeline's end.
	ReadyRack = {
		model = 122219228222871,
		meshes = {
			Steel = { id = 96352011086121, size = Vector3.new(4.7, 3.85, 4.77), at = Vector3.new(0, 1.925, -0.035) },
			Rubber = { id = 96085232879241, size = Vector3.new(1.9, 0.03, 2.05), at = Vector3.new(0, 3.415, 0.89) },
			Racks = { id = 136438712389020, size = Vector3.new(1.86, 4.8499, 2), at = Vector3.new(0, 5.825, 0.89) },
		},
		images = {},
	},
	-- tools/blender/cut_table.py (2026-10-21): the cut table from the user's photos (the
	-- stacks' blanks die-cut as src/shared/PizzaBox.luau);
	-- Rocker and RockerGrips are instanced (built standing, the edge's lowest point at the origin).
	CutTable = {
		model = 113387716064926,
		meshes = {
			Steel = { id = 129861066340300, size = Vector3.new(12.86, 3.0786, 6.37), at = Vector3.new(0, 1.6727, 0.005) },
			Dark = { id = 93063948607148, size = Vector3.new(12.74, 0.3939, 6.54), at = Vector3.new(0, 0.2, 0.05) },
			Cardboard = { id = 71873887434317, size = Vector3.new(10.24, 0.62, 3), at = Vector3.new(-0.32, 0.93, 0) },
			Blanks = { id = 122600154019553, size = Vector3.new(11.0872, 1.996, 5.8826), at = Vector3.new(0.6669, 2.77, -0.0159) },
			Bottles = { id = 127042004448027, size = Vector3.new(0.2535, 0.61, 0.26), at = Vector3.new(2.1121, 3.205, 2.5943) },
			Caps = { id = 82427795308953, size = Vector3.new(0.8292, 0.33, 0.27), at = Vector3.new(1.7451, 3.485, 2.5943) },
			Shakers = { id = 103106550156809, size = Vector3.new(0.5535, 0.42, 0.26), at = Vector3.new(1.6121, 3.11, 2.5943) },
			Trash = { id = 99931970717427, size = Vector3.new(1.44, 2.24, 1.3804), at = Vector3.new(0, 1.12, 4.05) },
			Rocker = { id = 107227853656891, size = Vector3.new(3.4, 0.625, 0.206), at = Vector3.new(0, 0.3125, 0) },
			RockerGrips = { id = 133911230277363, size = Vector3.new(3.52, 0.17, 0.19), at = Vector3.new(0, 0.595, 0) },
		},
		images = {},
	},
	-- tools/blender/ovens.py (2026-10-21): the three stacked ovens after the user's photo,
	-- the hood with its baffle filters, the painted enclosure (its colour is StationArt's);
	-- Pulley is instanced (built at the origin, its axle along X).
	Oven = {
		model = 132569644728161,
		meshes = {
			Body = { id = 114550878824710, size = Vector3.new(6.97, 6.59, 10.36), at = Vector3.new(-0.185, 3.415, 0) },
			Paint = { id = 78898037468960, size = Vector3.new(7.1, 12.99, 13.0), at = Vector3.new(0, 7.505, 0) },
			Conveyor = { id = 104332557373788, size = Vector3.new(6.0, 4.07, 14.185), at = Vector3.new(0, 3.165, -0.2925) },
			Hood = { id = 112995817288106, size = Vector3.new(7.86, 1.3, 13.96), at = Vector3.new(0, 7.3, 0) },
			Filters = { id = 97551212368341, size = Vector3.new(7.46, 0.7434, 10.3846), at = Vector3.new(0, 7.05, 0) },
			Dark = { id = 103380927038690, size = Vector3.new(7.36, 6.4333, 13.02), at = Vector3.new(0, 4.1467, 0) },
			Glass = { id = 75667401908642, size = Vector3.new(0.03, 4.45, 4.8), at = Vector3.new(-3.29, 3.625, 0) },
			Labels = { id = 108478829086854, size = Vector3.new(0.01, 3.96, 0.24), at = Vector3.new(-3.355, 4.52, 3.425) },
			Rubber = { id = 104563609693623, size = Vector3.new(5.98, 0.24, 9.8), at = Vector3.new(0, 0.12, 0.04) },
			Pulley = { id = 70983269327279, size = Vector3.new(5.98, 0.264, 0.264), at = Vector3.new(0, 0, 0) },
		},
		images = { Belt = 100820296560923 }, -- belt_mesh.png
	},
}

return MeshBank
