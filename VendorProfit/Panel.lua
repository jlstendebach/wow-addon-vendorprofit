-- The Vendor Profit window, with a tab per page down its right side: the
-- Shopping List (here: its title with Scan, then sections for the queued
-- order, its profit, the To do checklist and what's already in your bags,
-- each folding away; buying, crafting and taking from the bank are buttons
-- on To do's steps) and Best Crafts (BestPanel.lua).
--
-- It's a window of its own, not docked to the auction house or any other
-- window, and only opens or closes when you open or close it. It opens
-- centered near the top of the screen until you drag it; from then on it opens where you left
-- it, saved per character, until /vprofit reset centers it again. /vprofit
-- or /vendorprofit toggles it.

local _, ns = ...
local VendorProfit = ns.VendorProfit
local Order = VendorProfit.Order
local Shopper = VendorProfit.Shopper
local Poster = VendorProfit.Poster
local Inventory = VendorProfit.Inventory
local Crafter = VendorProfit.Crafter
local OpenButton = VendorProfit.OpenButton
local Banker = VendorProfit.Banker
local Merchant = VendorProfit.Merchant
local L = VendorProfit.L

local Panel = {}
VendorProfit.Panel = Panel

local WIDTH = 380
Panel.WIDTH = WIDTH
local PADDING = 16
local TOP = -32
local ROW_HEIGHT = 15
local HEADING_HEIGHT = 20

local HEADING_BUTTON_WIDTH = 120
-- To do's details scroll in a box as tall as its rows, between these:
-- at least a few rows, so it isn't cramped with only a row or two (or
-- none: a Post step not priced yet), and at most this many before it
-- scrolls, so a big order doesn't run the window off the screen. The
-- scroll bar only shows when it scrolls. Folding To do hides it.
Panel.TODO_MIN_ROWS = 3
Panel.TODO_ROWS = 12
-- The box is a little darker than the window, its items and scroll bar
-- inset by TODO_PADDING; the bar is SCROLLBAR_WIDTH wide, TODO_PADDING
-- from the items.
local TODO_PADDING = 6
local SCROLLBAR_WIDTH = 16
-- A step that has just moved into a button's place (the one before it
-- finished) ignores clicks on it for this long, so a click meant for the
-- old step doesn't land on the new one.
Panel.MOVED_GUARD = 0.5

local frame              -- the window
local content            -- the Shopping List page, where the rows below go
local rows = {}
local craftCover        -- { button, profession } when Then craft's button opens a profession
local usedRows = 0
local y

-- Items ------------------------------------------------------------------------

