-- Minimal WoW client + Auctionator stub: just enough to load VendorProfit and
-- drive Auctionator's crafting info frame the way the real addon does.
local stub = {}
_G.__stub = stub

stub.metadata = {}
stub.items = {}          -- itemLink -> { sellPrice = n } ; cached = true when loaded
stub.loadCallbacks = {}  -- itemLink -> { fn, ... }
stub.timers = {}
stub.errors = {}
stub.recipe = nil        -- what the schematic form is showing (see SetRecipe)
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
function FrameMethods:Hide() self.__shown = false end
function FrameMethods:SetShown(s) self.__shown = not not s end
function FrameMethods:IsShown() return self.__shown end
function FrameMethods:IsVisible()
    if not self.__shown then return false end
    if self.__parent and self.__parent.IsVisible then return self.__parent:IsVisible() end
    return true
end
function FrameMethods:RegisterEvent(e) self.__events[e] = true end
function FrameMethods:UnregisterAllEvents() self.__events = {} end
function FrameMethods:SetScript(k, fn) self.__scripts[k] = fn end
function FrameMethods:CreateFontString()
    return setmetatable({ __shown = true, __parent = self, __text = "" }, FontMethods)
end

function FontMethods:SetText(t) self.__text = t or "" end
function FontMethods:GetText() return self.__text end
function FontMethods:SetJustifyH() end
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

function stub.RunTimers()
    local t = stub.timers
    stub.timers = {}
    for _, fn in ipairs(t) do fn() end
end

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
C_Timer = { After = function(_, fn) stub.timers[#stub.timers + 1] = fn end }
Enum = { CraftingReagentType = { Basic = 0, Optional = 1 } }

local function Color(code)
    return { WrapTextInColorCode = function(_, t) return "|cff" .. code .. t .. "|r" end }
end
WHITE_FONT_COLOR, RED_FONT_COLOR, GRAY_FONT_COLOR = Color("ffffff"), Color("ff2020"), Color("808080")

function GetMoneyString(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

C_Item = {
    GetItemInfo = function(link)
        local item = stub.items[link]
        if item == nil or not item.cached then return nil end
        return link, link, 2, 20, 0, "Armor", "Mail", 1, "INVTYPE_CHEST", 0, item.sellPrice
    end,
}

Item = {
    CreateFromItemLink = function(_, link)
        return {
            ContinueOnItemLoad = function(_, fn)
                local item = stub.items[link]
                if item and item.cached then fn() return end
                stub.loadCallbacks[link] = stub.loadCallbacks[link] or {}
                table.insert(stub.loadCallbacks[link], fn)
            end,
        }
    end,
}

function stub.LoadItem(link)
    stub.items[link].cached = true
    local fns = stub.loadCallbacks[link] or {}
    stub.loadCallbacks[link] = nil
    for _, fn in ipairs(fns) do fn() end
end

-- Professions window ---------------------------------------------------------
-- recipe = { recipeID, itemLink (nil = no item output), isEnchant, quantityMin,
--            reagents = { { itemID, quantity }, ... } }
C_TradeSkillUI = {
    GetRecipeSchematic = function(recipeID)
        local r = stub.recipe
        if r == nil or r.recipeID ~= recipeID then return nil end
        local slots = {}
        for _, reagent in ipairs(r.reagents) do
            slots[#slots + 1] = {
                reagentType = reagent.optional and Enum.CraftingReagentType.Optional or Enum.CraftingReagentType.Basic,
                quantityRequired = reagent.quantity,
                reagents = { { itemID = reagent.itemID } },
            }
        end
        return { recipeID = recipeID, quantityMin = r.quantityMin, quantityMax = r.quantityMin, reagentSlotSchematics = slots }
    end,
    GetRecipeOutputItemData = function(recipeID)
        local r = stub.recipe
        return { hyperlink = r and r.itemLink }
    end,
}

local transaction = {
    CreateCraftingReagentInfoTbl = function() return {} end,
    GetAllocationItemGUID = function() return nil end,
}

ProfessionsFrame = CreateFrame("Frame", "ProfessionsFrame")
ProfessionsFrame.CraftingPage = { SchematicForm = CreateFrame("Frame", nil, ProfessionsFrame) }
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

Auctionator = { API = { v1 = {} }, CraftingInfo = {} }
local function verify(callerID)
    if type(callerID) ~= "string" or callerID == "" then error("Invalid callerID. Use the name of your add-on.") end
end
function Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID) verify(callerID) return stub.auctionPrices[itemID] end
function Auctionator.API.v1.GetVendorPriceByItemID(callerID, itemID) verify(callerID) return stub.vendorPrices[itemID] end

function Auctionator.CraftingInfo.CalculateCraftCost(recipeSchematic)
    if stub.craftCostOverride then return stub.craftCostOverride end
    local total = 0
    for _, slot in ipairs(recipeSchematic.reagentSlotSchematics) do
        local id = slot.reagents[1].itemID
        local price = stub.vendorPrices[id] or stub.auctionPrices[id] or 0
        total = total + price * slot.quantityRequired
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
