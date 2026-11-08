-- The Vendor Profit window, with a tab per page down its right side: the
-- Shopping List (here: the queued order, its profit, the To do checklist and
-- what's already in your bags; buying, crafting and taking from the bank are
-- buttons on their sections' headings) and Best Crafts (BestPanel.lua).
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
        row.hit:EnableMouse(true)
        row.hit:SetScript("OnEnter", function(self)
            if self.tooltip then
                VendorProfit.SetRowTooltipOwner(self)
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
    row.left:SetWidth(kind == "note" and (WIDTH - 2 * PADDING - reserved) or (WIDTH * 0.55))
    row.left:Show()

    row.right:ClearAllPoints()
    row.right:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PADDING - reserved, y)
    row.right:SetText(right or "")
    row.right:SetShown(right ~= nil)

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

-- What a scan is doing: the batch lookup, then "Scanning 2 of 5...".
local function ScanningText()
    if Shopper.IsLookingUp() then
        return L.BUTTON_LOOKING_UP
    end
    local done, total = Shopper.ScanProgress()
    return string.format(L.BUTTON_SCANNING, math.min(done + 1, total), total)
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
        if nextPurchase == nil then
            button.tooltip = L.BUTTON_NOTHING
        elseif Unprofitable() then
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
    -- The bottom line: a loss in red, label and all.
    local function Bottom(label, profit)
        return profit ~= nil and profit < 0 and Red(label) or label
    end
    AddRow("row", Bottom(L.VENDOR_PROFIT_ROW, s.profit), Money(s.profit))
    AddRow("row", Bottom(L.AUCTION_PROFIT_ROW, s.auctionProfit), OrNoPrice(s.auctionProfit))
    if s.spent > 0 then
        AddRow("gap")
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
-- Whether "Already in your bags" is folded away, saved per character.
local function BagsCollapsed()
    return VendorProfitCharDB ~= nil and VendorProfitCharDB.bagsCollapsed == true
end

local function SetBagsCollapsed(collapsed)
    VendorProfitCharDB = VendorProfitCharDB or {}
    VendorProfitCharDB.bagsCollapsed = collapsed or nil
    Panel.Refresh()
end

-- What one queued entry makes, on its own, along its cheapest route at
-- today's prices: { cost, vendor, auction } for all its crafts (vendor or
-- auction nil when there's no price to sell at).
local function EntryProfit(entry)
    local route = VendorProfit.Route.ForRecipe(entry.itemID, entry.reagents)
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
        tooltip:AddDoubleLine(L.QUEUED_COST, Money(-profit.cost))
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
    AddRow("row", label, nil, nil, {
        tooltip = QueuedTooltip(entry),
        -- Clicking the item shows its recipe in the professions window.
        onClick = function() VendorProfit.Recipes.Show(entry.recipeID, entry.profession) end,
        -- Right to left: cancel, +, -.
        icons = {
            { texture = CANCEL_TEXTURE, tooltip = L.QUEUED_REMOVE, onClick = function() Order.Remove(index) end },
            { text = "+", tooltip = L.QUEUED_MORE, onClick = function() Order.SetCrafts(index, entry.crafts + 1) end },
            {
                text = "-", enabled = entry.crafts > 1, tooltip = L.QUEUED_FEWER,
                onClick = function() Order.SetCrafts(index, entry.crafts - 1) end,
            },
        },
    })
end

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
        AddQueued(index, entry)
    end

    AddProfit(s)
    local fromBags = AddToDo(plan)

    if #fromBags > 0 then
        -- Click the divider to fold it away (remembered per character).
        local collapsed = BagsCollapsed()
        local sign = collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up"
        local title = "|T" .. sign .. ":12:12|t " .. L.HEAD_BAGS
        if collapsed then
            title = title .. " (" .. #fromBags .. ")"
        end
        AddRow("divider", title, nil, nil, {
            onClick = function() SetBagsCollapsed(not collapsed) end,
        })
        if not collapsed then
            for _, use in ipairs(fromBags) do
                AddRow("row", ItemLabel(use.itemID, use.quantity))
            end
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

    -- With the Craft button in place, cover it to open the profession, or
    -- uncover.
    if craftCover and not Order.IsEmpty() then
        craftCover.button:SetEnabled(OpenButton.Cover(craftCover.button, craftCover.profession))
    else
        OpenButton.Hide()
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

local function Create()
    frame = CreateFrame("Frame", "VendorProfitPanel", UIParent, "ButtonFrameTemplate")
    -- Above the professions window, auction house, bank and vendor it sits
    -- beside, and brought to the front when clicked. (The secure Open button
    -- over Craft is a strata higher still.)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
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

local function Dock()
    frame:ClearAllPoints()
    local saved = SavedPosition()
    if saved and saved.left and saved.top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.left, saved.top)
    elseif AuctionHouseFrame and AuctionHouseFrame:IsShown() then
        frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
    elseif Banker.IsBankOpen() and BankFrame and BankFrame:IsShown() then
        frame:SetPoint("TOPLEFT", BankFrame, "TOPRIGHT", 4, 0)
    elseif Merchant.IsOpen() and MerchantFrame and MerchantFrame:IsShown() then
        frame:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 4, 0)
    elseif ProfessionsFrame and ProfessionsFrame:IsShown() then
        frame:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 4, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER")
    end
