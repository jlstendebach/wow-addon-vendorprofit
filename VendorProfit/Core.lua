-- Vendor Profit for Auctionator: adds to Auctionator's crafting info (To Craft
-- / Profit) in the professions window, leaving Auctionator's own lines as
-- they are:
--
--     To Craft: ...                Auctionator
--     Profit: ...                  Auctionator
--     Vendor Profit: ...           sold to a vendor, at Auctionator's To Craft
--                                  cost (VendorLine.lua)
--     ----- Cheapest Route -----   crafting reagents yourself where that's
--     To Craft: ...                cheaper (RouteSection.lua, using
--     Profit: ...                  Recipes.lua and Route.lua)
--     Vendor Profit: ...
--     [Queue]                      QueueButton.lua, for the shopping panel
--
-- This file holds what they share: prices, working out the recipe being
-- shown, and attaching to Auctionator's frame. The addon only reads from
-- Auctionator. It adds its own regions to Auctionator's crafting info frame
-- and post-hooks that frame's UpdateTotal to know when to refresh. It never
-- changes Auctionator's text, settings or data.

local ADDON_NAME, ns = ...

local VendorProfit = {}
ns.VendorProfit = VendorProfit
_G.VendorProfit = VendorProfit

VendorProfit.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")

-- The frame Auctionator puts under a recipe's reagents in the professions
-- window. It's created the first time the professions window opens.
VendorProfit.AUCTIONATOR_FRAME = "AuctionatorCraftingInfoProfessionsFrame"

