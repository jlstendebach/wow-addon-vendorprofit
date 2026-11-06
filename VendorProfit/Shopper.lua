-- Shopping for the order at the auction house: scanning listings, pricing
-- the order with them, and buying one item at a time.
--
-- Scanning reads every listing of each item the plan buys at auction, so a
-- purchase of 24 is priced by walking up the cheapest listings, not at the
-- single lowest price. With live prices the order is planned again: if
-- crafting something has become cheaper than buying it, or the other way
-- round, the plan changes and any new items are scanned too.
--
-- Buying stackable items ("commodities", such as ore, bars and cloth) takes
-- two clicks, the same flow as Auctionator's and Blizzard's own:
--   Buy      asks the game for a price quote for the amount
--   Confirm  buys at that quote
-- The game only allows the purchase as part of a click. Before Confirm is
-- offered, the quote is checked against the scanned price; if it's higher,
-- the purchase is cancelled and the item scanned again. Each purchase also
-- needs finishing the order to still be profitable, unless you choose Buy
-- anyway.
--
-- Items that don't stack (gear and the like) are listed but not bought here:
-- buy those yourself.

local _, ns = ...
local VendorProfit = ns.VendorProfit
local Order = VendorProfit.Order
local L = VendorProfit.L

local Shopper = {}
VendorProfit.Shopper = Shopper

Shopper.SEARCH_TIMEOUT = 10
Shopper.SEARCH_RETRIES = 3
Shopper.MORE_RESULTS_REQUESTS = 3
Shopper.QUOTE_TIMEOUT = 10
Shopper.PURCHASE_TIMEOUT = 15
Shopper.THROTTLE_POLL = 0.2
-- Planning passes with live prices before settling.
Shopper.PLAN_PASSES = 4

local SORTS = { { sortOrder = 0, reverseSort = false } } -- by price, cheapest first

-- State ----------------------------------------------------------------------

-- status:
--   "closed"    auction house not open
--   "idle"      open, not scanned yet
--   "scanning"  reading listings
--   "ready"     scanned; Buy is available if there's something to buy
--   "quoting"   waiting for the game's price quote
--   "confirm"   quote is within budget; waiting for Confirm
--   "buying"    waiting for the purchase to go through
local status = "closed"
local message, messageIsError
local listings = {}     -- itemID -> { commodity = bool, rows = { { unitPrice, quantity }, ... } }
local scanQueue = {}    -- itemIDs waiting to be scanned
local scanTotal = 0     -- items in this scan, for "Scanning 2 of 5"
local scanDone = 0
local scanning          -- { itemID, tries, moreRequests }; callbacks for an older scan see it changed
local failed = {}       -- itemIDs whose scan failed this time, so they aren't retried in a loop
local purchase          -- { itemID, quantity, budget, quote }
local unanswered        -- a confirmed purchase that timed out; recorded if it succeeds late
local override = false  -- Buy anyway: buy even when the order isn't profitable
local summary           -- see Shopper.Summary

