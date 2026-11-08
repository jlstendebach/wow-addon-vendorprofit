-- The Best Crafts tab of the Vendor Profit window: every saved recipe of the
-- open profession, ranked by profit per craft (BestCrafts.lua), losses
-- included, then the ones with no price to rank by, in a scrolling list with
-- Vendor and Auction tabs and Investment, Profit and ROI columns, sortable
-- by clicking a column's heading, and filtered by name with the search box
-- as you type. Each has a magnifying glass (selects it in
-- the professions window) and + (adds one craft to the shopping order). Live
-- prices come from Scan.
--
-- Opened by the Vendor Profit button in the professions window's title bar,
-- or /vprofit best.

local ADDON_NAME, ns = ...
local VendorProfit = ns.VendorProfit
local BestCrafts = VendorProfit.BestCrafts
local Recipes = VendorProfit.Recipes
local Order = VendorProfit.Order
local L = VendorProfit.L

local BestPanel = {}
VendorProfit.BestPanel = BestPanel

local Panel = VendorProfit.Panel

-- Wider than the Shopping List, for the money columns.
local WIDTH = 480
local PADDING = 16
local ROW_HEIGHT = 22
local LIST_TOP = -94
local VISIBLE_ROWS = 14
local SCROLLBAR_WIDTH = 24
local LIST_WIDTH = WIDTH - 2 * PADDING - SCROLLBAR_WIDTH
-- Columns, from the right of the list: Show (magnifying glass), Queue (+),
-- ROI, Profit, Investment; the recipe name takes the rest.
local ICON_BUTTON_WIDTH, MONEY_WIDTH, ROI_WIDTH, GAP = 22, 72, 48, 6
local ROI_RIGHT = -(2 * ICON_BUTTON_WIDTH + 4 + 8)
local PROFIT_RIGHT = ROI_RIGHT - ROI_WIDTH - GAP
local INVESTMENT_RIGHT = PROFIT_RIGHT - MONEY_WIDTH - GAP
local NAME_WIDTH = LIST_WIDTH + INVESTMENT_RIGHT - MONEY_WIDTH - GAP

-- Sorting by column: Recipe (A to Z first), Investment, Profit, ROI (highest
-- first). Clicking the sorted column again reverses it. Recipes with no
-- profit to rank stay at the bottom.
local SORT_DEFAULT = { key = "profit", ascending = false }
local SORT_STARTS_ASCENDING = { name = true }

local frame              -- the page
local tab = "vendor"
local rows = {}
local shownList          -- profession, tab and filter the list was last scrolled for
local filter = ""        -- the search box's text, lowercased

local function ItemLabel(itemID)
    local name = C_Item.GetItemInfo(itemID)
    if name == nil then
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function() BestPanel.Refresh() end)
        name = "item " .. itemID
    end
    local icon = select(5, C_Item.GetItemInfoInstant(itemID))
    return (icon and ("|T" .. icon .. ":0|t ") or "") .. name
end

local function Gray(text)
    return GRAY_FONT_COLOR:WrapTextInColorCode(text)
end

-- The list stays up after the professions window closes (the game keeps
-- reporting the last profession), so you can scan and queue at the auction
-- house without it. Only Show needs the window open.
local ProfessionsWindowOpen = Recipes.WindowOpen

local function ShowRecipe(recipe)
    Recipes.Show(recipe.recipeID, recipe.profession)
end