VendorProfit.L = {
    VENDOR_PROFIT = "Vendor Profit:",
    TO_CRAFT = "To Craft:",
    PROFIT_COLON = "Profit:",
    NO_SELL_PRICE = "can't be sold to vendors",
    NO_AUCTION_PRICE = "no auction price",
    MISSING_PRICES = "(missing reagent prices)",
    ROUTE_TITLE = "Cheapest Route",
    SOURCE_VENDOR = "buy (vendor)",
    SOURCE_AUCTION = "buy (auction)",
    SOURCE_CRAFT = "craft",
    MAKES = "makes %d",
    SAVES_STEP = "saves %s",
    SOURCE_NONE = "no price",
    AUCTIONATOR_COST = "Auctionator's To Craft",
    SAVES = "Saves",
    RECIPES_FROM = "Uses your recipes from: %s.",
    NO_RECIPES = "No recipes saved yet.",
    OPEN_PROFESSIONS = "Open each profession once to add its recipes.",

    -- Search button
    SEARCH_TREE = "Search",
    SEARCH_TREE_HELP = "Looks up live lowest prices for every item in this recipe's crafting tree (the item, its reagents and everything they could be crafted from) in one request. Auctionator saves them, so the Cheapest Route updates.",
    SEARCH_TREE_SHIFT = "Shift-click to list them in Auctionator's search instead.",
    SEARCH_BUSY = "Looking up prices...",
    SEARCH_NOTHING = "Nothing in this recipe's tree can be listed on the auction house.",
    SEARCH_FAILED = "|cffffd100Vendor Profit:|r %s",
    SEARCH_NO_ANSWER = "The auction house didn't answer. Try Search again.",

    -- Best Crafts
    BEST_BUTTON = "Vendor Profit",
    BEST_BUTTON_HELP = "Shows this profession's best crafts, each along its cheapest route, in the Vendor Profit window. Your shopping list is on its other tab.",
    BEST_TITLE = "Best Crafts: %s",
    BEST_TAB_VENDOR = "Vendor",
    BEST_TAB_AUCTION = "Auction",
    BEST_RECIPE = "Recipe",
    BEST_ROI = "ROI",
    BEST_SORT_HELP = "Click to sort by this column; again to reverse.",
    BEST_SORT_UP = "|TInterface\\Buttons\\Arrow-Up-Up:10:10|t",
    BEST_SORT_DOWN = "|TInterface\\Buttons\\Arrow-Down-Up:10:10|t",
    BEST_INVESTMENT = "Investment",
    BEST_PROFIT = "Profit",
    BEST_QUEUE_HELP = "Adds one craft to your shopping order. Shift-click: five.",
    BEST_UNQUEUE_HELP = "Removes one craft from your shopping order. Shift-click: five.",
    BEST_QUEUED_HEADING = "Q",
    BEST_AUCTIONS_HEADING = "AH",
    BEST_AUCTIONS_HELP = "How many you have up for auction, as of your last visit to the auction house.",
    BEST_QUEUED_HELP = "Crafts in your shopping order.",
    BEST_SCAN_HELP = "Looks up live lowest prices for every item in this profession's recipes, in a few batches. Auctionator saves them too.",
    BEST_SCAN_OPEN_AH = "Open the auction house to look up live prices.",
    BEST_SCANNING = "Looking up prices: batch %d of %d",
    BEST_SCANNED = "Live prices updated.",
    BEST_SCAN_FAILED = "The auction house didn't answer. Try Scan again.",
    BEST_AH_CLOSED = "The auction house closed before the scan finished.",
    BEST_NOTHING_TO_SCAN = "Nothing in this profession can be listed on the auction house.",
    BEST_OPEN_PROFESSION = "Open one of your professions to see its best crafts.",
    BEST_NONE = "No saved recipes for this profession yet.",
    BEST_NO_MATCH = "No recipes match \"%s\".",
    BEST_NO_MATCH_FILTERS = "No recipes pass the filters.",
    BEST_FILTER = "Filter",
    BEST_FILTER_ON = "Filter (%d)",
    BEST_FILTER_RESET = "Clear the filters.",
    BEST_FILTER_PROFITABLE = "Profitable only",
    BEST_FILTER_SKILL_UP = "Skill up",
    BEST_SKILL_OPTIMAL = "Guaranteed",
    BEST_SKILL_MEDIUM = "Likely",
    BEST_SKILL_EASY = "Unlikely",
    BEST_SKILL_UNKNOWN = "Skill-up colors are only known for the profession whose window is open.",
    BEST_NO_PRICE_FOR = "no price: %s",
    BEST_NO_VENDOR_PRICE = "no vendor price",
    BEST_NO_AUCTION_PRICE = "no auction price",
    BEST_LIVE_PRICES = "Live prices from %s.",
    BEST_AUCTIONATOR_PRICES = "Prices from Auctionator's last scan.",

    -- Queue button
    QUEUE = "Queue",
    QUEUE_HELP = "Adds %d crafts of this recipe (the number in the Create box) to your shopping order.",
    QUEUED = "|cffffd100Vendor Profit:|r queued %d x %s. Shop for it on the Shopping List (/vprofit).",

    -- Shopping panel
    PANEL_TITLE = "Vendor Profit",
    TAB_SHOPPING = "Shopping List",
    TAB_BEST = "Best Crafts",
    TAB_HISTORY = "Profit History",
    TAB_PURCHASES = "Purchase History",
    PURCHASES_EMPTY = "No purchases yet. What you buy from vendors shows up here straight away; auction house purchases when you take them out of the mailbox.",
    PURCHASES_FROM = "From",
    PURCHASES_EACH = "Each",
    PURCHASES_TOTAL = "Total",
    PURCHASES_NOW = "Now",
    PURCHASES_EACH_LONG = "You paid each",
    PURCHASES_NOW_LONG = "Cheapest now (vendor or auction)",
    HISTORY_TOTAL = "Profit: %s from %d sales. Last 7 days: %s.",
    HISTORY_EMPTY = "No sales yet. Crafts you make from now on are tracked, with what their materials cost you. Their sales show up here when you sell to a vendor, or take an auction's payment from the mailbox.",
    HISTORY_DATE = "Date",
    HISTORY_ITEM = "Item",
    HISTORY_COST = "Cost",
    HISTORY_SOLD = "Sold for",
    HISTORY_VENDOR = "Vendor",
    HISTORY_AUCTION = "Auction",
    HISTORY_DATE_FORMAT = "%m/%d",
    HISTORY_TIME_FORMAT = "%b %d, %H:%M",
    HISTORY_BOUGHT = "Bought",
    HISTORY_OWN = "Your own items, at market value",
    HISTORY_SOLD_VENDOR = "Sold to a vendor for",
    HISTORY_SOLD_AUCTION = "Sold at auction for (after the cut)",
    HISTORY_VIEW_SALES = "Sales",
    HISTORY_VIEW_ITEMS = "Best Sellers",
    HISTORY_NO_MATCH = "No sales match your search.",
    HISTORY_NO_RANGE = "No sales in this range.",
    HISTORY_RANGE_ALL = "All time",
    HISTORY_RANGE_DAYS = "Last %d days",
    HISTORY_RANGE_SALES = "Last %d sales",
    HISTORY_RANGE_HELP = "Which sales to show and add up. All time counts every sale; the rest look back over your last %d.",
    HISTORY_SOLD_UNITS = "Sold",
    HISTORY_AVERAGE = "Avg profit",
    HISTORY_SOLD_COUNT = "%d sold in %d sales",
    HISTORY_AVERAGE_COST = "Average cost",
    HISTORY_AVERAGE_SOLD = "Average sold for",
    HISTORY_TO_VENDORS = "Sold to vendors",
    HISTORY_AT_AUCTION = "Sold at auction",
    HISTORY_LAST_SOLD = "Last sold %s",
    HISTORY_AVERAGE_ROI = "Avg ROI",
    BEST_SALES_TITLE = "Your sales, all time",
    BEST_NO_SALES = "No sales of it recorded yet.",
    TAB_GOLD = "Gold",
    GOLD_TOTAL = "Gold: %s across %d characters. Last 7 days: %s.",
    GOLD_TOTAL_ONE = "Gold: %s on one character. Last 7 days: %s.",
    GOLD_EMPTY = "No gold recorded yet. Each character's gold is saved from its next login on.",
    GOLD_NONE_SELECTED = "No characters selected. Tick some in the Characters menu.",
    GOLD_CHARACTERS = "Characters",
    GOLD_CHARACTERS_SOME = "Characters (%d of %d)",
    GOLD_SHOW_ALL = "Show every character.",
    GOLD_RANGE_HELP = "How far back the graph goes.",
    GOLD_RANGE_DAY = "Last 24 hours",
    GOLD_RANGE_MONTHS = "Last %d months",
    GOLD_RANGE_YEAR = "Last year",
    GOLD_HELP = "Drag across the graph to zoom in. Right-click to zoom back out.",
    GOLD_ZOOMED = "Zoomed in. Right-click the graph to zoom back out.",
    GOLD_HOUR_FORMAT = "%H:%M",
    GOLD_MONTH_FORMAT = "%b '%y",
    HEAD_QUEUED = "Queued",
    HEAD_TODO = "To do",
    STEP_BUY = "Buy",
    STEP_MAIL = "Collect from mailbox",
    STEP_BANK = "Take from bank",
    STEP_CRAFT = "Craft",
    HEAD_BAGS = "Already in your bags",
    HEAD_PROFIT = "Profit",
    NOTHING_QUEUED = "Nothing queued. Use Queue in a recipe's Cheapest Route section in the professions window.",
    QUEUED_REMOVE = "Remove from the order.",
    QUEUED_MORE = "Craft one more. Shift-click: five more.",
    QUEUED_FEWER = "Craft one fewer. Shift-click: five fewer.",
    QUEUED_COST = "Cost (cheapest route)",
    QUEUED_NO_VENDOR = "can't be sold to vendors",
    NOT_SCANNED = "not scanned",
    ONLY_LISTED = "only %d listed",
    CRAFTS = "%d crafts",
    CRAFTS_ONE = "%d craft",
    NEXT_MARK = "\194\187",
    VENDOR_PRICE = "Vendor price",
    AUCTION_PRICE = "Auction price",
    SPENT = "Spent on this order so far",
    ITEMS_YOU_HAVE = "Items you have",
    ITEMS_TO_BUY = "Items to buy",
    VENDOR_PROFIT_ROW = "Vendor profit",
    AUCTION_PROFIT_ROW = "Auction profit",
    BUY_OPEN_AH = "Open AH",
    VENDOR_BUY_HELP = "Buy from this vendor: %s, for %s.",
    VENDOR_BOUGHT = "|cffffd100Vendor Profit:|r bought %s from the vendor for %s.",
    VENDOR_SHORT = "|cffffd100Vendor Profit:|r not enough gold for all of: %s.",
    VENDOR_FIND = "The rest is sold by vendors. Talk to one that sells it to buy it here.",
    VENDOR_BUYING = "Waiting for your purchase to reach your bags.",
    PRICES_NO_VENDOR = "|cffffd100Vendor Profit:|r talk to a vendor first, then /vprofit prices lists its prices.",
    PRICES_TITLE = "Vendor prices",
    PRICES_NOTE = "%d items, %d new or changed. Copy (Ctrl+C) the lines you want into VendorPrices.lua.",
    BUY_OPEN_AH_HELP = "Talk to an auctioneer to buy. Until you scan there, prices are from Auctionator's last scan.",
    BUY_SCAN_HELP = "Scans the auction house for live prices of what's left to buy.",
    BUY_SCANNING = "Scanning...",
    SCAN_LIMIT_WAIT = "Waiting: the auction house answers %d searches a minute, from all addons together.",
    ACTION_BLOCKED = "|cffffd100Vendor Profit:|r the game blocked %s (it blamed %s). Please report this line.",
    BUY_PRICING = "Pricing...",
    BUY_BUY = "Buy",
    BUY_CONFIRM = "Confirm",
    BUY_BUYING = "Buying...",
    BUTTON_SCANNING = "Scanning %d of %d...",
    BUTTON_LOOKING_UP = "Looking up prices for the whole order...",
    BUTTON_NOTHING = "Nothing to buy here",
    BUTTON_NOT_PROFITABLE = "Not profitable: at these prices, neither selling to a vendor nor at auction makes money.",
    BUTTON_BUY = "Buy %d %s for %s",
    BUTTON_QUOTING = "Getting the price from the auction house...",
    BUTTON_CONFIRM = "Confirm: %d %s for %s",
    BUTTON_BUYING = "Buying...",
    CRAFT_LABEL = "Craft",
    OPENING_LABEL = "Opening...",
    OPENING_HELP = "Waiting for %s to open.",
    OPEN_LABEL = "Open %s",
    CRAFT_ONCE = "Craft %s",
    CRAFT_TIMES = "Craft %s, %d times",
    OPEN_TO_CRAFT = "Open %s to craft %s",
    OPEN_AFTER_COMBAT = "Open %s after combat to craft %s",
    OPEN_PROFESSION_HELP = "Opens %s.",
    NEED_MATERIALS = "Missing materials for %s",
    NEED_STATION = "Needs %s nearby to craft %s",
    STATIONS_NONE = "|cffffd100Vendor Profit:|r nothing to craft.",
    STATIONS_LINE = "|cffffd100Vendor Profit:|r %s (%s): %s",
    STATIONS_NEEDS_NONE = "needs no station",
    STATIONS_HERE = "%s, and you're at one",
    STATIONS_AWAY = "%s, and you're not at one",
    STATIONS_UNKNOWN = "%s, the game doesn't say if you're at one",
    CRAFTING = "Crafting...",
    SCAN = "Scan",
    CANCEL = "Cancel",
    BUY_ANYWAY = "Buy anyway",
    BUY_ANYWAY_HELP = "Click to buy anyway, until the next scan.",
    ORDER_DONE = "|cffffd100Vendor Profit:|r order done: everything queued is crafted.",
    BUY_SCAN_FIRST = "Scans prices first. Then click Buy for each purchase, and confirm it.",
    BUY_SCAN_NEW = "Scans prices for what was queued since the last scan. Then click Buy for each purchase.",
    SCAN_OPEN_AH = "Open the auction house to scan live prices.",
    FROM_AUCTION = "auction",
    FROM_VENDOR = "vendor",
    BANK_TAKE = "Take",
    BANK_TAKING = "Taking...",
    BANK_OPEN_FIRST = "Open your bank to take these out.",
    BANK_TAKE_HELP = "Moves exactly these from your bank into your bags.",
    BANK_DONE = "Took everything from the bank.",
    BANK_SOME_MISSING = "Took what was there; some of it wasn't in the bank.",
    BANK_NOTHING_FOUND = "None of these are in the bank.",
    BANK_CHANGED = "The bank changed while moving. Click Take from bank again.",
    BANK_CLOSED_MID = "The bank closed before everything was moved.",
    BANK_MOVE_STUCK = "An item didn't finish moving. Click Take from bank again.",
    BAGS_FULL = "Your bags are full.",

    -- Shopping messages
    SCAN_FAILED = "Couldn't scan %s. Scan again to retry.",
    NOT_PROFITABLE_STOPPED = "Neither selling to a vendor nor at auction makes money at these prices. Scan again, or choose Buy anyway.",
    NOT_ENOUGH_GOLD = "Not enough gold for the next purchase.",
    NO_QUOTE = "The auction house didn't give a price for %s. Click Buy to try again.",
    SCANNED_CLICK_BUY = "Prices are in. Click Buy for %s.",
    QUOTE_BUSY = "The auction house was busy and didn't price %s. Click Buy again.",
    BUTTON_AH_BUSY = "Waiting a moment for the auction house to be ready...",
    NO_PURCHASE_REPLY = "No reply buying %s. Scanning it again: check your mailbox before buying more.",
    PRICE_WENT_UP = "%s costs more than scanned (%s, now %s). Scanning it again.",
    PRICE_UNAVAILABLE = "%s isn't available at that price any more. Scanning it again.",
    BOUGHT = "Bought %d %s for %s.",
    PURCHASE_FAILED = "Buying %s failed. Scanning it again.",
    AUCTION_GONE = "%s was bought by someone else first. Buy goes on to the next cheapest.",
}

