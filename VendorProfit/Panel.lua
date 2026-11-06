-- The shopping panel: the queued order, what to buy, what you already have,
-- what to craft and the order's profit. Buying, crafting and taking from the
-- bank are buttons on their sections' headings.
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
local OpenButton = VendorProfit.OpenButton
local Banker = VendorProfit.Banker
local L = VendorProfit.L

local Panel = {}
VendorProfit.Panel = Panel

local WIDTH = 380
local PADDING = 16
local TOP = -32
local ROW_HEIGHT = 15
local HEADING_HEIGHT = 20

local HEADING_BUTTON_WIDTH = 120

local frame
local rows = {}
local craftCover        -- { button, profession } when Then craft's button opens a profession
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
        -- Disabled buttons still show their tooltip, to say why.
        row.button:SetMotionScriptsWhileDisabled(true)
        row.button:SetScript("OnEnter", function(self)
            if self.tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        row.button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Lines either side of a divider's title.
        row.lines = {}
        for side = 1, 2 do
            local line = frame:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(1, 0.82, 0, 0.35)
            line:SetHeight(1)
            line:Hide()
            row.lines[side] = line
        end
        rows[index] = row
    end
    return row
end

-- button: { text, onClick, onMouseDown, enabled, width, tooltip } adds a
-- button at the right.
local function AddDivider(row, title)
    y = y - 10
    row.left:SetFontObject("GameFontNormalSmall")
    row.left:ClearAllPoints()
    row.left:SetPoint("TOP", frame, "TOP", 0, y)
    row.left:SetWidth(0)
    row.left:SetWordWrap(false)
    row.left:SetText(title)
    row.left:Show()
    row.right:Hide()
    row.button:Hide()
    local left, right = row.lines[1], row.lines[2]
    left:ClearAllPoints()
    left:SetPoint("LEFT", frame, "TOPLEFT", PADDING, y - 6)
    left:SetPoint("RIGHT", row.left, "LEFT", -6, 0)
    right:ClearAllPoints()
    right:SetPoint("LEFT", row.left, "RIGHT", 6, 0)
    right:SetPoint("RIGHT", frame, "TOPRIGHT", -PADDING, y - 6)
    left:Show()
    right:Show()
    y = y - HEADING_HEIGHT
    return row
end

-- kind: "divider" (a centered title between lines), "heading", "row",
-- "note" or "gap" (space between groups).
local function AddRow(kind, left, right, button)
    usedRows = usedRows + 1
    local row = GetRow(usedRows)
    if kind == "divider" then
        return AddDivider(row, left)
    elseif kind == "gap" then
        -- Space between groups of rows.
        row.left:Hide()
        row.right:Hide()
        row.button:Hide()
        row.lines[1]:Hide()
        row.lines[2]:Hide()
        y = y - 6
        return row
    end
    row.lines[1]:Hide()
    row.lines[2]:Hide()
    local height = kind == "heading" and HEADING_HEIGHT or ROW_HEIGHT
    if kind == "heading" then
        y = y - 4
    end

    row.left:SetFontObject(kind == "heading" and "GameFontNormal" or "GameFontHighlightSmall")
    row.left:ClearAllPoints()
    row.left:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
    -- Notes are gray unless they bring their own color.
    local plain = kind == "note" and not left:find("^|c")
    row.left:SetText(plain and Gray(left) or left)
    local buttonWidth = button and (button.width or 60) or 0
    row.left:SetWordWrap(kind == "note")
    row.left:SetWidth(kind == "note" and (WIDTH - 2 * PADDING - (button and buttonWidth + 4 or 0)) or (WIDTH * 0.55))
    row.left:Show()

    row.right:ClearAllPoints()
    row.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING - (button and buttonWidth + 4 or 0), y)
    row.right:SetText(right or "")
    row.right:SetShown(right ~= nil)

    row.button:ClearAllPoints()
    if button then
        row.button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, y + 2)
        row.button:SetWidth(buttonWidth)
        row.button:SetText(button.text)
        row.button:SetScript("OnClick", button.onClick)
        row.button:SetScript("OnMouseDown", button.onMouseDown)
        row.button:SetEnabled(button.enabled ~= false)
        row.button.tooltip = button.tooltip
        row.button:Show()
    else
        row.button:Hide()
    end

    if kind == "note" then
        height = math.max(ROW_HEIGHT, (row.left:GetStringHeight() or 0) + 3)
    elseif button then
        height = math.max(height, 20)
    end
    y = y - height
    return row
