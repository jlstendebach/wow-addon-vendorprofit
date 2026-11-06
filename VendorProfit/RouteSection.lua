-- The Cheapest Route section, under a separator below Auctionator's lines and
-- the Vendor Profit line. It uses the cheapest way to get every reagent
-- (Route.lua), crafting them from your own recipes where that's cheaper:
--
--     ----------- Cheapest Route -----------
--     To Craft:       route cost
--     Profit:         auction price x number made x (1 - AH cut) - route cost
--     Vendor Profit:  vendor sell price x number made - route cost
--
-- Hovering the section shows the route as a tree, with how much each crafted
-- step saves over buying that item outright.

local _, ns = ...
local VendorProfit = ns.VendorProfit
local Route = VendorProfit.Route
local Recipes = VendorProfit.Recipes
local L = VendorProfit.L

local RouteSection = {}
VendorProfit.RouteSection = RouteSection

local INDENT = "    "
local SECTION_GAP = 8       -- space above the separator
local SEPARATOR_HEIGHT = 14

local function Round(copper)
    return math.floor(copper + 0.5)
end

-- Works out the section's numbers for a VendorProfit.Calculate result:
--   route          Route.ForResult's route
--   cost           crafting cost of one craft along the route
--   auctionProfit  after the auction house cut; nil with no auction price
--   vendorProfit   nil if vendors won't buy the item
function RouteSection.Calculate(result)
    local route = Route.ForResult(result)
    local cost = Round(route.cost)
    local info = { route = route, cost = cost, result = result }
    local auctionPrice = VendorProfit.GetOutputAuctionPrice(result.itemLink)
    if auctionPrice then
        info.auctionProfit = math.floor(auctionPrice * result.count * VendorProfit.GetAfterAHCut()) - cost
    end
    if result.sellPrice and result.sellPrice > 0 then
        info.vendorProfit = result.sellPrice * result.count - cost
    end
    return info
end

local function Gray(text)
    return GRAY_FONT_COLOR:WrapTextInColorCode(text)
end

-- The three lines' text: toCraft, profit, vendorProfit.
function RouteSection.Format(info)
    local toCraft = L.TO_CRAFT .. " " .. VendorProfit.FormatMoney(info.cost)
    if info.route.missing then
        toCraft = toCraft .. " " .. RED_FONT_COLOR:WrapTextInColorCode(L.MISSING_PRICES)
    end
    local profit = L.PROFIT_COLON .. " " ..
        (info.auctionProfit and VendorProfit.FormatMoney(info.auctionProfit) or Gray(L.NO_AUCTION_PRICE))
    local vendor = L.VENDOR_PROFIT .. " " ..
        (info.vendorProfit and VendorProfit.FormatMoney(info.vendorProfit) or Gray(L.NO_SELL_PRICE))
    return toCraft, profit, vendor
end

-- Tooltip ---------------------------------------------------------------------

local function FormatQuantity(n)
    if math.abs(n - math.floor(n + 0.5)) < 0.001 then
        return tostring(math.floor(n + 0.5))
    end
    return string.format("%.1f", n)
end

-- "icon Name x7". Names of items not cached yet are requested; showTooltip
-- runs again once one arrives.
local function ItemLabel(itemID, quantity, showTooltip)
    local name = C_Item.GetItemInfo(itemID)
    if name == nil then
        name = "item " .. itemID
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(showTooltip)
    end
    local icon = select(5, C_Item.GetItemInfoInstant(itemID))
    local iconText = icon and ("|T" .. icon .. ":0|t ") or ""
    return iconText .. name .. " x" .. FormatQuantity(quantity)
end

local function SourceLabel(node)
    if node.source == "craft" then
        local label = L.SOURCE_CRAFT
        local recipe = node.recipe
        if recipe then
            local details = recipe.profession or ""
            if recipe.count > 1 then
                details = details .. (details ~= "" and ", " or "") .. string.format(L.MAKES, recipe.count)
            end
            if details ~= "" then
                label = label .. " (" .. details .. ")"
            end
        end
        return GREEN_FONT_COLOR:WrapTextInColorCode(label)
    elseif node.source == "vendor" then
        return L.SOURCE_VENDOR
    elseif node.source == "auction" then
        return L.SOURCE_AUCTION
    end
    return RED_FONT_COLOR:WrapTextInColorCode(L.SOURCE_NONE)
end

local function NodeCost(node, quantity)
    if node.unitCost == nil then
        return ""
    end
    return VendorProfit.FormatMoney(node.unitCost * quantity)
end

-- For a crafted step: how much crafting it saves over buying that many
-- outright, everything under it done the cheapest way. Empty if it can't be
-- bought or there's nothing to compare.
local function Savings(node, quantity)
    if node.source ~= "craft" or node.buyCost == nil or node.unitCost == nil then
        return ""
    end
    local saves = Round(node.buyCost * quantity) - Round(node.unitCost * quantity)
    if saves <= 0 then
        return ""
    end
    return "  " .. GREEN_FONT_COLOR:WrapTextInColorCode(string.format(L.SAVES_STEP, GetMoneyString(saves, true)))
end

