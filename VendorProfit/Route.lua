-- Finds the cheapest way to get each reagent of a recipe: buy it from a
-- vendor, buy it on the auction house, or craft it with one of this
-- character's saved recipes, whose reagents are priced the same way, all the
-- way down.
--
-- A node is the cheapest way to get ONE of an item:
--   itemID
--   unitCost   copper for one, or nil when nothing gives it a price
--   source     "vendor", "auction", "craft" or nil (no price)
--   recipe     for "craft": the saved recipe used (Recipes.ForItem entry)
--   children   for "craft": { { node = ..., perUnit = n }, ... }, perUnit
--              being how many of that reagent one of this item takes
--   missing    true if a reagent somewhere below has no price and was
--              counted as free, so unitCost is too low
--
-- Costs per item are averaged over what a craft makes: a recipe that makes
-- 2 for 10c costs 5c each.

local _, ns = ...
local VendorProfit = ns.VendorProfit
local Recipes = VendorProfit.Recipes

local Route = {}
VendorProfit.Route = Route

-- How deep a route can go. Real crafting chains are a few steps; this only
-- stops runaway searches.
Route.MAX_DEPTH = 8

-- Whether a is a better way to get an item than b. A complete price beats
-- one with a reagent counted as free, then cheaper wins. On a tie the one
-- found first stays, and buying is always considered first.
local function IsBetter(a, b)
    if a == nil or a.unitCost == nil then return false end
    if b == nil or b.unitCost == nil then return true end
    if a.missing ~= b.missing then return not a.missing end
    return a.unitCost < b.unitCost
end

local Resolve

-- The cheapest way to fill each reagent slot. Returns the total cost of the
-- reagents, their children, and whether any was counted as free. Returns nil
-- if a slot can only be filled by an item already on the route (a loop).
local function ResolveReagents(reagents, visiting, depth)
    local total, missing, children = 0, false, {}
    for _, slot in ipairs(reagents) do
        local best
        for _, itemID in ipairs(slot.items) do
            if not visiting[itemID] then
                local node = Resolve(itemID, visiting, depth)
                if best == nil or IsBetter(node, best) then
                    best = node
                end
            end
        end
        if best == nil then
            return nil
        end
        if best.unitCost == nil then
            missing = true
        else
            total = total + best.unitCost * slot.quantity
        end
        missing = missing or best.missing
        children[#children + 1] = { node = best, perUnit = slot.quantity }
    end
    return total, children, missing
end

local function CraftNode(itemID, recipe, visiting, depth)
    local total, children, missing = ResolveReagents(recipe.reagents, visiting, depth)
    if total == nil then
        return nil
    end
    for _, child in ipairs(children) do
        child.perUnit = child.perUnit / recipe.count
    end
    return {
        itemID = itemID,
        unitCost = total / recipe.count,
        source = "craft",
        recipe = recipe,
        children = children,
        missing = missing,
    }
end

function Resolve(itemID, visiting, depth)
    local vendor, auction = VendorProfit.GetBuyPrices(itemID)
    local best = { itemID = itemID, missing = false }
    if vendor and (auction == nil or vendor <= auction) then
        best.unitCost, best.source = vendor, "vendor"
    elseif auction then
        best.unitCost, best.source = auction, "auction"
    end

    if depth < Route.MAX_DEPTH then
        visiting[itemID] = true
        for _, recipe in ipairs(Recipes.ForItem(itemID)) do
            local node = CraftNode(itemID, recipe, visiting, depth + 1)
            if IsBetter(node, best) then
                best = node
            end
        end
        visiting[itemID] = nil
    end
    return best
end

-- The cheapest route for one craft of a recipe that makes outputItemID from
-- reagents (Recipes.ReagentsFromSchematic format). Returns
--   { cost = copper for one craft, children = ..., missing = bool }
-- with children's perUnit being the amount one craft takes.
function Route.ForRecipe(outputItemID, reagents)
    local visiting = {}
    if outputItemID then
        visiting[outputItemID] = true
    end
    local total, children, missing = ResolveReagents(reagents, visiting, 1)
    if total == nil then
        -- Only reachable if the recipe uses its own output; price it as given.
        return { cost = 0, children = {}, missing = true }
    end
    return { cost = total, children = children, missing = missing }
end

-- The cheapest route for one craft of the recipe in a VendorProfit.Calculate
-- result.
function Route.ForResult(result)
    return Route.ForRecipe(result.itemID, Recipes.ReagentsFromSchematic(result.recipeSchematic))
end
