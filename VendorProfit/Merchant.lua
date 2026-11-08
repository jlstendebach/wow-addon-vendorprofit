-- Buying from a vendor. With a merchant window open, the Buy step buys what
-- the order still needs that this merchant sells for gold: anything the plan
-- would get from a vendor (or has no price for), and anything planned from
-- the auction house that this merchant sells for no more.
--
-- Vendor purchases land in your bags a moment later, and the plan picks them
-- up from there; only the gold spent is recorded on the order. Until they
-- land, Buy is off, so clicking twice can't buy twice.

local ADDON_NAME, ns = ...
local VendorProfit = ns.VendorProfit
local Order = VendorProfit.Order
local L = VendorProfit.L

local Merchant = {}
VendorProfit.Merchant = Merchant

local open = false

-- Purchases the vendor hasn't delivered yet: [itemID] = { target (bag count
-- once they arrive), expires }. Until they arrive, Buy is off and they don't
-- count as still needed, so a double click can't buy twice.
local pending = {}
local PENDING_TIMEOUT = 10

function Merchant.IsOpen()
    return open
end

-- What the merchant has at index: itemID, price (for a batch of
-- stackCount), stackCount, numAvailable (-1 for unlimited), and whether it
-- costs something other than gold.
local function ItemAt(index)
    local itemID = GetMerchantItemID and GetMerchantItemID(index)
    if itemID == nil then
        local link = GetMerchantItemLink(index)
        itemID = link and tonumber(link:match("item:(%d+)"))
    end
    local price, stackCount, numAvailable, extended
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        if info then
            price, stackCount, numAvailable, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
        end
    else
        local _
        _, _, price, stackCount, numAvailable, _, _, extended = GetMerchantItemInfo(index)
    end
    if GetMerchantItemCostInfo and (GetMerchantItemCostInfo(index) or 0) > 0 then
        extended = true
    end
    return itemID, price, math.max(stackCount or 1, 1), numAvailable or -1, extended
end

-- The merchant's gold-priced items: [itemID] = { index, price, stackCount,
-- numAvailable }, the cheapest per item where it's listed twice.
local function Catalog()
    local catalog = {}
    for index = 1, GetMerchantNumItems() do
        local itemID, price, stackCount, numAvailable, extended = ItemAt(index)
        if itemID and price and price > 0 and not extended and numAvailable ~= 0 then
            local each = price / stackCount
            local known = catalog[itemID]
            if known == nil or each < known.price / known.stackCount then
                catalog[itemID] = { index = index, price = price, stackCount = stackCount, numAvailable = numAvailable }
            end
        end
    end
    return catalog
end

local function Bags(itemID)
    return (VendorProfit.Inventory.Count(itemID))
end

-- Drops purchases that have arrived or timed out. Returns whether any are
-- still on their way.
function Merchant.IsBuying()
    local now = GetTime()
    local any = false
    for itemID, purchase in pairs(pending) do
        if Bags(itemID) >= purchase.target or now >= purchase.expires then
            pending[itemID] = nil
        else
            any = true
        end
    end
    return any
end

-- What to buy here for the plan: a list of { itemID, quantity (needed),
-- index, batches, count (items bought, whole batches), cost }, in the
-- plan's buy order. Empty when no merchant is open.
function Merchant.Offers(plan)
    local offers = {}
    if not open then
        return offers
    end
    local catalog = Catalog()
    Merchant.IsBuying()
    for _, line in ipairs(plan.buyOrder) do
        local item = catalog[line.itemID]
        -- Less what's bought and still on its way.
        local quantity = line.quantity
        local purchase = pending[line.itemID]
        if purchase then
            quantity = quantity - math.max(purchase.target - Bags(line.itemID), 0)
        end
        if item and quantity > 0 then
            local each = item.price / item.stackCount
            local worthIt = line.source ~= "auction" or each <= (line.total or 0) / line.quantity
            if worthIt then
                local batches = math.ceil(quantity / item.stackCount)
                if item.numAvailable > 0 then
                    batches = math.min(batches, item.numAvailable)
                end
                offers[#offers + 1] = {
                    itemID = line.itemID, quantity = quantity, index = item.index,
                    stackCount = item.stackCount, batches = batches,
                    count = batches * item.stackCount, cost = batches * item.price, price = item.price,
                }
            end
        end
    end
    return offers
end

-- Total cost of the offers.
function Merchant.Cost(offers)
    local total = 0
    for _, offer in ipairs(offers) do
        total = total + offer.cost
    end
    return total
end

