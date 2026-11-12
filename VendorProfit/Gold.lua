-- Gold: a log of each character's gold over time, for the Gold tab's graph
-- (GoldPanel.lua). Only the player's own gold, on every character of the
-- account: no guild bank.
--
-- Saved for the whole account in VendorProfitDB, so the graph can add
-- characters together:
--   gold[key] = { name, realm, log }, key "Name-Realm"
--     log = "minute:copper;minute:copper;..." oldest first: the gold the
--     character had from that minute (minutes since 1970) until the next
--     point. One string rather than a table: thousands of points save and
--     load far smaller and faster that way. Read when first needed, written
--     back on logout.
--   goldHidden[key] = true for characters left out of the graph and totals.
--
-- A point is saved when gold changes, at most one a minute (the last value
-- in a minute wins). Points older than THIN_AFTER are thinned to the last one
-- in each hour: far finer than the graph can draw.
--
-- Before a character's first point it counts at that first value: an alt
-- that sat untouched had that gold all along, so it doesn't show as a sudden
-- step up the first time it logs in with the addon.

local _, ns = ...
local VendorProfit = ns.VendorProfit

local Gold = {}
VendorProfit.Gold = Gold

local MINUTE = 60
-- In minutes.
local THIN_AFTER = 90 * 24 * 60
-- The game can report 0 gold for a few seconds after logging in, so a 0 then
-- is asked again every second, this many times, before it's believed.
Gold.LOGIN_RETRIES = 30

