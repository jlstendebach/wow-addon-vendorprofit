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
local OpenButton = VendorProfit.OpenButton
local ProfessionCycle = VendorProfit.ProfessionCycle
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
-- The minimums row, at the bottom of the window, under the notes.
local MINIMUMS_HEIGHT = 20
-- How many rows the list shows before it scrolls: 14 until you drag the
-- window's size grip (Create), then what you chose, saved per character.
local DEFAULT_ROWS = 14
local SCROLLBAR_WIDTH = 24
local BASE_LIST_WIDTH = WIDTH - 2 * PADDING - SCROLLBAR_WIDTH
local LIST_WIDTH = BASE_LIST_WIDTH
local ICON_BUTTON_WIDTH = 22
-- Room for the size grip at the end of the bottom row (16, and a gap).
local GRIP_ROOM = 24
-- The minimum boxes' widths: 4 digits or 2, each with its unit inside.
BestPanel.MIN_BOX_WIDE = 47
BestPanel.MIN_BOX_NARROW = 33
-- The columns, by key (Columns.lua), laid out for what's listed on each
-- refresh: the recipe name (the favorite star inside it, first),
-- Investment, Profit, Profit/hr, ROI, 7d (sold at auction in the last 7
-- days, in orange for hot ones), AH (your auctions of it), Q (crafts
-- queued), then - and + (unqueue and queue a craft). The layout key changes
-- only when the layout does.
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
-- How the list prices crafts: along each one's cheapest route (its
-- reagents crafted where that's cheaper), or as the exact recipe (its
-- reagents bought, never crafted, as Auctionator prices it). Saved per
-- character; the Cheapest and Exact buttons pick it.
local function Exact()
    return VendorProfitCharDB ~= nil and VendorProfitCharDB.bestExact == true
end

local function SetExact(exact)
    VendorProfitCharDB = VendorProfitCharDB or {}
    VendorProfitCharDB.bestExact = exact or nil
    BestPanel.Refresh()
end

-- The recipe whose row is shown the other way (cheapest route or exact
-- recipe) while Ctrl is held with the mouse on it; nil for none.
local exactRecipe

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

-- Money in the list's columns: two coins at most, so gold amounts drop
-- their copper (1g 20s 94c shows as 1g 20s) and the columns stay narrow.
-- Cut off, not rounded, so a figure is never more than it really is (Josh
-- would rather underestimate). Only the shown text: sorting, filters and
-- the minimums use the exact amount, and tooltips and the Shopping List
-- keep the copper.
local function ListMoney(copper)
    copper = math.floor(copper + 0.5)
    local size = math.abs(copper)
    if size >= 10000 then
        size = size - size % 100
    end
    return VendorProfit.FormatMoney(copper < 0 and -size or size)
end
BestPanel.ListMoney = ListMoney

-- Hot crafts (History.Heat): their 7d count in orange, the game's legendary
-- color. An icon was tried and dropped: it pulled the eye from the names.
local HOT_COLOR = CreateColor(1, 0.5, 0)
BestPanel.HOT_COLOR = HOT_COLOR

-- How the item has been selling at auction lately: { heat, sold, perDay,
-- hot }, or nil if it hasn't sold there within the heat's reach.
local function Heat(itemID)
    return VendorProfit.History.Heat()[itemID]
end

-- Sold at auction in the last 7 days.
local function Sold(itemID)
    local heat = Heat(itemID)
    return heat and heat.sold or 0
end

local function IsHot(itemID)
    local heat = Heat(itemID)
    return heat ~= nil and heat.hot == true
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

-- Favorite recipes, saved per character: { [recipeID] = true }. They're
-- listed first, sorted among themselves by the same column.
local function IsFavorite(recipeID)
    local db = VendorProfitCharDB
    return db ~= nil and type(db.bestFavorites) == "table" and db.bestFavorites[recipeID] == true
end

local function SetFavorite(recipeID, favorite)
    VendorProfitCharDB = VendorProfitCharDB or {}
    VendorProfitCharDB.bestFavorites = VendorProfitCharDB.bestFavorites or {}
    VendorProfitCharDB.bestFavorites[recipeID] = favorite or nil
    if next(VendorProfitCharDB.bestFavorites) == nil then
        VendorProfitCharDB.bestFavorites = nil
    end
end