end

local function HideUnusedRows()
    for index = usedRows + 1, #rows do
        local row = rows[index]
        row.left:Hide()
        row.right:Hide()
        row.button:Hide()
        row.lines[1]:Hide()
        row.lines[2]:Hide()
    end
end

-- Content ----------------------------------------------------------------------

local function BuyLineRight(line)
    if line.source == "vendor" then
        return L.FROM_VENDOR .. "  " .. Money(line.total)
    elseif line.source == nil then
        return Red(L.SOURCE_NONE)
    elseif line.manual then
        return Gray(L.BUY_YOURSELF) .. "  " .. Money(line.total)
    elseif line.unscanned and Shopper.IsOpen() then
        return Gray(L.NOT_SCANNED) .. "  " .. Money(line.total)
    elseif line.listed and line.listed < line.quantity then
        return Red(string.format(L.ONLY_LISTED, line.listed)) .. "  " .. Money(line.total)
    end
    return L.FROM_AUCTION .. "  " .. Money(line.total)
end

-- Splits what the plan uses of your items by where they are: bags first
-- (with the reagent bank, which crafting uses directly), then purchases still
-- in the mailbox, then the bank, so the bank list is what you need to fetch.
-- Returns three lists of { itemID, quantity }, sorted by item.
function Panel.SplitUses(uses)
    local fromBags, fromMail, fromBank = {}, {}, {}
    local itemIDs = {}
    for itemID in pairs(uses) do
        itemIDs[#itemIDs + 1] = itemID
    end
    table.sort(itemIDs)
    for _, itemID in ipairs(itemIDs) do
        local left = uses[itemID]
        local carried = Inventory.ForCrafting(itemID)
        local bank = math.max(Inventory.Total(itemID) - carried, 0)
        for _, place in ipairs({
            { list = fromBags, have = carried },
            { list = fromMail, have = Order.InMail(itemID) },
            { list = fromBank, have = bank },
        }) do
            local take = math.min(left, place.have)
            if take > 0 then
                place.list[#place.list + 1] = { itemID = itemID, quantity = take }
                left = left - take
            end
        end
    end
    return fromBags, fromMail, fromBank
end

-- What clicking the To buy heading's button does, by status.
local function BuyClick()
    local status = Shopper.Status()
    if status == "confirm" then
        Shopper.Confirm()
    elseif status == "ready" then
        -- Showing "Buy anyway": clicking it is the go-ahead.
        if not Shopper.IsProfitable() and not Shopper.IsOverridden() then
            Shopper.SetOverride(true)
        end
        Shopper.Buy()
    end
end

-- The To buy heading's button: { text, enabled, tooltip, onClick }, or nil
-- when there's nothing to buy. Labels are short; the tooltip has the detail.
-- Buy and Confirm call the game's purchase functions straight from the
-- click, which is the only way the game allows purchases.
local function BuyButton(plan)
    local status = Shopper.Status()
    local button = { onClick = BuyClick, enabled = false, width = HEADING_BUTTON_WIDTH }
    if #plan.buyOrder == 0 and status ~= "quoting" and status ~= "confirm" and status ~= "buying" then
        return nil
    elseif status == "closed" then
        button.text, button.tooltip = L.BUY_OPEN_AH, L.BUY_OPEN_AH_HELP
    elseif status == "idle" then
        button.text, button.tooltip = L.BUY_BUY, L.SCAN_FIRST
    elseif status == "scanning" then
        local done, total = Shopper.ScanProgress()
        button.text, button.tooltip = L.BUY_SCANNING, string.format(L.BUTTON_SCANNING, math.min(done + 1, total), total)
    elseif status == "quoting" then
        button.text, button.tooltip = L.BUY_PRICING, L.BUTTON_QUOTING
    elseif status == "buying" then
        button.text, button.tooltip = L.BUY_BUYING, L.BUTTON_BUYING
    elseif status == "confirm" then
        local p = Shopper.Purchase()
        button.text, button.enabled = L.BUY_CONFIRM, true
        button.tooltip = string.format(L.BUTTON_CONFIRM, p.quantity, ItemName(p.itemID), Money(p.quote))
    else
        local nextPurchase = Shopper.NextPurchase()
        button.text = L.BUY_BUY
        if nextPurchase == nil then
            button.tooltip = L.BUTTON_NOTHING
        elseif not Shopper.IsProfitable() and not Shopper.IsOverridden() then
            button.text, button.enabled = L.BUY_ANYWAY, true
            button.tooltip = L.BUTTON_NOT_PROFITABLE .. " " .. L.BUY_ANYWAY_HELP
        else
            button.enabled = true
            button.tooltip = string.format(L.BUTTON_BUY, nextPurchase.quantity, ItemName(nextPurchase.itemID), Money(nextPurchase.budget))
        end
    end
    return button
end

-- The Then craft heading's button: { text, enabled, tooltip, onClick,
-- onMouseDown }, plus the next step (to mark in the list) and, when the next
-- step is in a profession that isn't open, that profession (OpenButton.lua
-- covers the button to open it).
local function CraftButton()
    local button = {
        width = HEADING_BUTTON_WIDTH, enabled = false,
        -- Mouse down prepares, the click crafts: see Crafter.lua.
        onClick = function() Crafter.Craft() end, onMouseDown = Crafter.Prepare,
    }
    if Crafter.IsCasting() then
        button.text = L.CRAFTING
        return button
    end
    local nextCraft = Crafter.Next()
    if nextCraft == nil then
        return nil
    end
    local name = ItemName(nextCraft.step.itemID)
    if nextCraft.open then
        button.text = string.format(L.OPEN_LABEL, nextCraft.open)
        if InCombatLockdown() then
            button.tooltip = string.format(L.OPEN_AFTER_COMBAT, nextCraft.open, name)
            return button, nextCraft.step
        end
        button.tooltip, button.enabled = string.format(L.OPEN_TO_CRAFT, nextCraft.open, name), true
        return button, nextCraft.step, nextCraft.open
    end
    button.text = L.CRAFT_LABEL
    if nextCraft.materials then
        button.tooltip = string.format(L.NEED_MATERIALS, name)
    elseif nextCraft.crafts == 1 then
        button.tooltip, button.enabled = string.format(L.CRAFT_ONCE, name), true
    else
        button.tooltip, button.enabled = string.format(L.CRAFT_TIMES, name, nextCraft.crafts), true
    end
    return button, nextCraft.step
