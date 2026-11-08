-- The Profit History tab of the Vendor Profit window: what you made selling
-- things you crafted (History.lua), in two views, picked with buttons like
-- Best Crafts' Auction and Vendor:
--
--   Sales         every recorded sale, newest first: the date, the item, what
--                 it cost, what it sold for and the profit. Hovering one splits
--                 its cost into what you bought and your own items at market
--                 value, and says how it sold.
--   Best Sellers  one row per item: how many sold, the average profit on each,
--                 and the total, most profit first. The headings sort it.
--
-- The search box filters both by item name as you type, and Range narrows
-- both to recent sales: the last so many days, or the last so many sales.
-- Every sale ever is added up per item (History.ItemTotals), so the totals at
-- the top and Best Sellers over All time cover sales the list has dropped;
-- other ranges come from the list, the last History.MAX_SALES sales.

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
-- Title at -32 (12 tall), the total at -50 (10 tall), the view buttons and
-- search 6 below that (20 tall), then the column headings 6 below those and
-- 16 above the list: the same gaps as Best Crafts.
local TOTAL_TOP = -50
local CONTROLS_TOP = -66
local LIST_TOP = -108
local VISIBLE_ROWS = 18
local SCROLLBAR_WIDTH = 24
local LIST_WIDTH = WIDTH - 2 * PADDING - SCROLLBAR_WIDTH
local MONEY_WIDTH, GAP = 70, 6
-- Sales columns: Date and Item from the left; Profit, Sold for, Cost from the
-- right.
local DATE_WIDTH = 34
local PROFIT_RIGHT = 0
local SOLD_RIGHT = PROFIT_RIGHT - MONEY_WIDTH - GAP
local COST_RIGHT = SOLD_RIGHT - MONEY_WIDTH - GAP
local ITEM_LEFT = DATE_WIDTH + GAP
local ITEM_WIDTH = LIST_WIDTH + COST_RIGHT - MONEY_WIDTH - GAP - ITEM_LEFT
-- Best Sellers columns: Item from the left; Profit (total), Avg profit, Sold
-- from the right. Sold is narrow, with room left of it for its sort arrow.
local COUNT_WIDTH, COUNT_GAP = 36, 12
local TOTAL_RIGHT = 0
local AVERAGE_RIGHT = TOTAL_RIGHT - MONEY_WIDTH - GAP
local COUNT_RIGHT = AVERAGE_RIGHT - MONEY_WIDTH - COUNT_GAP
local SELLER_WIDTH = LIST_WIDTH + COUNT_RIGHT - COUNT_WIDTH - COUNT_GAP
local WEEK = 7 * 24 * 60 * 60

-- Best Sellers' sort: by total profit, highest first, unless changed (saved
-- per character). Item sorts A to Z first.
local SORT_DEFAULT = { key = "profit", ascending = false }
local SORT_STARTS_ASCENDING = { name = true }

-- Ranges, in the menu's order: All time, then the last so many days, then
-- the last so many sales. Saved per character.
local DAY = 24 * 60 * 60
local RANGES = {
    { key = "all" },
    { key = "d7", days = 7 }, { key = "d30", days = 30 }, { key = "d90", days = 90 },
    { key = "s50", sales = 50 }, { key = "s100", sales = 100 }, { key = "s250", sales = 250 },
}
local RANGE_BY_KEY = {}
for _, range in ipairs(RANGES) do
    RANGE_BY_KEY[range.key] = range
end

local frame
local view = "sales"     -- "sales" or "items" (Best Sellers)
local filter = ""        -- the search box's text, lowercased
local shownList          -- view and filter the list was last scrolled for
local rows = {}          -- Sales rows
local sellerRows = {}    -- Best Sellers rows

local function Gray(text)
    return GRAY_FONT_COLOR:WrapTextInColorCode(text)
end

local function ItemName(itemID)
    local name = C_Item.GetItemInfo(itemID)
    if name == nil then
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function() HistoryPanel.Refresh() end)
        return "item " .. itemID
    end
    return name
