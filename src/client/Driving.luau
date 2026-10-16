--!strict
-- Arcade handling for delivery cars. The server gives the driver network
-- ownership; while seated we steer with the car's LinearVelocity (planar) and
-- AngularVelocity (yaw only, which also keeps the car upright).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Driving = {}

local player = Players.LocalPlayer
local C = Config.Car

local function drive(seat: VehicleSeat)
	local model = seat.Parent
	local chassis = model and model:FindFirstChild("Chassis") :: BasePart?
	local lv = chassis and chassis:FindFirstChild("Drive") :: LinearVelocity?
	local av = chassis and chassis:FindFirstChild("Steer") :: AngularVelocity?
	if not chassis or not lv or not av then
		return
	end
	local speed = 0
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		if seat.Occupant == nil or not seat.Parent then
			-- Parked: hold still.
			lv.PlaneVelocity = Vector2.zero
			av.AngularVelocity = Vector3.zero
			conn:Disconnect()
			return
		end
		local throttle = seat.ThrottleFloat
		local steer = seat.SteerFloat
		local target = if throttle > 0 then C.MaxSpeed * throttle elseif throttle < 0 then -C.ReverseSpeed else 0
		local rate = if throttle == 0 then C.Accel * 0.6 elseif math.sign(target) ~= math.sign(speed) and speed ~= 0 then C.Brake else C.Accel
		if speed < target then
			speed = math.min(target, speed + rate * dt)
		else
			speed = math.max(target, speed - rate * dt)
		end
		local look = chassis.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			flat = flat.Unit
		end
		lv.PlaneVelocity = Vector2.new(flat.X * speed, flat.Z * speed)
		-- Steering needs some speed (no spinning in place) and flips when reversing.
		local grip = math.clamp(math.abs(speed) / 12, 0, 1) * math.sign(speed)
		av.AngularVelocity = Vector3.new(0, -steer * C.TurnRate * grip, 0)
	end)
end

function Driving.Init()
	local function hook(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then
			return
		end
		humanoid.Seated:Connect(function(active, seatPart)
			if active and seatPart and seatPart:IsA("VehicleSeat") and seatPart:GetAttribute("DeliveryCar") then
				drive(seatPart)
			end
		end)
	end
	if player.Character then
		task.spawn(hook, player.Character)
	end
	player.CharacterAdded:Connect(hook)
end

return Driving