end

-- The button on the "From your bank" heading: takes those items out.
function Panel.BankButton(fromBank)
    local text, enabled, tooltip
    if Banker.IsMoving() then
        text, enabled = L.BANK_TAKING, false
    elseif not Banker.IsBankOpen() then
        text, enabled, tooltip = L.BANK_TAKE, false, L.BANK_OPEN_FIRST
    else
        text, enabled, tooltip = L.BANK_TAKE, true, L.BANK_TAKE_HELP
    end
    return {
        text = text, enabled = enabled, tooltip = tooltip, width = HEADING_BUTTON_WIDTH,
        onClick = function() Banker.Withdraw(fromBank) end,
    }
end

-- The Profit heading's button: scans the auction house for live prices.
local function ScanButton()
    local status = Shopper.Status()
    local button = { text = L.SCAN, width = HEADING_BUTTON_WIDTH, enabled = false, onClick = Shopper.Scan }
    if status == "closed" then
        button.tooltip = L.SCAN_OPEN_AH
    elseif status == "scanning" then
        local done, total = Shopper.ScanProgress()
        button.text = L.BUY_SCANNING
        button.tooltip = string.format(L.BUTTON_SCANNING, math.min(done + 1, total), total)
    elseif status == "idle" or status == "ready" then
        button.enabled, button.tooltip = true, L.BUY_SCAN_HELP
    else
        button.tooltip = L.BUTTON_QUOTING
    end
    return button