local function QueueRecipe(entry)
    local recipe = entry.recipe
    Order.AddRecipe({
        itemID = recipe.item, recipeID = recipe.recipeID, profession = recipe.profession,
        count = recipe.count, reagents = recipe.reagents,
        sellPrice = select(11, C_Item.GetItemInfo(recipe.item)),
    }, 1)
    print(string.format(L.QUEUED, 1, C_Item.GetItemInfo(recipe.item) or ("item " .. recipe.item)))
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
        local function Column(width, right)
            local text = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetJustifyH("RIGHT")
            text:SetWordWrap(false)
            text:SetWidth(width)
            text:SetPoint("TOPRIGHT", list, "TOPRIGHT", right, top - 4)
            return text
        end
        row.left = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.left:SetJustifyH("LEFT")
        row.left:SetWordWrap(false)
        row.left:SetWidth(NAME_WIDTH)
        row.left:SetPoint("TOPLEFT", list, "TOPLEFT", 0, top - 4)
        -- Investment: what one craft's items cost along the cheapest route.
        row.investment = Column(MONEY_WIDTH, INVESTMENT_RIGHT)
        row.right = Column(MONEY_WIDTH, PROFIT_RIGHT)
        -- Return on investment: profit as a share of the investment.
        row.roi = Column(ROI_WIDTH, ROI_RIGHT)
        -- Why a recipe isn't ranked, across the columns it has no number for.
        row.reason = Column(MONEY_WIDTH, ROI_RIGHT)

        -- Show: a magnifying glass.
        row.show = SmallButton(list, "", ICON_BUTTON_WIDTH)
        row.show:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, top)
        row.show.icon = row.show:CreateTexture(nil, "OVERLAY")
        row.show.icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
        row.show.icon:SetSize(12, 12)
        row.show.icon:SetPoint("CENTER", row.show, "CENTER", 0, 0)
        row.show:SetMotionScriptsWhileDisabled(true)
        Tooltip(row.show, function(self)
            if self:IsEnabled() then
                return L.BEST_SHOW_HELP
            end
            return string.format(L.BEST_SHOW_CLOSED, self.profession or "")
        end)
        -- Queue: a plus.
        row.queue = SmallButton(list, "+", ICON_BUTTON_WIDTH)
        row.queue:SetPoint("RIGHT", row.show, "LEFT", -4, 0)
        Tooltip(row.queue, L.BEST_QUEUE_HELP)
        rows[index] = row
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

