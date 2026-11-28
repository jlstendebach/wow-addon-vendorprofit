-- Profit history: what each sale of something you crafted cost you, what it
-- sold for, and how (vendor or auction).
--
-- Costs follow the items. Every item gets a cost when it comes in:
--   * bought on the auction house: exactly what you paid, read from the
--     purchase's mail when you take the item out of the mailbox;
--   * bought from a vendor: exactly what you paid;
--   * crafted: the cost of the reagents the craft used up, oldest first.
--     Reagents with no recorded cost (farmed, owned before this was
--     installed, from an alt or a trade) count at their market value at
--     that moment: what you could have got for them instead.
-- Each item keeps two parts of its cost: what was bought (exact gold) and
-- what was your own items at market value.
--
-- A sale uses up the item's recorded costs, oldest first:
--   * to a vendor: read from the vendor's buyback list, which has the exact
--     price, and from the sell itself once its stack leaves the bags;
--     buying something back undoes its sale;
--   * at auction: read from the "Auction successful" mail once its money
--     arrives: the sale price less the auction house's cut (the deposit is
--     refunded, so it cancels out).
-- Only items with recorded costs are listed; anything sold beyond them (made
-- before this was installed) is left out rather than given a made-up cost.
--
-- Saved per character in VendorProfitCharDB.history:
--   stock[itemID] = { { n, cost, bought, crafted, time }, ... } oldest first,
--     cost and bought per item
--   sales = { { time, item, n, how ("vendor"/"auction"), sold, cost, bought },
--     ... } oldest first, at most MAX_SALES
--   items[itemID] = { n, sales, cost, sold, bought, vendor, auction, last,
--     roiSum, roiUnits }: every sale ever, added up per item, so totals don't
--     shrink as old sales drop off the list (n, vendor and auction count
--     units; last is a time; roiSum adds up each unit's return on its cost,
--     and roiUnits counts those units, for the average ROI)
--   daily[day][itemID] = { n, sales, cost, sold, bought, vendor, auction,
--     roiSum, roiUnits }:
--     sales that dropped off the list, added up per item per day (day =
--     days since 1970, UTC), kept for good: date ranges and Best Sellers
--     reach back through them; only the per-sale detail is gone
--   purchases = { { time, item, n, total, how }, ... } oldest first, at most
--     MAX_PURCHASES, for the Purchase History tab
--   missing[itemID] = { { n, cost, bought, crafted, time, gone }, ... }:
--     recorded items nowhere to be seen (see Reconcile), gone = when they
--     went missing; dropped after MISSING_DAYS

local _, ns = ...
local VendorProfit = ns.VendorProfit
local Recipes = VendorProfit.Recipes
local Route = VendorProfit.Route
local Inventory = VendorProfit.Inventory

local History = {}
VendorProfit.History = History

-- The newest sales are kept in full; older ones are added up per item per
-- day. Purchases are a gut check, so fewer are kept.
History.MAX_SALES = 10000
History.MAX_PURCHASES = 5000
History.DAY = 24 * 60 * 60
-- How long after an item comes in or goes out before its count is trusted
-- again (purchases and crafts land a moment later).
local SETTLE = 5
-- Missing items are kept this long: mail keeps for 30 days.
History.MISSING_DAYS = 31

