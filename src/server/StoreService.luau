--!strict
-- Store lots. Each server has a few lots (MapBuilder); a player opens their
-- own store on a free one or joins a store with room (Config.Store.MaxPlayers).
-- A store is its owner's: when the owner leaves, the longest-serving worker
-- takes over and the lot reopens as their store. The last one out frees it.
-- The owner hires team members (NPCs) in the Staff menu, assigns their
-- stations and schedules their shifts; staff are saved with the owner and
-- come along to whatever lot their store opens on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GameClock = require(ReplicatedStorage.Shared.GameClock)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Staff = require(ReplicatedStorage.Shared.Staff)
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

-- The owner's saved staff, made safe once as their store opens (unique ids,
-- each shift within the cap). ShopService writes XP straight into these records.
local function prepareStaff(owner: Player): { Staff.Member }
	local profile = DataService.Get(owner)
	if not profile then
		return {}
	end
	local list, seen, rng = {}, {}, Random.new()
	for i, raw in profile.Staff do
		local m = Staff.sanitize(raw, rng, i)
		if m then
			if seen[m.id] then
				m.id = #profile.Staff + i
			end
			seen[m.id] = true
			table.insert(list, m)
		end
	end
	for _, shift in Staff.Shifts do
		local n = 0
		for _, m in list do
			if m.shifts[shift] then
				n += 1
				m.shifts[shift] = n <= Config.StaffOnShift
			end
		end
	end
	profile.Staff = list
	return list
end

local function staffOf(owner: Player): { Staff.Member }
	local profile = DataService.Get(owner)
	return if profile then profile.Staff :: any else {}
end

-- Builds the store on `plot` as `owner`'s, with `members` working there.
local function openStore(plot: Plot, owner: Player, members: { Player })
	local model = MapBuilder.BuildShop(plot.cframe, Config.GameName, workspace:FindFirstChild("Shops") :: Folder)
	model.Name = "Store" .. plot.id
	local claim: Claim = { owner = owner, shop = ShopService.AddShop(model, Config.GameName, owner), members = members }
	ShopService.SetCrew(claim.shop, prepareStaff(owner))
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

local function countOf(staff: { Staff.Member }, kind: string): number
	local n = 0
	for _, m in staff do
		if m.kind == kind then
			n += 1
		end
	end
	return n
end

local function stationLabel(id: string): string
	local info = Config.StationInfo(id)
	return if info then info.label else id
end

