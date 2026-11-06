-- VendorProfit: adds a "Vendor Profit" line under Auctionator's crafting info
-- (To Craft / Profit) in the professions window. It shows what a craft makes
-- if the result is sold to a vendor instead of on the auction house:
--
--     vendor sell price x number made - cost to craft
--
-- The cost to craft is Auctionator's own number, so the lines always agree.
-- VendorProfit only reads from Auctionator. It adds one FontString to
-- Auctionator's crafting info frame and post-hooks that frame's UpdateTotal to
-- know when to refresh. It never changes Auctionator's text, settings or data.

local ADDON_NAME, ns = ...

local VendorProfit = {}
ns.VendorProfit = VendorProfit
_G.VendorProfit = VendorProfit

VendorProfit.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")

-- The frame Auctionator puts under a recipe's reagents in the professions
-- window. It's created the first time the professions window opens.
VendorProfit.AUCTIONATOR_FRAME = "AuctionatorCraftingInfoProfessionsFrame"

local L = {
    VENDOR_PROFIT = "Vendor Profit:",
    NO_SELL_PRICE = "can't be sold to vendors",
    MISSING_PRICES = "(missing reagent prices)",
}
VendorProfit.L = L

local attachedFrame     -- Auctionator's frame, once the line is added to it
local pendingItemLink   -- output item whose info is loading, to refresh once

-- Price of one reagent, the way Auctionator prices reagents: what a vendor
-- sells it for if a vendor does, otherwise its auction price. Auctionator only
-- knows vendor prices for items seen at a vendor while it was running.
local function GetReagentPrice(itemID)
    local api = Auctionator.API.v1
    return api.GetVendorPriceByItemID(ADDON_NAME, itemID)
        or api.GetAuctionPriceByItemID(ADDON_NAME, itemID)
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
                local price = reagent.itemID and GetReagentPrice(reagent.itemID)
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

-- Works out the vendor profit for the recipe a schematic form is showing.
-- Returns a result table, or nil when the recipe makes no item (enchants).
--   status "ok":        profit, missingPrices, sellPrice, count and cost are set
--   status "noSell":    the item has no vendor price
--   status "loading":   item info isn't cached yet; itemLink is set
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
    if sellPrice == 0 then
        return { status = "noSell", itemLink = itemLink }
    end

    local scannedTotal, missing = ScanReagents(recipeSchematic)
    local cost = GetCraftCost(recipeSchematic, transaction, scannedTotal)
    -- Same count Auctionator's Profit line uses: the guaranteed minimum.
    local count = math.max(recipeSchematic.quantityMin or 1, 1)

    return {
        status = "ok",
        itemLink = itemLink,
        sellPrice = sellPrice,
        count = count,
        cost = cost,
        profit = sellPrice * count - cost,
        missingPrices = missing,
    }
end

-- The line's text for a result, styled like Auctionator's Profit line.
function VendorProfit.FormatLine(result)
    local value
    if result.status == "noSell" then
        value = GRAY_FONT_COLOR:WrapTextInColorCode(L.NO_SELL_PRICE)
    elseif result.profit >= 0 then
        value = WHITE_FONT_COLOR:WrapTextInColorCode(GetMoneyString(result.profit, true))
    else
        value = RED_FONT_COLOR:WrapTextInColorCode("-" .. GetMoneyString(-result.profit, true))
    end

    local text = L.VENDOR_PROFIT .. " " .. value
    if result.missingPrices then
        text = text .. " " .. RED_FONT_COLOR:WrapTextInColorCode(L.MISSING_PRICES)
    end
    return text
end

local function Refresh(frame)
    local line = frame.VendorProfitLine
    local result = VendorProfit.Calculate(frame:GetParent())

    if result == nil then
        line:Hide()
        return
    end

    if result.status == "loading" then
        -- Hide until the item's info arrives, then refresh once.
        line:Hide()
        if pendingItemLink ~= result.itemLink then
            pendingItemLink = result.itemLink
            Item:CreateFromItemLink(result.itemLink):ContinueOnItemLoad(function()
                if pendingItemLink == result.itemLink then
                    pendingItemLink = nil
                    VendorProfit.Refresh()
                end
            end)
        end
        return
    end

    line:SetText(VendorProfit.FormatLine(result))
    line:Show()
end

-- Refreshes the line now. Errors are reported but never passed back up into
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

    -- Sits under Auctionator's text, in the same font, so it reads as one
    -- more line of it. As a child of Auctionator's frame it shows and hides
    -- with it.
    local line = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    line:SetJustifyH("LEFT")
    line:SetPoint("TOPLEFT", frame.Total, "BOTTOMLEFT", 0, -2)
    line:Hide()
    frame.VendorProfitLine = line

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
-- event is a backup in case Auctionator renames that function.
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
