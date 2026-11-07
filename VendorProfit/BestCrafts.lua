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

local ADDON_NAME, ns = ...
local VendorProfit = ns.VendorProfit
local Recipes = VendorProfit.Recipes
local Route = VendorProfit.Route
local L = VendorProfit.L

local BestCrafts = {}
VendorProfit.BestCrafts = BestCrafts

BestCrafts.TOP = 5
BestCrafts.BATCH = 200          -- items per lookup
BestCrafts.LOOKUP_TIMEOUT = 15  -- seconds
BestCrafts.THROTTLE_POLL = 0.2

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

-- Ranks a profession's recipes. by = "vendor" or "auction". Returns up to
-- BestCrafts.TOP of { recipe, profit, cost, route } that make money, best
-- first, and whether some item info is still loading (onLoad is called when
-- it arrives). Recipes with a reagent that has no price anywhere are left
-- out, since their profit can't be trusted.
function BestCrafts.Rank(profession, by, onLoad)
    local ranked, loading = {}, false
    for _, recipe in ipairs(Recipes.ForProfession(profession)) do
        local route = Route.ForRecipe(recipe.item, recipe.reagents, Prices)
        if not route.missing then
            local cost = math.floor(route.cost + 0.5)
            local profit
            if by == "vendor" then
                local sellPrice = select(11, C_Item.GetItemInfo(recipe.item))
                if sellPrice == nil then
                    loading = true
                    if onLoad then
                        Item:CreateFromItemID(recipe.item):ContinueOnItemLoad(onLoad)
                    end
                elseif sellPrice > 0 then
                    profit = sellPrice * recipe.count - cost
                end
            else
                local _, auction = Prices(recipe.item)
                if auction then
                    profit = math.floor(auction * recipe.count * VendorProfit.GetAfterAHCut()) - cost
                end
            end
            if profit and profit > 0 then
                ranked[#ranked + 1] = { recipe = recipe, profit = profit, cost = cost, route = route }
            end
        end
    end
    table.sort(ranked, function(a, b)
        if a.profit ~= b.profit then
            return a.profit > b.profit
        end
        return a.recipe.recipeID < b.recipe.recipeID
    end)
    for index = #ranked, BestCrafts.TOP + 1, -1 do
        ranked[index] = nil
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

local function Finish(text, isError)
    scan = nil
    message, messageIsError = text, isError
    Changed()
end

local SendBatch

local function BatchDone()
    local current = scan
    for _, itemID in ipairs(current.batches[current.batch]) do
        current.live.checked[itemID] = true
    end
    current.batch = current.batch + 1
    if current.batch > #current.batches then
        current.live.time = time()
        live = current.live
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
    local batch = current.batch
    C_AuctionHouse.SearchForItemKeys(keys, SORTS)
    C_Timer.After(BestCrafts.LOOKUP_TIMEOUT, function()
        if scan == current and current.batch == batch and current.waiting then
            Finish(L.BEST_SCAN_FAILED, true)
        end
    end)
    Changed()
end

local function OnResults(event, added)
    local current = scan
    if current == nil or not current.waiting then
        return
    end
    local results = event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" and C_AuctionHouse.GetBrowseResults() or added
    if not AddResults(results) then
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
function BestCrafts.Scan(profession)
    if not BestCrafts.CanScan() or profession == nil then
        return
    end
    local itemIDs = BestCrafts.Items(profession)
    message = nil
    scan = { profession = profession, loading = true }
    Changed()
    local current = scan
    local pending = #itemIDs
    local function Start()
        if scan ~= current then
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
            Finish(L.BEST_NOTHING_TO_SCAN, true)
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
end

-- Scan progress: batch, batches (nil while item info loads).
function BestCrafts.Progress()
    if scan and scan.batches then
        return scan.batch, #scan.batches
    end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "AUCTION_HOUSE_CLOSED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
    if event == "AUCTION_HOUSE_CLOSED" then
        if scan then
            Finish(L.BEST_AH_CLOSED, true)
        end
        return
    end
    local args = { ... }
    xpcall(function() OnResults(event, args[1]) end, geterrorhandler())
end)
