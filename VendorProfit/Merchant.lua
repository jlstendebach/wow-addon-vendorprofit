-- Buying from a vendor. With a merchant window open, the Buy step buys what
-- the order still needs that this merchant sells for gold: anything the plan
-- would get from a vendor (or has no price for), and anything planned from
-- the auction house that this merchant sells for no more.
--
-- Vendor purchases land in your bags straight away, so the plan picks them
-- up from there; only the gold spent is recorded on the order.

local ADDON_NAME, ns = ...
local VendorProfit = ns.VendorProfit
local Order = VendorProfit.Order
local L = VendorProfit.L

local Merchant = {}
VendorProfit.Merchant = Merchant

local open = false

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

-- What to buy here for the plan: a list of { itemID, quantity (needed),
-- index, batches, count (items bought, whole batches), cost }, in the
-- plan's buy order. Empty when no merchant is open.
function Merchant.Offers(plan)
    local offers = {}
    if not open then
        return offers
    end
    local catalog = Catalog()
    for _, line in ipairs(plan.buyOrder) do
        local item = catalog[line.itemID]
        if item and line.quantity > 0 then
            local each = item.price / item.stackCount
            local worthIt = line.source ~= "auction" or each <= (line.total or 0) / line.quantity
            if worthIt then
                local batches = math.ceil(line.quantity / item.stackCount)
                if item.numAvailable > 0 then
                    batches = math.min(batches, item.numAvailable)
                end
                offers[#offers + 1] = {
                    itemID = line.itemID, quantity = line.quantity, index = item.index,
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

local function ItemName(itemID)
    return C_Item.GetItemInfo(itemID) or ("item " .. itemID)
end

-- Buys the offers, as far as your gold goes. Must be called from a click.
-- Items sold one at a time are bought in the largest stacks the merchant
-- allows; items sold in batches (5 vials, say) a batch at a time.
function Merchant.Buy(offers)
    local money = GetMoney()
    local spent = 0
    local bought, short = {}, {}
    for _, offer in ipairs(offers) do
        local batches = math.min(offer.batches, math.floor(money / offer.price))
        if batches < offer.batches then
            short[#short + 1] = ItemName(offer.itemID)
        end
        if batches > 0 then
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
            local cost = batches * offer.price
            money = money - cost
            spent = spent + cost
            bought[#bought + 1] = (batches * offer.stackCount) .. " " .. ItemName(offer.itemID)
        end
    end
    if spent > 0 then
        Order.AddSpent(spent)
        print(string.format(L.VENDOR_BOUGHT, table.concat(bought, ", "), VendorProfit.FormatMoney(spent)))
    end
    if #short > 0 then
        print(string.format(L.VENDOR_SHORT, table.concat(short, ", ")))
    end
end

local listeners = {}
function Merchant.OnChange(fn)
    listeners[#listeners + 1] = fn
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        open = true
    elseif event == "MERCHANT_CLOSED" then
        open = false
    end
    for _, fn in ipairs(listeners) do
        xpcall(fn, geterrorhandler())
    end
end)
