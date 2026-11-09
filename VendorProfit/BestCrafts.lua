-- Best Crafts: the open profession's recipes ranked by profit per craft, each
-- along its cheapest route, sold to a vendor or at auction.
--
-- Ranking uses Auctionator's prices straight away. At the auction house,
-- Scan looks up live lowest prices for everything that matters to the
-- profession: every recipe's tree (Route.TreeItems) merged into one list of
-- unique items, looked up in batches with C_AuctionHouse.SearchForItemKeys,
-- the same batch query the auction house uses for favorites. That's a few
-- requests instead of one per item. The results are browse results, which
-- Auctionator also saves to its own prices while the auction house is open.
-- Items with nothing listed have no auction price until the next scan.
--
-- The crafting screen's Search uses the same lookup for one recipe's tree.

local ADDON_NAME, ns = ...
local VendorProfit = ns.VendorProfit
local Recipes = VendorProfit.Recipes
local Route = VendorProfit.Route
local L = VendorProfit.L

local BestCrafts = {}
VendorProfit.BestCrafts = BestCrafts

BestCrafts.BATCH = 100          -- items per lookup: the server's limit, more disconnects you
BestCrafts.LOOKUP_TIMEOUT = 15  -- seconds
BestCrafts.THROTTLE_POLL = 0.2
-- Browse results are shared with the auction house's own Browse tab and
-- other addons (TradeSkillMaster, Auctionator), which browse too, often as
-- the auction house opens. When their results replace ours, ours are sent
-- again this long after, rather than waiting out the timeout, at most
-- RESENDS times per batch. The same when the game drops a request.
BestCrafts.RESEND_DELAY = 1
BestCrafts.RESENDS = 2
-- Item info that never loads doesn't hold a lookup up longer than this.
BestCrafts.LOAD_TIMEOUT = 5

local BIND_ON_PICKUP = 1
local SORTS = { { sortOrder = 0, reverseSort = false } } -- by price

local live         -- { profession, prices = { [itemID] = lowest }, checked = { [itemID] = true }, time }
local scan         -- { profession, batches, batch, results, waiting } while scanning
local message, messageIsError

