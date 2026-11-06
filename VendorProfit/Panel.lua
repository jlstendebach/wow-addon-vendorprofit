-- The shopping panel: the queued order, what to buy, what you already have,
-- what to craft, the order's profit, and the scan, buy and craft buttons.
--
-- It docks beside the auction house when that's open (and opens there by
-- itself if something is queued), otherwise beside the professions window.
-- Drag it to move it: from then on it opens where you left it, saved per
-- character, until /vprofit reset docks it again. /vprofit or /vendorprofit
-- toggles it.

local _, ns = ...
local VendorProfit = ns.VendorProfit
local Order = VendorProfit.Order
local Shopper = VendorProfit.Shopper
local Inventory = VendorProfit.Inventory
local Crafter = VendorProfit.Crafter
local L = VendorProfit.L

local Panel = {}
VendorProfit.Panel = Panel

local WIDTH = 380
local PADDING = 16
local TOP = -32
local ROW_HEIGHT = 15
local HEADING_HEIGHT = 20
local BUTTON_HEIGHT = 22

local frame
local rows = {}
local usedRows = 0
local y

-- Items ------------------------------------------------------------------------

local function ItemName(itemID)
    local name = C_Item.GetItemInfo(itemID)
    if name == nil then
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function() Panel.Refresh() end)
        return "item " .. itemID
    end
    return name
end

local function ItemLabel(itemID, quantity)
    local icon = select(5, C_Item.GetItemInfoInstant(itemID))
    local iconText = icon and ("|T" .. icon .. ":0|t ") or ""
    return iconText .. ItemName(itemID) .. " x" .. quantity
end

local function Gray(text)
    return GRAY_FONT_COLOR:WrapTextInColorCode(text)
end

local function Red(text)
    return RED_FONT_COLOR:WrapTextInColorCode(text)
end

local function Money(copper)
    return VendorProfit.FormatMoney(copper)
end

-- Rows ---------------------------------------------------------------------------

local function GetRow(index)
    local row = rows[index]
    if row == nil then
        row = {}
        row.left = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.left:SetJustifyH("LEFT")
        row.left:SetWordWrap(false)
        row.right = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.right:SetJustifyH("RIGHT")
        row.right:SetWordWrap(false)
        row.button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        row.button:SetSize(60, 16)
        rows[index] = row
    end
    return row
end

-- kind: "heading", "row" or "note". onRemove adds a Remove button.
local function AddRow(kind, left, right, onRemove)
    usedRows = usedRows + 1
    local row = GetRow(usedRows)
    local height = kind == "heading" and HEADING_HEIGHT or ROW_HEIGHT
    if kind == "heading" then
        y = y - 4
    end

    row.left:SetFontObject(kind == "heading" and "GameFontNormal" or "GameFontHighlightSmall")
    row.left:ClearAllPoints()
    row.left:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
    row.left:SetText(kind == "note" and Gray(left) or left)
    row.left:SetWordWrap(kind == "note")
    row.left:SetWidth(kind == "note" and (WIDTH - 2 * PADDING) or (WIDTH * 0.55))
    row.left:Show()

    row.right:ClearAllPoints()
    row.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING - (onRemove and 64 or 0), y)
    row.right:SetText(right or "")
    row.right:SetShown(right ~= nil)

    row.button:ClearAllPoints()
    if onRemove then
        row.button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, y + 2)
        row.button:SetText(L.REMOVE)
        row.button:SetScript("OnClick", onRemove)
        row.button:Show()
    else
        row.button:Hide()
    end

    if kind == "note" then
        height = math.max(ROW_HEIGHT, (row.left:GetStringHeight() or 0) + 3)
    end
    y = y - height
end

local function HideUnusedRows()
    for index = usedRows + 1, #rows do
        local row = rows[index]
        row.left:Hide()
        row.right:Hide()
        row.button:Hide()
    end
end

-- Content ----------------------------------------------------------------------