local listeners = {}
function Gold.OnChange(fn)
    listeners[#listeners + 1] = fn
end

-- Goes up with every change, so the graph can tell when to redraw.
local version = 0
function Gold.Version()
    return version
end

local function Changed()
    version = version + 1
    for _, fn in ipairs(listeners) do
        xpcall(fn, geterrorhandler())
    end
end

local function DB()
    VendorProfitDB = VendorProfitDB or {}
    VendorProfitDB.gold = VendorProfitDB.gold or {}
    return VendorProfitDB
end

-- Logs as two lists, { minutes, copper }, read from the save on first use.
local logs = {}

local function Parse(text)
    local log = { minutes = {}, copper = {} }
    if type(text) == "string" then
        for minute, copper in text:gmatch("(%d+):(%d+)") do
            log.minutes[#log.minutes + 1] = tonumber(minute)
            log.copper[#log.copper + 1] = tonumber(copper)
        end
    end
    return log
end

local function Serialize(log)
    local parts = {}
    for index, minute in ipairs(log.minutes) do
        parts[index] = minute .. ":" .. log.copper[index]
    end
    return table.concat(parts, ";")
end

local function Log(key)
    local log = logs[key]
    if log == nil then
        local entry = DB().gold[key]
        log = Parse(entry and entry.log)
        logs[key] = log
    end
    return log
end

-- Keeps the last point of each hour among points older than cutoff (a
-- minute), and drops points that don't change the gold.
local function Thin(log, cutoff)
    local minutes, copper = log.minutes, log.copper
    local keptMinutes, keptCopper = {}, {}
    local function Keep(minute, value)
        local n = #keptCopper
        if n == 0 or keptCopper[n] ~= value then
            keptMinutes[n + 1], keptCopper[n + 1] = minute, value
        end
    end
    local count = #minutes
    local index = 1
    while index <= count do
        local minute = minutes[index]
        if minute < cutoff then
            local hour = math.floor(minute / 60)
            local last = index
            while last < count and minutes[last + 1] < cutoff and math.floor(minutes[last + 1] / 60) == hour do
                last = last + 1
            end
            Keep(minutes[last], copper[last])
            index = last + 1
        else
            Keep(minute, copper[index])
            index = index + 1
        end
    end
    log.minutes, log.copper = keptMinutes, keptCopper
end

local playerKey

function Gold.PlayerKey()
    return playerKey
end

-- Writes this character's log back into the save.
function Gold.Save()
    local log = playerKey and logs[playerKey]
    local entry = playerKey and DB().gold[playerKey]
    if log and entry then
        entry.log = Serialize(log)
    end
end

local function Record(copper)
    if playerKey == nil or copper == nil then
        return
    end
    local log = Log(playerKey)
    local minute = math.floor(time() / MINUTE)
    local count = #log.minutes
    if count > 0 and log.copper[count] == copper then
        return
    end
    if count > 0 and log.minutes[count] >= minute then
        -- Changed again within the minute: the last value wins. Back to what
        -- it was before, and the minute had no change at all.
        if count > 1 and log.copper[count - 1] == copper then
            log.minutes[count], log.copper[count] = nil, nil
        else
            log.copper[count] = copper
        end
    else
        log.minutes[count + 1], log.copper[count + 1] = minute, copper
    end
    Changed()
end

local recorded = false   -- whether gold was recorded since logging in
-- Between leaving the world (logout, /reload, a loading screen) and entering
-- it again, the game reports 0 gold, so nothing is recorded then.
local leaving = false

local function RecordAtLogin(tries)
    if recorded then
        return
    end
    local money = GetMoney() or 0
    if money == 0 and tries < Gold.LOGIN_RETRIES then
        C_Timer.After(1, function() RecordAtLogin(tries + 1) end)
        return
    end
    recorded = true
    Record(money)
end

local function Login()
    local name, realm = UnitName("player"), GetRealmName()
    if name == nil or realm == nil then
        return
    end
    playerKey = name .. "-" .. realm
    local gold = DB().gold
    gold[playerKey] = gold[playerKey] or {}
    gold[playerKey].name, gold[playerKey].realm = name, realm
    Thin(Log(playerKey), math.floor(time() / MINUTE) - THIN_AFTER)
    RecordAtLogin(0)
end

-- Queries --------------------------------------------------------------------

-- Every character with gold recorded, by name then realm: { key, name,
-- realm, copper (now), first (time of its first point) }.
function Gold.Characters()
    local list = {}
    for key, entry in pairs(DB().gold) do
        local log = Log(key)
        local count = #log.minutes
        if count > 0 then
            list[#list + 1] = { key = key, name = entry.name or key, realm = entry.realm or "",
                copper = log.copper[count], first = log.minutes[1] * MINUTE }
        end
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.realm < b.realm
    end)
    return list
end

-- A character's gold at a time; before its first point, its first value.
function Gold.ValueAt(key, at)
    local log = Log(key)
    local minutes = log.minutes
    if #minutes == 0 then
        return 0
    end
    local minute = math.floor(at / MINUTE)
    if minute < minutes[1] then
        return log.copper[1]
    end
    -- The last point at or before the minute.
    local low, high = 1, #minutes
    while low < high do
        local middle = math.floor((low + high + 1) / 2)
        if minutes[middle] <= minute then
            low = middle
        else
            high = middle - 1
        end
    end
    return log.copper[low]
end

-- The gold of characters (a list from Gold.Characters) added up at a time.
function Gold.Total(characters, at)
    local total = 0
    for _, character in ipairs(characters) do
        total = total + Gold.ValueAt(character.key, at)
    end
    return total
end

function Gold.IsShown(key)
    local hidden = DB().goldHidden
    return not (hidden and hidden[key])
end

function Gold.SetShown(key, shown)
    local db = DB()
    db.goldHidden = db.goldHidden or {}
    db.goldHidden[key] = not shown or nil
    if next(db.goldHidden) == nil then
        db.goldHidden = nil
    end
    Changed()
end

function Gold.ShowAll()
    DB().goldHidden = nil
    Changed()
end

-- The characters the graph shows: those not hidden.
function Gold.Shown()
    local shown = {}
    for _, character in ipairs(Gold.Characters()) do
        if Gold.IsShown(character.key) then
            shown[#shown + 1] = character
        end
    end
    return shown
end

-- For tests: forget the parsed logs, as after a restart.
function Gold.Reload()
    logs = {}
    playerKey = nil
    recorded = false
    leaving = false
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("PLAYER_LEAVING_WORLD")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        Login()
    elseif event == "PLAYER_MONEY" then
        if not leaving then
            -- A real change, even to 0: no need to wait for the login
            -- retries.
            recorded = true
            Record(GetMoney() or 0)
        end
    elseif event == "PLAYER_LEAVING_WORLD" then
        leaving = true
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Back from a loading screen: read the gold again, as at login.
        if leaving then
            leaving = false
            recorded = false
            RecordAtLogin(0)
        end
    elseif event == "PLAYER_LOGOUT" then
        -- Also on /reload; the game saves right after. Only saved, not
        -- recorded: the game reports 0 gold by now (seen on Forever), and
        -- every real change already came as PLAYER_MONEY.
        Gold.Save()
    end
end)
