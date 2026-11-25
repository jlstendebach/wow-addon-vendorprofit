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
-- other ranges come from the list (the last History.MAX_SALES sales, in
-- full) and, for days, from older sales added up per item per day.
--
-- The Sales list can hold thousands of sales, so it only ever builds the
-- rows that fit on screen and refills them as it scrolls, and what it shows
-- (the sales in range matching the search) is worked out once per change,
-- not on every scroll.

local _, ns = ...
local VendorProfit = ns.VendorProfit
local History = VendorProfit.History
local Panel = VendorProfit.Panel
local Columns = VendorProfit.Columns
local L = VendorProfit.L

local HistoryPanel = {}
VendorProfit.HistoryPanel = HistoryPanel

-- Wider if the columns need it (Columns.lua).
local WIDTH = 540
local PADDING = 16
-- Rows as tall as Best Crafts', as every table's (Columns.lua).
local ROW_HEIGHT = VendorProfit.Columns.ROW_HEIGHT
-- Title at -32 (12 tall), the total at -50 (10 tall), the view buttons and
-- search 6 below that (20 tall), then the column headings 6 below those and
-- 16 above the list: the same gaps as Best Crafts.
local TOTAL_TOP = -50
local CONTROLS_TOP = -66
local LIST_TOP = -108
local VISIBLE_ROWS = 15
-- The list is in a scroll box (ScrollBox.lua): its padding and bar beside
-- the list, its padding above and below.
local BOX_EXTRA = VendorProfit.ScrollBox.EXTRA_WIDTH
local BOX_PADDING = VendorProfit.ScrollBox.PADDING
local BASE_LIST_WIDTH = WIDTH - 2 * PADDING - BOX_EXTRA
local LIST_WIDTH = BASE_LIST_WIDTH
-- The columns, by key (Columns.lua), laid out for what the view lists on
-- each refresh. Sales: Date, Item, Cost, Sold for, Profit. Best Sellers:
-- Item, Sold, Avg profit, Profit (total), Avg ROI, ROI (overall). Each
-- layout's key changes only when the layout does.
local sales, sellers
local salesLayoutKey, sellersLayoutKey
-- This tab's entry in the window (Panel.AddPage), for the width.
local pageDef
local WEEK = 7 * 24 * 60 * 60

-- Best Sellers' sort: by total profit, highest first, unless changed (saved
-- per character). Item sorts A to Z first.
local SORT_DEFAULT = { key = "profit", ascending = false }
local SORT_STARTS_ASCENDING = { name = true }
-- Sales' sort: newest first, unless changed (saved per character). Item
-- sorts A to Z first; dates and money the newest or most first.
local SALES_SORT_DEFAULT = { key = "date", ascending = false }
local SALES_STARTS_ASCENDING = { item = true }

-- Ranges, in the menu's order: All time, then the last so many days, then
-- the last so many sales. Saved per character.
local DAY = History.DAY
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
local rows = {}          -- Sales rows: only as many as fit, refilled as it scrolls
local sellerRows = {}    -- Best Sellers rows
local salesData = {}     -- the sales the list shows, newest first
local salesKey           -- what salesData was worked out for
local salesExtents = {}  -- salesData's lowest and highest money, per column
local RenderSales        -- fills the Sales rows on screen (below)

local function Gray(text)
    return GRAY_FONT_COLOR:WrapTextInColorCode(text)
end

-- Item names, once the game has them, and in lower case for the search:
-- looked up once per item, not once per sale.
local names, lowerNames = {}, {}
local namesVersion = 0
-- Names arrived: what the list shows may change (search matches, sorting).
local function NamesLoaded()
    namesVersion = namesVersion + 1
    HistoryPanel.Refresh()
end
local function ItemName(itemID)
    local name = names[itemID]
    if name then
        return name
    end
    name = C_Item.GetItemInfo(itemID)
    if name == nil then
        VendorProfit.RedrawWhenLoaded(itemID, NamesLoaded)
        return "item " .. itemID
    end
    names[itemID] = name
    lowerNames[itemID] = name:lower()
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
    if filter == "" then
        return true
    end
    local lower = lowerNames[itemID] or ItemName(itemID):lower()
    return lower:find(filter, 1, true) ~= nil
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

