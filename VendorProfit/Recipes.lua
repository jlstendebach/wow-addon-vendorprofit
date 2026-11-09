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
--         stations = { "Anvil", ... } or nil: what it must be crafted at
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
local byRecipe = {}     -- recipeID -> the same entry
local NONE = {}

local function RebuildIndex()
    byItem = {}
    byRecipe = {}
    for _, profession in pairs(db.professions) do
        for recipeID, saved in pairs(profession.recipes) do
            local list = byItem[saved.item]
            if list == nil then
                list = {}
                byItem[saved.item] = list
            end
            local entry = {
                recipeID = recipeID,
                profession = profession.name,
                item = saved.item,
                count = saved.count,
                reagents = saved.reagents,
                stations = saved.stations,
            }
            list[#list + 1] = entry
            byRecipe[recipeID] = entry
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
-- A saved recipe by its ID (the craft's spell ID), or nil.
-- What a recipe must be crafted at (Anvil, Forge, Cooking Fire), as the
-- game lists it while the recipe's profession is open; nil for nothing.
function Recipes.StationsFromRequirements(recipeID)
    local requirements = C_TradeSkillUI.GetRecipeRequirements and C_TradeSkillUI.GetRecipeRequirements(recipeID)
    local stations
    for _, requirement in ipairs(requirements or NONE) do
        if requirement.name then
            stations = stations or {}
            stations[#stations + 1] = requirement.name
        end
    end
    return stations
end

-- The station a recipe needs, and whether you're at it right now: true,
-- false, or nil when the game doesn't say. The game reports this for the
-- open profession's recipes; for others it may not (then it's nil, unless the
-- recipe needs no station at all, which is true).
function Recipes.Station(recipeID)
    local requirements = C_TradeSkillUI.GetRecipeRequirements and C_TradeSkillUI.GetRecipeRequirements(recipeID)
    if requirements and #requirements > 0 then
        local name
        for _, requirement in ipairs(requirements) do
            if requirement.met == false then
                return requirement.name, false
            end
            name = name or requirement.name
        end
        return name, true
    end
    local entry = byRecipe[recipeID]
    if entry and entry.stations and #entry.stations > 0 then
        return entry.stations[1], nil
    end
    return nil, true
end

function Recipes.Get(recipeID)
    return byRecipe[recipeID]
end

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

-- The open profession window's key (how its recipes are saved) and name, or
-- nil if it isn't this character's own profession or isn't ready.
function Recipes.OpenProfession()
    if not IsOwnProfessionReady() then
        return nil
    end
    local info = C_TradeSkillUI.GetBaseProfessionInfo()
    local key = info and (info.professionID or info.professionName)
    if key == nil then
        return nil
    end
    return key, info.professionName or tostring(key)
end

-- The saved recipes of one profession: { recipeID, item, count, reagents,
-- profession }, sorted by recipeID.
-- Showing a recipe in the professions window ----------------------------------

-- Whether the professions window is open (a recipe can only be shown then).
function Recipes.WindowOpen()
    return ProfessionsFrame ~= nil and ProfessionsFrame:IsShown()
end

-- Selects a recipe in the professions window the way clicking it in the
-- window's own list does: instant, with no trip to the server. Only works in
-- the profession the window is showing. Returns whether it could.
local function SelectInWindow(recipeID, profession)
    local _, openName = Recipes.OpenProfession()
    local page = ProfessionsFrame.CraftingPage
    local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
    if openName ~= profession or info == nil or page == nil or page.SelectRecipe == nil then
        return false
    end
    -- On the recipes tab, not specializations or crafting orders.
    if ProfessionsFrame.recipesTabID and ProfessionsFrame.GetTab and ProfessionsFrame.SetTab
        and ProfessionsFrame:GetTab() ~= ProfessionsFrame.recipesTabID then
        ProfessionsFrame:SetTab(ProfessionsFrame.recipesTabID)
    end
    return pcall(page.SelectRecipe, page, info)
end

-- Shows a recipe (of profession, by name) in the professions window, if it's
-- open. In the profession the window is showing, it's selected there
-- directly. C_TradeSkillUI.OpenRecipe is only the fallback: it asks the
-- server to open the profession, which can be slow or do nothing.
function Recipes.Show(recipeID, profession)
    if not Recipes.WindowOpen() then
        return
    end
    if not SelectInWindow(recipeID, profession) and C_TradeSkillUI.OpenRecipe then
        C_TradeSkillUI.OpenRecipe(recipeID)
    end
end

function Recipes.ForProfession(key)
    local list = {}
    local saved = db and db.professions[key]
    if saved then
        for recipeID, recipe in pairs(saved.recipes) do
            list[#list + 1] = {
                recipeID = recipeID, item = recipe.item, count = recipe.count,
                reagents = recipe.reagents, profession = saved.name,
            }
        end
    end
    table.sort(list, function(a, b) return a.recipeID < b.recipeID end)
    return list
end

-- Saves the open profession's learned recipes. Returns true if it saved.
function Recipes.Scan()
    if db == nil then
        return false
    end
    local key, name = Recipes.OpenProfession()
    if key == nil then
        return false
    end
    local info = { professionName = name }

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
                    stations = Recipes.StationsFromRequirements(recipeID),
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
    -- Best Crafts lists every saved recipe (BestPanel.lua loads later).
    if VendorProfit.BestPanel then
        VendorProfit.BestPanel.Refresh()
    end
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
        for _, name in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
            pcall(self.RegisterEvent, self, name)
        end
    else
        QueueScan()
    end
end)
