--!strict
-- Store lots. Each server has a few lots (MapBuilder); a player opens their
-- own store on a free one or joins a store with room (Config.Store.MaxPlayers).
-- A store is its owner's: when the owner leaves, the longest-serving worker
-- takes over and the lot reopens as their store. The last one out frees it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MapBuilder = require(script.Parent.MapBuilder)
local ShopService = require(script.Parent.ShopService)

type Plot = { id: number, cframe: CFrame, model: Model }
-- `members` in the order they joined; the owner is one of them.
type Claim = { owner: Player, shop: ShopService.Shop, members: { Player } }

local StoreService = {}

local plots: { Plot } = {}
local claims: { [number]: Claim } = {}
local memberOf: { [Player]: number } = {}

local WARN = Color3.fromRGB(255, 160, 100)
local GOOD = Color3.fromRGB(120, 255, 160)

local function notify(player: Player, text: string, color: Color3?)
	if player.Parent then
		Remotes.Notify:FireClient(player, text, color)
	end
end

local function plotById(id: number): Plot?
	for _, plot in plots do
		if plot.id == id then
			return plot
		end
	end
	return nil
end

local function setLotVisible(plot: Plot, forSale: boolean)
	local sign = plot.model:FindFirstChild("ForSale") :: BasePart?
	if sign then
		sign.Transparency = if forSale then 0 else 1
		sign.CanCollide = forSale
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

-- What the store picker shows: every lot, who runs it and how full it is.
local function lotList(player: Player): { any }
	local list = {}
	for _, plot in plots do
		local claim = claims[plot.id]
		table.insert(list, {
			id = plot.id,
			owner = if claim then claim.owner.DisplayName else nil,
			count = if claim then #claim.members else 0,
			max = Config.Store.MaxPlayers,
			mine = memberOf[player] == plot.id,
			owned = claim ~= nil and claim.owner == player,
		})
	end
	return list
end

local function sendPicker(player: Player, focus: number?)
	Remotes.OpenStorePicker:FireClient(player, lotList(player), focus)
end

-- Just outside the entrance, facing in.
local function moveTo(player: Player, plot: Plot)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or (humanoid and humanoid.SeatPart) then
		return
	end
	local from = (plot.cframe * CFrame.new(0, 3, 34)).Position
	character:PivotTo(CFrame.lookAt(from, (plot.cframe * CFrame.new(0, 3, 0)).Position))
end

local function enlist(player: Player, plot: Plot, claim: Claim)
	memberOf[player] = plot.id
	ShopService.SetMember(player, claim.shop)
	player:SetAttribute("StoreOwner", if claim.owner == player then true else nil)
end

-- Builds the store on `plot` as `owner`'s, with `members` working there.
local function openStore(plot: Plot, owner: Player, members: { Player })
	local model = MapBuilder.BuildShop(plot.cframe, Config.GameName, workspace:FindFirstChild("Shops") :: Folder)
	model.Name = "Store" .. plot.id
	local claim: Claim = { owner = owner, shop = ShopService.AddShop(model, Config.GameName, owner), members = members }
	claims[plot.id] = claim
	setLotVisible(plot, false)
	for _, m in members do
		enlist(m, plot, claim)
	end
end

-- Takes `player` off whatever store they work at (handing it over if it was theirs).
local function leaveStore(player: Player)
	local id = memberOf[player]
	local claim = if id then claims[id] else nil
	memberOf[player] = nil
	ShopService.SetMember(player, nil)
	player:SetAttribute("StoreOwner", nil)
	if not id or not claim then
		return
	end
	local i = table.find(claim.members, player)
	if i then
		table.remove(claim.members, i)
	end
	if claim.owner ~= player then
		return
	end
	local plot = plotById(id) :: Plot
	ShopService.RemoveShop(claim.shop)
	claims[id] = nil
	local heir = claim.members[1]
	if heir then
		openStore(plot, heir, claim.members)
		for _, m in claim.members do
			notify(m, string.format("%s left, so this is now %s's store.", player.DisplayName, if m == heir then "your" else heir.DisplayName), GOOD)
		end
	else
		setLotVisible(plot, true)
	end
end

local function chooseStore(player: Player, lotId: number?)
	if lotId == nil then
		if memberOf[player] then
			leaveStore(player)
			notify(player, "You left the store. Open Stores (bottom left) to pick one.")
		end
		return
	end
	local plot = plotById(lotId)
	if not plot then
		return
	end
	if memberOf[player] == lotId then
		notify(player, "You already work here.")
		return
	end
	local claim = claims[lotId]
	if claim and #claim.members >= Config.Store.MaxPlayers then
		notify(player, string.format("%s's store is full (%d/%d).", claim.owner.DisplayName, #claim.members, Config.Store.MaxPlayers), WARN)
		sendPicker(player)
		return
	end
	leaveStore(player)
	-- Leaving may have handed over or freed a store, so look again.
	claim = claims[lotId]
	if claim then
		table.insert(claim.members, player)
		enlist(player, plot, claim)
		notify(player, string.format("You joined %s's store.", claim.owner.DisplayName), GOOD)
		for _, m in claim.members do
			if m ~= player then
				notify(m, player.DisplayName .. " joined the store.", GOOD)
			end
		end
	else
		openStore(plot, player, { player })
		notify(player, string.format("Your store on Lot #%d is open for business!", plot.id), GOOD)
	end
	moveTo(player, plot)
end

-- Called once a player's save has loaded: offer them a store.
function StoreService.OnPlayerLoaded(player: Player)
	sendPicker(player)
end

function StoreService.Init(worldPlots: { Plot })
	plots = worldPlots
	for _, plot in plots do
		local sign = plot.model:FindFirstChild("ForSale")
		local pp = sign and sign:FindFirstChildOfClass("ProximityPrompt")
		if pp then
			pp.Triggered:Connect(function(player)
				sendPicker(player, plot.id)
			end)
		end
	end
	Remotes.RequestStores.OnServerEvent:Connect(function(player)
		sendPicker(player)
	end)
	Remotes.ChooseStore.OnServerEvent:Connect(function(player, lotId)
		if lotId ~= nil and (type(lotId) ~= "number" or lotId ~= lotId) then
			return
		end
		chooseStore(player, lotId)
	end)
	Players.PlayerRemoving:Connect(leaveStore)
end

return StoreService
