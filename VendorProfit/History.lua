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
--     price; buying something back undoes its sale;
--   * at auction: read from the "Auction successful" mail when you take its
--     money: the sale price less the auction house's cut (the deposit is
--     refunded, so it cancels out).
-- Only items with recorded costs are listed; anything sold beyond them (made
-- before this was installed) is left out rather than given a made-up cost.
--
-- Saved per character in VendorProfitCharDB.history:
--   stock[itemID] = { { n, cost, bought, crafted, time }, ... } oldest first,
--     cost and bought per item
--   sales = { { time, item, n, how ("vendor"/"auction"), sold, cost, bought },
--     ... } oldest first, at most MAX_SALES
--   purchases = { { time, item, n, total, how }, ... } oldest first, at most
--     MAX_PURCHASES, for the Purchase History tab

local _, ns = ...
local VendorProfit = ns.VendorProfit
local Recipes = VendorProfit.Recipes
local Route = VendorProfit.Route
local Inventory = VendorProfit.Inventory

local History = {}
VendorProfit.History = History

History.MAX_SALES = 500
History.MAX_PURCHASES = 500
-- How long after an item comes in or goes out before its count is trusted
-- again (purchases and crafts land a moment later).
local SETTLE = 5
-- A mail taken twice this quickly is one mail (a double click).
local MAIL_REPEAT = 10

local listeners = {}
function History.OnChange(fn)
    listeners[#listeners + 1] = fn
end

local function Changed()
    for _, fn in ipairs(listeners) do
        xpcall(fn, geterrorhandler())
    end
end

local function DB()
    VendorProfitCharDB = VendorProfitCharDB or {}
    local db = VendorProfitCharDB
    db.history = db.history or {}
    db.history.stock = db.history.stock or {}
    db.history.sales = db.history.sales or {}
    db.history.purchases = db.history.purchases or {}
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
local function TakeStock(itemID, n)
    local stock = DB().stock
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

local function Recorded(itemID)
    local total = 0
    for _, lot in ipairs(DB().stock[itemID] or {}) do
        total = total + lot.n
    end
    return total
end

-- Items that went some other way (mailed to an alt, destroyed, used): when
-- you own fewer of a reagent than have recorded costs, the oldest go.
-- Crafted items are left alone, since they may be up for auction.
local function Reconcile()
    if GetTime() - lastMove < SETTLE then
        return
    end
    local stock = DB().stock
    for itemID, lots in pairs(stock) do
        local anyCrafted = false
        for _, lot in ipairs(lots) do
            anyCrafted = anyCrafted or lot.crafted == true
        end
        if not anyCrafted then
            local extra = Recorded(itemID) - Inventory.Total(itemID)
            if extra > 0 then
                TakeStock(itemID, extra)
            end
        end
    end
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

-- Purchases, newest first.
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
    local recipe = Recipes.Get(recipeID)
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
    local taken, cost, bought = TakeStock(itemID, n)
    if taken <= 0 then
        return
    end
    local sales = DB().sales
    sales[#sales + 1] = {
        time = time(), item = itemID, n = taken, how = how,
        -- Only the part of the sale that had recorded costs.
        sold = math.floor(sold * taken / n + 0.5),
        cost = math.floor(cost + 0.5), bought = math.floor(bought + 0.5),
    }
    while #sales > History.MAX_SALES do
        table.remove(sales, 1)
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
            AddStock(itemID, n, sale.cost / n, sale.bought / n, true, true)
            Changed()
            return
        end
    end
end

-- Sales, newest first.
function History.Sales()
    local list = {}
    local sales = DB().sales
    for index = #sales, 1, -1 do
        list[#list + 1] = sales[index]
    end
    return list
end

-- Total profit over sales since a time (all sales without one), and how
-- many sales.
function History.Total(since)
    local profit, count = 0, 0
    for _, sale in ipairs(DB().sales) do
        if since == nil or sale.time >= since then
            profit = profit + sale.sold - sale.cost
            count = count + 1
        end
    end
    return profit, count
end

function History.Clear()
    DB().sales = {}
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

-- New entries in the buyback list are things just sold.
local function CheckBuyback()
    local entries = BuybackEntries()
    local seen = {}
    for _, entry in ipairs(entries) do
        seen[entry.key] = (seen[entry.key] or 0) + 1
        if seen[entry.key] > (buyback[entry.key] or 0) then
            AddSale(entry.itemID, entry.n, "vendor", entry.price)
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

local recentMail = {}   -- mail key -> GetTime() it was handled
local inbox = {}        -- what each mail held at the last inbox update

-- A mail's auction details: { invoiceType, itemName, bid, consignment,
-- count, itemID, n, key }, or nil if it isn't an auction mail.
local function ReadMail(index)
    local invoiceType, itemName, _, bid, _, _, consignment, _, _, _, count = GetInboxInvoiceInfo(index)
    if invoiceType ~= "buyer" and invoiceType ~= "seller" then
        return nil
    end
    local _, _, sender, subject, money, _, daysLeft = GetInboxHeaderInfo(index)
    local _, itemID, _, n = GetInboxItem(index, 1)
    return {
        invoiceType = invoiceType, itemName = itemName, bid = bid, consignment = consignment,
        count = count, itemID = itemID, n = n,
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

-- Which tracked item a sale's mail names.
local function ItemByName(name)
    for itemID in pairs(DB().stock) do
        if C_Item.GetItemInfo(itemID) == name then
            return itemID
        end
    end
end

-- Reads a mail's invoice as it's taken: a purchase when its item is taken,
-- a sale when its money is. Read live, or as it was at the last inbox
-- update if taking it has already emptied it.
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
    if recentMail[mail.key] and now - recentMail[mail.key] < MAIL_REPEAT then
        return
    end
    if mail.invoiceType == "buyer" and takingItem then
        if mail.itemID and mail.bid then
            recentMail[mail.key] = now
            History.Bought(mail.itemID, mail.n or mail.count or 1, mail.bid, "auction")
        end
    elseif mail.invoiceType == "seller" and takingMoney then
        local itemID = ItemByName(mail.itemName)
        if itemID and mail.bid then
            recentMail[mail.key] = now
            History.Sold(itemID, mail.count or 1, mail.bid - (mail.consignment or 0), "auction")
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

local events = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "MERCHANT_SHOW", "MERCHANT_UPDATE", "BAG_UPDATE_DELAYED",
    "MAIL_SHOW", "MAIL_INBOX_UPDATE" }) do
    pcall(events.RegisterEvent, events, event)
end
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
        SnapshotInbox()
    elseif event == "BAG_UPDATE_DELAYED" then
        if VendorProfit.Merchant and VendorProfit.Merchant.IsOpen() then
            CheckBuyback()
        end
        Reconcile()
        -- Check again once things have settled.
        C_Timer.After(SETTLE + 0.5, Reconcile)
    end
end)
