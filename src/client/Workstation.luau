--!strict
-- Puts the local character at a station: they stand at the counter facing the
-- work, movement is switched off, and the camera moves to a fixed first-person
-- view of the work spot (Config.StationView). The view is the same on every
-- visit, whatever the character's size or where they walked up from. Their own
-- character is hidden locally, so the view shows just the pizza and the tools
-- the minigame draws; anyone else standing at the same spot (a player or
-- hired staff) is hidden too.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local Workstation = {}
Workstation.__index = Workstation

local player = Players.LocalPlayer

export type Workstation = typeof(setmetatable({} :: {
	station: BasePart,
	frame: CFrame, -- upright, centered on the work spot
	toWorker: Vector3, -- flat unit vector from the work spot toward the worker
	right: Vector3, -- worker's right-hand direction
	eye: Vector3, -- where the camera sits (minigames may move it, e.g. closing in on a box)
	focus: Vector3, -- where the camera looks
	fov: number,
	folder: Folder, -- local-only parts while at this station
	_view: any,
	_saved: { eye: Vector3, focus: Vector3, fov: number }?, -- the view to go back to after pushView
	_standAt: Vector3,
	_root: BasePart?,
	_hidden: { [Instance]: boolean }, -- what we hid of our own character
	_others: { [Instance]: { [Instance]: boolean } }, -- other characters at our spot -> what we hid
}, Workstation))

local RENDER_STEP = "PizzaStationCamera"
local savedFov: number? = nil -- the player's own field of view, restored when they leave

-- Latest mouse / touch position in screen space (GUI inset excluded), so the
-- minigames can be played with a finger as well as a mouse.
local pointerAt: Vector2? = nil
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		pointerAt = Vector2.new(input.Position.X, input.Position.Y)
	end
end)
UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		pointerAt = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

-- Ray from the camera through the mouse / last touch.
function Workstation.pointerRay(): Ray
	local camera = workspace.CurrentCamera
	local at = pointerAt
	if not at then
		local inset = GuiService:GetGuiInset()
		at = UserInputService:GetMouseLocation() - inset
	end
	local p = at :: Vector2
	return camera:ScreenPointToRay(p.X, p.Y)
end

-- The default player controls (keyboard, thumbstick, jump button).
local function controls(): any?
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, playerModule = pcall(require, module)
	return if ok and type(playerModule) == "table" then (playerModule :: any):GetControls() else nil
end

-- Hides `model` on this screen only (parts, decals and name tags), noting what
-- it changed in `hidden` so show() can put it back.
local function hide(model: Instance, hidden: { [Instance]: boolean })
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			(d :: any).LocalTransparencyModifier = 1
			hidden[d] = true
		elseif d:IsA("BillboardGui") and d.Enabled then
			d.Enabled = false
			hidden[d] = true
		end
	end
end

local function show(hidden: { [Instance]: boolean })
	for d in hidden do
		if d.Parent then
			if d:IsA("BillboardGui") then
				d.Enabled = true
			else
				(d :: any).LocalTransparencyModifier = 0
			end
		end
	end
	table.clear(hidden)
end

-- Floor height under `at` (collidable parts only), if there is one within reach.
local function floorBelow(at: Vector3, character: Model): number?
	-- Not on anyone's head: other players and hired staff can stand on the same spot.
	local skip: { Instance } = CollectionService:GetTagged("CrewNPC")
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(skip, other.Character)
		end
	end
	table.insert(skip, character)
	table.insert(skip, workspace.CurrentCamera)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = skip
	params.RespectCanCollide = true
	local hit = workspace:Raycast(at, Vector3.new(0, -20, 0), params)
	return if hit then hit.Position.Y else nil
end

-- Undoes everything enter() changed about the player's view and controls.
function Workstation.restore()
	RunService:UnbindFromRenderStep(RENDER_STEP)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	if savedFov then
		camera.FieldOfView = savedFov
		savedFov = nil
	end
	ProximityPromptService.Enabled = true
	local c = controls()
	if c then
		c:Enable()
	end
end

