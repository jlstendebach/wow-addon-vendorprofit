-- Table columns for the list tabs (Best Crafts, Profit History, Purchase
-- History), all laid out by one rule so that neither values nor headings
-- ever touch:
--
--   * A column is as wide as the widest of its heading (with the sort arrow,
--     if it sorts) and samples of the widest values it's meant to hold.
--     Both are measured in the game's own fonts when the tab is built, so
--     the rule holds whatever the font, locale or coin icons draw like.
--   * Columns are GAP apart.
--   * One column (the item or recipe name) takes what's left of the row;
--     the window widens if that would leave it narrower than FILL_MIN.
--
-- A value wider than its samples is cut short with "..." by the game rather
-- than run into its neighbor, since every column has a fixed width.

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

-- Samples of the widest values a column is meant to hold. Money per item
-- runs to 999g, totals to 9,999g, both with a minus for a loss.
function Columns.Samples()
    local big = BreakUpLargeNumbers or tostring
    return {
        money = { VendorProfit.FormatMoney(-9999999) },
        total = { VendorProfit.FormatMoney(-99999999) },
        roi = { VendorProfit.FormatROI(99.99), VendorProfit.FormatROI(-1) },
        count = { big(99999) },
        -- Days and months are two digits at most; 28/12 covers both orders.
        date = { date(L.HISTORY_DATE_FORMAT, time({ year = 2026, month = 12, day = 28, hour = 12 })) },
    }
end

-- Lays out a row of columns. columns, left to right: { key, heading (text),
-- sorts (it has a sort arrow), samples (texts), width (at least this, for
-- buttons), fill (takes the rest) }. Returns, by key, { width, left (from
-- the list's left edge), right (from its right edge, zero or less) }, and
-- the list width: listWidth, or wider if the columns need it.
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
    local layout, left = {}, 0
    for _, column in ipairs(columns) do
        local width = widths[column.key]
        layout[column.key] = { width = width, left = left, right = left + width - listWidth }
        left = left + width + Columns.GAP
    end
    return layout, listWidth
end

-- The width from the left edge of column from to the right edge of column
-- to, for text that spans several columns.
function Columns.Span(layout, from, to)
    return layout[to].left + layout[to].width - layout[from].left
end
