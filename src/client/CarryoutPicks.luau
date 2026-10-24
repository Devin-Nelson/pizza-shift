--!strict
-- Carryout pickup, walking round the store (not at a station): click an
-- order's stack on the carryout rack to pick it up, then click its customer at
-- the counter to hand it over, or the rack to put it back (on a touchscreen,
-- a tap: drags and the thumbstick never count). Hovering one
-- outlines it in white. The server tags what can be clicked (CarryoutPick,
-- CarryoutKind "Stack" / "Rack" / "Customer") and sets the player's Carrying
-- attribute while they have an order in hand.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local StationMode = require(script.Parent.StationMode)
local Workstation = require(script.Parent.Workstation)

local CarryoutPicks = {}

local player = Players.LocalPlayer
local REACH = 16 -- the server allows a little more

local highlight = Instance.new("Highlight")
highlight.Name = "CarryoutOutline"
highlight.FillTransparency = 1
highlight.OutlineColor = Color3.new(1, 1, 1)
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
highlight.Enabled = false

-- What a click (or a tap at `at`, screen coords) would land on: stacks with
-- nothing in hand; the rack and the customers with an order in hand.
local function target(at: Vector2?): Instance?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or StationMode.Current() then
		return nil
	end
	local holding = player:GetAttribute("Carrying") ~= nil
	local candidates: { Instance } = {}
	for _, inst in CollectionService:GetTagged("CarryoutPick") do
		if (inst:GetAttribute("CarryoutKind") == "Stack") ~= holding and inst:IsDescendantOf(workspace) then
			table.insert(candidates, inst)
		end
	end
	if #candidates == 0 then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = candidates
	local ray = if at then workspace.CurrentCamera:ScreenPointToRay(at.X, at.Y) else Workstation.pointerRay()
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 100, params)
	if not hit or (hit.Position - root.Position).Magnitude > REACH then
		return nil
	end
	local inst: Instance? = hit.Instance
	while inst and not CollectionService:HasTag(inst, "CarryoutPick") do
		inst = inst.Parent
	end
	return inst
end

function CarryoutPicks.start()
	highlight.Parent = player:WaitForChild("PlayerGui")
	RunService.Heartbeat:Connect(function()
		local inst = target()
		-- The rack's hitbox is invisible: outline the rack itself.
		highlight.Adornee = if inst and inst:GetAttribute("CarryoutKind") == "Rack" then inst.Parent else inst
		highlight.Enabled = inst ~= nil
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local inst = target()
		if inst then
			Remotes.CarryoutPick:FireServer(inst)
		end
	end)
	-- Touch: only a tap counts (short, barely moving), aimed where it landed.
	-- A camera swipe or the thumbstick starting over the rack used to put the
	-- order you'd just picked up straight back (the user, 2026-10-23, mobile).
	local touches: { [InputObject]: { at: Vector3, t: number } } = {}
	UserInputService.TouchStarted:Connect(function(touch, processed)
		if not processed then
			touches[touch] = { at = touch.Position, t = os.clock() }
		end
	end)
	UserInputService.TouchEnded:Connect(function(touch)
		local start = touches[touch]
		touches[touch] = nil
		if not start or os.clock() - start.t > 0.4 or (touch.Position - start.at).Magnitude > 12 then
			return
		end
		local inst = target(Vector2.new(touch.Position.X, touch.Position.Y))
		if inst then
			Remotes.CarryoutPick:FireServer(inst)
		end
	end)
end

return CarryoutPicks