-- Prices ---------------------------------------------------------------------

-- What it costs to buy one: from a vendor (Auctionator only knows vendor
-- prices for items it has seen at a vendor) and on the auction house.
function VendorProfit.GetBuyPrices(itemID)
    local api = Auctionator.API.v1
    -- Auctionator's vendor price once it has seen a vendor sell the item;
    -- until then, the usual price (VendorPrices.lua).
    local vendor = api.GetVendorPriceByItemID(ADDON_NAME, itemID)
    if vendor == nil and VendorProfit.KNOWN_VENDOR_PRICES then
        vendor = VendorProfit.KNOWN_VENDOR_PRICES[itemID]
    end
    return vendor, api.GetAuctionPriceByItemID(ADDON_NAME, itemID)
end

-- Price of one reagent the way Auctionator prices reagents: the vendor price
-- if there is one, otherwise the auction price.
function VendorProfit.GetReagentPrice(itemID)
    local vendor, auction = VendorProfit.GetBuyPrices(itemID)
    return vendor or auction
end

-- What a seller keeps of an auction sale: Auctionator's figure, or 95%.
function VendorProfit.GetAfterAHCut()
    local constants = Auctionator.Constants
    return constants and constants.AfterAHCut or 0.95
end

-- Auctionator's auction price for a crafted item, or nil.
function VendorProfit.GetOutputAuctionPrice(itemLink)
    return Auctionator.API.v1.GetAuctionPriceByItemLink(ADDON_NAME, itemLink)