end

local function RefreshShopping()
    usedRows = 0
    y = TOP
    craftCover = nil
    AddContent()
    local height = FinishLayout()
    HideUnusedRows()
    return height
end

local function Refresh()
    for _, def in ipairs(pageDefs) do
        local active = def.name == activeTab
        pages[def.name]:SetShown(active)
        frame.tabs[def.name]:SetChecked(active)
    end
    if activeTab ~= "shopping" then
        OpenButton.Hide()
    end
    for _, def in ipairs(pageDefs) do
        if def.name == activeTab then
            frame:SetWidth(def.width or WIDTH)
            frame:SetHeight(math.max(def.refresh(pages[def.name]), MinHeight()))
        end
    end
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

-- The first shown row whose left text contains text: its regions (left,
-- right, button, icons, hit: the text's hover and click area). For tests and debugging.
function Panel.FindRow(text)
    for index = 1, usedRows do
        local row = rows[index]
        if row.left:IsShown() and (row.left:GetText() or ""):find(text, 1, true) then
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

-- Opens with the auction house when something is queued. It only ever
-- closes when you close it.
local lastStatus = Shopper.Status()
Shopper.OnChange(function()
    local status = Shopper.Status()
    if lastStatus == "closed" and status ~= "closed" and not Order.IsEmpty() then
        -- Already open (on Best Crafts, say): stays on its tab.
        Panel.Show(not Panel.IsShown() and "shopping" or nil)
    end
    lastStatus = status
    Panel.Refresh()
end)

-- Opens at the bank when there's something to take out of it.
local bankWasOpen = Banker.IsBankOpen()
Banker.OnChange(function()
    local open = Banker.IsBankOpen()
    if open and not bankWasOpen and not Order.IsEmpty() and not Panel.IsShown() then
        local _, _, fromBank = Panel.SplitUses(Shopper.Summary().plan.uses)
        if #fromBank > 0 then
            Panel.Show("shopping")
        end
    end
    bankWasOpen = open
    Panel.Refresh()
end)

-- Opens at a vendor that sells something the order still needs.
local merchantWasOpen = Merchant.IsOpen()
Merchant.OnChange(function()
    local open = Merchant.IsOpen()
    if open and not merchantWasOpen and not Order.IsEmpty() and not Panel.IsShown() then
        if #Merchant.Offers(Shopper.Summary().plan) > 0 then
            Panel.Show("shopping")
        end
    end
    merchantWasOpen = open
    Panel.Refresh()
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
    Panel.Refresh()
end)

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
    elseif command == "prices" then
        VendorProfit.Merchant.ShowPriceLines()
    else
        Panel.Toggle()
    end
end
