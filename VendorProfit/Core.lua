-- Vendor Profit for Auctionator: adds lines under Auctionator's crafting info
-- (To Craft / Profit) in the professions window.
--
--   Vendor Profit          what the craft makes sold to a vendor
--                          (VendorLine.lua)
--   Vendor Profit (route)  the same, using the cheapest way to get every
--                          reagent, crafting them from your own recipes where
--                          that's cheaper (Recipes.lua, Route.lua,
--                          RouteLine.lua)
--
-- This file holds what the lines share: prices, working out the recipe being
-- shown, and attaching to Auctionator's frame. The addon only reads from
-- Auctionator. It adds its own regions to Auctionator's crafting info frame
-- and post-hooks that frame's UpdateTotal to know when to refresh. It never
-- changes Auctionator's text, settings or data.

local ADDON_NAME, ns = ...

local VendorProfit = {}
ns.VendorProfit = VendorProfit
_G.VendorProfit = VendorProfit

VendorProfit.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")

-- The frame Auctionator puts under a recipe's reagents in the professions
-- window. It's created the first time the professions window opens.
VendorProfit.AUCTIONATOR_FRAME = "AuctionatorCraftingInfoProfessionsFrame"

VendorProfit.L = {
    VENDOR_PROFIT = "Vendor Profit:",
    ROUTE_PROFIT = "Vendor Profit (route):",
    NO_SELL_PRICE = "can't be sold to vendors",
    MISSING_PRICES = "(missing reagent prices)",
    ROUTE_TITLE = "Cheapest Route",
    SOURCE_VENDOR = "buy (vendor)",
    SOURCE_AUCTION = "buy (auction)",
    SOURCE_CRAFT = "craft",
    MAKES = "makes %d",
    SOURCE_NONE = "no price",
    CRAFTING_COST = "Crafting cost",
    AUCTIONATOR_COST = "Auctionator's To Craft",
    SAVES = "Saves",
    VENDOR_PROFIT_SHORT = "Vendor profit",
    RECIPES_FROM = "Uses your recipes from: %s.",
    NO_RECIPES = "No recipes saved yet.",
    OPEN_PROFESSIONS = "Open each profession once to add its recipes.",
}

-- Prices ---------------------------------------------------------------------

-- What it costs to buy one: from a vendor (Auctionator only knows vendor
-- prices for items it has seen at a vendor) and on the auction house.
function VendorProfit.GetBuyPrices(itemID)
    local api = Auctionator.API.v1
    return api.GetVendorPriceByItemID(ADDON_NAME, itemID),
        api.GetAuctionPriceByItemID(ADDON_NAME, itemID)
end

-- Price of one reagent the way Auctionator prices reagents: the vendor price
-- if there is one, otherwise the auction price.
function VendorProfit.GetReagentPrice(itemID)
    local vendor, auction = VendorProfit.GetBuyPrices(itemID)
    return vendor or auction
end

-- Walks the required reagents. Returns their total cost, cheapest option per
-- slot, and whether any slot has no price at all (Auctionator counts those as
-- free, which makes a craft look more profitable than it is).
local function ScanReagents(recipeSchematic)
    local total, missing = 0, false
    for _, slot in ipairs(recipeSchematic.reagentSlotSchematics) do
        if slot.reagentType == Enum.CraftingReagentType.Basic and #slot.reagents > 0 then
            local cheapest
            for _, reagent in ipairs(slot.reagents) do
                local price = reagent.itemID and VendorProfit.GetReagentPrice(reagent.itemID)
                if price and price > 0 and (cheapest == nil or price < cheapest) then
                    cheapest = price
                end
            end
            if cheapest then
                total = total + cheapest * slot.quantityRequired
            else
                missing = true
            end
        end
    end
    return total, missing
end

-- What it costs to craft once. Auctionator's figure when available, so it
-- matches the To Craft line; otherwise the reagent scan's own total.
local function GetCraftCost(recipeSchematic, transaction, scannedTotal)
    local calculate = Auctionator.CraftingInfo and Auctionator.CraftingInfo.CalculateCraftCost
    if calculate then
        return calculate(recipeSchematic, transaction)
    end
    return scannedTotal
end

-- The recipe being shown ----------------------------------------------------

