-- The Best Crafts tab of the Vendor Profit window: every saved recipe of
-- every profession you've opened, ranked together by profit per craft
-- (BestCrafts.lua), losses included, then the ones with no price to rank by,
-- in a scrolling list with Auction and Vendor tabs and Investment, Profit and
-- ROI columns, sortable by clicking a column's heading, filtered by name with
-- the search box as you type, and by profit, skill-up color and profession
-- with the Filter menu (every profession ticked to start with). It works with
-- the professions window closed. Each row has - and + (one craft fewer or
-- more in the shopping order); clicking a name selects it in the professions
-- window while that profession's window is open. Live prices come from Scan.
--
-- Skill-up colors are live for the profession whose window is open; for the
-- others they're as of when their window was last open (Recipes.SkillUp),
-- which the Filter menu and each row's tooltip say.
--
-- Opened by the Vendor Profit button in the professions window's title bar,
-- or /vprofit best.

local ADDON_NAME, ns = ...
local VendorProfit = ns.VendorProfit
local BestCrafts = VendorProfit.BestCrafts
local Recipes = VendorProfit.Recipes
local Order = VendorProfit.Order
local Auctions = VendorProfit.Auctions
local L = VendorProfit.L

local BestPanel = {}
VendorProfit.BestPanel = BestPanel

local Panel = VendorProfit.Panel
local Columns = VendorProfit.Columns

-- Wider than the Shopping List, for the money columns and the search and
-- filter controls; wider still if the columns need it (LayOutColumns).
local WIDTH = 520
local PADDING = 16
local ROW_HEIGHT = 22
local LIST_TOP = -94
local VISIBLE_ROWS = 14
local SCROLLBAR_WIDTH = 24
local BASE_LIST_WIDTH = WIDTH - 2 * PADDING - SCROLLBAR_WIDTH
local LIST_WIDTH = BASE_LIST_WIDTH
local ICON_BUTTON_WIDTH = 22
-- The columns, by key (Columns.lua), laid out for what's listed on each
-- refresh: the recipe name, Investment, Profit, ROI, AH (your auctions of
-- it), Q (crafts queued), then - and + (unqueue and queue a craft). The
-- layout key changes only when the layout does.
local col, layoutKey
-- This tab's entry in the window (Panel.AddPage), for the width.
local pageDef

-- Sorting by column: Recipe (A to Z first), Investment, Profit, ROI (highest
-- first). Clicking the sorted column again reverses it. Recipes with no
-- profit to rank stay at the bottom.
local SORT_DEFAULT = { key = "profit", ascending = false }
local SORT_STARTS_ASCENDING = { name = true }

local SKILL_UP_ORDER, SKILL_UP, Filters, FiltersActive, SetFilter, ResetFilters, FilterMenu, ToggleFilterMenu

local frame              -- the page
local tab = "auction"     -- auction first: it's what this tab is used for most
local rows = {}
local shownList          -- profession, tab and filter the list was last scrolled for
local filter = ""        -- the search box's text, lowercased

-- The item's icon and name, the name in its skill-up color if given (as the
-- professions window colors its list).
local function ItemLabel(itemID, skillUp)
    local name = C_Item.GetItemInfo(itemID)
    if name == nil then
        VendorProfit.RedrawWhenLoaded(itemID, BestPanel.Refresh)
        name = "item " .. itemID
    end
    local skill = skillUp and SKILL_UP[skillUp]
    if skill then
        name = skill.color:WrapTextInColorCode(name)
    end
    local icon = select(5, C_Item.GetItemInfoInstant(itemID))
    return (icon and ("|T" .. icon .. ":0|t ") or "") .. name
end

local function Gray(text)
    return GRAY_FONT_COLOR:WrapTextInColorCode(text)
end

-- A count column's text: the number, or a gray dash for none.
local function Count(n)
    return n > 0 and tostring(n) or Gray("-")
end

-- The list stays up after the professions window closes (the game keeps
-- reporting the last profession), so you can scan and queue at the auction
-- house without it. Only Show needs the window open.
local ProfessionsWindowOpen = Recipes.WindowOpen

local function ShowRecipe(recipe)
    Recipes.Show(recipe.recipeID, recipe.profession)
end

-- How many crafts of a recipe the shopping order holds.
local function Queued(recipeID)
    local n = 0
    for _, entry in ipairs(Order.Entries()) do
        if entry.recipeID == recipeID then
            n = n + entry.crafts
        end
    end
    return n
end