end

-- The order's profit: what it sells for, what it costs, and what it makes.
local function AddProfit(s)
    local function OrNoPrice(copper)
        return copper and Money(copper) or Gray(L.NO_AUCTION_PRICE)
    end
    AddRow("heading", L.HEAD_PROFIT, nil, ScanButton())
    -- Three groups, set apart by a gap: what it sells for, what it costs,
    -- what it makes. Each pair is vendor, then auction.
    AddRow("row", L.VENDOR_PRICE, Money(s.revenue))
    AddRow("row", L.AUCTION_PRICE, OrNoPrice(s.auctionRevenue))
    AddRow("gap")
    if s.ownedValue > 0 then
        AddRow("row", L.ITEMS_YOU_HAVE, Money(-s.ownedValue))
    end
    AddRow("row", L.ITEMS_TO_BUY, Money(-s.remaining))
    AddRow("gap")
    AddRow("row", L.VENDOR_PROFIT_ROW, Money(s.profit))
    AddRow("row", L.AUCTION_PROFIT_ROW, OrNoPrice(s.auctionProfit))
    if s.spent > 0 then
        AddRow("row", Gray(L.SPENT), Gray(VendorProfit.FormatCoins(s.spent)))
    end
end

-- The To do checklist, in the order you'd do it: buy (prices can change, so
-- first), collect purchases from the mailbox, take things from the bank, then
-- craft. Each step shows only while it has something left in it, numbered in
-- order. Returns the bags list for the information section below it.
local function AddToDo(plan)
    AddRow("divider", L.HEAD_TODO)
    local number = 0
    local function Step(title, button)
        number = number + 1
        return AddRow("heading", number .. ". " .. title, nil, button)
    end

    local buying = Shopper.Status()
    if #plan.buyOrder > 0 or buying == "quoting" or buying == "confirm" or buying == "buying" then
        Step(L.STEP_BUY, BuyButton(plan))
        -- The price to confirm, where it can't be missed.
        if buying == "confirm" then
            local p = Shopper.Purchase()
            AddRow("note", NORMAL_FONT_COLOR:WrapTextInColorCode(
                string.format(L.BUTTON_CONFIRM, p.quantity, ItemName(p.itemID), Money(p.quote))), nil,
                { text = L.CANCEL, onClick = Shopper.Cancel, width = 70 })
        end
        for _, line in ipairs(plan.buyOrder) do
            AddRow("row", ItemLabel(line.itemID, line.quantity), BuyLineRight(line))
        end
    end

    local fromBags, fromMail, fromBank = Panel.SplitUses(plan.uses)
    if #fromMail > 0 then
        Step(L.STEP_MAIL)
        for _, use in ipairs(fromMail) do
            AddRow("row", ItemLabel(use.itemID, use.quantity))
        end
    end
    if #fromBank > 0 then
        Step(L.STEP_BANK, Panel.BankButton(fromBank))
        for _, use in ipairs(fromBank) do
            AddRow("row", ItemLabel(use.itemID, use.quantity))
        end
    end

    local craftButton, nextStep, openProfession = CraftButton()
    local craftRow = Step(L.STEP_CRAFT, craftButton)
    craftCover = openProfession and { button = craftRow.button, profession = openProfession } or nil
    for _, step in ipairs(plan.crafts) do
        local detail = string.format(step.crafts == 1 and L.CRAFTS_ONE or L.CRAFTS, step.crafts)
        if step.profession then
            detail = step.profession .. ", " .. detail
        end
        local label = ItemLabel(step.itemID, step.crafts * step.makes)
        if step == nextStep then
            label = NORMAL_FONT_COLOR:WrapTextInColorCode(L.NEXT_MARK) .. " " .. label
        end
        AddRow("row", label, Gray(detail))
    end
    return fromBags