end

-- Walks the required reagents. Returns their total cost, cheapest option per
-- slot, and whether any slot has no price at all (Auctionator counts those as
-- free, which makes a craft look more profitable than it is).
local function ScanReagents(recipeSchematic)
    local total, missing = 0, false
    for _, slot in ipairs(recipeSchematic.reagentSlotSchematics) do
        if slot.reagentType == Enum.CraftingReagentType.Basic and #slot.reagents > 0 then
            local cheapest
            for _, reagent in ipairs(slot.reagents) do
                local price = reagent.itemID and VendorProfit.GetReagentPrice(reagent.itemID)
                if price and price > 0 and (cheapest == nil or price < cheapest) then
                    cheapest = price
                end
            end
            if cheapest then
                total = total + cheapest * slot.quantityRequired
            else
                missing = true
            end
        end
    end
    return total, missing
end

-- What it costs to craft once. Auctionator's figure when available, so it
-- matches the To Craft line; otherwise the reagent scan's own total.
local function GetCraftCost(recipeSchematic, transaction, scannedTotal)
    local calculate = Auctionator.CraftingInfo and Auctionator.CraftingInfo.CalculateCraftCost
    if calculate then
        return calculate(recipeSchematic, transaction)
    end
    return scannedTotal
end

-- The recipe being shown ----------------------------------------------------