local function BuyLineRight(line)
    if line.source == "vendor" then
        return L.SOURCE_VENDOR .. "  " .. Money(line.total)
    elseif line.source == nil then
        return Red(L.SOURCE_NONE)
    elseif line.manual then
        return Gray(L.BUY_YOURSELF) .. "  " .. Money(line.total)
    elseif line.unscanned and Shopper.IsOpen() then
        return Gray(L.NOT_SCANNED) .. "  " .. Money(line.total)
    elseif line.listed and line.listed < line.quantity then
        return Red(string.format(L.ONLY_LISTED, line.listed)) .. "  " .. Money(line.total)
    end
    return L.SOURCE_AUCTION .. "  " .. Money(line.total)
end

local function SortedUses(uses)
    local list = {}
    for itemID, quantity in pairs(uses) do
        list[#list + 1] = { itemID = itemID, quantity = quantity }
    end
    table.sort(list, function(a, b) return a.itemID < b.itemID end)
    return list
end

local function AddContent()
    local s = Shopper.Summary()
    local plan = s.plan

    AddRow("heading", L.HEAD_QUEUED)
    local entries = Order.Entries()
    if #entries == 0 then
        AddRow("note", L.NOTHING_QUEUED)
    end
    for index, entry in ipairs(entries) do
        AddRow("row", ItemLabel(entry.itemID, entry.crafts * entry.count), nil, function()
            Order.Remove(index)
        end)
    end
    if #entries == 0 then
        return
    end

    AddRow("heading", L.HEAD_BUY)
    if #plan.buyOrder == 0 then
        AddRow("note", L.NOTHING_TO_BUY)
    end
    for _, line in ipairs(plan.buyOrder) do
        AddRow("row", ItemLabel(line.itemID, line.quantity), BuyLineRight(line))
    end

    local uses = SortedUses(plan.uses)
    if #uses > 0 then
        AddRow("heading", L.HEAD_HAVE)
        for _, use in ipairs(uses) do
            local _, bank = Inventory.Count(use.itemID)
            local notes = {}
            if bank > 0 then
                notes[#notes + 1] = string.format(L.IN_BANK, bank)
            end
            local inMail = Order.InMail(use.itemID)
            if inMail > 0 then
                notes[#notes + 1] = string.format(L.IN_MAIL, inMail)
            end
            local right = #notes > 0 and Gray(table.concat(notes, ", ")) or nil
            AddRow("row", ItemLabel(use.itemID, use.quantity), right)
        end
    end

    AddRow("heading", L.HEAD_CRAFT)
    for _, step in ipairs(plan.crafts) do
        local detail = string.format(L.CRAFTS, step.crafts)
        if step.profession then
            detail = step.profession .. ", " .. detail
        end
        AddRow("row", ItemLabel(step.itemID, step.crafts * step.makes), Gray(detail))
    end

    AddRow("heading", L.HEAD_PROFIT)
    AddRow("row", L.SELLS_FOR, Money(s.revenue))
    if s.ownedValue > 0 then
        AddRow("row", L.ITEMS_USED, Money(-s.ownedValue))
    end
    AddRow("row", L.STILL_TO_BUY, Money(-s.remaining))
    AddRow("row", L.PROFIT, Money(s.profit))
    if s.spent > 0 then
        AddRow("row", Gray(L.SPENT), Gray(GetMoneyString(s.spent, true)))
    end

    if not Shopper.IsOpen() then
        AddRow("note", L.PRICES_AUCTIONATOR)
    elseif #s.unscanned > 0 then
        AddRow("note", L.SCAN_FOR_LIVE)
    end
    if #s.short > 0 then
        AddRow("note", L.SHORT_NOTE)
    end
    if plan.missing then
        AddRow("note", L.MISSING_NOTE)
    end
    if s.profit < 0 then
        AddRow("note", Red(L.NOT_PROFITABLE))
    end
end

-- Buttons ----------------------------------------------------------------------

local function BuyButtonState()
    local status = Shopper.Status()
    if status == "closed" then
        return L.BUTTON_OPEN_AH, false
    elseif status == "idle" then
        return L.BUTTON_SCAN_FIRST, false
    elseif status == "scanning" then
        local done, total = Shopper.ScanProgress()
        return string.format(L.BUTTON_SCANNING, math.min(done + 1, total), total), false
    elseif status == "quoting" then
        return L.BUTTON_QUOTING, false
    elseif status == "buying" then
        return L.BUTTON_BUYING, false
    elseif status == "confirm" then
        local p = Shopper.Purchase()
        return string.format(L.BUTTON_CONFIRM, p.quantity, ItemName(p.itemID), Money(p.quote)), true
    end
    local nextPurchase = Shopper.NextPurchase()
    if nextPurchase == nil then
        return L.BUTTON_NOTHING, false
    end
    if not Shopper.IsProfitable() and not Shopper.IsOverridden() then
        return L.BUTTON_NOT_PROFITABLE, false
    end
    return string.format(L.BUTTON_BUY, nextPurchase.quantity, ItemName(nextPurchase.itemID), Money(nextPurchase.budget)), true
end

local function CraftButtonState()
    if Crafter.IsCasting() then
        return L.CRAFTING, false
    end
    local nextCraft = Crafter.Next()
    if nextCraft == nil then
        return L.NOTHING_TO_CRAFT, false
    end
    local name = ItemName(nextCraft.step.itemID)
    if nextCraft.open then
        return string.format(L.OPEN_TO_CRAFT, nextCraft.open, name), false
    elseif nextCraft.materials then
        return string.format(L.NEED_MATERIALS, name), false
    elseif nextCraft.crafts == 1 then
        return string.format(L.CRAFT_ONCE, name), true
    end
    return string.format(L.CRAFT_TIMES, name, nextCraft.crafts), true
end

local function LayoutButtons()
    local b = frame.buttons
    local status = Shopper.Status()

    local text, enabled = BuyButtonState()
    b.buy:SetText(text)
    b.buy:SetEnabled(enabled)

    local craftText, craftEnabled = CraftButtonState()
    b.craft:SetText(craftText)
    b.craft:SetEnabled(craftEnabled and not Order.IsEmpty())

    b.scan:SetText(status == "ready" and L.SCAN_AGAIN or L.SCAN)
    b.scan:SetEnabled((status == "idle" or status == "ready") and not Order.IsEmpty())

    local quoting = status == "quoting" or status == "confirm"
    b.cancel:SetShown(quoting)
    b.anyway:SetShown(not quoting and status == "ready" and not Shopper.IsProfitable()
        and not Shopper.IsOverridden() and Shopper.NextPurchase() ~= nil)

    b.clear:SetEnabled(not Order.IsEmpty() and not quoting and status ~= "buying")
    b.recount:SetEnabled(Order.HasMail())

    -- Message above the buttons.
    local text2, isError = Shopper.Message()
    if text2 then
        AddRow("note", isError and Red(text2) or text2)
    end

    local bottom = y - 8
    b.buy:ClearAllPoints()
    b.buy:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, bottom)
    b.buy:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, bottom)
    bottom = bottom - BUTTON_HEIGHT - 4

    b.craft:ClearAllPoints()
    b.craft:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, bottom)
    b.craft:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, bottom)
    bottom = bottom - BUTTON_HEIGHT - 4

    local half = (WIDTH - 2 * PADDING - 6) / 2
    b.scan:ClearAllPoints()
    b.scan:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, bottom)
    b.scan:SetWidth(half)
    for _, button in ipairs({ b.cancel, b.anyway }) do
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, bottom)
        button:SetWidth(half)
    end
    bottom = bottom - BUTTON_HEIGHT - 4

    b.recount:ClearAllPoints()
    b.recount:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, bottom)
    b.recount:SetWidth(half)
    b.clear:ClearAllPoints()
    b.clear:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, bottom)
    b.clear:SetWidth(half)
    bottom = bottom - BUTTON_HEIGHT

    frame:SetHeight(-bottom + PADDING)
