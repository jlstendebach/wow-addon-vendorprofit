-- The Profit History tab of the Vendor Profit window: every recorded sale of
-- something you crafted (History.lua), newest first, with what it cost, what
-- it sold for, the profit and how it sold. Hovering a sale splits its cost
-- into what you bought and your own items at market value.

local _, ns = ...
local VendorProfit = ns.VendorProfit
local History = VendorProfit.History
local Panel = VendorProfit.Panel
local L = VendorProfit.L

local HistoryPanel = {}
VendorProfit.HistoryPanel = HistoryPanel

local WIDTH = 540
local PADDING = 16
local ROW_HEIGHT = 18
local LIST_TOP = -76
local VISIBLE_ROWS = 18
local SCROLLBAR_WIDTH = 24
local LIST_WIDTH = WIDTH - 2 * PADDING - SCROLLBAR_WIDTH
-- Columns: Date and Item from the left; Profit, Sold for, Cost, How from
-- the right.
local DATE_WIDTH, HOW_WIDTH, MONEY_WIDTH, GAP = 46, 52, 70, 6
local PROFIT_RIGHT = 0
local SOLD_RIGHT = PROFIT_RIGHT - MONEY_WIDTH - GAP
local COST_RIGHT = SOLD_RIGHT - MONEY_WIDTH - GAP
local HOW_RIGHT = COST_RIGHT - MONEY_WIDTH - GAP
local ITEM_LEFT = DATE_WIDTH + GAP
local ITEM_WIDTH = LIST_WIDTH + HOW_RIGHT - HOW_WIDTH - GAP - ITEM_LEFT
local WEEK = 7 * 24 * 60 * 60

local frame
local rows = {}

local function Gray(text)
    return GRAY_FONT_COLOR:WrapTextInColorCode(text)
end

local function ItemLabel(itemID, n)
    local name = C_Item.GetItemInfo(itemID)
    if name == nil then
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function() HistoryPanel.Refresh() end)
        name = "item " .. itemID
    end
    local icon = select(5, C_Item.GetItemInfoInstant(itemID))
    local label = (icon and ("|T" .. icon .. ":0|t ") or "") .. name
    if n > 1 then
        label = label .. " x" .. n
    end
    return label
end

local function Money(copper)
    return VendorProfit.FormatMoney(copper)
end

local function Column(parent, width, justify)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH(justify)
    text:SetWordWrap(false)
    text:SetWidth(width)
    return text
end

local function ShowTooltip(row)
    local sale = row.sale
    if sale == nil then
        return
    end
    VendorProfit.SetRowTooltipOwner(row.hit, { row.date, row.item, row.how, row.cost, row.sold, row.profit })
    GameTooltip:SetText(ItemLabel(sale.item, sale.n))
    GameTooltip:AddLine(date(L.HISTORY_TIME_FORMAT, sale.time), 1, 1, 1)
    GameTooltip:AddDoubleLine(L.HISTORY_BOUGHT, Money(sale.bought))
    GameTooltip:AddDoubleLine(L.HISTORY_OWN, Money(sale.cost - sale.bought))
    GameTooltip:AddDoubleLine(sale.how == "vendor" and L.HISTORY_SOLD_VENDOR or L.HISTORY_SOLD_AUCTION, Money(sale.sold))
    GameTooltip:Show()
end

local function GetRow(index)
    local row = rows[index]
    if row == nil then
        local list = frame.list
        local top = -(index - 1) * ROW_HEIGHT - 2
        row = {}
        row.date = Column(list, DATE_WIDTH, "LEFT")
        row.date:SetPoint("TOPLEFT", list, "TOPLEFT", 0, top)
        row.item = Column(list, ITEM_WIDTH, "LEFT")
        row.item:SetPoint("TOPLEFT", list, "TOPLEFT", ITEM_LEFT, top)
        row.how = Column(list, HOW_WIDTH, "LEFT")
        row.how:SetPoint("TOPRIGHT", list, "TOPRIGHT", HOW_RIGHT, top)
        row.cost = Column(list, MONEY_WIDTH, "RIGHT")
        row.cost:SetPoint("TOPRIGHT", list, "TOPRIGHT", COST_RIGHT, top)
        row.sold = Column(list, MONEY_WIDTH, "RIGHT")
        row.sold:SetPoint("TOPRIGHT", list, "TOPRIGHT", SOLD_RIGHT, top)
        row.profit = Column(list, MONEY_WIDTH, "RIGHT")
        row.profit:SetPoint("TOPRIGHT", list, "TOPRIGHT", PROFIT_RIGHT, top)
        -- The whole row hovers, for the cost breakdown.
        row.hit = CreateFrame("Frame", nil, list)
        row.hit:SetPoint("TOPLEFT", list, "TOPLEFT", 0, top + 2)
        row.hit:SetSize(LIST_WIDTH, ROW_HEIGHT)
        row.hit:EnableMouse(true)
        row.hit:SetScript("OnEnter", function() ShowTooltip(row) end)
        row.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[index] = row
    end
    return row
