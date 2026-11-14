-- Turns a queue of crafts into a plan in whole numbers: what to buy, and what
-- to craft in which order, using what you already have first.
--
-- Route.lua picks the cheapest source for each item per unit. The plan walks
-- each queued recipe's route from the top: at every item it takes what's
-- available first, crafts the rest in whole crafts (keeping any spare for
-- other steps), and buys whatever is left at the bottom. All queued crafts
-- share one pool of items, so nothing is counted twice.
--
-- available(itemID) returns how many you have that the plan can use. They're
-- counted at their route price (the cheapest way to get one now), whether you
-- had them already or bought them for this order: what was paid before is
-- spent either way, so it doesn't change whether finishing is worth it.
--
-- Plan.Build returns:
--   buy[itemID]   { itemID, quantity, source, unitPrice }: source is
--                 "auction", "vendor" or nil (no price anywhere)
--   buyOrder      the buy entries in the order they were first needed
--   crafts        { itemID, recipeID, profession, crafts, makes, depth, reagents }
--                 deepest first, so each step's reagents come before it
--   uses[itemID]  how many of what you have the plan uses (not counting spares
--                 its own crafts make)
--   revenue       vendor sale value of everything queued
--   ownedValue    route price of the items you have that the plan uses
--   missing       true if something on the plan has no price

local _, ns = ...
local VendorProfit = ns.VendorProfit
local Route = VendorProfit.Route

local Plan = {}
VendorProfit.Plan = Plan

-- Queue entries: { itemID, recipeID, profession, count (made per craft),
-- crafts (how many crafts queued), reagents (Recipes format), sellPrice,
-- exact (its reagents bought as they are, never crafted) }.
function Plan.Build(entries, available, getBuyPrices)
    local plan = {
        buy = {}, buyOrder = {}, crafts = {}, uses = {},
        revenue = 0, ownedValue = 0, missing = false,
    }
    local pool = {}
    local craftsByRecipe = {}

    local function Pool(itemID)
        local entry = pool[itemID]
        if entry == nil then
            -- spare: made by the plan's own crafts beyond what a step needed,
            -- already paid for through that craft's reagents.
            entry = { spare = 0, owned = available(itemID) or 0 }
            pool[itemID] = entry
        end
        return entry
    end

    -- Takes up to amount from the pool. Returns how many are still needed.
    local function Take(itemID, amount, unitPrice)
        local entry = Pool(itemID)
        local fromSpare = math.min(entry.spare, amount)
        entry.spare = entry.spare - fromSpare
        local fromOwned = math.min(entry.owned, amount - fromSpare)
        entry.owned = entry.owned - fromOwned
        if fromOwned > 0 then
            plan.uses[itemID] = (plan.uses[itemID] or 0) + fromOwned
            plan.ownedValue = plan.ownedValue + fromOwned * (unitPrice or 0)
        end
        return amount - fromSpare - fromOwned
    end

    local function AddCraft(itemID, recipeID, profession, crafts, makes, depth, reagents)
        local key = recipeID or ("item:" .. itemID)
        local step = craftsByRecipe[key]
        if step == nil then
            step = {
                itemID = itemID, recipeID = recipeID, profession = profession,
                crafts = 0, makes = makes, depth = depth, reagents = reagents,
            }
            craftsByRecipe[key] = step
            plan.crafts[#plan.crafts + 1] = step
        end
        step.crafts = step.crafts + crafts
        step.depth = math.max(step.depth, depth)
    end

    local function AddBuy(node, amount)
        local line = plan.buy[node.itemID]
        if line == nil then
            line = { itemID = node.itemID, quantity = 0, source = node.source, unitPrice = node.unitCost }
            plan.buy[node.itemID] = line
            plan.buyOrder[#plan.buyOrder + 1] = line
        end
        line.quantity = line.quantity + amount
        if node.source == nil then
            plan.missing = true
        end
    end

    local function Require(node, amount, depth)
        amount = Take(node.itemID, amount, node.unitCost)
        if amount <= 0 then
            return
        end
        if node.source == "craft" then
            local recipe = node.recipe
            local crafts = math.ceil(amount / recipe.count)
            AddCraft(node.itemID, recipe.recipeID, recipe.profession, crafts, recipe.count, depth, recipe.reagents)
            local spare = crafts * recipe.count - amount
            if spare > 0 then
                local entry = Pool(node.itemID)
                entry.spare = entry.spare + spare
            end
            for _, child in ipairs(node.children) do
                Require(child.node, child.quantity * crafts, depth + 1)
            end
        else
            AddBuy(node, amount)
        end
    end

    for _, entry in ipairs(entries) do
        local route = Route.ForRecipe(entry.itemID, entry.reagents, getBuyPrices, entry.exact)
        AddCraft(entry.itemID, entry.recipeID, entry.profession, entry.crafts, entry.count, 0, entry.reagents)
        for _, child in ipairs(route.children) do
            Require(child.node, child.quantity * entry.crafts, 1)
        end
        plan.revenue = plan.revenue + (entry.sellPrice or 0) * entry.count * entry.crafts
    end

    -- Deepest first; ties keep the order they were found in.
    for index, step in ipairs(plan.crafts) do
        step.order = index
    end
    table.sort(plan.crafts, function(a, b)
        if a.depth ~= b.depth then
            return a.depth > b.depth
        end
        return a.order < b.order
    end)
    return plan
end

-- Estimated cost of the plan's purchases at its unit prices.
function Plan.BuyCost(plan)
    local total = 0
    for _, line in ipairs(plan.buyOrder) do
        total = total + (line.unitPrice or 0) * line.quantity
    end
    return total
end
