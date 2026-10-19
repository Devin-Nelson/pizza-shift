--!strict
-- Store lots. Each server has a few lots (MapBuilder); a player opens their
-- own store on a free one or joins a store with room (Config.Store.MaxPlayers).
-- A store is its owner's: when the owner leaves, the longest-serving worker
-- takes over and the lot reopens as their store. The last one out frees it.
-- The owner hires staff (NPCs) for their store in the Staff menu; hires are
-- saved with the owner and come along to whatever lot their store opens on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
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

-- The owner's saved hires that are still valid (kinds and stations change).
local function staffOf(owner: Player): { ShopService.CrewSpec }
	local profile = DataService.Get(owner)
	local list = {}
	for _, h in (if profile then profile.Staff else {}) do
		if type(h) == "table" and Config.Staff[h.kind] and type(h.name) == "string" then
			local station = if h.kind == "Insider" and table.find(Config.StaffStations, h.station) then h.station elseif h.kind == "Insider" then Config.StaffStations[1] else nil
			table.insert(list, { kind = h.kind, name = h.name, station = station })
		end
	end
	return list
end

-- Builds the store on `plot` as `owner`'s, with `members` working there.
local function openStore(plot: Plot, owner: Player, members: { Player })
	local model = MapBuilder.BuildShop(plot.cframe, Config.GameName, workspace:FindFirstChild("Shops") :: Folder)
	model.Name = "Store" .. plot.id
	local claim: Claim = { owner = owner, shop = ShopService.AddShop(model, Config.GameName, owner), members = members }
	ShopService.SetCrew(claim.shop, staffOf(owner))
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

---------------------------------------------------------------------------
-- Staff menu
---------------------------------------------------------------------------

local function countOf(staff: { any }, kind: string): number
	local n = 0
	for _, h in staff do
		if h.kind == kind then
			n += 1
		end
	end
	return n
end

local function stationLabel(id: string?): string?
	local info = if id then Config.StationInfo(id) else nil
	return if info then info.label else id
end

-- Everything the Staff menu shows; only the owner can change it.
local function sendStaff(player: Player)
	local id = memberOf[player]
	local claim = if id then claims[id] else nil
	if not claim then
		notify(player, "Open or join a store first (Stores, bottom left).", WARN)
		return
	end
	local staff = staffOf(claim.owner)
	local hired = {}
	for _, h in staff do
		table.insert(hired, { kind = h.kind, display = Config.Staff[h.kind].display, name = h.name, station = h.station, stationLabel = stationLabel(h.station) })
	end
	local hire = {}
	local roll = {}
	for _, kind in Config.StaffOrder do
		local def = Config.Staff[kind]
		if def.hire == "buy" then
			local count = countOf(staff, kind)
			table.insert(hire, { kind = kind, display = def.display, cost = Config.HireCost(kind, count), count = count, max = def.max })
		else
			table.insert(roll, def.display)
		end
	end
	local stations = {}
	for _, s in Config.StaffStations do
		table.insert(stations, { id = s, label = stationLabel(s) })
	end
	local profile = DataService.Get(player)
	Remotes.OpenStaffMenu:FireClient(player, {
		owner = claim.owner.DisplayName,
		canEdit = claim.owner == player,
		coins = if profile then profile.Coins else 0,
		staff = hired,
		hire = hire,
		stations = stations,
		roll = { enabled = Config.StaffRoll.Enabled, cost = Config.StaffRoll.Cost, kinds = roll },
	})
end

-- The store `player` owns (nil if they don't own one here).
local function ownedClaim(player: Player): Claim?
	local id = memberOf[player]
	local claim = if id then claims[id] else nil
	return if claim and claim.owner == player then claim else nil
end

-- Saves the owner's hires and puts them to work.
local function staffChanged(player: Player, claim: Claim)
	ShopService.SetCrew(claim.shop, staffOf(player))
	task.spawn(DataService.Save, player)
	sendStaff(player)
end

local function hire(player: Player, kind: string)
	local claim = ownedClaim(player)
	local def = Config.Staff[kind]
	local profile = DataService.Get(player)
	if not claim or not def or def.hire ~= "buy" or not profile then
		return
	end
	local count = countOf(profile.Staff, kind)
	if count >= def.max then
		notify(player, string.format("You already have %d %ss (the most a store can have).", def.max, def.display), WARN)
		return
	end
	local cost = Config.HireCost(kind, count)
	if not DataService.SpendCoins(player, cost) then
		notify(player, string.format("Hiring a %s costs %d coins.", def.display, cost), WARN)
		return
	end
	-- A first name nobody on the crew has yet (if there's one left).
	local free = {}
	for _, n in Config.StaffNames do
		local taken = false
		for _, h in profile.Staff do
			taken = taken or h.name == n
		end
		if not taken then
			table.insert(free, n)
		end
	end
	local name = if #free > 0 then free[math.random(#free)] else Config.StaffNames[math.random(#Config.StaffNames)]
	-- Insiders start wherever the fewest insiders work (the owner can move them).
	local station = nil
	if kind == "Insider" then
		local best = math.huge
		for _, s in Config.StaffStations do
			local n = 0
			for _, h in profile.Staff do
				n += if h.kind == "Insider" and h.station == s then 1 else 0
			end
			if n < best then
				station, best = s, n
			end
		end
	end
	table.insert(profile.Staff, { kind = kind, name = name, station = station })
	notify(player, string.format("%s joined your crew as %s %s!", name, if string.find(def.display, "^[AEIOU]") then "an" else "a", def.display), GOOD)
	staffChanged(player, claim)
end

local function assign(player: Player, index: number, stationId: string)
	local claim = ownedClaim(player)
	local profile = DataService.Get(player)
	local h = if profile then profile.Staff[index] else nil
	if not claim or not h or h.kind ~= "Insider" or not table.find(Config.StaffStations, stationId) then
		return
	end
	h.station = stationId
	staffChanged(player, claim)
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
	Remotes.RequestStaff.OnServerEvent:Connect(sendStaff)
	Remotes.HireStaff.OnServerEvent:Connect(function(player, kind)
		if type(kind) == "string" then
			hire(player, kind)
		end
	end)
	Remotes.AssignStaff.OnServerEvent:Connect(function(player, index, stationId)
		if type(index) == "number" and index == math.floor(index) and type(stationId) == "string" then
			assign(player, index, stationId)
		end
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
