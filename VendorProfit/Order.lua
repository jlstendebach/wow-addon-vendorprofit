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
-- Opening the mailbox corrects that from what the inbox actually holds.
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

-- Queues crafts of a recipe: fields = { itemID, recipeID, profession, count,
-- reagents (Recipes format), sellPrice }. Queuing a recipe already in the
-- order adds to it.
function Order.AddRecipe(fields, crafts)
    local order = DB()
    for _, entry in ipairs(order.entries) do
        if entry.recipeID == fields.recipeID then
            entry.crafts = entry.crafts + crafts
            Changed()
            return entry
        end
    end
    local entry = {
        itemID = fields.itemID,
        recipeID = fields.recipeID,
        profession = fields.profession,
        count = fields.count,
        crafts = crafts,
        reagents = fields.reagents,
        sellPrice = fields.sellPrice,
    }
    order.entries[#order.entries + 1] = entry
    Changed()
    return entry
end

-- Queues crafts of the recipe in a VendorProfit.Calculate result.
function Order.Add(result, crafts, profession)
    return Order.AddRecipe({
        itemID = result.itemID,
        recipeID = result.recipeSchematic.recipeID,
        profession = profession,
        count = result.count,
        reagents = VendorProfit.Recipes.ReagentsFromSchematic(result.recipeSchematic),
        sellPrice = result.sellPrice,
    }, crafts)
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
-- Gold spent on something that lands in your bags straight away (a vendor
-- purchase), so there's nothing to wait for in the mail.
function Order.AddSpent(total)
    local order = DB()
    order.spent = order.spent + total
    Changed()
end

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

-- Corrects what's counted as in the mail from what the inbox actually holds,
-- when the mailbox is open and all of it is loaded. Purchases that arrived
-- but were never seen arriving (used up straight away, say) stop counting.
function Order.CheckInbox()
    local shown, total = GetInboxNumItems()
    if shown == nil or (total and total > shown) then
        return
    end
    local inbox = {}
    for index = 1, shown do
        for attachment = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
            local _, itemID, _, count = GetInboxItem(index, attachment)
            if itemID then
                inbox[itemID] = (inbox[itemID] or 0) + (count or 1)
            end
        end
    end
    local order = DB()
    local changed = false
    for itemID, pending in pairs(order.inMail) do
        local there = inbox[itemID] or 0
        if pending > there then
            changed = true
            if there > 0 then
                order.inMail[itemID] = there
            else
                order.inMail[itemID] = nil
                order.lastSeen[itemID] = nil
            end
        end
    end
    if changed then
        Changed()
    end
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
pcall(events.RegisterEvent, events, "MAIL_INBOX_UPDATE")
events:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "MAIL_INBOX_UPDATE" then
        Order.CheckInbox()
    elseif event == "BAG_UPDATE_DELAYED" then
        if Reconcile() then
            Changed()
        end
    elseif unit == "player" and spellID then
        Order.Crafted(spellID)
    end
end)