local listeners = {}
function Merchant.OnChange(fn)
    listeners[#listeners + 1] = fn
end

local function Changed()
    for _, fn in ipairs(listeners) do
        xpcall(fn, geterrorhandler())
    end
end

local function ItemName(itemID)
    return C_Item.GetItemInfo(itemID) or ("item " .. itemID)
end

-- Buys the offers, as far as your gold goes. Must be called from a click.
-- Items sold one at a time are bought in the largest stacks the merchant
-- allows; items sold in batches (5 vials, say) a batch at a time.
function Merchant.Buy(offers)
    if Merchant.IsBuying() then
        return
    end
    local money = GetMoney()
    local spent = 0
    local bought, short = {}, {}
    for _, offer in ipairs(offers) do
        local batches = math.min(offer.batches, math.floor(money / offer.price))
        if batches < offer.batches then
            short[#short + 1] = ItemName(offer.itemID)
        end
        if batches > 0 then
            local before = Bags(offer.itemID)
            if offer.stackCount == 1 then
                local left = batches
                local maxStack = math.max(GetMerchantItemMaxStack(offer.index) or 1, 1)
                while left > 0 do
                    local amount = math.min(left, maxStack)
                    BuyMerchantItem(offer.index, amount)
                    left = left - amount
                end
            else
                for _ = 1, batches do
                    BuyMerchantItem(offer.index)
                end
            end
            pending[offer.itemID] = {
                target = before + batches * offer.stackCount,
                expires = GetTime() + PENDING_TIMEOUT,
            }
            local cost = batches * offer.price
            money = money - cost
            spent = spent + cost
            bought[#bought + 1] = (batches * offer.stackCount) .. " " .. ItemName(offer.itemID)
        end
    end
    if spent > 0 then
        -- Buy comes back on by itself if something never arrives.
        C_Timer.After(PENDING_TIMEOUT, Changed)
        Order.AddSpent(spent)
        print(string.format(L.VENDOR_BOUGHT, table.concat(bought, ", "), VendorProfit.FormatMoney(spent)))
    end
    if #short > 0 then
        print(string.format(L.VENDOR_SHORT, table.concat(short, ", ")))
    end
end


-- Keeping VendorPrices.lua up to date ---------------------------------------------

-- The open vendor's prices in VendorPrices.lua's format, one line per item
-- it sells for gold without limit, sorted by ID, each marked if it's not in
-- the list or the list has another price. Returns the text and how many
-- lines are new or changed.
function Merchant.PriceLines()
    local items = {}
    for index = 1, GetMerchantNumItems() do
        local itemID, price, stackCount, numAvailable, extended = ItemAt(index)
        if itemID and price and price > 0 and not extended and numAvailable == -1 then
            local each = price / stackCount
            if items[itemID] == nil or each < items[itemID] then
                items[itemID] = each
            end
        end
    end
    local ids = {}
    for itemID in pairs(items) do
        ids[#ids + 1] = itemID
    end
    table.sort(ids)
    local known = VendorProfit.KNOWN_VENDOR_PRICES or {}
    local lines, changed = {}, 0
    for _, itemID in ipairs(ids) do
        local price = items[itemID]
        local note = ItemName(itemID)
        if known[itemID] == nil then
            note = note .. " (new)"
            changed = changed + 1
        elseif known[itemID] ~= price then
            note = note .. " (was " .. known[itemID] .. ")"
            changed = changed + 1
        end
        -- Prices per item can be fractional when sold in batches.
        local text = price == math.floor(price) and tostring(price) or string.format("%.2f", price)
        lines[#lines + 1] = string.format("    [%d] = %s, -- %s", itemID, text, note)
    end
    return table.concat(lines, "\n"), changed, #ids
end

-- A box to copy the lines from (Ctrl+C), since chat can't be copied.
local exportFrame
function Merchant.ShowPriceLines()
    if not open then
        print(L.PRICES_NO_VENDOR)
        return
    end
    local text, changed, total = Merchant.PriceLines()
    if exportFrame == nil then
        exportFrame = CreateFrame("Frame", "VendorProfitPriceExport", UIParent, "ButtonFrameTemplate")
        exportFrame:SetSize(460, 360)
        exportFrame:SetPoint("CENTER")
        exportFrame:SetFrameStrata("DIALOG")
        exportFrame:SetMovable(true)
        exportFrame:EnableMouse(true)
        exportFrame:RegisterForDrag("LeftButton")
        exportFrame:SetScript("OnDragStart", exportFrame.StartMoving)
        exportFrame:SetScript("OnDragStop", exportFrame.StopMovingOrSizing)
        if ButtonFrameTemplate_HidePortrait then
            ButtonFrameTemplate_HidePortrait(exportFrame)
        end
        if ButtonFrameTemplate_HideButtonBar then
            ButtonFrameTemplate_HideButtonBar(exportFrame)
        end
        exportFrame.note = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        exportFrame.note:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 16, -32)
        exportFrame.note:SetPoint("RIGHT", exportFrame, "RIGHT", -16, 0)
        exportFrame.note:SetJustifyH("LEFT")
        local scroll = CreateFrame("ScrollFrame", nil, exportFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 16, -64)
        scroll:SetPoint("BOTTOMRIGHT", exportFrame, "BOTTOMRIGHT", -34, 16)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(400)
        edit:SetScript("OnEscapePressed", function() exportFrame:Hide() end)
        scroll:SetScrollChild(edit)
        exportFrame.edit = edit
    end
    exportFrame:SetTitle(L.PRICES_TITLE)
    exportFrame.note:SetText(string.format(L.PRICES_NOTE, total, changed))
    exportFrame.edit:SetText(text)
    exportFrame:Show()
    exportFrame.edit:SetFocus()
    exportFrame.edit:HighlightText()
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE", "BAG_UPDATE_DELAYED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        open = true
    elseif event == "MERCHANT_CLOSED" then
        open = false
    elseif event == "BAG_UPDATE_DELAYED" then
        -- Purchases that have arrived stop being pending.
        Merchant.IsBuying()
        return
    end
    Changed()
end)