-- Works out what the lines need for the recipe a schematic form is showing.
-- Returns a result table, or nil when the recipe makes no item (enchants).
--   status "loading":  item info isn't cached yet; only itemLink is set
--   status "noSell":   the item has no vendor price; profit is nil
--   status "ok":       profit is the vendor profit
-- Every status but "loading" also has itemID, sellPrice, count, cost (the To
-- Craft cost), missingPrices and recipeSchematic.
function VendorProfit.Calculate(schematicForm)
    local recipeInfo = schematicForm:GetRecipeInfo()
    if recipeInfo == nil or recipeInfo.isEnchantingRecipe then
        return nil
    end

    local recipeID = recipeInfo.recipeID
    local recipeSchematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false, schematicForm:GetCurrentRecipeLevel())
    local transaction = schematicForm:GetTransaction()
    if recipeSchematic == nil or transaction == nil then
        return nil
    end

    local outputData = C_TradeSkillUI.GetRecipeOutputItemData(
        recipeID,
        transaction:CreateCraftingReagentInfoTbl(),
        transaction:GetAllocationItemGUID()
    )
    local itemLink = outputData and outputData.hyperlink
    if itemLink == nil then
        return nil
    end

    local sellPrice = select(11, C_Item.GetItemInfo(itemLink))
    if sellPrice == nil then
        return { status = "loading", itemLink = itemLink }
    end

    local scannedTotal, missing = ScanReagents(recipeSchematic)
    local cost = GetCraftCost(recipeSchematic, transaction, scannedTotal)
    -- Same count Auctionator's Profit line uses: the guaranteed minimum.
    local count = math.max(recipeSchematic.quantityMin or 1, 1)

    local result = {
        status = sellPrice > 0 and "ok" or "noSell",
        itemLink = itemLink,
        itemID = recipeSchematic.outputItemID or C_Item.GetItemInfoInstant(itemLink),
        sellPrice = sellPrice,
        count = count,
        cost = cost,
        missingPrices = missing,
        recipeSchematic = recipeSchematic,
    }
    if sellPrice > 0 then
        result.profit = sellPrice * count - cost
    end
    return result