-- Moves the player to `station`. Returns nil if the character isn't usable.
-- Called while already at another station, the camera glides over from there.
function Workstation.enter(station: BasePart): Workstation?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local pizzaAt = station:GetAttribute("PizzaAt")
	if typeof(pizzaAt) ~= "Vector3" then
		pizzaAt = Vector3.new(0, station.Size.Y, -0.5)
	end
	local art = station.CFrame * CFrame.new(0, -station.Size.Y / 2, 0)
	local spot = (art * CFrame.new(pizzaAt :: Vector3)).Position
	local look = art.LookVector
	local toWorker = Vector3.new(look.X, 0, look.Z).Unit
	local right = Vector3.new(0, 1, 0):Cross(toWorker).Unit -- worker faces -toWorker
	local kind = station:GetAttribute("Station")
	local view = Config.StationView[if type(kind) == "string" then kind else ""] or Config.StationView.Default

	local folder = Instance.new("Folder")
	folder.Name = "Workstation"
	folder.Parent = workspace.CurrentCamera

	local self = setmetatable({
		station = station,
		frame = CFrame.lookAt(spot, spot - toWorker),
		toWorker = toWorker,
		right = right,
		eye = spot,
		focus = spot,
		fov = view.fov,
		folder = folder,
		_view = view,
		_standAt = spot,
		_root = root,
		_hidden = {},
		_others = {},
		_saved = nil,
	}, Workstation)
	self:resetView()

	-- Stand on the floor in front of the work spot, facing it.
	local standXZ = spot + toWorker * (view.stand or 1.9)
	local floorY = floorBelow(Vector3.new(standXZ.X, spot.Y + 1, standXZ.Z), character)
	local rootHeight = if humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else humanoid.HipHeight + root.Size.Y / 2
	local standAt = Vector3.new(standXZ.X, if floorY then floorY + rootHeight else root.Position.Y, standXZ.Z)
	self._standAt = standAt
	root.Anchored = true
	root.CFrame = CFrame.lookAt(standAt, standAt - toWorker)

	local camera = workspace.CurrentCamera
	if not savedFov then
		savedFov = camera.FieldOfView
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local current = camera.CFrame
	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, function(dt)
		local k = math.min(1, dt * 8)
		current = current:Lerp(CFrame.lookAt(self.eye, self.focus), k)
		camera.CFrame = current
		camera.FieldOfView += (self.fov - camera.FieldOfView) * k
		-- The pointer has to stay free (zooming into first person locks it to the center).
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		-- Re-applied every frame: Roblox's camera scripts reset it on our own character.
		local char = player.Character
		if char then
			hide(char, self._hidden)
		end
		-- Someone else working the same spot would block the view.
		local others = CollectionService:GetTagged("CrewNPC") -- hired staff (ShopService)
		for _, other in Players:GetPlayers() do
			if other ~= player and other.Character then
				table.insert(others, other.Character)
			end
		end
		for _, otherChar in others do
			local otherRoot = otherChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if otherRoot then
				local near = (otherRoot.Position - self._standAt).Magnitude < 3
				local hiddenParts = self._others[otherChar]
				if near and not hiddenParts then
					local record = {}
					hide(otherChar, record)
					self._others[otherChar] = record
				elseif not near and hiddenParts then
					self._others[otherChar] = nil
					show(hiddenParts)
				end
			end
		end
	end)

	-- Station prompts would float over the work, and nobody should walk off mid-pizza.
	ProximityPromptService.Enabled = false
	local c = controls()
	if c then
		c:Disable()
	end
	return self
end

-- Sets the working view. While something's pushed on top (pushView), this
-- becomes the view popView() returns to instead.
local function setView(self: Workstation, eye: Vector3, focus: Vector3, fov: number)
	if self._saved then
		self._saved = { eye = eye, focus = focus, fov = fov }
	else
		self.eye, self.focus, self.fov = eye, focus, fov
	end
end

-- Back to this station's own view (Config.StationView).
function Workstation.resetView(self: Workstation)
	local v = self._view
	local spot = self.frame.Position
	local side = self.right * (v.side or 0)
	setView(self, spot + self.toWorker * v.back + Vector3.yAxis * v.height + side, spot + self.toWorker * (v.focusBack or 0) + Vector3.yAxis * (v.focusUp or 0) + side, v.fov)
end

-- Looks at something else for a moment (e.g. a job aid card up close); popView()
-- goes back to the working view.
function Workstation.pushView(self: Workstation, eye: Vector3, focus: Vector3, fov: number)
	if not self._saved then
		self._saved = { eye = self.eye, focus = self.focus, fov = self.fov }
	end
	self.eye, self.focus, self.fov = eye, focus, fov
end

function Workstation.popView(self: Workstation)
	local saved = self._saved
	if saved then
		self._saved = nil
		self.eye, self.focus, self.fov = saved.eye, saved.focus, saved.fov
	end
end

function Workstation.viewPushed(self: Workstation): boolean
	return self._saved ~= nil
end

-- The standard close-up working angle (Config.StationView.Default) over `point`.
function Workstation.closeUp(self: Workstation, point: Vector3)
	local v = Config.StationView.Default
	setView(self, point + self.toWorker * v.back + Vector3.yAxis * v.height, point + self.toWorker * (v.focusBack or 0), v.fov)
end

-- Top of the work surface at local (x, z) relative to the work spot (x = worker's right, z = toward worker).
function Workstation.at(self: Workstation, x: number, y: number, z: number): Vector3
	return self.frame.Position + self.right * x + Vector3.new(0, y, 0) + self.toWorker * z
end

-- Where the pointer (mouse / touch) meets the horizontal plane at height `y`
-- above the surface. Returns world position and local (x, z) from the work spot.
function Workstation.pointer(self: Workstation, y: number?): (Vector3?, number, number)
	local ray = Workstation.pointerRay()
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

-- Leaves the station. `switching`: going straight to another station, so keep
-- the camera and controls as they are for the next enter().
function Workstation.leave(self: Workstation, switching: boolean?)
	self.folder:Destroy()
	RunService:UnbindFromRenderStep(RENDER_STEP)
	show(self._hidden)
	for _, record in self._others do
		show(record)
	end
	table.clear(self._others)
	if self._root and self._root.Parent then
		self._root.Anchored = false
	end
	if not switching then
		Workstation.restore()
	end
end

return Workstation
