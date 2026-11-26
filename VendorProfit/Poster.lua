-- Posting at the auction house: the Shopping List's Post Queue and Post
-- step. Queued items, once in your bags, are posted at the lowest price
-- listed, one click an item (the queued count at once), the way Josh posts
-- by hand:
--
--   * Price: one search for the item. The answer sometimes never comes, so
--     after SEARCH_TIMEOUT it's asked again (SEARCH_RETRIES in all).
--   * The lowest price listed, matched (no undercut), unless it looks like
--     bait: at most SUSPICIOUS_COUNT items at it and SUSPICIOUS_GAP below
--     the next price up. Then the next price, up to SUSPICIOUS_SKIPS times.
--   * Nothing listed: the last price Auctionator saw, x gold, posted at
--     x + min(x, x^0.7) (1g -> 2g, 3g -> 5g, 10g -> 15g, 30g -> 40g: Josh's
--     own examples). Never seen: skipped, saying so.
--   * Below what the item cost you (after the auction house's cut): Post
--     turns red and needs a second click.
--   * The shortest duration, unless you last posted the item for longer
--     (see Durations), the queued count in one post. The game posts a
--     number of items that don't stack in one go (Auctionator's multisell
--     does the same), so it's one click for those too.
--
-- The game only posts as part of a click, so each post is a click on Post;
-- the price lookups in between happen by themselves.
--
-- What's queued to post: what the order crafts (Order.Crafted: the
-- outputs of queued recipes, not the reagents crafted on the way, and not
-- recipes queued from Best Crafts' Vendor tab, meant for a vendor), and
-- auctions that come back by mail, expired or cancelled (History.lua), as
-- many as made or returned. The Post Queue section changes the counts (up
-- to what's in your bags) or removes an item (to keep it). Saved per
-- character in VendorProfitCharDB.postQueue = { { itemID, count }, ... },
-- first in, first out.

local ADDON_NAME, ns = ...
local VendorProfit = ns.VendorProfit
local L = VendorProfit.L

local Poster = {}
VendorProfit.Poster = Poster

Poster.SEARCH_TIMEOUT = 3
Poster.SEARCH_RETRIES = 3
Poster.POST_TIMEOUT = 15
Poster.THROTTLE_POLL = 0.2
-- The shortest duration, as the game numbers them (1, 2, 3, shortest
-- first; 2 hours on Forever's auction house, 12 on retail's): the default.
Poster.DURATION = 1
Poster.SUSPICIOUS_COUNT = 3
Poster.SUSPICIOUS_GAP = 0.8
Poster.SUSPICIOUS_SKIPS = 2
-- How many of the cheapest prices the Post step shows, for a gut check.
Poster.LISTED_SHOWN = 4

local SORTS = { { sortOrder = 0, reverseSort = false } } -- by price, cheapest first

-- status:
--   "closed"   auction house not open
--   "idle"     open, nothing priced yet
--   "pricing"  looking up the current item's price
--   "ready"    priced: Post is offered
--   "posting"  waiting for the items to leave your bags
local status = "closed"
-- The item being priced or posted: { itemID, tries, commodity, price,
-- listed (the cheapest few prices, { price, quantity }), skipped (how many
-- of them were passed over as bait), guess (last known price, when
-- nothing's listed), cost (per item), armed (below cost, clicked once),
-- before, quantity, left, progress (posting) }.
local current
local message, messageIsError

local listeners = {}
function Poster.OnChange(fn)
    listeners[#listeners + 1] = fn
end

local function Changed()
    for _, fn in ipairs(listeners) do
        xpcall(fn, geterrorhandler())
    end
end

local function SetMessage(text, isError)
    message, messageIsError = text, isError and true or nil
end

function Poster.Status()
    return status
end

function Poster.Current()
    return current
end

function Poster.Message()
    return message, messageIsError
end

local function ItemName(itemID)
    return C_Item.GetItemInfo(itemID) or ("item " .. itemID)
end

local function InBags(itemID)
    return C_Item.GetItemCount(itemID) or 0
end

-- The queue, in posting order. (An earlier version kept a set of items to
-- post all of: each is queued at what's in your bags.)
local function Queue()
    VendorProfitCharDB = VendorProfitCharDB or {}
    local db = VendorProfitCharDB
    if db.postQueue == nil then
        db.postQueue = {}
        local old = {}
        for itemID in pairs(db.toPost or {}) do
            old[#old + 1] = itemID
        end
        table.sort(old)
        for _, itemID in ipairs(old) do
            db.postQueue[#db.postQueue + 1] = { itemID = itemID, count = InBags(itemID) }
        end
        db.toPost = nil
    end
    return db.postQueue
end

local function Find(itemID)
    for index, entry in ipairs(Queue()) do
        if entry.itemID == itemID then
            return index, entry
        end
    end
end

-- Queues count more of an item to post (at the end if it's new).
function Poster.Add(itemID, count)
    if count == nil or count <= 0 then
        return
    end
    local _, entry = Find(itemID)
    if entry then
        entry.count = entry.count + count
    else
        table.insert(Queue(), { itemID = itemID, count = count })
    end
    Changed()
end

-- What the order crafted: made of the item, to post.
function Poster.Crafted(itemID, made)
    Poster.Add(itemID, made or 1)
end

-- An auction that came back by mail, expired or cancelled: n of the item.
function Poster.Returned(itemID, n)
    Poster.Add(itemID, n or 1)
end

-- Durations --------------------------------------------------------------------

-- How long you last posted each item for, so the Post step posts it the
-- same way: watched on every post, whoever makes it (the game's Sell tab,
-- Auctionator, the Post step), since the game passes the duration in. An
-- auction mailed back doesn't say how long it was up. Only the longer ones
-- are kept (VendorProfitCharDB.postDurations[itemID] = duration); posting
-- an item at the default forgets it, so going back to 2 hours sticks.
local function Durations()
    VendorProfitCharDB = VendorProfitCharDB or {}
    VendorProfitCharDB.postDurations = VendorProfitCharDB.postDurations or {}
    return VendorProfitCharDB.postDurations
end

function Poster.Duration(itemID)
    return Durations()[itemID] or Poster.DURATION
end

local function Remember(location, duration)
    if type(duration) ~= "number" or location == nil then
        return
    end
    local ok, itemID = pcall(C_Item.GetItemID, location)
    if not ok or itemID == nil then
        return
    end
    Durations()[itemID] = duration ~= Poster.DURATION and duration or nil
end

hooksecurefunc(C_AuctionHouse, "PostItem", function(location, duration) Remember(location, duration) end)
hooksecurefunc(C_AuctionHouse, "PostCommodity", function(location, duration) Remember(location, duration) end)

-- The game's name for a duration ("8 Hours"), or nil.
local DURATION_NAMES = { "AUCTION_DURATION_ONE", "AUCTION_DURATION_TWO", "AUCTION_DURATION_THREE" }
function Poster.DurationName(duration)
    local name = DURATION_NAMES[duration]
    return name and _G[name] or nil
end

-- Takes count off an item's queued count (after posting them); off the
-- queue at none.
local function Take(itemID, count)
    local index, entry = Find(itemID)
    if entry then
        entry.count = entry.count - count
        if entry.count <= 0 then
            table.remove(Queue(), index)
        end
    end
end

-- Swaps up to count of one item waiting to be posted for another (handed
-- in for it: Thorium Shells for arrows), at the end of the queue.
function Poster.Swap(fromItem, toItem, count)
    local _, entry = Find(fromItem)
    if entry then
        local n = math.min(entry.count, count)
        Take(fromItem, n)
        Poster.Add(toItem, n)
    end
end

-- Forgets an item, to keep it (the Post Queue's x).
function Poster.Remove(itemID)
    local index = Find(itemID)
    if index then
        table.remove(Queue(), index)
        if current and current.itemID == itemID and status ~= "posting" then
            current = nil
            if status ~= "closed" then
                status = "idle"
            end
        end
        Changed()
    end
end

-- Sets how many of an item to post: at least 1, at most what's in your
-- bags (the Post Queue's - and +).
function Poster.SetCount(itemID, count)
    local _, entry = Find(itemID)
    if entry then
        entry.count = math.max(1, math.min(count, InBags(itemID)))
        Changed()
    end
end

-- What's queued and in your bags, in posting order: { { itemID, count (to
-- post: the queued count, or what's in your bags if fewer), queued, bags } }.
function Poster.Items()
    local list = {}
    for _, entry in ipairs(Queue()) do
        local bags = InBags(entry.itemID)
        if bags > 0 then
            list[#list + 1] = { itemID = entry.itemID, count = math.min(entry.count, bags),
                queued = entry.count, bags = bags }
        end
    end
    return list
end

-- Pricing ------------------------------------------------------------------------

-- A price for an item with nothing listed, from its last known price x
-- (in gold): f(x) = x + min(x, x^0.7). The step grows with the price but
-- more slowly, so it's a smaller share of a dearer item; under 1g, where
-- x^0.7 would be more than x, it's at most double. Then cut down to whole
-- gold (whole silver under a gold). It fits Josh's examples exactly:
-- 1g -> 2g, 3g -> 5g, 10g -> 15g, 30g -> 40g. A smooth formula on purpose,
-- not a table of price bands.
function Poster.Guess(last)
    local gold = last / 10000
    local price = (gold + math.min(gold, gold ^ 0.7)) * 10000
    if price >= 10000 then
        return math.floor(price / 10000) * 10000
    elseif price >= 100 then
        return math.floor(price / 100) * 100
    end
    return math.floor(price)
end

-- The price to post at from the listings, cheapest first, as { price,
-- quantity } per price: the lowest, unless at most SUSPICIOUS_COUNT items
-- are at it and it's SUSPICIOUS_GAP below the next; then the next, up to
-- SUSPICIOUS_SKIPS times. Returns the price and how many prices it passed.
function Poster.Choose(groups)
    local index = 1
    while index <= Poster.SUSPICIOUS_SKIPS and groups[index + 1]
        and groups[index].quantity <= Poster.SUSPICIOUS_COUNT
        and groups[index].price < groups[index + 1].price * Poster.SUSPICIOUS_GAP do
        index = index + 1
    end
    return groups[index].price, index - 1
end

-- Listings as { price, quantity } per price, cheapest first. Yours count:
-- matching your own price is matching the market.
local function Groups(rows)
    local byPrice = {}
    for _, row in ipairs(rows) do
        byPrice[row.price] = (byPrice[row.price] or 0) + row.quantity
    end
    local groups = {}
    for price, quantity in pairs(byPrice) do
        groups[#groups + 1] = { price = price, quantity = quantity }
    end
    table.sort(groups, function(a, b) return a.price < b.price end)
    return groups
end

-- Sets the current item's price from its listings (rows of { price,
-- quantity }), or from its last known price when nothing's listed.
local function Priced(rows)
    local item = current
    item.cost = VendorProfit.History.UnitCost(item.itemID)
    local groups = Groups(rows)
    -- The cheapest few, for a gut check under the price (the Post step).
    item.listed = {}
    for index = 1, math.min(#groups, Poster.LISTED_SHOWN) do
        item.listed[index] = groups[index]
    end
    if #groups > 0 then
        item.price, item.skipped = Poster.Choose(groups)
    else
        local last = Auctionator.API.v1.GetAuctionPriceByItemID(ADDON_NAME, item.itemID)
        if last == nil or last <= 0 then
            -- Nothing to go on: left for you to price.
            -- Off the queue: you'll have to post it yourself.
            SetMessage(string.format(L.POST_NO_PRICE, ItemName(item.itemID)), true)
            local index = Find(item.itemID)
            if index then
                table.remove(Queue(), index)
            end
            current = nil
            Poster.PriceNext()
            return
        end
        item.guess = last
        item.price = Poster.Guess(last)
    end
    status = "ready"
    Changed()
end

-- Whether the current price is under what the item cost you, after the
-- auction house's cut.
function Poster.BelowCost()
    return current ~= nil and current.price ~= nil and current.cost ~= nil
        and current.price * VendorProfit.GetAfterAHCut() < current.cost
end

local function Search()
    local item = current
    if item == nil or status ~= "pricing" then
        return
    end
    -- The game drops searches while it's busy, and the server limits them
    -- (shared with buying: VendorProfit.Shopper).
    local wait = VendorProfit.Shopper.SearchWait()
    if not C_AuctionHouse.IsThrottledMessageSystemReady() or wait > 0 then
        C_Timer.After(math.max(wait, Poster.THROTTLE_POLL), function()
            if current == item then Search() end
        end)
        return
    end
    item.tries = item.tries + 1
    C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(item.itemID), SORTS, false)
    local tries = item.tries
    C_Timer.After(Poster.SEARCH_TIMEOUT, function()
        if current == item and status == "pricing" and item.tries == tries then
            if item.tries < Poster.SEARCH_RETRIES then
                Search()
            else
                SetMessage(string.format(L.POST_NO_ANSWER, ItemName(item.itemID)), true)
                status = "idle"
                Changed()
            end
        end
    end)
end

-- Prices the next item to post, if any.
function Poster.PriceNext()
    if status == "closed" then
        return
    end
    local items = Poster.Items()
    if #items == 0 then
        current = nil
        status = "idle"
        Changed()
        return
    end
    current = { itemID = items[1].itemID, tries = 0 }
    status = "pricing"
    Changed()
    local item = current
    -- The game ignores searches for items it hasn't loaded yet.
    Item:CreateFromItemID(item.itemID):ContinueOnItemLoad(function()
        if current == item and item.tries == 0 then
            Search()
        end
    end)
end

-- Post clicked with nothing priced: prices the first item.
function Poster.Price()
    if status == "idle" then
        SetMessage(nil)
        Poster.PriceNext()
    end
end

local function OnCommodityResults(itemID)
    local item = current
    if status ~= "pricing" or item == nil or item.itemID ~= itemID then
        return
    end
    local itemKey = C_AuctionHouse.MakeItemKey(itemID)
    local count = C_AuctionHouse.GetNumCommoditySearchResults(itemID)
    -- Sometimes it answers with nothing loaded although there are listings.
    if not C_AuctionHouse.HasSearchResults(itemKey)
        or (count == 0 and not C_AuctionHouse.HasFullCommoditySearchResults(itemID)) then
        if item.tries < Poster.SEARCH_RETRIES then
            Search()
        else
            item.commodity = true
            Priced({})
        end
        return
    end
    local rows = {}
    for index = 1, count do
        local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
        if info and info.unitPrice and info.quantity then
            rows[#rows + 1] = { price = info.unitPrice, quantity = info.quantity }
        end
    end
    item.commodity = true
    Priced(rows)
end

local function OnItemResults(itemKey)
    local item = current
    if status ~= "pricing" or item == nil or type(itemKey) ~= "table" or itemKey.itemID ~= item.itemID then
        return
    end
    local count = C_AuctionHouse.GetNumItemSearchResults(itemKey)
    if not C_AuctionHouse.HasSearchResults(itemKey)
        or (count == 0 and not C_AuctionHouse.HasFullItemSearchResults(itemKey)) then
        if item.tries < Poster.SEARCH_RETRIES then
            Search()
        else
            item.commodity = false
            Priced({})
        end
        return
    end
    local rows = {}
    for index = 1, count do
        local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
        -- Buyouts only: an auction that only takes bids has no price to match.
        -- A row is quantity auctions of one item each, all at buyoutAmount
        -- (the game groups identical ones), so buyoutAmount is already the
        -- price of one: dividing it by quantity priced 4 toads at 4.65g each
        -- as 1.16g.
        if info and info.buyoutAmount and info.buyoutAmount > 0 then
            rows[#rows + 1] = { price = info.buyoutAmount, quantity = math.max(info.quantity or 1, 1) }
        end
    end
    item.commodity = false
    Priced(rows)
end

-- Posting ------------------------------------------------------------------------

-- Where one of the item is in your bags (an ItemLocation), or nil.
local function BagLocation(itemID)
    for bag = 0, 5 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID and not info.isLocked then
                return ItemLocation:CreateFromBagAndSlot(bag, slot)
            end
        end
    end
end

-- Whether the game will take a post now (it drops requests just after one).
function Poster.ThrottleReady()
    return C_AuctionHouse.IsThrottledMessageSystemReady()
end

local watchingThrottle = false
function Poster.WatchThrottle()
    if watchingThrottle then
        return
    end
    watchingThrottle = true
    C_Timer.After(Poster.THROTTLE_POLL, function()
        watchingThrottle = false
        if Poster.ThrottleReady() then
            Changed()
        else
            Poster.WatchThrottle()
        end
    end)
end

-- The items left your bags (all of the post): done, on to the next.
local function Posted()
    local item = current
    SetMessage(string.format(L.POSTED, item.quantity, ItemName(item.itemID), VendorProfit.FormatMoney(item.price)))
    Take(item.itemID, item.quantity)
    current = nil
    Poster.PriceNext()
end

-- No reply to a post: given up on after POST_TIMEOUT with nothing leaving
-- the bags. Counted from the last item to leave, not from the click: a
-- multisell of things that don't stack posts one auction at a time and can
-- take longer than that. Timing out on the click cut it short: the part
-- posted so far was taken off the queue, the item came up again for the
-- rest, which left the bags while it was priced, and it said to post 0.
local function WatchPost(item, wait)
    C_Timer.After(wait, function()
        if current ~= item or status ~= "posting" then
            return
        end
        local quiet = GetTime() - item.progress
        if quiet < Poster.POST_TIMEOUT then
            WatchPost(item, Poster.POST_TIMEOUT - quiet)
        elseif InBags(item.itemID) < item.before then
            item.quantity = item.before - InBags(item.itemID)
            Posted()
        else
            SetMessage(string.format(L.POST_NO_REPLY, ItemName(item.itemID)), true)
            status = "ready"
            Changed()
        end
    end)
end

-- How many of an item to post now: its queued count, or what's in your
-- bags if fewer.
local function ToPostCount(itemID)
    local _, entry = Find(itemID)
    return entry and math.min(entry.count, InBags(itemID)) or 0
end

-- Post click: posts the queued count at the price shown. Below what it
-- cost you, the first click only arms it.
function Poster.Post()
    local item = current
    if status ~= "ready" or item == nil then
        return
    end
    if Poster.BelowCost() and not item.armed then
        item.armed = true
        Changed()
        return
    end
    local location = BagLocation(item.itemID)
    local quantity = ToPostCount(item.itemID)
    if location == nil or quantity == 0 then
        current = nil
        Poster.PriceNext()
        return
    end
    item.before, item.quantity = InBags(item.itemID), quantity
    item.left, item.progress = item.before, GetTime()
    status = "posting"
    SetMessage(nil)
    if item.commodity then
        C_AuctionHouse.PostCommodity(location, Poster.Duration(item.itemID), quantity, item.price)
    else
        C_AuctionHouse.PostItem(location, Poster.Duration(item.itemID), quantity, nil, item.price)
    end
    WatchPost(item, Poster.POST_TIMEOUT)
    Changed()
end

-- Bags changed while posting: done once all of it has left. A post that
-- stopped early (an error, which may not even be about the post) is done
-- too if the rest leaves after all: otherwise it stayed on the item with
-- none left to post ("Post 0"), needing a click to move on.
local function CheckPosted()
    local item = current
    if item == nil or item.before == nil or (status ~= "posting" and status ~= "ready") then
        return
    end
    local bags = InBags(item.itemID)
    if bags < item.left then
        item.left, item.progress = bags, GetTime()
    end
    if bags <= item.before - item.quantity then
        Posted()
    end
end

local function OnErrorMessage(_, text)
    if status ~= "posting" or current == nil or text == nil then
        return
    end
    SetMessage(string.format(L.POST_FAILED, ItemName(current.itemID), text), true)
    status = "ready"
    Changed()
end

-- Auction house open and close -----------------------------------------------------

local function Opened()
    if status == "closed" then
        status = "idle"
        SetMessage(nil)
        Changed()
    end
end

local function Closed()
    if status ~= "closed" then
        status = "closed"
        current = nil
        SetMessage(nil)
        Changed()
    end
end

local AUCTIONEER = Enum.PlayerInteractionType and Enum.PlayerInteractionType.Auctioneer

local handlers = {
    PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(kind) if kind == AUCTIONEER then Opened() end end,
    PLAYER_INTERACTION_MANAGER_FRAME_HIDE = function(kind) if kind == AUCTIONEER then Closed() end end,
    AUCTION_HOUSE_SHOW = Opened,
    AUCTION_HOUSE_CLOSED = Closed,
    COMMODITY_SEARCH_RESULTS_UPDATED = OnCommodityResults,
    COMMODITY_SEARCH_RESULTS_ADDED = function(itemID) OnCommodityResults(itemID or (current and current.itemID)) end,
    ITEM_SEARCH_RESULTS_UPDATED = OnItemResults,
    ITEM_SEARCH_RESULTS_ADDED = function(itemKey)
        OnItemResults(itemKey or (current and C_AuctionHouse.MakeItemKey(current.itemID)))
    end,
    AUCTION_HOUSE_AUCTION_CREATED = CheckPosted,
    BAG_UPDATE_DELAYED = CheckPosted,
    UI_ERROR_MESSAGE = OnErrorMessage,
}

local events = CreateFrame("Frame")
for event in pairs(handlers) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
    local args, n = { ... }, select("#", ...)
    xpcall(function() handlers[event](unpack(args, 1, n)) end, geterrorhandler())
end)
