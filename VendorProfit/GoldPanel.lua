-- The Gold tab of the Vendor Profit window: a graph of your gold over time
-- (Gold.lua), added up over the characters ticked in the Characters menu,
-- like TradeSkillMaster's Player Gold graph. Our own code and look; the
-- behavior is borrowed:
--
--   * a soft, thin line, green when the range ends higher than it starts,
--     red when lower, and gold while hovered;
--   * hovering shows a gold guide line, a dot on the line and the gold then
--     at the guide's top, with the time beside the page's title;
--   * dragging across the graph zooms into that stretch; right-click zooms
--     back out. Zoom is for the moment: changing the range or reopening the
--     tab resets it.
--
-- Range is a menu like Profit History's, and Characters works like Best
-- Crafts' Filter, with the red X beside it showing everyone again.
--
-- The graph is drawn from samples, evenly spaced across what's shown, rather
-- than every point: a long log has far more points than pixels.

local ADDON_NAME, ns = ...
local VendorProfit = ns.VendorProfit
local Gold = VendorProfit.Gold
local Panel = VendorProfit.Panel
local L = VendorProfit.L

local GoldPanel = {}
VendorProfit.GoldPanel = GoldPanel

local WIDTH = 540
local PADDING = 16
-- Title at -32, the total at -50 and the buttons at -66 (20 tall), as on
-- Profit History; the graph 18 below those, with the hovered amount between.
local TOTAL_TOP = -50
local CONTROLS_TOP = -66
local Y_LABEL_WIDTH = 64
local PLOT_LEFT = PADDING + Y_LABEL_WIDTH
local PLOT_TOP = -104
-- Room on the right for the last time label, which is centered on its tick.
local PLOT_WIDTH = WIDTH - PLOT_LEFT - PADDING - 12
local PLOT_HEIGHT = 200
local X_LABEL_WIDTH = 64
local HELP_TOP = PLOT_TOP - PLOT_HEIGHT - 22
local HEIGHT = -HELP_TOP + 10 + PADDING
-- About one sample per 3 pixels.
local SAMPLES = math.floor(PLOT_WIDTH / 3)
-- Drags shorter than this are clicks, not zooms.
local DRAG_PIXELS = 4
-- The shortest stretch the graph shows, in seconds: a single point just now
-- still gets a line, and zooming stops somewhere readable.
local MIN_SPAN = 60 * 60
local MIN_ZOOM = 10 * 60
local Y_STEPS = 4
-- Our own textures: a stroke that fades out across its width, so the line's
-- edges and joints are smooth (a plain color fill looks jagged), and a round
-- dot.
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local LINE_TEXTURE = MEDIA .. "GraphLine.png"
local DOT_TEXTURE = MEDIA .. "GraphDot.png"
local LINE_THICKNESS = 2.5
local X_LABELS = 5

local HOUR = 60 * 60
local DAY = 24 * HOUR
local WEEK = 7 * DAY

-- Ranges, in the menu's order. Saved per character, like Profit History's.
local RANGES = {
    { key = "all" },
    { key = "d1", seconds = DAY },
    { key = "d7", seconds = 7 * DAY, days = 7 },
    { key = "d30", seconds = 30 * DAY, days = 30 },
    { key = "m3", seconds = 91 * DAY, months = 3 },
    { key = "m6", seconds = 183 * DAY, months = 6 },
    { key = "y1", seconds = 365 * DAY },
}
local RANGE_BY_KEY = {}
for _, range in ipairs(RANGES) do
    RANGE_BY_KEY[range.key] = range
end

-- Time label steps, smallest first: seconds, or months.
local X_STEPS = {
    { seconds = 10 * 60 }, { seconds = 15 * 60 }, { seconds = 30 * 60 }, { seconds = HOUR }, { seconds = 2 * HOUR }, { seconds = 3 * HOUR }, { seconds = 6 * HOUR },
    { seconds = 12 * HOUR }, { seconds = DAY }, { seconds = 2 * DAY }, { seconds = 7 * DAY },
    { seconds = 14 * DAY }, { months = 1 }, { months = 2 }, { months = 3 }, { months = 6 }, { months = 12 },
}

