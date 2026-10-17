--!strict
-- Delivery cars. Each driver gets their own car (drivers use their own cars,
-- with a lit roof topper) parked in their store's lot. Physics is owned by the
-- driver's client (see client/Driving.luau), which drives it with a planar
-- LinearVelocity + an AngularVelocity that also keeps it upright.

local Players = game:GetService("Players")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local CarService = {}

type CarInfo = { model: Model, shopModel: Model }
local cars: { [Player]: CarInfo } = {}

local PAINT = {
	Color3.fromRGB(200, 200, 205),
	Color3.fromRGB(30, 30, 35),
	Color3.fromRGB(150, 25, 30),
	Color3.fromRGB(30, 70, 140),
	Color3.fromRGB(235, 235, 235),
	Color3.fromRGB(90, 110, 90),
}

local function carsFolder(): Folder
	local folder = workspace:FindFirstChild("Cars")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Cars"
		folder.Parent = workspace
	end
	return folder :: Folder
end

-- A body part welded to the chassis at world CFrame `cf`. Detail parts are
-- massless and don't collide unless `props` says so.
local function weldPart(chassis: BasePart, props: { [string]: any }, model: Model, cf: CFrame): BasePart
	local p: BasePart = Instance.new(props.ClassName or "Part") :: any
	p.Anchored = false
	p.CanCollide = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	if props.Shape then
		(p :: any).Shape = props.Shape -- before Size: changing Shape can resize the part
	end
	for k, v in props do
		if k ~= "ClassName" and k ~= "Shape" then
			(p :: any)[k] = v
		end
	end
	p.CFrame = cf
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = chassis
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

-- The brand name across `face`, `height` (0-1) of the face tall, centered.
local function brandText(part: BasePart, face: Enum.NormalId, color: Color3, canvas: Vector2, height: number)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0
	gui.CanvasSize = canvas
	local tl = Instance.new("TextLabel")
	tl.AnchorPoint = Vector2.new(0.5, 0.5)
	tl.Position = UDim2.fromScale(0.5, 0.5)
	tl.Size = UDim2.fromScale(0.9, height)
	tl.BackgroundTransparency = 1
	tl.Font = Enum.Font.FredokaOne
	tl.TextScaled = true
	tl.TextColor3 = color
	tl.Text = string.upper(Config.GameName)
	tl.Parent = gui
	gui.Parent = part
end

local GLASS = Color3.fromRGB(150, 185, 215)
local TRIM = Color3.fromRGB(30, 30, 34)
local UPHOLSTERY = Color3.fromRGB(48, 48, 54)
-- Windshield and rear window slopes (degrees from vertical).
local WINDSHIELD = math.rad(37.5)
local REAR_WINDOW = math.rad(-29.5)