end

-- Item info -------------------------------------------------------------------

-- Items whose info the game hasn't sent yet (the first time a list shows
-- them, say): each is asked for once, and the views waiting on them are
-- redrawn once per batch, a moment after items start arriving, not once per
-- item. Asking again on every redraw multiplied: each arrival redrew, every
-- redraw asked again for every item still missing, and the redraws doubled
-- with each item (10 items, 1,024 redraws), freezing the game.
VendorProfit.ITEM_REDRAW_DELAY = 0.2
local waitingItems = {}   -- itemID -> { [redraw] = true }
local dueRedraws = {}     -- redraw -> true
local redrawScheduled = false

local function RunRedraws()
    redrawScheduled = false
    local redraws = dueRedraws
    dueRedraws = {}
    for redraw in pairs(redraws) do
        xpcall(redraw, geterrorhandler())
    end
end

-- Calls redraw (always the same function for a view, so it's only queued
-- once) after the item's info arrives.
function VendorProfit.RedrawWhenLoaded(itemID, redraw)
    local redraws = waitingItems[itemID]
    if redraws then
        redraws[redraw] = true
        return
    end
    waitingItems[itemID] = { [redraw] = true }
    Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
        local waiting = waitingItems[itemID] or {}
        waitingItems[itemID] = nil
        for fn in pairs(waiting) do
            dueRedraws[fn] = true
        end
        if not redrawScheduled then
            redrawScheduled = true
            C_Timer.After(VendorProfit.ITEM_REDRAW_DELAY, RunRedraws)
        end
    end)