-- The star: the auction house's favorite star, or the star raid marker if
-- this client hasn't that atlas. A favorite's is always shown; the others'
-- only while the mouse is on the row (as TradeSkillMaster's crafting list
-- does), faded, so 14 empty stars don't clutter the list.
local STAR_ATLAS = "auctionhouse-icon-favorite"
-- The star is the first thing in the name column, where the heading starts,
-- and the names follow it: every row's left edge lines up with the heading
-- and the window, whether its star shows or not. It's as tall as the item
-- icon after it (an inline |T:0|t icon is the font's height), so the two
-- sit on the same line; set from the font with the first row.
local STAR_GAP = 4
local starWidth, starHeight, nameIndent = 12, 12, 16
local function SizeStar(fontString)
    local _, fontHeight = fontString:GetFont()
    starHeight = math.floor((fontHeight or 12) + 0.5)
    -- Keeps the atlas's own shape.
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(STAR_ATLAS)
    starWidth = info and info.width and info.height and info.height > 0
        and math.floor(starHeight * info.width / info.height + 0.5) or starHeight
    nameIndent = starWidth + STAR_GAP
end

-- The favorites and the rest are set apart by a gold line with equal room
-- above and below it. A row's buttons fill its top 20 of 22, so the space
-- between the two groups is 2 + DIVIDER_GAP: 4 above the line, the line,
-- 4 below.
local DIVIDER_GAP = 7
local DIVIDER_SPACE = 4

-- The window's height besides the list's rows: the controls above it, the
-- divider's gap (always allowed for, so favorites don't change the
-- height), and the notes (one line) and minimums under it.
local function ChromeHeight()
    return -LIST_TOP + DIVIDER_GAP + 8 + MINIMUMS_HEIGHT + 8 + 12 + PADDING
end

-- The fewest rows: the window stays tall enough for the side tabs, and a
-- list shorter than that would leave a gap under it.
local function MinRows()
    return math.max(1, math.ceil((Panel.MinHeight() - ChromeHeight()) / ROW_HEIGHT))
end

local function VisibleRows()
    local db = VendorProfitCharDB
    local rows = db and tonumber(db.bestRows) or DEFAULT_ROWS
    return math.max(math.floor(rows), MinRows())
end

-- Where the index-th row's top is, the rows after the favorites pushed down
-- by the gap (favorites: how many lead the list, while a divider shows).
local function RowTop(index, favorites)
    local top = -(index - 1) * ROW_HEIGHT
    if favorites and index > favorites then
        top = top - DIVIDER_GAP
    end
    return top
end
local function ShowStar(row)
    local star = row.favorite
    local favorite = star.recipe ~= nil and IsFavorite(star.recipe.recipeID)
    star.icon:SetDesaturated(not favorite)
    star.icon:SetAlpha(favorite and 1 or 0.5)
    star:SetAlpha((favorite or row.hovered) and 1 or 0)
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
-- Queued the way the list prices it; Ctrl-click: the other way (exact
-- recipe, as the exact Queue button under Auctionator's line queues it, or
-- cheapest route), the same view Ctrl shows on the row.
local function QueueRecipe(entry)
    local recipe = entry.recipe
    local crafts = VendorProfit.QueueStep()
    local exact = Exact() ~= (IsControlKeyDown() and true or false)
    Order.AddRecipe({
        itemID = recipe.item, recipeID = recipe.recipeID, profession = recipe.profession,
        count = recipe.count, reagents = recipe.reagents,
        sellPrice = select(11, C_Item.GetItemInfo(recipe.item)),
        exact = exact,
    }, crafts)
    local name = C_Item.GetItemInfo(recipe.item) or ("item " .. recipe.item)
    print(string.format(L.QUEUED, crafts, exact and (name .. " " .. L.QUEUED_EXACT_MARK) or name))
end

-- Takes one craft of a recipe off the shopping order (five with Shift), and
-- the recipe once none are left.
-- Ctrl-click: only from the entry queued the other way from the list.
local function UnqueueRecipe(entry)
    local step = VendorProfit.QueueStep()
    local otherOnly = IsControlKeyDown()
    local other = not Exact()
    local entries = Order.Entries()
    for index = #entries, 1, -1 do
        local queued = entries[index]
        if queued.recipeID == entry.recipe.recipeID and (not otherOnly or (queued.exact == true) == other) then
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