-- Car layout, in studs: origin on the ground under the car's center, forward
-- is -Z, the driver sits on the left (-X). It's sized for Roblox characters:
-- a seated R15/R6 player fits inside without clipping (floor at 1.3, seat top
-- at 2.4, roof underside at 6.4; seated heads, hair included, top out around 6.2;
-- doors 2.0 out from the driver's centerline). Only the lower body, bumpers and wheels
-- collide; the welded wheels are low-friction skids (the client drives the car
-- with constraints, so they don't need to turn).
local function buildCar(owner: Player, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "DeliveryCar_" .. owner.Name
	local paint = PAINT[math.random(1, #PAINT)]
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	-- Chassis: the floor pan and the one heavy part. Everything else is welded on.
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(7.6, 0.5, 15)
	chassis.CFrame = at(0, 1.05, 0)
	chassis.Color = TRIM
	chassis.Material = Enum.Material.SmoothPlastic
	chassis.CustomPhysicalProperties = PhysicalProperties.new(1.5, 0, 0, 100, 1)
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.Parent = model
	model.PrimaryPart = chassis
	local function add(props: { [string]: any }, where: CFrame): BasePart
		return weldPart(chassis, props, model, where)
	end

	-- Lower body (solid): hood, trunk, doors, bumpers
	add({ Name = "Hood", Size = Vector3.new(7.8, 2.0, 4.2), Color = paint, CanCollide = true }, at(0, 2.3, -5.9))
	add({ Name = "Trunk", Size = Vector3.new(7.8, 2.0, 4.2), Color = paint, CanCollide = true }, at(0, 2.3, 5.9))
	for _, z in { -8.15, 8.15 } do
		add({ Name = "Bumper", Size = Vector3.new(8.0, 0.55, 0.4), Color = TRIM, CanCollide = true }, at(0, 1.55, z))
	end
	for _, sx in { -1, 1 } do
		local door = add({ Name = "Door", Size = Vector3.new(0.2, 2.4, 7.6), Color = paint, CanCollide = true }, at(sx * 3.8, 2.2, 0))
		brandText(door, if sx < 0 then Enum.NormalId.Left else Enum.NormalId.Right, Config.Brand.Red, Vector2.new(380, 120), 0.4)
	end

	-- Cabin: windshield, pillars, side and rear glass, roof (none of it collides)
	local function glassProps(name: string, size: Vector3, class: string?): { [string]: any }
		return { Name = name, Size = size, Color = GLASS, Transparency = 0.55, ClassName = class }
	end
	add(glassProps("Windshield", Vector3.new(7.4, 3.78, 0.1)), at(0, 4.9, -2.65) * CFrame.Angles(WINDSHIELD, 0, 0))
	add(glassProps("RearGlass", Vector3.new(7.4, 3.45, 0.1)), at(0, 4.9, 4.75) * CFrame.Angles(REAR_WINDOW, 0, 0))
	add({ Name = "Roof", Size = Vector3.new(7.8, 0.3, 5.6), Color = paint }, at(0, 6.55, 1.15))
	add({ Name = "Dash", Size = Vector3.new(7.4, 0.9, 0.9), Color = TRIM }, at(0, 3.0, -3.35))
	for _, sx in { -1, 1 } do
		local x = sx * 3.8
		add({ Name = "APillar", Size = Vector3.new(0.25, 3.78, 0.25), Color = paint }, at(x, 4.9, -2.65) * CFrame.Angles(WINDSHIELD, 0, 0))
		add({ Name = "BPillar", Size = Vector3.new(0.28, 3.0, 0.35), Color = paint }, at(x, 4.9, 1.9))
		-- A wedge's tall end is +Z and it slopes down toward -Z, like the windshield.
		add(glassProps("QuarterGlass", Vector3.new(0.1, 3.0, 2.3), "WedgePart"), at(x, 4.9, -2.65))
		add(glassProps("SideGlass", Vector3.new(0.1, 3.0, 5.4)), at(x, 4.9, 1.2))
		-- Rear pillar slopes the other way (tall at the front).
		add({ Name = "CPillar", ClassName = "WedgePart", Size = Vector3.new(0.12, 3.0, 1.7), Color = paint }, at(x, 4.9, 4.75) * CFrame.Angles(0, math.pi, 0))
		add({ Name = "Headlight", Size = Vector3.new(1.3, 0.5, 0.1), Color = Color3.fromRGB(255, 250, 220), Material = Enum.Material.Neon }, at(sx * 2.6, 2.7, -8.03))
		add({ Name = "TailLight", Size = Vector3.new(1.3, 0.5, 0.1), Color = Color3.fromRGB(220, 30, 30), Material = Enum.Material.Neon }, at(sx * 2.6, 2.7, 8.03))
		for _, z in { -5.3, 5.3 } do
			add({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 2.6, 2.6), Color = Color3.fromRGB(25, 25, 25), Material = Enum.Material.Rubber, CanCollide = true, CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1) }, at(sx * 3.55, 1.3, z))
			add({ Name = "Hubcap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.95, 1.4, 1.4), Color = Color3.fromRGB(180, 180, 185), Material = Enum.Material.Metal }, at(sx * 3.55, 1.3, z))
		end
	end
	add({ Name = "Grille", Size = Vector3.new(3.2, 0.7, 0.1), Color = TRIM }, at(0, 2.5, -8.03))
	add({ Name = "Plate", Size = Vector3.new(1.4, 0.5, 0.05), Color = Color3.new(1, 1, 1) }, at(0, 2.2, 8.03))

	-- Interior: front seats, rear bench, steering wheel
	for _, sx in { -1, 1 } do
		if sx > 0 then
			add({ Name = "PassengerSeat", Size = Vector3.new(2.4, 0.5, 2.2), Color = UPHOLSTERY, Material = Enum.Material.Fabric }, at(1.6, 2.15, 0.6))
		end
		add({ Name = "SeatBack", Size = Vector3.new(2.4, 2.6, 0.45), Color = UPHOLSTERY, Material = Enum.Material.Fabric }, at(sx * 1.6, 3.6, 1.85) * CFrame.Angles(math.rad(10), 0, 0))
		add({ Name = "Headrest", Size = Vector3.new(1.4, 0.7, 0.4), Color = UPHOLSTERY, Material = Enum.Material.Fabric }, at(sx * 1.6, 5.15, 2.1))
	end
	add({ Name = "RearBench", Size = Vector3.new(7.2, 0.5, 1.4), Color = UPHOLSTERY, Material = Enum.Material.Fabric }, at(0, 2.15, 3.1))
	local column = Vector3.new(0, math.sin(math.rad(25)), math.cos(math.rad(25))) -- toward the driver, tilted up
	local wheelAt = at(-1.6, 3.65, -2.05).Position
	add({ Name = "SteeringWheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 1.5, 1.5), Color = TRIM }, CFrame.fromMatrix(wheelAt, cf:VectorToWorldSpace(column), cf.RightVector))
	add({ Name = "SteeringColumn", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.3, 0.22, 0.22), Color = TRIM }, CFrame.fromMatrix(wheelAt - cf:VectorToWorldSpace(column) * 0.7, cf:VectorToWorldSpace(column), cf.RightVector))

	-- Lit roof topper with the store brand on both sides
	add({ Name = "TopperBase", Size = Vector3.new(0.8, 0.15, 3.0), Color = TRIM }, at(0, 6.775, 1.15))
	local topper = add({ Name = "Topper", Size = Vector3.new(0.6, 1.1, 3.2), Color = Config.Brand.Red, Material = Enum.Material.Neon }, at(0, 7.4, 1.15))
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		brandText(topper, face, Color3.new(1, 1, 1), Vector2.new(320, 110), 1)
	end

	-- Driver's seat: the cushion itself. A VehicleSeat gives us ThrottleFloat /
	-- SteerFloat from any input device; seated, the character faces forward.
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2.4, 0.5, 2.2)
	seat.Color = UPHOLSTERY
	seat.Material = Enum.Material.Fabric
	seat.CanCollide = false
	seat.Massless = true
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = 0 -- we drive with constraints, not the seat's motors
	seat.CFrame = at(-1.6, 2.15, 0.6)
	seat:SetAttribute("DeliveryCar", true)
	seat:SetAttribute("Owner", owner.UserId)
	local seatWeld = Instance.new("WeldConstraint")
	seatWeld.Part0 = chassis
	seatWeld.Part1 = seat
	seatWeld.Parent = seat
	seat.Parent = model

	-- Drive constraints
	local attachment = Instance.new("Attachment")
	attachment.Name = "Drive"
	attachment.Parent = chassis
	local lv = Instance.new("LinearVelocity")
	lv.Name = "Drive"
	lv.Attachment0 = attachment
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	lv.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	lv.PlaneVelocity = Vector2.zero
	lv.MaxForce = 80000
	lv.Parent = chassis
	local av = Instance.new("AngularVelocity")
	av.Name = "Steer"
	av.Attachment0 = attachment
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.AngularVelocity = Vector3.zero
	av.MaxTorque = 1e6
	av.Parent = chassis

	-- Hop-in prompt at the driver's door (only the owner sees it or may drive).
	local door = Instance.new("Attachment")
	door.Name = "DriverDoor"
	door.Parent = chassis
	door.WorldCFrame = at(-4.4, 3.0, 0.4)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Drive"
	pp.ObjectText = "Your delivery car"
	pp.MaxActivationDistance = 10
	pp.RequiresLineOfSight = false
	pp:SetAttribute("CarOwner", owner.UserId)
	pp.Parent = door
	pp.Triggered:Connect(function(player)
		if player ~= owner or seat.Occupant then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not humanoid or not root or humanoid.Health <= 0 or humanoid.SeatPart then
			return
		end
		root.Anchored = false
		-- Line up over the seat first so sitting doesn't drag them through the door.
		character:PivotTo(seat.CFrame * CFrame.new(0, 1.8, 0))
		seat:Sit(humanoid)
	end)
	local driver: Humanoid? = nil
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		if occupant then
			if Players:GetPlayerFromCharacter(occupant.Parent) ~= owner then
				-- Someone else hopped in; kick them out.
				local sw = seat:FindFirstChild("SeatWeld")
				if sw then
					sw:Destroy()
				end
				return
			end
			driver = occupant
		elseif driver then
			-- Hopped out (jump): step out beside the driver's door rather than
			-- popping up inside the cabin.
			local character = driver.Parent
			driver = nil
			task.defer(function()
				if character and character:IsA("Model") and character.Parent and model.Parent then
					character:PivotTo(seat.CFrame * CFrame.new(-3.9, 1.5, 0))
				end
			end)
		end
	end)

	model.Parent = carsFolder()
	pcall(function()
		chassis:SetNetworkOwner(owner)
	end)
	return model
end

local function freeParking(shopModel: Model): CFrame
	local spots = shopModel:FindFirstChild("Spots")
	local candidates = {}
	if spots then
		for i = 1, 8 do
			local s = spots:FindFirstChild("Parking" .. i) :: BasePart?
			if s then
				table.insert(candidates, s)
			end
		end
	end
	for _, s in candidates do
		local taken = false
		for _, info in cars do
			if info.model.PrimaryPart and (info.model.PrimaryPart.Position - s.Position).Magnitude < 5 then
				taken = true
				break
			end
		end
		if not taken then
			return CFrame.new(s.Position.X, shopModel:GetPivot().Position.Y, s.Position.Z) * (s.CFrame - s.CFrame.Position)
		end
	end
	local fallback = candidates[1]
	return if fallback then fallback.CFrame * CFrame.new(0, -2, 0) else shopModel:GetPivot() * CFrame.new(0, 0, -45)
end

-- Makes sure the driver has a car near their store. Returns it.
function CarService.Ensure(player: Player, shopModel: Model): Model
	local info = cars[player]
	if info and info.model.Parent and info.shopModel == shopModel and info.model.PrimaryPart then
		local dist = (info.model.PrimaryPart.Position - shopModel:GetPivot().Position).Magnitude
		local seat = info.model:FindFirstChild("DriverSeat") :: VehicleSeat?
		if dist < 150 or (seat and seat.Occupant) then
			return info.model
		end
	end
	CarService.Release(player)
	local model = buildCar(player, freeParking(shopModel))
	cars[player] = { model = model, shopModel = shopModel }
	return model
end

function CarService.Release(player: Player)
	local info = cars[player]
	if info then
		cars[player] = nil
		info.model:Destroy()
	end
end

function CarService.Init()
	Players.PlayerRemoving:Connect(CarService.Release)
	-- Clean up cars that end up in the void.
	task.spawn(function()
		while true do
			task.wait(5)
			for player, info in cars do
				local chassis = info.model.PrimaryPart
				if not chassis or chassis.Position.Y < -50 then
					CarService.Release(player)
				end
			end
		end
	end)
end

return CarService
