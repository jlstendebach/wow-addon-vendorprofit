-- Crafting the order's next step from the shopping panel's Craft button.
--
-- The game only crafts recipes of the profession window that's open, and in
-- Forever an addon can't open a profession window itself outside a special
-- button that's locked in combat. So the Craft button crafts the next step
-- the open window can make, and otherwise says which profession to open.
--
-- The next step is the first one in the plan's craft list (deepest first)
-- that belongs to the open profession and that you have the materials for.
-- It crafts as many as that step needs, up to as many as you can make now.
--
-- Crafting more than one at a time only works if the button was pressed
-- (mouse down) in an earlier frame than the click, a quirk of the game that
-- TradeSkillMaster works around the same way. Otherwise it crafts one.

local _, ns = ...
local VendorProfit = ns.VendorProfit
local Shopper = VendorProfit.Shopper

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

-- How many times the open profession can craft a recipe now, or nil if it's
-- not in the open profession.
local function NumAvailable(recipeID)
    local info = recipeID and C_TradeSkillUI.GetRecipeInfo(recipeID)
    if info == nil or not info.learned then
        return nil
    end
    return info.numAvailable or 0
end

-- The next craft:
--   { step, crafts }           ready: craft step.recipeID this many times
--   { step, open = name }      open this profession to craft it
--   { step, materials = true } in the open profession, but materials are missing
-- When nothing can be crafted, it's about the first step in the list.
--   nil                        nothing to craft
function Crafter.Next()
    local plan = Shopper.Summary().plan
    local first = plan.crafts[1]
    if first == nil then
        return nil
    end
    local open = OpenProfession()
    if open then
        for _, step in ipairs(plan.crafts) do
            if step.profession == open then
                local available = NumAvailable(step.recipeID)
                if available and available > 0 then
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
