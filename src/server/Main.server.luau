--!strict
-- Server entry point.

local Players = game:GetService("Players")

local CarService = require(script.Parent.CarService)
local ClockService = require(script.Parent.ClockService)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local DataService = require(script.Parent.DataService)
local MapBuilder = require(script.Parent.MapBuilder)
local ShopService = require(script.Parent.ShopService)
local FranchiseService = require(script.Parent.FranchiseService)

local world = MapBuilder.Build()

ClockService.Init()
DataService.Init()
CarService.Init()
ShopService.Init(world.houses)
ShopService.AddShop(world.hq, Config.GameName, nil)
FranchiseService.Init(world.plots)

local function onPlayerAdded(player: Player)
	local profile = DataService.Load(player)
	if profile then
		FranchiseService.OnPlayerLoaded(player)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Franchise shops close in FranchiseService's own PlayerRemoving handler.
Players.PlayerRemoving:Connect(function(player)
	DataService.Release(player)
end)