local function ItemName(itemID)
    local name = C_Item.GetItemInfo(itemID)
    if name == nil then
        VendorProfit.RedrawWhenLoaded(itemID, Panel.Refresh)
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
        row.left = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.left:SetJustifyH("LEFT")
        row.left:SetWordWrap(false)
        row.right = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.right:SetJustifyH("RIGHT")
        row.right:SetWordWrap(false)
        row.button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        row.button:SetSize(60, 16)
        -- Disabled buttons still show their tooltip, to say why.
        row.button:SetMotionScriptsWhileDisabled(true)
        row.button:SetScript("OnEnter", function(self)
            -- The open-profession cover goes over the Craft button while
            -- the mouse is on it (see OpenButton.lua), so the click opens
            -- the profession.
            if craftCover and craftCover.button == self and not Order.IsEmpty() then
                local wait = Panel.MovedWait(craftCover.movedAt)
                if wait > 0 then
                    C_Timer.After(wait, Panel.Refresh)
                else
                    self:SetEnabled(OpenButton.Cover(self, craftCover.profession))
                end
            end
            if self.tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        row.button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Small icon buttons right of the row (Queued: - + magnifier cancel),
        -- made as needed.
        row.icons = {}
        -- Hovering the row's text, for rows that explain themselves.
        row.hit = CreateFrame("Frame", nil, content)
        row.hit.text = row.left
        row.hit:EnableMouse(true)
        row.hit:SetScript("OnEnter", function(self)
            if self.tooltip then
                VendorProfit.SetNameTooltipOwner(self, self.text)
                self.tooltip(GameTooltip)
                GameTooltip:Show()
            end
        end)
        row.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.hit:SetScript("OnMouseUp", function(self, mouseButton)
            if self.onClick and mouseButton == "LeftButton" and self:IsMouseOver() then
                self.onClick()
            end
        end)
        row.hit:Hide()
        -- Lines either side of a divider's title.
        row.lines = {}
        for side = 1, 2 do
            local line = content:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(1, 0.82, 0, 0.35)
            line:SetHeight(1)
            line:Hide()
            row.lines[side] = line
        end
        rows[index] = row
    end
    return row
end

local ICON_BUTTON_WIDTH, ICON_BUTTON_HEIGHT = 20, 18

local function GetIcon(row, index)
    local icon = row.icons[index]
    if icon == nil then
        icon = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        icon:SetSize(ICON_BUTTON_WIDTH, ICON_BUTTON_HEIGHT)
        icon:SetMotionScriptsWhileDisabled(true)
        icon.icon = icon:CreateTexture(nil, "OVERLAY")
        icon.icon:SetSize(12, 12)
        icon.icon:SetPoint("CENTER", icon, "CENTER", 0, 0)
        icon:SetScript("OnEnter", function(self)
            if self.tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.icons[index] = icon
    end
    return icon
end

local function HideExtras(row, fromIcon)
    for index = fromIcon or 1, #row.icons do
        row.icons[index]:Hide()
    end
    row.hit:Hide()
    row.hit.tooltip = nil
    row.hit.onClick = nil
end

-- Lays out icon buttons ({ text or texture, onClick, enabled, tooltip })
-- from the right edge, leftwards. Returns the width they take.
local function LayoutIcons(row, icons)
    local right = -PADDING
    for index, spec in ipairs(icons or {}) do
        local icon = GetIcon(row, index)
        icon:ClearAllPoints()
        icon:SetPoint("TOPRIGHT", content, "TOPRIGHT", right, y + 2)
        icon:SetText(spec.text or "")
        if spec.texture then
            icon.icon:SetTexture(spec.texture)
            icon.icon:SetDesaturated(spec.enabled == false)
            icon.icon:Show()
        else
            icon.icon:Hide()
        end
        icon:SetScript("OnClick", spec.onClick)
        icon:SetEnabled(spec.enabled ~= false)
        icon.tooltip = spec.tooltip
        icon:Show()
        right = right - ICON_BUTTON_WIDTH - 2
    end
    HideExtras(row, #(icons or {}) + 1)
    return -right - PADDING
end

-- button: { text, onClick, onMouseDown, enabled, width, tooltip } adds a
-- button at the right. extras: { icons = { ... } (see LayoutIcons),
-- tooltip = function(GameTooltip) for hovering the row's text, onClick for
-- clicking it }.
local function AddDivider(row, title, onClick)
    y = y - 10
    row.left:SetFontObject("GameFontNormalSmall")
    row.left:ClearAllPoints()
    row.left:SetPoint("TOP", content, "TOP", 0, y)
    row.left:SetWidth(0)
    row.left:SetWordWrap(false)
    row.left:SetText(title)
    row.left:Show()
    row.right:Hide()
    row.button:Hide()
    local left, right = row.lines[1], row.lines[2]
    left:ClearAllPoints()
    left:SetPoint("LEFT", content, "TOPLEFT", PADDING, y - 6)
    left:SetPoint("RIGHT", row.left, "LEFT", -6, 0)
    right:ClearAllPoints()
    right:SetPoint("LEFT", row.left, "RIGHT", 6, 0)
    right:SetPoint("RIGHT", content, "TOPRIGHT", -PADDING, y - 6)
    left:Show()
    right:Show()
    -- A divider that collapses its section: the whole row is clickable.
    if onClick then
        row.hit:ClearAllPoints()
        row.hit:SetPoint("TOPLEFT", content, "TOPLEFT", PADDING, y + 4)
        row.hit:SetSize(WIDTH - 2 * PADDING, HEADING_HEIGHT)
        row.hit.onClick = onClick
        row.hit:Show()
    end
    y = y - HEADING_HEIGHT
    return row
end

-- A row's left text gets its share of the width, but never runs under the
-- right text: a long right side cuts the left short ("...") rather than
-- the two drawing over each other.
local RIGHT_GAP = 8
local function FitLeft(row, share, total, hasRight)
    local room = hasRight and (total - (row.right:GetStringWidth() or 0) - RIGHT_GAP) or total
    row.left:SetWidth(math.max(math.min(share, room), 1))
end

-- kind: "divider" (a centered title between lines), "heading", "row",
-- "note" or "gap" (space between groups).
local function AddRow(kind, left, right, button, extras)
    usedRows = usedRows + 1
    local row = GetRow(usedRows)
    HideExtras(row)
    if kind == "divider" then
        return AddDivider(row, left, extras and extras.onClick)
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
    row.left:SetPoint("TOPLEFT", content, "TOPLEFT", PADDING, y)
    -- Notes are gray unless they bring their own color.
    local plain = kind == "note" and not left:find("^|c")
    row.left:SetText(plain and Gray(left) or left)
    local buttonWidth = button and (button.width or 60) or 0
    if extras and extras.icons then
        buttonWidth = LayoutIcons(row, extras.icons)
        button = nil
    end
    local reserved = buttonWidth > 0 and buttonWidth + 4 or 0
    row.left:SetWordWrap(kind == "note")
    row.left:Show()

    row.right:ClearAllPoints()
    row.right:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PADDING - reserved, y)
    row.right:SetText(right or "")
    row.right:SetShown(right ~= nil)
    if kind == "note" then
        row.left:SetWidth(WIDTH - 2 * PADDING - reserved)
    else
        FitLeft(row, WIDTH * 0.55, WIDTH - 2 * PADDING - reserved, right ~= nil)
    end

    row.button:ClearAllPoints()
    if button then
        row.button:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PADDING, y + 2)
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

    if extras and extras.tooltip then
        row.hit:ClearAllPoints()
        row.hit:SetPoint("TOPLEFT", content, "TOPLEFT", PADDING, y + 2)
        row.hit:SetSize(WIDTH * 0.55, ROW_HEIGHT + 2)
        row.hit.tooltip = extras.tooltip
        row.hit.onClick = extras.onClick
        row.hit:Show()
    end

    if kind == "note" then
        height = math.max(ROW_HEIGHT, (row.left:GetStringHeight() or 0) + 3)
    elseif button or (extras and extras.icons) then
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
        HideExtras(row)
    end
end

-- Content ----------------------------------------------------------------------

local function BuyLineRight(line)
    if line.source == "vendor" then
        return L.FROM_VENDOR .. "  " .. Money(line.total)
    elseif line.source == nil then
        return Red(L.SOURCE_NONE)
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

-- What a scan is doing: the batch lookup, then "Scanning 2 of 5...".
local function ScanningText()
    if Shopper.IsLookingUp() then
        return L.BUTTON_LOOKING_UP
    end
    local done, total = Shopper.ScanProgress()
    local text = string.format(L.BUTTON_SCANNING, math.min(done + 1, total), total)
    if Shopper.WaitingForLimit() then
        text = text .. " " .. string.format(L.SCAN_LIMIT_WAIT, Shopper.SEARCH_LIMIT)
    end
    return text
end

-- Whether to hold off buying: the order loses money and "Buy anyway" hasn't
-- been clicked.
local function Unprofitable()
    return not Shopper.IsProfitable() and not Shopper.IsOverridden()
end

-- What clicking the To buy heading's button does at a vendor.
local function VendorBuyClick(offers)
    if Unprofitable() then
        Shopper.SetOverride(true)
    end
    Merchant.Buy(offers)
end

-- The words for a vendor purchase: "20 Weak Flux, 5 Coarse Thread".
local function OfferList(offers)
    local parts = {}
    for _, offer in ipairs(offers) do
        parts[#parts + 1] = offer.count .. " " .. ItemName(offer.itemID)
    end
    return table.concat(parts, ", ")
end

-- Whether anything left to buy is planned from the auction house.
local function AnyFromAuction(plan)
    for _, line in ipairs(plan.buyOrder) do
        if line.source == "auction" and line.quantity > 0 then
            return true
        end
    end
    return false
end

-- What clicking the To buy heading's button does, by status.
local function BuyClick()
    local status = Shopper.Status()
    if not Shopper.ThrottleReady() then
        return
    end
    if status == "confirm" then
        Shopper.Confirm()
    elseif status == "ready" then
        -- Showing "Buy anyway": clicking it is the go-ahead.
        if Unprofitable() then
            Shopper.SetOverride(true)
        end
        Shopper.Buy()
    end
end

-- How many of an item the Post Queue posts now.
local function PostCount(itemID)
    for _, item in ipairs(Poster.Items()) do
        if item.itemID == itemID then
            return item.count
        end
    end
    return 0
end

-- The Post step's button: prices the first item, then posts each in turn
-- (Poster.lua). Below cost it's red, and the first click only arms it.
local function PostButton()
    local status, item = Poster.Status(), Poster.Current()
    local button = { onClick = Poster.Post, enabled = false, width = HEADING_BUTTON_WIDTH, text = L.POST_POST }
    if status == "closed" then
        button.text, button.tooltip = L.BUY_OPEN_AH, L.POST_OPEN_AH
    elseif status == "idle" then
        button.enabled, button.onClick = true, Poster.Price
        button.tooltip = string.format(L.POST_PRICE_HELP, ItemName(Poster.Items()[1].itemID))
    elseif status == "pricing" then
        button.text, button.tooltip = L.BUY_PRICING, string.format(L.POST_PRICING, ItemName(item.itemID))
    elseif status == "posting" then
        button.text, button.tooltip = L.POST_POSTING, L.POST_POSTING_HELP
    else
        button.enabled = true
        button.tooltip = string.format(L.POST_HELP, PostCount(item.itemID), ItemName(item.itemID), Money(item.price))
        if Poster.BelowCost() then
            button.text = Red(item.armed and L.POST_ANYWAY or L.POST_POST)
            button.tooltip = string.format(item.armed and L.POST_ANYWAY_HELP or L.POST_BELOW_COST_HELP, Money(item.cost))
        end
        -- The game is busy (just after a post) and would drop it.
        if not Poster.ThrottleReady() then
            button.enabled, button.tooltip = false, L.BUTTON_AH_BUSY
            Poster.WatchThrottle()
        end
    end
    return button
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
    end
    -- At a vendor, while a purchase is on its way to your bags: wait.
    if Merchant.IsOpen() and Merchant.IsBuying() then
        button.text, button.tooltip = L.BUY_BUYING, L.VENDOR_BUYING
        return button
    end
    -- At a vendor that sells some of it: buy that here.
    local offers = Merchant.Offers(plan)
    if #offers > 0 then
        button.enabled = true
        button.onClick = function() VendorBuyClick(offers) end
        local help = string.format(L.VENDOR_BUY_HELP, OfferList(offers), Money(Merchant.Cost(offers)))
        if Unprofitable() then
            button.text, button.tooltip = L.BUY_ANYWAY, L.BUTTON_NOT_PROFITABLE .. " " .. help
        else
            button.text, button.tooltip = L.BUY_BUY, help
        end
        return button
    end
    if status == "closed" or status == "idle" or status == "ready" then
        -- Only vendor items left: the auction house can't help.
        if not AnyFromAuction(plan) then
            button.text, button.tooltip = L.BUY_BUY, L.VENDOR_FIND
            return button
        end
    end
    if status == "closed" then
        button.text, button.tooltip = L.BUY_OPEN_AH, L.BUY_OPEN_AH_HELP
    elseif status == "idle" then
        -- Not scanned yet: Buy scans first, then buys.
        button.text, button.tooltip, button.enabled = L.BUY_BUY, L.BUY_SCAN_FIRST, true
        button.onClick = Shopper.ScanAndBuy
    elseif status == "scanning" then
        button.text, button.tooltip = L.BUY_SCANNING, ScanningText()
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
        if nextPurchase == nil and status == "ready" and Shopper.HasUnscanned() then
            -- Queued after the last scan: Buy scans those first.
            button.enabled, button.tooltip = true, L.BUY_SCAN_NEW
            button.onClick = Shopper.ScanMissing
        elseif nextPurchase == nil then
            button.tooltip = L.BUTTON_NOTHING
        elseif Unprofitable() then
            button.text, button.enabled = L.BUY_ANYWAY, true
            button.tooltip = L.BUTTON_NOT_PROFITABLE .. " " .. L.BUY_ANYWAY_HELP
        else
            button.enabled = true
            button.tooltip = string.format(L.BUTTON_BUY, nextPurchase.quantity, ItemName(nextPurchase.itemID), Money(nextPurchase.budget))
        end
    end
    -- The game is busy (just after a purchase, say) and would drop the
    -- request: held until it isn't, so the click always counts.
    if button.enabled and (status == "ready" or status == "confirm") and not Shopper.ThrottleReady() then
        button.enabled = false
        button.tooltip = L.BUTTON_AH_BUSY
        Shopper.WatchThrottle()
    end
    return button
end

-- The Then craft heading's button: { text, enabled, tooltip, onClick,
-- onMouseDown }, plus the next step (to mark in the list) and, when the next
-- step is in a profession that isn't open, that profession (OpenButton.lua
-- covers the button to open it).
-- What the Craft button is about, as text: which step, and whether it's
-- crafting, opening a profession, missing materials, away from its station or
-- loading. Compared each second (PollCraft) to notice changes the game sends
-- no event for, such as walking up to an anvil.
local function CraftKey(nextCraft)
    if nextCraft == nil then
        return "none"
    end
    local state = nextCraft.crafts and ("craft" .. nextCraft.crafts) or nextCraft.open and ("open " .. nextCraft.open)
        or nextCraft.station and "station" or nextCraft.materials and "materials" or "loading"
    return tostring(nextCraft.step.recipeID) .. ":" .. state
