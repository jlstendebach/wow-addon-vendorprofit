-- The Route Profit line: profit using the cheapest route to every reagent
-- (Route.lua), sold wherever pays more, auction house or vendor. Hovering it
-- shows the route as a tree with the crafting cost and both profits.

local ADDON_NAME, ns = ...
local VendorProfit = ns.VendorProfit
local Route = VendorProfit.Route
local Recipes = VendorProfit.Recipes
local L = VendorProfit.L

local RouteLine = {}
VendorProfit.RouteLine = RouteLine

local INDENT = "    "

local function Round(copper)
    return math.floor(copper + 0.5)
end

-- Works out the line's numbers for a VendorProfit.Calculate result:
--   route          Route.ForResult's route
--   cost           crafting cost of one craft along the route
--   auctionProfit  after the auction house cut, or nil with no auction price
--   vendorProfit   nil if vendors won't buy it
--   best, bestBy   the higher of the two and "auction" or "vendor"; nil if
--                  there's nowhere to sell
function RouteLine.Calculate(result)
    local route = Route.ForResult(result)
    local cost = Round(route.cost)
    local info = { route = route, cost = cost, result = result }

    local auctionPrice = Auctionator.API.v1.GetAuctionPriceByItemLink(ADDON_NAME, result.itemLink)
    if auctionPrice then
        info.auctionProfit = math.floor(auctionPrice * result.count * VendorProfit.GetAfterAHCut()) - cost
    end
    if result.sellPrice and result.sellPrice > 0 then
        info.vendorProfit = result.sellPrice * result.count - cost
    end

    if info.auctionProfit and (info.vendorProfit == nil or info.auctionProfit > info.vendorProfit) then
        info.best, info.bestBy = info.auctionProfit, "auction"
    elseif info.vendorProfit then
        info.best, info.bestBy = info.vendorProfit, "vendor"
    end
    return info
end

function RouteLine.Format(info)
    local text
    if info.best == nil then
        text = L.ROUTE_PROFIT .. " " .. GRAY_FONT_COLOR:WrapTextInColorCode(L.NO_SALE_PRICE)
    else
        local by = info.bestBy == "auction" and L.BY_AUCTION or L.BY_VENDOR
        text = L.ROUTE_PROFIT .. " " .. VendorProfit.FormatMoney(info.best) .. " " .. GRAY_FONT_COLOR:WrapTextInColorCode("(" .. by .. ")")
    end
    if info.route.missing then
        text = text .. " " .. RED_FONT_COLOR:WrapTextInColorCode(L.MISSING_PRICES)
    end
    return text
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

-- One row per reagent, children indented under the items they're crafted
-- into.
local function AddRows(tooltip, children, quantity, depth, showTooltip)
    for _, child in ipairs(children) do
        local node, amount = child.node, child.perUnit * quantity
        tooltip:AddDoubleLine(
            string.rep(INDENT, depth) .. ItemLabel(node.itemID, amount, showTooltip),
            SourceLabel(node) .. "  " .. NodeCost(node, amount),
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

function RouteLine.FillTooltip(tooltip, info, showTooltip)
    local result = info.result
    tooltip:SetText(L.ROUTE_TITLE)

    tooltip:AddDoubleLine(ItemLabel(result.itemID, result.count, showTooltip), VendorProfit.FormatMoney(info.cost), 1, 1, 1)
    AddRows(tooltip, info.route.children, 1, 1, showTooltip)

    tooltip:AddLine(" ")
    AddMoneyRow(tooltip, L.CRAFTING_COST, info.cost)
    AddMoneyRow(tooltip, L.AUCTIONATOR_COST, result.cost)
    local saves = Round(result.cost) - info.cost
    if saves > 0 then
        AddMoneyRow(tooltip, L.SAVES, saves)
    end
    AddMoneyRow(tooltip, L.AUCTION_PROFIT, info.auctionProfit, L.NO_AUCTION_PRICE)
    AddMoneyRow(tooltip, L.VENDOR_PROFIT_SHORT, info.vendorProfit, L.NO_SELL_PRICE)
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

-- Line ------------------------------------------------------------------------

local function ShowTooltip(hover)
    local info = hover.info
    if info == nil then
        return
    end
    GameTooltip:SetOwner(hover, "ANCHOR_RIGHT")
    RouteLine.FillTooltip(GameTooltip, info, function()
        if GameTooltip:IsOwned(hover) then
            ShowTooltip(hover)
        end
    end)
    GameTooltip:Show()
end

function RouteLine.Create(frame, anchor)
    local line = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    line:SetJustifyH("LEFT")
    line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    line:Hide()
    frame.VendorProfitRouteLine = line

    -- Font strings can't take the mouse, so a frame covers the line.
    local hover = CreateFrame("Frame", nil, frame)
    hover:SetAllPoints(line)
    hover:EnableMouse(true)
    hover:SetScript("OnEnter", ShowTooltip)
    hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hover:Hide()
    frame.VendorProfitRouteHover = hover
    return line
end

function RouteLine.Refresh(frame, result)
    local line, hover = frame.VendorProfitRouteLine, frame.VendorProfitRouteHover
    if result == nil then
        line:Hide()
        hover:Hide()
        hover.info = nil
        if GameTooltip:IsOwned(hover) then
            GameTooltip:Hide()
        end
        return
    end

    local info = RouteLine.Calculate(result)
    hover.info = info
    line:SetText(RouteLine.Format(info))
    line:Show()
    hover:Show()
    if GameTooltip:IsOwned(hover) then
        ShowTooltip(hover)
    end
end

VendorProfit.AddLine(RouteLine)
