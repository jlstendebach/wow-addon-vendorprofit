-- The Queue button under the Cheapest Route section's Vendor Profit line:
-- adds the shown recipe to the order
-- (Order.lua), as many crafts as the number in the Create box, and opens the
-- shopping panel.

local _, ns = ...
local VendorProfit = ns.VendorProfit
local Order = VendorProfit.Order
local L = VendorProfit.L

local QueueButton = {}
VendorProfit.QueueButton = QueueButton

-- The number in the professions window's Create box, or 1.
function QueueButton.GetCraftCount()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local box = page and page.CreateMultipleInputBox
    local value = box and box.GetValue and box:GetValue()
    value = tonumber(value)
    if value == nil or value < 1 then
        return 1
    end
    return math.floor(value)
end

local function CurrentProfession()
    local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    return info and info.professionName
end

local function OnClick(button)
    local result = button.result
    if result == nil then
        return
    end
    local crafts = QueueButton.GetCraftCount()
    Order.Add(result, crafts, CurrentProfession())
    local name = C_Item.GetItemInfo(result.itemID) or ("item " .. result.itemID)
    print(string.format(L.QUEUED, crafts, name))
    if VendorProfit.Panel then
        VendorProfit.Panel.Show()
    end
end

local function OnEnter(button)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.QUEUE)
    GameTooltip:AddLine(string.format(L.QUEUE_HELP, QueueButton.GetCraftCount()), 1, 1, 1, true)
    GameTooltip:Show()
end

function QueueButton.Create(frame, anchor)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(64, 20)
    button:SetText(L.QUEUE)
    button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
    -- Above the frame that shows the route tooltip, so clicks reach it.
    button:SetFrameLevel(frame:GetFrameLevel() + 5)
    button:SetScript("OnClick", OnClick)
    button:SetScript("OnEnter", OnEnter)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()
    frame.VendorProfitQueueButton = button
    return button
end

function QueueButton.Refresh(frame, result)
    local button = frame.VendorProfitQueueButton
    button.result = result
    -- Only worth queuing something a vendor will buy.
    button:SetShown(result ~= nil and result.status == "ok")
end

VendorProfit.AddLine(QueueButton)
