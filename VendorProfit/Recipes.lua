-- Recipes this character knows, saved per character so routes can cross
-- professions.
--
-- The game only gives recipe details for the profession window that's open,
-- so each profession is saved when its window opens (and again whenever its
-- list changes). A profession not opened yet on this character isn't known,
-- and its items can only be bought on a route.
--
-- Saved data: VendorProfitCharDB.professions[key] = {
--     name = "Mining",
--     recipes = { [recipeID] = {
--         item = outputItemID,
--         count = minimum number made,
--         reagents = { { items = { itemID, ... }, quantity = n }, ... },
--     } },
-- }
-- A reagent slot lists every item that can fill it.

local ADDON_NAME, ns = ...
local VendorProfit = ns.VendorProfit

local Recipes = {}
VendorProfit.Recipes = Recipes

-- Delay before saving after the list changes, so a burst of updates is one
-- save.
Recipes.SCAN_DELAY = 0.5

local db                -- VendorProfitCharDB, once loaded
local byItem = {}       -- itemID -> { recipe, ... }: saved fields plus recipeID, profession
local NONE = {}

local function RebuildIndex()
    byItem = {}
    for _, profession in pairs(db.professions) do
        for recipeID, saved in pairs(profession.recipes) do
            local list = byItem[saved.item]
            if list == nil then
                list = {}
                byItem[saved.item] = list
            end
            list[#list + 1] = {
                recipeID = recipeID,
                profession = profession.name,
                item = saved.item,
                count = saved.count,
                reagents = saved.reagents,
            }
        end
    end
    -- A fixed order, so ties between recipes always pick the same one.
    for _, list in pairs(byItem) do
        table.sort(list, function(a, b) return a.recipeID < b.recipeID end)
    end
end

-- The required reagents of a recipe schematic, in the saved format.
function Recipes.ReagentsFromSchematic(recipeSchematic)
    local reagents = {}
    for _, slot in ipairs(recipeSchematic.reagentSlotSchematics) do
        if slot.reagentType == Enum.CraftingReagentType.Basic and #slot.reagents > 0 then
            local items = {}
            for _, reagent in ipairs(slot.reagents) do
                if reagent.itemID then
                    items[#items + 1] = reagent.itemID
                end
            end
            if #items > 0 then
                reagents[#reagents + 1] = { items = items, quantity = slot.quantityRequired }
            end
        end
    end
    return reagents
end

-- Known recipes that make an item.
function Recipes.ForItem(itemID)
    return byItem[itemID] or NONE
end

-- Names of the professions saved for this character, sorted.
function Recipes.ProfessionNames()
    local names = {}
    if db then
        for _, profession in pairs(db.professions) do
            names[#names + 1] = profession.name
        end
    end
    table.sort(names)
    return names
end

-- Whether the open profession window shows this character's own recipes
-- and has finished loading them.
local function IsOwnProfessionReady()
    local ui = C_TradeSkillUI
    if ui.IsTradeSkillReady and not ui.IsTradeSkillReady() then return false end
    if ui.IsDataSourceChanging and ui.IsDataSourceChanging() then return false end
    if ui.IsTradeSkillLinked and ui.IsTradeSkillLinked() then return false end
    if ui.IsTradeSkillGuild and ui.IsTradeSkillGuild() then return false end
    if ui.IsNPCCrafting and ui.IsNPCCrafting() then return false end
    return true
end

-- Saves the open profession's learned recipes. Returns true if it saved.
function Recipes.Scan()
    if db == nil or not IsOwnProfessionReady() then
        return false
    end
    local info = C_TradeSkillUI.GetBaseProfessionInfo()
    local key = info and (info.professionID or info.professionName)
    if key == nil then
        return false
    end

    -- The full list when the game offers it. Otherwise the list as filtered
    -- in the window, which may be missing some recipes, so it's merged into
    -- what's saved instead of replacing it.
    local recipeIDs, complete
    if C_TradeSkillUI.GetAllRecipeIDs then
        recipeIDs, complete = C_TradeSkillUI.GetAllRecipeIDs(), true
    else
        recipeIDs, complete = C_TradeSkillUI.GetFilteredRecipeIDs(), false
    end

    local saved = db.professions[key]
    local recipes = (not complete and saved and saved.recipes) or {}
    for _, recipeID in ipairs(recipeIDs or NONE) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if recipeInfo and recipeInfo.learned and not recipeInfo.isEnchantingRecipe then
            local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
            if schematic and schematic.outputItemID then
                recipes[recipeID] = {
                    item = schematic.outputItemID,
                    count = math.max(schematic.quantityMin or 1, 1),
                    reagents = Recipes.ReagentsFromSchematic(schematic),
                }
            end
        end
    end

    db.professions[key] = {
        name = info.professionName or tostring(key),
        recipes = recipes,
    }
    RebuildIndex()
    VendorProfit.Refresh()
    return true
end

local scanQueued = false
local function QueueScan()
    if scanQueued then
        return
    end
    scanQueued = true
    C_Timer.After(Recipes.SCAN_DELAY, function()
        scanQueued = false
        xpcall(Recipes.Scan, geterrorhandler())
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" then
        if arg ~= ADDON_NAME then
            return
        end
        VendorProfitCharDB = VendorProfitCharDB or {}
        db = VendorProfitCharDB
        db.professions = db.professions or {}
        RebuildIndex()
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("TRADE_SKILL_SHOW")
        self:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
        self:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
    else
        QueueScan()
    end
end)
