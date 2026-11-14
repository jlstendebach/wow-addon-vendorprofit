-- The Vendor Profit line: what the craft makes if the result is sold to a
-- vendor, using Auctionator's To Craft cost:
--
--     vendor sell price x number made - cost to craft
--
-- Under it, a Queue button for the exact recipe (QueueButton.lua).

local _, ns = ...
local VendorProfit = ns.VendorProfit
local L = VendorProfit.L

local VendorLine = {}
VendorProfit.VendorLine = VendorLine

-- The line's text for a VendorProfit.Calculate result.
function VendorLine.Format(result)
    local value
    if result.status == "noSell" then
        value = GRAY_FONT_COLOR:WrapTextInColorCode(L.NO_SELL_PRICE)
    else
        value = VendorProfit.FormatMoney(result.profit)
    end

    local text = L.VENDOR_PROFIT .. " " .. value
    if result.missingPrices and result.status == "ok" then
        text = text .. " " .. RED_FONT_COLOR:WrapTextInColorCode(L.MISSING_PRICES)
    end
    return text
end

function VendorLine.Create(frame, anchor)
    local line = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    line:SetJustifyH("LEFT")
    line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    line:Hide()
    frame.VendorProfitLine = line
    -- The next line (the Cheapest Route) hangs under the button.
    return VendorProfit.QueueButton.CreateExact(frame, line)
end

function VendorLine.Refresh(frame, result)
    local line = frame.VendorProfitLine
    VendorProfit.QueueButton.RefreshExact(frame, result)
    if result == nil then
        line:Hide()
        return
    end
    line:SetText(VendorLine.Format(result))
    line:Show()
end

VendorProfit.AddLine(VendorLine)
