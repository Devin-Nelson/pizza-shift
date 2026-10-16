--!strict
-- Player-owned restaurants. Owning a franchise is saved; while the owner is in
-- the server their shop is built on a free lot and runs like the HQ. The owner
-- earns a cut of every sale and a royalty on every worker's pay there.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local MapBuilder = require(script.Parent.MapBuilder)
local ShopService = require(script.Parent.ShopService)

type Plot = { id: number, cframe: CFrame, model: Model }

local FranchiseService = {}

local plots: { Plot } = {}
local claims: { [number]: { player: Player, shop: ShopService.Shop } } = {}
local lastPlotViewed: { [Player]: number } = {}

local function setLotVisible(plot: Plot, forSale: boolean)
	local sign = plot.model:FindFirstChild("ForSale") :: BasePart?
	if sign then
		sign.Transparency = if forSale then 0 else 1
		local pp = sign:FindFirstChildOfClass("ProximityPrompt")
		if pp then
			pp.Enabled = forSale
		end
		local label = sign:FindFirstChild("Label") :: BillboardGui?
		if label then
			label.Enabled = forSale
		end
	end
end

local function freePlot(preferred: number?): Plot?
	if preferred and not claims[preferred] then
		for _, plot in plots do
			if plot.id == preferred then
				return plot
			end
		end
	end
	for _, plot in plots do
		if not claims[plot.id] then
			return plot
		end
	end
	return nil
end

local function ownedPlot(player: Player): number?
	for id, claim in claims do
		if claim.player == player then
			return id
		end
	end
	return nil
end

local function openShop(player: Player, name: string, preferred: number?): boolean
	if ownedPlot(player) then
		return true
	end
	local plot = freePlot(preferred)
	if not plot then
		Remotes.Notify:FireClient(player, "All franchise lots in this server are taken - your shop opens when one frees up.", Color3.fromRGB(255, 160, 100))
		return false
	end
	local shops = workspace:FindFirstChild("Shops") :: Folder
	local model = MapBuilder.BuildShop(plot.cframe, name, shops)
	model.Name = "Franchise_" .. player.UserId
	local shop = ShopService.AddShop(model, name, player)
	claims[plot.id] = { player = player, shop = shop }
	setLotVisible(plot, false)
	Remotes.Notify:FireClient(player, "Your franchise \"" .. name .. "\" is open on Lot #" .. plot.id .. "!", Color3.fromRGB(120, 255, 160))
	return true
end

local function closeShop(player: Player)
	local id = ownedPlot(player)
	if not id then
		return
	end
	local claim = claims[id]
	claims[id] = nil
	ShopService.RemoveShop(claim.shop)
	for _, plot in plots do
		if plot.id == id then
			setLotVisible(plot, true)
		end
	end
	-- Someone else may have been waiting for a lot.
	for _, other in Players:GetPlayers() do
		local profile = DataService.Get(other)
		if other ~= player and profile and profile.Franchise.owned and not ownedPlot(other) then
			openShop(other, profile.Franchise.name, nil)
			break
		end
	end
end

local function filterName(player: Player, raw: string): string?
	local trimmed = string.gsub(raw, "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")
	if #trimmed < 3 or #trimmed > 24 then
		return nil
	end
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(trimmed, player.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(result) ~= "string" or string.find(result, "#") then
		return nil
	end
	return result
end

function FranchiseService.OnPlayerLoaded(player: Player)
	local profile = DataService.Get(player)
	if profile and profile.Franchise.owned then
		openShop(player, profile.Franchise.name, nil)
	end
end

function FranchiseService.Init(worldPlots: { Plot })
	plots = worldPlots

	for _, plot in plots do
		local sign = plot.model:FindFirstChild("ForSale")
		local pp = sign and sign:FindFirstChildOfClass("ProximityPrompt")
		if pp then
			pp.Triggered:Connect(function(player)
				lastPlotViewed[player] = plot.id
				local profile = DataService.Get(player)
				if not profile then
					return
				end
				Remotes.OpenFranchiseMenu:FireClient(player, {
					cost = Config.Franchise.Cost,
					minLevel = Config.Franchise.MinLevel,
					level = DataService.GetLevel(player),
					coins = profile.Coins,
					owned = profile.Franchise.owned,
					saleCut = Config.Franchise.SaleCut,
					royalty = Config.Franchise.OwnerRoyalty,
				})
			end)
		end
	end

	Remotes.BuyFranchise.OnServerEvent:Connect(function(player, rawName)
		if type(rawName) ~= "string" then
			return
		end
		local profile = DataService.Get(player)
		if not profile then
			return
		end
		if profile.Franchise.owned then
			Remotes.Notify:FireClient(player, "You already own a franchise!")
			return
		end
		if DataService.GetLevel(player) < Config.Franchise.MinLevel then
			Remotes.Notify:FireClient(player, "You need to be level " .. Config.Franchise.MinLevel .. " to franchise.", Color3.fromRGB(255, 160, 100))
			return
		end
		if not freePlot(lastPlotViewed[player]) then
			Remotes.Notify:FireClient(player, "No free lots in this server right now.", Color3.fromRGB(255, 160, 100))
			return
		end
		local name = filterName(player, rawName)
		if not name then
			Remotes.Notify:FireClient(player, "That name isn't allowed (3-24 characters, family friendly).", Color3.fromRGB(255, 160, 100))
			return
		end
		if not DataService.SpendCoins(player, Config.Franchise.Cost) then
			Remotes.Notify:FireClient(player, "Not enough coins.", Color3.fromRGB(255, 160, 100))
			return
		end
		profile.Franchise = { owned = true, name = name }
		DataService.Sync(player)
		task.spawn(DataService.Save, player)
		openShop(player, name, lastPlotViewed[player])
	end)

	Players.PlayerRemoving:Connect(function(player)
		closeShop(player)
		lastPlotViewed[player] = nil
	end)
end

return FranchiseService