end

local function ItemLabel(itemID, n)
    local icon = select(5, C_Item.GetItemInfoInstant(itemID))
    local label = (icon and ("|T" .. icon .. ":0|t ") or "") .. ItemName(itemID)
    if n and n > 1 then
        label = label .. " x" .. n
    end
    return label
end

local function Money(copper)
    return VendorProfit.FormatMoney(copper)
end

local function Matches(itemID)
    return filter == "" or ItemName(itemID):lower():find(filter, 1, true) ~= nil
end

local function Column(parent, width, justify)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH(justify)
    text:SetWordWrap(false)
    text:SetWidth(width)
    return text
end

local function SmallButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 20)
    button:SetText(text)
    return button
end

-- Range -----------------------------------------------------------------------

local function Range()
    local db = VendorProfitCharDB
    return RANGE_BY_KEY[db and db.historyRange] or RANGES[1]
end

function HistoryPanel.Range()
    return Range().key
end

function HistoryPanel.SetRange(key)
    if RANGE_BY_KEY[key] then
        VendorProfitCharDB = VendorProfitCharDB or {}
        VendorProfitCharDB.historyRange = key
        HistoryPanel.Refresh()
    end
end

local function RangeLabel(range)
    if range.days then
        return string.format(L.HISTORY_RANGE_DAYS, range.days)
    elseif range.sales then
        return string.format(L.HISTORY_RANGE_SALES, range.sales)
    end
    return L.HISTORY_RANGE_ALL
end