end
local shownCraft          -- CraftKey of the Craft button shown, nil when there's none to watch

local function CraftButton()
    local button = {
        width = HEADING_BUTTON_WIDTH, enabled = false,
        -- Mouse down prepares, the click crafts: see Crafter.lua.
        onClick = function() Crafter.Craft() end, onMouseDown = Crafter.Prepare,
    }
    shownCraft = nil
    if Crafter.IsCasting() then
        button.text = L.CRAFTING
        return button
    end
    local nextCraft = Crafter.Next()
    if nextCraft == nil then
        return nil
    end
    shownCraft = CraftKey(nextCraft)
    local name = ItemName(nextCraft.step.itemID)
    -- Opening: wait, rather than offer a click that would close it again.
    local waitingFor = nextCraft.loading or (nextCraft.open and OpenButton.IsOpening(nextCraft.open) and nextCraft.open)
    if waitingFor then
        button.text, button.tooltip = L.OPENING_LABEL, string.format(L.OPENING_HELP, waitingFor)
        return button, nextCraft.step
    end
    if not nextCraft.open then
        OpenButton.Opened()
    end
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
    if nextCraft.station then
        button.tooltip = string.format(L.NEED_STATION, nextCraft.station, name)
    elseif nextCraft.materials then
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

-- The title's button: scans the auction house for live prices. On the
-- page's title line, where Best Crafts has its Scan: it's for the whole
-- order, not one section.
local function ScanButton()
    local status = Shopper.Status()
    local button = { text = L.SCAN, width = HEADING_BUTTON_WIDTH, enabled = false, onClick = Shopper.Scan }
    if status == "closed" then
        button.tooltip = L.SCAN_OPEN_AH
    elseif status == "scanning" then
        button.text = L.BUY_SCANNING
        button.tooltip = ScanningText()
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
    -- Three groups, set apart by a gap: what it sells for, what it costs,
    -- what it makes. Each pair is vendor, then auction.
    AddRow("row", L.VENDOR_PRICE, Money(s.revenue))
    AddRow("row", L.AUCTION_PRICE, OrNoPrice(s.auctionRevenue))
    AddRow("gap")
    if s.ownedValue > 0 then
        AddRow("row", L.ITEMS_YOU_HAVE, Money(-s.ownedValue))
    end
    AddRow("row", L.ITEMS_TO_BUY, Money(-s.remaining))
    -- What's been paid: always shown, under what's left to buy, so it's
    -- there to watch from the first purchase. Not taken off the profit
    -- (see README).
    AddRow("row", Gray(L.SPENT), Gray(VendorProfit.FormatCoins(s.spent)))
    AddRow("gap")
    -- The bottom line: a loss in red, label and all.
    local function Bottom(label, profit)
        return profit ~= nil and profit < 0 and Red(label) or label
    end
    AddRow("row", Bottom(L.VENDOR_PROFIT_ROW, s.profit), Money(s.profit))
    AddRow("row", Bottom(L.AUCTION_PROFIT_ROW, s.auctionProfit), OrNoPrice(s.auctionProfit))