end

local function MakeButton(text, onClick, tooltip)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetHeight(BUTTON_HEIGHT)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    if tooltip then
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return button
end

-- Frame ------------------------------------------------------------------------

local function Create()
    frame = CreateFrame("Frame", "VendorProfitPanel", UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(frame)
    ButtonFrameTemplate_HideButtonBar(frame)
    if frame.Inset then
        frame.Inset:Hide()
    end
    frame:SetTitle(L.PANEL_TITLE)
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
        Panel.SavePosition()
    end)
    frame:Hide()

    -- Buy and Confirm call the game's purchase functions straight from the
    -- click: the game only allows purchases as part of a click.
    frame.buttons = {
        buy = MakeButton("", function()
            if Shopper.Status() == "confirm" then
                Shopper.Confirm()
            else
                Shopper.Buy()
            end
        end),
        scan = MakeButton(L.SCAN, Shopper.Scan),
        cancel = MakeButton(L.CANCEL, Shopper.Cancel),
        anyway = MakeButton(L.BUY_ANYWAY, function() Shopper.SetOverride(true) end, L.BUY_ANYWAY_HELP),
        recount = MakeButton(L.FORGET_MAIL, Order.ForgetMail, L.FORGET_MAIL_HELP),
        clear = MakeButton(L.CLEAR, Order.Clear),
        -- Mouse down prepares, the click crafts: see Crafter.lua.
        craft = MakeButton("", function() Crafter.Craft() end),
    }
    frame.buttons.craft:SetScript("OnMouseDown", Crafter.Prepare)