-- Calls fn(sale) for each sale on the list in the range, newest first.
local function EachSaleInRange(fn)
    local range = Range()
    local count = History.SaleCount()
    local limit = range.sales and math.min(range.sales, count) or count
    local since = range.days and (time() - range.days * DAY)
    for index = 1, limit do
        local sale = History.Sale(index)
        -- The list is oldest to newest, so the rest are older still.
        if since and sale.time < since then
            break
        end
        fn(sale)
    end
end

local function SalesSort()
    local db = VendorProfitCharDB
    if db and type(db.historySalesSort) == "table" and db.historySalesSort.key then
        return db.historySalesSort
    end
    return SALES_SORT_DEFAULT
end

function HistoryPanel.SalesSort()
    return SalesSort()
end

local function SetSalesSort(key)
    VendorProfitCharDB = VendorProfitCharDB or {}
    VendorProfitCharDB.historySalesSort = Columns.NextSort(SalesSort(), key, SALES_STARTS_ASCENDING)
    HistoryPanel.Refresh()
end

local SALE_VALUES = {
    date = function(sale) return sale.time end,
    item = function(sale) return lowerNames[sale.item] or ItemName(sale.item):lower() end,
    cost = function(sale) return sale.cost end,
    sold = function(sale) return sale.sold end,
    profit = function(sale) return sale.sold - sale.cost end,
}

