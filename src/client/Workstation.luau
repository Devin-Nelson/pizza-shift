--!strict
-- Puts the local character "at" a station for a 3D minigame: stands them at
-- the counter facing the work surface and switches to a first-person camera.
-- The character's head, arms and hands are hidden locally, so the view shows
-- just the pizza and the tools (ladle, rocker blade...) the minigame draws.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Workstation = {}
Workstation.__index = Workstation

local player = Players.LocalPlayer

export type Workstation = typeof(setmetatable({} :: {
	frame: CFrame, -- upright, centered on the pizza spot at the work surface
	focus: Vector3, -- where the first-person camera looks
	toWorker: Vector3, -- flat unit vector from the surface toward the worker
	right: Vector3, -- worker's right-hand direction
	folder: Folder, -- local-only parts for this minigame
	_conns: { RBXScriptConnection },
	_root: BasePart?,
	_fov: number,
	_hidden: { [Instance]: boolean },
}, Workstation))

local RENDER_STEP = "PizzaMinigameCamera"
-- Body parts hidden in first person (plus anything worn on them).
local HIDDEN_PARTS = {
	Head = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
}

local function hiddenInFirstPerson(d: Instance): boolean
	if d:FindFirstAncestorOfClass("Accessory") or d:FindFirstAncestor("UniformCap") then
		return true
	end
	-- Walk up to the body part directly under the character model.
	local p: Instance? = d
	while p and p.Parent and not p.Parent:IsA("Model") do
		p = p.Parent
	end
	return p ~= nil and HIDDEN_PARTS[p.Name] == true
end

-- Enters the station. Returns nil if the character/station isn't usable.
-- `view`: nil = first person at normal zoom; "wide" = first person with a
-- wider field of view (for long stations like the cut table, where the
-- camera also turns between the oven exit and the boxes).
function Workstation.enter(station: BasePart, view: string?): Workstation?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		return nil
	end
	local pizzaAt = station:GetAttribute("PizzaAt")
	if typeof(pizzaAt) ~= "Vector3" then
		pizzaAt = Vector3.new(0, station.Size.Y, -0.5)
	end
	local art = station.CFrame * CFrame.new(0, -station.Size.Y / 2, 0)
	local surface = (art * CFrame.new(pizzaAt :: Vector3)).Position
	local look = art.LookVector
	local toWorker = Vector3.new(look.X, 0, look.Z).Unit
	local right = Vector3.new(0, 1, 0):Cross(toWorker).Unit -- worker faces -toWorker

	local folder = Instance.new("Folder")
	folder.Name = "Workstation"
	folder.Parent = workspace.CurrentCamera

	local camera = workspace.CurrentCamera
	local self = setmetatable({
		frame = CFrame.lookAt(surface, surface - toWorker),
		focus = surface + Vector3.new(0, 0.1, 0),
		toWorker = toWorker,
		right = right,
		folder = folder,
		_conns = {},
		_root = root,
		_fov = camera.FieldOfView,
		_hidden = {},
	}, Workstation)

	-- Stand at the counter, facing the work.
	local standAt = Vector3.new(surface.X, root.Position.Y, surface.Z) + toWorker * 1.9
	root.Anchored = true
	root.CFrame = CFrame.lookAt(standAt, Vector3.new(surface.X, standAt.Y, surface.Z))

	-- First person: the camera sits at the character's eyes and looks at
	-- `focus` (the work by default; minigames can move it, e.g. to the oven exit).
	camera.CameraType = Enum.CameraType.Scriptable
	local head = character:FindFirstChild("Head") :: BasePart?
	local eye = (if head then head.Position else standAt + Vector3.new(0, 1.5, 0)) + Vector3.new(0, 0.1, 0) - toWorker * 0.25
	TweenService:Create(camera, TweenInfo.new(0.35), { FieldOfView = if view == "wide" then 80 else 70 }):Play()
	local current = camera.CFrame
	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, function(dt)
		current = current:Lerp(CFrame.lookAt(eye, self.focus), math.min(1, dt * 8))
		camera.CFrame = current
		-- Re-applied every frame: Roblox's camera scripts reset this property.
		local char = player.Character
		if char then
			for _, d in char:GetDescendants() do
				if (d:IsA("BasePart") or d:IsA("Decal")) and hiddenInFirstPerson(d) then
					(d :: any).LocalTransparencyModifier = 1
					self._hidden[d] = true
				end
			end
		end
	end)

	-- Station prompts would float over the work; hide them while we're busy.
	ProximityPromptService.Enabled = false
	return self
end

-- Top of the work surface at local (x, z) relative to the pizza spot (x = worker's right, z = toward worker).
function Workstation.at(self: Workstation, x: number, y: number, z: number): Vector3
	return self.frame.Position + self.right * x + Vector3.new(0, y, 0) + self.toWorker * z
end

-- Where the pointer (mouse / touch) meets the horizontal plane at height `y`
-- above the surface. Returns world position and local (x, z) from the pizza spot.
function Workstation.pointer(self: Workstation, y: number?): (Vector3?, number, number)
	local camera = workspace.CurrentCamera
	local m = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(m.X, m.Y)
	local planeY = self.frame.Position.Y + (y or 0)
	if math.abs(ray.Direction.Y) < 1e-4 then
		return nil, 0, 0
	end
	local t = (planeY - ray.Origin.Y) / ray.Direction.Y
	if t < 0 then
		return nil, 0, 0
	end
	local hit = ray.Origin + ray.Direction * t
	local offset = hit - self.frame.Position
	return hit, offset:Dot(self.right), offset:Dot(self.toWorker)
end

function Workstation.track(self: Workstation, conn: RBXScriptConnection)
	table.insert(self._conns, conn)
end

function Workstation.leave(self: Workstation)
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
	self.folder:Destroy()
	RunService:UnbindFromRenderStep(RENDER_STEP)
	for d in self._hidden do
		if d.Parent then
			(d :: any).LocalTransparencyModifier = 0
		end
	end
	if self._root and self._root.Parent then
		self._root.Anchored = false
	end
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = self._fov
	ProximityPromptService.Enabled = true
end

return Workstation
