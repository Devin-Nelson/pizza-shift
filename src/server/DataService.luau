--!strict
-- Player persistence + leaderstats. Fails soft in Studio when API access is off.

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Remotes = require(game:GetService("ReplicatedStorage").Shared.Remotes)

export type Profile = {
	Coins: number,
	XP: number,
	PizzasMade: number,
	Deliveries: number,
	TipsSeen: { [string]: boolean }, -- stations whose first-visit tip the player has closed
	Staff: { { kind: string, name: string, station: string? } }, -- hired for their store (Config.Staff)
}

local DataService = {}

-- Internal key (predates the Dominus rename). Changing it orphans existing saves.
local STORE_NAME = "PizzaShift_v1"
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore unavailable (enable Studio API access to save):", result)
	end
end

local profiles: { [Player]: Profile } = {}
local loaded: { [Player]: boolean } = {}
local doublePay: { [Player]: boolean } = {}

local function defaultProfile(): Profile
	return {
		Coins = 0,
		XP = 0,
		PizzasMade = 0,
		Deliveries = 0,
		TipsSeen = {},
		Staff = {},
	}
end

-- The first-visit tips already seen, as a comma list the client can read.
local function tipsAttribute(profile: Profile): string
	local seen = {}
	for id, on in profile.TipsSeen do
		if on == true and type(id) == "string" then
			table.insert(seen, id)
		end
	end
	table.sort(seen)
	return table.concat(seen, ",")
end

local function reconcile(data: any): Profile
	local profile = defaultProfile()
	if type(data) == "table" then
		for key, value in data do
			if (profile :: any)[key] ~= nil and typeof(value) == typeof((profile :: any)[key]) then
				(profile :: any)[key] = value
			end
		end
	end
	return profile
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

local function retry<T>(fn: () -> T): (boolean, T?)
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn("[DataService] attempt", attempt, "failed:", result)
		task.wait(attempt)
	end
	return false, nil
end

local function makeLeaderstats(player: Player, profile: Profile)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = profile.Coins
	coins.Parent = stats
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Value = Config.LevelFromXP(profile.XP)
	level.Parent = stats
	stats.Parent = player

	-- XP replicates as an attribute for the HUD (leaderstats only shows Level).
	player:SetAttribute("XP", profile.XP)
	player:SetAttribute("TipsSeen", tipsAttribute(profile))
end

local function syncStats(player: Player)
	local profile = profiles[player]
	local stats = player:FindFirstChild("leaderstats")
	if not profile or not stats then
		return
	end
	(stats:FindFirstChild("Coins") :: IntValue).Value = profile.Coins;
	(stats:FindFirstChild("Level") :: IntValue).Value = Config.LevelFromXP(profile.XP)
	player:SetAttribute("XP", profile.XP)
end

-- Session lock: a save carries Lock = { job, at } while a server holds it, so
-- two servers never hold one player's save at once.
local function heldBy(save: any, job: string): boolean
	local lock = if type(save) == "table" then save.Lock else nil
	return type(lock) == "table" and lock.job == job
end

-- Reads a player's save and locks it to this server. If another live server
-- holds it (the player just hopped), wait for it to save and let go; a lock
-- older than LockTTL, or still there after the last try, is taken over (that
-- server is gone or stuck, and its own saves are refused from then on).
local function claim(player: Player, tries: number): (boolean, any)
	for attempt = 1, tries do
		local busy, data = false, nil
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key(player), function(old)
				local lock = if type(old) == "table" then old.Lock else nil
				local live = type(lock) == "table" and lock.job ~= game.JobId and os.time() - (tonumber(lock.at) or 0) < Config.Save.LockTTL
				busy = live and attempt < tries
				if busy then
					return nil
				end
				data = old
				local new = if type(old) == "table" then old else {}
				new.Lock = { job = game.JobId, at = os.time() }
				return new
			end)
		end)
		if ok and not busy then
			return true, data
		end
		if not ok then
			warn("[DataService] load attempt", attempt, "failed:", err)
		end
		if attempt < tries then
			task.wait(attempt)
		end
	end
	return false, nil
