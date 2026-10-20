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
	-- tools/blender/stretch_table.py (2026-10-20)
	StretchTable = {
		model = 77149469623185,
		meshes = {
			Steel = { id = 92512823316766, size = Vector3.new(12.7, 3.85, 4.47), at = Vector3.new(0, 1.925, -0.035) },
			Rubber = { id = 72861686830050, size = Vector3.new(10.565, 0.16, 3.15), at = Vector3.new(-0.6025, 0.08, 0.1) },
			Dollies = { id = 88400879921150, size = Vector3.new(7.11, 0.17, 3.41), at = Vector3.new(-2.5, 0.265, 0.1) },
			Bin = { id = 136433825176172, size = Vector3.new(2.24, 2.48, 3.12), at = Vector3.new(3.8, 1.46, -0.01) },
			Tray = { id = 133768002011497, size = Vector3.new(2.2667, 0.4041, 3.29), at = Vector3.new(0, 0.173, 0) },
			Ball1 = { id = 104129538787063, size = Vector3.new(0.9893, 0.373, 1.0049), at = Vector3.new(0.001, 0.1865, 0.0033) },
			Ball2 = { id = 118550023057615, size = Vector3.new(1.0136, 0.3733, 0.9862), at = Vector3.new(0.0025, 0.1866, -0.0055) },
			Ball3 = { id = 124849948995047, size = Vector3.new(0.993, 0.3704, 1.0081), at = Vector3.new(0.0046, 0.1852, -0.0005) },
		},
		images = { Dust = 136882393122317 }, -- cornmeal_dust.png
	},
}

return MeshBank
