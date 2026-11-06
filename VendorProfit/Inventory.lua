-- How many of an item this character has, in bags and in the bank.
--
-- The bank count is the game's saved count from the last bank visit, so it's
-- known anywhere, but it can be out of date until the bank is opened again.

local _, ns = ...
local VendorProfit = ns.VendorProfit

local Inventory = {}
VendorProfit.Inventory = Inventory

-- Returns bags, bank (bank includes the reagent bank).
function Inventory.Count(itemID)
    local bags = C_Item.GetItemCount(itemID, false, false, false) or 0
    local total = C_Item.GetItemCount(itemID, true, false, true) or 0
    return bags, math.max(total - bags, 0)
end

function Inventory.Total(itemID)
    local bags, bank = Inventory.Count(itemID)
    return bags + bank
end
