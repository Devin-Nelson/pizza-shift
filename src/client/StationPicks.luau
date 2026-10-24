--!strict
-- Things you can click in the world while you're at a station:
--  * At the Load Oven station: pizzas on the ready rack (click one to load it into the oven).
--  * At the cut table: pizzas waiting at the oven exits (click one to pull it).
-- Hovering one outlines it in white. Minigames check IsPointerOverPick() so a
-- click on one of these doesn't also count as a minigame press.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local StationMode = require(script.Parent.StationMode)
local Workstation = require(script.Parent.Workstation)

local StationPicks = {}

local player = Players.LocalPlayer

-- Which pizzas can be picked at which station (the pizza model's PieStage).
local PIE_STAGE: { [string]: string } = { Load = "Ready", CutTable = "Exit" }

local highlight = Instance.new("Highlight")
highlight.Name = "PickOutline"
highlight.FillTransparency = 1
highlight.OutlineColor = Color3.new(1, 1, 1)
highlight.OutlineTransparency = 0
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
highlight.Enabled = false

local onPie: (station: string, pieId: number, size: string) -> () = function(_station, _pieId, _size) end
local busy: () -> boolean = function()
	return false
end

-- The shop model the station we're at belongs to (stations live in <shop>.Stations).
local function currentShop(): Instance?
	local ws = StationMode.Workstation()
	local folder = ws and ws.station.Parent
	return folder and folder.Parent
end

-- The pickable pizza under the pointer, if any.
local function target(input: InputObject?): Instance?
	local here = StationMode.Current()
	local shop = currentShop()
	if not here or not shop then
		return nil
	end
	local candidates: { Instance } = {}
	-- At the cut table it's one pizza at a time.
	local stage = PIE_STAGE[here]
	if stage and not (here == "CutTable" and busy()) then
		for _, child in shop:GetChildren() do
			if child:IsA("Model") and child:GetAttribute("PieStage") == stage then
				table.insert(candidates, child)
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = candidates
	local ray = Workstation.pointerRay(input)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 100, params)
	if not hit then
		return nil
	end
	local model = hit.Instance:FindFirstAncestorWhichIsA("Model")
	return if model and model:GetAttribute("PieId") ~= nil then model else nil
end

-- True while a click would land on a pickable pizza.
function StationPicks.IsPointerOverPick(): boolean
	return target() ~= nil
end

-- `pie`: what to do when a pizza is clicked (station, its id, its size).
-- `isBusy`: true while a minigame is open (at the cut table: no pulling another pizza mid-cut).
function StationPicks.Init(pie: (string, number, string) -> (), isBusy: () -> boolean)
	onPie = pie
	busy = isBusy
	highlight.Parent = player:WaitForChild("PlayerGui")

	RunService.RenderStepped:Connect(function()
		if not StationMode.Current() then
			highlight.Enabled = false
			return
		end
		local inst = target()
		highlight.Adornee = inst
		highlight.Enabled = inst ~= nil
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or (input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch) then
			return
		end
		local here = StationMode.Current()
		if not here then
			return
		end
		local inst = target(input)
		if inst then
			local id = inst:GetAttribute("PieId")
			local size = inst:GetAttribute("PieSize")
			if type(id) == "number" then
				onPie(here, id, if type(size) == "string" then size else "")
			end
		end
	end)
end

return StationPicks