end

-- Coin icons, as the game draws them in money text.
VendorProfit.COINS = {
    gold = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
    silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
    copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}

-- Money as coins, like the game's own money text, except that silver and
-- copper are always two digits after a larger coin: 5s 07c, not 5s 7c, so it
-- can't be misread as 5s 70c. Coins that are zero are left out, and gold gets
-- thousands separators.
function VendorProfit.FormatCoins(copper)
    copper = math.floor(math.abs(copper) + 0.5)
    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local cop = copper % 100
    local coins = VendorProfit.COINS
    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = (BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or tostring(gold)) .. coins.gold
    end
    if silver > 0 then
        parts[#parts + 1] = string.format(gold > 0 and "%02d" or "%d", silver) .. coins.silver
    end
    if cop > 0 or #parts == 0 then
        parts[#parts + 1] = string.format(#parts > 0 and "%02d" or "%d", cop) .. coins.copper
    end
    return table.concat(parts, " ")
end

-- A return on investment as a whole percentage: red with a minus for a
-- loss, a gray dash when there's none (nothing was spent).
function VendorProfit.FormatROI(roi)
    if roi == nil then
        return GRAY_FONT_COLOR:WrapTextInColorCode("-")
    end
    local text = string.format("%d%%", math.floor(roi * 100 + (roi >= 0 and 0.5 or -0.5)))
    if roi < 0 then
        return RED_FONT_COLOR:WrapTextInColorCode(text)
    end
    return text
end

-- How many crafts a + or - click on a queue adds or takes off: one, or
-- SHIFT_STEP with Shift held.
VendorProfit.SHIFT_STEP = 5
function VendorProfit.QueueStep()
    return IsShiftKeyDown() and VendorProfit.SHIFT_STEP or 1
end

-- Money text styled like Auctionator's Profit line: white, or red with a
-- minus for a loss.
function VendorProfit.FormatMoney(copper)
    copper = math.floor(copper + 0.5)
    if copper >= 0 then
        return WHITE_FONT_COLOR:WrapTextInColorCode(VendorProfit.FormatCoins(copper))
    end
    return RED_FONT_COLOR:WrapTextInColorCode("-" .. VendorProfit.FormatCoins(-copper))
end

-- Starts a list row's tooltip where the game puts an item's: just above the
-- row, past the end of its name (text). The row's hover area is wider than
-- the name, so the usual ANCHOR_RIGHT on it would put the tooltip too far out.
function VendorProfit.SetNameTooltipOwner(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    local x = 0
    local textLeft, ownerLeft = text:GetLeft(), owner:GetLeft()
    if textLeft and ownerLeft then
        -- A long name is cut off at its column's width.
        local width = text:GetStringWidth()
        local column = text:GetWidth()
        if column and column > 0 then
            width = math.min(width, column)
        end
        x = textLeft - ownerLeft + width
    end
    GameTooltip:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", x, 0)
end

-- Starts a list row's tooltip where the game puts one for a button: its
-- bottom left at the top right of the column (one of columns, the row's text
-- regions) under the cursor. It moves along as the cursor crosses into
-- another column.
function VendorProfit.SetRowTooltipOwner(owner, columns)
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    local placedAt
    local function Place()
        local ownerLeft = owner:GetLeft()
        if ownerLeft == nil then
            return
        end
        local cursor = GetCursorPosition() / owner:GetEffectiveScale()
        -- The rightmost column starting left of the cursor; left of them
        -- all, the first.
        local column, first
        for _, region in ipairs(columns) do
            local left = region:GetLeft()
            if left then
                if left <= cursor and (column == nil or left > column:GetLeft()) then
                    column = region
                end
                if first == nil or left < first:GetLeft() then
                    first = region
                end
            end
        end
        column = column or first
        local x = column and column:GetRight() - ownerLeft or 0
        if x ~= placedAt then
            placedAt = x
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", x, 0)
        end
    end
    Place()
    owner:SetScript("OnUpdate", function(self)
        if not GameTooltip:IsOwned(self) then
            self:SetScript("OnUpdate", nil)
            return
        end
        Place()
    end)
end

-- Lines -----------------------------------------------------------------------

-- Each line module has:
--   Create(frame, anchor)  adds its regions to Auctionator's frame under
--                          anchor (the region above it); returns its bottom
--                          region for the next line to anchor to
--   Refresh(frame, result) updates from VendorProfit.Calculate's result, or
--                          hides when result is nil
-- Lines appear in the order they're added.
local lines = {}
function VendorProfit.AddLine(line)
    lines[#lines + 1] = line
end

local attachedFrame     -- Auctionator's frame, once the lines are added to it
local pendingItemLink   -- output item whose info is loading, to refresh once

local function Refresh(frame)
    local result = VendorProfit.Calculate(frame:GetParent())

    if result and result.status == "loading" then
        -- Hide until the item's info arrives, then refresh once.
        local itemLink = result.itemLink
        result = nil
        if pendingItemLink ~= itemLink then
            pendingItemLink = itemLink
            Item:CreateFromItemLink(itemLink):ContinueOnItemLoad(function()
                if pendingItemLink == itemLink then
                    pendingItemLink = nil
                    VendorProfit.Refresh()
                end
            end)
        end
    end

    for _, line in ipairs(lines) do
        line.Refresh(frame, result)
    end
end

-- Refreshes the lines now. Errors are reported but never passed back up into
-- Auctionator's or Blizzard's code that triggered the refresh.
function VendorProfit.Refresh()
    local frame = attachedFrame
    if frame == nil or not frame:IsVisible() then
        return
    end
    xpcall(function() Refresh(frame) end, geterrorhandler())
end

local function Attach(frame)
    attachedFrame = frame

    -- Lines sit under Auctionator's text, in the same font, so they read as
    -- more lines of it. As children of Auctionator's frame they show and hide
    -- with it.
    local anchor = frame.Total
    for _, line in ipairs(lines) do
        anchor = line.Create(frame, anchor)
    end

    -- Auctionator calls UpdateTotal whenever the recipe, its reagents or its
    -- prices change, so refreshing right after it keeps both in step.
    hooksecurefunc(frame, "UpdateTotal", VendorProfit.Refresh)
    VendorProfit.Refresh()
end

function VendorProfit.TryAttach()
    if attachedFrame then
        return true
    end
    local frame = _G[VendorProfit.AUCTIONATOR_FRAME]
    if frame == nil or frame.Total == nil or type(frame.UpdateTotal) ~= "function" then
        return false
    end
    Attach(frame)
    return true
end

function VendorProfit.IsAttached()
    return attachedFrame ~= nil
end

-- Auctionator makes its frame on TRADE_SKILL_SHOW. Hooking the function that
-- makes it attaches right after, whichever addon sees the event first. The
-- event is a backup in case Auctionator renames that function. Attaching only
-- happens at these events, after every file of the addon has loaded.
if Auctionator.CraftingInfo and Auctionator.CraftingInfo.InitializeProfessionsFrame then
    hooksecurefunc(Auctionator.CraftingInfo, "InitializeProfessionsFrame", VendorProfit.TryAttach)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("TRADE_SKILL_SHOW")
events:SetScript("OnEvent", function(self, event)
    if VendorProfit.TryAttach() then
        self:UnregisterAllEvents()
    elseif event == "TRADE_SKILL_SHOW" then
        -- Auctionator may handle this same event after us.
        C_Timer.After(0, VendorProfit.TryAttach)
    end
end)

-- When the game blocks an action ("Interface action failed because of an
-- AddOn"), its message doesn't say what was blocked. Say it once per action,
-- so a report can name it. The game blames whichever addon touched things
-- last, which isn't always the one at fault, so every block is reported.
local blocked = CreateFrame("Frame")
local reported = {}
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    pcall(blocked.RegisterEvent, blocked, event)
end
blocked:SetScript("OnEvent", function(_, _, addon, action)
    local key = tostring(addon) .. "/" .. tostring(action)
    if not reported[key] then
        reported[key] = true
        print(string.format(VendorProfit.L.ACTION_BLOCKED, tostring(action), tostring(addon)))
    end
end)
