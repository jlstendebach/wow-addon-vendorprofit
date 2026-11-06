-- The order: crafts queued to shop for, saved per character.
--
-- Saved data: VendorProfitCharDB.order = {
--     entries  = { { itemID, recipeID, profession, count, crafts, reagents, sellPrice }, ... },
--     inMail   = { [itemID] = bought by the panel, not seen in bags or bank yet },
--     lastSeen = { [itemID] = bags + bank when last checked, for items in inMail },
--     spent    = copper spent by the panel on this order,
-- }
--
-- What the order can use is what's in your bags and bank now, plus purchases
-- still in the mailbox. Purchases may arrive in either place: one is counted
-- as in the mail until that many more of the item show up in bags or bank.
--
-- Crafting a queued recipe counts it down, and the order is finished once
-- every queued craft is made. Reagents you craft with leave your bags, so the
-- plan always works from what's actually left.

local _, ns = ...
local VendorProfit = ns.VendorProfit
local Plan = VendorProfit.Plan
local Inventory = VendorProfit.Inventory

local Order = {}
VendorProfit.Order = Order

local listeners = {}

local function DB()
    VendorProfitCharDB = VendorProfitCharDB or {}
    local db = VendorProfitCharDB
    db.order = db.order or {}
    local order = db.order
    order.entries = order.entries or {}
    order.inMail = order.inMail or {}
    order.lastSeen = order.lastSeen or {}
    order.spent = order.spent or 0
    -- From 1.2.x, which counted purchases differently.
    order.snapshot, order.bought = nil, nil
    return order
end

-- Calls fn() whenever the order changes.
function Order.OnChange(fn)
    listeners[#listeners + 1] = fn
end

local function Changed()
    for _, fn in ipairs(listeners) do
        fn()
    end
end
Order.Changed = Changed

function Order.Entries()
    return DB().entries
end

function Order.IsEmpty()
    return #DB().entries == 0
end

function Order.Spent()
    return DB().spent
end

-- Queues crafts of the recipe in a VendorProfit.Calculate result. Queuing a
-- recipe already in the order adds to it.
function Order.Add(result, crafts, profession)
    local order = DB()
    local recipeID = result.recipeSchematic.recipeID
    for _, entry in ipairs(order.entries) do
        if entry.recipeID == recipeID then
            entry.crafts = entry.crafts + crafts
            Changed()
            return entry
        end
    end
    local entry = {
        itemID = result.itemID,
        recipeID = recipeID,
        profession = profession,
        count = result.count,
        crafts = crafts,
        reagents = VendorProfit.Recipes.ReagentsFromSchematic(result.recipeSchematic),
        sellPrice = result.sellPrice,
    }
    order.entries[#order.entries + 1] = entry
    Changed()
    return entry
end

function Order.Remove(index)
    local order = DB()
    table.remove(order.entries, index)
    if #order.entries == 0 then
        Order.Clear()
        return
    end
    Changed()
end

-- Empties the order and forgets its purchases.
function Order.Clear()
    local order = DB()
    order.entries = {}
    order.inMail = {}
    order.lastSeen = {}
    order.spent = 0
    Changed()
end

-- Notes how many of an item you have just before buying it, so its arrival
-- can be told apart from what was already there.
function Order.BeforePurchase(itemID)
    local order = DB()
    if order.inMail[itemID] == nil then
        order.lastSeen[itemID] = Inventory.Total(itemID)
    end
end

-- Counts purchases in the mail as arrived when that many more of the item
-- show up in bags or bank. Returns true if anything changed.
local function Reconcile()
    local order = DB()
    local changed = false
    for itemID, pending in pairs(order.inMail) do
        local live = Inventory.Total(itemID)
        local arrived = live - (order.lastSeen[itemID] or live)
        if arrived > 0 then
            pending = pending - math.min(pending, arrived)
            changed = true
        end
        order.lastSeen[itemID] = live
        if pending <= 0 then
            order.inMail[itemID] = nil
            order.lastSeen[itemID] = nil
        else
            order.inMail[itemID] = pending
        end
    end
    return changed
end

-- Records a purchase made by the panel.
function Order.RecordPurchase(itemID, quantity, total)
    local order = DB()
    if order.lastSeen[itemID] == nil then
        order.lastSeen[itemID] = Inventory.Total(itemID)
    end
    order.inMail[itemID] = (order.inMail[itemID] or 0) + quantity
    order.spent = order.spent + total
    Reconcile()
    Changed()
end

-- How many purchases of an item are counted as still in the mail.
function Order.InMail(itemID)
    return DB().inMail[itemID] or 0
end

function Order.HasMail()
    return next(DB().inMail) ~= nil
end

-- Stops counting purchases as in the mail: for when they've been collected
-- but are still counted, such as when they were used up as they arrived.
function Order.ForgetMail()
    local order = DB()
    order.inMail = {}
    order.lastSeen = {}
    Changed()
end

-- How many of an item the order can use: bags and bank, plus purchases still
-- in the mail.
function Order.Available(itemID)
    return Inventory.Total(itemID) + (DB().inMail[itemID] or 0)
end

-- Crafting a queued recipe counts it down; the last one finishes the order.
-- Returns true if the recipe was in the order.
function Order.Crafted(recipeID)
    local order = DB()
    for index, entry in ipairs(order.entries) do
        if entry.recipeID == recipeID then
            entry.crafts = entry.crafts - 1
            if entry.crafts <= 0 then
                table.remove(order.entries, index)
            end
            if #order.entries == 0 then
                print(VendorProfit.L.ORDER_DONE)
                Order.Clear()
            else
                Changed()
            end
            return true
        end
    end
    return false
end

-- The plan for the whole order, priced with getBuyPrices (Auctionator's
-- prices by default).
function Order.Plan(getBuyPrices)
    local entries = DB().entries
    Reconcile()
    for _, entry in ipairs(entries) do
        local sellPrice = select(11, C_Item.GetItemInfo(entry.itemID))
        if sellPrice then
            entry.sellPrice = sellPrice
        end
    end
    return Plan.Build(entries, Order.Available, getBuyPrices)
end

local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "BAG_UPDATE_DELAYED" then
        if Reconcile() then
            Changed()
        end
    elseif unit == "player" and spellID then
        Order.Crafted(spellID)
    end
end)