end

-- Where you moved the panel to: { left, top } from the screen's bottom left.
local function SavedPosition()
    local db = VendorProfitCharDB
    return db and db.panel
end

function Panel.SavePosition()
    VendorProfitCharDB = VendorProfitCharDB or {}
    VendorProfitCharDB.panel = { left = frame:GetLeft(), top = frame:GetTop() }
end

local function Dock()
    frame:ClearAllPoints()
    local saved = SavedPosition()
    if saved and saved.left and saved.top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.left, saved.top)
    elseif AuctionHouseFrame and AuctionHouseFrame:IsShown() then
        frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
    elseif ProfessionsFrame and ProfessionsFrame:IsShown() then
        frame:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 4, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER")
    end
end

local function Refresh()
    usedRows = 0
    y = TOP
    AddContent()
    LayoutButtons()
    HideUnusedRows()
end

function Panel.Refresh()
    if frame == nil or not frame:IsShown() then
        return
    end
    xpcall(Refresh, geterrorhandler())
end

function Panel.Show()
    if frame == nil then
        Create()
    end
    Dock()
    frame:Show()
    Panel.Refresh()
end

function Panel.Hide()
    if frame then
        frame:Hide()
    end
end

-- Forgets where you moved it, so it docks again.
function Panel.ResetPosition()
    if VendorProfitCharDB then
        VendorProfitCharDB.panel = nil
    end
    if frame then
        Dock()
    end
end

function Panel.IsShown()
    return frame ~= nil and frame:IsShown()
end

function Panel.Toggle()
    if Panel.IsShown() then
        Panel.Hide()
    else
        Panel.Show()
    end
end

-- The rows shown, as "left | right" text, and the buttons. For tests and
-- debugging.
function Panel.Lines()
    local lines = {}
    for index = 1, usedRows do
        local row = rows[index]
        local text = row.left:GetText() or ""
        if row.right:IsShown() and (row.right:GetText() or "") ~= "" then
            text = text .. " | " .. row.right:GetText()
        end
        lines[#lines + 1] = text
    end
    return lines
end

function Panel.Buttons()
    return frame and frame.buttons
end

-- Opens with the auction house when something is queued, and closes with
-- it wherever it's been moved. /vprofit opens it again.
local lastStatus = Shopper.Status()
Shopper.OnChange(function()
    local status = Shopper.Status()
    if lastStatus == "closed" and status ~= "closed" and not Order.IsEmpty() then
        Panel.Show()
    elseif status == "closed" and lastStatus ~= "closed" then
        Panel.Hide()
    end
    lastStatus = status
    Panel.Refresh()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_MONEY")
-- The Craft button follows the open profession window and your casting.
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE" }) do
    pcall(events.RegisterEvent, events, event)
end
pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_START", "player")
pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_STOP", "player")
events:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_DELAYED" then
        local status = Shopper.Status()
        if status == "ready" or status == "idle" or status == "closed" then
            Shopper.Recompute()
        end
    end
    Panel.Refresh()
end)

SLASH_VENDORPROFIT1 = "/vprofit"
SLASH_VENDORPROFIT2 = "/vendorprofit"
SlashCmdList.VENDORPROFIT = function(arg)
    if arg and arg:lower():match("^%s*reset%s*$") then
        Panel.ResetPosition()
        Panel.Show()
    else
        Panel.Toggle()
    end
end