end

-- Sections fold away when their divider is clicked (a plus or minus sign
-- on it says which), remembered per character. A folded section says how
-- many rows it holds, where that's useful.
local function Collapsed(key)
    local db = VendorProfitCharDB
    if db == nil then
        return false
    end
    -- Saved before every section folded: only the bags one did.
    if db.bagsCollapsed then
        db.collapsed = type(db.collapsed) == "table" and db.collapsed or {}
        db.collapsed.bags, db.bagsCollapsed = true, nil
    end
    return type(db.collapsed) == "table" and db.collapsed[key] == true
end

local function SetCollapsed(key, collapsed)
    VendorProfitCharDB = VendorProfitCharDB or {}
    VendorProfitCharDB.collapsed = VendorProfitCharDB.collapsed or {}
    VendorProfitCharDB.collapsed[key] = collapsed or nil
    Panel.Refresh()
end

-- A section's divider. Returns whether the section is open (its rows to be
-- added).
local function Section(key, title, count)
    local collapsed = Collapsed(key)
    local sign = collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up"
    title = "|T" .. sign .. ":12:12|t " .. title
    if collapsed and count then
        title = title .. " (" .. count .. ")"
    end
    AddRow("divider", title, nil, nil, {
        onClick = function() SetCollapsed(key, not collapsed) end,
    })
    return not collapsed
end

-- Seconds left before a step that moved into its place at movedAt takes
-- clicks (0 when it can).
function Panel.MovedWait(movedAt)
    if movedAt == nil then
        return 0
    end
    return math.max(0, movedAt + Panel.MOVED_GUARD - GetTime())
end

-- To do's details: each step's items, in a scroll box under the steps, so a
-- long order doesn't make the window run off the screen. The steps and
-- their buttons stay put above it.
local todoScroll, todoList
local todoRows = {}
local todoUsed = 0
local todoAfter          -- the row the box follows, for Panel.Lines
local todoPlaced = false

local function TodoRow(index)
    local row = todoRows[index]
    if row == nil then
        row = {}
        row.left = todoList:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.left:SetJustifyH("LEFT")
        row.left:SetWordWrap(false)
        row.right = todoList:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.right:SetJustifyH("RIGHT")
        row.right:SetWordWrap(false)
        todoRows[index] = row
    end
    return row
end

-- groups: { { title, rows = { { left, right }, ... } }, ... }: a gold title
-- for each step, then its items.
local function AddTodoDetails(groups)
    if todoScroll == nil then
        todoScroll = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
        todoList = CreateFrame("Frame", nil, todoScroll)
        todoScroll:SetScrollChild(todoList)
        -- The template shows the bar again whenever the scroll range
        -- changes (unless scrollBarHideable, which hides it at no range);
        -- this runs after it, so the bar is shown only when it's needed.
        todoScroll.scrollBarHideable = true
        todoScroll:HookScript("OnScrollRangeChanged", function(self)
            if self.ScrollBar then
                self.ScrollBar:SetShown(self.needsBar == true)
            end
        end)
        -- Behind the items and the scroll bar, to the page's edges.
        todoScroll.back = content:CreateTexture(nil, "BACKGROUND")
        todoScroll.back:SetColorTexture(0, 0, 0, 0.35)
    end
    local listWidth = WIDTH - 2 * PADDING - 3 * TODO_PADDING - SCROLLBAR_WIDTH
    todoList:SetWidth(listWidth)
    todoUsed = 0
    local function Line(left, right, isTitle)
        todoUsed = todoUsed + 1
        local row = TodoRow(todoUsed)
        local top = -(todoUsed - 1) * ROW_HEIGHT
        row.left:SetFontObject(isTitle and "GameFontNormalSmall" or "GameFontHighlightSmall")
        row.left:ClearAllPoints()
        row.left:SetPoint("TOPLEFT", todoList, "TOPLEFT", 0, top)
        row.left:SetText(left)
        row.left:Show()
        row.right:ClearAllPoints()
        row.right:SetPoint("TOPRIGHT", todoList, "TOPRIGHT", 0, top)
        row.right:SetText(right or "")
        row.right:SetShown(right ~= nil)
        FitLeft(row, listWidth * 0.6, listWidth, right ~= nil)
    end
    for _, group in ipairs(groups) do
        Line(group.title, nil, true)
        for _, item in ipairs(group.rows) do
            Line(item[1], item[2])
        end
    end
    for index = todoUsed + 1, #todoRows do
        todoRows[index].left:Hide()
        todoRows[index].right:Hide()
    end
    local shown = math.max(Panel.TODO_MIN_ROWS, math.min(todoUsed, Panel.TODO_ROWS))
    todoList:SetHeight(math.max(todoUsed, 1) * ROW_HEIGHT)
    y = y - 4
    local back = todoScroll.back
    back:ClearAllPoints()
    back:SetPoint("TOPLEFT", content, "TOPLEFT", PADDING, y)
    back:SetSize(WIDTH - 2 * PADDING, shown * ROW_HEIGHT + 2 * TODO_PADDING)
    back:Show()
    todoScroll:ClearAllPoints()
    todoScroll:SetPoint("TOPLEFT", content, "TOPLEFT", PADDING + TODO_PADDING, y - TODO_PADDING)
    todoScroll:SetSize(listWidth, shown * ROW_HEIGHT)
    -- The template puts the bar a little right of the list; here it's held
    -- the same padding from the box's right edge as the items are from its
    -- left, its arrows inside the box.
    local bar = todoScroll.ScrollBar
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", back, "TOPRIGHT", -TODO_PADDING, -TODO_PADDING - 16)
        bar:SetPoint("BOTTOMRIGHT", back, "BOTTOMRIGHT", -TODO_PADDING, TODO_PADDING + 16)
        -- Only when there's something to scroll: in a short box the bar's
        -- arrows nearly met, with no room for the thumb, and a bar that
        -- can't scroll says nothing. It only shows at the most rows, where
        -- it has room.
        todoScroll.needsBar = todoUsed > shown
        bar:SetShown(todoScroll.needsBar)
    end
    -- Shorter than before: don't leave it scrolled past its end.
    local maxScroll = math.max(todoUsed - Panel.TODO_ROWS, 0) * ROW_HEIGHT
    if (todoScroll:GetVerticalScroll() or 0) > maxScroll then
        todoScroll:SetVerticalScroll(maxScroll)
    end
    todoScroll:Show()
    todoAfter, todoPlaced = usedRows, true
    y = y - shown * ROW_HEIGHT - 2 * TODO_PADDING - 4
