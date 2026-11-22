-- Turn-ins: items an NPC trades for others, which any character of the
-- level can do, so Best Crafts can price them like recipes: 200 Thorium
-- Shells, bought or crafted, handed in for 200 Thorium Headed Arrows.
--
-- Each is priced as a recipe that makes `made` of `get` from `count` of
-- `give`, under its own "Turn-ins" heading (not a profession: anyone can do
-- them). They're only priced, never queued: the Shopping List can't hand in
-- a quest. The recipe ID is the output's item ID made negative, so it can't
-- clash with a real recipe (a spell ID) and still sorts as a number.
--
-- The repeatable quests, per faction, from the wiki (warcraft.wiki.gg):
-- "Arrows Are For Sissies" (7342), Artilleryman Sheldonore in Ironforge,
-- requires level 52; "A Fair Trade" (7341), Bounty Hunter Kolark in
-- Orgrimmar, listed as requiring 60.

local _, ns = ...
local VendorProfit = ns.VendorProfit
local L = VendorProfit.L

local TurnIns = {}
VendorProfit.TurnIns = TurnIns

-- The Best Crafts heading (and Filter menu entry) they're listed under.
TurnIns.KEY = "turnins"

TurnIns.LIST = {
    {
        give = 15997, count = 200,    -- Thorium Shells
        get = 18042, made = 200,      -- Thorium Headed Arrow
        Alliance = { quest = 7342, level = 52, npc = L.TURN_IN_SHELDONORE, place = L.TURN_IN_IRONFORGE },
        Horde = { quest = 7341, level = 60, npc = L.TURN_IN_KOLARK, place = L.TURN_IN_ORGRIMMAR },
    },
}

-- The turn-ins this character can do (by faction and level), as recipes:
-- { recipeID, item, count, reagents, profession, professionKey, turnIn =
-- { give, count, npc, place } }.
function TurnIns.Recipes()
    local list = {}
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local level = UnitLevel and UnitLevel("player") or 0
    for _, turnIn in ipairs(TurnIns.LIST) do
        local side = faction and turnIn[faction]
        if side and level >= side.level then
            list[#list + 1] = {
                recipeID = -turnIn.get,
                item = turnIn.get,
                count = turnIn.made,
                reagents = { { items = { turnIn.give }, quantity = turnIn.count } },
                profession = L.TURN_INS,
                professionKey = TurnIns.KEY,
                turnIn = { give = turnIn.give, count = turnIn.count, npc = side.npc, place = side.place },
            }
        end
    end
    return list
end