local function FormatROI(roi)
    if roi == nil then
        return Gray("-")
    end
    local text = string.format("%d%%", math.floor(roi * 100 + (roi >= 0 and 0.5 or -0.5)))
    if roi < 0 then
        return RED_FONT_COLOR:WrapTextInColorCode(text)
    end
    return text
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
        vendor = SmallButton(frame, L.BEST_TAB_VENDOR, 90),
        auction = SmallButton(frame, L.BEST_TAB_AUCTION, 90),
    }
    frame.tabs.vendor:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -52)
    frame.tabs.auction:SetPoint("LEFT", frame.tabs.vendor, "RIGHT", 4, 0)
    frame.tabs.vendor:SetScript("OnClick", function() SetTab("vendor") end)
    frame.tabs.auction:SetScript("OnClick", function() SetTab("auction") end)

    frame.scan = SmallButton(frame, L.SCAN, 90)
    frame.scan:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -52)
    frame.scan:SetMotionScriptsWhileDisabled(true)
    frame.scan:SetScript("OnClick", function()
        BestCrafts.Scan(Recipes.OpenProfession())
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
    search:SetSize(150, 20)
    search:SetPoint("LEFT", frame.tabs.auction, "RIGHT", 14, 0)
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

    -- Column headings over the list; click one to sort by it.
    frame.headings = {}
    local function Heading(key, text, width, right)
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
        Tooltip(heading, L.BEST_SORT_HELP)
        frame.headings[key] = heading
        return heading
    end
    frame.nameHeading = Heading("name", L.BEST_RECIPE, NAME_WIDTH)
    frame.investmentHeading = Heading("investment", L.BEST_INVESTMENT, MONEY_WIDTH, INVESTMENT_RIGHT)
    frame.profitHeading = Heading("profit", L.BEST_PROFIT, MONEY_WIDTH, PROFIT_RIGHT)
    frame.roiHeading = Heading("roi", L.BEST_ROI, ROI_WIDTH, ROI_RIGHT)

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

local function Refresh()
    local profession, name = Recipes.OpenProfession()
    frame.heading:SetText(string.format(L.BEST_TITLE, name or ""))

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
        scan:SetEnabled(profession ~= nil and BestCrafts.CanScan())
        scan.tooltip = BestCrafts.CanScan() and L.BEST_SCAN_HELP or L.BEST_SCAN_OPEN_AH
    end

    -- Headings: the sorted one in white, with an arrow for its direction.
    local sort = Sort()
    for key, heading in pairs(frame.headings) do
        if key == sort.key then
            local arrow = sort.ascending and L.BEST_SORT_UP or L.BEST_SORT_DOWN
            heading.text:SetText(HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(heading.label .. " " .. arrow))
        else
            heading.text:SetText(heading.label)
        end
    end

    local all = {}
    if profession then
        all = SortEntries(BestCrafts.Rank(profession, tab, function() BestPanel.Refresh() end))
    end
    -- Numbered across the whole list, then filtered by the search box, so a
    -- recipe keeps its place in the ranking while searching.
    local ranked, place = {}, 0
    for _, entry in ipairs(all) do
        if entry.profit then
            place = place + 1
            entry.place = place
        end
        local name = (C_Item.GetItemInfo(entry.recipe.item) or ""):lower()
        if filter == "" or name:find(filter, 1, true) then
            ranked[#ranked + 1] = entry
        end
    end
    for index, entry in ipairs(ranked) do
        local row = GetRow(index)
        local reason
        row.roi:SetText("")
        if entry.profit then
            row.left:SetText(entry.place .. ". " .. ItemLabel(entry.recipe.item))
            row.investment:SetText(VendorProfit.FormatMoney(entry.cost))
            row.right:SetText(VendorProfit.FormatMoney(entry.profit))
            row.roi:SetText(FormatROI(entry.roi))
        else
            row.left:SetText(Gray("-  ") .. ItemLabel(entry.recipe.item))
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
                row.reason:SetWidth(MONEY_WIDTH + GAP + ROI_WIDTH)
            else
                row.investment:SetText("")
                row.reason:SetWidth(2 * (MONEY_WIDTH + GAP) + ROI_WIDTH)
            end
        end
        row.reason:SetText(reason and Gray(reason) or "")
        row.left:Show()
        row.investment:Show()
        row.right:Show()
        row.roi:Show()
        row.reason:Show()
        row.show:SetScript("OnClick", function() ShowRecipe(entry.recipe) end)
        row.show:SetEnabled(ProfessionsWindowOpen())
        row.show.icon:SetDesaturated(not ProfessionsWindowOpen())
        row.show.profession = name
        row.show:Show()
        row.queue:SetScript("OnClick", function() QueueRecipe(entry) end)
        row.queue:Show()
    end
    for index = #ranked + 1, #rows do
        local row = rows[index]
        row.left:Hide()
        row.investment:Hide()
        row.right:Hide()
        row.roi:Hide()
        row.reason:Hide()
        row.show:Hide()
        row.queue:Hide()
    end

    -- The list shows up to VISIBLE_ROWS at a time and scrolls for the rest,
    -- back to the top for another profession or tab.
    local listHeight = math.max(math.min(#ranked, VISIBLE_ROWS), 1) * ROW_HEIGHT
    frame.list:SetHeight(math.max(#ranked, 1) * ROW_HEIGHT)
    frame.scroll:SetSize(LIST_WIDTH, listHeight)
    frame.scroll:SetShown(#ranked > 0)
    local listKey = tostring(profession) .. "/" .. tab .. "/" .. filter
    if listKey ~= shownList then
        shownList = listKey
        frame.scroll:SetVerticalScroll(0)
    end
    local y = #ranked > 0 and LIST_TOP - listHeight or LIST_TOP

    -- Status: why the list is empty, where prices are from, and messages.
    local lines = {}
    if profession == nil then
        lines[#lines + 1] = L.BEST_OPEN_PROFESSION
    elseif #all == 0 then
        lines[#lines + 1] = L.BEST_NONE
    elseif #ranked == 0 then
        lines[#lines + 1] = string.format(L.BEST_NO_MATCH, frame.search:GetText() or "")
    end
    local liveTime = profession and BestCrafts.LiveTime(profession)
    if liveTime then
        lines[#lines + 1] = string.format(L.BEST_LIVE_PRICES, date("%H:%M", liveTime))
    elseif profession then
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

Panel.AddPage({
    name = "best",
    icon = "Interface\\Icons\\INV_Misc_Coin_02",
    label = L.TAB_BEST,
    create = Create,
    width = WIDTH,
    refresh = function() return Refresh() end,
})

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