-- The sales the Sales list shows: in range and matching the search, in the
-- chosen order (newest first to start). Worked out again only when the
-- history, search, range, sort or a loaded name changes (and, for day
-- ranges, each minute as days roll over).
local function SalesData()
    local range, sort = Range(), SalesSort()
    local key = table.concat({ History.Version(), History.SaleCount(), filter, range.key, namesVersion,
        range.days and math.floor(time() / 60) or 0, sort.key, tostring(sort.ascending) }, "/")
    if key ~= salesKey then
        salesKey = key
        local data, extents = {}, {}
        EachSaleInRange(function(sale)
            if Matches(sale.item) then
                data[#data + 1] = sale
                Columns.Track(extents, "cost", sale.cost)
                Columns.Track(extents, "sold", sale.sold)
                Columns.Track(extents, "profit", sale.sold - sale.cost)
            end
        end)
        -- Newest first already; any other order sorted (ties newest first).
        if not (sort.key == "date" and not sort.ascending) then
            local value = SALE_VALUES[sort.key] or SALE_VALUES.date
            local values = {}
            for _, sale in ipairs(data) do
                values[sale] = value(sale)
            end
            table.sort(data, function(a, b)
                local x, y = values[a], values[b]
                if x ~= y then
                    if sort.ascending then
                        return x < y
                    end
                    return x > y
                end
                return a.time > b.time
            end)
        end
        salesData, salesExtents = data, extents
    end
    return salesData
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
-- average (profit per unit), roi (profit / cost: the overall return),
-- averageRoi (each unit's own return on its cost, averaged), vendor, auction
-- (units each way), last (time) }. roi and averageRoi are nil when nothing
-- was spent.
-- All time: every sale ever, from the totals. Other ranges: the list's,
-- plus for days, older sales added up by day (whose time is their day).
function HistoryPanel.BestSellers()
    local byItem, list = {}, {}
    local range = Range()
    if range.key == "all" then
        for itemID, totals in pairs(History.ItemTotals()) do
            local item = { item = itemID }
            for key, value in pairs(totals) do
                item[key] = value
            end
            list[#list + 1] = item
        end
    end
    local function Add(itemID, n, sales, cost, sold, vendor, auction, when, roiSum, roiUnits)
        local item = byItem[itemID]
        if item == nil then
            item = { item = itemID, n = 0, sales = 0, cost = 0, sold = 0, vendor = 0, auction = 0, last = when,
                roiSum = 0, roiUnits = 0 }
            byItem[itemID] = item
            list[#list + 1] = item
        end
        item.roiSum = item.roiSum + (roiSum or 0)
        item.roiUnits = item.roiUnits + (roiUnits or 0)
        item.n = item.n + n
        item.sales = item.sales + sales
        item.cost = item.cost + cost
        item.sold = item.sold + sold
        item.vendor = item.vendor + vendor
        item.auction = item.auction + auction
        item.last = math.max(item.last, when)
    end
    if range.key ~= "all" then
        EachSaleInRange(function(sale)
            local vendor = sale.how == "vendor" and sale.n or 0
            local roiSum, roiUnits = History.SaleROI(sale)
            Add(sale.item, sale.n, 1, sale.cost, sale.sold, vendor, sale.n - vendor, sale.time, roiSum, roiUnits)
        end)
        if range.days then
            History.EachDaily(time() - range.days * DAY, function(itemID, t, dayStart)
                Add(itemID, t.n, t.sales, t.cost, t.sold, t.vendor, t.auction, dayStart, t.roiSum, t.roiUnits)
            end)
        end
    end
    for _, item in ipairs(list) do
        HistoryPanel.Finish(item)
    end
    return list
end

-- Works out an item's profit, averages and ROIs from its sums.
function HistoryPanel.Finish(item)
    item.profit = item.sold - item.cost
    item.average = item.n > 0 and item.profit / item.n or 0
    item.roi = item.cost > 0 and item.profit / item.cost or nil
    local units = item.roiUnits or 0
    item.averageRoi = units > 0 and (item.roiSum or 0) / units or nil
    return item
end

-- An item's sales over all time, as Best Sellers shows them (whatever its
-- range), or nil if it hasn't sold.
function HistoryPanel.AllTime(itemID)
    local totals = History.ItemTotals()[itemID]
    if totals == nil then
        return nil
    end
    local item = { item = itemID }
    for key, value in pairs(totals) do
        item[key] = value
    end
    return HistoryPanel.Finish(item)
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
    VendorProfitCharDB = VendorProfitCharDB or {}
    VendorProfitCharDB.bestSellersSort = Columns.NextSort(Sort(), key, SORT_STARTS_ASCENDING)
    HistoryPanel.Refresh()
end

local function SortValue(item, key)
    if key == "name" then
        return ItemName(item.item):lower()
    elseif key == "n" then
        return item.n
    elseif key == "average" then
        return item.average
    elseif key == "averageRoi" then
        return item.averageRoi or -math.huge
    elseif key == "roi" then
        return item.roi or -math.huge
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

-- "3000 sold in 15 sales", or "in 1 sale".
function HistoryPanel.SoldCount(n, sales)
    return string.format(sales == 1 and L.HISTORY_SOLD_COUNT_ONE or L.HISTORY_SOLD_COUNT, n, sales)
end

-- An item's sales lines for a tooltip (from BestSellers or AllTime): how
-- many, then with withProfit its profit and ROIs (Best Sellers has those in
-- its columns), what one cost and sold for on average, which way they sold,
-- and when it last sold.
function HistoryPanel.AddSalesLines(item, withProfit)
    GameTooltip:AddLine(HistoryPanel.SoldCount(item.n, item.sales), 1, 1, 1)
    if withProfit then
        GameTooltip:AddDoubleLine(L.HISTORY_AVERAGE, Money(item.average))
        GameTooltip:AddDoubleLine(L.BEST_PROFIT, Money(item.profit))
        GameTooltip:AddDoubleLine(L.HISTORY_AVERAGE_ROI, VendorProfit.FormatROI(item.averageRoi), nil, nil, nil, 1, 1, 1)
        GameTooltip:AddDoubleLine(L.BEST_ROI, VendorProfit.FormatROI(item.roi), nil, nil, nil, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine(L.HISTORY_AVERAGE_COST, Money(item.cost / item.n))
    GameTooltip:AddDoubleLine(L.HISTORY_AVERAGE_SOLD, Money(item.sold / item.n))
    GameTooltip:AddDoubleLine(L.HISTORY_TO_VENDORS, tostring(item.vendor), nil, nil, nil, 1, 1, 1)
    GameTooltip:AddDoubleLine(L.HISTORY_AT_AUCTION, tostring(item.auction), nil, nil, nil, 1, 1, 1)
    GameTooltip:AddLine(string.format(L.HISTORY_LAST_SOLD, date(L.HISTORY_TIME_FORMAT, item.last)), 1, 1, 1)
end

local function ShowSellerTooltip(row)
    local item = row.seller
    if item == nil then
        return
    end
    VendorProfit.SetRowTooltipOwner(row.hit, { row.item, row.n, row.average, row.profit, row.averageRoi, row.roi })
    GameTooltip:SetText(ItemLabel(item.item))
    HistoryPanel.AddSalesLines(item, false)
    GameTooltip:Show()
end

-- Rows ----------------------------------------------------------------------------

-- The text's place in a row, from the row's top: as on Best Crafts.
local TEXT_OFFSET = -4

local function HitArea(row, list, top, onEnter)
    -- The whole row hovers, for the details, lit while the mouse is on it.
    row.highlight = Columns.Highlight(list)
    row.hit = CreateFrame("Frame", nil, list)
    row.hit:SetPoint("TOPLEFT", list, "TOPLEFT", 0, top)
    row.hit:SetSize(LIST_WIDTH, ROW_HEIGHT)
    row.hit:EnableMouse(true)
    row.hit:SetScript("OnEnter", function()
        row.highlight:Show()
        onEnter(row)
    end)
    row.hit:SetScript("OnLeave", function()
        row.highlight:Hide()
        GameTooltip:Hide()
    end)
end

local function PlaceHit(row, list, top)
    row.hit:ClearAllPoints()
    row.hit:SetPoint("TOPLEFT", list, "TOPLEFT", 0, top)
    row.hit:SetSize(LIST_WIDTH, ROW_HEIGHT)
    row.highlight:ClearAllPoints()
    row.highlight:SetPoint("TOPLEFT", list, "TOPLEFT", 0, top)
    row.highlight:SetSize(LIST_WIDTH, ROW_HEIGHT)
end

-- Puts a Sales row at a place in the list (1 = top of the whole list).
local function PlaceRow(row, index)
    if row.index == index and row.layoutKey == salesLayoutKey then
        return
    end
    row.index, row.layoutKey = index, salesLayoutKey
    local list = frame.list
    local top = -(index - 1) * ROW_HEIGHT
    local function At(region, key)
        local column = sales[key]
        region:SetWidth(column.width)
        region:ClearAllPoints()
        if key == "date" or key == "item" then
            region:SetPoint("TOPLEFT", list, "TOPLEFT", column.left, top + TEXT_OFFSET)
        else
            region:SetPoint("TOPRIGHT", list, "TOPRIGHT", column.right, top + TEXT_OFFSET)
        end
    end
    for _, key in ipairs({ "date", "item", "cost", "sold", "profit" }) do
        At(row[key], key)
    end
    PlaceHit(row, list, top)
end

-- The slot-th of the Sales rows that fit on screen.
local function GetRow(slot)
    local row = rows[slot]
    if row == nil then
        local list = frame.list
        row = {}
        row.date = Column(list, 0, "LEFT")
        row.item = Column(list, 0, "LEFT")
        row.cost = Column(list, 0, "RIGHT")
        row.sold = Column(list, 0, "RIGHT")
        row.profit = Column(list, 0, "RIGHT")
        HitArea(row, list, 0, ShowSaleTooltip)
        row.regions = { row.date, row.item, row.cost, row.sold, row.profit, row.hit }
        row.highlight:Hide()
        rows[slot] = row
    end
    return row
end

local function GetSellerRow(index)
    local row = sellerRows[index]
    if row == nil then
        local list = frame.list
        local top = -(index - 1) * ROW_HEIGHT
        row = {}
        row.item = Column(list, 0, "LEFT")
        for _, key in ipairs({ "n", "average", "profit", "averageRoi", "roi" }) do
            row[key] = Column(list, 0, "RIGHT")
        end
        HitArea(row, list, top, ShowSellerTooltip)
        row.regions = { row.item, row.n, row.average, row.profit, row.averageRoi, row.roi, row.hit }
        sellerRows[index] = row
    end
    -- Placed again only when the columns change.
    if row.layoutKey ~= sellersLayoutKey then
        row.layoutKey = sellersLayoutKey
        local list, top = frame.list, -(index - 1) * ROW_HEIGHT
        row.item:SetWidth(sellers.name.width)
        row.item:ClearAllPoints()
        row.item:SetPoint("TOPLEFT", list, "TOPLEFT", sellers.name.left, top + TEXT_OFFSET)
        for _, key in ipairs({ "n", "average", "profit", "averageRoi", "roi" }) do
            row[key]:SetWidth(sellers[key].width)
            row[key]:ClearAllPoints()
            row[key]:SetPoint("TOPRIGHT", list, "TOPRIGHT", sellers[key].right, top + TEXT_OFFSET)
        end
        PlaceHit(row, list, top)
    end
    return row
end

local function ShowRegions(row, shown)
    for _, region in ipairs(row.regions) do
        region:SetShown(shown)
    end
    if not shown then
        row.highlight:Hide()
    end
end

-- Page ------------------------------------------------------------------------------

local function SetView(name)
    view = name
    HistoryPanel.Refresh()
end

-- Puts a heading over its column: the name columns from the left, the
-- numbers from the right.
local function PlaceHeading(heading, column, fromLeft)
    heading:SetWidth(column.width)
    heading:ClearAllPoints()
    if fromLeft then
        heading:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + BOX_PADDING + column.left, LIST_TOP + 16)
    else
        heading:SetPoint("TOPRIGHT", frame, "TOPLEFT", PADDING + BOX_PADDING + LIST_WIDTH + column.right,
            LIST_TOP + 16)
    end
end

-- The view's width: its list's, and the window's for this tab.
local function SetListWidth(listWidth)
    LIST_WIDTH = listWidth
    WIDTH = LIST_WIDTH + 2 * PADDING + BOX_EXTRA
    pageDef.width = WIDTH
    frame.list:SetWidth(LIST_WIDTH)
end

-- Lays the Sales columns out to fit the sales listed (Columns.lua), placing
-- the headings again when that changes the layout; the rows follow as
-- they're placed.
local function LayOutSales()
    local key, listWidth
    sales, listWidth, key = Columns.Layout(BASE_LIST_WIDTH, {
        { key = "date", heading = L.HISTORY_DATE, sorts = true, samples = Columns.Date() },
        { key = "item", heading = L.HISTORY_ITEM, sorts = true, fill = true },
        { key = "cost", heading = L.HISTORY_COST, sorts = true, samples = Columns.Money(salesExtents, "cost") },
        { key = "sold", heading = L.HISTORY_SOLD, sorts = true, samples = Columns.Money(salesExtents, "sold") },
        { key = "profit", heading = L.BEST_PROFIT, sorts = true, samples = Columns.Money(salesExtents, "profit") },
    })
    SetListWidth(listWidth)
    if key ~= salesLayoutKey then
        salesLayoutKey = key
        for _, heading in ipairs(frame.headings) do
            PlaceHeading(heading, sales[heading.key], heading.key == "date" or heading.key == "item")
        end
    end
end

-- The same for Best Sellers, for the items listed.
local function LayOutSellers(items)
    local extents = {}
    for _, item in ipairs(items) do
        for _, key in ipairs({ "n", "average", "profit", "averageRoi", "roi" }) do
            Columns.Track(extents, key, item[key])
        end
    end
    local key, listWidth
    sellers, listWidth, key = Columns.Layout(BASE_LIST_WIDTH, {
        { key = "name", heading = L.HISTORY_ITEM, sorts = true, fill = true },
        { key = "n", heading = L.HISTORY_SOLD_UNITS, sorts = true, samples = Columns.Count(extents, "n") },
        { key = "average", heading = L.HISTORY_AVERAGE, sorts = true, samples = Columns.Money(extents, "average") },
        { key = "profit", heading = L.BEST_PROFIT, sorts = true, samples = Columns.Money(extents, "profit") },
        { key = "averageRoi", heading = L.HISTORY_AVERAGE_ROI, sorts = true, samples = Columns.Percent(extents, "averageRoi") },
        { key = "roi", heading = L.BEST_ROI, sorts = true, samples = Columns.Percent(extents, "roi") },
    })
    SetListWidth(listWidth)
    if key ~= sellersLayoutKey then
        sellersLayoutKey = key
        for name, heading in pairs(frame.sellerHeadings) do
            PlaceHeading(heading, sellers[name], name == "name")
        end
    end
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

    -- Sales headings: click one to sort by it, as on Best Crafts. Placed
    -- with the columns (LayOutSales).
    local function Heading(key, text, justify)
        return Columns.Heading(frame, key, text, justify, SetSalesSort)
    end
    frame.headings = {
        Heading("date", L.HISTORY_DATE, "LEFT"),
        Heading("item", L.HISTORY_ITEM, "LEFT"),
        Heading("cost", L.HISTORY_COST, "RIGHT"),
        Heading("sold", L.HISTORY_SOLD, "RIGHT"),
        Heading("profit", L.BEST_PROFIT, "RIGHT"),
    }

    -- Best Sellers headings, the same. Placed with the columns
    -- (LayOutSellers).
    frame.sellerHeadings = {}
    local function SortHeading(key, text)
        local heading = Columns.Heading(frame, key, text, key == "name" and "LEFT" or "RIGHT", SetSort)
        frame.sellerHeadings[key] = heading
        return heading
    end
    SortHeading("name", L.HISTORY_ITEM)
    SortHeading("n", L.HISTORY_SOLD_UNITS)
    SortHeading("average", L.HISTORY_AVERAGE)
    SortHeading("profit", L.BEST_PROFIT)
    SortHeading("averageRoi", L.HISTORY_AVERAGE_ROI)
    SortHeading("roi", L.BEST_ROI)

    -- The list, in a scroll box (placed in Refresh).
    frame.scroll = VendorProfit.ScrollBox.Create(frame)
    frame.list = frame.scroll.list
    frame.list:SetSize(LIST_WIDTH, ROW_HEIGHT)
    -- Scrolling refills the rows on screen; nothing else needs redoing.
    frame.scroll:HookScript("OnVerticalScroll", function()
        if view == "sales" then
            RenderSales()
        end
    end)

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + BOX_PADDING, LIST_TOP - BOX_PADDING)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetWidth(WIDTH - 2 * PADDING - 2 * BOX_PADDING)
end

-- Fills the Sales rows that fit on screen from where the list is scrolled
-- to: a row more than fits, for the one half in view while scrolling.
function RenderSales()
    local data = salesData
    local first = math.floor((frame.scroll:GetVerticalScroll() or 0) / ROW_HEIGHT)
    local needed = math.min(VISIBLE_ROWS + 1, math.max(#data - first, 0))
    for slot = 1, math.max(needed, #rows) do
        local sale = slot <= needed and data[first + slot]
        local row = (sale or rows[slot]) and GetRow(slot)
        if sale then
            PlaceRow(row, first + slot)
            if row.sale ~= sale then
                row.sale = sale
                row.date:SetText(date(L.HISTORY_DATE_FORMAT, sale.time))
                row.item:SetText(ItemLabel(sale.item, sale.n))
                row.cost:SetText(Money(sale.cost))
                row.sold:SetText(Money(sale.sold))
                row.profit:SetText(Money(sale.sold - sale.cost))
            end
            ShowRegions(row, true)
        elseif row then
            row.sale = nil
            ShowRegions(row, false)
        end
    end
end

local function RefreshSales()
    local data = SalesData()
    LayOutSales()
    local shown = #data
    -- Data got shorter: don't leave the list scrolled past its end (before
    -- the rows are filled from where it's scrolled to).
    local maxScroll = math.max(shown - VISIBLE_ROWS, 0) * ROW_HEIGHT
    if (frame.scroll:GetVerticalScroll() or 0) > maxScroll then
        frame.scroll:SetVerticalScroll(maxScroll)
    end
    -- Names may have loaded, or the history changed: refill every row.
    for _, row in ipairs(rows) do
        row.sale = nil
    end
    RenderSales()
    for _, row in ipairs(sellerRows) do
        row.seller = nil
        ShowRegions(row, false)
    end
    return shown
end

local function RefreshSellers()
    local items = {}
    for _, item in ipairs(SortSellers(HistoryPanel.BestSellers())) do
        if Matches(item.item) then
            items[#items + 1] = item
        end
    end
    LayOutSellers(items)
    local shown = #items
    for index, item in ipairs(items) do
        local row = GetSellerRow(index)
        row.seller = item
        row.item:SetText(ItemLabel(item.item))
        row.n:SetText(tostring(item.n))
        row.average:SetText(Money(item.average))
        row.profit:SetText(Money(item.profit))
        row.averageRoi:SetText(VendorProfit.FormatROI(item.averageRoi))
        row.roi:SetText(VendorProfit.FormatROI(item.roi))
        ShowRegions(row, true)
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

    -- Back to the top for another view, search or range.
    local listKey = view .. "/" .. filter .. "/" .. Range().key
    if listKey ~= shownList then
        shownList = listKey
        frame.scroll:SetVerticalScroll(0)
    end

    local shown = view == "items" and RefreshSellers() or RefreshSales()

    -- Headings: the view's own, the sorted one in white, with an arrow for
    -- its direction.
    for _, heading in ipairs(frame.headings) do
        heading:SetShown(view == "sales" and shown > 0)
    end
    for _, heading in pairs(frame.sellerHeadings) do
        heading:SetShown(view == "items" and shown > 0)
    end
    Columns.ShowSort(frame.headings, SalesSort())
    Columns.ShowSort(frame.sellerHeadings, Sort())

    -- The list fills the page: its box always VISIBLE_ROWS tall, kept when
    -- empty (saying why, inside it).
    local boxHeight = VendorProfit.ScrollBox.Place(frame.scroll, frame, PADDING, LIST_TOP, LIST_WIDTH,
        VISIBLE_ROWS * ROW_HEIGHT, shown * ROW_HEIGHT, true)
    if count == 0 then
        frame.empty:SetText(L.HISTORY_EMPTY)
    elseif filter ~= "" then
        frame.empty:SetText(L.HISTORY_NO_MATCH)
    else
        frame.empty:SetText(L.HISTORY_NO_RANGE)
    end
    frame.empty:SetShown(shown == 0)

    return -LIST_TOP + boxHeight + PADDING
end

function HistoryPanel.Refresh()
    if Panel.IsShown() and Panel.ActiveTab() == "history" then
        Panel.Refresh()
    end
end

-- The shown rows as text, for tests: Sales as "date | item | cost | sold |
-- profit", Best Sellers as "item | sold | average | profit | average ROI | ROI".
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
                row.average:GetText(), row.profit:GetText(), row.averageRoi:GetText(), row.roi:GetText() }, " | ")
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

pageDef = {
    name = "history",
    icon = "Interface\\Icons\\INV_Scroll_03",
    label = L.TAB_HISTORY,
    width = WIDTH,
    create = Create,
    refresh = function() return Refresh() end,
}
Panel.AddPage(pageDef)

History.OnChange(HistoryPanel.Refresh)