end

local function Create(page)
    frame = page

    frame.heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -32)
    frame.heading:SetText(L.TAB_HISTORY)

    frame.total = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.total:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -50)
    frame.total:SetJustifyH("LEFT")
    frame.total:SetWidth(WIDTH - 2 * PADDING)

    -- Column headings.
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
        Heading(L.HISTORY_DATE, DATE_WIDTH, "LEFT", "LEFT", 0),
        Heading(L.HISTORY_ITEM, ITEM_WIDTH, "LEFT", "LEFT", ITEM_LEFT),
        Heading(L.HISTORY_HOW, HOW_WIDTH, "LEFT", "RIGHT", HOW_RIGHT),
        Heading(L.HISTORY_COST, MONEY_WIDTH, "RIGHT", "RIGHT", COST_RIGHT),
        Heading(L.HISTORY_SOLD, MONEY_WIDTH, "RIGHT", "RIGHT", SOLD_RIGHT),
        Heading(L.BEST_PROFIT, MONEY_WIDTH, "RIGHT", "RIGHT", PROFIT_RIGHT),
    }

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, LIST_TOP)
    frame.list = CreateFrame("Frame", nil, frame.scroll)
    frame.list:SetSize(LIST_WIDTH, ROW_HEIGHT)
    frame.scroll:SetScrollChild(frame.list)

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, LIST_TOP)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetWidth(WIDTH - 2 * PADDING)
    frame.empty:SetText(L.HISTORY_EMPTY)
end

local function Refresh()
    local sales = History.Sales()
    local profit, count = History.Total()
    local weekProfit = History.Total(time() - WEEK)
    frame.total:SetText(string.format(L.HISTORY_TOTAL, Money(profit), count, Money(weekProfit)))

    for index, sale in ipairs(sales) do
        local row = GetRow(index)
        row.sale = sale
        row.date:SetText(date(L.HISTORY_DATE_FORMAT, sale.time))
        row.item:SetText(ItemLabel(sale.item, sale.n))
        row.how:SetText(sale.how == "vendor" and L.HISTORY_VENDOR or L.HISTORY_AUCTION)
        row.cost:SetText(Money(sale.cost))
        row.sold:SetText(Money(sale.sold))
        row.profit:SetText(Money(sale.sold - sale.cost))
        for _, region in ipairs({ row.date, row.item, row.how, row.cost, row.sold, row.profit, row.hit }) do
            region:Show()
        end
    end
    for index = #sales + 1, #rows do
        local row = rows[index]
        row.sale = nil
        for _, region in ipairs({ row.date, row.item, row.how, row.cost, row.sold, row.profit, row.hit }) do
            region:Hide()
        end
    end

    local shown = math.max(math.min(#sales, VISIBLE_ROWS), 1)
    frame.list:SetHeight(math.max(#sales, 1) * ROW_HEIGHT)
    frame.scroll:SetSize(LIST_WIDTH, shown * ROW_HEIGHT)
    frame.scroll:SetShown(#sales > 0)
    frame.empty:SetShown(#sales == 0)
    for _, heading in ipairs(frame.headings) do
        heading:SetShown(#sales > 0)
    end

    local listHeight = #sales > 0 and shown * ROW_HEIGHT or (frame.empty:GetStringHeight() or 24)
    return -LIST_TOP + listHeight + PADDING
end

function HistoryPanel.Refresh()
    if Panel.IsShown() and Panel.ActiveTab() == "history" then
        Panel.Refresh()
    end
end

-- The shown sales as "date | item | how | cost | sold | profit". For tests.
function HistoryPanel.Lines()
    local lines = {}
    for _, row in ipairs(rows) do
        if row.sale then
            lines[#lines + 1] = table.concat({ row.date:GetText(), row.item:GetText(), row.how:GetText(),
                row.cost:GetText(), row.sold:GetText(), row.profit:GetText() }, " | ")
        end
    end
    return lines
end

function HistoryPanel.Row(index)
    return rows[index]
end

function HistoryPanel.Frame()
    return frame
end

Panel.AddPage({
    name = "history",
    icon = "Interface\\Icons\\INV_Scroll_03",
    label = L.TAB_HISTORY,
    width = WIDTH,
    create = Create,
    refresh = function() return Refresh() end,
})

History.OnChange(HistoryPanel.Refresh)