local listeners = {}
function BestCrafts.OnChange(fn)
    listeners[#listeners + 1] = fn
end
local function Changed()
    for _, fn in ipairs(listeners) do
        fn()
    end
end

function BestCrafts.IsScanning()
    return scan ~= nil
end

function BestCrafts.Message()
    return message, messageIsError
end

-- When live prices were last looked up for a profession, or nil.
function BestCrafts.LiveTime(profession)
    return live and live.profession == profession and live.time or nil
end

-- Prices for ranking: Auctionator's, with live lowest prices where looked up.
local function Prices(itemID)
    local vendor, auction = VendorProfit.GetBuyPrices(itemID)
    if live and live.checked[itemID] then
        auction = live.prices[itemID]
    end
    return vendor, auction
end
BestCrafts.Prices = Prices

-- Every unique item in the trees of a profession's recipes.
function BestCrafts.Items(profession)
    local items, seen = {}, {}
    for _, recipe in ipairs(Recipes.ForProfession(profession)) do
        for _, itemID in ipairs(Route.TreeItems(recipe.item, recipe.reagents)) do
            if not seen[itemID] then
                seen[itemID] = true
                items[#items + 1] = itemID
            end
        end
    end
    return items
end

-- The first item somewhere in a route with no price anywhere, or nil.
local function FirstUnpriced(children)
    for _, child in ipairs(children or {}) do
        local node = child.node
        if node.source == nil then
            return node.itemID
        elseif node.missing then
            local found = FirstUnpriced(node.children)
            if found then
                return found
            end
        end
    end
end

-- Ranks every saved recipe of a profession. by = "vendor" or "auction".
-- Returns a list of { recipe, profit, cost, route } best first, then the
-- recipes with no profit to rank, each with unpriced = why: { itemID = a
-- reagent with no price anywhere } (its profit can't be trusted), or
-- { output = true } (no vendor price, or no auction price, for what it
-- makes). Also returns whether some item info is still loading (onLoad is
-- called when it arrives).
function BestCrafts.Rank(profession, by, onLoad)
    local ranked, unranked, loading = {}, {}, false
    for _, recipe in ipairs(Recipes.ForProfession(profession)) do
        local route = Route.ForRecipe(recipe.item, recipe.reagents, Prices)
        local cost = math.floor(route.cost + 0.5)
        local entry = { recipe = recipe, cost = cost, route = route }
        if route.missing then
            entry.unpriced = { itemID = FirstUnpriced(route.children) }
        elseif by == "vendor" then
            local sellPrice = select(11, C_Item.GetItemInfo(recipe.item))
            if sellPrice == nil then
                loading = true
                if onLoad then
                    Item:CreateFromItemID(recipe.item):ContinueOnItemLoad(onLoad)
                end
                entry.unpriced = { output = true }
            elseif sellPrice > 0 then
                entry.profit = sellPrice * recipe.count - cost
            else
                entry.unpriced = { output = true }
            end
        else
            local _, auction = Prices(recipe.item)
            if auction then
                entry.profit = math.floor(auction * recipe.count * VendorProfit.GetAfterAHCut()) - cost
            else
                entry.unpriced = { output = true }
            end
        end
        if entry.profit then
            ranked[#ranked + 1] = entry
        else
            unranked[#unranked + 1] = entry
        end
    end
    -- Losses too: they rank below the crafts that make money.
    table.sort(ranked, function(a, b)
        if a.profit ~= b.profit then
            return a.profit > b.profit
        end
        return a.recipe.recipeID < b.recipe.recipeID
    end)
    for _, entry in ipairs(unranked) do
        ranked[#ranked + 1] = entry
    end
    return ranked, loading
end

-- Live lookup ------------------------------------------------------------------

local function AuctionHouseOpen()
    return AuctionHouseFrame ~= nil and AuctionHouseFrame:IsShown()
end

function BestCrafts.CanScan()
    return scan == nil and AuctionHouseOpen() and C_AuctionHouse.SearchForItemKeys ~= nil
end

-- Ends the scan. A profession scan's outcome shows on Best Crafts; a lookup
-- for one recipe's tree (Search) reports to its caller instead.
local function Finish(text, isError)
    local current = scan
    scan = nil
    if current and current.onDone then
        current.onDone(text, isError, current.live)
    else
        message, messageIsError = text, isError
    end
    Changed()
end

local SendBatch

local function BatchDone()
    local current = scan
    for _, itemID in ipairs(current.batches[current.batch]) do
        current.live.checked[itemID] = true
    end
    current.batch = current.batch + 1
    current.resends = 0
    if current.batch > #current.batches then
        if current.profession then
            current.live.time = time()
            live = current.live
        end
        Finish(L.BEST_SCANNED)
        return
    end
    SendBatch()
end

-- Adds browse results to the scan. Results for items outside this batch mean
-- they're someone else's (the auction house's own browsing): ignored.
local function AddResults(results)
    local current = scan
    local inBatch = current.inBatch
    for _, result in ipairs(results or {}) do
        local itemID = result.itemKey and result.itemKey.itemID
        if itemID == nil or not inBatch[itemID] then
            return false
        end
    end
    for _, result in ipairs(results or {}) do
        local itemID = result.itemKey.itemID
        if (result.totalQuantity or 0) > 0 and result.minPrice then
            local prices = current.live.prices
            prices[itemID] = math.min(prices[itemID] or result.minPrice, result.minPrice)
        end
    end
    return true
end

function SendBatch()
    local current = scan
    if current == nil then
        return
    end
    if not AuctionHouseOpen() then
        Finish(L.BEST_AH_CLOSED, true)
        return
    end
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then
        C_Timer.After(BestCrafts.THROTTLE_POLL, function()
            if scan == current then SendBatch() end
        end)
        return
    end
    local items = current.batches[current.batch]
    local keys, inBatch = {}, {}
    for _, itemID in ipairs(items) do
        keys[#keys + 1] = C_AuctionHouse.MakeItemKey(itemID)
        inBatch[itemID] = true
    end
    current.inBatch = inBatch
    current.waiting = true
    current.sends = (current.sends or 0) + 1
    local sent = current.sends
    C_AuctionHouse.SearchForItemKeys(keys, SORTS)
    C_Timer.After(BestCrafts.LOOKUP_TIMEOUT, function()
        if scan == current and current.sends == sent and current.waiting then
            Finish(L.BEST_SCAN_FAILED, true)
        end
    end)
    Changed()
end

-- Our results were replaced, or the request dropped: send the batch again
-- soon, unless an answer comes first.
local function Resend()
    local current = scan
    if current == nil or not current.waiting or (current.resends or 0) >= BestCrafts.RESENDS then
        return
    end
    current.resends = (current.resends or 0) + 1
    local sent = current.sends
    C_Timer.After(BestCrafts.RESEND_DELAY, function()
        if scan == current and current.sends == sent and current.waiting then
            SendBatch()
        end
    end)
end

local function OnResults(event, added)
    local current = scan
    if current == nil or not current.waiting then
        return
    end
    local results = event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" and C_AuctionHouse.GetBrowseResults() or added
    if not AddResults(results) then
        -- Someone else's browse: it may have replaced ours.
        Resend()
        return
    end
    if C_AuctionHouse.HasFullBrowseResults and not C_AuctionHouse.HasFullBrowseResults() then
        C_AuctionHouse.RequestMoreBrowseResults()
        return
    end
    current.waiting = false
    BatchDone()
end

-- Scan button: looks up live lowest prices for a profession's items.
-- Looks up live lowest prices for itemIDs in batches. With a profession,
-- they become Best Crafts' live prices; with onDone(text, isError) instead,
-- the caller hears how it went (Auctionator saves what's found either way).
local function LookUp(itemIDs, profession, onDone)
    if profession then
        message = nil
    end
    scan = { profession = profession, onDone = onDone, loading = true }
    Changed()
    local current = scan
    local pending = #itemIDs
    local function Start()
        if scan ~= current or not current.loading then
            return
        end
        -- Only items that can be listed.
        local listable = {}
        for _, itemID in ipairs(itemIDs) do
            local bindType = select(14, C_Item.GetItemInfo(itemID))
            if bindType ~= BIND_ON_PICKUP then
                listable[#listable + 1] = itemID
            end
        end
        if #listable == 0 then
            Finish(current.profession and L.BEST_NOTHING_TO_SCAN or L.SEARCH_NOTHING, true)
            return
        end
        current.batches = {}
        for index = 1, #listable, BestCrafts.BATCH do
            local batch = {}
            for i = index, math.min(index + BestCrafts.BATCH - 1, #listable) do
                batch[#batch + 1] = listable[i]
            end
            current.batches[#current.batches + 1] = batch
        end
        current.batch = 1
        current.loading = false
        current.live = { profession = profession, prices = {}, checked = {} }
        SendBatch()
    end
    if pending == 0 then
        Start()
        return
    end
    for _, itemID in ipairs(itemIDs) do
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
            pending = pending - 1
            if pending == 0 then
                Start()
            end
        end)
    end
    -- Some item's info never came: go on without waiting for it.
    C_Timer.After(BestCrafts.LOAD_TIMEOUT, Start)
end

function BestCrafts.Scan(profession)
    if not BestCrafts.CanScan() or profession == nil then
        return
    end
    LookUp(BestCrafts.Items(profession), profession)
end

-- Looks up live prices for some items (one recipe's tree for Search, an
-- order's for the shopping scan), in one batch request rather than a search
-- per item. onDone(text, isError, live): live.prices[itemID] is the lowest
-- unit price listed, and live.checked[itemID] is true for every item looked
-- up (so checked but no price means nothing listed). live may be nil or
-- partial if the lookup failed.
function BestCrafts.LookUpItems(itemIDs, onDone)
    if not BestCrafts.CanScan() then
        return false
    end
    LookUp(itemIDs, nil, onDone)
    return true
end

-- What's being scanned: a profession's key, or "items" for LookUpItems.
function BestCrafts.Scanning()
    return scan and (scan.profession or "items")
end

-- Scan progress: batch, batches (nil while item info loads).
function BestCrafts.Progress()
    if scan and scan.batches then
        return scan.batch, #scan.batches
    end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
    if event == "AUCTION_HOUSE_CLOSED" then
        if scan then
            Finish(L.BEST_AH_CLOSED, true)
        end
        return
    end
    if event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
        Resend()
        return
    end
    local args = { ... }
    xpcall(function() OnResults(event, args[1]) end, geterrorhandler())
end)