-- Rows live on the scroll child, frame.list, one ROW_HEIGHT apart (top:
-- RowTop's).
local function GetRow(index, top)
    local row = rows[index]
    if row == nil then
        local list = frame.list
        row = {}
        local function Column()
            local text = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetJustifyH("RIGHT")
            text:SetWordWrap(false)
            return text
        end
        row.left = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if index == 1 then
            SizeStar(row.left)
        end
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
            row.hovered = true
            ShowStar(row)
            if self.recipe then
                BestPanel.ShowSalesTooltip(self, row.left, self.recipe.item, self.recipe, self.entry)
            end
        end)
        row.hit:SetScript("OnLeave", function()
            row.hovered = false
            ShowStar(row)
            GameTooltip:Hide()
        end)
        -- The favorite star, before the name, centered on its line of text.
        -- Hidden by alpha, not Hide, so it still hears the mouse and shows
        -- itself.
        row.favorite = CreateFrame("Button", nil, list)
        row.favorite:SetPoint("RIGHT", row.left, "LEFT", -STAR_GAP, 0)
        row.favorite:SetSize(starWidth, starHeight)
        row.favorite.icon = row.favorite:CreateTexture(nil, "ARTWORK")
        row.favorite.icon:SetAllPoints(row.favorite)
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(STAR_ATLAS) then
            row.favorite.icon:SetAtlas(STAR_ATLAS)
        else
            row.favorite.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
        end
        row.favorite:SetScript("OnClick", function(self)
            if self.recipe then
                SetFavorite(self.recipe.recipeID, not IsFavorite(self.recipe.recipeID))
                BestPanel.Refresh()
            end
        end)
        row.favorite:SetScript("OnEnter", function(self)
            row.hovered = true
            ShowStar(row)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.recipe and IsFavorite(self.recipe.recipeID) and L.BEST_UNFAVORITE_HELP
                or L.BEST_FAVORITE_HELP, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row.favorite:SetScript("OnLeave", function()
            row.hovered = false
            ShowStar(row)
            GameTooltip:Hide()
        end)
        -- Investment: what one craft's items cost along the cheapest route.
        row.investment = Column()
        row.right = Column()
        -- Profit an hour, crafting it back to back.
        row.perHour = Column()
        -- Return on investment: profit as a share of the investment.
        row.roi = Column()
        -- How many sold at auction in the last 7 days, a flame if hot.
        row.sold = Column()
        -- How many of what it makes you have up for auction (Auctions.lua).
        row.auctions = Column()
        -- How many crafts the shopping order holds.
        row.queued = Column()
        -- Why a recipe isn't ranked, across the columns it has no number for.
        row.reason = Column()
        -- The whole row, to tell which row the mouse is on (for Ctrl). Not
        -- mouse-enabled, so the name, star and buttons still get the mouse.
        row.area = CreateFrame("Frame", nil, list)

        -- Queue: a plus, at the row's end; unqueue: a minus, before it.
        row.queue = SmallButton(list, "+", ICON_BUTTON_WIDTH)
        Tooltip(row.queue, L.BEST_QUEUE_HELP)
        row.unqueue = SmallButton(list, "-", ICON_BUTTON_WIDTH)
        row.unqueue:SetPoint("RIGHT", row.queue, "LEFT", -4, 0)
        Tooltip(row.unqueue, L.BEST_UNQUEUE_HELP)
        rows[index] = row
    end
    -- Placed again only when the columns or its place change.
    if row.layoutKey ~= layoutKey or row.top ~= top then
        row.layoutKey, row.top = layoutKey, top
        local list = frame.list
        local function At(region, key)
            region:SetWidth(col[key].width)
            region:ClearAllPoints()
            region:SetPoint("TOPRIGHT", list, "TOPRIGHT", col[key].right, top - 4)
        end
        row.left:SetWidth(col.name.width - nameIndent)
        row.left:ClearAllPoints()
        row.left:SetPoint("TOPLEFT", list, "TOPLEFT", col.name.left + nameIndent, top - 4)
        row.hit:ClearAllPoints()
        row.hit:SetPoint("TOPLEFT", list, "TOPLEFT", col.name.left + nameIndent, top)
        row.hit:SetSize(col.name.width - nameIndent, ROW_HEIGHT)
        row.queue:ClearAllPoints()
        row.queue:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, top)
        row.area:ClearAllPoints()
        row.area:SetPoint("TOPLEFT", list, "TOPLEFT", 0, top)
        row.area:SetSize(LIST_WIDTH, ROW_HEIGHT)
        At(row.investment, "investment")
        At(row.right, "profit")
        At(row.perHour, "perHour")
        At(row.roi, "roi")
        At(row.sold, "sold")
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
    elseif key == "perHour" then
        return entry.perHour or -math.huge
    elseif key == "roi" then
        return entry.roi or -math.huge
    elseif key == "queued" then
        return Queued(entry.recipe.recipeID)
    elseif key == "auctions" then
        return Auctions.Count(entry.recipe.item)
    elseif key == "sold" then
        return Sold(entry.recipe.item)
    end
    return entry.profit
end

-- Orders the ranked entries by the sort; unranked ones stay last as they are.
local function SortGroup(entries)
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
    if sort.key == "queued" or sort.key == "auctions" or sort.key == "sold" then
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