local listeners = {}
function Shopper.OnChange(fn)
    listeners[#listeners + 1] = fn
end
local function Changed()
    for _, fn in ipairs(listeners) do
        fn()
    end
end

local function SetMessage(text, isError)
    message, messageIsError = text, isError or false
end

function Shopper.Status()
    return status
end

function Shopper.Message()
    return message, messageIsError
end

function Shopper.IsOpen()
    return status ~= "closed"
end

function Shopper.ScanProgress()
    return scanDone, scanTotal
end

function Shopper.Purchase()
    return purchase
end

-- Listings -------------------------------------------------------------------

-- Walks the cheapest listings for up to quantity. Returns total cost and how
-- many are listed (at most quantity).
function Shopper.Walk(listing, quantity)
    local total, got = 0, 0
    for _, row in ipairs(listing.rows) do
        if got >= quantity then
            break
        end
        local take = math.min(row.quantity, quantity - got)
        total = total + take * row.unitPrice
        got = got + take
    end
    return total, got
end

local function ListedQuantity(listing)
    local n = 0
    for _, row in ipairs(listing.rows) do
        n = n + row.quantity
    end
    return n
end

-- Removes what was just bought from the front of the listings.
local function ConsumeListings(listing, quantity)
    while quantity > 0 and #listing.rows > 0 do
        local row = listing.rows[1]
        local take = math.min(row.quantity, quantity)
        row.quantity = row.quantity - take
        quantity = quantity - take
        if row.quantity <= 0 then
            table.remove(listing.rows, 1)
        end
    end
end

function Shopper.Listing(itemID)
    return listings[itemID]
end

-- Prices for planning: the vendor price as usual, and for scanned stackable
-- items the average price of buying `need` of them now (nil if none listed,
-- so the plan crafts or uses a vendor instead).
local function LivePrices(need)
    return function(itemID)
        local vendor, auction = VendorProfit.GetBuyPrices(itemID)
        local listing = listings[itemID]
        if listing and listing.commodity then
            local total, got = Shopper.Walk(listing, need[itemID] or 1)
            auction = got > 0 and total / got or nil
        end
        return vendor, auction
    end
end

-- Planning and pricing -------------------------------------------------------

-- Summary of the order at the best prices known (live where scanned):
--   plan           Order.Plan's plan
--   revenue        vendor sale value of everything still queued
--   ownedValue     what the items you have that the plan uses are worth
--   remaining      cost of what's left to buy
--   profit         revenue - ownedValue - remaining: what finishing the
--                  order makes from here. Items you have count at what they'd
--                  cost to get now, whether you had them or bought them for
--                  this order; what was paid before is spent either way.
--   spent          what the panel has spent on this order, for reference
--   unscanned      auction items not scanned yet
--   short          auction items with fewer listed than needed
-- Each auction buy line also gets: total (cost now), listed (how many can be
-- bought), manual (true for items that don't stack), unscanned.
function Shopper.Recompute()
    local need = {}
    local plan
    for _ = 1, Shopper.PLAN_PASSES do
        plan = Order.Plan(LivePrices(need))
        local newNeed, same = {}, true
        for _, line in ipairs(plan.buyOrder) do
            newNeed[line.itemID] = line.quantity
            if need[line.itemID] ~= line.quantity then
                same = false
            end
        end
        for itemID in pairs(need) do
            if newNeed[itemID] == nil then
                same = false
            end
        end
        if same then
            break
        end
        need = newNeed
    end

    local remaining, unscanned, short = 0, {}, {}
    for _, line in ipairs(plan.buyOrder) do
        local listing = listings[line.itemID]
        if line.source == "auction" and listing and listing.commodity then
            line.total, line.listed = Shopper.Walk(listing, line.quantity)
            if line.listed < line.quantity then
                short[#short + 1] = line
            end
        else
            line.total = (line.unitPrice or 0) * line.quantity
            line.listed = nil
            if line.source == "auction" then
                if listing then
                    line.manual = true
                else
                    line.unscanned = true
                    unscanned[#unscanned + 1] = line.itemID
                end
            end
        end
        remaining = remaining + line.total
    end

    local spent = Order.Spent()
    summary = {
        plan = plan,
        revenue = plan.revenue,
        spent = spent,
        ownedValue = plan.ownedValue,
        remaining = remaining,
        profit = plan.revenue - plan.ownedValue - remaining,
        unscanned = unscanned,
        short = short,
    }
    return summary
end

function Shopper.Summary()
    return summary or Shopper.Recompute()
end

-- The next purchase: the first stackable auction item still needed, as much
-- as is listed. Returns { itemID, quantity, budget } or nil.
function Shopper.NextPurchase()
    local s = Shopper.Summary()
    for _, line in ipairs(s.plan.buyOrder) do
        local listing = listings[line.itemID]
        if line.source == "auction" and listing and listing.commodity and line.quantity > 0 then
            local quantity = math.min(line.quantity, ListedQuantity(listing))
            if quantity > 0 then
                local budget = Shopper.Walk(listing, quantity)
                return { itemID = line.itemID, quantity = quantity, budget = budget }
            end
        end
    end
    return nil
end

function Shopper.CanBuy()
    return status == "ready" and Shopper.NextPurchase() ~= nil
end

function Shopper.IsProfitable()
    return Shopper.Summary().profit >= 0
end

function Shopper.IsOverridden()
    return override
end

function Shopper.SetOverride(value)
    override = value and true or false
    Changed()
end

-- Scanning -------------------------------------------------------------------

local ScanNext

local function ItemName(itemID)
    return C_Item.GetItemInfo(itemID) or ("item " .. itemID)
end

local function FinishScanItem(itemID, listing)
    listings[itemID] = listing
    if listing == nil then
        failed[itemID] = true
    end
    scanning = nil
    scanDone = scanDone + 1
    ScanNext()
end

-- Reads the commodity results for the item being scanned. Asks for more
-- results when not all are loaded and they may be needed.
local function ReadCommodityResults(itemID)
    local rows = {}
    for index = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
        local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
        if info and info.unitPrice and info.quantity then
            -- Your own listings can't be bought.
            local own = info.numOwnerItems or ((info.containsOwnerItem or info.containsAccountItem) and info.quantity) or 0
            local quantity = info.quantity - own
            if quantity > 0 then
                rows[#rows + 1] = { unitPrice = info.unitPrice, quantity = quantity }
            end
        end
    end
    table.sort(rows, function(a, b) return a.unitPrice < b.unitPrice end)
    return rows
end

local function SendSearch()
    local current = scanning
    if current == nil then
        return
    end
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then
        C_Timer.After(Shopper.THROTTLE_POLL, function()
            if scanning == current then SendSearch() end
        end)
        return
    end
    current.tries = current.tries + 1
    C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(current.itemID), SORTS, false)
    local tries = current.tries
    C_Timer.After(Shopper.SEARCH_TIMEOUT, function()
        if scanning == current and current.tries == tries then
            if current.tries < Shopper.SEARCH_RETRIES then
                SendSearch()
            else
                SetMessage(string.format(L.SCAN_FAILED, ItemName(current.itemID)), true)
                FinishScanItem(current.itemID, nil)
            end
        end
    end)
end

function ScanNext()
    if status ~= "scanning" then
        return
    end
    local itemID = table.remove(scanQueue, 1)
    if itemID == nil then
        -- Planning with the new prices may need items not scanned yet.
        local s = Shopper.Recompute()
        for _, id in ipairs(s.unscanned) do
            if not failed[id] then
                scanQueue[#scanQueue + 1] = id
                scanTotal = scanTotal + 1
            end
        end
        if #scanQueue > 0 then
            ScanNext()
            return
        end
        status = "ready"
        Changed()
        return
    end

    scanning = { itemID = itemID, tries = 0, moreRequests = 0 }
    Changed()
    local current = scanning
    -- The game ignores searches for items it hasn't loaded yet.
    Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
        if scanning == current then
            SendSearch()
        end
    end)
end

-- Scans every item the order buys at auction.
function Shopper.Scan()
    if status ~= "idle" and status ~= "ready" then
        return
    end
    listings = {}
    failed = {}
    override = false
    SetMessage(nil)
    local s = Shopper.Recompute()
    scanQueue = {}
    for _, line in ipairs(s.plan.buyOrder) do
        if line.source == "auction" then
            scanQueue[#scanQueue + 1] = line.itemID
        end
    end
    scanTotal, scanDone = #scanQueue, 0
    status = "scanning"
    ScanNext()
end

-- Scans one item again (after a price change or failed purchase).
local function Rescan(itemID)
    listings[itemID] = nil
    failed[itemID] = nil
    scanQueue = { itemID }
    scanTotal, scanDone = 1, 0
    status = "scanning"
    ScanNext()
end

-- Buying ---------------------------------------------------------------------

local function EndPurchase(newStatus)
    purchase = nil
    status = newStatus or "ready"
    Shopper.Recompute()
    Changed()
end

-- Buy click: asks for a price quote for the next purchase.
function Shopper.Buy()
    if status ~= "ready" then
        return
    end
    local nextPurchase = Shopper.NextPurchase()
    if nextPurchase == nil then
        return
    end
    if not Shopper.IsProfitable() and not override then
        SetMessage(L.NOT_PROFITABLE_STOPPED, true)
        Changed()
        return
    end
    if GetMoney() < nextPurchase.budget then
        SetMessage(L.NOT_ENOUGH_GOLD, true)
        Changed()
        return
    end
    purchase = nextPurchase
    status = "quoting"
    SetMessage(nil)
    Order.BeforePurchase(purchase.itemID)
    C_AuctionHouse.StartCommoditiesPurchase(purchase.itemID, purchase.quantity)
    local current = purchase
    C_Timer.After(Shopper.QUOTE_TIMEOUT, function()
        if purchase == current and status == "quoting" then
            C_AuctionHouse.CancelCommoditiesPurchase()
            SetMessage(string.format(L.NO_QUOTE, ItemName(current.itemID)), true)
            EndPurchase("ready")
        end
    end)
    Changed()
end

-- Confirm click: buys at the quote.
function Shopper.Confirm()
    if status ~= "confirm" or purchase == nil then
        return
    end
    status = "buying"
    C_AuctionHouse.ConfirmCommoditiesPurchase(purchase.itemID, purchase.quantity)
    local current = purchase
    C_Timer.After(Shopper.PURCHASE_TIMEOUT, function()
        if purchase == current and status == "buying" then
            -- No answer yet: not recorded, but remembered in case the
            -- success arrives late. Scanning again shows what's left.
            SetMessage(string.format(L.NO_PURCHASE_REPLY, ItemName(current.itemID)), true)
            unanswered = current
            purchase = nil
            Rescan(current.itemID)
        end
    end)
    Changed()
end

-- Cancel click: drops the quote.
function Shopper.Cancel()
    if status ~= "quoting" and status ~= "confirm" then
        return
    end
    C_AuctionHouse.CancelCommoditiesPurchase()
    SetMessage(nil)
    EndPurchase("ready")
end

local function OnPriceUpdated(unitPrice, totalPrice)
    if purchase == nil or (status ~= "quoting" and status ~= "confirm") then
        return
    end
    if totalPrice <= purchase.budget then
        purchase.quote = totalPrice
        status = "confirm"
        Changed()
        return
    end
    -- More than scanned: someone bought the cheap ones first.
    C_AuctionHouse.CancelCommoditiesPurchase()
    local itemID = purchase.itemID
    SetMessage(string.format(L.PRICE_WENT_UP, ItemName(itemID),
        VendorProfit.FormatMoney(purchase.budget), VendorProfit.FormatMoney(totalPrice)), true)
    purchase = nil
    Rescan(itemID)
end

local function OnPriceUnavailable()
    if purchase == nil or (status ~= "quoting" and status ~= "confirm") then
        return
    end
    local itemID = purchase.itemID
    SetMessage(string.format(L.PRICE_UNAVAILABLE, ItemName(itemID)), true)
    purchase = nil
    Rescan(itemID)
end

local function OnPurchaseSucceeded()
    if (purchase == nil or status ~= "buying") and unanswered then
        -- A purchase that timed out went through after all.
        local late = unanswered
        unanswered = nil
        Order.RecordPurchase(late.itemID, late.quantity, late.quote)
        SetMessage(string.format(L.BOUGHT, late.quantity, ItemName(late.itemID), VendorProfit.FormatMoney(late.quote)))
        Shopper.Recompute()
        Changed()
        return
    end
    if purchase == nil or status ~= "buying" then
        return
    end
    unanswered = nil
    local bought = purchase
    Order.RecordPurchase(bought.itemID, bought.quantity, bought.quote)
    local listing = listings[bought.itemID]
    if listing then
        ConsumeListings(listing, bought.quantity)
    end
    SetMessage(string.format(L.BOUGHT, bought.quantity, ItemName(bought.itemID), VendorProfit.FormatMoney(bought.quote)))
    EndPurchase("ready")
end

local function OnPurchaseFailed()
    if purchase == nil or status ~= "buying" then
        unanswered = nil
        return
    end
    local itemID = purchase.itemID
    SetMessage(string.format(L.PURCHASE_FAILED, ItemName(itemID)), true)
    purchase = nil
    Rescan(itemID)
end

-- Search results ---------------------------------------------------------------

local function OnCommodityResults(itemID)
    local current = scanning
    if current == nil or current.itemID ~= itemID then
        return
    end
    local itemKey = C_AuctionHouse.MakeItemKey(itemID)
    local full = C_AuctionHouse.HasFullCommoditySearchResults(itemID)
    -- Sometimes the game answers with nothing loaded although there are
    -- listings; ask again.
    if not C_AuctionHouse.HasSearchResults(itemKey)
        or (not full and C_AuctionHouse.GetNumCommoditySearchResults(itemID) == 0) then
        if current.tries < Shopper.SEARCH_RETRIES then
            SendSearch()
        else
            FinishScanItem(itemID, { commodity = true, rows = {} })
        end
        return
    end

    local rows = ReadCommodityResults(itemID)
    local listing = { commodity = true, rows = rows }
    local line = Shopper.Summary().plan.buy[itemID]
    local needed = line and line.quantity or 1
    if not full and ListedQuantity(listing) < needed and current.moreRequests < Shopper.MORE_RESULTS_REQUESTS then
        current.moreRequests = current.moreRequests + 1
        C_AuctionHouse.RequestMoreCommoditySearchResults(itemID)
        return
    end
    FinishScanItem(itemID, listing)
end

local function OnItemResults(itemKey)
    local current = scanning
    if current == nil or type(itemKey) ~= "table" or itemKey.itemID ~= current.itemID then
        return
    end
    -- Doesn't stack: listed for you to buy yourself.
    FinishScanItem(current.itemID, { commodity = false, rows = {} })
end

-- Auction house open and close ------------------------------------------------------

local function Opened()
    if status ~= "closed" then
        return
    end
    status = "idle"
    SetMessage(nil)
    Shopper.Recompute()
    Changed()
end

local function Closed()
    if status == "closed" then
        return
    end
    if status == "buying" then
        -- Already confirmed: it may still go through.
        unanswered = purchase
    elseif purchase then
        C_AuctionHouse.CancelCommoditiesPurchase()
    end
    status = "closed"
    purchase, scanning = nil, nil
    scanQueue = {}
    listings = {}
    override = false
    SetMessage(nil)
    Shopper.Recompute()
    Changed()
end

local AUCTIONEER = Enum.PlayerInteractionType and Enum.PlayerInteractionType.Auctioneer

local events = CreateFrame("Frame")
for _, event in ipairs({
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED", "ITEM_SEARCH_RESULTS_UPDATED",
    "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
    "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED",
}) do
    -- One at a time, so an event this client doesn't have can't stop the rest.
    pcall(events.RegisterEvent, events, event)
end

local handlers = {
    PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(kind) if kind == AUCTIONEER then Opened() end end,
    PLAYER_INTERACTION_MANAGER_FRAME_HIDE = function(kind) if kind == AUCTIONEER then Closed() end end,
    AUCTION_HOUSE_SHOW = Opened,
    AUCTION_HOUSE_CLOSED = Closed,
    COMMODITY_SEARCH_RESULTS_UPDATED = OnCommodityResults,
    COMMODITY_SEARCH_RESULTS_ADDED = function(itemID)
        OnCommodityResults(itemID or (scanning and scanning.itemID))
    end,
    ITEM_SEARCH_RESULTS_UPDATED = OnItemResults,
    COMMODITY_PRICE_UPDATED = OnPriceUpdated,
    COMMODITY_PRICE_UNAVAILABLE = OnPriceUnavailable,
    COMMODITY_PURCHASE_SUCCEEDED = OnPurchaseSucceeded,
    COMMODITY_PURCHASE_FAILED = OnPurchaseFailed,
}

events:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then
        local args = { ... }
        local n = select("#", ...)
        xpcall(function() handler(unpack(args, 1, n)) end, geterrorhandler())
    end
end)

-- Plans change when the order or what you have changes.
Order.OnChange(function()
    if status == "ready" or status == "idle" or status == "closed" then
        Shopper.Recompute()
    end
    Changed()
end)
