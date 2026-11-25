-- The Purchase History tab of the Vendor Profit window: your recent
-- purchases (History.lua), newest first (or sorted by a column), with what
-- you paid for each one, for a gut check against today's price. Auction house purchases show up
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

-- Wider if the columns need it (Columns.lua).
local WIDTH = 540
local PADDING = 16
-- Rows as tall as Best Crafts', as every table's (Columns.lua).
local ROW_HEIGHT = Columns.ROW_HEIGHT
-- The text's place in a row, from the row's top: as on Best Crafts.
local TEXT_OFFSET = -4
-- The column headings sit 16 above the list, as far below the title (12
-- tall, at -32) as Profit History's total is below its title.
local LIST_TOP = -66
local VISIBLE_ROWS = 15
-- The list is in a scroll box (ScrollBox.lua): its padding and bar beside
-- the list, its padding above and below.
local BOX_EXTRA = VendorProfit.ScrollBox.EXTRA_WIDTH
local BOX_PADDING = VendorProfit.ScrollBox.PADDING
local BASE_LIST_WIDTH = WIDTH - 2 * PADDING - BOX_EXTRA
local LIST_WIDTH = BASE_LIST_WIDTH
-- The columns, by key (Columns.lua), laid out for every purchase on each
-- refresh: Date, Item, From, Each, Total, Now (the cheapest price today).
-- The layout key changes only when the layout does.
local col, layoutKey
local KEYS = { "date", "item", "from", "each", "total", "market" }
local FROM_LEFT = { date = true, item = true }
-- This tab's entry in the window (Panel.AddPage), for the width.
local pageDef

local frame
local rows = {}

-- The sort: newest first, unless changed (saved per character). Item and
-- From sort A to Z first; dates and money the newest or most first.
local SORT_DEFAULT = { key = "date", ascending = false }
local STARTS_ASCENDING = { item = true, from = true }

local function Sort()
    local db = VendorProfitCharDB
    if db and type(db.purchasesSort) == "table" and db.purchasesSort.key then
        return db.purchasesSort
    end
    return SORT_DEFAULT
end

function PurchasePanel.Sort()
    return Sort()
end

-- Item names arrived: what the list shows may change (sorting by item).
local namesVersion = 0
local function NamesLoaded()
    namesVersion = namesVersion + 1
    PurchasePanel.Refresh()
end

local function Gray(text)
    return GRAY_FONT_COLOR:WrapTextInColorCode(text)
end

local function ItemLabel(itemID, n)
    local name = C_Item.GetItemInfo(itemID)
    if name == nil then
        VendorProfit.RedrawWhenLoaded(itemID, NamesLoaded)
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

local function SetSort(key)
    VendorProfitCharDB = VendorProfitCharDB or {}
    VendorProfitCharDB.purchasesSort = Columns.NextSort(Sort(), key, STARTS_ASCENDING)
    PurchasePanel.Refresh()
end

local VALUES = {
    date = function(p) return p.time end,
    item = function(p) return (C_Item.GetItemInfo(p.item) or ("item " .. p.item)):lower() end,
    from = function(p) return p.how == "vendor" and L.HISTORY_VENDOR or L.HISTORY_AUCTION end,
    each = function(p) return p.total / p.n end,
    total = function(p) return p.total end,
    market = function(p) return MarketNow(p.item) or -math.huge end,
}

-- The purchases the list shows, in the chosen order. Worked out again only
-- when the purchases, sort or a loaded name change (and, sorted by today's
-- price, each minute, as prices move).
local data, dataKey = {}, nil
local function Data()
    local sort = Sort()
    local key = table.concat({ History.Version(), History.PurchaseCount(), sort.key, tostring(sort.ascending),
        namesVersion, sort.key == "market" and math.floor(time() / 60) or 0 }, "/")
    if key ~= dataKey then
        dataKey = key
        data = {}
        for index = 1, History.PurchaseCount() do
            data[index] = History.Purchase(index)
        end
        -- Newest first already; any other order sorted (ties newest first).
        if not (sort.key == "date" and not sort.ascending) then
            local value, values = VALUES[sort.key] or VALUES.date, {}
            for _, purchase in ipairs(data) do
                values[purchase] = value(purchase)
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
    end
    return data
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
        row.date = Column(list, 0, "LEFT")
        row.item = Column(list, 0, "LEFT")
        row.from = Column(list, 0, "LEFT")
        row.each = Column(list, 0, "RIGHT")
        row.total = Column(list, 0, "RIGHT")
        row.market = Column(list, 0, "RIGHT")
        -- The whole row hovers, for the details, lit while the mouse is on it.
        row.highlight = Columns.Highlight(list)
        row.hit = CreateFrame("Frame", nil, list)
        row.hit:EnableMouse(true)
        row.hit:SetScript("OnEnter", function()
            row.highlight:Show()
            ShowTooltip(row)
        end)
        row.hit:SetScript("OnLeave", function()
            row.highlight:Hide()
            GameTooltip:Hide()
        end)
        row.regions = { row.date, row.item, row.from, row.each, row.total, row.market, row.hit }
        rows[slot] = row
    end
    return row
end

-- Puts a row at a place in the list (1 = top of the whole list).
local function PlaceRow(row, index)
    if row.index == index and row.layoutKey == layoutKey then
        return
    end
    row.index, row.layoutKey = index, layoutKey
    local list = frame.list
    local top = -(index - 1) * ROW_HEIGHT
    for _, key in ipairs(KEYS) do
        local region, column = row[key], col[key]
        region:SetWidth(column.width)
        region:ClearAllPoints()
        if FROM_LEFT[key] then
            region:SetPoint("TOPLEFT", list, "TOPLEFT", column.left, top + TEXT_OFFSET)
        else
            region:SetPoint("TOPRIGHT", list, "TOPRIGHT", column.right, top + TEXT_OFFSET)
        end
    end
    row.hit:ClearAllPoints()
    row.hit:SetPoint("TOPLEFT", list, "TOPLEFT", 0, top)
    row.hit:SetSize(LIST_WIDTH, ROW_HEIGHT)
    row.highlight:ClearAllPoints()
    row.highlight:SetPoint("TOPLEFT", list, "TOPLEFT", 0, top)
    row.highlight:SetSize(LIST_WIDTH, ROW_HEIGHT)