-- Favorites first, then the rest, each sorted the same way.
local function SortEntries(entries)
    local favorites, others = {}, {}
    for _, entry in ipairs(entries) do
        local group = IsFavorite(entry.recipe.recipeID) and favorites or others
        group[#group + 1] = entry
    end
    local sorted = SortGroup(favorites)
    for _, entry in ipairs(SortGroup(others)) do
        sorted[#sorted + 1] = entry
    end
    return sorted
end

local FormatROI = VendorProfit.FormatROI

-- What you've made selling an item, over all time: its Best Sellers figures
-- (Profit History), with the profit and ROIs. Placed like an item's
-- tooltip: above the row, past the end of its name.
-- With a recipe (a row's), it also names the recipe's profession and says
-- when its skill-up color is saved rather than live; with the row's entry,
-- how many one craft makes and its figures per item (the columns are per
-- craft: what you spend and what a cast earns).
-- Money per item can be a fraction of a copper (a craft of 200): under half
-- a copper shows as "<1c", not 0c, which would read as nothing.
local function PerItemMoney(copper)
    if copper > 0 and copper < 0.5 then
        return "<" .. VendorProfit.FormatMoney(1)
    elseif copper < 0 and copper > -0.5 then
        return ">" .. VendorProfit.FormatMoney(-1)
    end
    return VendorProfit.FormatMoney(copper)
end
BestPanel.PerItemMoney = PerItemMoney

function BestPanel.ShowSalesTooltip(owner, nameText, itemID, recipe, entry)
    VendorProfit.SetNameTooltipOwner(owner, nameText)
    GameTooltip:SetText(ItemLabel(itemID))
    if recipe then
        GameTooltip:AddLine(recipe.profession, 1, 1, 1)
        local skillUp, saved = Recipes.SkillUp(recipe)
        if skillUp and saved then
            GameTooltip:AddLine(string.format(L.BEST_SKILL_SAVED, recipe.profession),
                GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b, true)
        end
        if recipe.count > 1 then
            GameTooltip:AddLine(string.format(L.BEST_MAKES, recipe.count), 1, 1, 1)
            if entry and entry.profit then
                GameTooltip:AddDoubleLine(L.BEST_INVESTMENT_EACH, PerItemMoney(entry.cost / recipe.count))
                GameTooltip:AddDoubleLine(L.BEST_PROFIT_EACH, PerItemMoney(entry.profit / recipe.count))
            end
        end
    end
    local heat = Heat(itemID)
    if heat and heat.hot then
        GameTooltip:AddLine(string.format(L.BEST_HOT_TOOLTIP, VendorProfit.FormatMoney(math.floor(heat.perDay + 0.5))),
            HOT_COLOR.r, HOT_COLOR.g, HOT_COLOR.b, true)
    end
    if heat and heat.sold > 0 then
        GameTooltip:AddLine(string.format(L.BEST_SOLD_RECENT,
            VendorProfit.HistoryPanel.SoldCount(heat.sold, math.floor(heat.sales + 0.5))), 1, 1, 1)
    end
    local HistoryPanel = VendorProfit.HistoryPanel
    local item = HistoryPanel and HistoryPanel.AllTime(itemID)
    if item and item.n > 0 then
        GameTooltip:AddLine(L.BEST_SALES_TITLE, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
        HistoryPanel.AddSalesLines(item, true)
    else
        GameTooltip:AddLine(L.BEST_NO_SALES, 1, 1, 1, true)
    end
    if recipe then
        GameTooltip:AddLine(Exact() and L.BEST_CHEAPEST_HINT or L.BEST_EXACT_HINT,
            GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b, true)
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

-- The filters, saved per character: { profitable, hot, optimal, medium,
-- easy, prof:<key> }.
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

-- The minimum profit per craft (copper) and ROI (a whole percentage) typed
-- into the boxes above the list, saved per character; 0 for none. They're
-- boxes rather than Filter menu entries because they take exact amounts.
-- Returns the minimum profit, ROI and profit an hour (copper).
local function Minimums()
    local db = VendorProfitCharDB
    local saved = db and type(db.bestMinimums) == "table" and db.bestMinimums or {}
    return saved.profit or 0, saved.roi or 0, saved.perHour or 0
end

local function SetMinimums(profit, roi, perHour)
    VendorProfitCharDB = VendorProfitCharDB or {}
    if profit > 0 or roi > 0 or perHour > 0 then
        VendorProfitCharDB.bestMinimums = {
            profit = profit > 0 and profit or nil,
            roi = roi > 0 and roi or nil,
            perHour = perHour > 0 and perHour or nil,
        }
    else
        VendorProfitCharDB.bestMinimums = nil
    end
    BestPanel.Refresh()
end

-- Shows the saved minimums in the boxes (0 for none).
local function ShowMinimums()
    if frame == nil or frame.minimums == nil then
        return
    end
    local profit, roi, perHour = Minimums()
    local boxes = frame.minimums
    boxes.gold:SetText(tostring(math.floor(profit / 10000)))
    boxes.silver:SetText(tostring(math.floor(profit / 100) % 100))
    boxes.copper:SetText(tostring(profit % 100))
    boxes.hourGold:SetText(tostring(math.floor(perHour / 10000)))
    boxes.hourSilver:SetText(tostring(math.floor(perHour / 100) % 100))
    boxes.roi:SetText(tostring(roi))
end

ResetFilters = function()
    if VendorProfitCharDB then
        VendorProfitCharDB.bestFilters = nil
        VendorProfitCharDB.bestMinimums = nil
    end
    ShowMinimums()
    BestPanel.Refresh()
end

-- Whether an entry passes the filters. Skill-up filters show recipes of the
-- checked colors; a recipe whose color isn't known can't pass them. A
-- recipe with no profit to rank can't meet a minimum. ROI is compared as
-- shown, a whole percentage.
local function PassesFilters(entry)
    local filters = Filters()
    if filters.profitable and not (entry.profit and entry.profit > 0) then
        return false
    end
    if filters.hot and not IsHot(entry.recipe.item) then
        return false
    end
    local minProfit, minRoi, minPerHour = Minimums()
    if minProfit > 0 and not (entry.profit and entry.profit >= minProfit) then
        return false
    end
    -- A recipe with no Profit/hr (no cast time) can't meet it either.
    if minPerHour > 0 and not (entry.perHour and entry.perHour >= minPerHour) then
        return false
    end
    if minRoi > 0 and not (entry.profit and entry.roi and math.floor(entry.roi * 100 + 0.5) >= minRoi) then
        return false
    end
    if SkillFilterActive() then
        return entry.skillUp ~= nil and filters[entry.skillUp] == true
    end
    return true
end

-- The Filter menu: profitable only, hot only, the skill-up colors (with a note that
-- they're as of each profession's last opening), then the professions, each
-- ticked while it's shown.
FilterMenu = function(_, root)
    root:CreateCheckbox(L.BEST_FILTER_PROFITABLE,
        function() return Filters().profitable == true end,
        function() SetFilter("profitable", not Filters().profitable) end)
    root:CreateCheckbox(L.BEST_FILTER_HOT,
        function() return Filters().hot == true end,
        function() SetFilter("hot", not Filters().hot) end)
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

    -- How to make it, beside how to sell it: they change the same columns.
    frame.modes = {
        cheapest = SmallButton(frame, L.BEST_MODE_CHEAPEST, 76),
        exact = SmallButton(frame, L.BEST_MODE_EXACT, 76),
    }
    frame.modes.cheapest:SetPoint("LEFT", frame.tabs.vendor, "RIGHT", 14, 0)
    frame.modes.exact:SetPoint("LEFT", frame.modes.cheapest, "RIGHT", 4, 0)
    frame.modes.cheapest:SetScript("OnClick", function() SetExact(false) end)
    frame.modes.exact:SetScript("OnClick", function() SetExact(true) end)
    Tooltip(frame.modes.cheapest, L.BEST_MODE_CHEAPEST_HELP)
    Tooltip(frame.modes.exact, L.BEST_MODE_EXACT_HELP)

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

    -- Professions: click it again and again to open each of your
    -- professions in turn, saving their recipes, then close the window
    -- (ProfessionCycle.lua). Opening goes through the secure cover, laid
    -- over it while the mouse is on it (OpenButton.lua).
    frame.professions = SmallButton(frame, L.PROFESSIONS_BUTTON, 90)
    frame.professions:SetPoint("RIGHT", frame.scan, "LEFT", -4, 0)
    frame.professions:SetMotionScriptsWhileDisabled(true)
    frame.professions:SetScript("OnClick", function()
        if ProfessionCycle.State().action == "close" then
            ProfessionCycle.Close()
        end
    end)
    frame.professions:SetScript("OnEnter", function(self)
        local state = ProfessionCycle.State()
        if state.action == "open" and not InCombatLockdown() then
            OpenButton.Cover(self, state.entry.name, function() ProfessionCycle.Opened(state.entry) end, self.tooltip)
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltip or "", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.professions:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Search: filters the list by name as you type. The game's own search
    -- box (magnifying glass, "Search" placeholder, clear button) where it
    -- exists, a plain input box otherwise.
    local ok, search = pcall(CreateFrame, "EditBox", nil, frame, "SearchBoxTemplate")
    if not ok then
        search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    end
    -- It fills the row between the tabs and Filter (see below).
    search:SetHeight(20)
    search:SetPoint("LEFT", frame.modes.exact, "RIGHT", 14, 0)
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

    -- Minimums, on a row under the list (placed in Refresh): profit in
    -- gold, silver and copper boxes, and ROI, each a number box like the
    -- search box with its unit inside. 0 is no minimum. Changes apply as you
    -- type.
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(WIDTH - 2 * PADDING, MINIMUMS_HEIGHT)
    frame.minimums = row
    local function Changed(_, userInput)
        if userInput then
            local function Number(box)
                return math.floor(tonumber(row[box]:GetText() or "") or 0)
            end
            local profit = Number("gold") * 10000 + Number("silver") * 100 + Number("copper")
            local perHour = Number("hourGold") * 10000 + Number("hourSilver") * 100
            SetMinimums(profit, Number("roi"), perHour)
        end
    end
    local function Help(region, text)
        region:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        region:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    -- A label, after the previous box (or first in the row).
    local function Text(after, text, gap)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if after then
            label:SetPoint("LEFT", after, "RIGHT", gap, 0)
        else
            label:SetPoint("LEFT", row, "LEFT", 0, 0)
        end
        label:SetText(text)
        return label
    end
    -- A number box like the search box (the same template underneath, the
    -- same height and font, text from the left), with its unit inside at
    -- the right (a coin icon, or %), the text stopping short of it.
    local UNIT_SPACE = 17
    local function Box(key, after, gap, width, letters, unit, help)
        local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        box:SetSize(width, MINIMUMS_HEIGHT)
        -- The template's border reaches a few pixels left of the box, so the
        -- gap is measured as for the search box beside the Vendor tab.
        box:SetPoint("LEFT", after, "RIGHT", gap, 0)
        box:SetAutoFocus(false)
        box:SetNumeric(true)
        box:SetMaxLetters(letters)
        box:SetTextInsets(0, UNIT_SPACE, 0, 0)
        local mark
        if unit.texture then
            mark = box:CreateTexture(nil, "OVERLAY")
            mark:SetTexture(unit.texture)
            mark:SetSize(11, 11)
        else
            mark = box:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
            mark:SetText(unit.text)
            mark:SetTextColor(0.6, 0.6, 0.6)
        end
        mark:SetPoint("RIGHT", box, "RIGHT", -4, 0)
        box.unit = mark
        box:HookScript("OnTextChanged", Changed)
        box:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)
        box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
        -- Left empty: back to 0.
        box:HookScript("OnEditFocusLost", function(self)
            if (self:GetText() or "") == "" then
                self:SetText("0")
            end
        end)
        Help(box, help)
        row[key] = box
        return box
    end
    local COIN = "Interface\\MoneyFrame\\UI-%sIcon"
    -- Up to 9,999 gold and 9,999%. Boxes are as wide as their digits and
    -- unit need (4 digits, or 2, then the unit's space), and nearly touching
    -- (each border reaches 5px outside it). They were 52 and 36, which left
    -- a visible gap between the digits and the unit.
    local WIDE, NARROW = BestPanel.MIN_BOX_WIDE, BestPanel.MIN_BOX_NARROW
    local gold = Box("gold", Text(nil, L.BEST_MIN_PROFIT), 10, WIDE, 4, { texture = COIN:format("Gold") }, L.BEST_MIN_PROFIT_HELP)
    local silver = Box("silver", gold, 9, NARROW, 2, { texture = COIN:format("Silver") }, L.BEST_MIN_PROFIT_HELP)
    local copper = Box("copper", silver, 9, NARROW, 2, { texture = COIN:format("Copper") }, L.BEST_MIN_PROFIT_HELP)
    -- Profit an hour in gold and silver: copper is noise at an hour's scale.
    local hourGold = Box("hourGold", Text(copper, L.BEST_MIN_PER_HOUR, 24), 10, WIDE, 4, { texture = COIN:format("Gold") },
        L.BEST_MIN_PER_HOUR_HELP)
    local hourSilver = Box("hourSilver", hourGold, 9, NARROW, 2, { texture = COIN:format("Silver") }, L.BEST_MIN_PER_HOUR_HELP)
    Box("roi", Text(hourSilver, L.BEST_MIN_ROI, 24), 10, WIDE, 4, { text = "%" }, L.BEST_MIN_ROI_HELP)
    -- The window is at least as wide as the row (and the size grip after
    -- it), however narrow the columns are.
    local rowWidth = 0
    for _, part in ipairs({
        { Columns.Measure(L.BEST_MIN_PROFIT, "GameFontNormalSmall"), 10, WIDE, 9, NARROW, 9, NARROW },
        { 24, Columns.Measure(L.BEST_MIN_PER_HOUR, "GameFontNormalSmall"), 10, WIDE, 9, NARROW },
        { 24, Columns.Measure(L.BEST_MIN_ROI, "GameFontNormalSmall"), 10, WIDE },
    }) do
        for _, width in ipairs(part) do
            rowWidth = rowWidth + width
        end
    end
    BASE_LIST_WIDTH = math.max(BASE_LIST_WIDTH, rowWidth + GRIP_ROOM - SCROLLBAR_WIDTH)
    ShowMinimums()

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
    frame.perHourHeading = Heading("perHour", L.BEST_PER_HOUR, L.BEST_PER_HOUR_HELP .. "\n" .. L.BEST_SORT_HELP)
    frame.roiHeading = Heading("roi", L.BEST_ROI)
    frame.soldHeading = Heading("sold", L.BEST_SOLD_HEADING,
        L.BEST_SOLD_HELP .. "\n" .. L.BEST_SORT_HELP)
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
    -- A line between the favorites and the rest, in the gold of the
    -- Shopping List's dividers.
    frame.favoritesDivider = frame.list:CreateTexture(nil, "ARTWORK")
    frame.favoritesDivider:SetColorTexture(1, 0.82, 0, 0.35)
    frame.favoritesDivider:SetHeight(1)
    frame.favoritesDivider:Hide()

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.status:SetJustifyH("LEFT")
    frame.status:SetWidth(WIDTH - 2 * PADDING)

    -- The size grip, in the bottom right corner: drag it up or down to show
    -- fewer or more rows. Height only (the width follows the columns), a
    -- whole row at a time so no row is cut off. It works out the rows from
    -- how far the mouse has moved rather than using the game's frame
    -- sizing, which would fight the height each refresh sets. Never shorter
    -- than the side tabs need, nor past the bottom of the screen.
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    local function CursorY()
        local _, y = GetCursorPosition()
        return y / frame:GetEffectiveScale()
    end
    local function Drag(self)
        local maxRows = math.max(MinRows(), math.floor((frame:GetTop() - ChromeHeight()) / ROW_HEIGHT))
        local rows = self.startRows + math.floor((self.startY - CursorY()) / ROW_HEIGHT + 0.5)
        rows = math.min(math.max(rows, MinRows()), maxRows)
        if rows ~= VisibleRows() then
            VendorProfitCharDB = VendorProfitCharDB or {}
            VendorProfitCharDB.bestRows = rows
            BestPanel.Refresh()
        end
    end
    grip:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton == "LeftButton" then
            self.startY, self.startRows = CursorY(), VisibleRows()
            self:SetScript("OnUpdate", Drag)
        end
    end)
    grip:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    -- Let go off the window, or the window hidden mid-drag: stop too.
    grip:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    Tooltip(grip, L.BEST_RESIZE_HELP)
    frame.grip = grip

    -- Ctrl on a row shows it as the exact recipe. Checked every frame while
    -- the tab is up (no event says the mouse moved between rows), but only
    -- the cheap Ctrl check unless Ctrl is held or a row is showing it.
    frame:SetScript("OnUpdate", function()
        BestPanel.UpdateExact()
    end)
    frame:HookScript("OnHide", function()
        exactRecipe = nil
    end)
end

-- Which row, if any, should show the exact recipe: the one under the mouse
-- while Ctrl is held. Redraws when that changes.
function BestPanel.UpdateExact()
    local recipeID
    if IsControlKeyDown() and frame.scroll:IsShown() and frame.scroll:IsMouseOver() then
        for _, row in ipairs(rows) do
            if row.entry and row.area:IsMouseOver() then
                recipeID = row.entry.recipe.recipeID
                break
            end
        end
    end
    if recipeID ~= exactRecipe then
        exactRecipe = recipeID
        BestPanel.Refresh()
    end
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
        Columns.Track(extents, "perHour", entry.perHour)
        Columns.Track(extents, "roi", entry.profit and entry.roi)
        Columns.Track(extents, "sold", Sold(entry.recipe.item))
        Columns.Track(extents, "auctions", Auctions.Count(entry.recipe.item))
        Columns.Track(extents, "queued", Queued(entry.recipe.recipeID))
    end
    local key
    col, LIST_WIDTH, key = Columns.Layout(BASE_LIST_WIDTH, {
        { key = "name", heading = L.BEST_RECIPE, sorts = true, fill = true },
        { key = "investment", heading = L.BEST_INVESTMENT, sorts = true, samples = Columns.Money(extents, "investment", ListMoney) },
        { key = "profit", heading = L.BEST_PROFIT, sorts = true, samples = Columns.Money(extents, "profit", ListMoney) },
        { key = "perHour", heading = L.BEST_PER_HOUR, sorts = true, samples = Columns.Money(extents, "perHour", ListMoney) },
        { key = "roi", heading = L.BEST_ROI, sorts = true, samples = Columns.Percent(extents, "roi") },
        { key = "sold", heading = L.BEST_SOLD_HEADING, sorts = true, samples = Columns.Count(extents, "sold") },
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
        -- The X clears the minimums too.
        local minProfit, minRoi, minPerHour = Minimums()
        local any = on > 0 or minProfit > 0 or minRoi > 0 or minPerHour > 0
        frame.filterReset:SetEnabled(any)
        frame.filterReset.icon:SetDesaturated(not any)
    end

    -- Tabs: the selected one stays lit.
    for key, button in pairs(frame.tabs) do
        if key == tab then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end
    for key, button in pairs(frame.modes) do
        if (key == "exact") == Exact() then
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

    -- Professions button: what the next click does.
    local professions, state = frame.professions, ProfessionCycle.State()
    local text, enabled, tooltip = L.PROFESSIONS_BUTTON, false, nil
    if state.action == "open" then
        if state.started then
            text = string.format(L.PROFESSIONS_NEXT, state.index, state.count)
        end
        enabled = not InCombatLockdown()
        tooltip = enabled and string.format(L.PROFESSIONS_OPEN_HELP, state.entry.name, state.index, state.count)
            or L.PROFESSIONS_COMBAT
    elseif state.action == "wait" then
        text, tooltip = L.OPENING_LABEL, string.format(L.OPENING_HELP, state.entry.name)
    elseif state.action == "close" then
        text, enabled, tooltip = L.PROFESSIONS_CLOSE, true, L.PROFESSIONS_CLOSE_HELP
    elseif state.action == "rest" then
        tooltip = L.PROFESSIONS_REST
    else
        tooltip = L.PROFESSIONS_NONE
    end
    professions:SetText(text)
    professions:SetEnabled(enabled)
    professions.tooltip = tooltip
    -- The mouse on it as it becomes ready to open the next one: cover it
    -- now, as its OnEnter would.
    if state.action == "open" and enabled and OpenButton.HasMouse(professions) then
        OpenButton.Cover(professions, state.entry.name, function() ProfessionCycle.Opened(state.entry) end, tooltip)
    else
        OpenButton.Uncover(professions)
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
        all = SortEntries(BestCrafts.Rank(keys, tab, BestPanel.Refresh, Exact()))
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
    -- What each row shows: its entry, or with Ctrl held on it, the exact
    -- recipe's. Only the numbers change: the row keeps its place, and the
    -- filters still go by the cheapest route.
    local shownEntries = {}
    for index, entry in ipairs(ranked) do
        if entry.recipe.recipeID == exactRecipe then
            shownEntries[index] = BestCrafts.PriceRecipe(entry.recipe, tab, BestPanel.Refresh, not Exact())
            shownEntries[index].other = true
        else
            shownEntries[index] = entry
        end
    end
    LayOutColumns(shownEntries)
    -- How many favorites lead the list, while there are others after them
    -- to set them apart from (nil otherwise).
    local favorites = 0
    for _, entry in ipairs(ranked) do
        if IsFavorite(entry.recipe.recipeID) then
            favorites = favorites + 1
        end
    end
    if favorites == 0 or favorites == #ranked then
        favorites = nil
    end
    for index, ranking in ipairs(ranked) do
        local entry = shownEntries[index]
        local row = GetRow(index, RowTop(index, favorites))
        local reason
        local label = ItemLabel(entry.recipe.item, ranking.skillUp)
        -- Shown the other way (Ctrl): marked which.
        if entry.other then
            label = label .. " " .. Gray(entry.exact and L.QUEUED_EXACT_MARK or L.BEST_CHEAPEST_MARK)
        end
        row.left:SetText(label)
        row.entry = ranking
        local queued = Queued(entry.recipe.recipeID)
        row.queued:SetText(Count(queued))
        row.auctions:SetText(Count(Auctions.Count(entry.recipe.item)))
        local sold = Sold(entry.recipe.item)
        row.sold:SetText(IsHot(entry.recipe.item) and HOT_COLOR:WrapTextInColorCode(sold) or Count(sold))
        row.roi:SetText("")
        if entry.profit then
            row.investment:SetText(ListMoney(entry.cost))
            row.right:SetText(ListMoney(entry.profit))
            row.perHour:SetText(entry.perHour and ListMoney(entry.perHour) or Gray("-"))
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
            row.perHour:SetText("")
            if unpriced.output then
                row.investment:SetText(ListMoney(entry.cost))
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
        row.perHour:Show()
        row.roi:Show()
        row.queued:Show()
        row.sold:Show()
        row.auctions:Show()
        row.reason:Show()
        row.hit.recipe = entry.recipe
        row.hit.entry = entry
        row.hit:Show()
        row.favorite.recipe = entry.recipe
        ShowStar(row)
        row.favorite:Show()
        row.queue:SetScript("OnClick", function() QueueRecipe(ranking) end)
        row.queue:Show()
        row.unqueue:SetScript("OnClick", function() UnqueueRecipe(ranking) end)
        row.unqueue:SetEnabled(queued > 0)
        row.unqueue:Show()
    end
    for index = #ranked + 1, #rows do
        local row = rows[index]
        row.entry = nil
        row.left:Hide()
        row.investment:Hide()
        row.right:Hide()
        row.perHour:Hide()
        row.roi:Hide()
        row.queued:Hide()
        row.sold:Hide()
        row.auctions:Hide()
        row.reason:Hide()
        row.hit.recipe = nil
        row.hit:Hide()
        row.favorite.recipe = nil
        row.favorite:Hide()
        row.queue:Hide()
        row.unqueue:Hide()
    end

    -- The divider, under the last favorite, while there are others below.
    local divider = frame.favoritesDivider
    divider:ClearAllPoints()
    if favorites then
        local y = RowTop(favorites, favorites) - ROW_HEIGHT + 2 - DIVIDER_SPACE
        divider:SetPoint("TOPLEFT", frame.list, "TOPLEFT", 0, y)
        divider:SetPoint("TOPRIGHT", frame.list, "TOPRIGHT", 0, y)
        divider:Show()
    else
        divider:Hide()
    end

    -- The list is VisibleRows tall, however many are listed (so the window
    -- doesn't jump as you search or filter), and scrolls for the rest, back
    -- to the top for another profession or tab.
    local gap = favorites and DIVIDER_GAP or 0
    local listHeight = VisibleRows() * ROW_HEIGHT + DIVIDER_GAP
    frame.list:SetHeight(math.max(#ranked, 1) * ROW_HEIGHT + gap)
    frame.scroll:SetSize(LIST_WIDTH, listHeight)
    frame.scroll:SetShown(#ranked > 0)
    local listKey = table.concat(keys, ",") .. "/" .. tab .. "/" .. filter
    if listKey ~= shownList then
        shownList = listKey
        frame.scroll:SetVerticalScroll(0)
    end
    local y = LIST_TOP - listHeight

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
    -- The minimums row at the bottom of the window and the notes just above
    -- it, held there when the window is taller than the list needs (it's
    -- at least tall enough for the side tabs). The height leaves room for
    -- both under the list.
    frame.status:SetText(table.concat(lines, "\n"))
    frame.minimums:ClearAllPoints()
    frame.minimums:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING, PADDING)
    frame.status:ClearAllPoints()
    frame.status:SetPoint("BOTTOMLEFT", frame.minimums, "TOPLEFT", 0, 8)
    return -y + 8 + MINIMUMS_HEIGHT + 8 + (frame.status:GetStringHeight() or 12) + PADDING
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
