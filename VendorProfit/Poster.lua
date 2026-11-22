-- Posting at the auction house: the Shopping List's Post step. What the
-- order crafted, once it's in your bags, is posted at the lowest price
-- listed, one click an item (all of it at once), the way Josh posts by hand:
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
--   * The shortest duration, every item you have in one post. The game
--     posts a number of items that don't stack in one go (Auctionator's
--     multisell does the same), so it's one click for those too.
--
-- The game only posts as part of a click, so each post is a click on Post;
-- the price lookups in between happen by themselves.
--
-- What to post is noted when the order crafts it (Order.Crafted): the
-- outputs of queued recipes, not the reagents crafted on the way, and not
-- recipes queued from Best Crafts' Vendor tab (meant for a vendor). Saved
-- per character in VendorProfitCharDB.toPost[itemID] = true until posted or
-- skipped.

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
-- first; 2 hours on Forever's auction house, 12 on retail's).
Poster.DURATION = 1
Poster.SUSPICIOUS_COUNT = 3
Poster.SUSPICIOUS_GAP = 0.8
Poster.SUSPICIOUS_SKIPS = 2

local SORTS = { { sortOrder = 0, reverseSort = false } } -- by price, cheapest first

-- status:
--   "closed"   auction house not open
--   "idle"     open, nothing priced yet
--   "pricing"  looking up the current item's price
--   "ready"    priced: Post is offered
--   "posting"  waiting for the items to leave your bags
local status = "closed"
-- The item being priced or posted: { itemID, tries, commodity, price,
-- skipped (cheap listings passed over), guess (last known price, when
-- nothing's listed), cost (per item), armed (below cost, clicked once),
-- before, quantity (posting) }.
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

local function ToPost()
    VendorProfitCharDB = VendorProfitCharDB or {}
    VendorProfitCharDB.toPost = VendorProfitCharDB.toPost or {}
    return VendorProfitCharDB.toPost
end

local function InBags(itemID)
    return C_Item.GetItemCount(itemID) or 0
end

-- An item the order crafted, to post.
function Poster.Crafted(itemID)
    ToPost()[itemID] = true
    Changed()
end

-- What's waiting to be posted and in your bags: { { itemID, count } },
-- by item ID.
function Poster.Items()
    local list = {}
    for itemID in pairs(ToPost()) do
        local count = InBags(itemID)
        if count > 0 then
            list[#list + 1] = { itemID = itemID, count = count }
        end
    end
    table.sort(list, function(a, b) return a.itemID < b.itemID end)
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
    if #groups > 0 then
        item.price, item.skipped = Poster.Choose(groups)
    else
        local last = Auctionator.API.v1.GetAuctionPriceByItemID(ADDON_NAME, item.itemID)
        if last == nil or last <= 0 then
            -- Nothing to go on: left for you to price.
            SetMessage(string.format(L.POST_NO_PRICE, ItemName(item.itemID)), true)
            ToPost()[item.itemID] = nil
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
        if info and info.buyoutAmount and info.buyoutAmount > 0 then
            local quantity = math.max(info.quantity or 1, 1)
            rows[#rows + 1] = { price = math.floor(info.buyoutAmount / quantity), quantity = quantity }
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
    if InBags(item.itemID) == 0 then
        ToPost()[item.itemID] = nil
    end
    current = nil
    Poster.PriceNext()
end

-- Post click: posts every one in your bags at the price shown. Below what
-- it cost you, the first click only arms it.
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
    local quantity = InBags(item.itemID)
    if location == nil or quantity == 0 then
        ToPost()[item.itemID] = nil
        current = nil
        Poster.PriceNext()
        return
    end
    item.before, item.quantity = quantity, quantity
    status = "posting"
    SetMessage(nil)
    if item.commodity then
        C_AuctionHouse.PostCommodity(location, Poster.DURATION, quantity, item.price)
    else
        C_AuctionHouse.PostItem(location, Poster.DURATION, quantity, nil, item.price)
    end
    C_Timer.After(Poster.POST_TIMEOUT, function()
        if current == item and status == "posting" then
            if InBags(item.itemID) < item.before then
                item.quantity = item.before - InBags(item.itemID)
                Posted()
            else
                SetMessage(string.format(L.POST_NO_REPLY, ItemName(item.itemID)), true)
                status = "ready"
                Changed()
            end
        end
    end)
    Changed()
end

-- Skip clicked: leaves the current item off the Post step.
function Poster.Skip()
    if current == nil or status == "posting" then
        return
    end
    ToPost()[current.itemID] = nil
    current = nil
    SetMessage(nil)
    Poster.PriceNext()
end

-- Bags changed while posting: done once all of it has left.
local function CheckPosted()
    local item = current
    if status == "posting" and item and InBags(item.itemID) <= item.before - item.quantity then
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
