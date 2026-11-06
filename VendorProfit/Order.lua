-- The order: crafts queued to shop for, saved per character.
--
-- Saved data: VendorProfitCharDB.order = {
--     entries  = { { itemID, recipeID, profession, count, crafts, reagents, sellPrice }, ... },
--     snapshot = { [itemID] = bags + bank when the order first needed it },
--     bought   = { [itemID] = how many the panel has bought },
--     spent    = copper spent by the panel on this order,
-- }
--
-- Purchases may arrive in the mailbox rather than the bags, so what the
-- order can use is the larger of what's in bags and bank now, and what was
-- there when the order started plus what the panel bought. That's right
-- whether purchases go to the bags or the mail, and items you buy from a
-- vendor or craft yourself show up through the live count.

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
    order.snapshot = order.snapshot or {}
    order.bought = order.bought or {}
    order.spent = order.spent or 0
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
    order.snapshot = {}
    order.bought = {}
    order.spent = 0
    Changed()
end

-- Records a purchase made by the panel.
function Order.RecordPurchase(itemID, quantity, total)
    local order = DB()
    order.bought[itemID] = (order.bought[itemID] or 0) + quantity
    order.spent = order.spent + total
    Changed()
end

-- Recounts what you have from scratch. For after collecting purchases from
-- the mailbox: they're in the bags now, so the purchase record is cleared to
-- avoid counting them twice. What was spent is kept.
function Order.Recount()
    local order = DB()
    order.snapshot = {}
    order.bought = {}
    Changed()
end

-- How many of an item the order can use: paid (bought by the panel) and
-- owned (had already). See the top of this file.
function Order.Available(itemID)
    local order = DB()
    local live = Inventory.Total(itemID)
    local snapshot = order.snapshot[itemID]
    if snapshot == nil then
        snapshot = live
        order.snapshot[itemID] = live
    end
    local bought = order.bought[itemID] or 0
    local total = math.max(live, snapshot + bought)
    local paid = math.min(bought, total)
    return paid, total - paid
end

-- The plan for the whole order, priced with getBuyPrices (Auctionator's
-- prices by default).
function Order.Plan(getBuyPrices)
    local entries = DB().entries
    for _, entry in ipairs(entries) do
        local sellPrice = select(11, C_Item.GetItemInfo(entry.itemID))
        if sellPrice then
            entry.sellPrice = sellPrice
        end
    end
    return Plan.Build(entries, Order.Available, getBuyPrices)
end