local frame
local zoom          -- { start, finish } while zoomed in
local graph         -- what's drawn: { start, finish, low, high, times, values, characters }
local hoverIndex    -- the sample the hover shows
local dragFrom      -- where a drag started, in plot pixels
local hovered       -- whether the mouse is over the graph
local drawnKey      -- what the page was last drawn for (see Refresh)

local function Money(copper)
    return VendorProfit.FormatMoney(copper)
end

local function Signed(copper)
    if copper > 0 then
        return "+" .. Money(copper)
    end
    return Money(copper)
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
    return RANGE_BY_KEY[db and db.goldRange] or RANGES[1]
end

function GoldPanel.Range()
    return Range().key
end

function GoldPanel.SetRange(key)
    if RANGE_BY_KEY[key] then
        VendorProfitCharDB = VendorProfitCharDB or {}
        VendorProfitCharDB.goldRange = key
        zoom = nil
        GoldPanel.Refresh()
    end
end

local function RangeLabel(range)
    if range.key == "d1" then
        return L.GOLD_RANGE_DAY
    elseif range.days then
        return string.format(L.HISTORY_RANGE_DAYS, range.days)
    elseif range.months then
        return string.format(L.GOLD_RANGE_MONTHS, range.months)
    elseif range.key == "y1" then
        return L.GOLD_RANGE_YEAR
    end
    return L.HISTORY_RANGE_ALL
end

local function RangeMenu(_, root)
    for _, range in ipairs(RANGES) do
        root:CreateRadio(RangeLabel(range),
            function() return Range().key == range.key end,
            function() GoldPanel.SetRange(range.key) end)
    end
end

-- Characters ------------------------------------------------------------------

-- Names in the menu and tooltip, with the realm only when the account has
-- characters on more than one.
local function NameOf(character, characters)
    for _, other in ipairs(characters) do
        if other.realm ~= character.realm then
            return character.name .. "-" .. character.realm
        end
    end
    return character.name
end

local function CharactersMenu(_, root)
    local characters = Gold.Characters()
    for _, character in ipairs(characters) do
        local key = character.key
        root:CreateCheckbox(NameOf(character, characters) .. "  " .. Money(character.copper),
            function() return Gold.IsShown(key) end,
            function() Gold.SetShown(key, not Gold.IsShown(key)) end)
    end
end

-- Opening a menu under its button: as with Best Crafts' Filter, a click on
-- the button just after its menu closed was meant to close it. The game may
-- reuse one menu frame for every menu, so what's tracked is which button the
-- open menu belongs to.
local openMenu, openFor       -- the menu showing, and its button
local closedFor, closedAt = nil, 0

local function ToggleMenu(button, generator)
    if openMenu and openFor == button and openMenu:IsShown() then
        openMenu:Hide()
        return
    end
    if closedFor == button and GetTime() - closedAt < 0.25 then
        return
    end
    local menu = MenuUtil.CreateContextMenu(button, generator)
    if menu then
        -- Under the button, not at the mouse.
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
        openMenu, openFor = menu, button
        if not menu.vendorProfitGoldHooked then
            menu.vendorProfitGoldHooked = true
            menu:HookScript("OnHide", function(self)
                if self == openMenu and openFor then
                    closedFor, closedAt = openFor, GetTime()
                    openFor = nil
                end
            end)
        end
    end
end

-- Axes ------------------------------------------------------------------------

-- A round step (1, 2 or 5 times a power of ten copper) that splits span into
-- about steps parts.
local function NiceStep(span, steps)
    local raw = span / steps
    if raw <= 1 then
        return 1
    end
    local power = 10 ^ math.floor(math.log10(raw))
    for _, multiple in ipairs({ 1, 2, 5, 10 }) do
        if multiple * power >= raw then
            return multiple * power
        end
    end
    return 10 * power
