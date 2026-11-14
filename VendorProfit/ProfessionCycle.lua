-- Going through your professions for Best Crafts: the game only gives a
-- profession's recipes (and their skill-up colors) while its window is
-- open, so the Professions button on Best Crafts opens each in turn, one
-- click at a time, and a last click closes the window. Made to be clicked
-- repeatedly:
--
--   * Each profession opens through the secure cover (OpenButton.lua): an
--     addon can only open one by casting its spell from a secure button.
--   * After a click it waits ("Opening...") until that profession is open
--     and saved (Recipes.lua), so clicking fast can't skip one before it's
--     saved; if it doesn't open within a few seconds, the click can be
--     tried again.
--   * The profession already open when it starts is saved already, so it's
--     skipped (casting its spell again would close it).
--   * Fishing is included: Forever gives it a window (Camping), opened with
--     Bait and Tackle (OpenButton.SpellFor).
--   * After the closing click the button rests for a second, so a click too
--     many doesn't start it all over again.
--   * Closing the window yourself part way through starts it over.

local _, ns = ...
local VendorProfit = ns.VendorProfit
local Recipes = VendorProfit.Recipes

local ProfessionCycle = {}
VendorProfit.ProfessionCycle = ProfessionCycle

ProfessionCycle.OPEN_TIMEOUT = 3
ProfessionCycle.COOLDOWN = 1

local run           -- { list, index (next to open), waiting = { entry, since } } part way through
local restUntil     -- GetTime() the button rests until, after closing

local function Redraw()
    if VendorProfit.BestPanel then
        VendorProfit.BestPanel.Refresh()
    end
end

local function IsOpen(entry)
    if not Recipes.WindowOpen() then
        return false
    end
    local key, name = Recipes.OpenProfession()
    return key ~= nil and (key == entry.key or name == entry.name)
end

-- Your professions to open: all with a window but the one open now.
local function ToOpen()
    local list = {}
    for _, entry in ipairs(Recipes.PlayerProfessions()) do
        if not IsOpen(entry) then
            list[#list + 1] = entry
        end
    end
    return list
end

-- Saved since it was clicked open.
local function Saved(waiting)
    local scan = Recipes.LastScan()
    return scan ~= nil and scan.time >= waiting.since
        and (scan.key == waiting.entry.key or scan.name == waiting.entry.name)
end

-- What the button does next: { action, entry, index, count, started (part
-- way through) }. action:
--   "open"  - opens entry, the index-th of count
--   "wait"  - entry was clicked open and isn't saved yet
--   "close" - closes the professions window, the last click
--   "rest"  - just closed: a second before it can start again
--   "none"  - no profession to open
function ProfessionCycle.State()
    if restUntil and GetTime() < restUntil then
        return { action = "rest" }
    end
    restUntil = nil
    if run == nil then
        local list = ToOpen()
        if #list > 0 then
            return { action = "open", entry = list[1], index = 1, count = #list }
        end
        return { action = Recipes.WindowOpen() and "close" or "none" }
    end
    local waiting = run.waiting
    if waiting then
        if Saved(waiting) then
            run.index, run.waiting = run.index + 1, nil
        elseif GetTime() - waiting.since < ProfessionCycle.OPEN_TIMEOUT then
            return { action = "wait", entry = waiting.entry, index = run.index, count = #run.list }
        else
            -- Didn't open: the same one again.
            run.waiting = nil
        end
    end
    if run.index > #run.list then
        return { action = "close", started = true }
    end
    return { action = "open", entry = run.list[run.index], index = run.index, count = #run.list, started = true }
end

-- The cover was clicked to open entry (the State's): wait for it.
function ProfessionCycle.Opened(entry)
    if run == nil then
        run = { list = ToOpen(), index = 1 }
    end
    run.waiting = { entry = entry, since = GetTime() }
    -- Saving redraws Best Crafts; this is for when it never opens.
    C_Timer.After(ProfessionCycle.OPEN_TIMEOUT + 0.1, Redraw)
end

-- The last click: closes the window, and rests.
function ProfessionCycle.Close()
    run = nil
    restUntil = GetTime() + ProfessionCycle.COOLDOWN
    if C_TradeSkillUI.CloseTradeSkill then
        C_TradeSkillUI.CloseTradeSkill()
    end
    C_Timer.After(ProfessionCycle.COOLDOWN + 0.05, Redraw)
    Redraw()
end

-- Closed some other way between professions: start over. (While one is
-- opening, the window can close as it switches professions.)
local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "TRADE_SKILL_CLOSE")
events:SetScript("OnEvent", function()
    if run and run.waiting == nil then
        run = nil
        Redraw()
    end
end)