local listeners = {}
function History.OnChange(fn)
    listeners[#listeners + 1] = fn
end

-- Goes up with every change, so views can cache what they work out from
-- the history until it changes.
local version = 0
function History.Version()
    return version
end

local function Changed()
    version = version + 1
    for _, fn in ipairs(listeners) do
        xpcall(fn, geterrorhandler())
    end
end

-- A sale's part of the average ROI: its return on cost for each unit, and
-- how many units (none when it cost nothing, which has no ROI).
function History.SaleROI(sale)
    if sale.cost > 0 then
        return (sale.sold - sale.cost) / sale.cost * sale.n, sale.n
    end
    return 0, 0
end

local function AddROI(item, sale, sign)
    local sum, units = History.SaleROI(sale)
    item.roiSum = (item.roiSum or 0) + sign * sum
    item.roiUnits = (item.roiUnits or 0) + sign * units
end

-- Adds a sale to (sign 1) or takes it from (sign -1) the per-item totals.
local function AddToTotals(items, sale, sign)
    local item = items[sale.item]
    if item == nil then
        item = { n = 0, sales = 0, cost = 0, sold = 0, bought = 0, vendor = 0, auction = 0, last = 0,
            roiSum = 0, roiUnits = 0 }
        items[sale.item] = item
    end
    AddROI(item, sale, sign)
    item.n = item.n + sign * sale.n
    item.sales = item.sales + sign
    item.cost = item.cost + sign * sale.cost
    item.sold = item.sold + sign * sale.sold
    item.bought = item.bought + sign * (sale.bought or 0)
    local how = sale.how == "vendor" and "vendor" or "auction"
    item[how] = item[how] + sign * sale.n
    if sign > 0 then
        item.last = math.max(item.last, sale.time)
    end
    if item.sales <= 0 then
        items[sale.item] = nil
    end
end

-- Adds a sale dropping off the list to its day's totals.
local function RollUp(daily, sale)
    if sale == nil then
        return
    end
    local day = math.floor(sale.time / History.DAY)
    daily[day] = daily[day] or {}
    local item = daily[day][sale.item]
    if item == nil then
        item = { n = 0, sales = 0, cost = 0, sold = 0, bought = 0, vendor = 0, auction = 0, roiSum = 0, roiUnits = 0 }
        daily[day][sale.item] = item
    end
    AddROI(item, sale, 1)
    item.n = item.n + sale.n
    item.sales = item.sales + 1
    item.cost = item.cost + sale.cost
    item.sold = item.sold + sale.sold
    item.bought = item.bought + (sale.bought or 0)
    local how = sale.how == "vendor" and "vendor" or "auction"
    item[how] = item[how] + sale.n
end

local function DB()
    VendorProfitCharDB = VendorProfitCharDB or {}
    local db = VendorProfitCharDB
    db.history = db.history or {}
    db.history.stock = db.history.stock or {}
    db.history.sales = db.history.sales or {}
    db.history.purchases = db.history.purchases or {}
    db.history.daily = db.history.daily or {}
    db.history.missing = db.history.missing or {}
    if db.history.items == nil then
        -- From before the totals were kept: start them from the sales list.
        db.history.items = {}
        for _, sale in ipairs(db.history.sales) do
            AddToTotals(db.history.items, sale, 1)
        end
    elseif not db.history.roiTotals then
        -- From before the average ROI was kept: work it out from the sales
        -- list. Sales already added up by day (older than the last
        -- MAX_SALES) have no per-sale detail left, so they're not in it.
        for _, item in pairs(db.history.items) do
            item.roiSum, item.roiUnits = 0, 0
        end
        for _, sale in ipairs(db.history.sales) do
            local item = db.history.items[sale.item]
            if item then
                AddROI(item, sale, 1)
            end
        end
    end
    db.history.roiTotals = true
    return db.history
end

local lastMove = -math.huge   -- GetTime() of the last stock change

-- Stock -------------------------------------------------------------------------

local function AddStock(itemID, n, cost, bought, crafted, atFront)
    if n <= 0 then
        return
    end
    local stock = DB().stock
    local lots = stock[itemID] or {}
    stock[itemID] = lots
    local lot = { n = n, cost = cost, bought = bought, crafted = crafted or nil, time = time() }
    if atFront then
        table.insert(lots, 1, lot)
    else
        lots[#lots + 1] = lot
    end
    lastMove = GetTime()
end

-- Uses up n of an item's recorded costs, oldest first. Returns how many had
-- one, their total cost, the bought part of it, and whether any were crafted.
local function TakeLots(stock, itemID, n)
    local lots = stock[itemID]
    local taken, cost, bought, crafted = 0, 0, 0, false
    while lots and #lots > 0 and taken < n do
        local lot = lots[1]
        local use = math.min(lot.n, n - taken)
        taken = taken + use
        cost = cost + use * lot.cost
        bought = bought + use * lot.bought
        crafted = crafted or lot.crafted == true
        lot.n = lot.n - use
        if lot.n <= 0 then
            table.remove(lots, 1)
        end
    end
    if lots and #lots == 0 then
        stock[itemID] = nil
    end
    lastMove = GetTime()
    return taken, cost, bought, crafted
end

local function TakeStock(itemID, n)
    return TakeLots(DB().stock, itemID, n)
end

local function Recorded(itemID)
    local total = 0
    for _, lot in ipairs(DB().stock[itemID] or {}) do
        total = total + lot.n
    end
    return total
end

-- What one of an item cost you on average, over the ones with recorded
-- costs (copper), or nil if none: for posting (Poster.lua) never below it
-- by accident.
function History.UnitCost(itemID)
    local count, total = 0, 0
    for _, lot in ipairs(DB().stock[itemID] or {}) do
        count = count + lot.n
        total = total + lot.n * lot.cost
    end
    return count > 0 and total / count or nil
end

-- Where recorded items are: bags, bank, or yours at the auction house (up,
-- or sold with the gold not sent yet). More recorded than that, and the
-- oldest go missing: mailed to an alt, destroyed, used, or out of sight (a
-- sale's gold or an expired auction waiting in the mail, a post the
-- auction list doesn't show yet). Missing ones aren't stock (no cost floor,
-- not the next sale's cost), but they come back: a sale from the mail
-- takes them first, and if more turn up than are recorded, the last to go
-- missing return first, at the front, so a miscount undoes itself. Dropped
-- once mail would have expired.
local function MoveToMissing(itemID, n)
    local db = DB()
    local lots = db.stock[itemID]
    local missing = db.missing[itemID] or {}
    db.missing[itemID] = missing
    local now = time()
    while lots and #lots > 0 and n > 0 do
        local lot = lots[1]
        local use = math.min(lot.n, n)
        missing[#missing + 1] = { n = use, cost = lot.cost, bought = lot.bought, crafted = lot.crafted,
            time = lot.time, gone = now }
        n = n - use
        lot.n = lot.n - use
        if lot.n <= 0 then
            table.remove(lots, 1)
        end
    end
    if lots and #lots == 0 then
        db.stock[itemID] = nil
    end
    if #missing == 0 then
        db.missing[itemID] = nil
    end
end

local function Restore(itemID, n)
    local db = DB()
    local missing = db.missing[itemID]
    while missing and #missing > 0 and n > 0 do
        local lot = missing[#missing]
        local use = math.min(lot.n, n)
        local lots = db.stock[itemID] or {}
        db.stock[itemID] = lots
        table.insert(lots, 1, { n = use, cost = lot.cost, bought = lot.bought, crafted = lot.crafted, time = lot.time })
        n = n - use
        lot.n = lot.n - use
        if lot.n <= 0 then
            table.remove(missing)
        end
    end
    if missing and #missing == 0 then
        db.missing[itemID] = nil
    end
end

local function Reconcile()
    if GetTime() - lastMove < SETTLE then
        return
    end
    local db = DB()
    local oldest = time() - History.MISSING_DAYS * History.DAY
    local items = {}
    for itemID, lots in pairs(db.missing) do
        for index = #lots, 1, -1 do
            if (lots[index].gone or 0) < oldest then
                table.remove(lots, index)
            end
        end
        if #lots == 0 then
            db.missing[itemID] = nil
        else
            items[itemID] = true
        end
    end
    for itemID in pairs(db.stock) do
        items[itemID] = true
    end
    local Auctions = VendorProfit.Auctions
    for itemID in pairs(items) do
        local extra = Recorded(itemID) - Inventory.Total(itemID) - (Auctions and Auctions.Owned(itemID) or 0)
        if extra > 0 then
            MoveToMissing(itemID, extra)
        elseif extra < 0 then
            Restore(itemID, -extra)
        end
    end
end

-- How many of an item are missing. For tests and debugging.
function History.Missing(itemID)
    local total = 0
    for _, lot in ipairs(DB().missing[itemID] or {}) do
        total = total + lot.n
    end
    return total
end

-- Purchases ---------------------------------------------------------------------

-- A purchase: its cost goes on the item, and it's logged for the Purchase
-- History tab. how = "auction" or "vendor".
function History.Bought(itemID, n, total, how)
    if itemID and n and n > 0 and total then
        AddStock(itemID, n, total / n, total / n, false)
        local purchases = DB().purchases
        purchases[#purchases + 1] = { time = time(), item = itemID, n = n, total = math.floor(total + 0.5), how = how }
        while #purchases > History.MAX_PURCHASES do
            table.remove(purchases, 1)
        end
        Changed()
    end
end

-- How many purchases the list holds, and the index-th newest, without
-- copying the list.
function History.PurchaseCount()
    return #DB().purchases
end

function History.Purchase(index)
    local purchases = DB().purchases
    return purchases[#purchases - index + 1]
end

-- Purchases, newest first (a copy; for tests and small lists).
function History.Purchases()
    local list = {}
    local purchases = DB().purchases
    for index = #purchases, 1, -1 do
        list[#list + 1] = purchases[index]
    end
    return list
end

-- Crafts ------------------------------------------------------------------------

-- What one of an item is worth right now, for your own items.
local function MarketValue(itemID)
    return Route.UnitCost(itemID) or 0
end

-- A craft of a saved recipe: its reagents' costs go into what it makes.
function History.Crafted(recipeID)
    -- A turn-in handed in (TurnIns.lua) counts as a craft too.
    local recipe = Recipes.Get(recipeID) or (recipeID < 0 and VendorProfit.TurnIns.Get(recipeID)) or nil
    if recipe == nil or not recipe.item then
        return
    end
    local cost, bought = 0, 0
    for _, slot in ipairs(recipe.reagents or {}) do
        -- Of a slot's choices, the one with recorded costs, else the first.
        local itemID = slot.items[1]
        for _, choice in ipairs(slot.items) do
            if Recorded(choice) > 0 then
                itemID = choice
                break
            end
        end
        local taken, takenCost, takenBought = TakeStock(itemID, slot.quantity)
        cost = cost + takenCost + (slot.quantity - taken) * MarketValue(itemID)
        bought = bought + takenBought
    end
    local count = math.max(recipe.count or 1, 1)
    AddStock(recipe.item, count, cost / count, bought / count, true)
    Changed()
end

-- Sales -------------------------------------------------------------------------

local function AddSale(itemID, n, how, sold)
    -- An auction's sale from the mail: missing ones first (likely the very
    -- ones, out of sight since). A vendor's: from the bags, so stock first.
    local db = DB()
    local first, second = db.stock, db.missing
    if how == "auction" then
        first, second = db.missing, db.stock
    end
    local taken, cost, bought = TakeLots(first, itemID, n)
    if taken < n then
        local more, moreCost, moreBought = TakeLots(second, itemID, n - taken)
        taken, cost, bought = taken + more, cost + moreCost, bought + moreBought
    end
    if taken <= 0 then
        return
    end
    local sales = db.sales
    local sale = {
        time = time(), item = itemID, n = taken, how = how,
        -- Only the part of the sale that had recorded costs.
        sold = math.floor(sold * taken / n + 0.5),
        cost = math.floor(cost + 0.5), bought = math.floor(bought + 0.5),
    }
    sales[#sales + 1] = sale
    AddToTotals(db.items, sale, 1)
    -- The list keeps the newest; older sales are added up per item per day,
    -- and the totals keep everything.
    while #sales > History.MAX_SALES do
        RollUp(db.daily, table.remove(sales, 1))
    end
    Changed()
end

function History.Sold(itemID, n, sold, how)
    if itemID and n and n > 0 and sold then
        AddSale(itemID, n, how, sold)
    end
end

-- Buying back something you just sold: its sale is undone and its cost
-- comes back.
function History.BoughtBack(itemID, n)
    local sales = DB().sales
    for index = #sales, 1, -1 do
        local sale = sales[index]
        if sale.item == itemID and sale.how == "vendor" and sale.n == n then
            table.remove(sales, index)
            AddToTotals(DB().items, sale, -1)
            AddStock(itemID, n, sale.cost / n, sale.bought / n, true, true)
            Changed()
            return
        end
    end
end

-- How many sales the list holds, and the index-th newest (1 = newest),
-- without copying the list.
function History.SaleCount()
    return #DB().sales
end

function History.Sale(index)
    local sales = DB().sales
    return sales[#sales - index + 1]
end

-- Sales that dropped off the list, added up per item for each day that
-- overlaps since onward (all of them without a time): calls fn(itemID,
-- totals, dayStart) for each.
function History.EachDaily(since, fn)
    local first = since and math.floor(since / History.DAY) or -math.huge
    for day, items in pairs(DB().daily) do
        if day >= first then
            for itemID, totals in pairs(items) do
                fn(itemID, totals, day * History.DAY)
            end
        end
    end
end

-- Sales, newest first (a copy; for tests and small lists).
function History.Sales()
    local list = {}
    local sales = DB().sales
    for index = #sales, 1, -1 do
        list[#list + 1] = sales[index]
    end
    return list
end

-- Every sale ever, added up per item: { [itemID] = { n, sales, cost, sold,
-- bought, vendor, auction, last, roiSum, roiUnits } }.
function History.ItemTotals()
    return DB().items
end

-- Hot crafts (Best Crafts): what's selling well at auction lately.
--   * Heat: each auction sale's profit, its weight halving every
--     HEAT_HALF_LIFE, added up per item. Recent profit counts most, and
--     nothing ever falls off a cliff the way a fixed window does. Vendor
--     sales aren't demand (a vendor buys anything), so they don't count.
--   * Hot: in the top HOT_SHARE (a fifth) of items with positive heat, and
--     at least HOT_MIN_SALES separate auction sales in the last RECENT.
--     Ranking against your own sales adapts to however much you sell; the
--     minimum keeps one buyer from making an item hot. Sales, not items:
--     one buyer of a stack of 200 shells is still one buyer.
-- Heat over the half-life's steady state is profit per day: a steady
-- rate r gives r * HALF_LIFE / ln 2, so rate = heat * ln 2 / half-life.
History.HEAT_HALF_LIFE = 7 * History.DAY
History.RECENT = 7 * History.DAY
History.HOT_SHARE = 0.2
History.HOT_MIN_SALES = 2
-- Past 8 half-lives a sale weighs under 1/256: not worth reading.
local HEAT_HORIZON = 8 * History.HEAT_HALF_LIFE

local heat, heatKey

-- { [itemID] = { heat, sold (items sold at auction in the last RECENT),
-- sales (how many auction sales those were), perDay (profit a day lately),
-- hot } }, for items sold at auction within the horizon. Worked out again when the history changes, and hourly as sales age.
function History.Heat()
    local now = time()
    local count = History.SaleCount()
    local newest = count > 0 and History.Sale(1).time or 0
    local key = version .. "/" .. count .. "/" .. newest .. "/" .. math.floor(now / 3600)
    if key == heatKey then
        return heat
    end
    local items = {}
    local function Add(itemID, profit, n, sales, at)
        local item = items[itemID]
        if item == nil then
            item = { heat = 0, sold = 0, sales = 0 }
            items[itemID] = item
        end
        local age = math.max(now - at, 0)
        item.heat = item.heat + profit * 0.5 ^ (age / History.HEAT_HALF_LIFE)
        if age <= History.RECENT then
            item.sold = item.sold + n
            item.sales = item.sales + sales
        end
    end
    local since = now - HEAT_HORIZON
    -- Newest first: the list is in time order, so stop at the horizon.
    for index = 1, count do
        local sale = History.Sale(index)
        if sale.time < since then
            break
        end
        if sale.how == "auction" then
            Add(sale.item, sale.sold - sale.cost, sale.n, 1, sale.time)
        end
    end
    -- Sales that dropped off the list (only past MAX_SALES): their day's
    -- auction share, as of midday (the day's sales, vendor and auction
    -- together, shared out by items).
    History.EachDaily(since, function(itemID, totals, dayStart)
        local auction = totals.auction or 0
        if auction > 0 and totals.n > 0 then
            local share = auction / totals.n
            Add(itemID, (totals.sold - totals.cost) * share, auction, (totals.sales or 0) * share,
                dayStart + History.DAY / 2)
        end
    end)
    local ranked = {}
    for itemID, item in pairs(items) do
        item.perDay = item.heat * math.log(2) / (History.HEAT_HALF_LIFE / History.DAY)
        if item.heat > 0 then
            ranked[#ranked + 1] = itemID
        end
    end
    table.sort(ranked, function(a, b)
        if items[a].heat ~= items[b].heat then
            return items[a].heat > items[b].heat
        end
        return a < b
    end)
    for place = 1, math.ceil(#ranked * History.HOT_SHARE) do
        local item = items[ranked[place]]
        item.hot = item.sales >= History.HOT_MIN_SALES
    end
    heat, heatKey = items, key
    return heat
end

-- Total profit and how many sales: every sale ever, or (given a time) those
-- since then on the list.
function History.Total(since)
    local profit, count = 0, 0
    if since == nil then
        for _, item in pairs(DB().items) do
            profit = profit + item.sold - item.cost
            count = count + item.sales
        end
        return profit, count
    end
    for _, sale in ipairs(DB().sales) do
        if sale.time >= since then
            profit = profit + sale.sold - sale.cost
            count = count + 1
        end
    end
    History.EachDaily(since, function(_, totals)
        profit = profit + totals.sold - totals.cost
        count = count + totals.sales
    end)
    return profit, count
end

function History.Clear()
    DB().sales = {}
    DB().items = {}
    DB().daily = {}
    Changed()
end

-- How many of an item have recorded costs. For tests and debugging.
function History.Recorded(itemID)
    return Recorded(itemID)
end

-- Vendor: the buyback list ----------------------------------------------------------

local ItemIDFromLink = function(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local buyback = {}   -- what the buyback list held last time: { key = count }
local buybackList = {}  -- and in order

local function BuybackEntries()
    local entries = {}
    for index = 1, GetNumBuybackItems() do
        local _, _, price, quantity = GetBuybackItemInfo(index)
        local itemID = ItemIDFromLink(GetBuybackItemLink(index))
        if itemID then
            entries[#entries + 1] = { itemID = itemID, n = quantity or 1, price = price or 0,
                key = itemID .. ":" .. (quantity or 1) .. ":" .. (price or 0) }
        end
    end
    return entries
end

local function Counts(entries)
    local counts = {}
    for _, entry in ipairs(entries) do
        counts[entry.key] = (counts[entry.key] or 0) + 1
    end
    return counts
end

local function SnapshotBuyback()
    buybackList = BuybackEntries()
    buyback = Counts(buybackList)
end

-- Vendor: the sell itself ----------------------------------------------------------

-- The buyback list holds 12. Once it's full, selling a stack just like the
-- oldest one pushes that one off and adds its twin, and the list reads the
-- same as before: the sale can't be seen there. So a sell (a right-click at
-- the merchant, which is C_Container.UseContainerItem; vendor addons sell
-- the same way) is noted too, and recorded once its stack leaves the bags.
-- A sell the list does show is matched to the note, so it's recorded once
-- whichever comes first. Drag-and-drop sells aren't noted, but the list
-- catches them as before. A note nothing confirms (the merchant wouldn't
-- take it) goes after a few seconds.
local SELL_TIMEOUT = 5
local pendingSells = {}  -- { itemID, n, price, time, recorded, listed }
local sellBase = {}      -- itemID -> { count = in bags before, matched = left since }

local function ExpireSells()
    local now = GetTime()
    for index = #pendingSells, 1, -1 do
        if now - pendingSells[index].time > SELL_TIMEOUT then
            table.remove(pendingSells, index)
        end
    end
    local waiting = {}
    for _, sell in ipairs(pendingSells) do
        waiting[sell.itemID] = true
    end
    for itemID in pairs(sellBase) do
        if not waiting[itemID] then
            sellBase[itemID] = nil
        end
    end
end

-- Stacks gone from the bags: the oldest sells of them are confirmed.
local function CheckSells()
    ExpireSells()
    for _, sell in ipairs(pendingSells) do
        local base = sellBase[sell.itemID]
        if not sell.gone and base then
            local gone = base.count - (C_Item.GetItemCount(sell.itemID) or 0) - base.matched
            if gone >= sell.n then
                base.matched = base.matched + sell.n
                sell.gone = true
                if not sell.recorded then
                    sell.recorded = true
                    AddSale(sell.itemID, sell.n, "vendor", sell.price)
                end
            end
        end
    end
end

if C_Container and C_Container.UseContainerItem then
    hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot, onSelf)
        if onSelf or not (VendorProfit.Merchant and VendorProfit.Merchant.IsOpen()) then
            return
        end
        -- Still in the slot: the sell is a request the server answers.
        local info = C_Container.GetContainerItemInfo(bag, slot)
        local itemID = info and info.itemID
        local sellPrice = itemID and select(11, C_Item.GetItemInfo(itemID))
        if not sellPrice or sellPrice <= 0 then
            return  -- the merchant won't buy it
        end
        ExpireSells()
        sellBase[itemID] = sellBase[itemID] or { count = C_Item.GetItemCount(itemID) or 0, matched = 0 }
        local n = info.stackCount or 1
        pendingSells[#pendingSells + 1] = { itemID = itemID, n = n, price = sellPrice * n, time = GetTime() }
    end)
end

-- New entries in the buyback list are things just sold: each the sell
-- noted for it if there is one, recorded once.
local function CheckBuyback()
    ExpireSells()
    local entries = BuybackEntries()
    local seen = {}
    for _, entry in ipairs(entries) do
        seen[entry.key] = (seen[entry.key] or 0) + 1
        if seen[entry.key] > (buyback[entry.key] or 0) then
            local noted
            for _, sell in ipairs(pendingSells) do
                if not sell.listed and sell.itemID == entry.itemID and sell.n == entry.n then
                    noted = sell
                    break
                end
            end
            if noted then
                noted.listed = true
            end
            if not (noted and noted.recorded) then
                if noted then
                    noted.recorded = true
                end
                AddSale(entry.itemID, entry.n, "vendor", entry.price)
            end
        end
    end
    buybackList = entries
    buyback = Counts(entries)
end

-- Buying back: the entry as the list last showed it (it may be gone by
-- the time this runs).
if BuybackItem then
    hooksecurefunc("BuybackItem", function(index)
        local entry = buybackList[index]
        if entry then
            History.BoughtBack(entry.itemID, entry.n)
        end
    end)
end

-- Vendor purchases, wherever you buy.
if BuyMerchantItem then
    hooksecurefunc("BuyMerchantItem", function(index, quantity)
        local itemID = GetMerchantItemID and GetMerchantItemID(index) or ItemIDFromLink(GetMerchantItemLink(index))
        local price, stackCount
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local info = C_MerchantFrame.GetItemInfo(index)
            if info == nil or info.hasExtendedCost then
                return
            end
            price, stackCount = info.price, info.stackCount
        else
            local _, _, p, s, _, _, _, extended = GetMerchantItemInfo(index)
            if extended then
                return
            end
            price, stackCount = p, s
        end
        stackCount = math.max(stackCount or 1, 1)
        local n = quantity or stackCount
        if itemID and price and price > 0 then
            History.Bought(itemID, n, price * n / stackCount, "vendor")
        end
    end)
end

-- Mail: auction purchases and sales --------------------------------------------------

-- Recorded from what actually arrives, not from the request to take a mail.
-- A request can be made twice for one mail and the game pays out once:
-- TradeSkillMaster holds a take back until the buyer's name has loaded,
-- Open All asks again meanwhile, and the name loading refreshes the inbox.
-- (Recording the requests put one Lionheart Helm sale down twice.) So
-- taking a mail only notes what it should bring, and
--   * a sale is recorded when its gold arrives (PLAYER_MONEY: the mail's
--     money, the sale less the cut and the deposit back), matched by amount;
--   * a purchase, or an auction back, when its items land in your bags.
-- A request that brings nothing (the second for the same mail, or one the
-- game refused: bags full) is dropped after PENDING_TIMEOUT. Identical
-- mails (a purchase of several stacks comes as one mail per stack, the same
-- invoice on each) each bring their own, so each is recorded.
History.PENDING_TIMEOUT = 10

local inbox = {}        -- what each mail held at the last inbox update

-- Whether a mail's subject is the game's for an auction that came back:
-- "Auction expired: %s" or "Auction cancelled: %s", matched from the
-- game's own text (so in any language), or the English if it hasn't any.
local RETURNED_SUBJECTS = {
    AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s",
    AUCTION_REMOVED_MAIL_SUBJECT or "Auction cancelled: %s",
}
local function IsReturnedSubject(subject)
    if type(subject) ~= "string" then
        return false
    end
    for _, text in ipairs(RETURNED_SUBJECTS) do
        local before, after = text:match("^(.-)%%s(.*)$")
        if before and #subject > #before + #after and subject:sub(1, #before) == before
            and subject:sub(#subject - #after + 1) == after then
            return true
        end
    end
    return false
end

-- A mail's auction details: { invoiceType, itemName, bid, consignment,
-- count, itemID, n, key }, or nil if it isn't an auction mail. An auction
-- that came back (expired or cancelled) has no invoice: invoiceType
-- "returned".
local function ReadMail(index)
    local invoiceType, itemName, _, bid, _, _, consignment, _, _, _, count = GetInboxInvoiceInfo(index)
    local _, _, sender, subject, money, _, daysLeft = GetInboxHeaderInfo(index)
    if invoiceType ~= "buyer" and invoiceType ~= "seller" then
        if not IsReturnedSubject(subject) then
            return nil
        end
        invoiceType = "returned"
    end
    local _, itemID, _, n = GetInboxItem(index, 1)
    return {
        invoiceType = invoiceType, itemName = itemName, bid = bid, consignment = consignment,
        count = count, itemID = itemID, n = n, money = money,
        key = table.concat({ invoiceType, tostring(sender), tostring(subject), tostring(itemName),
            tostring(bid), tostring(count), tostring(daysLeft) }, "|"),
    }
end

local function SnapshotInbox()
    inbox = {}
    local shown = GetInboxNumItems()
    for index = 1, shown or 0 do
        inbox[index] = ReadMail(index) or false
    end
end

-- Which tracked item a sale's mail names: in stock, or missing (its gold
-- waiting in the mail is one reason to be).
local function ItemByName(name)
    local db = DB()
    for _, store in ipairs({ db.stock, db.missing }) do
        for itemID in pairs(store) do
            if C_Item.GetItemInfo(itemID) == name then
                return itemID
            end
        end
    end
end

-- What takes are waiting for: sales for their gold ({ itemID, n, sold,
-- money, time }), purchases and auctions back for their items ({ kind,
-- itemID, n, total, time }), oldest first. For items: each item's bag count
-- when the first of its takes was made, and how many have been matched
-- since, so what's arrived is what's more than that.
local pendingSales, pendingItems = {}, {}
local itemBase = {}
local lastMoney

local function Expire(list)
    local now = GetTime()
    for index = #list, 1, -1 do
        if now - list[index].time > History.PENDING_TIMEOUT then
            table.remove(list, index)
        end
    end
end

local function InBags(itemID)
    return C_Item.GetItemCount(itemID) or 0
end

-- Gold came in: the sales it pays for, matched by amount. One sale's gold
-- (the oldest waiting at that amount), or else several in a row, oldest
-- first, whose gold adds up to it. Gold from anything else matches none.
local function MoneyArrived(gain)
    Expire(pendingSales)
    if gain <= 0 or #pendingSales == 0 then
        return
    end
    local matched
    for index, sale in ipairs(pendingSales) do
        if sale.money == gain then
            matched = { index }
            break
        end
    end
    if matched == nil then
        local sum = 0
        for index, sale in ipairs(pendingSales) do
            sum = sum + sale.money
            if sum == gain then
                matched = {}
                for i = 1, index do
                    matched[i] = i
                end
                break
            elseif sum > gain then
                break
            end
        end
    end
    for i = #(matched or {}), 1, -1 do
        local sale = table.remove(pendingSales, matched[i])
        History.Sold(sale.itemID, sale.n, sale.sold, "auction")
    end
end

local function CheckMoney()
    local money = GetMoney()
    if lastMoney then
        MoneyArrived(money - lastMoney)
    end
    lastMoney = money
end

-- Items landed: the purchases and auctions back they're for, oldest first,
-- each once all of its stack is in.
local function CheckItems()
    Expire(pendingItems)
    local waiting = {}
    for _, take in ipairs(pendingItems) do
        waiting[take.itemID] = true
    end
    for itemID, base in pairs(itemBase) do
        if not waiting[itemID] then
            itemBase[itemID] = nil
        end
    end
    local index = 1
    while index <= #pendingItems do
        local take = pendingItems[index]
        local base = itemBase[take.itemID]
        local arrived = InBags(take.itemID) - base.count - base.matched
        if arrived >= take.n then
            base.matched = base.matched + take.n
            table.remove(pendingItems, index)
            if take.kind == "purchase" then
                History.Bought(take.itemID, take.n, take.total, "auction")
            else
                -- Back from the auction house: queued to post again (Poster.lua).
                VendorProfit.Poster.Returned(take.itemID, take.n)
            end
        else
            index = index + 1
        end
    end
end

-- Reads a mail's invoice as it's asked to be taken, and notes what it
-- should bring: a purchase when its item is taken, a sale when its money
-- is, an auction back when its item is. Read live: taking is a request, so
-- the mail at that position is still the one being taken (as it was at the
-- last inbox update only if it's already empty).
local function TakeMail(index, takingItem, takingMoney)
    local mail = ReadMail(index)
    local before = inbox[index]
    if before and (mail == nil or (mail.key == before.key and takingItem and mail.itemID == nil)) then
        mail = before
    end
    if mail == nil then
        return
    end
    local now = GetTime()
    local function ExpectItems(kind, n, total)
        if itemBase[mail.itemID] == nil then
            itemBase[mail.itemID] = { count = InBags(mail.itemID), matched = 0 }
        end
        pendingItems[#pendingItems + 1] = { kind = kind, itemID = mail.itemID, n = n, total = total, time = now }
        -- Checked again once it's had time to land, in case no bag update
        -- comes for it.
        C_Timer.After(1, CheckItems)
    end
    if mail.invoiceType == "buyer" and takingItem then
        if mail.itemID and mail.bid then
            -- The invoice is for the whole purchase (bid for count items),
            -- but a purchase of more than a stack comes as one mail per
            -- stack: this mail's share is its own stack (n) at the price
            -- each.
            local count = math.max(mail.count or mail.n or 1, 1)
            local n = mail.n or count
            ExpectItems("purchase", n, mail.bid * n / count)
        end
    elseif mail.invoiceType == "returned" and takingItem then
        if mail.itemID then
            ExpectItems("returned", mail.n or 1)
        end
    elseif mail.invoiceType == "seller" and takingMoney then
        local itemID = ItemByName(mail.itemName)
        if itemID and mail.bid and (mail.money or 0) > 0 then
            -- With nothing else waiting, the gold now is where to count
            -- from (whatever changed it before).
            Expire(pendingSales)
            if lastMoney == nil or #pendingSales == 0 then
                lastMoney = GetMoney()
            end
            pendingSales[#pendingSales + 1] = { itemID = itemID, n = mail.count or 1,
                sold = mail.bid - (mail.consignment or 0), money = mail.money, time = now }
        end
    end
end

if TakeInboxItem then
    hooksecurefunc("TakeInboxItem", function(index) TakeMail(index, true, false) end)
end
if TakeInboxMoney then
    hooksecurefunc("TakeInboxMoney", function(index) TakeMail(index, false, true) end)
end
if AutoLootMailItem then
    hooksecurefunc("AutoLootMailItem", function(index) TakeMail(index, true, true) end)
end

-- Events ----------------------------------------------------------------------------

local reconcileWaiting, lastBagUpdate = false, 0
local events = CreateFrame("Frame")
for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "BAG_UPDATE_DELAYED", "MAIL_SHOW", "MAIL_INBOX_UPDATE",
    "PLAYER_MONEY" }) do
    pcall(events.RegisterEvent, events, event)
end
-- Only the player's casts: registered for every unit, it ran for each cast
-- in a group, a raid or a crowded city.
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit == "player" and spellID then
            History.Crafted(spellID)
        end
    elseif event == "MERCHANT_SHOW" then
        SnapshotBuyback()
    elseif event == "MERCHANT_UPDATE" then
        CheckBuyback()
    elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
        if event == "MAIL_SHOW" then
            lastMoney = GetMoney()
        end
        SnapshotInbox()
    elseif event == "PLAYER_MONEY" then
        CheckMoney()
    elseif event == "BAG_UPDATE_DELAYED" then
        if #pendingItems > 0 then
            CheckItems()
        end
        if VendorProfit.Merchant and VendorProfit.Merchant.IsOpen() then
            CheckBuyback()
        end
        if #pendingSells > 0 then
            CheckSells()
        end
        Reconcile()
        -- Check again once things have settled, SETTLE after the last bag
        -- update: one timer, put off while updates keep coming (bags update
        -- many times while crafting or looting, and a timer each piled up
        -- checks of every recorded item).
        lastBagUpdate = GetTime()
        if not reconcileWaiting then
            reconcileWaiting = true
            local function Later()
                local wait = lastBagUpdate + SETTLE + 0.5 - GetTime()
                if wait > 0 then
                    C_Timer.After(wait, Later)
                    return
                end
                reconcileWaiting = false
                Reconcile()
            end
            C_Timer.After(SETTLE + 0.5, Later)
        end
    end
end)
