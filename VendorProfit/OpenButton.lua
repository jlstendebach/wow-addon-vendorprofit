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
    button:Hide()
end

-- Lays the secure button over target so clicking target opens profession.
-- Does nothing in combat. Returns true if it's in place.
function OpenButton.Cover(target, profession)
    if InCombatLockdown() then
        return false
    end
    if button == nil then
        Create()
    end
    local spell = OpenButton.SpellFor(profession)
    local left, bottom = target:GetLeft(), target:GetBottom()
    if spell == nil or left == nil or bottom == nil then
        button:Hide()
        return false
    end
    -- Placed on the screen, not anchored to target: anchoring a secure frame
    -- to the panel would make the panel protected too.
    local scale = target:GetEffectiveScale() / UIParent:GetEffectiveScale()
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
    button:SetSize(target:GetWidth() * scale, target:GetHeight() * scale)
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

function OpenButton.IsShown()
    return button ~= nil and button:IsShown()
end

-- Combat is about to start: the last moment the secure button can be hidden.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if button then
            button:Hide()
        end
    elseif VendorProfit.Panel then
        VendorProfit.Panel.Refresh()
    end
end)