end

-- Where each To do step was last drawn (its top, by step), and when a step
-- last moved into the place of one that finished.
local stepPlaces = {}
local stepMovedAt = {}

local function Count(n, one, many)
    return Gray(n == 1 and one or string.format(many, n))
end

-- The Craft step's title: with about how long the crafts left will take,
-- to the nearest minute (at least 1), from the cast times the game knows.
-- Just the casts: walking to an anvil or between crafts isn't counted.
local function CraftTitle(crafts)
    local seconds = 0
    for _, step in ipairs(crafts) do
        seconds = seconds + (VendorProfit.CastSeconds(step.recipeID) or 0) * step.crafts
    end
    if seconds == 0 then
        return L.STEP_CRAFT
    end
    return string.format(L.STEP_CRAFT_TIME, math.max(1, math.floor(seconds / 60 + 0.5)))
end

-- The To do checklist, in the order you'd do it: buy (prices can change, so
-- first), collect purchases from the mailbox, take things from the bank, then
-- craft. Each step shows only while it has something left in it, numbered in
-- order, so when one is done the next moves up into its place. The steps,
-- each with its count and button, and the next craft stay at the top; their
-- items scroll in a box below (folding To do folds just the box). Returns the
-- bags list for the information section below it.
local function AddToDo(plan)
    local buying = Shopper.Status()
    local hasBuy = #plan.buyOrder > 0 or buying == "quoting" or buying == "confirm" or buying == "buying"
    local fromBags, fromMail, fromBank = Panel.SplitUses(plan.uses)
    local detailsOpen = Section("todo", L.HEAD_TODO)
    local number = 0
    local placed = {}
    -- A step and its count; its button ignores clicks just after the step
    -- moved into the place of one that finished (see MOVED_GUARD).
    local function Step(key, title, count, button)
        number = number + 1
        if button and button.onClick then
            local onClick = button.onClick
            button.onClick = function(...)
                if Panel.MovedWait(stepMovedAt[key]) == 0 then
                    onClick(...)
                end
            end
        end
        placed[#placed + 1] = { key = key, top = y }
        return AddRow("heading", number .. ". " .. title, count, button)
    end
    local groups = {}

    if hasBuy then
        Step("buy", L.STEP_BUY, #plan.buyOrder > 0 and Count(#plan.buyOrder, L.TODO_ITEM, L.TODO_ITEMS) or nil,
            BuyButton(plan))
        -- The price to confirm, where it can't be missed.
        if buying == "confirm" then
            local p = Shopper.Purchase()
            AddRow("note", NORMAL_FONT_COLOR:WrapTextInColorCode(
                string.format(L.BUTTON_CONFIRM, p.quantity, ItemName(p.itemID), Money(p.quote))), nil,
                { text = L.CANCEL, onClick = Shopper.Cancel, width = 70 })
        end
        local items = {}
        for _, line in ipairs(plan.buyOrder) do
            items[#items + 1] = { ItemLabel(line.itemID, line.quantity), BuyLineRight(line) }
        end
        groups[#groups + 1] = { title = L.STEP_BUY, rows = items }
    end

    local function Uses(key, title, uses, button)
        Step(key, title, Count(#uses, L.TODO_ITEM, L.TODO_ITEMS), button)
        local items = {}
        for _, use in ipairs(uses) do
            items[#items + 1] = { ItemLabel(use.itemID, use.quantity) }
        end
        groups[#groups + 1] = { title = title, rows = items }
    end
    if #fromMail > 0 then
        Uses("mail", L.STEP_MAIL, fromMail)
    end
    if #fromBank > 0 then
        Uses("bank", L.STEP_BANK, fromBank, Panel.BankButton(fromBank))
    end

    shownCraft = nil
    local craftRow, openProfession
    if #plan.crafts > 0 then
        local craftButton, nextStep
        craftButton, nextStep, openProfession = CraftButton()
        craftRow = Step("craft", CraftTitle(plan.crafts), Count(#plan.crafts, L.TODO_RECIPE, L.TODO_RECIPES), craftButton)
        local items = {}
        for _, step in ipairs(plan.crafts) do
            local detail = string.format(step.crafts == 1 and L.CRAFTS_ONE or L.CRAFTS, step.crafts)
            if step.profession then
                detail = step.profession .. ", " .. detail
            end
            local label = ItemLabel(step.itemID, step.crafts * step.makes)
            if step == nextStep then
                label = NORMAL_FONT_COLOR:WrapTextInColorCode(L.NEXT_MARK) .. " " .. label
                -- The next craft under its step too, so it's seen without
                -- scrolling.
                AddRow("row", label, Gray(detail))
            end
            items[#items + 1] = { label, Gray(detail) }
        end
        groups[#groups + 1] = { title = L.STEP_CRAFT, rows = items }
    end

    -- Hand in: queued turn-ins (TurnIns.lua), what to hand to whom. No
    -- button: an addon can't hand in a quest. Handing it in counts it down.
    -- Under the step, what to bring and to whom; in the box, like a craft,
    -- what it makes and where, how many times (the whole sentence on one
    -- line ran past the box's edge).
    if #plan.handIns > 0 then
        local times = 0
        for _, handIn in ipairs(plan.handIns) do
            times = times + handIn.crafts
        end
        Step("handin", L.STEP_HAND_IN, Count(times, L.TODO_HAND_IN, L.TODO_HAND_INS))
        local rows = {}
        for _, handIn in ipairs(plan.handIns) do
            local turnIn = handIn.turnIn
            AddRow("row", ItemLabel(turnIn.give, turnIn.count * handIn.crafts), Gray(turnIn.npc .. ", " .. turnIn.place))
            local times = handIn.crafts == 1 and L.TODO_HAND_IN or string.format(L.TODO_HAND_INS, handIn.crafts)
            rows[#rows + 1] = { ItemLabel(handIn.itemID, handIn.makes * handIn.crafts), Gray(turnIn.place .. ", " .. times) }
        end
        groups[#groups + 1] = { title = L.STEP_HAND_IN, rows = rows }
    end

    -- Post: the Post Queue, at the auction house (Poster.lua), with the
    -- price to post at where it can't be missed. The box below lists the
    -- cheapest prices found for it, as the Sell tab would show them, for a
    -- gut check: from the search already done, so no extra calls, and
    -- without touching the game's Sell tab.
    local toPost = Poster.Items()
    if #toPost > 0 then
        Step("post", L.STEP_POST, Count(#toPost, L.TODO_ITEM, L.TODO_ITEMS), PostButton())
        local item = Poster.Current()
        if item and item.price and (Poster.Status() == "ready" or Poster.Status() == "posting") then
            local note = string.format(L.POST_AT, PostCount(item.itemID), ItemName(item.itemID), Money(item.price))
            if item.guess then
                note = note .. " " .. string.format(L.POST_GUESSED, Money(item.guess))
            elseif item.skipped and item.skipped > 0 then
                note = note .. " " .. L.POST_SKIPPED_CHEAP
            end
            if Poster.BelowCost() then
                note = Red(note .. " " .. string.format(L.POST_BELOW_COST, Money(item.cost)))
            else
                note = NORMAL_FONT_COLOR:WrapTextInColorCode(note)
            end
            AddRow("note", note)
            if item.listed and #item.listed > 0 then
                local rows = {}
                for index, group in ipairs(item.listed) do
                    local right = "x" .. group.quantity
                    if index <= (item.skipped or 0) then
                        right = right .. " " .. Gray(L.POST_LISTED_SKIPPED)
                    end
                    rows[index] = { Money(group.price), right }
                end
                -- First in the box, posting started early or not, so the
                -- prices are in view; titled with the item, so the box
                -- says what they're for.
                table.insert(groups, 1, { title = string.format(L.POST_LISTED_TITLE, ItemName(item.itemID)), rows = rows })
            end
        end
    end

    -- A step now where one that's gone was (it finished, and this one moved
    -- up into its place): a click there was likely meant for the old one.
    -- Steps that only shifted (a line added above) don't count.
    local present, places = {}, {}
    for _, step in ipairs(placed) do
        present[step.key] = true
        places[step.top] = step.key
    end
    for _, step in ipairs(placed) do
        local before = stepPlaces[step.top]
        if before ~= nil and before ~= step.key and not present[before] then
            stepMovedAt[step.key] = GetTime()
        end
    end
    stepPlaces = places
    craftCover = openProfession and { button = craftRow.button, profession = openProfession, movedAt = stepMovedAt.craft }
        or nil

    if detailsOpen and number == 0 then
        AddRow("note", L.EMPTY_TODO)
    end
    -- The box whenever there's a step, empty or not (just a Post step not
    -- priced yet has nothing to list), never smaller than TODO_MIN_ROWS.
    if detailsOpen and number > 0 then
        AddTodoDetails(groups)
    end
    return fromBags
end

-- What one queued entry makes, on its own, at today's prices, along its
-- cheapest route (or as it is, for an exact one): { cost, vendor, auction }
-- for all its crafts (vendor or auction nil when there's no price to sell at).
local function EntryProfit(entry)
    local route = VendorProfit.Route.ForRecipe(entry.itemID, entry.reagents, nil, entry.exact)
    local cost = math.floor(route.cost * entry.crafts + 0.5)
    local made = entry.count * entry.crafts
    local sellPrice = entry.sellPrice or select(11, C_Item.GetItemInfo(entry.itemID))
    local _, auction = VendorProfit.GetBuyPrices(entry.itemID)
    return {
        cost = cost,
        vendor = sellPrice and sellPrice > 0 and sellPrice * made - cost or nil,
        auction = auction and math.floor(auction * made * VendorProfit.GetAfterAHCut()) - cost or nil,
    }
end

-- Whether a profit makes money: positive vendor or auction profit.
local function MakesMoney(vendor, auction)
    return (vendor ~= nil and vendor > 0) or (auction ~= nil and auction > 0)
end

local function QueuedTooltip(entry)
    return function(tooltip)
        local profit = EntryProfit(entry)
        tooltip:SetText(ItemLabel(entry.itemID, entry.crafts * entry.count))
        tooltip:AddLine(" ")
        tooltip:AddDoubleLine(entry.exact and L.QUEUED_COST_EXACT or L.QUEUED_COST, Money(-profit.cost))
        tooltip:AddDoubleLine(L.VENDOR_PROFIT_ROW,
            profit.vendor and Money(profit.vendor) or Gray(L.QUEUED_NO_VENDOR))
        tooltip:AddDoubleLine(L.AUCTION_PROFIT_ROW,
            profit.auction and Money(profit.auction) or Gray(L.NO_AUCTION_PRICE))
    end
end

local CANCEL_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local function AddQueued(index, entry)
    local profit = EntryProfit(entry)
    local label = ItemLabel(entry.itemID, entry.crafts * entry.count)
    if not MakesMoney(profit.vendor, profit.auction) then
        label = Red(label)
    end
    if entry.exact then
        label = label .. " " .. Gray(L.QUEUED_EXACT_MARK)
    end
    -- A turn-in (TurnIns.lua): handed in, not crafted, so no recipe to show.
    local turnIn = entry.recipeID < 0
    if turnIn then
        label = label .. " " .. Gray(L.QUEUED_TURN_IN_MARK)
    end
    AddRow("row", label, nil, nil, {
        tooltip = QueuedTooltip(entry),
        -- Clicking the item shows its recipe in the professions window.
        onClick = not turnIn and function() VendorProfit.Recipes.Show(entry.recipeID, entry.profession) end or nil,
        -- Right to left: cancel, +, -.
        icons = {
            { texture = CANCEL_TEXTURE, tooltip = L.QUEUED_REMOVE, onClick = function() Order.Remove(index) end },
            -- One at a time, or five with Shift; never below one (cancel
            -- takes it off).
            { text = "+", tooltip = L.QUEUED_MORE, onClick = function()
                Order.SetCrafts(index, entry.crafts + VendorProfit.QueueStep())
            end },
            {
                text = "-", enabled = entry.crafts > 1, tooltip = L.QUEUED_FEWER,
                onClick = function() Order.SetCrafts(index, entry.crafts - VendorProfit.QueueStep()) end,
            },
        },
    })
end

-- One item in the Post Queue: how many to post (and how many are in your
-- bags, when more), then x (off the queue: keep them), + and - (five with
-- Shift), between 1 and what's in your bags.
local function AddPostQueued(item)
    local label = ItemLabel(item.itemID, item.count)
    if item.bags > item.count then
        label = label .. " " .. Gray(string.format(L.POST_QUEUE_IN_BAGS, item.bags))
    end
    AddRow("row", label, nil, nil, {
        icons = {
            { texture = CANCEL_TEXTURE, tooltip = string.format(L.POST_QUEUE_REMOVE, ItemName(item.itemID)),
                onClick = function() Poster.Remove(item.itemID) end },
            { text = "+", enabled = item.count < item.bags, tooltip = L.POST_QUEUE_MORE, onClick = function()
                Poster.SetCount(item.itemID, item.count + VendorProfit.QueueStep())
            end },
            { text = "-", enabled = item.count > 1, tooltip = L.POST_QUEUE_FEWER, onClick = function()
                Poster.SetCount(item.itemID, item.count - VendorProfit.QueueStep())
            end },
        },
    })
end

-- The title (with Scan), then the order's profit, the queued crafts,
-- what's queued to post, the To do checklist, and what's already in your
-- bags, for information. Every section shows even with nothing in it,
-- saying what it's for and when it fills, so the page keeps its shape.
local function AddContent()
    local s = Shopper.Summary()
    local plan = s.plan

    local entries = Order.Entries()
    local posts = Poster.Items()
    AddRow("heading", L.TAB_SHOPPING, nil, #entries > 0 and ScanButton() or nil)

    if Section("profit", L.HEAD_PROFIT) then
        if #entries > 0 then
            AddProfit(s)
        else
            AddRow("note", L.EMPTY_PROFIT)
        end
    end
    if Section("queued", L.HEAD_QUEUED, #entries) then
        for index, entry in ipairs(entries) do
            AddQueued(index, entry)
        end
        if #entries == 0 then
            AddRow("note", L.EMPTY_QUEUED)
        end
    end
    if Section("postQueue", L.HEAD_POST_QUEUE, #posts) then
        for _, item in ipairs(posts) do
            AddPostQueued(item)
        end
        if #posts == 0 then
            AddRow("note", L.EMPTY_POST_QUEUE)
        end
    end
    local fromBags = AddToDo(plan)
    if Section("bags", L.HEAD_BAGS, #fromBags) then
        for _, use in ipairs(fromBags) do
            AddRow("row", ItemLabel(use.itemID, use.quantity))
        end
        if #fromBags == 0 then
            AddRow("note", L.EMPTY_BAGS)
        end
    end
end

-- Buttons ----------------------------------------------------------------------

-- Messages at the end, the panel's height, and the open-profession cover.
local function FinishLayout()
    for _, source in ipairs({ Shopper, Banker, Poster }) do
        local text, isError = source.Message()
        if text then
            AddRow("note", isError and Red(text) or text)
        end
    end

    -- With the Craft button in place and the mouse on it, cover it to open
    -- the profession (otherwise its OnEnter does, when the mouse gets
    -- there), or uncover.
    -- A Craft step that just moved under the mouse waits a moment first (see
    -- MOVED_GUARD), then the panel redraws and covers it.
    local wait = craftCover and Panel.MovedWait(craftCover.movedAt) or 0
    if craftCover and not Order.IsEmpty() and OpenButton.HasMouse(craftCover.button) and wait == 0 then
        craftCover.button:SetEnabled(OpenButton.Cover(craftCover.button, craftCover.profession))
    else
        OpenButton.Hide()
        if wait > 0 and OpenButton.HasMouse(craftCover.button) then
            C_Timer.After(wait, Panel.Refresh)
        end
    end
    return -y + PADDING
end

-- Frame ------------------------------------------------------------------------

-- Pages, in tab order: { name, icon, label, width (optional), create(page),
-- refresh(page) -> height }. Other files add theirs with Panel.AddPage before the window is
-- first shown.
local pageDefs = {}
local pages = {}
local activeTab = "shopping"

function Panel.AddPage(def)
    pageDefs[#pageDefs + 1] = def
end

function Panel.ActiveTab()
    return activeTab
end

local TAB_TOP = 36
local TAB_SPACING = 48
local TAB_SIZE = 32

-- Tall enough for every side tab, so none hang below the window.
local function MinHeight()
    return TAB_TOP + (#pageDefs - 1) * TAB_SPACING + TAB_SIZE + 12
end

function Panel.MinHeight()
    return MinHeight()
end

local function CreateSideTab(index, def)
    local tab = CreateFrame("CheckButton", nil, frame)
    tab:SetSize(TAB_SIZE, TAB_SIZE)
    tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -TAB_TOP - (index - 1) * TAB_SPACING)
    local border = tab:CreateTexture(nil, "BACKGROUND")
    border:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    border:SetSize(64, 64)
    border:SetPoint("TOPLEFT", tab, "TOPLEFT", -3, 11)
    tab:SetNormalTexture(def.icon)
    tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight", "ADD")
    tab:SetScript("OnClick", function()
        activeTab = def.name
        Panel.Refresh()
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(def.label)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tab.label = def.label
    return tab
end

local Place   -- puts the window where it belongs (below)

local function Create()
    frame = CreateFrame("Frame", "VendorProfitPanel", UIParent, "ButtonFrameTemplate")
    -- Escape closes it along with the game's other windows, as they do. The
    -- game hides it directly, which works in combat (it isn't protected).
    if UISpecialFrames then
        table.insert(UISpecialFrames, "VendorProfitPanel")
    end
    -- In the same strata as the game's windows (and most addons'), and
    -- brought to the front when clicked: clicking another window brings that
    -- one in front of it instead, as windows normally do. (A higher strata
    -- kept it above everything, bags included, however you clicked.)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    ButtonFrameTemplate_HidePortrait(frame)
    ButtonFrameTemplate_HideButtonBar(frame)
    if frame.Inset then
        frame.Inset:Hide()
    end
    frame:SetTitle(L.PANEL_TITLE)
    -- The template's close button closes through HideUIPanel, which the
    -- game blocks in combat (it does nothing then). The window isn't
    -- protected, so hiding it directly works in combat too.
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function() Panel.Hide() end)
    end
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
        -- The game leaves a moved window anchored by a point of its choosing
        -- (often its center), so the window would grow and shrink at both
        -- edges as pages change height. Held by its top left corner again.
        Place()
        Panel.Refresh()
    end)
    frame:Hide()

    -- One page per tab, each filling the window; side tabs down the right
    -- edge, like the professions window's.
    frame.tabs = {}
    for index, def in ipairs(pageDefs) do
        local page = CreateFrame("Frame", nil, frame)
        page:SetAllPoints(frame)
        page:Hide()
        pages[def.name] = page
        def.create(page)
        frame.tabs[def.name] = CreateSideTab(index, def)
    end
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

-- How far below the top of the screen it opens until you move it.
local DEFAULT_TOP = -120

-- Where you left it, or centered across the screen near its top. Held by
-- its top left corner either way: tabs differ in width and height, and
-- anchored by its center the window's edges would jump on every tab
-- switch. Only ever anchored to UIParent: anchored to a protected window
-- (the professions window, say) it would be protected too, and the game
-- would block hiding it in combat.
function Place()
    frame:ClearAllPoints()
    local saved = SavedPosition()
    if saved and saved.left and saved.top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.left, saved.top)
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOP", -frame:GetWidth() / 2, DEFAULT_TOP)
    end
end

local function RefreshShopping()
    usedRows = 0
    y = TOP
    craftCover = nil
    todoPlaced = false
    AddContent()
    local height = FinishLayout()
    HideUnusedRows()
    if todoScroll and not todoPlaced then
        todoScroll:Hide()
        todoScroll.back:Hide()
    end
    return height
end

local function Refresh()
    for _, def in ipairs(pageDefs) do
        local active = def.name == activeTab
        pages[def.name]:SetShown(active)
        frame.tabs[def.name]:SetChecked(active)
    end
    -- Off the Shopping List: not over its Craft button. (Best Crafts has its
    -- own button the cover goes over.)
    if activeTab ~= "shopping" and craftCover then
        OpenButton.Uncover(craftCover.button)
    end
    for _, def in ipairs(pageDefs) do
        if def.name == activeTab then
            -- Refreshed first: a tab can change its width as it lays out
            -- its columns (Columns.lua).
            local height = def.refresh(pages[def.name])
            frame:SetWidth(def.width or WIDTH)
            frame:SetHeight(math.max(height, MinHeight()))
        end
    end
    -- The cover was placed while laying out; the new height can move a
    -- centered window.
    OpenButton.Follow()
end

function Panel.Refresh()
    if frame == nil or not frame:IsShown() then
        return
    end
    xpcall(Refresh, geterrorhandler())
end

-- Shows the window, on a tab if one is given.
function Panel.Show(tab)
    if tab then
        activeTab = tab
    end
    if frame == nil then
        Create()
    end
    Place()
    frame:Show()
    -- Opened: in front of the other windows, as if clicked.
    frame:Raise()
    Panel.Refresh()
end

function Panel.Hide()
    if frame then
        frame:Hide()
    end
end

-- Forgets where you moved it, so it's centered near the top again.
function Panel.ResetPosition()
    if VendorProfitCharDB then
        VendorProfitCharDB.panel = nil
    end
    if frame then
        Place()
    end
end

function Panel.IsShown()
    return frame ~= nil and frame:IsShown()
end

-- Shows the window on a tab, or hides it if it's already showing that tab.
function Panel.Toggle(tab)
    if Panel.IsShown() and (tab == nil or tab == activeTab) then
        Panel.Hide()
    else
        Panel.Show(tab)
    end
end

-- The rows shown, as "left | right" text, and the buttons. For tests and
-- debugging.
function Panel.Lines()
    local lines = {}
    local function Add(row)
        local text = row.left:IsShown() and row.left:GetText() or ""
        if row.right:IsShown() and (row.right:GetText() or "") ~= "" then
            text = text .. " | " .. row.right:GetText()
        end
        if text ~= "" then
            lines[#lines + 1] = text
        end
    end
    for index = 1, usedRows do
        Add(rows[index])
        -- To do's details, where their box is.
        if todoPlaced and index == todoAfter then
            for detail = 1, todoUsed do
                Add(todoRows[detail])
            end
        end
    end
    return lines
end

-- To do's scroll box (for tests).
function Panel.TodoScroll()
    return todoScroll
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

-- The first shown row whose left text contains text (and right text right,
-- if given): its regions (left, right, button, icons, hit: the text's hover
-- and click area). For tests and debugging.
function Panel.FindRow(text, right)
    for index = 1, usedRows do
        local row = rows[index]
        if row.left:IsShown() and (row.left:GetText() or ""):find(text, 1, true)
            and (right == nil or (row.right:IsShown() and (row.right:GetText() or ""):find(right, 1, true))) then
            return row
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

Panel.AddPage({
    name = "shopping",
    icon = "Interface\\Icons\\INV_Misc_Bag_08",
    label = L.TAB_SHOPPING,
    create = function(page) content = page end,
    refresh = function() return RefreshShopping() end,
})

-- The window only opens and closes when you open or close it: not at the
-- auction house, bank or a vendor, and not on Queue. It redraws as they
-- change while it's open.
-- What the Shopping List shows changing: redrawn only while it's the tab
-- up. The other tabs listen for what they show (Best Crafts redrawing for
-- every bag, cast and plan change made crafting stutter).
local function RefreshIfShopping()
    if activeTab == "shopping" then
        Panel.Refresh()
    end
end
Shopper.OnChange(RefreshIfShopping)
Poster.OnChange(RefreshIfShopping)
Banker.OnChange(RefreshIfShopping)
Merchant.OnChange(RefreshIfShopping)

-- Walking up to a crafting station (or away from one) changes what can be
-- crafted, but the game sends no event for it, so the panel would keep saying
-- "Needs Anvil nearby" until something else redrew it. While a Craft step is
-- shown, the next craft is checked each second and the panel redrawn when it
-- changed.
Panel.CRAFT_POLL = 1
function Panel.PollCraft()
    if shownCraft == nil or not Panel.IsShown() or activeTab ~= "shopping" or Order.IsEmpty()
        or Crafter.IsCasting() then
        return
    end
    if CraftKey(Crafter.Next()) ~= shownCraft then
        Panel.Refresh()
    end
end
local poller = CreateFrame("Frame")
local sincePoll = 0
poller:SetScript("OnUpdate", function(_, elapsed)
    sincePoll = sincePoll + elapsed
    if sincePoll >= Panel.CRAFT_POLL then
        sincePoll = 0
        xpcall(Panel.PollCraft, geterrorhandler())
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_MONEY")
-- The Craft button follows the open profession window and your casting.
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
    "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_DATA_SOURCE_CHANGING" }) do
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
    RefreshIfShopping()
end)

-- /vprofit stations: each queued step's crafting station and whether the
-- game says you're at it, to check what it reports away from a profession.
function Panel.PrintStations()
    local list = Crafter.Stations()
    if #list == 0 then
        print(L.STATIONS_NONE)
        return
    end
    for _, entry in ipairs(list) do
        local where
        if entry.station == nil then
            where = L.STATIONS_NEEDS_NONE
        elseif entry.at == true then
            where = string.format(L.STATIONS_HERE, entry.station)
        elseif entry.at == false then
            where = string.format(L.STATIONS_AWAY, entry.station)
        else
            where = string.format(L.STATIONS_UNKNOWN, entry.station)
        end
        print(string.format(L.STATIONS_LINE, ItemName(entry.step.itemID), entry.step.profession or "?", where))
    end
end

SLASH_VENDORPROFIT1 = "/vprofit"
SLASH_VENDORPROFIT2 = "/vendorprofit"
SlashCmdList.VENDORPROFIT = function(arg)
    local command = arg and arg:lower():match("^%s*(%S*)") or ""
    if command == "reset" then
        Panel.ResetPosition()
        Panel.Show()
    elseif command == "best" then
        Panel.Toggle("best")
    elseif command == "history" then
        Panel.Toggle("history")
    elseif command == "purchases" then
        Panel.Toggle("purchases")
    elseif command == "gold" then
        Panel.Toggle("gold")
    elseif command == "minimap" then
        VendorProfit.MinimapButton.Toggle()
    elseif command == "prices" then
        VendorProfit.Merchant.ShowPriceLines()
    elseif command == "stations" then
        Panel.PrintStations()
    else
        Panel.Toggle()
    end
end