end

-- The local start of the day or month a time is in.
local function Floor(at, unit)
    local d = date("*t", at)
    if unit == "day" then
        return at - d.hour * HOUR - d.min * 60 - d.sec
    end
    return time({ year = d.year, month = d.month, day = 1, hour = 0 })
end

local function AddMonths(at, months)
    local d = date("*t", at)
    return time({ year = d.year, month = d.month + months, day = 1, hour = 0 })
end

-- The time labels' positions: round local times (whole hours, midnights,
-- the first of a month), at most X_LABELS of them.
local function TimeTicks(start, finish)
    local span = finish - start
    local step = X_STEPS[#X_STEPS]
    for _, candidate in ipairs(X_STEPS) do
        local length = candidate.seconds or candidate.months * 30 * DAY
        if span / length <= X_LABELS then
            step = candidate
            break
        end
    end
    local ticks = {}
    if step.months then
        local at = Floor(start, "month")
        while at <= finish and #ticks < 50 do
            if at >= start then
                ticks[#ticks + 1] = at
            end
            at = AddMonths(at, step.months)
        end
    else
        -- Counted from midnight, so they land on 00:00, 06:00, 06:30, ...
        local at = Floor(start, "day")
        while at <= finish and #ticks < 50 do
            if at >= start then
                ticks[#ticks + 1] = at
            end
            at = at + step.seconds
        end
    end
    return ticks, step
end

local function TimeLabel(at, step)
    if step.months then
        return date(L.GOLD_MONTH_FORMAT, at)
    elseif step.seconds < DAY then
        return date(L.GOLD_HOUR_FORMAT, at)
    end
    return date(L.HISTORY_DATE_FORMAT, at)
end

-- Drawing -----------------------------------------------------------------------

local function X(at)
    return (at - graph.start) / (graph.finish - graph.start) * PLOT_WIDTH
end

local function Y(value)
    return (value - graph.low) / (graph.high - graph.low) * PLOT_HEIGHT
end

-- Pools of regions, reused from one draw to the next.
local lines, grid, yLabels, xLabels = {}, {}, {}, {}

local function PoolLine(index)
    local line = lines[index]
    if line == nil then
        line = frame.plot:CreateLine(nil, "ARTWORK")
        line:SetTexture(LINE_TEXTURE)
        line:SetThickness(LINE_THICKNESS)
        -- The client snaps textures to whole pixels, which makes a slanted
        -- line stair-step; drawn where it falls, the soft edges blend.
        if line.SetSnapToPixelGrid then
            line:SetSnapToPixelGrid(false)
            line:SetTexelSnappingBias(0)
        end
        lines[index] = line
    end
    return line
end

local function PoolGrid(index)
    local texture = grid[index]
    if texture == nil then
        texture = frame.plot:CreateTexture(nil, "BORDER")
        texture:SetColorTexture(1, 1, 1, 0.08)
        texture:SetHeight(1)
        grid[index] = texture
    end
    return texture
end

local function PoolLabel(pool, index, width, justify)
    local label = pool[index]
    if label == nil then
        label = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetWidth(width)
        label:SetJustifyH(justify)
        label:SetWordWrap(false)
        pool[index] = label
    end
    return label
end

local function HideFrom(pool, first)
    for index = first, #pool do
        pool[index]:Hide()
    end
end

-- The line's color: gold while hovered, else green or red (see Draw).
local function ColorLine()
    local color = hovered and NORMAL_FONT_COLOR or graph.color
    for index = 1, #graph.values - 1 do
        lines[index]:SetVertexColor(color.r, color.g, color.b, 1)
    end
end

local function HideHover()
    hoverIndex = nil
    if frame then
        frame.guide:Hide()
        frame.dot:Hide()
        frame.value:Hide()
        frame.when:SetText("")
    end
end

-- Works out what to draw: the stretch of time, the samples and the gold
-- range, or nil with the reason when there's nothing to draw.
local function Compute()
    local characters = Gold.Shown()
    if #Gold.Characters() == 0 then
        return nil, L.GOLD_EMPTY
    elseif #characters == 0 then
        return nil, L.GOLD_NONE_SELECTED
    end

    local now = time()
    local first = now
    for _, character in ipairs(characters) do
        first = math.min(first, character.first)
    end
    local range = Range()
    local start = range.seconds and math.max(now - range.seconds, first) or first
    local finish = now
    if zoom then
        start, finish = zoom[1], zoom[2]
    end
    if finish - start < MIN_SPAN and not zoom then
        start = finish - MIN_SPAN
    end

    local times, values = {}, {}
    local low, high = math.huge, -math.huge
    for index = 0, SAMPLES do
        local at = start + (finish - start) * index / SAMPLES
        local value = Gold.Total(characters, at)
        times[index + 1], values[index + 1] = at, value
        low, high = math.min(low, value), math.max(high, value)
    end
    -- A flat line still gets some room above and below.
    if high - low < 1 then
        low, high = math.max(low - 10000, 0), high + 10000
    end
    local step = NiceStep(high - low, Y_STEPS)
    low = math.floor(low / step) * step
    high = math.ceil(high / step) * step
    if high <= low then
        high = low + step
    end
    return { start = start, finish = finish, low = low, high = high, step = step,
        times = times, values = values, characters = characters }
end

-- A gold label on the side: the amount, with 0 in the step's coin (0g on a
-- gold axis, not 0c).
local function AxisMoney(value, step)
    if value == 0 then
        local coins = VendorProfit.COINS
        return "0" .. (step >= 10000 and coins.gold or step >= 100 and coins.silver or coins.copper)
    end
    return VendorProfit.FormatCoins(value)
end

local function Draw()
    -- Gold labels on the left, with faint lines across at each.
    local index = 0
    local value = graph.low
    while value <= graph.high + 0.5 do
        index = index + 1
        local y = Y(value)
        local line = PoolGrid(index)
        line:ClearAllPoints()
        line:SetPoint("BOTTOMLEFT", frame.plot, "BOTTOMLEFT", 0, y)
        line:SetPoint("BOTTOMRIGHT", frame.plot, "BOTTOMLEFT", PLOT_WIDTH, y)
        line:Show()
        local label = PoolLabel(yLabels, index, Y_LABEL_WIDTH - 6, "RIGHT")
        label:ClearAllPoints()
        label:SetPoint("RIGHT", frame.plot, "BOTTOMLEFT", -6, y)
        label:SetText(AxisMoney(value, graph.step))
        label:Show()
        value = value + graph.step
    end
    HideFrom(grid, index + 1)
    HideFrom(yLabels, index + 1)

    -- Time labels under the graph.
    local ticks, step = TimeTicks(graph.start, graph.finish)
    for tick, at in ipairs(ticks) do
        local label = PoolLabel(xLabels, tick, X_LABEL_WIDTH, "CENTER")
        label:ClearAllPoints()
        label:SetPoint("TOP", frame.plot, "BOTTOMLEFT", X(at), -4)
        label:SetText(TimeLabel(at, step))
        label:Show()
    end
    HideFrom(xLabels, #ticks + 1)

    -- The line: green when the stretch ends at least as high as it starts.
    local values = graph.values
    graph.color = values[#values] >= values[1] and GREEN_FONT_COLOR or RED_FONT_COLOR
    for sample = 2, #values do
        local line = PoolLine(sample - 1)
        line:SetStartPoint("BOTTOMLEFT", frame.plot, X(graph.times[sample - 1]), Y(values[sample - 1]))
        line:SetEndPoint("BOTTOMLEFT", frame.plot, X(graph.times[sample]), Y(values[sample]))
        line:Show()
    end
    HideFrom(lines, #values)
    ColorLine()
end

-- Hover and zoom ----------------------------------------------------------------

-- Where the cursor is across the plot, in pixels from its left, kept on it.
local function CursorX()
    local plot = frame.plot
    local x = GetCursorPosition() / plot:GetEffectiveScale() - (plot:GetLeft() or 0)
    return math.max(0, math.min(PLOT_WIDTH, x))
end

local function TimeAt(x)
    return graph.start + (graph.finish - graph.start) * x / PLOT_WIDTH
end

-- The gold at a sample, above the guide line's top (kept over the graph),
-- and its time beside the title.
local function ShowValue(index)
    local x = X(graph.times[index])
    frame.value:SetText(VendorProfit.FormatCoins(graph.values[index]))
    local half = (frame.value:GetStringWidth() or 0) / 2
    x = math.max(half, math.min(PLOT_WIDTH - half, x))
    frame.value:ClearAllPoints()
    frame.value:SetPoint("BOTTOM", frame.plot, "TOPLEFT", x, 3)
    frame.value:Show()
    frame.when:SetText(date(L.HISTORY_TIME_FORMAT, graph.times[index]))
end

-- The mouse left the graph.
local function Leave()
    hovered = false
    frame.plot:SetScript("OnUpdate", nil)
    HideHover()
    if graph then
        ColorLine()
    end
end

local function UpdateHover()
    -- Hidden or covered while hovered: the game may not say the mouse left.
    if not dragFrom and not frame.plot:IsMouseOver() then
        Leave()
        return
    end
    if graph == nil then
        HideHover()
        return
    end
    local x = CursorX()
    local index = math.floor(x / PLOT_WIDTH * SAMPLES + 0.5) + 1
    if index ~= hoverIndex then
        hoverIndex = index
        local sampleX = X(graph.times[index])
        local y = Y(graph.values[index])
        frame.guide:ClearAllPoints()
        frame.guide:SetPoint("TOPLEFT", frame.plot, "TOPLEFT", sampleX, 0)
        frame.guide:SetPoint("BOTTOMLEFT", frame.plot, "BOTTOMLEFT", sampleX, 0)
        frame.guide:Show()
        frame.dot:ClearAllPoints()
        frame.dot:SetPoint("CENTER", frame.plot, "BOTTOMLEFT", sampleX, y)
        frame.dot:Show()
        ShowValue(index)
    end
    -- The stretch being dragged across.
    if dragFrom then
        local left, right = math.min(dragFrom, x), math.max(dragFrom, x)
        frame.selection:ClearAllPoints()
        frame.selection:SetPoint("TOPLEFT", frame.plot, "TOPLEFT", left, 0)
        frame.selection:SetPoint("BOTTOMRIGHT", frame.plot, "BOTTOMLEFT", right, 0)
        frame.selection:SetShown(right - left >= DRAG_PIXELS)
    end
end

local function MouseDown(_, button)
    if button == "LeftButton" and graph then
        dragFrom = CursorX()
    end
end

local function MouseUp(_, button)
    if button == "RightButton" then
        if zoom then
            zoom = nil
            GoldPanel.Refresh()
        end
    elseif button == "LeftButton" and dragFrom and graph then
        local x = CursorX()
        local from = dragFrom
        dragFrom = nil
        frame.selection:Hide()
        if math.abs(x - from) >= DRAG_PIXELS then
            local start, finish = TimeAt(math.min(from, x)), TimeAt(math.max(from, x))
            if finish - start < MIN_ZOOM then
                local middle = (start + finish) / 2
                start, finish = middle - MIN_ZOOM / 2, middle + MIN_ZOOM / 2
            end
            zoom = { start, finish }
            GoldPanel.Refresh()
        end
    end
    dragFrom = nil
    if frame then
        frame.selection:Hide()
    end
end

-- Page ------------------------------------------------------------------------------

local function Create(page)
    frame = page

    frame.heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -32)
    frame.heading:SetText(L.TAB_GOLD)

    frame.total = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.total:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, TOTAL_TOP)
    frame.total:SetJustifyH("LEFT")
    frame.total:SetWidth(WIDTH - 2 * PADDING)

    -- Characters and Range: buttons in the page's own style opening the
    -- game's menus under them. Left out if this client doesn't have the
    -- game's menu system.
    if MenuUtil and MenuUtil.CreateContextMenu then
        local characters = SmallButton(frame, L.GOLD_CHARACTERS, 140)
        characters:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, CONTROLS_TOP)
        characters:SetScript("OnClick", function(self) ToggleMenu(self, CharactersMenu) end)
        frame.characters = characters

        -- The red X: shows every character again, grayed out while none
        -- are hidden.
        local reset = SmallButton(frame, "", 22)
        reset:SetPoint("LEFT", characters, "RIGHT", 4, 0)
        reset:SetMotionScriptsWhileDisabled(true)
        reset.icon = reset:CreateTexture(nil, "OVERLAY")
        reset.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        reset.icon:SetSize(12, 12)
        reset.icon:SetPoint("CENTER", reset, "CENTER", 0, 0)
        reset:SetScript("OnClick", function() Gold.ShowAll() end)
        reset:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L.GOLD_SHOW_ALL, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        reset:SetScript("OnLeave", function() GameTooltip:Hide() end)
        frame.charactersReset = reset

        frame.range = SmallButton(frame, "", 110)
        frame.range:SetPoint("RIGHT", frame, "TOPRIGHT", -PADDING, CONTROLS_TOP - 10)
        frame.range:SetScript("OnClick", function(self) ToggleMenu(self, RangeMenu) end)
        frame.range:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L.GOLD_RANGE_HELP, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        frame.range:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- The graph: a dark plot area the line, guide and drag selection sit on.
    local plot = CreateFrame("Frame", nil, frame)
    plot:SetPoint("TOPLEFT", frame, "TOPLEFT", PLOT_LEFT, PLOT_TOP)
    plot:SetSize(PLOT_WIDTH, PLOT_HEIGHT)
    plot:EnableMouse(true)
    frame.plot = plot
    local background = plot:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(plot)
    background:SetColorTexture(0, 0, 0, 0.3)

    frame.selection = plot:CreateTexture(nil, "OVERLAY")
    frame.selection:SetColorTexture(1, 1, 1, 0.15)
    frame.selection:Hide()

    frame.guide = plot:CreateTexture(nil, "OVERLAY")
    frame.guide:SetColorTexture(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 0.8)
    frame.guide:SetWidth(1)
    frame.guide:Hide()

    frame.dot = plot:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.dot:SetTexture(DOT_TEXTURE)
    frame.dot:SetSize(8, 8)
    frame.dot:Hide()

    frame.value = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.value:Hide()

    frame.when = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.when:SetPoint("LEFT", frame.heading, "RIGHT", 8, 0)

    plot:SetScript("OnEnter", function(self)
        hovered = true
        self:SetScript("OnUpdate", UpdateHover)
        if graph then
            ColorLine()
        end
        UpdateHover()
    end)
    plot:SetScript("OnLeave", Leave)
    plot:SetScript("OnMouseDown", MouseDown)
    plot:SetScript("OnMouseUp", MouseUp)

    -- On the graph, not the page: the graph is drawn over the page's own
    -- text, and its dark background would dim it.
    frame.empty = plot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("CENTER", plot, "CENTER", 0, 0)
    frame.empty:SetWidth(PLOT_WIDTH - 40)

    frame.help = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.help:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, HELP_TOP)
    frame.help:SetJustifyH("LEFT")
    frame.help:SetWidth(WIDTH - 2 * PADDING)

    -- Reopening the tab (or the window) starts unzoomed, and not hovered.
    frame:HookScript("OnShow", function()
        zoom = nil
        dragFrom = nil
        if hovered then
            Leave()
        end
    end)
end

-- What the page shows depends on: the gold logs and ticks (Gold.Version),
-- the range, the zoom, and the minute (the graph runs to now). The window
-- refreshes its open page on every bag and gold change, so the page is only
-- worked out and drawn again when one of these changed.
local function DrawKey()
    return table.concat({ Gold.Version(), Range().key, zoom and zoom[1] or "", zoom and zoom[2] or "",
        math.floor(time() / 60) }, "/")
end

local function Refresh()
    local key = DrawKey()
    if key == drawnKey then
        return HEIGHT
    end
    drawnKey = key
    local shown = Gold.Shown()
    local all = Gold.Characters()
    local now = time()

    if #shown == 1 then
        frame.total:SetText(string.format(L.GOLD_TOTAL_ONE, Money(Gold.Total(shown, now)),
            Signed(Gold.Total(shown, now) - Gold.Total(shown, now - WEEK))))
    elseif #shown > 1 then
        frame.total:SetText(string.format(L.GOLD_TOTAL, Money(Gold.Total(shown, now)), #shown,
            Signed(Gold.Total(shown, now) - Gold.Total(shown, now - WEEK))))
    else
        frame.total:SetText("")
    end

    if frame.characters then
        frame.characters:SetText(#shown < #all and string.format(L.GOLD_CHARACTERS_SOME, #shown, #all)
            or L.GOLD_CHARACTERS)
        frame.charactersReset:SetEnabled(#shown < #all)
        frame.charactersReset.icon:SetDesaturated(#shown == #all)
        frame.range:SetText(RangeLabel(Range()))
    end

    local reason
    graph, reason = Compute()
    HideHover()
    if graph then
        Draw()
    else
        HideFrom(lines, 1)
        HideFrom(grid, 1)
        HideFrom(yLabels, 1)
        HideFrom(xLabels, 1)
    end
    frame.empty:SetText(reason or "")
    frame.empty:SetShown(graph == nil)
    frame.help:SetText(zoom and L.GOLD_ZOOMED or L.GOLD_HELP)
    frame.help:SetShown(graph ~= nil)
    return HEIGHT
end

function GoldPanel.Refresh()
    if Panel.IsShown() and Panel.ActiveTab() == "gold" then
        Panel.Refresh()
    end
end

-- For tests ------------------------------------------------------------------------

function GoldPanel.Frame()
    return frame
end

-- What's drawn: { start, finish, low, high, step, times, values, characters }.
function GoldPanel.Graph()
    return graph
end

function GoldPanel.Zoom()
    return zoom
end

-- The line segments shown.
function GoldPanel.Segments()
    local segments = {}
    for _, line in ipairs(lines) do
        if line:IsShown() then
            segments[#segments + 1] = line
        end
    end
    return segments
end

function GoldPanel.YLabels()
    local texts = {}
    for _, label in ipairs(yLabels) do
        if label:IsShown() then
            texts[#texts + 1] = label:GetText()
        end
    end
    return texts
end

function GoldPanel.XLabels()
    local texts = {}
    for _, label in ipairs(xLabels) do
        if label:IsShown() then
            texts[#texts + 1] = label:GetText()
        end
    end
    return texts
end

-- The tab's icon: a Gold Bar's, read from the client's item data, so it's
-- sure to exist (INV_Misc_Coin_01 drew nothing on Forever). Best Crafts has
-- the coins.
local GOLD_BAR = 3577
local GOLD_BAR_ICON = select(5, C_Item.GetItemInfoInstant(GOLD_BAR)) or "Interface\\Icons\\INV_Misc_Coin_02"

Panel.AddPage({
    name = "gold",
    icon = GOLD_BAR_ICON,
    label = L.TAB_GOLD,
    width = WIDTH,
    create = Create,
    refresh = function() return Refresh() end,
})

Gold.OnChange(GoldPanel.Refresh)
