--!strict
-- Things you can click in the world while you're at a station:
--  * Job aid cards (any station): click one (or the station rail's Job Aid button) to
--    read it up close; click again to go back.
--  * At the Load Oven station: pizzas on the ready rack (click one to load it into the oven).
--  * At the cut table: pizzas waiting at the oven exits (click one to pull it).
-- Hovering one outlines it in white. Minigames check IsPointerOverPick() so a
-- click on one of these doesn't also count as a minigame press.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
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

local reading: BasePart? = nil -- the job aid card being read up close
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

-- This station's job aid cards (looked up once per station visit).
local aidsFor: { station: string?, shop: Instance?, parts: { [Instance]: boolean } } = { station = nil, shop = nil, parts = {} }
local function stationAids(here: string, shop: Instance): { [Instance]: boolean }
	if aidsFor.station ~= here or aidsFor.shop ~= shop then
		local parts = {}
		for _, d in shop:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("JobAid") == here then
				parts[d] = true
			end
		end
		aidsFor = { station = here, shop = shop, parts = parts }
	end
	return aidsFor.parts
end

-- The pickable thing under the pointer, if any: (instance, "aid" | "pie").
local function target(): (Instance?, string?)
	local here = StationMode.Current()
	local shop = currentShop()
	if not here or not shop then
		return nil, nil
	end
	local candidates: { Instance } = {}
	local aids = stationAids(here, shop)
	for part in aids do
		table.insert(candidates, part)
	end
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
		return nil, nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = candidates
	local ray = Workstation.pointerRay()
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 100, params)
	if not hit then
		return nil, nil
	end
	if aids[hit.Instance] then
		return hit.Instance, "aid"
	end
	local model = hit.Instance:FindFirstAncestorWhichIsA("Model")
	if model and model:GetAttribute("PieId") ~= nil then
		return model, "pie"
	end
	return nil, nil
end

-- True while a click would land on a job aid or a pickable pizza (or close the card being read).
function StationPicks.IsPointerOverPick(): boolean
	if reading then
		return true
	end
	return (target()) ~= nil
end

local function stopReading()
	local ws = StationMode.Workstation()
	if reading and ws then
		ws:popView()
	end
	reading = nil
end

local function read(card: BasePart)
	local ws = StationMode.Workstation()
	if not ws then
		return
	end
	reading = card
	-- The printed side faces the card's LookVector.
	ws:pushView(card.Position + card.CFrame.LookVector * Config.JobAidView.distance, card.Position, Config.JobAidView.fov)
end

-- Whether the station we're at has a job aid card.
function StationPicks.HasAid(): boolean
	local here, shop = StationMode.Current(), currentShop()
	return here ~= nil and shop ~= nil and next(stationAids(here, shop)) ~= nil
end

-- The station rail's Job Aid button: read this station's card up close, or go back.
function StationPicks.ToggleAid()
	if reading then
		stopReading()
		return
	end
	local here, shop = StationMode.Current(), currentShop()
	if here and shop then
		local card = next(stationAids(here, shop))
		if card and card:IsA("BasePart") then
			read(card)
		end
	end
end

-- `pie`: what to do when a pizza is clicked (station, its id, its size).
-- `isBusy`: true while a minigame is open (at the cut table: no pulling another pizza mid-cut).
function StationPicks.Init(pie: (string, number, string) -> (), isBusy: () -> boolean)
	onPie = pie
	busy = isBusy
	highlight.Parent = player:WaitForChild("PlayerGui")

	RunService.RenderStepped:Connect(function()
		if not StationMode.Current() then
			if reading then
				reading = nil
			end
			highlight.Enabled = false
			return
		end
		local inst = if reading then nil else (target())
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
		if reading then
			stopReading()
			return
		end
		local inst, kind = target()
		if kind == "aid" then
			read(inst :: BasePart)
		elseif kind == "pie" and inst then
			local id = inst:GetAttribute("PieId")
			local size = inst:GetAttribute("PieSize")
			if type(id) == "number" then
				onPie(here, id, if type(size) == "string" then size else "")
			end
		end
	end)
end

return StationPicks
