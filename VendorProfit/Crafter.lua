-- Crafting the order's next step from the shopping panel's Craft button.
--
-- The game only crafts recipes of the profession window that's open. So the
-- Craft button crafts the next step the open window can make, and otherwise
-- says which profession to open and opens it when clicked (OpenButton.lua).
--
-- The next step is the first one in the plan's craft list (deepest first)
-- that belongs to the open profession and that you have the materials for in
-- your bags (or reagent bank).
-- It crafts as many as that step needs, up to as many as you can make now.
--
-- Crafting more than one at a time only works if the button was pressed
-- (mouse down) in an earlier frame than the click, a quirk of the game that
-- TradeSkillMaster works around the same way. Otherwise it crafts one.

local _, ns = ...
local VendorProfit = ns.VendorProfit
local Shopper = VendorProfit.Shopper
local Inventory = VendorProfit.Inventory

local Crafter = {}
VendorProfit.Crafter = Crafter

local prepared -- { recipeID, time } from the button's mouse down

local function OpenProfession()
    if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then
        return nil
    end
    local ui = C_TradeSkillUI
    if ui.IsTradeSkillReady and not ui.IsTradeSkillReady() then return nil end
    if ui.IsTradeSkillLinked and ui.IsTradeSkillLinked() then return nil end
    if ui.IsTradeSkillGuild and ui.IsTradeSkillGuild() then return nil end
    local info = ui.GetBaseProfessionInfo and ui.GetBaseProfessionInfo()
    return info and info.professionName
end

-- The profession the window is showing, even while it's still loading.
local function ShowingProfession()
    if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then
        return nil
    end
    local ui = C_TradeSkillUI
    if ui.IsTradeSkillLinked and ui.IsTradeSkillLinked() then return nil end
    local info = ui.GetBaseProfessionInfo and ui.GetBaseProfessionInfo()
    return info and info.professionName
end

-- How many times a step can be crafted with what's in your bags (and reagent
-- bank) now. Counted here rather than asking the game: its recipe info's
-- numAvailable isn't reliable in Forever (TradeSkillMaster counts them itself
-- too). A slot that several items can fill counts the one you have most of.
function Crafter.CanCraft(step)
    local reagents = step.reagents
    if reagents == nil or #reagents == 0 then
        return 0
    end
    local crafts = math.huge
    for _, slot in ipairs(reagents) do
        local have = 0
        for _, itemID in ipairs(slot.items) do
            have = math.max(have, Inventory.ForCrafting(itemID))
        end
        crafts = math.min(crafts, math.floor(have / slot.quantity))
    end
    return crafts
end

-- The next craft:
--   { step, crafts }           ready: craft step.recipeID this many times
--   { step, open = name }      open this profession to craft it
--   { step, materials = true } in the open profession, but materials are missing
--   { step, loading = name }   its profession's window is open but still loading
-- When nothing can be crafted, it's about the first step in the list.
--   nil                        nothing to craft
function Crafter.Next()
    local plan = Shopper.Summary().plan
    local first = plan.crafts[1]
    if first == nil then
        return nil
    end
    local open = OpenProfession()
    if open == nil then
        -- The window is showing a profession the order needs, still loading.
        local loading = ShowingProfession()
        for _, step in ipairs(plan.crafts) do
            if loading and step.profession == loading then
                return { step = step, loading = loading }
            end
        end
    end
    if open then
        for _, step in ipairs(plan.crafts) do
            if step.profession == open then
                local available = Crafter.CanCraft(step)
                if available > 0 then
                    return { step = step, crafts = math.min(step.crafts, available) }
                end
            end
        end
    end
    -- Nothing can be crafted here: say what's holding up the first step.
    if open and first.profession == open then
        return { step = first, materials = true }
    end
    return { step = first, open = first.profession or "?" }
end

function Crafter.IsCasting()
    return UnitCastingInfo("player") ~= nil
end

-- Mouse down on the Craft button.
function Crafter.Prepare()
    local nextCraft = Crafter.Next()
    if nextCraft and nextCraft.crafts then
        prepared = { recipeID = nextCraft.step.recipeID, time = GetTime() }
    else
        prepared = nil
    end
end

-- Click on the Craft button. Returns how many crafts were started.
function Crafter.Craft()
    local nextCraft = Crafter.Next()
    if nextCraft == nil or nextCraft.crafts == nil then
        return 0
    end
    local recipeID, crafts = nextCraft.step.recipeID, nextCraft.crafts
    if prepared == nil or prepared.recipeID ~= recipeID or prepared.time == GetTime() then
        crafts = 1
    end
    prepared = nil
    C_TradeSkillUI.CraftRecipe(recipeID, crafts)
    return crafts
end
