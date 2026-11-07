-- The Best Crafts panel: the open profession's top recipes by profit per
-- craft (BestCrafts.lua), with Vendor and Auction tabs. Each has Show (selects
-- it in the professions window) and Queue (adds one craft to the shopping
-- order). It docks beside the professions window: on its left if there's
-- room, otherwise on its right (past the shopping panel if that's there). It
-- can be dragged, remembers where it was left (per character, until
-- /vprofit reset), stays on screen, and closes with the professions window.
--
-- Opened by the Best Crafts button under the Cheapest Route section, or
-- /vprofit best.

local ADDON_NAME, ns = ...
local VendorProfit = ns.VendorProfit
local BestCrafts = VendorProfit.BestCrafts
local Recipes = VendorProfit.Recipes
local Order = VendorProfit.Order
local L = VendorProfit.L

local BestPanel = {}
VendorProfit.BestPanel = BestPanel

local WIDTH = 400
local PADDING = 16
local ROW_HEIGHT = 22

local frame
local tab = "vendor"
local rows = {}

local function ItemLabel(itemID)
    local name = C_Item.GetItemInfo(itemID)
    if name == nil then
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function() BestPanel.Refresh() end)
        name = "item " .. itemID
    end
    local icon = select(5, C_Item.GetItemInfoInstant(itemID))
    return (icon and ("|T" .. icon .. ":0|t ") or "") .. name
end

local function Gray(text)
    return GRAY_FONT_COLOR:WrapTextInColorCode(text)
end

-- Shows a recipe in the professions window.
local function ShowRecipe(recipeID)
    if C_TradeSkillUI.OpenRecipe then
        C_TradeSkillUI.OpenRecipe(recipeID)
    end
end

local function QueueRecipe(entry)
    local recipe = entry.recipe
    Order.AddRecipe({
        itemID = recipe.item, recipeID = recipe.recipeID, profession = recipe.profession,
        count = recipe.count, reagents = recipe.reagents,
        sellPrice = select(11, C_Item.GetItemInfo(recipe.item)),
    }, 1)
    print(string.format(L.QUEUED, 1, C_Item.GetItemInfo(recipe.item) or ("item " .. recipe.item)))
    if VendorProfit.Panel then
        VendorProfit.Panel.Show()
    end
    -- The shopping panel may have opened where this one is.
    BestPanel.Dock()
end

local function SmallButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 20)
    button:SetText(text)
    return button
end

local function GetRow(index)
    local row = rows[index]
    if row == nil then
        row = {}
        row.left = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.left:SetJustifyH("LEFT")
        row.left:SetWordWrap(false)
        row.left:SetWidth(WIDTH * 0.45)
        row.right = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.right:SetJustifyH("RIGHT")
        row.queue = SmallButton(frame, L.QUEUE, 56)
        row.show = SmallButton(frame, L.BEST_SHOW, 50)
        row.queue:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L.BEST_QUEUE_HELP, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row.queue:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[index] = row
    end
    return row
end

local function SetTab(name)
    tab = name
    BestPanel.Refresh()
end

local function Create()
    frame = CreateFrame("Frame", "VendorProfitBestCrafts", UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(frame)
    ButtonFrameTemplate_HideButtonBar(frame)
    if frame.Inset then
        frame.Inset:Hide()
    end
    frame:SetWidth(WIDTH)
    frame:SetHeight(200)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Saved by the addon, not the game's own layout cache.
        self:SetUserPlaced(false)
        VendorProfitCharDB = VendorProfitCharDB or {}
        VendorProfitCharDB.bestPanel = { left = self:GetLeft(), top = self:GetTop() }
    end)
    frame:Hide()

    frame.tabs = {
        vendor = SmallButton(frame, L.BEST_TAB_VENDOR, 90),
        auction = SmallButton(frame, L.BEST_TAB_AUCTION, 90),
    }
    frame.tabs.vendor:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -30)
    frame.tabs.auction:SetPoint("LEFT", frame.tabs.vendor, "RIGHT", 4, 0)
    frame.tabs.vendor:SetScript("OnClick", function() SetTab("vendor") end)
    frame.tabs.auction:SetScript("OnClick", function() SetTab("auction") end)

    frame.scan = SmallButton(frame, L.SCAN, 90)
    frame.scan:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -30)
    frame.scan:SetMotionScriptsWhileDisabled(true)
    frame.scan:SetScript("OnClick", function()
        BestCrafts.Scan(Recipes.OpenProfession())
    end)
    frame.scan:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltip or "", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.scan:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.status:SetJustifyH("LEFT")
    frame.status:SetWidth(WIDTH - 2 * PADDING)