-- One row per reagent, children indented under the items they're crafted
-- into.
local function AddRows(tooltip, children, quantity, depth, showTooltip)
    for _, child in ipairs(children) do
        local node, amount = child.node, child.perUnit * quantity
        tooltip:AddDoubleLine(
            string.rep(INDENT, depth) .. ItemLabel(node.itemID, amount, showTooltip),
            SourceLabel(node) .. "  " .. NodeCost(node, amount) .. Savings(node, amount),
            1, 1, 1, 1, 1, 1
        )
        if node.source == "craft" then
            AddRows(tooltip, node.children, amount, depth + 1, showTooltip)
        end
    end
end

local function AddMoneyRow(tooltip, label, copper, whenNil)
    local value = copper and VendorProfit.FormatMoney(copper) or GRAY_FONT_COLOR:WrapTextInColorCode(whenNil or "")
    tooltip:AddDoubleLine(label, value)
end

function RouteSection.FillTooltip(tooltip, info, showTooltip)
    local result = info.result
    tooltip:SetText(L.ROUTE_TITLE)

    tooltip:AddDoubleLine(ItemLabel(result.itemID, result.count, showTooltip), VendorProfit.FormatMoney(info.cost), 1, 1, 1)
    AddRows(tooltip, info.route.children, 1, 1, showTooltip)

    tooltip:AddLine(" ")
    AddMoneyRow(tooltip, L.AUCTIONATOR_COST, result.cost)
    local saves = Round(result.cost) - info.cost
    if saves > 0 then
        AddMoneyRow(tooltip, L.SAVES, saves)
    end
    if info.route.missing then
        tooltip:AddLine(L.MISSING_PRICES, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
    end

    tooltip:AddLine(" ")
    local names = Recipes.ProfessionNames()
    if #names > 0 then
        tooltip:AddLine(string.format(L.RECIPES_FROM, table.concat(names, ", ")), 0.6, 0.6, 0.6, true)
    else
        tooltip:AddLine(L.NO_RECIPES, 0.6, 0.6, 0.6, true)
    end
    tooltip:AddLine(L.OPEN_PROFESSIONS, 0.6, 0.6, 0.6, true)
end

-- Section ---------------------------------------------------------------------

local function ShowTooltip(hover)
    local info = hover.info
    if info == nil then
        return
    end
    GameTooltip:SetOwner(hover, "ANCHOR_RIGHT")
    RouteSection.FillTooltip(GameTooltip, info, function()
        if GameTooltip:IsOwned(hover) then
            ShowTooltip(hover)
        end
    end)
    GameTooltip:Show()
end

local function CreateSeparator(frame, anchor)
    local separator = CreateFrame("Frame", nil, frame)
    separator:SetHeight(SEPARATOR_HEIGHT)
    separator:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -SECTION_GAP)
    separator:SetPoint("RIGHT", frame, "RIGHT")

    local label = separator:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(L.ROUTE_TITLE)
    separator.Label = label

    for _, side in ipairs({ "Left", "Right" }) do
        local line = separator:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 0.82, 0, 0.35)
        line:SetHeight(1)
        if side == "Left" then
            line:SetPoint("LEFT", separator, "LEFT")
            line:SetPoint("RIGHT", label, "LEFT", -6, 0)
        else
            line:SetPoint("LEFT", label, "RIGHT", 6, 0)
            line:SetPoint("RIGHT", separator, "RIGHT")
        end
        separator[side .. "Line"] = line
    end
    separator:Hide()
    return separator
end

local function CreateLine(frame, anchor, gap)
    local line = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    line:SetJustifyH("LEFT")
    line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
    line:Hide()
    return line
end

function RouteSection.Create(frame, anchor)
    local separator = CreateSeparator(frame, anchor)
    local toCraft = CreateLine(frame, separator, 2)
    local profit = CreateLine(frame, toCraft, 2)
    local vendor = CreateLine(frame, profit, 2)
    frame.VendorProfitRoute = { separator = separator, toCraft = toCraft, profit = profit, vendor = vendor }

    -- Font strings can't take the mouse, so a frame covers the section.
    local hover = CreateFrame("Frame", nil, frame)
    hover:SetPoint("TOPLEFT", separator, "TOPLEFT")
    hover:SetPoint("RIGHT", separator, "RIGHT")
    hover:SetPoint("BOTTOM", vendor, "BOTTOM")
    hover:EnableMouse(true)
    hover:SetScript("OnEnter", ShowTooltip)
    hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hover:Hide()
    frame.VendorProfitRoute.hover = hover
    return vendor
end

function RouteSection.Refresh(frame, result)
    local section = frame.VendorProfitRoute
    local hover = section.hover
    if result == nil then
        for _, region in pairs(section) do
            region:Hide()
        end
        hover.info = nil
        if GameTooltip:IsOwned(hover) then
            GameTooltip:Hide()
        end
        return
    end

    local info = RouteSection.Calculate(result)
    hover.info = info
    local toCraft, profit, vendor = RouteSection.Format(info)
    section.toCraft:SetText(toCraft)
    section.profit:SetText(profit)
    section.vendor:SetText(vendor)
    for _, region in pairs(section) do
        region:Show()
    end
    if GameTooltip:IsOwned(hover) then
        ShowTooltip(hover)
    end
end

VendorProfit.AddLine(RouteSection)
