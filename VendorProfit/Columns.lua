-- Table columns for the list tabs (Best Crafts, Profit History, Purchase
-- History), all laid out by one rule so that neither values nor headings
-- ever touch:
--
--   * A column is as wide as the widest of its heading (with the sort arrow,
--     if it sorts) and the widest value in the whole list, not just the rows
--     on screen. Both are measured in the game's own fonts, so the rule holds
--     whatever the font, locale or coin icons draw like.
--   * Columns are GAP apart.
--   * One column (the item or recipe name) takes what's left of the row;
--     the window widens if that would leave it narrower than FILL_MIN.
--
-- The tabs lay their columns out again on each refresh, which is cheap: the
-- list's lowest and highest numbers per column are found with arithmetic
-- (Track), and only a sample for each end is measured. A sample has the
-- same coins and digits as the real value, every digit a 9 (12g 05s 07c is
-- sized as 99g 99s 99c), so widths change only when a value gains a digit
-- or a coin, not at every new number. Every column has a fixed width, so
-- anything wider is cut short with "..." rather than run into the next.

local _, ns = ...
local VendorProfit = ns.VendorProfit
local L = VendorProfit.L

local Columns = {}
VendorProfit.Columns = Columns

Columns.GAP = 12
Columns.FILL_MIN = 160

-- The fonts the tabs use for values and for headings.
local VALUE_FONT, HEADING_FONT = "GameFontHighlightSmall", "GameFontNormalSmall"

-- One hidden font string per font, reused for every measurement.
local measurers = {}
function Columns.Measure(text, font)
    font = font or VALUE_FONT
    local measurer = measurers[font]
    if measurer == nil then
        measurer = UIParent:CreateFontString(nil, "OVERLAY", font)
        measurer:Hide()
        measurers[font] = measurer
    end
    measurer:SetText(text)
    -- Unbounded: the width the whole text needs, not what a set width lets
    -- it show.
    local width = measurer.GetUnboundedStringWidth and measurer:GetUnboundedStringWidth()
        or measurer:GetStringWidth()
    return math.ceil(width or 0)
end

-- A heading's text as shown when its column is sorted: the label, then an
-- arrow for the direction.
function Columns.SortedText(label, ascending)
    return label .. " " .. (ascending and L.BEST_SORT_UP or L.BEST_SORT_DOWN)
end

-- Notes value (nil is skipped) as one of column key's, in extents (a table
-- the caller starts empty for each refresh): its lowest and highest.
function Columns.Track(extents, key, value)
    if value == nil then
        return
    end
    local extent = extents[key]
    if extent == nil then
        extent = { low = 0, high = 0 }
        extents[key] = extent
    end
    extent.low = math.min(extent.low, value)
    extent.high = math.max(extent.high, value)
end

-- The number with as many digits as whole number n, all nines (0 for 0).
local function Nines(n)
    return n == 0 and 0 or math.floor(10 ^ #tostring(n) - 1 + 0.5)
end

-- Copper with the same coins and digits as copper, every digit a 9.
local function MoneyNines(copper)
    copper = math.floor(math.abs(copper) + 0.5)
    for _, unit in ipairs({ 10000, 100 }) do
        if copper >= unit then
            return Nines(math.floor(copper / unit)) * unit + unit - 1
        end
    end
    return Nines(copper)
end

-- Samples for a column's extent (from Track): its widest positive and
-- negative values, as money, a percentage (ROI) or a count.
local function Ends(extents, key, format)
    local extent, samples = extents[key], {}
    if extent and extent.high > 0 then
        samples[1] = format(extent.high)
    end
    if extent and extent.low < 0 then
        samples[#samples + 1] = format(extent.low)
    end
    return samples
end
function Columns.Money(extents, key)
    return Ends(extents, key, function(copper)
        return VendorProfit.FormatMoney((copper < 0 and -1 or 1) * MoneyNines(copper))
    end)
end
function Columns.Percent(extents, key)
    return Ends(extents, key, function(roi)
        return VendorProfit.FormatROI((roi < 0 and -1 or 1) * Nines(math.floor(math.abs(roi) * 100 + 0.5)) / 100)
    end)
end
function Columns.Count(extents, key)
    return Ends(extents, key, function(n)
        return (BreakUpLargeNumbers or tostring)(Nines(math.floor(n)))
    end)
end

-- A sample date: days and months are two digits at most, and 28/12 covers
-- both orders.
function Columns.Date()
    return { date(L.HISTORY_DATE_FORMAT, time({ year = 2026, month = 12, day = 28, hour = 12 })) }
end

-- Lays out a row of columns. columns, left to right: { key, heading (text),
-- sorts (it has a sort arrow), samples (texts), width (at least this, for
-- buttons), fill (takes the rest) }. Returns, by key, { width, left (from
-- the list's left edge), right (from its right edge, zero or less) }, the
-- list width (listWidth, or wider if the columns need it), and a key that
-- changes only when the layout does, so rows are placed again only then.
function Columns.Layout(listWidth, columns)
    local widths, needed, fill = {}, 0, nil
    for i, column in ipairs(columns) do
        local width = column.width or 0
        if column.heading then
            local heading = column.sorts and Columns.SortedText(column.heading, false) or column.heading
            width = math.max(width, Columns.Measure(heading, HEADING_FONT))
        end
        for _, sample in ipairs(column.samples or {}) do
            width = math.max(width, Columns.Measure(sample))
        end
        if column.fill then
            fill = column.key
            width = math.max(width, Columns.FILL_MIN)
        end
        widths[column.key] = width
        needed = needed + width + (i > 1 and Columns.GAP or 0)
    end
    listWidth = math.max(listWidth, needed)
    if fill then
        widths[fill] = widths[fill] + listWidth - needed
    end
    local layout, left, key = {}, 0, { listWidth }
    for _, column in ipairs(columns) do
        local width = widths[column.key]
        layout[column.key] = { width = width, left = left, right = left + width - listWidth }
        left = left + width + Columns.GAP
        key[#key + 1] = width
    end
    return layout, listWidth, table.concat(key, ",")
end

-- The width from the left edge of column from to the right edge of column
-- to, for text that spans several columns.
function Columns.Span(layout, from, to)
    return layout[to].left + layout[to].width - layout[from].left
end
