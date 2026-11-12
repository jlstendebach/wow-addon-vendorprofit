-- Opening a profession window from the shopping panel's Craft button, when
-- the next step is in a profession that isn't open ("Open Mining to craft
-- Copper Bar").
--
-- In Forever an addon can only open a profession through a secure action
-- button that casts the profession's spell (Mining opens with Smelting), the
-- same way TradeSkillMaster does it. A secure button inside the panel would
-- make the whole panel protected, so the game would block showing, hiding or
-- moving it in combat. Instead this is a separate, invisible secure button
-- laid exactly over the Craft button. It's only placed out of combat, and
-- hidden as combat starts, so the panel itself stays unprotected.

local _, ns = ...
local VendorProfit = ns.VendorProfit
local L = VendorProfit.L

local OpenButton = {}
VendorProfit.OpenButton = OpenButton

local MINING_SPELL, SMELTING_SPELL = 2575, 2656

local button
local target             -- the button it's laid over
local placed             -- where it was put: "left,bottom,width,height"
local opening            -- { profession, expires } after a click, until it opens
local OPENING_TIMEOUT = 3
local FOLLOW_INTERVAL = 0.1

local function SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    return (GetSpellInfo(spellID))
end

-- The spell that opens a profession's window: its own name, except Mining,
-- whose window opens with Smelting.
function OpenButton.SpellFor(profession)
    if profession ~= nil and profession == SpellName(MINING_SPELL) then
        return SpellName(SMELTING_SPELL) or profession
    end
    return profession
end

local function Create()
    button = CreateFrame("Button", "VendorProfitOpenProfessionButton", UIParent, "SecureActionButtonTemplate")
    button:SetFrameStrata("DIALOG")
    button:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "LeftButtonDown" or "LeftButtonUp")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(string.format(L.OPEN_PROFESSION_HELP, self.profession or ""), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Clicked: the profession is on its way. Casting its spell again would
    -- close the window it's opening, so the button goes away until it's open
    -- (or a few seconds pass), and the panel checks back as it loads.
    button:SetScript("PostClick", function(self)
        opening = { profession = self.profession, expires = GetTime() + OPENING_TIMEOUT }
        if not InCombatLockdown() then
            self:Hide()
        end
        if VendorProfit.Panel then
            VendorProfit.Panel.Refresh()
        end
        for _, delay in ipairs({ 0.5, 1.5, OPENING_TIMEOUT + 0.1 }) do
            C_Timer.After(delay, function()
                if VendorProfit.Panel then
                    VendorProfit.Panel.Refresh()
                end
            end)
        end
    end)
    button:Hide()
end

-- Whether that profession was just clicked open and hasn't finished opening.
function OpenButton.IsOpening(profession)
    if opening == nil or GetTime() >= opening.expires then
        opening = nil
        return false
    end
    return opening.profession == profession
end

-- It's open: stop waiting.
function OpenButton.Opened()
    opening = nil
end

-- Puts the secure button exactly over over. Placed on the screen, not
-- anchored to it: anchoring a secure frame to the panel would make the panel
-- protected too. So it doesn't move with the panel by itself; Follow moves it.
local function Place(over)
    local left, bottom = over:GetLeft(), over:GetBottom()
    if left == nil or bottom == nil then
        return false
    end
    local scale = over:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local width, height = over:GetWidth() * scale, over:GetHeight() * scale
    left, bottom = left * scale, bottom * scale
    local where = string.format("%.1f,%.1f,%.1f,%.1f", left, bottom, width, height)
    if where ~= placed or target ~= over then
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        button:SetSize(width, height)
        placed, target = where, over
    end
    return true
end

-- Lays the secure button over a button so clicking it opens profession.
-- Does nothing in combat. Returns true if it's in place.
function OpenButton.Cover(over, profession)
    if InCombatLockdown() then
        return false
    end
    if button == nil then
        Create()
    end
    local spell = OpenButton.SpellFor(profession)
    if spell == nil or not Place(over) then
        button:Hide()
        return false
    end
    button:SetAttribute("type", "spell")
    button:SetAttribute("spell", spell)
    button.profession = profession
    button:Show()
    return true
end

function OpenButton.Hide()
    if button and not InCombatLockdown() then
        button:Hide()
    end
end

-- Keeps the cover over its button when the panel moves without redrawing:
-- its height changes while it's centered, say. Gone from view: the cover
-- goes too.
function OpenButton.Follow()
    if button == nil or not button:IsShown() or target == nil or InCombatLockdown() then
        return
    end
    if not target:IsVisible() or not Place(target) then
        button:Hide()
    end
end

local follower = CreateFrame("Frame")
local sinceFollow = 0
follower:SetScript("OnUpdate", function(_, elapsed)
    sinceFollow = sinceFollow + elapsed
    if sinceFollow >= FOLLOW_INTERVAL then
        sinceFollow = 0
        OpenButton.Follow()
    end
end)

function OpenButton.IsShown()
    return button ~= nil and button:IsShown()
end

-- Combat is about to start: the last moment the secure button can be hidden.
-- After combat, or when the screen's size or the UI scale changes (which can
-- happen on alt-tab), the panel redraws and the cover is placed again.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(events.RegisterEvent, events, "DISPLAY_SIZE_CHANGED")
pcall(events.RegisterEvent, events, "UI_SCALE_CHANGED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if button then
            button:Hide()
        end
    elseif VendorProfit.Panel then
        VendorProfit.Panel.Refresh()
    end
end)