-- The sales in the range, newest first.
local function SalesInRange()
    local range = Range()
    local sales = History.Sales()
    if range.sales then
        local list = {}
        for index = 1, math.min(range.sales, #sales) do
            list[index] = sales[index]
        end
        return list
    elseif range.days then
        local since = time() - range.days * DAY
        local list = {}
        for _, sale in ipairs(sales) do
            if sale.time >= since then
                list[#list + 1] = sale
            end
        end
        return list
    end
    return sales
end

local function RangeMenu(_, root)
    for _, range in ipairs(RANGES) do
        root:CreateRadio(RangeLabel(range),
            function() return Range().key == range.key end,
            function() HistoryPanel.SetRange(range.key) end)
    end
end

-- The open Range menu, and when it last closed: as with Best Crafts' Filter,
-- a click on the button just after the menu closed was meant to close it.
local rangeMenu
local rangeMenuClosed = 0

local function ToggleRangeMenu(button)
    if rangeMenu and rangeMenu:IsShown() then
        rangeMenu:Hide()
        return
    end
    if GetTime() - rangeMenuClosed < 0.25 then
        return
    end
    rangeMenu = MenuUtil.CreateContextMenu(button, RangeMenu)
    if rangeMenu then
        -- Under the button, not at the mouse.
        rangeMenu:ClearAllPoints()
        rangeMenu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
        if not rangeMenu.vendorProfitHooked then
            rangeMenu.vendorProfitHooked = true
            rangeMenu:HookScript("OnHide", function() rangeMenuClosed = GetTime() end)
        end
    end
end

-- Best Sellers ----------------------------------------------------------------

-- Sales grouped by item: { item, n (units sold), sales, cost, sold, profit,
-- average (profit per unit), vendor, auction (units each way), last (time) }.
-- All time: every sale ever, from the totals; other ranges: the list's.
function HistoryPanel.BestSellers()
    local byItem, list = {}, {}
    if Range().key == "all" then
        for itemID, totals in pairs(History.ItemTotals()) do
            local item = { item = itemID }
            for key, value in pairs(totals) do
                item[key] = value
            end
            list[#list + 1] = item
        end
    end
    for _, sale in ipairs(Range().key == "all" and {} or SalesInRange()) do
        local item = byItem[sale.item]
        if item == nil then
            item = { item = sale.item, n = 0, sales = 0, cost = 0, sold = 0, vendor = 0, auction = 0, last = sale.time }
            byItem[sale.item] = item
            list[#list + 1] = item
        end
        item.n = item.n + sale.n
        item.sales = item.sales + 1
        item.cost = item.cost + sale.cost
        item.sold = item.sold + sale.sold
        if sale.how == "vendor" then
            item.vendor = item.vendor + sale.n
        else
            item.auction = item.auction + sale.n
        end
        item.last = math.max(item.last, sale.time)
    end
    for _, item in ipairs(list) do
        item.profit = item.sold - item.cost
        item.average = item.n > 0 and item.profit / item.n or 0
    end
    return list
end

local function Sort()
    local db = VendorProfitCharDB
    if db and type(db.bestSellersSort) == "table" and db.bestSellersSort.key then
        return db.bestSellersSort
    end
    return SORT_DEFAULT
end

function HistoryPanel.Sort()
    return Sort()
end

local function SetSort(key)
    local current = Sort()
    local ascending
    if current.key == key then
        ascending = not current.ascending
    else
        ascending = SORT_STARTS_ASCENDING[key] or false
    end
    VendorProfitCharDB = VendorProfitCharDB or {}
    VendorProfitCharDB.bestSellersSort = { key = key, ascending = ascending }
    HistoryPanel.Refresh()
end

local function SortValue(item, key)
    if key == "name" then
        return ItemName(item.item):lower()
    elseif key == "n" then
        return item.n
    elseif key == "average" then
        return item.average
    end
    return item.profit
end

local function SortSellers(list)
    local sort = Sort()
    table.sort(list, function(a, b)
        local x, y = SortValue(a, sort.key), SortValue(b, sort.key)
        if x ~= y then
            if sort.ascending then
                return x < y
            end
            return x > y
        end
        if a.profit ~= b.profit then
            return a.profit > b.profit
        end
        return a.item < b.item
    end)
    return list
end

-- Tooltips ----------------------------------------------------------------------

local function ShowSaleTooltip(row)
    local sale = row.sale
    if sale == nil then
        return
    end
    VendorProfit.SetRowTooltipOwner(row.hit, { row.date, row.item, row.cost, row.sold, row.profit })
    GameTooltip:SetText(ItemLabel(sale.item, sale.n))
    GameTooltip:AddLine(date(L.HISTORY_TIME_FORMAT, sale.time), 1, 1, 1)
    GameTooltip:AddDoubleLine(L.HISTORY_BOUGHT, Money(sale.bought))
    GameTooltip:AddDoubleLine(L.HISTORY_OWN, Money(sale.cost - sale.bought))
    GameTooltip:AddDoubleLine(sale.how == "vendor" and L.HISTORY_SOLD_VENDOR or L.HISTORY_SOLD_AUCTION, Money(sale.sold))
    GameTooltip:Show()
end

local function ShowSellerTooltip(row)
    local item = row.seller
    if item == nil then
        return
    end
    VendorProfit.SetRowTooltipOwner(row.hit, { row.item, row.n, row.average, row.profit })
    GameTooltip:SetText(ItemLabel(item.item))
    GameTooltip:AddLine(string.format(L.HISTORY_SOLD_COUNT, item.n, item.sales), 1, 1, 1)
    GameTooltip:AddDoubleLine(L.HISTORY_AVERAGE_COST, Money(item.cost / item.n))
    GameTooltip:AddDoubleLine(L.HISTORY_AVERAGE_SOLD, Money(item.sold / item.n))
    GameTooltip:AddDoubleLine(L.HISTORY_TO_VENDORS, tostring(item.vendor), nil, nil, nil, 1, 1, 1)
    GameTooltip:AddDoubleLine(L.HISTORY_AT_AUCTION, tostring(item.auction), nil, nil, nil, 1, 1, 1)
    GameTooltip:AddLine(string.format(L.HISTORY_LAST_SOLD, date(L.HISTORY_TIME_FORMAT, item.last)), 1, 1, 1)
    GameTooltip:Show()
end

-- Rows ----------------------------------------------------------------------------

local function HitArea(row, list, top, onEnter)
    -- The whole row hovers, for the details.
    row.hit = CreateFrame("Frame", nil, list)
    row.hit:SetPoint("TOPLEFT", list, "TOPLEFT", 0, top + 2)
    row.hit:SetSize(LIST_WIDTH, ROW_HEIGHT)
    row.hit:EnableMouse(true)
    row.hit:SetScript("OnEnter", function() onEnter(row) end)
    row.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
        row.cost = Column(list, MONEY_WIDTH, "RIGHT")
        row.cost:SetPoint("TOPRIGHT", list, "TOPRIGHT", COST_RIGHT, top)
        row.sold = Column(list, MONEY_WIDTH, "RIGHT")
        row.sold:SetPoint("TOPRIGHT", list, "TOPRIGHT", SOLD_RIGHT, top)
        row.profit = Column(list, MONEY_WIDTH, "RIGHT")
        row.profit:SetPoint("TOPRIGHT", list, "TOPRIGHT", PROFIT_RIGHT, top)
        HitArea(row, list, top, ShowSaleTooltip)
        row.regions = { row.date, row.item, row.cost, row.sold, row.profit, row.hit }
        rows[index] = row
    end
    return row
end

local function GetSellerRow(index)
    local row = sellerRows[index]
    if row == nil then
        local list = frame.list
        local top = -(index - 1) * ROW_HEIGHT - 2
        row = {}
        row.item = Column(list, SELLER_WIDTH, "LEFT")
        row.item:SetPoint("TOPLEFT", list, "TOPLEFT", 0, top)
        row.n = Column(list, COUNT_WIDTH, "RIGHT")
        row.n:SetPoint("TOPRIGHT", list, "TOPRIGHT", COUNT_RIGHT, top)
        row.average = Column(list, MONEY_WIDTH, "RIGHT")
        row.average:SetPoint("TOPRIGHT", list, "TOPRIGHT", AVERAGE_RIGHT, top)
        row.profit = Column(list, MONEY_WIDTH, "RIGHT")
        row.profit:SetPoint("TOPRIGHT", list, "TOPRIGHT", TOTAL_RIGHT, top)
        HitArea(row, list, top, ShowSellerTooltip)
        row.regions = { row.item, row.n, row.average, row.profit, row.hit }
        sellerRows[index] = row
    end
    return row
end

local function ShowRegions(row, shown)
    for _, region in ipairs(row.regions) do
        region:SetShown(shown)
    end
end

-- Page ------------------------------------------------------------------------------

local function SetView(name)
    view = name
    HistoryPanel.Refresh()
end

local function Create(page)
    frame = page

    frame.heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -32)
    frame.heading:SetText(L.TAB_HISTORY)

    frame.total = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.total:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, TOTAL_TOP)
    frame.total:SetJustifyH("LEFT")
    frame.total:SetWidth(WIDTH - 2 * PADDING)

    -- The views, as Best Crafts' Auction and Vendor buttons.
    frame.views = {
        sales = SmallButton(frame, L.HISTORY_VIEW_SALES, 76),
        items = SmallButton(frame, L.HISTORY_VIEW_ITEMS, 96),
    }
    frame.views.sales:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, CONTROLS_TOP)
    frame.views.items:SetPoint("LEFT", frame.views.sales, "RIGHT", 4, 0)
    frame.views.sales:SetScript("OnClick", function() SetView("sales") end)
    frame.views.items:SetScript("OnClick", function() SetView("items") end)

    -- Search: filters by item name as you type, as on Best Crafts.
    local ok, search = pcall(CreateFrame, "EditBox", nil, frame, "SearchBoxTemplate")
    if not ok then
        search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    end
    search:SetHeight(20)
    search:SetPoint("LEFT", frame.views.items, "RIGHT", 14, 0)
    -- Range: a button at the row's end, styled and opening like Best
    -- Crafts' Filter. Left out if this client doesn't have the game's menu
    -- system; the search box then runs to the end of the row.
    if MenuUtil and MenuUtil.CreateContextMenu then
        frame.range = SmallButton(frame, "", 110)
        frame.range:SetPoint("RIGHT", frame, "TOPRIGHT", -PADDING, CONTROLS_TOP - 10)
        frame.range:SetScript("OnClick", function(self) ToggleRangeMenu(self) end)
        frame.range:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(string.format(L.HISTORY_RANGE_HELP, History.MAX_SALES), 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        frame.range:SetScript("OnLeave", function() GameTooltip:Hide() end)
        search:SetPoint("RIGHT", frame.range, "LEFT", -8, 0)
    else
        search:SetPoint("RIGHT", frame, "TOPRIGHT", -PADDING, CONTROLS_TOP - 10)
    end
    search:SetAutoFocus(false)
    -- Hooked, not set, so the template's own placeholder and clear button
    -- keep working.
    search:HookScript("OnTextChanged", function(self)
        local text = (self:GetText() or ""):lower()
        if text ~= filter then
            filter = text
            HistoryPanel.Refresh()
        end
    end)
    search:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.search = search

    -- Sales headings.
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
        Heading(L.HISTORY_COST, MONEY_WIDTH, "RIGHT", "RIGHT", COST_RIGHT),
        Heading(L.HISTORY_SOLD, MONEY_WIDTH, "RIGHT", "RIGHT", SOLD_RIGHT),
        Heading(L.BEST_PROFIT, MONEY_WIDTH, "RIGHT", "RIGHT", PROFIT_RIGHT),
    }

    -- Best Sellers headings: click one to sort by it, as on Best Crafts.
    frame.sellerHeadings = {}
    local function SortHeading(key, text, width, right)
        local heading = CreateFrame("Button", nil, frame)
        heading:SetSize(width, 14)
        if right then
            heading:SetPoint("TOPRIGHT", frame, "TOPLEFT", PADDING + LIST_WIDTH + right, LIST_TOP + 16)
        else
            heading:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, LIST_TOP + 16)
        end
        heading.text = heading:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        heading.text:SetAllPoints(heading)
        heading.text:SetJustifyH(right and "RIGHT" or "LEFT")
        heading.label = text
        heading:SetScript("OnClick", function() SetSort(key) end)
        heading:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L.BEST_SORT_HELP, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        heading:SetScript("OnLeave", function() GameTooltip:Hide() end)
        frame.sellerHeadings[key] = heading
        return heading
    end
    SortHeading("name", L.HISTORY_ITEM, SELLER_WIDTH)
    -- Wider than its column, into the gap, to fit the sort arrow.
    SortHeading("n", L.HISTORY_SOLD_UNITS, COUNT_WIDTH + COUNT_GAP, COUNT_RIGHT)
    SortHeading("average", L.HISTORY_AVERAGE, MONEY_WIDTH, AVERAGE_RIGHT)
    SortHeading("profit", L.BEST_PROFIT, MONEY_WIDTH, TOTAL_RIGHT)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, LIST_TOP)
    frame.list = CreateFrame("Frame", nil, frame.scroll)
    frame.list:SetSize(LIST_WIDTH, ROW_HEIGHT)
    frame.scroll:SetScrollChild(frame.list)

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, LIST_TOP)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetWidth(WIDTH - 2 * PADDING)
end

