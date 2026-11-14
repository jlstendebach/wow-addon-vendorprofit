-- The Purchase History tab of the Vendor Profit window: your recent
-- purchases (History.lua), newest first, with what you paid for each one,
-- for a gut check against today's price. Auction house purchases show up
-- when you take them out of the mailbox; vendor purchases straight away.
--
-- The list can hold thousands of purchases, so it only builds the rows that
-- fit on screen and refills them as it scrolls.

local _, ns = ...
local VendorProfit = ns.VendorProfit
local History = VendorProfit.History
local Panel = VendorProfit.Panel
local Columns = VendorProfit.Columns
local L = VendorProfit.L

local PurchasePanel = {}
VendorProfit.PurchasePanel = PurchasePanel

-- Wider if the columns need it (set in Create).
local WIDTH = 540
local PADDING = 16
local ROW_HEIGHT = 18
-- The column headings sit 16 above the list, as far below the title (12
-- tall, at -32) as Profit History's total is below its title.
local LIST_TOP = -66
local VISIBLE_ROWS = 18
local SCROLLBAR_WIDTH = 24
local LIST_WIDTH = WIDTH - 2 * PADDING - SCROLLBAR_WIDTH
-- The columns, by key (Columns.lua), laid out when the tab is built: Date,
-- Item, From, Each, Total, Now (the cheapest price today).
local col
-- This tab's entry in the window (Panel.AddPage), for the width.
local pageDef

local frame
local rows = {}

local function Gray(text)
    return GRAY_FONT_COLOR:WrapTextInColorCode(text)
end

local function ItemLabel(itemID, n)
    local name = C_Item.GetItemInfo(itemID)
    if name == nil then
        VendorProfit.RedrawWhenLoaded(itemID, PurchasePanel.Refresh)
        name = "item " .. itemID
    end
    local icon = select(5, C_Item.GetItemInfoInstant(itemID))
    local label = (icon and ("|T" .. icon .. ":0|t ") or "") .. name
    if n > 1 then
        label = label .. " x" .. n
    end
    return label
end

-- Copper, to a hundredth for prices per item that don't come out even.
local function Money(copper)
    return VendorProfit.FormatMoney(math.floor(copper + 0.5))
end

-- What one costs now: the cheaper of the vendor and auction prices.
local function MarketNow(itemID)
    local vendor, auction = VendorProfit.GetBuyPrices(itemID)
    if vendor and auction then
        return math.min(vendor, auction)
    end
    return vendor or auction
end

local function Column(parent, width, justify)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH(justify)
    text:SetWordWrap(false)
    text:SetWidth(width)
    return text
end

local function ShowTooltip(row)
    local purchase = row.purchase
    if purchase == nil then
        return
    end
    VendorProfit.SetRowTooltipOwner(row.hit, { row.date, row.item, row.from, row.each, row.total, row.market })
    GameTooltip:SetText(ItemLabel(purchase.item, purchase.n))
    GameTooltip:AddLine(date(L.HISTORY_TIME_FORMAT, purchase.time), 1, 1, 1)
    GameTooltip:AddDoubleLine(L.PURCHASES_EACH_LONG, Money(purchase.total / purchase.n))
    local now = MarketNow(purchase.item)
    if now then
        GameTooltip:AddDoubleLine(L.PURCHASES_NOW_LONG, Money(now))
    end
    GameTooltip:Show()
end

-- The slot-th of the rows that fit on screen.
local function GetRow(slot)
    local row = rows[slot]
    if row == nil then
        local list = frame.list
        row = {}
        row.date = Column(list, col.date.width, "LEFT")
        row.item = Column(list, col.item.width, "LEFT")
        row.from = Column(list, col.from.width, "LEFT")
        row.each = Column(list, col.each.width, "RIGHT")
        row.total = Column(list, col.total.width, "RIGHT")
        row.market = Column(list, col.market.width, "RIGHT")
        row.hit = CreateFrame("Frame", nil, list)
        row.hit:SetSize(LIST_WIDTH, ROW_HEIGHT)
        row.hit:EnableMouse(true)
        row.hit:SetScript("OnEnter", function() ShowTooltip(row) end)
        row.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.regions = { row.date, row.item, row.from, row.each, row.total, row.market, row.hit }
        rows[slot] = row
    end
    return row
end

-- Puts a row at a place in the list (1 = top of the whole list).
local function PlaceRow(row, index)
    if row.index == index then
        return
    end
    row.index = index
    local list = frame.list
    local top = -(index - 1) * ROW_HEIGHT - 2
    local function At(region, point, x)
        region:ClearAllPoints()
        region:SetPoint(point, list, point, x, top)
    end
    At(row.date, "TOPLEFT", 0)
    At(row.item, "TOPLEFT", col.item.left)
    At(row.from, "TOPRIGHT", col.from.right)
    At(row.each, "TOPRIGHT", col.each.right)
    At(row.total, "TOPRIGHT", col.total.right)
    At(row.market, "TOPRIGHT", col.market.right)
    row.hit:ClearAllPoints()
    row.hit:SetPoint("TOPLEFT", list, "TOPLEFT", 0, top + 2)
end