end

-- Lays the columns out to fit every purchase (Columns.lua), not just the
-- rows on screen, so nothing moves as the list scrolls. Places the headings
-- again when that changes the layout; the rows follow as they're placed.
local function LayOut()
    local extents, market = {}, {}
    for index = 1, History.PurchaseCount() do
        local purchase = History.Purchase(index)
        Columns.Track(extents, "each", purchase.total / purchase.n)
        Columns.Track(extents, "total", purchase.total)
        -- Each item's price once, however often it was bought.
        if market[purchase.item] == nil then
            market[purchase.item] = MarketNow(purchase.item) or false
            Columns.Track(extents, "market", market[purchase.item] or nil)
        end
    end
    local key
    col, LIST_WIDTH, key = Columns.Layout(BASE_LIST_WIDTH, {
        { key = "date", heading = L.HISTORY_DATE, sorts = true, samples = Columns.Date() },
        { key = "item", heading = L.HISTORY_ITEM, sorts = true, fill = true },
        { key = "from", heading = L.PURCHASES_FROM, sorts = true, samples = { L.HISTORY_VENDOR, L.HISTORY_AUCTION } },
        { key = "each", heading = L.PURCHASES_EACH, sorts = true, samples = Columns.Money(extents, "each") },
        { key = "total", heading = L.PURCHASES_TOTAL, sorts = true, samples = Columns.Money(extents, "total") },
        { key = "market", heading = L.PURCHASES_NOW, sorts = true, samples = Columns.Money(extents, "market") },
    })
    if key == layoutKey then
        return
    end
    layoutKey = key
    WIDTH = LIST_WIDTH + 2 * PADDING + BOX_EXTRA
    pageDef.width = WIDTH
    frame.list:SetWidth(LIST_WIDTH)
    for index, heading in ipairs(frame.headings) do
        local column = col[KEYS[index]]
        heading:SetWidth(column.width)
        heading:ClearAllPoints()
        if FROM_LEFT[KEYS[index]] then
            heading:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + BOX_PADDING + column.left, LIST_TOP + 16)
        else
            heading:SetPoint("TOPRIGHT", frame, "TOPLEFT", PADDING + BOX_PADDING + LIST_WIDTH + column.right,
                LIST_TOP + 16)
        end
    end
end

-- Fills the rows that fit on screen from where the list is scrolled to.
local function Render()
    local list = Data()
    local count = #list
    local first = math.floor((frame.scroll:GetVerticalScroll() or 0) / ROW_HEIGHT)
    local needed = math.min(VISIBLE_ROWS + 1, math.max(count - first, 0))
    for slot = 1, math.max(needed, #rows) do
        local purchase = slot <= needed and list[first + slot]
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
            row.highlight:Hide()
        end
    end
end

local function Create(page)
    frame = page

    frame.heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -32)
    frame.heading:SetText(L.TAB_PURCHASES)

    -- In KEYS' order, placed with the columns (LayOut): click one to sort
    -- by it, as on Best Crafts.
    local function Heading(key, text, justify)
        return Columns.Heading(frame, key, text, justify, SetSort)
    end
    frame.headings = {
        Heading("date", L.HISTORY_DATE, "LEFT"),
        Heading("item", L.HISTORY_ITEM, "LEFT"),
        Heading("from", L.PURCHASES_FROM, "LEFT"),
        Heading("each", L.PURCHASES_EACH, "RIGHT"),
        Heading("total", L.PURCHASES_TOTAL, "RIGHT"),
        Heading("market", L.PURCHASES_NOW, "RIGHT"),
    }

    -- The list, in a scroll box (placed in Refresh).
    frame.scroll = VendorProfit.ScrollBox.Create(frame)
    frame.list = frame.scroll.list
    frame.list:SetSize(LIST_WIDTH, ROW_HEIGHT)
    -- Scrolling refills the rows on screen.
    frame.scroll:HookScript("OnVerticalScroll", Render)

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + BOX_PADDING, LIST_TOP - BOX_PADDING)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetWidth(WIDTH - 2 * PADDING - 2 * BOX_PADDING)
    frame.empty:SetText(L.PURCHASES_EMPTY)
end

local function Refresh()
    LayOut()
    local count = History.PurchaseCount()
    local maxScroll = math.max(count - VISIBLE_ROWS, 0) * ROW_HEIGHT
    if (frame.scroll:GetVerticalScroll() or 0) > maxScroll then
        frame.scroll:SetVerticalScroll(maxScroll)
    end
    Render()

    -- The list fills the page: its box always VISIBLE_ROWS tall, kept when
    -- empty (saying so, inside it).
    local boxHeight = VendorProfit.ScrollBox.Place(frame.scroll, frame, PADDING, LIST_TOP, LIST_WIDTH,
        VISIBLE_ROWS * ROW_HEIGHT, count * ROW_HEIGHT, true)
    frame.empty:SetShown(count == 0)
    for _, heading in ipairs(frame.headings) do
        heading:SetShown(count > 0)
    end
    -- The sorted heading in white, with an arrow for its direction.
    Columns.ShowSort(frame.headings, Sort())

    local listHeight = boxHeight
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