end

function DataService.Load(player: Player): Profile?
	local data = nil
	if store and RunService:IsStudio() then
		-- One quick try in Studio; if API access is off, play unsaved instead of retrying.
		local ok, result = claim(player, 1)
		if ok then
			data = result
		else
			warn("[DataService] Saving disabled for this Studio session")
			store = nil
		end
	elseif store then
		local ok, result = claim(player, Config.Save.LoadTries)
		if not ok then
			player:Kick("Couldn't load your save data. Please rejoin.")
			return nil
		end
		data = result
	end
	if not player.Parent then
		return nil
	end
	local profile = reconcile(data)
	profiles[player] = profile
	loaded[player] = true
	makeLeaderstats(player, profile)

	if Config.GamePasses.DoublePay ~= 0 then
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, Config.GamePasses.DoublePay)
		end)
		doublePay[player] = ok and owns == true
	end
	return profile
end

-- Writes the profile, but only while this server still holds the save's lock
-- (never over another server's newer data). `release`: let go of the lock.
function DataService.Save(player: Player, release: boolean?)
	local profile = profiles[player]
	if not store or not profile or not loaded[player] then
		return
	end
	local refused = false
	retry(function()
		(store :: DataStore):UpdateAsync(key(player), function(old)
			refused = not heldBy(old, game.JobId)
			if refused then
				return nil
			end
			local data: any = table.clone(profile)
			data.Lock = if release then nil else { job = game.JobId, at = os.time() }
			return data
		end)
		return true
	end)
	if refused and not release then
		warn("[DataService] another server holds", player.Name, "'s save; not overwriting it")
	end
end

function DataService.Release(player: Player)
	DataService.Save(player, true)
	profiles[player] = nil
	loaded[player] = nil
	doublePay[player] = nil
end

function DataService.Get(player: Player): Profile?
	return profiles[player]
end

-- Pays a worker. Returns the amount actually granted.
function DataService.AddCoins(player: Player, amount: number, ignoreMultiplier: boolean?): number
	local profile = profiles[player]
	if not profile then
		return 0
	end
	local final = math.floor(amount)
	if not ignoreMultiplier and doublePay[player] then
		final *= 2
	end
	profile.Coins += final
	syncStats(player)
	return final
end

function DataService.SpendCoins(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or profile.Coins < amount then
		return false
	end
	profile.Coins -= amount
	syncStats(player)
	return true
end

-- Returns true if the player levelled up.
function DataService.AddXP(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local before = Config.LevelFromXP(profile.XP)
	profile.XP += amount
	syncStats(player)
	return Config.LevelFromXP(profile.XP) > before
end

function DataService.GetLevel(player: Player): number
	local profile = profiles[player]
	return if profile then Config.LevelFromXP(profile.XP) else 1
end

function DataService.Sync(player: Player)
	syncStats(player)
end

-- The player closed a station's first-visit tip: don't show it again.
function DataService.MarkTipSeen(player: Player, stationId: string)
	local profile = profiles[player]
	if not profile or profile.TipsSeen[stationId] then
		return
	end
	profile.TipsSeen[stationId] = true
	player:SetAttribute("TipsSeen", tipsAttribute(profile))
end

function DataService.Init()
	Remotes.TipSeen.OnServerEvent:Connect(function(player, stationId)
		if type(stationId) == "string" and Config.StationInfo(stationId) then
			DataService.MarkTipSeen(player, stationId)
		end
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passId == Config.GamePasses.DoublePay then
			doublePay[player] = true
		end
	end)

	-- Autosave every 2 minutes.
	task.spawn(function()
		while true do
			task.wait(120)
			for _, player in Players:GetPlayers() do
				task.spawn(DataService.Save, player)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				DataService.Save(player, true)
				pending -= 1
			end)
		end
		local start = os.clock()
		while pending > 0 and os.clock() - start < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
