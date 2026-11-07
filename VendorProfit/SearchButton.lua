-- The Search button in the Cheapest Route section, shown while the auction
-- house is open, like Auctionator's own Search button. It looks up live
-- prices for every item in the crafting tree (Route.TreeItems): the item, its
-- reagents and everything they could be crafted from, not just what the
-- current route uses, since any of those prices can change the route.
--
-- A click does it in one batch request, the same lookup as Best Crafts'
-- Scan, rather than a search per item. Those are browse results, and
-- Auctionator saves the lowest price of anything a browse query returns while
-- the auction house is open, so the route updates from what it finds.
-- Shift-click runs Auctionator's own search instead, listing every item.

local ADDON_NAME, ns = ...
local VendorProfit = ns.VendorProfit
local Route = VendorProfit.Route
local Recipes = VendorProfit.Recipes
local L = VendorProfit.L

local SearchButton = {}
VendorProfit.SearchButton = SearchButton

local BIND_ON_PICKUP = 1

local function AuctionHouseOpen()
    return AuctionHouseFrame ~= nil and AuctionHouseFrame:IsShown()
end

-- Search terms for the tree: one exact name search per item, leaving out
-- items that can't be listed (bind on pickup). Calls done(terms) once every
-- item's name is loaded.
function SearchButton.BuildTerms(result, done)
    local itemIDs = Route.TreeItems(result.itemID, Recipes.ReagentsFromSchematic(result.recipeSchematic))
    local pending = #itemIDs
    local function Finish()
        local terms = {}
        for _, itemID in ipairs(itemIDs) do
            local name, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(itemID)
            if name and bindType ~= BIND_ON_PICKUP then
                terms[#terms + 1] = { searchString = name, isExact = true }
            end
        end
        done(terms)
    end
    if pending == 0 then
        Finish()
        return
    end
    for _, itemID in ipairs(itemIDs) do
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
            pending = pending - 1
            if pending == 0 then
                Finish()
            end
        end)
    end
end

-- Shift-click: Auctionator's own search, listing every item.
local function AuctionatorSearch(result)
    SearchButton.BuildTerms(result, function(terms)
        if #terms > 0 then
            -- Auctionator raises an error for a bad term; report it, don't break.
            xpcall(function() Auctionator.API.v1.MultiSearchAdvanced(ADDON_NAME, terms) end, geterrorhandler())
        end
    end)
end

-- Click: one batch lookup for the whole tree (Best Crafts' Scan, for one
-- recipe), much quicker than a search per item.
local function LookUp(result)
    local itemIDs = Route.TreeItems(result.itemID, Recipes.ReagentsFromSchematic(result.recipeSchematic))
    VendorProfit.BestCrafts.LookUpItems(itemIDs, function(text, isError)
        if isError then
            if text == L.BEST_SCAN_FAILED then
                text = L.SEARCH_NO_ANSWER
            end
            print(string.format(L.SEARCH_FAILED, text))
        end
        VendorProfit.Refresh()
    end)
end

local function OnClick(button)
    local result = button.result
    if result == nil or not AuctionHouseOpen() then
        return
    end
    if IsShiftKeyDown() then
        AuctionatorSearch(result)
    else
        LookUp(result)
    end
end

local function OnEnter(button)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.SEARCH_TREE)
    if VendorProfit.BestCrafts.IsScanning() then
        GameTooltip:AddLine(L.SEARCH_BUSY, 1, 1, 1, true)
    else
        GameTooltip:AddLine(L.SEARCH_TREE_HELP, 1, 1, 1, true)
        GameTooltip:AddLine(L.SEARCH_TREE_SHIFT, nil, nil, nil, true)
    end
    GameTooltip:Show()
end

local buttons = {}

local function UpdateShown(button)
    button:SetShown(button.result ~= nil and AuctionHouseOpen())
    -- Off while a lookup (this or Best Crafts' Scan) is running.
    button:SetEnabled(not VendorProfit.BestCrafts.IsScanning())
end

local listening = false
local function UpdateAll()
    for _, button in ipairs(buttons) do
        UpdateShown(button)
    end
end

function SearchButton.Create(frame, anchor)
    -- The same template as Auctionator's Search button, so it's the same
    -- size: 22 high and as wide as its text.
    local ok, button = pcall(CreateFrame, "Button", nil, frame, "UIPanelDynamicResizeButtonTemplate")
    if not ok then
        button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    end
    button:SetHeight(22)
    button:SetText(L.SEARCH_TREE)
    if DynamicResizeButton_Resize then
        DynamicResizeButton_Resize(button)
    else
        button:SetWidth(math.max(80, (button:GetTextWidth() or 0) + 40))
    end
    -- Top right of the section, where Auctionator puts its own Search button.
    button:SetPoint("TOPRIGHT", frame.VendorProfitRoute.separator, "BOTTOMRIGHT", 0, -1)
    -- Above the frame that shows the route tooltip, so clicks reach it.
    button:SetFrameLevel(frame:GetFrameLevel() + 5)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnClick", OnClick)
    button:SetScript("OnEnter", OnEnter)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()
    frame.VendorProfitSearchButton = button
    buttons[#buttons + 1] = button
    -- BestCrafts.lua loads after this file; by now it's there.
    if not listening then
        listening = true
        VendorProfit.BestCrafts.OnChange(UpdateAll)
    end
    return anchor
end

function SearchButton.Refresh(frame, result)
    local button = frame.VendorProfitSearchButton
    button.result = result
    UpdateShown(button)
end

-- Show and hide with the auction house.
local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", UpdateAll)

VendorProfit.AddLine(SearchButton)