-- Fills the rows that fit on screen from where the list is scrolled to.
local function Render()
    local count = History.PurchaseCount()
    local first = math.floor((frame.scroll:GetVerticalScroll() or 0) / ROW_HEIGHT)
    local needed = math.min(VISIBLE_ROWS + 1, math.max(count - first, 0))
    for slot = 1, math.max(needed, #rows) do
        local purchase = slot <= needed and History.Purchase(first + slot)
        local row = (purchase or rows[slot]) and GetRow(slot)
        if purchase then
            PlaceRow(row, first + slot)
            row.purchase = purchase
            row.date:SetText(date(L.HISTORY_DATE_FORMAT, purchase.time))
            row.item:SetText(ItemLabel(purchase.item, purchase.n))
            row.from:SetText(purchase.how == "vendor" and L.HISTORY_VENDOR or L.HISTORY_AUCTION)
            row.each:SetText(Money(purchase.total / purchase.n))
            row.total:SetText(Money(purchase.total))
            local now = MarketNow(purchase.item)
            row.market:SetText(now and Money(now) or Gray("-"))
            for _, region in ipairs(row.regions) do
                region:Show()
            end
        elseif row then
            row.purchase = nil
            for _, region in ipairs(row.regions) do
                region:Hide()
            end
        end
    end
end

local function Create(page)
    frame = page
    local samples = Columns.Samples()
    col, LIST_WIDTH = Columns.Layout(LIST_WIDTH, {
        { key = "date", heading = L.HISTORY_DATE, samples = samples.date },
        { key = "item", heading = L.HISTORY_ITEM, fill = true },
        { key = "from", heading = L.PURCHASES_FROM, samples = { L.HISTORY_VENDOR, L.HISTORY_AUCTION } },
        { key = "each", heading = L.PURCHASES_EACH, samples = samples.money },
        { key = "total", heading = L.PURCHASES_TOTAL, samples = samples.total },
        { key = "market", heading = L.PURCHASES_NOW, samples = samples.money },
    })
    WIDTH = LIST_WIDTH + 2 * PADDING + SCROLLBAR_WIDTH
    pageDef.width = WIDTH

    frame.heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -32)
    frame.heading:SetText(L.TAB_PURCHASES)

    local function Heading(text, width, justify, point, x)
        local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        heading:SetJustifyH(justify)
        heading:SetWidth(width)
        heading:SetText(text)
        if point == "LEFT" then
            heading:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + x, LIST_TOP + 16)
        else
            heading:SetPoint("TOPRIGHT", frame, "TOPLEFT", PADDING + LIST_WIDTH + x, LIST_TOP + 16)
        end
        return heading
    end
    frame.headings = {
        Heading(L.HISTORY_DATE, col.date.width, "LEFT", "LEFT", col.date.left),
        Heading(L.HISTORY_ITEM, col.item.width, "LEFT", "LEFT", col.item.left),
        Heading(L.PURCHASES_FROM, col.from.width, "LEFT", "RIGHT", col.from.right),
        Heading(L.PURCHASES_EACH, col.each.width, "RIGHT", "RIGHT", col.each.right),
        Heading(L.PURCHASES_TOTAL, col.total.width, "RIGHT", "RIGHT", col.total.right),
        Heading(L.PURCHASES_NOW, col.market.width, "RIGHT", "RIGHT", col.market.right),
    }

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, LIST_TOP)
    frame.list = CreateFrame("Frame", nil, frame.scroll)
    frame.list:SetSize(LIST_WIDTH, ROW_HEIGHT)
    frame.scroll:SetScrollChild(frame.list)
    -- Scrolling refills the rows on screen.
    frame.scroll:HookScript("OnVerticalScroll", Render)

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, LIST_TOP)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetWidth(WIDTH - 2 * PADDING)
    frame.empty:SetText(L.PURCHASES_EMPTY)
end

local function Refresh()
    local count = History.PurchaseCount()
    local maxScroll = math.max(count - VISIBLE_ROWS, 0) * ROW_HEIGHT
    if (frame.scroll:GetVerticalScroll() or 0) > maxScroll then
        frame.scroll:SetVerticalScroll(maxScroll)
    end
    Render()

    local shown = math.max(math.min(count, VISIBLE_ROWS), 1)
    frame.list:SetHeight(math.max(count, 1) * ROW_HEIGHT)
    frame.scroll:SetSize(LIST_WIDTH, shown * ROW_HEIGHT)
    frame.scroll:SetShown(count > 0)
    frame.empty:SetShown(count == 0)
    for _, heading in ipairs(frame.headings) do
        heading:SetShown(count > 0)
    end

    local listHeight = count > 0 and shown * ROW_HEIGHT or (frame.empty:GetStringHeight() or 24)
    return -LIST_TOP + listHeight + PADDING
end

function PurchasePanel.Refresh()
    if Panel.IsShown() and Panel.ActiveTab() == "purchases" then
        Panel.Refresh()
    end
end

-- The shown purchases as "date | item | from | each | total | now". For tests.
function PurchasePanel.Lines()
    local lines = {}
    for _, row in ipairs(rows) do
        if row.purchase then
            lines[#lines + 1] = table.concat({ row.date:GetText(), row.item:GetText(), row.from:GetText(),
                row.each:GetText(), row.total:GetText(), row.market:GetText() }, " | ")
        end
    end
    return lines
end

function PurchasePanel.Row(index)
    return rows[index]
end

function PurchasePanel.Frame()
    return frame
end

pageDef = {
    name = "purchases",
    icon = "Interface\\Icons\\INV_Misc_Note_01",
    label = L.TAB_PURCHASES,
    width = WIDTH,
    create = Create,
    refresh = function() return Refresh() end,
}
Panel.AddPage(pageDef)

History.OnChange(PurchasePanel.Refresh)