local function RefreshSales()
    local shown = 0
    for _, sale in ipairs(SalesInRange()) do
        if Matches(sale.item) then
            shown = shown + 1
            local row = GetRow(shown)
            row.sale = sale
            row.date:SetText(date(L.HISTORY_DATE_FORMAT, sale.time))
            row.item:SetText(ItemLabel(sale.item, sale.n))
            row.cost:SetText(Money(sale.cost))
            row.sold:SetText(Money(sale.sold))
            row.profit:SetText(Money(sale.sold - sale.cost))
            ShowRegions(row, true)
        end
    end
    for index = shown + 1, #rows do
        rows[index].sale = nil
        ShowRegions(rows[index], false)
    end
    for _, row in ipairs(sellerRows) do
        row.seller = nil
        ShowRegions(row, false)
    end
    return shown
end

local function RefreshSellers()
    local shown = 0
    for _, item in ipairs(SortSellers(HistoryPanel.BestSellers())) do
        if Matches(item.item) then
            shown = shown + 1
            local row = GetSellerRow(shown)
            row.seller = item
            row.item:SetText(ItemLabel(item.item))
            row.n:SetText(tostring(item.n))
            row.average:SetText(Money(item.average))
            row.profit:SetText(Money(item.profit))
            ShowRegions(row, true)
        end
    end
    for index = shown + 1, #sellerRows do
        sellerRows[index].seller = nil
        ShowRegions(sellerRows[index], false)
    end
    for _, row in ipairs(rows) do
        row.sale = nil
        ShowRegions(row, false)
    end
    return shown