-- Adds one craft of a recipe to the shopping order, or five with Shift.
local function QueueRecipe(entry)
    local recipe = entry.recipe
    local crafts = VendorProfit.QueueStep()
    Order.AddRecipe({
        itemID = recipe.item, recipeID = recipe.recipeID, profession = recipe.profession,
        count = recipe.count, reagents = recipe.reagents,
        sellPrice = select(11, C_Item.GetItemInfo(recipe.item)),
    }, crafts)
    print(string.format(L.QUEUED, crafts, C_Item.GetItemInfo(recipe.item) or ("item " .. recipe.item)))
end

-- Takes one craft of a recipe off the shopping order (five with Shift), and
-- the recipe once none are left.
local function UnqueueRecipe(entry)
    local step = VendorProfit.QueueStep()
    local entries = Order.Entries()
    for index = #entries, 1, -1 do
        local queued = entries[index]
        if queued.recipeID == entry.recipe.recipeID then
            if queued.crafts > step then
                Order.SetCrafts(index, queued.crafts - step)
            else
                Order.Remove(index)
            end
            return
        end
    end
end

local function SmallButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 20)
    button:SetText(text)
    return button
end

local function Tooltip(button, text)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(type(text) == "function" and text(self) or text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Rows live on the scroll child, frame.list, one ROW_HEIGHT apart.
local function GetRow(index)
    local row = rows[index]
    if row == nil then
        local list = frame.list
        row = {}
        local top = -(index - 1) * ROW_HEIGHT
        local function Column()
            local text = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetJustifyH("RIGHT")
            text:SetWordWrap(false)
            return text
        end
        row.left = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.left:SetJustifyH("LEFT")
        row.left:SetWordWrap(false)
        -- Clicking the name shows the recipe in the professions window (while
        -- it's open); hovering it shows what you've made selling the item.
        row.hit = CreateFrame("Frame", nil, list)
        row.hit:EnableMouse(true)
        row.hit:SetScript("OnMouseUp", function(self, mouseButton)
            if mouseButton == "LeftButton" and self.recipe and ProfessionsWindowOpen() then
                ShowRecipe(self.recipe)
            end
        end)
        row.hit:SetScript("OnEnter", function(self)
            if self.recipe then
                BestPanel.ShowSalesTooltip(self, row.left, self.recipe.item, self.recipe)
            end
        end)
        row.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Investment: what one craft's items cost along the cheapest route.
        row.investment = Column()
        row.right = Column()
        -- Return on investment: profit as a share of the investment.
        row.roi = Column()
        -- How many of what it makes you have up for auction (Auctions.lua).
        row.auctions = Column()
        -- How many crafts the shopping order holds.
        row.queued = Column()
        -- Why a recipe isn't ranked, across the columns it has no number for.
        row.reason = Column()

        -- Queue: a plus, at the row's end; unqueue: a minus, before it.
        row.queue = SmallButton(list, "+", ICON_BUTTON_WIDTH)
        row.queue:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, top)
        Tooltip(row.queue, L.BEST_QUEUE_HELP)
        row.unqueue = SmallButton(list, "-", ICON_BUTTON_WIDTH)
        row.unqueue:SetPoint("RIGHT", row.queue, "LEFT", -4, 0)
        Tooltip(row.unqueue, L.BEST_UNQUEUE_HELP)
        rows[index] = row
    end
    -- Placed again only when the columns change.
    if row.layoutKey ~= layoutKey then
        row.layoutKey = layoutKey
        local list, top = frame.list, -(index - 1) * ROW_HEIGHT
        local function At(region, key)
            region:SetWidth(col[key].width)
            region:ClearAllPoints()
            region:SetPoint("TOPRIGHT", list, "TOPRIGHT", col[key].right, top - 4)
        end
        row.left:SetWidth(col.name.width)
        row.left:ClearAllPoints()
        row.left:SetPoint("TOPLEFT", list, "TOPLEFT", col.name.left, top - 4)
        row.hit:ClearAllPoints()
        row.hit:SetPoint("TOPLEFT", list, "TOPLEFT", col.name.left, top)
        row.hit:SetSize(col.name.width, ROW_HEIGHT)
        At(row.investment, "investment")
        At(row.right, "profit")
        At(row.roi, "roi")
        At(row.auctions, "auctions")
        At(row.queued, "queued")
        -- Its width depends on the columns it spans (set in Refresh).
        At(row.reason, "roi")
    end
    return row
end

-- The sort, saved per character.
local function Sort()
    local db = VendorProfitCharDB
    if db and type(db.bestSort) == "table" and db.bestSort.key then
        return db.bestSort
    end
    return SORT_DEFAULT
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
    VendorProfitCharDB.bestSort = { key = key, ascending = ascending }
    BestPanel.Refresh()
end

function BestPanel.Sort()
    return Sort()
end

local function SortValue(entry, key)
    if key == "name" then
        return (C_Item.GetItemInfo(entry.recipe.item) or ""):lower()
    elseif key == "investment" then
        return entry.cost
    elseif key == "roi" then
        return entry.roi or -math.huge
    elseif key == "queued" then
        return Queued(entry.recipe.recipeID)
    elseif key == "auctions" then
        return Auctions.Count(entry.recipe.item)
    end
    return entry.profit
end

-- Orders the ranked entries by the sort; unranked ones stay last as they are.
local function SortEntries(entries)
    local sort = Sort()
    local ranked, unranked = {}, {}
    for _, entry in ipairs(entries) do
        if entry.profit then
            entry.roi = entry.cost > 0 and entry.profit / entry.cost or nil
            ranked[#ranked + 1] = entry
        else
            unranked[#unranked + 1] = entry
        end
    end
    if sort.key == "queued" or sort.key == "auctions" then
        -- Counts: every recipe has one, priced or not; ties keep the ranking.
        local all, place = {}, {}
        for _, entry in ipairs(ranked) do all[#all + 1] = entry end
        for _, entry in ipairs(unranked) do all[#all + 1] = entry end
        for index, entry in ipairs(all) do place[entry] = index end
        table.sort(all, function(a, b)
            local x, y = SortValue(a, sort.key), SortValue(b, sort.key)
            if x ~= y then
                if sort.ascending then
                    return x < y
                end
                return x > y
            end
            return place[a] < place[b]
        end)
        return all
    end
    table.sort(ranked, function(a, b)
        local x, y = SortValue(a, sort.key), SortValue(b, sort.key)
        if x ~= y then
            if sort.ascending then
                return x < y
            end
            return x > y
        end
        return a.recipe.recipeID < b.recipe.recipeID
    end)
    for _, entry in ipairs(unranked) do
        ranked[#ranked + 1] = entry
    end
    return ranked
end

local FormatROI = VendorProfit.FormatROI

-- What you've made selling an item, over all time: its Best Sellers figures
-- (Profit History), with the profit and ROIs. Placed like an item's
-- tooltip: above the row, past the end of its name.
-- With a recipe (a row's), it also names the recipe's profession and says
-- when its skill-up color is saved rather than live.
function BestPanel.ShowSalesTooltip(owner, nameText, itemID, recipe)
    VendorProfit.SetNameTooltipOwner(owner, nameText)
    GameTooltip:SetText(ItemLabel(itemID))
    if recipe then
        GameTooltip:AddLine(recipe.profession, 1, 1, 1)
        local skillUp, saved = Recipes.SkillUp(recipe)
        if skillUp and saved then
            GameTooltip:AddLine(string.format(L.BEST_SKILL_SAVED, recipe.profession),
                GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b, true)
        end
    end
    local HistoryPanel = VendorProfit.HistoryPanel
    local item = HistoryPanel and HistoryPanel.AllTime(itemID)
    if item and item.n > 0 then
        GameTooltip:AddLine(L.BEST_SALES_TITLE, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
        HistoryPanel.AddSalesLines(item, true)
    else
        GameTooltip:AddLine(L.BEST_NO_SALES, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

-- Filters ---------------------------------------------------------------------


-- Skill-up colors, as the professions window shows them.
SKILL_UP_ORDER = { "optimal", "medium", "easy" }
SKILL_UP = {
    optimal = { label = L.BEST_SKILL_OPTIMAL, color = CreateColor and CreateColor(1, 0.5, 0.25) or ORANGE_FONT_COLOR },
    medium = { label = L.BEST_SKILL_MEDIUM, color = CreateColor and CreateColor(1, 1, 0) or YELLOW_FONT_COLOR },
    easy = { label = L.BEST_SKILL_EASY, color = CreateColor and CreateColor(0.25, 0.75, 0.25) or GREEN_FONT_COLOR },
}

-- A recipe's skill-up color key, if the game says (it only knows for the
-- profession whose window is open).
-- (Recipes.SkillUp: "trivial", no skill up, is left white here, as gray in
-- the professions window would be hard to read.)

-- Professions are filtered out by key: "prof:<key>" in the filters.
local function ProfessionFilterKey(key)
    return "prof:" .. tostring(key)
end

-- The saved professions the Filter menu leaves in: { key, name } by name.
local function ShownProfessions()
    local filters = Filters()
    local shown = {}
    for _, profession in ipairs(Recipes.Professions()) do
        if not filters[ProfessionFilterKey(profession.key)] then
            shown[#shown + 1] = profession
        end
    end
    return shown
end

local function Keys(professions)
    local keys = {}
    for index, profession in ipairs(professions) do
        keys[index] = profession.key
    end
    return keys
end

-- The filters, saved per character: { profitable, optimal, medium, easy }.
Filters = function()
    local db = VendorProfitCharDB
    return db and type(db.bestFilters) == "table" and db.bestFilters or {}
end

FiltersActive = function()
    return next(Filters()) ~= nil
end

local function SkillFilterActive()
    local filters = Filters()
    return filters.optimal or filters.medium or filters.easy or false
end

SetFilter = function(key, value)
    VendorProfitCharDB = VendorProfitCharDB or {}
    VendorProfitCharDB.bestFilters = VendorProfitCharDB.bestFilters or {}
    VendorProfitCharDB.bestFilters[key] = value or nil
    BestPanel.Refresh()
end

ResetFilters = function()
    if VendorProfitCharDB then
        VendorProfitCharDB.bestFilters = nil
    end
    BestPanel.Refresh()
end

-- Whether an entry passes the filters. Skill-up filters show recipes of the
-- checked colors; a recipe whose color isn't known can't pass them.
local function PassesFilters(entry)
    local filters = Filters()
    if filters.profitable and not (entry.profit and entry.profit > 0) then
        return false
    end
    if SkillFilterActive() then
        return entry.skillUp ~= nil and filters[entry.skillUp] == true
    end
    return true
end

-- The Filter menu: profitable only, the skill-up colors (with a note that
-- they're as of each profession's last opening), then the professions, each
-- ticked while it's shown.
FilterMenu = function(_, root)
    root:CreateCheckbox(L.BEST_FILTER_PROFITABLE,
        function() return Filters().profitable == true end,
        function() SetFilter("profitable", not Filters().profitable) end)
    root:CreateTitle(L.BEST_FILTER_SKILL_UP)
    for _, key in ipairs(SKILL_UP_ORDER) do
        local skill = SKILL_UP[key]
        root:CreateCheckbox(skill.color:WrapTextInColorCode(skill.label),
            function() return Filters()[key] == true end,
            function() SetFilter(key, not Filters()[key]) end)
    end
    -- The note, a line at a time: the game's menu doesn't wrap text, and is
    -- as wide as its widest line.
    for line in L.BEST_SKILL_SAVED_NOTE:gmatch("[^\n]+") do
        root:CreateTitle(GRAY_FONT_COLOR:WrapTextInColorCode(line))
    end
    local professions = Recipes.Professions()
    if #professions > 0 then
        root:CreateTitle(L.BEST_FILTER_PROFESSIONS)
        for _, profession in ipairs(professions) do
            local filterKey = ProfessionFilterKey(profession.key)
            root:CreateCheckbox(profession.name,
                function() return not Filters()[filterKey] end,
                function() SetFilter(filterKey, not Filters()[filterKey]) end)
        end
    end
end

-- The open Filter menu, and when it last closed: a click on the button
-- closes the menu (the game closes menus on any click outside them) before
-- the button hears it, so a click just after it closed was meant to close it.
local filterMenu
local filterMenuClosed = 0

ToggleFilterMenu = function(button)
    if filterMenu and filterMenu:IsShown() then
        filterMenu:Hide()
        return
    end
    if GetTime() - filterMenuClosed < 0.25 then
        return
    end
    filterMenu = MenuUtil.CreateContextMenu(button, FilterMenu)
    if filterMenu then
        -- Under the button, not at the mouse.
        filterMenu:ClearAllPoints()
        filterMenu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
        if not filterMenu.vendorProfitHooked then
            filterMenu.vendorProfitHooked = true
            filterMenu:HookScript("OnHide", function() filterMenuClosed = GetTime() end)
        end
    end
end

function BestPanel.Filters()
    return Filters()
end

function BestPanel.SetFilter(key, value)
    SetFilter(key, value)
end

function BestPanel.ResetFilters()
    ResetFilters()
end

local function SetTab(name)
    tab = name
    BestPanel.Refresh()
end

local function Create(page)
    frame = page

    frame.heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -32)
    frame.heading:SetJustifyH("LEFT")

    frame.tabs = {
        vendor = SmallButton(frame, L.BEST_TAB_VENDOR, 76),
        auction = SmallButton(frame, L.BEST_TAB_AUCTION, 76),
    }
    frame.tabs.auction:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -52)
    frame.tabs.vendor:SetPoint("LEFT", frame.tabs.auction, "RIGHT", 4, 0)
    frame.tabs.vendor:SetScript("OnClick", function() SetTab("vendor") end)
    frame.tabs.auction:SetScript("OnClick", function() SetTab("auction") end)

    frame.scan = SmallButton(frame, L.SCAN, 90)
    -- On the heading's line: it's for the whole profession, not the list.
    frame.scan:SetPoint("RIGHT", frame, "TOPRIGHT", -PADDING, -38)
    frame.scan:SetMotionScriptsWhileDisabled(true)
    frame.scan:SetScript("OnClick", function()
        BestCrafts.Scan(Keys(ShownProfessions()))
    end)
    frame.scan:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltip or "", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.scan:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Search: filters the list by name as you type. The game's own search
    -- box (magnifying glass, "Search" placeholder, clear button) where it
    -- exists, a plain input box otherwise.
    local ok, search = pcall(CreateFrame, "EditBox", nil, frame, "SearchBoxTemplate")
    if not ok then
        search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    end
    -- It fills the row between the tabs and Filter (see below).
    search:SetHeight(20)
    search:SetPoint("LEFT", frame.tabs.vendor, "RIGHT", 14, 0)
    search:SetAutoFocus(false)
    -- Hooked, not set, so the template's own placeholder and clear button
    -- keep working.
    search:HookScript("OnTextChanged", function(self)
        local text = (self:GetText() or ""):lower()
        if text ~= filter then
            filter = text
            BestPanel.Refresh()
        end
    end)
    search:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.search = search

    -- Filter: a button in the page's own style that opens the game's menu
    -- of checkboxes under it (clicking it again closes it), and a small red
    -- X at the row's end that clears the filters, grayed out while none are
    -- on. Left out if this client doesn't have the game's menu system; the
    -- search box then runs to the end of the row.
    if MenuUtil and MenuUtil.CreateContextMenu then
        local reset = SmallButton(frame, "", 22)
        reset:SetPoint("RIGHT", frame, "TOPRIGHT", -PADDING, -62)
        reset:SetMotionScriptsWhileDisabled(true)
        reset.icon = reset:CreateTexture(nil, "OVERLAY")
        reset.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        reset.icon:SetSize(12, 12)
        reset.icon:SetPoint("CENTER", reset, "CENTER", 0, 0)
        reset:SetScript("OnClick", function() ResetFilters() end)
        reset:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L.BEST_FILTER_RESET, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        reset:SetScript("OnLeave", function() GameTooltip:Hide() end)
        frame.filterReset = reset

        local button = SmallButton(frame, L.BEST_FILTER, 76)
        button:SetPoint("RIGHT", reset, "LEFT", -4, 0)
        button:SetScript("OnClick", function(self) ToggleFilterMenu(self) end)
        frame.filter = button
        search:SetPoint("RIGHT", button, "LEFT", -8, 0)
    else
        search:SetPoint("RIGHT", frame, "TOPRIGHT", -PADDING, -62)
    end

    -- Column headings over the list; click one to sort by it.
    frame.headings = {}
    -- Placed with the columns (LayOutColumns). Every column but the name is
    -- a number, right-aligned.
    local function Heading(key, text, help)
        local heading = CreateFrame("Button", nil, frame)
        heading.text = heading:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        heading.text:SetAllPoints(heading)
        heading.text:SetJustifyH(key == "name" and "LEFT" or "RIGHT")
        heading.label = text
        heading:SetScript("OnClick", function() SetSort(key) end)
        Tooltip(heading, help or L.BEST_SORT_HELP)
        frame.headings[key] = heading
        return heading
    end
    frame.nameHeading = Heading("name", L.BEST_RECIPE)
    frame.investmentHeading = Heading("investment", L.BEST_INVESTMENT)
    frame.profitHeading = Heading("profit", L.BEST_PROFIT)
    frame.roiHeading = Heading("roi", L.BEST_ROI)
    frame.auctionsHeading = Heading("auctions", L.BEST_AUCTIONS_HEADING,
        L.BEST_AUCTIONS_HELP .. "\n" .. L.BEST_SORT_HELP)
    frame.queuedHeading = Heading("queued", L.BEST_QUEUED_HEADING,
        L.BEST_QUEUED_HELP .. "\n" .. L.BEST_SORT_HELP)

    -- The list scrolls; the mouse wheel works over it.
    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, LIST_TOP)
    frame.list = CreateFrame("Frame", nil, frame.scroll)
    frame.list:SetSize(LIST_WIDTH, ROW_HEIGHT)
    frame.scroll:SetScrollChild(frame.list)

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.status:SetJustifyH("LEFT")
    frame.status:SetWidth(WIDTH - 2 * PADDING)
end

-- Lays the columns out to fit the entries listed (Columns.lua), and places
-- the headings and sets the tab's width when that changes the layout. The
-- rows follow as they're filled (GetRow).
local function LayOutColumns(ranked)
    local extents = {}
    for _, entry in ipairs(ranked) do
        if entry.profit or entry.unpriced.output then
            Columns.Track(extents, "investment", entry.cost)
        end
        Columns.Track(extents, "profit", entry.profit)
        Columns.Track(extents, "roi", entry.profit and entry.roi)
        Columns.Track(extents, "auctions", Auctions.Count(entry.recipe.item))
        Columns.Track(extents, "queued", Queued(entry.recipe.recipeID))
    end
    local key
    col, LIST_WIDTH, key = Columns.Layout(BASE_LIST_WIDTH, {
        { key = "name", heading = L.BEST_RECIPE, sorts = true, fill = true },
        { key = "investment", heading = L.BEST_INVESTMENT, sorts = true, samples = Columns.Money(extents, "investment") },
        { key = "profit", heading = L.BEST_PROFIT, sorts = true, samples = Columns.Money(extents, "profit") },
        { key = "roi", heading = L.BEST_ROI, sorts = true, samples = Columns.Percent(extents, "roi") },
        { key = "auctions", heading = L.BEST_AUCTIONS_HEADING, sorts = true, samples = Columns.Count(extents, "auctions") },
        { key = "queued", heading = L.BEST_QUEUED_HEADING, sorts = true, samples = Columns.Count(extents, "queued") },
        { key = "buttons", width = 2 * ICON_BUTTON_WIDTH + 4 },
    })
    if key == layoutKey then
        return
    end
    layoutKey = key
    WIDTH = LIST_WIDTH + 2 * PADDING + SCROLLBAR_WIDTH
    pageDef.width = WIDTH
    frame.list:SetWidth(LIST_WIDTH)
    for name, heading in pairs(frame.headings) do
        heading:SetSize(col[name].width, 14)
        heading:ClearAllPoints()
        if name == "name" then
            heading:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + col[name].left, LIST_TOP + 16)
        else
            heading:SetPoint("TOPRIGHT", frame, "TOPLEFT", PADDING + LIST_WIDTH + col[name].right, LIST_TOP + 16)
        end
    end
end

local function Refresh()
    local saved = Recipes.Professions()
    local shown = ShownProfessions()
    local keys = Keys(shown)
    local openKey = Recipes.OpenProfession()
    -- One profession shown: its name in the title.
    if #shown == 1 then
        frame.heading:SetText(string.format(L.BEST_TITLE, shown[1].name))
    else
        frame.heading:SetText(L.BEST_TITLE_ALL)
    end

    -- Filter: how many are on, and the reset X while any are.
    if frame.filter then
        local on = 0
        for _, value in pairs(Filters()) do
            if value then
                on = on + 1
            end
        end
        frame.filter:SetText(on > 0 and string.format(L.BEST_FILTER_ON, on) or L.BEST_FILTER)
        frame.filterReset:SetEnabled(on > 0)
        frame.filterReset.icon:SetDesaturated(on == 0)
    end

    -- Tabs: the selected one stays lit.
    for key, button in pairs(frame.tabs) do
        if key == tab then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end

    -- Scan button.
    local scan = frame.scan
    if BestCrafts.IsScanning() and BestCrafts.Scanning() ~= "items" then
        local batch, batches = BestCrafts.Progress()
        scan:SetText(L.BUY_SCANNING)
        scan:SetEnabled(false)
        scan.tooltip = batch and string.format(L.BEST_SCANNING, batch, batches) or L.BUY_SCANNING
    else
        scan:SetText(L.SCAN)
        scan:SetEnabled(#keys > 0 and BestCrafts.CanScan())
        scan.tooltip = BestCrafts.CanScan() and L.BEST_SCAN_HELP or L.BEST_SCAN_OPEN_AH
    end

    -- Headings: the sorted one in white, with an arrow for its direction.
    local sort = Sort()
    for key, heading in pairs(frame.headings) do
        if key == sort.key then
            heading.text:SetText(HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(Columns.SortedText(heading.label, sort.ascending)))
        else
            heading.text:SetText(heading.label)
        end
    end

    local all = {}
    if #keys > 0 then
        all = SortEntries(BestCrafts.Rank(keys, tab, BestPanel.Refresh))
    end
    local ranked, unknownSkillUp = {}, false
    for _, entry in ipairs(all) do
        entry.skillUp, entry.skillUpSaved = Recipes.SkillUp(entry.recipe, openKey)
        if entry.skillUp == nil then
            unknownSkillUp = true
        end
        local name = (C_Item.GetItemInfo(entry.recipe.item) or ""):lower()
        if (filter == "" or name:find(filter, 1, true)) and PassesFilters(entry) then
            ranked[#ranked + 1] = entry
        end
    end
    LayOutColumns(ranked)
    for index, entry in ipairs(ranked) do
        local row = GetRow(index)
        local reason
        row.left:SetText(ItemLabel(entry.recipe.item, entry.skillUp))
        local queued = Queued(entry.recipe.recipeID)
        row.queued:SetText(Count(queued))
        row.auctions:SetText(Count(Auctions.Count(entry.recipe.item)))
        row.roi:SetText("")
        if entry.profit then
            row.investment:SetText(VendorProfit.FormatMoney(entry.cost))
            row.right:SetText(VendorProfit.FormatMoney(entry.profit))
            row.roi:SetText(FormatROI(entry.roi))
        else
            local unpriced = entry.unpriced
            if unpriced.itemID then
                reason = string.format(L.BEST_NO_PRICE_FOR, C_Item.GetItemInfo(unpriced.itemID) or ("item " .. unpriced.itemID))
            elseif tab == "vendor" then
                reason = L.BEST_NO_VENDOR_PRICE
            else
                reason = L.BEST_NO_AUCTION_PRICE
            end
            -- The investment is known when only the sale price is missing;
            -- the reason takes the columns without a number.
            row.right:SetText("")
            if unpriced.output then
                row.investment:SetText(VendorProfit.FormatMoney(entry.cost))
                row.reason:SetWidth(Columns.Span(col, "profit", "roi"))
            else
                row.investment:SetText("")
                row.reason:SetWidth(Columns.Span(col, "investment", "roi"))
            end
        end
        row.reason:SetText(reason and Gray(reason) or "")
        row.left:Show()
        row.investment:Show()
        row.right:Show()
        row.roi:Show()
        row.queued:Show()
        row.auctions:Show()
        row.reason:Show()
        row.hit.recipe = entry.recipe
        row.hit:Show()
        row.queue:SetScript("OnClick", function() QueueRecipe(entry) end)
        row.queue:Show()
        row.unqueue:SetScript("OnClick", function() UnqueueRecipe(entry) end)
        row.unqueue:SetEnabled(queued > 0)
        row.unqueue:Show()
    end
    for index = #ranked + 1, #rows do
        local row = rows[index]
        row.left:Hide()
        row.investment:Hide()
        row.right:Hide()
        row.roi:Hide()
        row.queued:Hide()
        row.auctions:Hide()
        row.reason:Hide()
        row.hit.recipe = nil
        row.hit:Hide()
        row.queue:Hide()
        row.unqueue:Hide()
    end

    -- The list shows up to VISIBLE_ROWS at a time and scrolls for the rest,
    -- back to the top for another profession or tab.
    local listHeight = math.max(math.min(#ranked, VISIBLE_ROWS), 1) * ROW_HEIGHT
    frame.list:SetHeight(math.max(#ranked, 1) * ROW_HEIGHT)
    frame.scroll:SetSize(LIST_WIDTH, listHeight)
    frame.scroll:SetShown(#ranked > 0)
    local listKey = table.concat(keys, ",") .. "/" .. tab .. "/" .. filter
    if listKey ~= shownList then
        shownList = listKey
        frame.scroll:SetVerticalScroll(0)
    end
    local y = #ranked > 0 and LIST_TOP - listHeight or LIST_TOP

    -- Status: why the list is empty, where prices are from, and messages.
    local lines = {}
    if #saved == 0 then
        lines[#lines + 1] = L.BEST_OPEN_PROFESSION
    elseif #keys == 0 then
        lines[#lines + 1] = L.BEST_NO_MATCH_FILTERS
    elseif #all == 0 then
        lines[#lines + 1] = L.BEST_NONE
    elseif #ranked == 0 and filter ~= "" then
        lines[#lines + 1] = string.format(L.BEST_NO_MATCH, frame.search:GetText() or "")
    elseif #ranked == 0 then
        lines[#lines + 1] = L.BEST_NO_MATCH_FILTERS
    end
    if SkillFilterActive() and unknownSkillUp then
        lines[#lines + 1] = L.BEST_SKILL_UNKNOWN
    end
    local liveTime = #keys > 0 and BestCrafts.LiveTime(keys)
    if liveTime then
        lines[#lines + 1] = string.format(L.BEST_LIVE_PRICES, date("%H:%M", liveTime))
    elseif #keys > 0 then
        lines[#lines + 1] = L.BEST_AUCTIONATOR_PRICES
    end
    local text, isError = BestCrafts.Message()
    if text then
        lines[#lines + 1] = isError and RED_FONT_COLOR:WrapTextInColorCode(text) or text
    end
    frame.status:ClearAllPoints()
    frame.status:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y - 8)
    frame.status:SetText(table.concat(lines, "\n"))
    return -y + 8 + (frame.status:GetStringHeight() or 12) + PADDING
end

function BestPanel.Refresh()
    if Panel.IsShown() and Panel.ActiveTab() == "best" then
        Panel.Refresh()
    end
end

Auctions.OnChange(BestPanel.Refresh)

pageDef = {
    name = "best",
    icon = "Interface\\Icons\\INV_Misc_Coin_02",
    label = L.TAB_BEST,
    create = Create,
    width = WIDTH,
    refresh = function() return Refresh() end,
}
Panel.AddPage(pageDef)

-- The rows shown, as "left | right" text (for tests and debugging), and the
-- tab and Scan buttons.
function BestPanel.Lines()
    local lines = {}
    for _, row in ipairs(rows) do
        if row.left:IsShown() then
            local right = row.reason:GetText() ~= "" and row.reason:GetText() or row.right:GetText()
            lines[#lines + 1] = row.left:GetText() .. " | " .. right
        end
    end
    return lines
end

-- A row's regions: left, investment, right (profit), roi, reason, show,
-- queue.
-- For tests and debugging.
function BestPanel.Row(index)
    return rows[index]
end

function BestPanel.Scroll()
    return frame and frame.scroll
end

function BestPanel.Frame()
    return frame
end

function BestPanel.IsShown()
    return Panel.IsShown() and Panel.ActiveTab() == "best"
end

function BestPanel.Tab()
    return tab
end

BestCrafts.OnChange(BestPanel.Refresh)
-- Auctionator's prices changing (its scans, or saving browse results).
if Auctionator.API.v1.RegisterForDBUpdate then
    Auctionator.API.v1.RegisterForDBUpdate(ADDON_NAME, BestPanel.Refresh)
end

local events = CreateFrame("Frame")
-- Closing the professions window leaves it open; it says to open one.
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "BAG_UPDATE_DELAYED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", BestPanel.Refresh)

-- The Vendor Profit button in the professions window's title bar, left of
-- TradeSkillMaster's button there (TSM's: 50 from the right edge, about 57
-- wide, 14 high, 4 down), with the same gap and height, so it reads as
-- being about the whole profession rather than the selected recipe. Opens
-- the Best Crafts tab.
local TITLE_BUTTON_RIGHT = -111
local TITLE_BUTTON_TOP = -4
local TITLE_BUTTON_HEIGHT = 15

local titleButton

local function CreateTitleButton()
    if titleButton or ProfessionsFrame == nil then
        return
    end
    titleButton = CreateFrame("Button", "VendorProfitProfessionsButton", ProfessionsFrame, "UIPanelButtonTemplate")
    titleButton:SetSize(96, TITLE_BUTTON_HEIGHT)
    titleButton:SetText(L.BEST_BUTTON)
    titleButton:SetPoint("TOPRIGHT", ProfessionsFrame, "TOPRIGHT", TITLE_BUTTON_RIGHT, TITLE_BUTTON_TOP)
    -- The window's border and title art sit hundreds of levels above the
    -- window itself; stay above them, level with the close button.
    local level = ProfessionsFrame:GetFrameLevel()
    local close = ProfessionsFrame.CloseButton
    if close then
        level = math.max(level, close:GetFrameLevel())
    end
    titleButton:SetFrameLevel(math.max(level, 500) + 2)
    titleButton:SetScript("OnClick", function() Panel.Toggle("best") end)
    titleButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.BEST_BUTTON)
        GameTooltip:AddLine(L.BEST_BUTTON_HELP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    titleButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    titleButton:Show()
end

-- The professions window is load-on-demand: made when its addon loads, or
-- when a profession opens (just after, in case the window is made in the
-- same event).
local titleEvents = CreateFrame("Frame")
pcall(titleEvents.RegisterEvent, titleEvents, "ADDON_LOADED")
pcall(titleEvents.RegisterEvent, titleEvents, "TRADE_SKILL_SHOW")
titleEvents:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "Blizzard_Professions" then
        return
    end
    CreateTitleButton()
    C_Timer.After(0, CreateTitleButton)
end)
CreateTitleButton()

function BestPanel.TitleButton()
    return titleButton
end