local function findMember(staff: { Staff.Member }, id: number): Staff.Member?
	for _, m in staff do
		if m.id == id then
			return m
		end
	end
	return nil
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
	local list = {}
	for _, m in staff do
		local stats = {}
		for _, s in Config.StaffStations do
			table.insert(stats, { name = Config.StaffStatNames[s], level = m.stats[s].level })
		end
		local stat = m.stats[m.station]
		table.insert(list, {
			id = m.id,
			name = m.name,
			display = Config.Staff[m.kind].display,
			works = m.kind == "TeamMember",
			station = m.station,
			stationLabel = stationLabel(m.station),
			level = stat.level,
			xp = stat.xp,
			xpNext = Staff.xpToNext(stat.level),
			stats = stats,
			reliability = m.reliability,
			avail = m.avail,
			shifts = m.shifts,
			open = Staff.isOpen(m.avail),
		})
	end
	local shifts = {}
	for _, shift in Staff.Shifts do
		table.insert(shifts, { name = shift, count = Staff.scheduled(staff, shift), max = Config.StaffOnShift })
	end
	local hire, roll = {}, {}
	for _, kind in Config.StaffOrder do
		local def = Config.Staff[kind]
		if def.hire == "buy" then
			table.insert(hire, { kind = kind, display = def.display, cost = Config.HireCost(kind, countOf(staff, kind)) })
		else
			table.insert(roll, def.display)
		end
	end
	local stations = {}
	for _, s in Config.StaffStations do
		table.insert(stations, { id = s, label = stationLabel(s) })
	end
	local _, hour = GameClock.split(GameClock.weekHour())
	local profile = DataService.Get(player)
	Remotes.OpenStaffMenu:FireClient(player, {
		owner = claim.owner.DisplayName,
		canEdit = claim.owner == player,
		coins = if profile then profile.Coins else 0,
		staff = list,
		roster = { count = #staff, max = Config.StaffRoster },
		shifts = shifts,
		now = Staff.shiftAt(hour),
		reliabilityMax = Config.Reliability.Max,
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

-- Saves the owner's staff and puts the change to work.
local function staffChanged(player: Player, claim: Claim)
	ShopService.SetCrew(claim.shop, staffOf(player))
	task.spawn(DataService.Save, player)
	sendStaff(player)
end

local function hire(player: Player, kind: string)
	local claim = ownedClaim(player)
	local def = Config.Staff[kind]
	if not claim or not def or def.hire ~= "buy" then
		return
	end
	local staff = staffOf(player)
	if #staff >= Config.StaffRoster then
		notify(player, string.format("Your store has a full roster (%d).", Config.StaffRoster), WARN)
		return
	end
	local cost = Config.HireCost(kind, countOf(staff, kind))
	if not DataService.SpendCoins(player, cost) then
		notify(player, string.format("Hiring a %s costs %d coins.", def.display, cost), WARN)
		return
	end
	local nextId, taken = 1, {}
	for _, m in staff do
		nextId = math.max(nextId, m.id + 1)
		taken[m.name] = true
	end
	local free = {}
	for _, n in Config.StaffNames do
		if not taken[n] then
			table.insert(free, n)
		end
	end
	local name = if #free > 0 then free[math.random(#free)] else Config.StaffNames[math.random(#Config.StaffNames)]
	-- They start wherever the fewest work (the owner can move them).
	local station, fewest = Config.StaffStations[1], math.huge
	for _, s in Config.StaffStations do
		local n = 0
		for _, m in staff do
			n += if m.station == s then 1 else 0
		end
		if n < fewest then
			station, fewest = s, n
		end
	end
	local m = Staff.newMember(Random.new(), "Buy", nextId, name, station)
	-- Scheduled for every shift they can work that still has room.
	for _, shift in Staff.Shifts do
		if m.shifts[shift] and Staff.scheduled(staff, shift) >= Config.StaffOnShift then
			m.shifts[shift] = false
		end
	end
	table.insert(staff, m)
	local can = {}
	for _, shift in Staff.Shifts do
		if m.avail[shift] then
			table.insert(can, shift)
		end
	end
	notify(player, string.format("%s joined your crew! Available: %s.", name, if Staff.isOpen(m.avail) then "open (any shift)" else table.concat(can, ", ")), GOOD)
	staffChanged(player, claim)
end

local function assign(player: Player, id: number, stationId: string)
	local claim = ownedClaim(player)
	local m = findMember(staffOf(player), id)
	if not claim or not m or not table.find(Config.StaffStations, stationId) then
		return
	end
	m.station = stationId
	staffChanged(player, claim)
end

local function schedule(player: Player, id: number, shift: string, on: boolean)
	local claim = ownedClaim(player)
	local staff = staffOf(player)
	local m = findMember(staff, id)
	if not claim or not m or not table.find(Staff.Shifts, shift) or m.shifts[shift] == on then
		return
	end
	if on and not m.avail[shift] then
		notify(player, string.format("%s isn't available for %s.", m.name, shift), WARN)
		return
	end
	if on and Staff.scheduled(staff, shift) >= Config.StaffOnShift then
		notify(player, string.format("%s is full (%d on shift). Take someone off it first.", shift, Config.StaffOnShift), WARN)
		return
	end
	m.shifts[shift] = on
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
	Remotes.AssignStaff.OnServerEvent:Connect(function(player, id, stationId)
		if type(id) == "number" and type(stationId) == "string" then
			assign(player, id, stationId)
		end
	end)
	Remotes.ScheduleStaff.OnServerEvent:Connect(function(player, id, shift, on)
		if type(id) == "number" and type(shift) == "string" and type(on) == "boolean" then
			schedule(player, id, shift, on)
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
