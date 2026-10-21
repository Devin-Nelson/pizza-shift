--!strict
-- Server entry point.

local Players = game:GetService("Players")

local CarService = require(script.Parent.CarService)
local ClockService = require(script.Parent.ClockService)
local DataService = require(script.Parent.DataService)
local MapBuilder = require(script.Parent.MapBuilder)
local ShopService = require(script.Parent.ShopService)
local StationArt = require(script.Parent.StationArt)
local StoreService = require(script.Parent.StoreService)

StationArt.Preload()
local world = MapBuilder.Build()

ClockService.Init()
DataService.Init()
CarService.Init()
ShopService.Init(world.houses)
StoreService.Init(world.plots)

local function onPlayerAdded(player: Player)
	local profile = DataService.Load(player)
	if profile then
		StoreService.OnPlayerLoaded(player)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Stores hand over or close in StoreService's own PlayerRemoving handler.
Players.PlayerRemoving:Connect(function(player)
	DataService.Release(player)
end)
