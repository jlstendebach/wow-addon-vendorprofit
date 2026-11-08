-- Minimal WoW client + Auctionator stub: just enough to load VendorProfit and
-- drive Auctionator's crafting info frame the way the real addon does.
local stub = {}
_G.__stub = stub

stub.metadata = {}
stub.items = {}          -- "item:<id>" -> { sellPrice = n, cached = bool, name = s }
stub.loadCallbacks = {}  -- "item:<id>" -> { fn, ... }
stub.timers = {}
stub.errors = {}
stub.recipe = nil        -- what the schematic form is showing (see SetRecipe)
stub.recipes = {}        -- recipeID -> recipe, for the open profession window
stub.profession = nil    -- the open profession window (see OpenProfession)
local eventFrames = {}

-- Frames and font strings ---------------------------------------------------
local FrameMethods = {}
FrameMethods.__index = FrameMethods
local FontMethods = {}
FontMethods.__index = FontMethods

function CreateFrame(_, name, parent)
    local f = setmetatable({ __shown = true, __parent = parent, __events = {}, __scripts = {} }, FrameMethods)
    if name then _G[name] = f end
    eventFrames[#eventFrames + 1] = f
    return f
end
function FrameMethods:GetParent() return self.__parent end
function FrameMethods:Show() self.__shown = true end
function FrameMethods:Hide()
    local was = self.__shown
    self.__shown = false
    if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
end
function FrameMethods:SetShown(s) self.__shown = not not s end
function FrameMethods:IsShown() return self.__shown end
function FrameMethods:IsVisible()
    if not self.__shown then return false end
    if self.__parent and self.__parent.IsVisible then return self.__parent:IsVisible() end
    return true
end
function FrameMethods:RegisterEvent(e) self.__events[e] = true end
function FrameMethods:RegisterUnitEvent(e) self.__events[e] = true end
function FrameMethods:UnregisterEvent(e) self.__events[e] = nil end
function FrameMethods:UnregisterAllEvents() self.__events = {} end
function FrameMethods:SetScript(k, fn) self.__scripts[k] = fn end
function FrameMethods:GetScript(k) return self.__scripts[k] end
function FrameMethods:SetAllPoints(r) self.__allPoints = r end
function FrameMethods:EnableMouse(e) self.__mouse = e end
function FrameMethods:SetSize(w, h) self.__w, self.__h = w, h end
function FrameMethods:SetWidth(w) self.__w = w end
function FrameMethods:SetHeight(h) self.__h = h end
function FrameMethods:GetHeight() return self.__h or 0 end
-- __point is the first point set since ClearAllPoints.
function FrameMethods:SetPoint(...) if self.__point == nil then self.__point = { ... } end end
function FrameMethods:ClearAllPoints() self.__point = nil end
function FrameMethods:SetText(t) self.__text = t end
function FrameMethods:GetText() return self.__text end
function FrameMethods:SetEnabled(e) self.__enabled = not not e end
function FrameMethods:IsEnabled() return self.__enabled ~= false end
function FrameMethods:SetTitle(t) self.__title = t end
function FrameMethods:SetMovable(m) self.__movable = m end
function FrameMethods:SetClampedToScreen() end
function FrameMethods:RegisterForDrag(...) self.__drag = { ... } end
function FrameMethods:SetUserPlaced(u) self.__userPlaced = u end
-- Dragging: StartMoving, then the stub moves the frame to stub.dragTo = { left, top }.
function FrameMethods:StartMoving() self.__moving = true end
function FrameMethods:StopMovingOrSizing()
    self.__moving = false
    if stub.dragTo then self.__left, self.__top = stub.dragTo[1], stub.dragTo[2] end
end
function FrameMethods:GetLeft() return self.__left or 10 end
function FrameMethods:GetTop() return self.__top end
function FrameMethods:GetBottom() return self.__bottom or 20 end
function FrameMethods:GetWidth() return self.__w or 100 end
function FrameMethods:GetEffectiveScale() return 1 end
function FrameMethods:SetFrameStrata(s) self.__strata = s end
function FrameMethods:SetToplevel(t) self.__toplevel = t end
function FrameMethods:SetScrollChild(child) self.__scrollChild = child end
function FrameMethods:SetVerticalScroll(v) self.__scroll = v end
function FrameMethods:GetVerticalScroll() return self.__scroll or 0 end
function FrameMethods:RegisterForClicks(...) self.__clicks = { ... } end
function FrameMethods:SetHighlightTexture() end
function FrameMethods:SetMotionScriptsWhileDisabled() end
function FrameMethods:SetNormalTexture(t) self.__normal = t end
function FrameMethods:SetCheckedTexture() end
function FrameMethods:SetChecked(c) self.__checked = not not c end
function FrameMethods:GetChecked() return self.__checked end
function FrameMethods:GetTextWidth() return #(self.__text or "") * 6 end
function DynamicResizeButton_Resize(button) button:SetWidth(button:GetTextWidth() + 40) end
function FrameMethods:LockHighlight() self.__lit = true end
function FrameMethods:UnlockHighlight() self.__lit = false end
function FrameMethods:SetAttribute(k, v) self.__attrs = self.__attrs or {}; self.__attrs[k] = v end
function FrameMethods:GetAttribute(k) return self.__attrs and self.__attrs[k] end
function stub.Drag(f, left, top)
    stub.dragTo = { left, top }
    f.__scripts.OnDragStart(f)
    f.__scripts.OnDragStop(f)
    stub.dragTo = nil
end
function FrameMethods:Click(...) if self.__scripts.OnClick and self:IsEnabled() then self.__scripts.OnClick(self, ...) end end
function FrameMethods:SetFrameLevel(l) self.__level = l end
function FrameMethods:GetFrameLevel() return self.__level or 1 end
function FrameMethods:CreateTexture()
    local t = setmetatable({ __shown = true, __parent = self, __text = "" }, FontMethods)
    t.SetColorTexture = function(tex, ...) tex.__color = { ... } end
    t.SetHeight = function() end
    t.SetSize = function() end
    t.SetTexture = function(tex, path) tex.__texture = path end
    return t
end
function FrameMethods:CreateFontString()
    return setmetatable({ __shown = true, __parent = self, __text = "" }, FontMethods)
end

function FontMethods:SetText(t) self.__text = t or "" end
function FontMethods:GetText() return self.__text end
function FontMethods:SetJustifyH() end
function FontMethods:SetFontObject() end
function FontMethods:SetWordWrap() end
function FontMethods:SetAllPoints(target) self.__point = { "ALL", target } end
function FontMethods:SetDesaturated(d) self.__desaturated = d end
function FontMethods:SetWidth() end
function FontMethods:GetStringHeight() return 12 end
function FontMethods:ClearAllPoints() self.__point = nil end
function FontMethods:SetShown(s) self.__shown = not not s end
function FontMethods:SetPoint(...) self.__point = { ... } end
function FontMethods:Show() self.__shown = true end
function FontMethods:Hide() self.__shown = false end
function FontMethods:IsShown() return self.__shown end
function FontMethods:IsVisible() return self.__shown and self.__parent:IsVisible() end

function stub.Fire(event, ...)
    for _, f in ipairs(eventFrames) do
        if f.__events[event] and f.__scripts.OnEvent then f.__scripts.OnEvent(f, event, ...) end
    end
end

-- Timers run in time order as time advances. RunTimers advances one second.
stub.now = 0
function stub.Advance(seconds)
    local target = stub.now + seconds
    while true do
        local best, bestIndex
        for i, t in ipairs(stub.timers) do
            if t.at <= target and (best == nil or t.at < best.at) then best, bestIndex = t, i end
        end
        if best == nil then break end
        table.remove(stub.timers, bestIndex)
        stub.now = best.at
        best.fn()
    end
    stub.now = target
end
function stub.RunTimers() stub.Advance(1) end

-- Tooltip -------------------------------------------------------------------
GameTooltip = { lines = {}, shown = false }
function GameTooltip:SetOwner(owner) self.owner = owner; self.lines = {} end
function GameTooltip:SetText(t) self.lines = { { left = t } } end
function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = { left = t } end
function GameTooltip:AddDoubleLine(l, r) self.lines[#self.lines + 1] = { left = l, right = r } end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide() self.shown = false; self.owner = nil end
function GameTooltip:IsOwned(f) return self.shown and self.owner == f end

-- Globals -------------------------------------------------------------------
function hooksecurefunc(tbl, name, hook)
    if type(tbl) == "string" then tbl, name, hook = _G, tbl, name end
    local orig = tbl[name]
    tbl[name] = function(...)
        local r = { orig(...) }
        hook(...)
        return unpack(r)
    end
end

function geterrorhandler()
    return function(msg) stub.errors[#stub.errors + 1] = tostring(msg) end
end

C_AddOns = { GetAddOnMetadata = function(addon, key) return stub.metadata[addon] and stub.metadata[addon][key] end }
C_Timer = { After = function(seconds, fn) stub.timers[#stub.timers + 1] = { at = stub.now + seconds, fn = fn } end }
SlashCmdList = {}
stub.money = 1000000
function GetMoney() return stub.money end
function GetTime() return stub.now end
function time() return 1700000000 end
date = os.date
stub.inCombat = false
function InCombatLockdown() return stub.inCombat end
function IsShiftKeyDown() return stub.shift end
-- Chat output, kept for tests.
stub.printed = {}
local rawPrint = print
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    stub.printed[#stub.printed + 1] = table.concat(parts, " ")
    rawPrint(...)
end
function GetCVarBool() return false end
C_Spell = { GetSpellName = function(id) return ({ [2575] = "Mining", [2656] = "Smelting" })[id] end }
stub.casting = nil
function UnitCastingInfo(unit) if unit == "player" then return stub.casting end end
function ButtonFrameTemplate_HidePortrait() end
function ButtonFrameTemplate_HideButtonBar() end
Enum = { CraftingReagentType = { Basic = 0, Optional = 1 }, PlayerInteractionType = { Auctioneer = 21, Merchant = 5 } }

local function Color(code, r, g, b)
    return { r = r, g = g, b = b, WrapTextInColorCode = function(_, t) return "|cff" .. code .. t .. "|r" end }
end
WHITE_FONT_COLOR, RED_FONT_COLOR = Color("ffffff", 1, 1, 1), Color("ff2020", 1, 0.125, 0.125)
GRAY_FONT_COLOR, GREEN_FONT_COLOR = Color("808080", 0.5, 0.5, 0.5), Color("20ff20", 0.125, 1, 0.125)
NORMAL_FONT_COLOR = Color("ffd100", 1, 0.82, 0)
HIGHLIGHT_FONT_COLOR = Color("ffffff", 1, 1, 1)

function GetMoneyString(copper)
    assert(copper == math.floor(copper), "GetMoneyString needs whole copper, got " .. tostring(copper))
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- Inventory: bags, bank and the mailbox (which GetItemCount doesn't see).
stub.bags, stub.bank, stub.mail = {}, {}, {}

local function ToLink(x) return type(x) == "number" and ("item:" .. x) or x end
local function ToID(x) return type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)")) end
stub.ToID = ToID

C_Item = {
    GetItemInfo = function(x)
        local link = ToLink(x)
        local item = stub.items[link]
        if item == nil or not item.cached then return nil end
        return item.name or link, link, 2, 20, 0, "Armor", "Mail", 1, "INVTYPE_CHEST", 0, item.sellPrice or 0, 4, 3, item.bind or 0
    end,
    GetItemCount = function(id, includeBank, _, includeReagentBank)
        local n = stub.bags[id] or 0
        if includeBank then n = n + (stub.bank[id] or 0) end
        return n
    end,
    GetItemInfoInstant = function(x)
        local id = ToID(x)
        return id, "Armor", "Mail", "INVTYPE_CHEST", "icon" .. id
    end,
}

local function ItemObject(link)
    return {
        ContinueOnItemLoad = function(_, fn)
            local item = stub.items[link]
            if item and item.cached then fn() return end
            stub.loadCallbacks[link] = stub.loadCallbacks[link] or {}
            table.insert(stub.loadCallbacks[link], fn)
        end,
    }
end
Item = {
    CreateFromItemLink = function(_, link) return ItemObject(link) end,
    CreateFromItemID = function(_, id) return ItemObject(ToLink(id)) end,
}

function stub.LoadItem(link)
    stub.items[link].cached = true
    local fns = stub.loadCallbacks[link] or {}
    stub.loadCallbacks[link] = nil
    for _, fn in ipairs(fns) do fn() end
end

-- Professions window ---------------------------------------------------------
-- recipe = { recipeID, itemLink (nil = no item output), isEnchant, quantityMin,
--            learned (default true),
--            reagents = { { itemID, quantity, optional, options = { more itemIDs } }, ... } }
local function Schematic(r)
    local slots = {}
    for _, reagent in ipairs(r.reagents) do
        local options = { { itemID = reagent.itemID } }
        for _, id in ipairs(reagent.options or {}) do options[#options + 1] = { itemID = id } end
        slots[#slots + 1] = {
            reagentType = reagent.optional and Enum.CraftingReagentType.Optional or Enum.CraftingReagentType.Basic,
            quantityRequired = reagent.quantity,
            reagents = options,
        }
    end
    return {
        recipeID = r.recipeID,
        outputItemID = r.itemLink and ToID(r.itemLink),
        quantityMin = r.quantityMin, quantityMax = r.quantityMin,
        reagentSlotSchematics = slots,
    }
end

local function FindRecipe(recipeID)
    if stub.recipe and stub.recipe.recipeID == recipeID then return stub.recipe end
    return stub.recipes[recipeID]
end

stub.tradeSkill = { ready = true, linked = false, guild = false, npc = false, changing = false }
C_TradeSkillUI = {
    GetRecipeSchematic = function(recipeID)
        local r = FindRecipe(recipeID)
        return r and Schematic(r)
    end,
    GetRecipeOutputItemData = function(recipeID)
        local r = FindRecipe(recipeID)
        return { hyperlink = r and r.itemLink }
    end,
    GetRecipeInfo = function(recipeID)
        local r = FindRecipe(recipeID)
        if r == nil then return nil end
        -- Forever reports 0 here even with the materials in your bags.
        local available = 0
        return { recipeID = recipeID, learned = r.learned ~= false, isEnchantingRecipe = r.isEnchant or false, numAvailable = available }
    end,
    CraftRecipe = function(recipeID, count)
        stub.crafted = stub.crafted or {}
        stub.crafted[#stub.crafted + 1] = { recipeID, count }
    end,
    GetAllRecipeIDs = function()
        local ids = {}
        for id in pairs(stub.recipes) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids
    end,
    GetFilteredRecipeIDs = function()
        return stub.filteredRecipeIDs or C_TradeSkillUI.GetAllRecipeIDs()
    end,
    GetBaseProfessionInfo = function() return stub.profession end,
    IsTradeSkillReady = function() return stub.tradeSkill.ready end,
    IsDataSourceChanging = function() return stub.tradeSkill.changing end,
    IsTradeSkillLinked = function() return stub.tradeSkill.linked end,
    IsTradeSkillGuild = function() return stub.tradeSkill.guild end,
    IsNPCCrafting = function() return stub.tradeSkill.npc end,
}

-- Opens a profession window with these recipes and lets the addon save them.
function stub.OpenProfession(id, name, recipes)
    stub.profession = { professionID = id, professionName = name }
    stub.recipes = {}
    for _, r in ipairs(recipes) do stub.recipes[r.recipeID] = r end
    if ProfessionsFrame then ProfessionsFrame:Show() end
    stub.Fire("TRADE_SKILL_SHOW")
    stub.Fire("TRADE_SKILL_LIST_UPDATE")
    stub.RunTimers()
end

local transaction = {
    CreateCraftingReagentInfoTbl = function() return {} end,
    GetAllocationItemGUID = function() return nil end,
}

ProfessionsFrame = CreateFrame("Frame", "ProfessionsFrame")
-- Closing the window: the game still reports the last profession afterwards.
function stub.CloseProfession()
    ProfessionsFrame:Hide()
    stub.Fire("TRADE_SKILL_CLOSE")
end
ProfessionsFrame.CloseButton = CreateFrame("Button", nil, ProfessionsFrame)
ProfessionsFrame.CraftingPage = { SchematicForm = CreateFrame("Frame", nil, ProfessionsFrame) }
function ProfessionsFrame.CraftingPage:SelectRecipe(info) stub.selectedRecipe = info.recipeID end
ProfessionsFrame.recipesTabID, stub.professionsTab = 1, 1
function ProfessionsFrame:GetTab() return stub.professionsTab end
function ProfessionsFrame:SetTab(id) stub.professionsTab = id end
local form = ProfessionsFrame.CraftingPage.SchematicForm
function form:GetRecipeInfo()
    local r = stub.recipe
    if r == nil then return nil end
    return { recipeID = r.recipeID, name = r.name, isEnchantingRecipe = r.isEnchant or false }
end
function form:GetCurrentRecipeLevel() return nil end
function form:GetTransaction() return transaction end

-- Auctionator ------------------------------------------------------------------
stub.auctionPrices = {}  -- itemID -> copper
stub.vendorPrices = {}   -- itemID -> copper (what a vendor sells it for)
stub.craftCostOverride = nil

Auctionator = { API = { v1 = {} }, CraftingInfo = {}, Constants = { AfterAHCut = 0.95 } }
function verify(callerID)
    if type(callerID) ~= "string" or callerID == "" then error("Invalid callerID. Use the name of your add-on.") end
end
function Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID) verify(callerID) return stub.auctionPrices[itemID] end
function Auctionator.API.v1.GetAuctionPriceByItemLink(callerID, link) verify(callerID) return stub.auctionPrices[ToID(link)] end
function Auctionator.API.v1.MultiSearchAdvanced(callerID, terms) verify(callerID) stub.searched = terms end
function Auctionator.API.v1.GetVendorPriceByItemID(callerID, itemID) verify(callerID) return stub.vendorPrices[itemID] end

function Auctionator.CraftingInfo.CalculateCraftCost(recipeSchematic)
    if stub.craftCostOverride then return stub.craftCostOverride end
    local total = 0
    for _, slot in ipairs(recipeSchematic.reagentSlotSchematics) do
        if slot.reagentType == Enum.CraftingReagentType.Basic then
            local id = slot.reagents[1].itemID
            local price = stub.vendorPrices[id] or stub.auctionPrices[id] or 0
            total = total + price * slot.quantityRequired
        end
    end
    return total
end

-- Like Auctionator's: creates the frame under the schematic form once, on
-- TRADE_SKILL_SHOW. Its UpdateTotal rewrites its own text.
function Auctionator.CraftingInfo.InitializeProfessionsFrame()
    if _G.AuctionatorCraftingInfoProfessionsFrame then return end
    local f = CreateFrame("Frame", "AuctionatorCraftingInfoProfessionsFrame", form)
    f.Total = f:CreateFontString()
    function f:UpdateTotal()
        self.Total:SetText("To Craft: x\nProfit: y")
    end
    stub.auctionatorFrame = f
end

local auctionatorEvents = CreateFrame("Frame")
auctionatorEvents:RegisterEvent("TRADE_SKILL_SHOW")
auctionatorEvents:SetScript("OnEvent", function()
    local init = Auctionator.CraftingInfo.InitializeProfessionsFrame
    if init then init() end
end)

-- Selecting a recipe: Blizzard's Init runs, Auctionator refreshes if visible.
function stub.SetRecipe(r)
    stub.recipe = r
    local f = _G.AuctionatorCraftingInfoProfessionsFrame
    if f then
        f:SetShown(r ~= nil)
        if f:IsVisible() then f:UpdateTotal() end
    end
end

-- Hovers the route line: returns the tooltip's lines as "left | right".
function stub.HoverRoute()
    local hover = AuctionatorCraftingInfoProfessionsFrame.VendorProfitRoute.hover
    hover.__scripts.OnEnter(hover)
    local out = {}
    for _, l in ipairs(GameTooltip.lines) do
        out[#out + 1] = l.right and (l.left .. " | " .. l.right) or l.left
    end
    return table.concat(out, "\n")
end

-- Professions window Create box.
stub.createCount = 1
ProfessionsFrame.CraftingPage.CreateMultipleInputBox = { GetValue = function() return stub.createCount end }

-- Auction house --------------------------------------------------------------
-- ah.listings[itemID] = { { unitPrice, quantity, own }, ... } for stackable items;
-- ah.nonCommodity[itemID] = true for items that don't stack.
stub.ah = {
    listings = {}, nonCommodity = {}, ready = true, pageSize = 100, loaded = {},
    searches = {}, starts = {}, confirms = {}, cancels = 0,
    dropSearches = 0,     -- ignore this many searches (no reply)
    emptyReplies = 0,     -- answer this many searches with "no results loaded"
    failNext = false,     -- next confirm fails
    toMail = false,       -- purchases go to the mailbox instead of the bags
    noPurchaseReply = false,
    quotePriceChange = 0, -- added to every quote's total
}
local ah = stub.ah
UIParent = UIParent or CreateFrame("Frame", "UIParent")
AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame")
AuctionHouseFrame:Hide()

local function Later(fn) C_Timer.After(0.1, fn) end
local function Rows(id) return ah.listings[id] or {} end
local function WalkListings(id, quantity)
    local total, got = 0, 0
    for _, row in ipairs(Rows(id)) do
        local buyable = row.quantity - (row.own or 0)
        local take = math.min(buyable, quantity - got)
        if take > 0 then total = total + take * row.unitPrice; got = got + take end
        if got >= quantity then break end
    end
    return total, got
end

C_AuctionHouse = {
    MakeItemKey = function(id) return { itemID = id } end,
    IsThrottledMessageSystemReady = function() return ah.ready end,
    SendSearchQuery = function(itemKey)
        local id = itemKey.itemID
        ah.searches[#ah.searches + 1] = id
        if ah.dropSearches > 0 then ah.dropSearches = ah.dropSearches - 1 return end
        ah.loaded[id] = math.min(ah.pageSize, #Rows(id))
        local empty = false
        if ah.emptyReplies > 0 then ah.emptyReplies = ah.emptyReplies - 1; empty = true end
        Later(function()
            ah.forceEmpty = empty
            if ah.nonCommodity[id] then
                stub.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = id })
            else
                stub.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", id)
            end
            ah.forceEmpty = false
        end)
    end,
    HasSearchResults = function() return true end,
    HasFullCommoditySearchResults = function(id) return not ah.forceEmpty and (ah.loaded[id] or 0) >= #Rows(id) end,
    GetNumCommoditySearchResults = function(id) if ah.forceEmpty then return 0 end return ah.loaded[id] or 0 end,
    GetCommoditySearchResultInfo = function(id, i)
        local row = Rows(id)[i]
        return row and { unitPrice = row.unitPrice, quantity = row.quantity, numOwnerItems = row.own or 0, containsOwnerItem = (row.own or 0) > 0 }
    end,
    RequestMoreCommoditySearchResults = function(id)
        ah.moreRequests = (ah.moreRequests or 0) + 1
        ah.loaded[id] = math.min((ah.loaded[id] or 0) + ah.pageSize, #Rows(id))
        Later(function() stub.Fire("COMMODITY_SEARCH_RESULTS_ADDED", id) end)
    end,
    StartCommoditiesPurchase = function(id, quantity)
        ah.starts[#ah.starts + 1] = { id, quantity }
        Later(function()
            local total, got = WalkListings(id, quantity)
            if got < quantity then
                stub.Fire("COMMODITY_PRICE_UNAVAILABLE")
            else
                total = total + ah.quotePriceChange
                stub.Fire("COMMODITY_PRICE_UPDATED", math.ceil(total / quantity), total)
            end
        end)
    end,
    CancelCommoditiesPurchase = function() ah.cancels = ah.cancels + 1 end,
    ConfirmCommoditiesPurchase = function(id, quantity)
        ah.confirms[#ah.confirms + 1] = { id, quantity }
        if ah.noPurchaseReply then return end
        Later(function()
            if ah.failNext then ah.failNext = false; stub.Fire("COMMODITY_PURCHASE_FAILED") return end
            local total = WalkListings(id, quantity)
            -- remove bought listings
            local left = quantity
            for _, row in ipairs(Rows(id)) do
                local take = math.min(row.quantity - (row.own or 0), left)
                row.quantity = row.quantity - take; left = left - take
            end
            stub.money = stub.money - total
            local where = ah.toMail and stub.mail or stub.bags
            where[id] = (where[id] or 0) + quantity
            stub.Fire("COMMODITY_PURCHASE_SUCCEEDED")
            if not ah.toMail then stub.Fire("BAG_UPDATE_DELAYED") end
        end)
    end,
}

function stub.OpenAH()
    AuctionHouseFrame:Show()
    stub.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21)
    stub.Fire("AUCTION_HOUSE_SHOW")
end
function stub.CloseAH()
    AuctionHouseFrame:Hide()
    stub.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 21)
    stub.Fire("AUCTION_HOUSE_CLOSED")
end


-- Bank -----------------------------------------------------------------------
-- Containers hold slots: stub.containers[bag][slot] = { itemID, count, locked }.
-- Bags 0-4 (16 slots each), the reagent bag 5, bank tabs 6-11 (20 slots each).
-- Moving between them keeps stub.bags / stub.bank (what GetItemCount sees) in step.
NUM_BAG_SLOTS = 4
Constants = { InventoryConstants = { NumReagentBagSlots = 1, NumCharacterBankSlots = 6 } }
BANK_CONTAINER, REAGENTBANK_CONTAINER = -1, -3
stub.containers = {}
local function SlotsIn(bag)
    if bag >= 0 and bag <= 4 then return 16 end
    if bag >= 6 and bag <= 11 then return 20 end
    return 0
end
local function IsBankBag(bag) return bag >= 6 and bag <= 11 end
local function Slot(bag, slot) return stub.containers[bag] and stub.containers[bag][slot] end
local function SetSlot(bag, slot, v) stub.containers[bag] = stub.containers[bag] or {}; stub.containers[bag][slot] = v end

-- Puts count of an item into a bank tab slot (and counts it as in the bank).
function stub.PutInBank(bag, slot, itemID, count)
    SetSlot(bag, slot, { itemID = itemID, count = count })
    stub.bank[itemID] = (stub.bank[itemID] or 0) + count
end
-- Fills a bag slot with something else (to make bags full).
function stub.FillBags()
    for bag = 0, 4 do for slot = 1, 16 do
        if not Slot(bag, slot) then SetSlot(bag, slot, { itemID = 1, count = 1 }) end
    end end
end

local cursor
stub.splits = {}
C_Container = {
    GetContainerNumSlots = function(bag) return SlotsIn(bag) end,
    GetContainerItemInfo = function(bag, slot)
        local s = Slot(bag, slot)
        if s == nil or s.count <= 0 then return nil end
        return { itemID = s.itemID, stackCount = s.count, isLocked = s.locked or false }
    end,
    SplitContainerItem = function(bag, slot, count)
        local s = Slot(bag, slot)
        stub.splits[#stub.splits + 1] = { bag, slot, count }
        if s and count <= s.count then cursor = { bag = bag, slot = slot, itemID = s.itemID, count = count } end
    end,
    PickupContainerItem = function(bag, slot)
        if cursor and Slot(bag, slot) == nil then
            local from = Slot(cursor.bag, cursor.slot)
            from.count = from.count - cursor.count
            if from.count <= 0 then SetSlot(cursor.bag, cursor.slot, nil) end
            SetSlot(bag, slot, { itemID = cursor.itemID, count = cursor.count, locked = stub.lockMoves })
            if IsBankBag(cursor.bag) and not IsBankBag(bag) then
                stub.bank[cursor.itemID] = stub.bank[cursor.itemID] - cursor.count
                stub.bags[cursor.itemID] = (stub.bags[cursor.itemID] or 0) + cursor.count
            end
            cursor = nil
        end
    end,
}
function ClearCursor() cursor = nil end
function GetCursorInfo() return cursor and "item" or nil end

BankFrame = CreateFrame("Frame", "BankFrame")
BankFrame:Hide()
function stub.OpenBank() BankFrame:Show(); stub.Fire("BANKFRAME_OPENED") end
function stub.CloseBank() BankFrame:Hide(); stub.Fire("BANKFRAME_CLOSED") end

-- Mailbox: one mail per item in stub.mail, the item as its only attachment.
ATTACHMENTS_MAX_RECEIVE = 16
local function Mails()
    local list = {}
    for id, n in pairs(stub.mail) do if n > 0 then list[#list + 1] = { id, n } end end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    return list
end
function GetInboxNumItems() local n = #Mails() return n, n end
function GetInboxItem(index, attachment)
    local m = Mails()[index]
    if m and attachment == 1 then return "item", m[1], "icon", m[2] end
end

-- Batch lookups (browse results): one result per listed item, lowest price and
-- how many are listed, from ah.listings.
stub.ah.itemKeySearches = {}
stub.ah.dropBrowse = false
C_AuctionHouse.SearchForItemKeys = function(keys)
    local ids = {}
    for _, key in ipairs(keys) do ids[#ids + 1] = key.itemID end
    stub.ah.itemKeySearches[#stub.ah.itemKeySearches + 1] = ids
    if stub.ah.dropBrowse then return end
    C_Timer.After(0.1, function()
        local results = {}
        for _, id in ipairs(ids) do
            local min, total
            for _, row in ipairs(stub.ah.listings[id] or {}) do
                local n = row.quantity - (row.own or 0)
                if n > 0 then
                    min = math.min(min or row.unitPrice, row.unitPrice)
                    total = (total or 0) + n
                end
            end
            if min then results[#results + 1] = { itemKey = { itemID = id }, minPrice = min, totalQuantity = total } end
        end
        stub.ah.browseResults = results
        -- Auctionator saving browse results to its prices (when a test asks).
        if stub.ah.auctionatorSaves then
            for _, r in ipairs(results) do stub.auctionPrices[r.itemKey.itemID] = r.minPrice end
        end
        stub.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    end)
end
C_AuctionHouse.GetBrowseResults = function() return stub.ah.browseResults or {} end
C_AuctionHouse.HasFullBrowseResults = function() return true end
C_AuctionHouse.RequestMoreBrowseResults = function() end
C_TradeSkillUI.OpenRecipe = function(recipeID) stub.openedRecipe = recipeID end
function Auctionator.API.v1.RegisterForDBUpdate(callerID, fn) verify(callerID) stub.dbUpdate = fn end

-- Merchant ---------------------------------------------------------------------
-- stub.merchant = { { itemID, price, stackCount, numAvailable, extended } }.
-- Buying puts the items in your bags and takes the gold.
stub.merchant = {}
stub.merchantBuys = {}
MerchantFrame = CreateFrame("Frame", "MerchantFrame")
MerchantFrame:Hide()
function GetMerchantNumItems() return #stub.merchant end
function GetMerchantItemID(index) return stub.merchant[index] and stub.merchant[index].itemID end
function GetMerchantItemLink(index) local m = stub.merchant[index]; return m and ("item:" .. m.itemID) end
function GetMerchantItemMaxStack(index) return stub.merchant[index].maxStack or 20 end
function GetMerchantItemCostInfo(index) return stub.merchant[index].extended and 1 or 0 end
C_MerchantFrame = {
    GetItemInfo = function(index)
        local m = stub.merchant[index]
        if m == nil then return nil end
        return { price = m.price, stackCount = m.stackCount or 1, numAvailable = m.numAvailable or -1,
                 hasExtendedCost = m.extended or false }
    end,
}
function BuyMerchantItem(index, quantity)
    local m = stub.merchant[index]
    local stackCount = m.stackCount or 1
    -- No quantity: one batch. A quantity: that many items.
    local count = quantity or stackCount
    stub.merchantBuys[#stub.merchantBuys + 1] = { itemID = m.itemID, quantity = quantity }
    stub.money = stub.money - m.price * count / stackCount
    -- stub.merchantDelay: the items arrive that much later (never, if
    -- stub.merchantLost), as in the game.
    local function Deliver()
        stub.bags[m.itemID] = (stub.bags[m.itemID] or 0) + count
    end
    if stub.merchantLost then
        return
    elseif stub.merchantDelay then
        C_Timer.After(stub.merchantDelay, function() Deliver(); stub.Fire("BAG_UPDATE_DELAYED") end)
    else
        Deliver()
        C_Timer.After(0, function() stub.Fire("BAG_UPDATE_DELAYED") end)
    end
end
function stub.OpenMerchant(items)
    stub.merchant = items
    MerchantFrame:Show()
    stub.Fire("MERCHANT_SHOW")
end
function stub.CloseMerchant()
    MerchantFrame:Hide()
    stub.Fire("MERCHANT_CLOSED")
end