end

local function Refresh()
    local profession, name = Recipes.OpenProfession()
    frame:SetTitle(string.format(L.BEST_TITLE, name or ""))

    -- Tabs: the selected one stays lit.
    for key, button in pairs(frame.tabs) do
        if key == tab then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end

    -- Scan button.
    local scan = frame.scan
    if BestCrafts.IsScanning() then
        local batch, batches = BestCrafts.Progress()
        scan:SetText(L.BUY_SCANNING)
        scan:SetEnabled(false)
        scan.tooltip = batch and string.format(L.BEST_SCANNING, batch, batches) or L.BUY_SCANNING
    else
        scan:SetText(L.SCAN)
        scan:SetEnabled(profession ~= nil and BestCrafts.CanScan())
        scan.tooltip = BestCrafts.CanScan() and L.BEST_SCAN_HELP or L.BEST_SCAN_OPEN_AH
    end

    local y = -58
    local used = 0
    local ranked = {}
    if profession then
        ranked = BestCrafts.Rank(profession, tab, function() BestPanel.Refresh() end)
    end
    for index, entry in ipairs(ranked) do
        used = index
        local row = GetRow(index)
        row.left:ClearAllPoints()
        row.left:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y - 4)
        row.left:SetText(index .. ". " .. ItemLabel(entry.recipe.item))
        row.left:Show()
        row.show:ClearAllPoints()
        row.show:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, y)
        row.show:SetScript("OnClick", function() ShowRecipe(entry.recipe.recipeID) end)
        row.show:Show()
        row.queue:ClearAllPoints()
        row.queue:SetPoint("RIGHT", row.show, "LEFT", -4, 0)
        row.queue:SetScript("OnClick", function() QueueRecipe(entry) end)
        row.queue:Show()
        row.right:ClearAllPoints()
        row.right:SetPoint("RIGHT", row.queue, "LEFT", -8, 0)
        row.right:SetText(VendorProfit.FormatMoney(entry.profit))
        row.right:Show()
        y = y - ROW_HEIGHT
    end
    for index = used + 1, #rows do
        local row = rows[index]
        row.left:Hide()
        row.right:Hide()
        row.show:Hide()
        row.queue:Hide()
    end

    -- Status: why the list is empty, where prices are from, and messages.
    local lines = {}
    if profession == nil then
        lines[#lines + 1] = L.BEST_OPEN_PROFESSION
    elseif #ranked == 0 then
        lines[#lines + 1] = L.BEST_NONE
    end
    local liveTime = profession and BestCrafts.LiveTime(profession)
    if liveTime then
        lines[#lines + 1] = string.format(L.BEST_LIVE_PRICES, date("%H:%M", liveTime))
    elseif profession then
        lines[#lines + 1] = L.BEST_AUCTIONATOR_PRICES
    end
    local text, isError = BestCrafts.Message()
    if text then
        lines[#lines + 1] = isError and RED_FONT_COLOR:WrapTextInColorCode(text) or text
    end
    frame.status:ClearAllPoints()
    frame.status:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y - 8)
    frame.status:SetText(table.concat(lines, "\n"))
    frame:SetHeight(-y + 8 + (frame.status:GetStringHeight() or 12) + PADDING)
end

function BestPanel.Refresh()
    if frame == nil or not frame:IsShown() then
        return
    end
    xpcall(Refresh, geterrorhandler())
end

-- Where it opens: where you left it, else beside the professions window.
function BestPanel.Dock()
    if frame == nil then
        return
    end
    frame:ClearAllPoints()
    local saved = VendorProfitCharDB and VendorProfitCharDB.bestPanel
    if saved and saved.left and saved.top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.left, saved.top)
        return
    end
    if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then
        frame:SetPoint("CENTER", UIParent, "CENTER")
        return
    end
    -- Room on the left of the professions window? (It usually opens at the
    -- left edge of the screen.)
    local left = ProfessionsFrame:GetLeft()
    local scale = ProfessionsFrame:GetEffectiveScale() / frame:GetEffectiveScale()
    if left and left * scale >= WIDTH + 8 then
        frame:SetPoint("TOPRIGHT", ProfessionsFrame, "TOPLEFT", -4, 0)
        return
    end
    local shopping = VendorProfitPanel
    if shopping and shopping:IsShown() then
        frame:SetPoint("TOPLEFT", shopping, "TOPRIGHT", 4, 0)
    else
        frame:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 4, 0)
    end
end

-- Forgets where you moved it, so it docks again.
function BestPanel.ResetPosition()
    if VendorProfitCharDB then
        VendorProfitCharDB.bestPanel = nil
    end
    BestPanel.Dock()
end

function BestPanel.Show()
    if frame == nil then
        Create()
    end
    BestPanel.Dock()
    frame:Show()
    BestPanel.Refresh()
end

function BestPanel.Hide()
    if frame then
        frame:Hide()
    end
end

function BestPanel.IsShown()
    return frame ~= nil and frame:IsShown()
end

function BestPanel.Toggle()
    if BestPanel.IsShown() then
        BestPanel.Hide()
    else
        BestPanel.Show()
    end
end

-- The rows shown, as "left | right" text (for tests and debugging), and the
-- tab and Scan buttons.
function BestPanel.Lines()
    local lines = {}
    for _, row in ipairs(rows) do
        if row.left:IsShown() then
            lines[#lines + 1] = row.left:GetText() .. " | " .. row.right:GetText()
        end
    end
    return lines
end

-- A shown row's regions: left, right, show, queue. For tests and debugging.
function BestPanel.Row(index)
    return rows[index]
end

function BestPanel.Frame()
    return frame
end

function BestPanel.Tab()
    return tab
end

BestCrafts.OnChange(BestPanel.Refresh)
-- Auctionator's prices changing (its scans, or saving browse results).
if Auctionator.API.v1.RegisterForDBUpdate then
    Auctionator.API.v1.RegisterForDBUpdate(ADDON_NAME, BestPanel.Refresh)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED", "BAG_UPDATE_DELAYED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "TRADE_SKILL_CLOSE" then
        BestPanel.Hide()
    else
        BestPanel.Refresh()
    end
end)

-- The Best Crafts button, beside Queue under the Cheapest Route section.
local BestButton = {}

function BestButton.Create(frame2, anchor)
    local button = CreateFrame("Button", nil, frame2, "UIPanelButtonTemplate")
    button:SetSize(96, 20)
    button:SetText(L.BEST_BUTTON)
    button:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    button:SetFrameLevel(frame2:GetFrameLevel() + 5)
    button:SetScript("OnClick", BestPanel.Toggle)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.BEST_BUTTON)
        GameTooltip:AddLine(L.BEST_BUTTON_HELP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()
    frame2.VendorProfitBestButton = button
    return anchor
end

function BestButton.Refresh(frame2, result)
    frame2.VendorProfitBestButton:SetShown(result ~= nil)
end

VendorProfit.AddLine(BestButton)