-- Works out what the lines need for the recipe a schematic form is showing.
-- Returns a result table, or nil when the recipe makes no item (enchants).
--   status "loading":  item info isn't cached yet; only itemLink is set
--   status "noSell":   the item has no vendor price; profit is nil
--   status "ok":       profit is the vendor profit
-- Every status but "loading" also has itemID, sellPrice, count, cost (the To
-- Craft cost), missingPrices and recipeSchematic.
function VendorProfit.Calculate(schematicForm)
    local recipeInfo = schematicForm:GetRecipeInfo()
    if recipeInfo == nil or recipeInfo.isEnchantingRecipe then
        return nil
    end

    local recipeID = recipeInfo.recipeID
    local recipeSchematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false, schematicForm:GetCurrentRecipeLevel())
    local transaction = schematicForm:GetTransaction()
    if recipeSchematic == nil or transaction == nil then
        return nil
    end

    local outputData = C_TradeSkillUI.GetRecipeOutputItemData(
        recipeID,
        transaction:CreateCraftingReagentInfoTbl(),
        transaction:GetAllocationItemGUID()
    )
    local itemLink = outputData and outputData.hyperlink
    if itemLink == nil then
        return nil
    end

    local sellPrice = select(11, C_Item.GetItemInfo(itemLink))
    if sellPrice == nil then
        return { status = "loading", itemLink = itemLink }
    end

    local scannedTotal, missing = ScanReagents(recipeSchematic)
    local cost = GetCraftCost(recipeSchematic, transaction, scannedTotal)
    -- Same count Auctionator's Profit line uses: the guaranteed minimum.
    local count = math.max(recipeSchematic.quantityMin or 1, 1)

    local result = {
        status = sellPrice > 0 and "ok" or "noSell",
        itemLink = itemLink,
        itemID = recipeSchematic.outputItemID or C_Item.GetItemInfoInstant(itemLink),
        sellPrice = sellPrice,
        count = count,
        cost = cost,
        missingPrices = missing,
        recipeSchematic = recipeSchematic,
    }
    if sellPrice > 0 then
        result.profit = sellPrice * count - cost
    end
    return result
end

-- Money text styled like Auctionator's Profit line: white, or red with a
-- minus for a loss.
function VendorProfit.FormatMoney(copper)
    copper = math.floor(copper + 0.5)
    if copper >= 0 then
        return WHITE_FONT_COLOR:WrapTextInColorCode(GetMoneyString(copper, true))
    end
    return RED_FONT_COLOR:WrapTextInColorCode("-" .. GetMoneyString(-copper, true))
end

-- Lines -----------------------------------------------------------------------

-- Each line module has:
--   Create(frame, anchor)  adds its regions to Auctionator's frame under
--                          anchor (the region above it); returns its bottom
--                          region for the next line to anchor to
--   Refresh(frame, result) updates from VendorProfit.Calculate's result, or
--                          hides when result is nil
-- Lines appear in the order they're added.
local lines = {}
function VendorProfit.AddLine(line)
    lines[#lines + 1] = line
end

local attachedFrame     -- Auctionator's frame, once the lines are added to it
local pendingItemLink   -- output item whose info is loading, to refresh once

local function Refresh(frame)
    local result = VendorProfit.Calculate(frame:GetParent())

    if result and result.status == "loading" then
        -- Hide until the item's info arrives, then refresh once.
        local itemLink = result.itemLink
        result = nil
        if pendingItemLink ~= itemLink then
            pendingItemLink = itemLink
            Item:CreateFromItemLink(itemLink):ContinueOnItemLoad(function()
                if pendingItemLink == itemLink then
                    pendingItemLink = nil
                    VendorProfit.Refresh()
                end
            end)
        end
    end

    for _, line in ipairs(lines) do
        line.Refresh(frame, result)
    end
end

-- Refreshes the lines now. Errors are reported but never passed back up into
-- Auctionator's or Blizzard's code that triggered the refresh.
function VendorProfit.Refresh()
    local frame = attachedFrame
    if frame == nil or not frame:IsVisible() then
        return
    end
    xpcall(function() Refresh(frame) end, geterrorhandler())
end

local function Attach(frame)
    attachedFrame = frame

    -- Lines sit under Auctionator's text, in the same font, so they read as
    -- more lines of it. As children of Auctionator's frame they show and hide
    -- with it.
    local anchor = frame.Total
    for _, line in ipairs(lines) do
        anchor = line.Create(frame, anchor)
    end

    -- Auctionator calls UpdateTotal whenever the recipe, its reagents or its
    -- prices change, so refreshing right after it keeps both in step.
    hooksecurefunc(frame, "UpdateTotal", VendorProfit.Refresh)
    VendorProfit.Refresh()
end

function VendorProfit.TryAttach()
    if attachedFrame then
        return true
    end
    local frame = _G[VendorProfit.AUCTIONATOR_FRAME]
    if frame == nil or frame.Total == nil or type(frame.UpdateTotal) ~= "function" then
        return false
    end
    Attach(frame)
    return true
end

function VendorProfit.IsAttached()
    return attachedFrame ~= nil
end

-- Auctionator makes its frame on TRADE_SKILL_SHOW. Hooking the function that
-- makes it attaches right after, whichever addon sees the event first. The
-- event is a backup in case Auctionator renames that function. Attaching only
-- happens at these events, after every file of the addon has loaded.
if Auctionator.CraftingInfo and Auctionator.CraftingInfo.InitializeProfessionsFrame then
    hooksecurefunc(Auctionator.CraftingInfo, "InitializeProfessionsFrame", VendorProfit.TryAttach)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("TRADE_SKILL_SHOW")
events:SetScript("OnEvent", function(self, event)
    if VendorProfit.TryAttach() then
        self:UnregisterAllEvents()
    elseif event == "TRADE_SKILL_SHOW" then
        -- Auctionator may handle this same event after us.
        C_Timer.After(0, VendorProfit.TryAttach)
    end
end)
