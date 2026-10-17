--!strict
-- Arcade handling for delivery cars. The server gives the driver network
-- ownership; while we're in the driver's seat we steer with the car's
-- LinearVelocity (planar) and AngularVelocity (yaw only, which also keeps the
-- car upright).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Driving = {}

local player = Players.LocalPlayer
local C = Config.Car

-- Raw move input (WASD / arrows, gamepad stick, mobile thumbstick), as a
-- fallback for when the seat's own throttle/steer aren't coming through.
local function moveInput(): Vector3
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if module and module:IsA("ModuleScript") then
		local ok, controls = pcall(function()
			return (require(module) :: any):GetControls()
		end)
		if ok and controls then
			return controls:GetMoveVector()
		end
	end
	return Vector3.zero
end

local function drive(humanoid: Humanoid, seat: VehicleSeat)
	local model = seat.Parent
	local chassis = model and model:FindFirstChild("Chassis") :: BasePart?
	local lv = chassis and chassis:FindFirstChild("Drive") :: LinearVelocity?
	local av = chassis and chassis:FindFirstChild("Steer") :: AngularVelocity?
	if not chassis or not lv or not av then
		return
	end
	local speed = 0
	local satAt = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		-- Follow the humanoid, not seat.Occupant: Occupant can arrive a frame late.
		if humanoid.SeatPart ~= seat or not seat.Parent or humanoid.Health <= 0 then
			-- Parked: hold still.
			lv.PlaneVelocity = Vector2.zero
			av.AngularVelocity = Vector3.zero
			conn:Disconnect()
			return
		end
		-- The sit pose and vehicle controls come with the Seated state. If getting in
		-- left us standing in the seat, sit down properly (only right after getting
		-- in, and never mid-jump, so jumping out still works).
		local state = humanoid:GetState()
		if os.clock() - satAt < 1 and (state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.RunningNoPhysics or state == Enum.HumanoidStateType.Landed) then
			humanoid:ChangeState(Enum.HumanoidStateType.Seated)
		end
		local throttle, steer = seat.ThrottleFloat, seat.SteerFloat
		if throttle == 0 and steer == 0 then
			local move = moveInput()
			throttle = math.clamp(-move.Z, -1, 1)
			steer = math.clamp(move.X, -1, 1)
		end
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
		local h = humanoid :: Humanoid
		local driving: VehicleSeat? = nil
		h:GetPropertyChangedSignal("SeatPart"):Connect(function()
			local seat = h.SeatPart
			if seat and seat:IsA("VehicleSeat") and seat:GetAttribute("DeliveryCar") and seat:GetAttribute("Owner") == player.UserId then
				if driving ~= seat then
					driving = seat
					drive(h, seat)
				end
			else
				driving = nil
			end
		end)
	end
	if player.Character then
		task.spawn(hook, player.Character)
	end
	player.CharacterAdded:Connect(hook)
end

return Driving
