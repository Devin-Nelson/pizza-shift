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

local function weldPart(chassis: BasePart, props: { [string]: any }, model: Model, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.CFrame = chassis.CFrame * cf
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = chassis
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

local function buildCar(owner: Player, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "DeliveryCar_" .. owner.Name
	local paint = PAINT[math.random(1, #PAINT)]

	-- Chassis: the one physical body. Car forward is -Z.
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(6, 1.6, 11)
	chassis.CFrame = cf * CFrame.new(0, 0.8, 0)
	chassis.Color = paint
	chassis.Material = Enum.Material.SmoothPlastic
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.05, 0, 100, 1)
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.Parent = model
	model.PrimaryPart = chassis

	-- Body
	weldPart(chassis, { Name = "Cabin", Size = Vector3.new(5.6, 1.8, 5.6), Color = paint, CanCollide = true }, model, CFrame.new(0, 1.7, 0.6))
	weldPart(chassis, { Name = "Windshield", Size = Vector3.new(5.2, 1.6, 0.1), Color = Color3.fromRGB(120, 160, 200), Material = Enum.Material.Glass, Transparency = 0.35 }, model, CFrame.new(0, 1.7, -2.25) * CFrame.Angles(math.rad(25), 0, 0))
	weldPart(chassis, { Name = "RearGlass", Size = Vector3.new(5.2, 1.4, 0.1), Color = Color3.fromRGB(120, 160, 200), Material = Enum.Material.Glass, Transparency = 0.35 }, model, CFrame.new(0, 1.7, 3.45))
	for _, sx in { -1, 1 } do
		weldPart(chassis, { Name = "SideGlass", Size = Vector3.new(0.1, 1.3, 4.6), Color = Color3.fromRGB(120, 160, 200), Material = Enum.Material.Glass, Transparency = 0.35 }, model, CFrame.new(sx * 2.82, 1.75, 0.6))
		weldPart(chassis, { Name = "Headlight", Size = Vector3.new(1.0, 0.5, 0.1), Color = Color3.fromRGB(255, 250, 220), Material = Enum.Material.Neon }, model, CFrame.new(sx * 2.2, 0.2, -5.52))
		weldPart(chassis, { Name = "TailLight", Size = Vector3.new(1.0, 0.5, 0.1), Color = Color3.fromRGB(220, 30, 30), Material = Enum.Material.Neon }, model, CFrame.new(sx * 2.2, 0.2, 5.52))
		for _, z in { -3.6, 3.6 } do
			weldPart(chassis, { Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 2.4, 2.4), Color = Color3.fromRGB(25, 25, 25), Material = Enum.Material.Rubber }, model, CFrame.new(sx * 2.9, 0.4, z))
			weldPart(chassis, { Name = "Hubcap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.95, 1.3, 1.3), Color = Color3.fromRGB(180, 180, 185), Material = Enum.Material.Metal }, model, CFrame.new(sx * 2.9, 0.4, z))
		end
	end
	weldPart(chassis, { Name = "Grille", Size = Vector3.new(2.6, 0.6, 0.1), Color = Color3.fromRGB(30, 30, 30) }, model, CFrame.new(0, 0.1, -5.52))
	weldPart(chassis, { Name = "Plate", Size = Vector3.new(1.4, 0.5, 0.05), Color = Color3.new(1, 1, 1) }, model, CFrame.new(0, -0.3, 5.53))

	-- Lit roof topper with the store brand on both sides
	local topper = weldPart(chassis, { Name = "Topper", Size = Vector3.new(0.6, 1.1, 3.2), Color = Config.Brand.Red, Material = Enum.Material.Neon }, model, CFrame.new(0, 3.15, 0.6))
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0
		gui.CanvasSize = Vector2.new(320, 110)
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.fromScale(1, 1)
		tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.FredokaOne
		tl.TextScaled = true
		tl.TextColor3 = Color3.new(1, 1, 1)
		tl.Text = string.upper(Config.GameName)
		tl.Parent = gui
		gui.Parent = topper
	end
	weldPart(chassis, { Name = "TopperBase", Size = Vector3.new(0.8, 0.15, 3.0), Color = Color3.fromRGB(30, 30, 30) }, model, CFrame.new(0, 2.6, 0.6))

	-- Driver seat (a VehicleSeat gives us ThrottleFloat/SteerFloat from any input device)
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.4, 2)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.Massless = true
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = 0 -- we drive with constraints, not the seat's motors
	seat.CFrame = chassis.CFrame * CFrame.new(-1.3, 0.7, 0.9)
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
	lv.MaxForce = 60000
	lv.Parent = chassis
	local av = Instance.new("AngularVelocity")
	av.Name = "Steer"
	av.Attachment0 = attachment
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.AngularVelocity = Vector3.zero
	av.MaxTorque = 1e6
	av.Parent = chassis

	-- Hop-in prompt (only the owner may drive)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Drive"
	pp.ObjectText = "Your delivery car"
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp.Parent = chassis
	pp.Triggered:Connect(function(player)
		if player ~= owner then
			return
		end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and not seat.Occupant then
			seat:Sit(humanoid)
		end
	end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		if occupant and Players:GetPlayerFromCharacter(occupant.Parent) ~= owner then
			-- Someone else hopped in; kick them out.
			local sw = seat:FindFirstChild("SeatWeld")
			if sw then
				sw:Destroy()
			end
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