end

local function Refresh()
    local profit, count = History.Total()
    local weekProfit = History.Total(time() - WEEK)
    frame.total:SetText(string.format(L.HISTORY_TOTAL, Money(profit), count, Money(weekProfit)))

    if frame.range then
        frame.range:SetText(RangeLabel(Range()))
    end

    -- The selected view stays lit.
    for key, button in pairs(frame.views) do
        if key == view then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end

    local shown = view == "items" and RefreshSellers() or RefreshSales()

    -- Headings: the view's own; Best Sellers' sorted one in white, with an
    -- arrow for its direction.
    for _, heading in ipairs(frame.headings) do
        heading:SetShown(view == "sales" and shown > 0)
    end
    local sort = Sort()
    for key, heading in pairs(frame.sellerHeadings) do
        heading:SetShown(view == "items" and shown > 0)
        if key == sort.key then
            local arrow = sort.ascending and L.BEST_SORT_UP or L.BEST_SORT_DOWN
            heading.text:SetText(HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(heading.label .. " " .. arrow))
        else
            heading.text:SetText(heading.label)
        end
    end

    local visible = math.max(math.min(shown, VISIBLE_ROWS), 1)
    frame.list:SetHeight(math.max(shown, 1) * ROW_HEIGHT)
    frame.scroll:SetSize(LIST_WIDTH, visible * ROW_HEIGHT)
    frame.scroll:SetShown(shown > 0)
    -- Back to the top for another view or search.
    local listKey = view .. "/" .. filter .. "/" .. Range().key
    if listKey ~= shownList then
        shownList = listKey
        frame.scroll:SetVerticalScroll(0)
    end
    if count == 0 then
        frame.empty:SetText(L.HISTORY_EMPTY)
    elseif filter ~= "" then
        frame.empty:SetText(L.HISTORY_NO_MATCH)
    else
        frame.empty:SetText(L.HISTORY_NO_RANGE)
    end
    frame.empty:SetShown(shown == 0)

    local listHeight = shown > 0 and visible * ROW_HEIGHT or (frame.empty:GetStringHeight() or 24)
    return -LIST_TOP + listHeight + PADDING
end

function HistoryPanel.Refresh()
    if Panel.IsShown() and Panel.ActiveTab() == "history" then
        Panel.Refresh()
    end
end

-- The shown rows as text, for tests: Sales as "date | item | cost | sold |
-- profit", Best Sellers as "item | sold | average | profit".
function HistoryPanel.Lines()
    local lines = {}
    for _, row in ipairs(rows) do
        if row.sale then
            lines[#lines + 1] = table.concat({ row.date:GetText(), row.item:GetText(),
                row.cost:GetText(), row.sold:GetText(), row.profit:GetText() }, " | ")
        end
    end
    for _, row in ipairs(sellerRows) do
        if row.seller then
            lines[#lines + 1] = table.concat({ row.item:GetText(), row.n:GetText(),
                row.average:GetText(), row.profit:GetText() }, " | ")
        end
    end
    return lines
end

function HistoryPanel.Row(index)
    return rows[index]
end

function HistoryPanel.SellerRow(index)
    return sellerRows[index]
end

function HistoryPanel.View()
    return view
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