end

-- Queued crafts, the order's profit, the To do checklist, then what's
-- already in your bags, for information.
local function AddContent()
    local s = Shopper.Summary()
    local plan = s.plan

    local entries = Order.Entries()
    AddRow("heading", L.HEAD_QUEUED)
    if #entries == 0 then
        AddRow("note", L.NOTHING_QUEUED)
        return
    end
    for index, entry in ipairs(entries) do
        AddRow("row", ItemLabel(entry.itemID, entry.crafts * entry.count), nil, {
            text = L.REMOVE,
            onClick = function() Order.Remove(index) end,
        })
    end

    AddProfit(s)
    local fromBags = AddToDo(plan)

    if #fromBags > 0 then
        AddRow("divider", L.HEAD_BAGS)
        for _, use in ipairs(fromBags) do
            AddRow("row", ItemLabel(use.itemID, use.quantity))
        end
    end
end

-- Buttons ----------------------------------------------------------------------

-- Messages at the end, the panel's height, and the open-profession cover.
local function FinishLayout()
    for _, source in ipairs({ Shopper, Banker }) do
        local text, isError = source.Message()
        if text then
            AddRow("note", isError and Red(text) or text)
        end
    end

    frame:SetHeight(-y + PADDING)

    -- With the Craft button in place, cover it to open the profession, or
    -- uncover.
    if craftCover and not Order.IsEmpty() then
        craftCover.button:SetEnabled(OpenButton.Cover(craftCover.button, craftCover.profession))
    else
        OpenButton.Hide()
    end
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
    frame:SetScript("OnDragStart", function(self)
        -- The open-profession cover doesn't follow a drag; put it back after.
        OpenButton.Hide()
        self:StartMoving()
    end)
    frame:SetScript("OnHide", OpenButton.Hide)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Saved by the addon, not the game's own layout cache.
        self:SetUserPlaced(false)
        Panel.SavePosition()
        Panel.Refresh()
    end)
    frame:Hide()

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
    elseif Banker.IsBankOpen() and BankFrame and BankFrame:IsShown() then
        frame:SetPoint("TOPLEFT", BankFrame, "TOPRIGHT", 4, 0)
    elseif ProfessionsFrame and ProfessionsFrame:IsShown() then
        frame:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 4, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER")
    end
end

local function Refresh()
    usedRows = 0
    y = TOP
    craftCover = nil
    AddContent()
    FinishLayout()
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
        local text = row.left:IsShown() and row.left:GetText() or ""
        if row.right:IsShown() and (row.right:GetText() or "") ~= "" then
            text = text .. " | " .. row.right:GetText()
        end
        if text ~= "" then
            lines[#lines + 1] = text
        end
    end
    return lines
end

-- The first shown row button labeled text.
function Panel.FindButton(text)
    for index = 1, usedRows do
        local button = rows[index].button
        if button:IsShown() and button:GetText() == text then
            return button
        end
    end
end

-- The button on the row whose left text is text (or a numbered step called
-- text), if it has one.
function Panel.RowButton(text)
    for index = 1, usedRows do
        local row = rows[index]
        local label = row.left:GetText() or ""
        if (label == text or label:match("^%d+%. (.*)$") == text) and row.button:IsShown() then
            return row.button
        end
    end
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

-- Opens at the bank when there's something to take out of it, and closes
-- with the bank if it opened for it.
local openedForBank = false
local bankWasOpen = Banker.IsBankOpen()
Banker.OnChange(function()
    local open = Banker.IsBankOpen()
    if open and not bankWasOpen and not Order.IsEmpty() and not Panel.IsShown() then
        local _, _, fromBank = Panel.SplitUses(Shopper.Summary().plan.uses)
        if #fromBank > 0 then
            openedForBank = true
            Panel.Show()
        end
    elseif not open and bankWasOpen then
        if openedForBank then
            Panel.Hide()
        end
        openedForBank = false
    end
    bankWasOpen = open
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
