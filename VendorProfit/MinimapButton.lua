-- The minimap button: a round button on the minimap's edge, in the usual
-- minimap-button look (the game's own textures) with the addon's coin icon.
-- Clicking it opens or closes the Vendor Profit window, on the tab last used;
-- dragging it moves it around the edge. /vprofit minimap hides or shows it.
--
-- Our own small button rather than a library (LibDBIcon and the like): the
-- addon needs nothing but Auctionator.
--
-- Saved for the whole account in VendorProfitDB.minimap = { angle, hide }:
-- angle in degrees around the minimap's center (0 = right, 90 = top).

local _, ns = ...
local VendorProfit = ns.VendorProfit
local Panel = VendorProfit.Panel
local L = VendorProfit.L

local MinimapButton = {}
VendorProfit.MinimapButton = MinimapButton

-- Where it starts: lower left, where minimap buttons usually go.
MinimapButton.DEFAULT_ANGLE = 225
-- How far outside the minimap's edge its center sits.
local OUTSET = 5
local ICON = "Interface\\Icons\\INV_Misc_Coin_02"

local button

local function DB()
    VendorProfitDB = VendorProfitDB or {}
    VendorProfitDB.minimap = VendorProfitDB.minimap or {}
    return VendorProfitDB.minimap
end

-- Puts the button on the minimap's edge at its angle. On a square minimap
-- (GetMinimapShape, set by minimap addons that make it square) it follows
-- the square's edge instead of a circle.
local function Place()
    local angle = math.rad(DB().angle or MinimapButton.DEFAULT_ANGLE)
    local x, y = math.cos(angle), math.sin(angle)
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        local stretch = 1 / math.max(math.abs(x), math.abs(y))
        x, y = x * stretch, y * stretch
    end
    local width = Minimap:GetWidth() / 2 + OUTSET
    local height = Minimap:GetHeight() / 2 + OUTSET
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * width, y * height)
end

-- While dragging: the angle from the minimap's center to the cursor.
local function FollowCursor()
    local centerX, centerY = Minimap:GetCenter()
    if centerX == nil then
        return
    end
    local scale = Minimap:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX, cursorY = cursorX / scale, cursorY / scale
    DB().angle = math.deg(math.atan2(cursorY - centerY, cursorX - centerX)) % 360
    Place()
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(L.PANEL_TITLE)
    GameTooltip:AddLine(L.MINIMAP_CLICK, 1, 1, 1)
    GameTooltip:AddLine(L.MINIMAP_DRAG, 1, 1, 1)
    GameTooltip:AddLine(L.MINIMAP_HIDE, GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
    GameTooltip:Show()
end

local function Create()
    if button or Minimap == nil then
        return
    end
    button = CreateFrame("Button", "VendorProfitMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- The usual round minimap button: a dark disc, the icon, a gold ring.
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6)
    -- The icon's own border trimmed off, to sit inside the ring.
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    button:SetScript("OnClick", function()
        GameTooltip:Hide()
        Panel.Toggle()
    end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", FollowCursor)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        FollowCursor()
    end)

    Place()
    button:SetShown(not DB().hide)
end

-- /vprofit minimap: hides or shows the button, and says how to undo it.
function MinimapButton.Toggle()
    local db = DB()
    db.hide = not db.hide or nil
    Create()
    if button then
        button:SetShown(not db.hide)
    end
    print(db.hide and L.MINIMAP_HIDDEN or L.MINIMAP_SHOWN)
end

function MinimapButton.Button()
    return button
end

-- The minimap's shape or size can change (a minimap addon loading later).
function MinimapButton.Place()
    if button then
        Place()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    -- The account's saved data is loaded by now.
    Create()
    -- Minimap addons may reshape the minimap as they load, just after.
    C_Timer.After(1, MinimapButton.Place)
end)
