-- The Queue buttons: each adds the shown recipe to the order (Order.lua), as
-- many crafts as the number in the Create box, and says so in chat.
--   * under the Cheapest Route section's Vendor Profit line: along the
--     cheapest route, crafting reagents yourself where that's cheaper;
--   * under Auctionator's section's Vendor Profit line (VendorLine.lua): the
--     exact recipe, as Auctionator prices it, its reagents bought (or taken
--     from what you have), never crafted.

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
    Order.Add(result, crafts, CurrentProfession(), button.exact)
    local name = C_Item.GetItemInfo(result.itemID) or ("item " .. result.itemID)
    -- Said in chat; the window is left as it is (it only opens when you
    -- open it).
    print(string.format(L.QUEUED, crafts, name))
end

local function OnEnter(button)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.QUEUE)
    local help = button.exact and L.QUEUE_EXACT_HELP or L.QUEUE_HELP
    GameTooltip:AddLine(string.format(help, QueueButton.GetCraftCount()), 1, 1, 1, true)
    GameTooltip:Show()
end

local function MakeButton(frame)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(64, 20)
    button:SetText(L.QUEUE)
    -- Above the frame that shows the route tooltip, so clicks reach it.
    button:SetFrameLevel(frame:GetFrameLevel() + 5)
    button:SetScript("OnClick", OnClick)
    button:SetScript("OnEnter", OnEnter)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()
    return button
end

-- Only worth queuing something a vendor will buy.
local function Queueable(result)
    return result ~= nil and result.status == "ok"
end

function QueueButton.Create(frame, anchor)
    local button = MakeButton(frame)
    button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
    frame.VendorProfitQueueButton = button
    return button
end

function QueueButton.Refresh(frame, result)
    local button = frame.VendorProfitQueueButton
    button.result = result
    button:SetShown(Queueable(result))
end

-- The exact recipe's button, under the Vendor Profit line (anchor). The
-- Cheapest Route section hangs under it, so when it's hidden it folds to
-- nothing rather than leave a gap.
local EXACT_GAP, BUTTON_HEIGHT = 6, 20

function QueueButton.CreateExact(frame, anchor)
    local button = MakeButton(frame)
    button.exact = true
    button.anchor = anchor
    frame.VendorProfitExactQueueButton = button
    QueueButton.RefreshExact(frame, nil)
    return button
end

function QueueButton.RefreshExact(frame, result)
    local button = frame.VendorProfitExactQueueButton
    button.result = result
    local shown = Queueable(result)
    if shown ~= button.placedShown then
        button.placedShown = shown
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", button.anchor, "BOTTOMLEFT", 0, shown and -EXACT_GAP or 0)
        button:SetHeight(shown and BUTTON_HEIGHT or 0.001)
    end
    button:SetShown(shown)
end

VendorProfit.AddLine(QueueButton)
