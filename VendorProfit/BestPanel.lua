-- The Best Crafts tab of the Vendor Profit window: the open profession's top
-- recipes by profit per craft (BestCrafts.lua), losses included, with Vendor
-- and Auction tabs. Each has Show (selects it in the professions window) and
-- Queue (adds one craft to the shopping order). Live prices come from Scan.
--
-- Opened by the Vendor Profit button in the professions window's title bar,
-- or /vprofit best.

local ADDON_NAME, ns = ...
local VendorProfit = ns.VendorProfit
local BestCrafts = VendorProfit.BestCrafts
local Recipes = VendorProfit.Recipes
local Order = VendorProfit.Order
local L = VendorProfit.L

local BestPanel = {}
VendorProfit.BestPanel = BestPanel

local Panel = VendorProfit.Panel

local WIDTH = Panel.WIDTH
local PADDING = 16
local ROW_HEIGHT = 22

local frame              -- the page
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

-- The list stays up after the professions window closes (the game keeps
-- reporting the last profession), so you can scan and queue at the auction
-- house without it. Only Show needs the window open.
local function ProfessionsWindowOpen()
    return ProfessionsFrame ~= nil and ProfessionsFrame:IsShown()
end

-- Shows a recipe in the professions window, if it's open.
local function ShowRecipe(recipeID)
    if ProfessionsWindowOpen() and C_TradeSkillUI.OpenRecipe then
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
        row.show:SetMotionScriptsWhileDisabled(true)
        row.show:SetScript("OnEnter", function(self)
            if not self:IsEnabled() then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(string.format(L.BEST_SHOW_CLOSED, self.profession or ""), 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        row.show:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

local function Create(page)
    frame = page

    frame.heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -32)
    frame.heading:SetJustifyH("LEFT")

    frame.tabs = {
        vendor = SmallButton(frame, L.BEST_TAB_VENDOR, 90),
        auction = SmallButton(frame, L.BEST_TAB_AUCTION, 90),
    }
    frame.tabs.vendor:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -52)
    frame.tabs.auction:SetPoint("LEFT", frame.tabs.vendor, "RIGHT", 4, 0)
    frame.tabs.vendor:SetScript("OnClick", function() SetTab("vendor") end)
    frame.tabs.auction:SetScript("OnClick", function() SetTab("auction") end)

    frame.scan = SmallButton(frame, L.SCAN, 90)
    frame.scan:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -52)
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
    frame.heading:SetText(string.format(L.BEST_TITLE, name or ""))

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

    local y = -80
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
        row.show:SetEnabled(ProfessionsWindowOpen())
        row.show.profession = name
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
    return -y + 8 + (frame.status:GetStringHeight() or 12) + PADDING
end

function BestPanel.Refresh()
    if Panel.IsShown() and Panel.ActiveTab() == "best" then
        Panel.Refresh()
    end
end

Panel.AddPage({
    name = "best",
    icon = "Interface\\Icons\\INV_Misc_Coin_02",
    label = L.TAB_BEST,
    create = Create,
    refresh = function() return Refresh() end,
})

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

function BestPanel.IsShown()
    return Panel.IsShown() and Panel.ActiveTab() == "best"
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
-- Closing the professions window leaves it open; it says to open one.
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "BAG_UPDATE_DELAYED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", BestPanel.Refresh)

-- The Vendor Profit button in the professions window's title bar, left of
-- TradeSkillMaster's button there, so it reads as being about the whole
-- profession rather than the selected recipe. Opens the Best Crafts tab.
local titleButton

local function CreateTitleButton()
    if titleButton or ProfessionsFrame == nil then
        return
    end
    titleButton = CreateFrame("Button", "VendorProfitProfessionsButton", ProfessionsFrame, "UIPanelButtonTemplate")
    titleButton:SetSize(96, 20)
    titleButton:SetText(L.BEST_BUTTON)
    local close = ProfessionsFrame.CloseButton
    if close then
        titleButton:SetPoint("RIGHT", close, "LEFT", -84, 0)
    else
        titleButton:SetPoint("TOPRIGHT", ProfessionsFrame, "TOPRIGHT", -110, -1)
    end
    titleButton:SetFrameLevel(ProfessionsFrame:GetFrameLevel() + 10)
    titleButton:SetScript("OnClick", function() Panel.Toggle("best") end)
    titleButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.BEST_BUTTON)
        GameTooltip:AddLine(L.BEST_BUTTON_HELP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    titleButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Made when the professions window first opens (it's load-on-demand).
local titleEvents = CreateFrame("Frame")
pcall(titleEvents.RegisterEvent, titleEvents, "TRADE_SKILL_SHOW")
titleEvents:SetScript("OnEvent", CreateTitleButton)
CreateTitleButton()

function BestPanel.TitleButton()
    return titleButton
end
