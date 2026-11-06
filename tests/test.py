"""Loads VendorProfit into a stubbed WoW client + Auctionator (real Lua 5.1)
and checks the Vendor Profit and Vendor Profit (route) lines.

The stub mirrors how Auctionator's crafting info frame is created and
refreshed, but it is not the real client: anything here still needs checking
in game.

    pip install lupa
    python tests/test.py
"""
import pathlib
import re
import sys

from lupa import lua51

ADDON = pathlib.Path(__file__).resolve().parent.parent / "VendorProfit"
HERE = pathlib.Path(__file__).resolve().parent
TOC = (ADDON / "VendorProfit.toc").read_text()
FILES = re.findall(r"^(\w+\.lua)\s*$", TOC, re.M)
TOC_VERSION = re.search(r"^## Version: (.+)$", TOC, re.M).group(1).strip()

results = []


def check(label, cond):
    results.append((label, bool(cond)))
    print(("PASS " if cond else "FAIL ") + label)


def client(before_load=""):
    """A fresh client with VendorProfit loaded. before_load runs after the
    stub and before the addon, to change what the addon sees at load."""
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute((HERE / "wowstub.lua").read_text())
    lua.execute('__stub.metadata.VendorProfit = { Version = "%s" }' % TOC_VERSION)
    lua.execute(before_load)
    ns = lua.eval("{}")
    loader = lua.execute("return function(src, name) return assert(loadstring(src, name)) end")
    for name in FILES:
        loader((ADDON / name).read_text(), "@" + name)("VendorProfit", ns)
    lua.execute('__stub.Fire("ADDON_LOADED", "VendorProfit")')
    lua.execute('__stub.Fire("PLAYER_LOGIN")')
    return lua.execute, lua.eval


# Rough Bronze Cuirass: 7 Bronze Bars. Values are copper.
CUIRASS = """{
    recipeID = 2670, name = "Rough Bronze Cuirass", itemLink = "item:2866", quantityMin = 1,
    reagents = { { itemID = 2841, quantity = 7 } },
}"""

run, ev = client()
LINE = "AuctionatorCraftingInfoProfessionsFrame.VendorProfitLine"

# --- Loading and attaching ---------------------------------------------------
check("files loaded in toc order", FILES == ["Core.lua", "VendorLine.lua", "Recipes.lua", "Route.lua", "RouteLine.lua", "Inventory.lua", "Plan.lua", "Order.lua", "QueueButton.lua", "Shopper.lua", "Panel.lua"])
check("version read from the .toc", ev("VendorProfit.VERSION") == TOC_VERSION)
check("not attached before the professions window opens", not ev("VendorProfit.IsAttached()"))
run('__stub.Fire("TRADE_SKILL_SHOW")')
check("attached when Auctionator makes its frame", ev("VendorProfit.IsAttached()"))
check("line added to Auctionator's frame", ev(LINE) is not None)
check("line anchored under Auctionator's text",
      ev(LINE + ".__point[2] == AuctionatorCraftingInfoProfessionsFrame.Total"))
run('__stub.Fire("TRADE_SKILL_SHOW")')
check("opening again causes no errors", ev("#__stub.errors") == 0)

# --- Loss: Rough Bronze Cuirass ---------------------------------------------
run('__stub.items["item:2866"] = { sellPrice = 147, cached = true }')
run('__stub.auctionPrices[2841] = 177')  # Bronze Bar, 1s 77c each -> 12s 39c
run('__stub.SetRecipe(%s)' % CUIRASS)
check("line shown", ev(LINE + ":IsShown()"))
text = ev(LINE + ":GetText()")
check("loss shown in red as -10s 92c", text == "Vendor Profit: |cffff2020-10s 92c|r")
check("Auctionator's own lines untouched",
      ev("AuctionatorCraftingInfoProfessionsFrame.Total:GetText()") == "To Craft: x\nProfit: y")
r = ev("VendorProfit.Calculate(ProfessionsFrame.CraftingPage.SchematicForm)")
check("result: sell 147 x 1 - cost 1239", r.sellPrice == 147 and r.count == 1 and r.cost == 1239 and r.profit == -1092)

# --- Profit, several made ----------------------------------------------------
run('__stub.items["item:3470"] = { sellPrice = 30, cached = true }')
run('__stub.vendorPrices[2835] = 8')
run('''__stub.SetRecipe({
    recipeID = 3320, itemLink = "item:3470", quantityMin = 3,
    reagents = { { itemID = 2835, quantity = 2 } },
})''')
check("profit counts every item made: 30 x 3 - 16 = 74c",
      ev(LINE + ":GetText()") == "Vendor Profit: |cffffffff74c|r")

# --- Uses Auctionator's craft cost, so it matches To Craft -------------------
run('__stub.craftCostOverride = 50')
run('AuctionatorCraftingInfoProfessionsFrame:UpdateTotal()')
check("cost comes from Auctionator's CalculateCraftCost", ev("VendorProfit.Calculate(ProfessionsFrame.CraftingPage.SchematicForm).cost") == 50)
check("line follows Auctionator's refresh", ev(LINE + ":GetText()") == "Vendor Profit: |cffffffff40c|r")
run('__stub.craftCostOverride = nil')

# --- Missing reagent prices --------------------------------------------------
run('''__stub.SetRecipe({
    recipeID = 3321, itemLink = "item:3470", quantityMin = 1,
    reagents = { { itemID = 2835, quantity = 1 }, { itemID = 9999, quantity = 1 } },
})''')
check("warns when a reagent has no price",
      ev(LINE + ":GetText()") == "Vendor Profit: |cffffffff22c|r |cffff2020(missing reagent prices)|r")
run('''__stub.SetRecipe({
    recipeID = 3322, itemLink = "item:3470", quantityMin = 1,
    reagents = { { itemID = 2835, quantity = 1 }, { itemID = 9999, quantity = 1, optional = true } },
})''')
check("optional reagents without a price don't warn", "missing" not in ev(LINE + ":GetText()"))

# --- Items vendors won't buy -------------------------------------------------
run('__stub.items["item:5000"] = { sellPrice = 0, cached = true }')
run('__stub.SetRecipe({ recipeID = 4000, itemLink = "item:5000", quantityMin = 1, reagents = { { itemID = 2835, quantity = 1 } } })')
check("no vendor price says so in grey",
      ev(LINE + ":GetText()") == "Vendor Profit: |cff808080can't be sold to vendors|r")

# --- Recipes that make no item -------------------------------------------------
run('__stub.SetRecipe({ recipeID = 4001, itemLink = nil, quantityMin = 1, reagents = { { itemID = 2835, quantity = 1 } } })')
check("no item made: line hidden", not ev(LINE + ":IsShown()"))
run('__stub.SetRecipe({ recipeID = 4002, itemLink = "item:3470", isEnchant = true, quantityMin = 1, reagents = { { itemID = 2835, quantity = 1 } } })')
check("enchant: line hidden", not ev(LINE + ":IsShown()"))

# --- Item info not cached yet ------------------------------------------------
run('__stub.items["item:6000"] = { sellPrice = 500, cached = false }')
run('__stub.SetRecipe({ recipeID = 4003, itemLink = "item:6000", quantityMin = 1, reagents = { { itemID = 2835, quantity = 1 } } })')
check("uncached item: hidden while loading", not ev(LINE + ":IsShown()"))
run('AuctionatorCraftingInfoProfessionsFrame:UpdateTotal()')
check("only one load request per item", ev('#__stub.loadCallbacks["item:6000"]') == 1)
run('__stub.LoadItem("item:6000")')
check("shown once the item loads", ev(LINE + ":GetText()") == "Vendor Profit: |cffffffff4s 92c|r" and ev(LINE + ":IsShown()"))

run('__stub.items["item:6001"] = { sellPrice = 100, cached = false }')
run('__stub.SetRecipe({ recipeID = 4004, itemLink = "item:6001", quantityMin = 1, reagents = { { itemID = 2835, quantity = 1 } } })')
run('__stub.SetRecipe(%s)' % CUIRASS)
run('__stub.LoadItem("item:6001")')
check("a late load for another recipe still shows the current one", "-10s 92c" in ev(LINE + ":GetText()"))

# --- Hidden frame and errors -------------------------------------------------
run('__stub.SetRecipe(nil)')
check("hidden Auctionator frame: refresh does nothing", ev("(function() VendorProfit.Refresh() return #__stub.errors end)()") == 0)
run('__stub.SetRecipe(%s)' % CUIRASS)
run('C_TradeSkillUI.GetRecipeSchematic = function() error("boom") end')
ok = ev("(function() return pcall(AuctionatorCraftingInfoProfessionsFrame.UpdateTotal, AuctionatorCraftingInfoProfessionsFrame) end)()")
check("an error in VendorProfit doesn't break Auctionator's refresh", ok)
check("...but it is still reported", ev("#__stub.errors") == 1 and "boom" in ev("__stub.errors[1]"))
check("no errors other than the forced one", ev("#__stub.errors") == 1)

# --- Attach order --------------------------------------------------------------
# VendorProfit sees TRADE_SKILL_SHOW before Auctionator and Auctionator's init
# function has been renamed: the next-frame retry still attaches.
run2, ev2 = client('''
    __stub.renamedInit = Auctionator.CraftingInfo.InitializeProfessionsFrame
    Auctionator.CraftingInfo.InitializeProfessionsFrame = nil
''')
run2('''
    local f = CreateFrame("Frame")
    f:RegisterEvent("TRADE_SKILL_SHOW")
    f:SetScript("OnEvent", function() __stub.renamedInit() end)
''')
run2('__stub.Fire("TRADE_SKILL_SHOW")')
check("not attached yet when VendorProfit handles the event first", not ev2("VendorProfit.IsAttached()"))
run2('__stub.RunTimers()')
check("attached on the next frame", ev2("VendorProfit.IsAttached()"))

# =============================================================================
# Vendor Profit (route)
# =============================================================================
# Mining: Copper Ore -> Copper Bar, Tin Ore -> Tin Bar, Copper Bar + Tin Bar ->
# 2 Bronze Bars. Blacksmithing: 7 Bronze Bars -> Rough Bronze Cuirass.
COPPER_ORE, TIN_ORE, COPPER_BAR, TIN_BAR, BRONZE_BAR, CUIRASS_ID = 2770, 2771, 2840, 3576, 2841, 2866
MINING = """{
    { recipeID = 2657, itemLink = "item:2840", quantityMin = 1, reagents = { { itemID = 2770, quantity = 1 } } },
    { recipeID = 3304, itemLink = "item:3576", quantityMin = 1, reagents = { { itemID = 2771, quantity = 1 } } },
    { recipeID = 2659, itemLink = "item:2841", quantityMin = 2, reagents = { { itemID = 2840, quantity = 1 }, { itemID = 3576, quantity = 1 } } },
    { recipeID = 9999, itemLink = "item:1234", quantityMin = 1, learned = false, reagents = { { itemID = 2770, quantity = 1 } } },
}"""
NAMES = {COPPER_ORE: "Copper Ore", TIN_ORE: "Tin Ore", COPPER_BAR: "Copper Bar", TIN_BAR: "Tin Bar",
         BRONZE_BAR: "Bronze Bar", CUIRASS_ID: "Rough Bronze Cuirass"}
ROUTE = "AuctionatorCraftingInfoProfessionsFrame.VendorProfitRouteLine"


def route_client(before_load=""):
    run, ev = client(before_load)
    for item_id, name in NAMES.items():
        run('__stub.items["item:%d"] = { name = "%s", cached = true, sellPrice = 5 }' % (item_id, name))
    run('__stub.items["item:2866"].sellPrice = 147')
    # Auction prices: crafting copper bars is cheaper than buying them, buying
    # tin bars is cheaper than crafting them.
    run('''
        __stub.auctionPrices[2770] = 50   -- Copper Ore
        __stub.auctionPrices[2771] = 80   -- Tin Ore
        __stub.auctionPrices[2840] = 70   -- Copper Bar (craft: 50)
        __stub.auctionPrices[3576] = 75   -- Tin Bar (craft: 80)
        __stub.auctionPrices[2841] = 177  -- Bronze Bar (craft: (50 + 75) / 2 = 62.5)
        __stub.auctionPrices[2866] = 1300 -- Rough Bronze Cuirass
    ''')
    run('__stub.Fire("TRADE_SKILL_SHOW")')
    return run, ev


run, ev = route_client()

# --- Before Mining has been opened ------------------------------------------
run('__stub.OpenProfession(164, "Blacksmithing", { %s })' % CUIRASS)
run('__stub.SetRecipe(%s)' % CUIRASS)
check("route line shown under the vendor line",
      ev(ROUTE + ":IsShown()") and ev(ROUTE + ".__point[2] == AuctionatorCraftingInfoProfessionsFrame.VendorProfitLine"))
r = ev("VendorProfit.RouteLine.Calculate(VendorProfit.Calculate(ProfessionsFrame.CraftingPage.SchematicForm))")
check("without Mining saved, bronze bars are bought: same cost as Auctionator", r.cost == 1239)
check("vendor line unchanged by routes", ev(LINE + ":GetText()") == "Vendor Profit: |cffff2020-10s 92c|r")

# --- Mining opened: saved and used ------------------------------------------
run('__stub.OpenProfession(186, "Mining", %s)' % MINING)
check("Mining's learned recipes saved",
      ev('(function() local n = 0 for _ in pairs(VendorProfitCharDB.professions[186].recipes) do n = n + 1 end return n end)()') == 3)
check("unlearned recipes not saved", ev("VendorProfitCharDB.professions[186].recipes[9999]") is None)
check("both professions listed", list(ev("VendorProfit.Recipes.ProfessionNames()").values()) == ["Blacksmithing", "Mining"])

run('__stub.OpenProfession(164, "Blacksmithing", { %s })' % CUIRASS)
run('__stub.SetRecipe(%s)' % CUIRASS)
r = ev("VendorProfit.RouteLine.Calculate(VendorProfit.Calculate(ProfessionsFrame.CraftingPage.SchematicForm))")
check("route cost: 7 bronze bars at 62.5c = 438c", r.cost == 438)
check("vendor profit: 147 - 438 = -291", r.vendorProfit == -291)
check("line shows the route's vendor profit", ev(ROUTE + ":GetText()") == "Vendor Profit (route): |cffff2020-2s 91c|r")

bronze = r.route.children[1].node
check("bronze bars crafted", bronze.source == "craft" and bronze.itemID == BRONZE_BAR)
kids = {c.node.itemID: c.node for c in bronze.children.values()}
check("copper bars crafted (50c beats 70c)", kids[COPPER_BAR].source == "craft")
check("tin bars bought (75c beats 80c)", kids[TIN_BAR].source == "auction")
check("half a copper bar per bronze bar", abs(bronze.children[1].perUnit - 0.5) < 1e-9)

# --- Tooltip -----------------------------------------------------------------
tip = ev("__stub.HoverRoute()")
check("tooltip titled", tip.startswith("Cheapest Route"))
check("tooltip root: the crafted item and route cost", "Rough Bronze Cuirass x1 | |cffffffff4s 38c|r" in tip)
check("tooltip: bronze bars crafted in Mining, 2 per craft",
      "    |Ticon2841:0|t Bronze Bar x7 | |cff20ff20craft (Mining, makes 2)|r  |cffffffff4s 38c|r" in tip)
check("tooltip: copper bars nested under bronze bars",
      "        |Ticon2840:0|t Copper Bar x3.5 | |cff20ff20craft (Mining)|r  |cffffffff1s 75c|r" in tip)
check("tooltip: copper ore nested under copper bars",
      "            |Ticon2770:0|t Copper Ore x3.5 | buy (auction)  |cffffffff1s 75c|r" in tip)
check("tooltip: tin bars bought", "        |Ticon3576:0|t Tin Bar x3.5 | buy (auction)  |cffffffff2s 63c|r" in tip)
check("tooltip: crafting cost", "Crafting cost | |cffffffff4s 38c|r" in tip)
check("tooltip: Auctionator's cost and the saving",
      "Auctionator's To Craft | |cffffffff12s 39c|r" in tip and "Saves | |cffffffff8s 1c|r" in tip)
check("tooltip: vendor profit, no auction profit",
      "Vendor profit | |cffff2020-2s 91c|r" in tip and "Auction" not in tip.replace("Auctionator", ""))
check("tooltip: which professions it used", "Uses your recipes from: Blacksmithing, Mining." in tip)
run('AuctionatorCraftingInfoProfessionsFrame.VendorProfitRouteHover.__scripts.OnLeave()')
check("tooltip hides on leave", not ev("GameTooltip.shown"))

# --- Prices change: the route follows ---------------------------------------
run('__stub.auctionPrices[2840] = 40')  # Copper Bar now cheaper to buy than craft
run('AuctionatorCraftingInfoProfessionsFrame:UpdateTotal()')
r = ev("VendorProfit.RouteLine.Calculate(VendorProfit.Calculate(ProfessionsFrame.CraftingPage.SchematicForm))")
check("cheaper copper bars bought instead", r.route.children[1].node.children[1].node.source == "auction")
check("route cost: 7 x (40 + 75) / 2 = 402.5 -> 403", r.cost == 403)
run('__stub.auctionPrices[2840] = 70')

# --- Profit and items vendors won't buy ----------------------------------------
run('__stub.items["item:2866"].sellPrice = 500')
run('AuctionatorCraftingInfoProfessionsFrame:UpdateTotal()')
check("route profit in white: 500 - 438 = 62c", ev(ROUTE + ":GetText()") == "Vendor Profit (route): |cffffffff62c|r")
run('__stub.items["item:2866"].sellPrice = 0')
run('AuctionatorCraftingInfoProfessionsFrame:UpdateTotal()')
check("can't be vendored: says so", ev(ROUTE + ":GetText()") == "Vendor Profit (route): |cff808080can't be sold to vendors|r")
check("...and the route tooltip still works", "Crafting cost | |cffffffff4s 38c|r" in ev("__stub.HoverRoute()"))
run('__stub.items["item:2866"].sellPrice = 147')

# --- Missing prices ------------------------------------------------------------
run('__stub.auctionPrices[2771] = nil; __stub.auctionPrices[3576] = nil')  # no tin prices at all
run('AuctionatorCraftingInfoProfessionsFrame:UpdateTotal()')
r = ev("VendorProfit.RouteLine.Calculate(VendorProfit.Calculate(ProfessionsFrame.CraftingPage.SchematicForm))")
check("bronze bar has a price, so buying beats a route with a free reagent", r.route.children[1].node.source == "auction")
check("...and the route is complete", not r.route.missing)
run('__stub.auctionPrices[2841] = nil')  # and no bronze price either
run('AuctionatorCraftingInfoProfessionsFrame:UpdateTotal()')
check("only route left counts tin as free and warns", "(missing reagent prices)" in ev(ROUTE + ":GetText()"))
check("tooltip marks the item with no price", "no price" in ev("__stub.HoverRoute()"))
run('__stub.auctionPrices[2771] = 80; __stub.auctionPrices[3576] = 75; __stub.auctionPrices[2841] = 177')

# --- Item names load late ------------------------------------------------------
run('__stub.items["item:2770"].cached = false')
tip = ev("__stub.HoverRoute()")
check("unloaded name shown as a placeholder", "item 2770 x3.5" in tip)
run('__stub.LoadItem("item:2770")')
check("tooltip redrawn once the name loads", "Copper Ore x3.5" in ev("__stub.HoverRoute()"))

# --- Hidden with the vendor line ---------------------------------------------
run('__stub.SetRecipe({ recipeID = 4001, itemLink = nil, quantityMin = 1, reagents = { { itemID = 2835, quantity = 1 } } })')
check("no item made: route line and hover hidden",
      not ev(ROUTE + ":IsShown()") and not ev("AuctionatorCraftingInfoProfessionsFrame.VendorProfitRouteHover:IsShown()"))
check("no errors from routes", ev("#__stub.errors") == 0)

# --- Scanning rules ---------------------------------------------------------------
run('__stub.tradeSkill.linked = true')
run('__stub.OpenProfession(186, "Mining", {})')
check("someone else's linked profession isn't saved",
      ev("VendorProfitCharDB.professions[186].recipes[2659]") is not None)
run('__stub.tradeSkill.linked = false')

run('__stub.tradeSkill.ready = false')
run('__stub.OpenProfession(186, "Mining", {})')
check("not saved before the window is ready", ev("VendorProfitCharDB.professions[186].recipes[2659]") is not None)
run('__stub.tradeSkill.ready = true')

run('''
    local all = C_TradeSkillUI.GetAllRecipeIDs
    C_TradeSkillUI.GetAllRecipeIDs = nil
    __stub.filteredRecipeIDs = { 2657 }
    __stub.OpenProfession(186, "Mining", %s)
    C_TradeSkillUI.GetAllRecipeIDs = all
    __stub.filteredRecipeIDs = nil
''' % MINING)
check("a filtered list adds to what's saved instead of replacing it",
      ev("VendorProfitCharDB.professions[186].recipes[2659]") is not None
      and ev("VendorProfitCharDB.professions[186].recipes[2657]") is not None)

run('__stub.OpenProfession(186, "Mining", { (%s)[1] })' % MINING)
check("a full list replaces what's saved (dropped recipes go)",
      ev("VendorProfitCharDB.professions[186].recipes[2659]") is None)
check("index follows: bronze bars no longer craftable", len(list(ev("VendorProfit.Recipes.ForItem(2841)").values())) == 0)

# --- Saved across sessions ---------------------------------------------------
run('__stub.OpenProfession(186, "Mining", %s)' % MINING)
dump = run('''
    local function dump(v)
        if type(v) == "table" then
            local parts = {}
            for k, x in pairs(v) do
                local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
                parts[#parts + 1] = key .. "=" .. dump(x)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        elseif type(v) == "string" then
            return string.format("%q", v)
        end
        return tostring(v)
    end
    return dump(VendorProfitCharDB)
''')
check("saved data holds only plain recipe fields", "profession" not in dump.replace("professions", ""))
run3, ev3 = route_client("VendorProfitCharDB = " + dump)
check("saved recipes load in a new session", len(list(ev3("VendorProfit.Recipes.ForItem(2841)").values())) == 1)
run3('__stub.SetRecipe(%s)' % CUIRASS)
check("and the route uses them without opening Mining", "-2s 91c" in ev3(ROUTE + ":GetText()"))

# --- Loops ---------------------------------------------------------------------
# Lesser <-> Greater essence: 3 lesser make 1 greater, 1 greater makes 3 lesser.
run4, ev4 = route_client()
run4('''
    __stub.items["item:10998"] = { name = "Lesser Astral Essence", cached = true, sellPrice = 1 }
    __stub.items["item:11082"] = { name = "Greater Astral Essence", cached = true, sellPrice = 1 }
    __stub.items["item:7777"] = { name = "Thing", cached = true, sellPrice = 900 }
    __stub.auctionPrices[10998] = 100
    __stub.auctionPrices[11082] = 200   -- cheaper than 3 lesser (300)
    __stub.OpenProfession(333, "Enchanting", {
        { recipeID = 13361, itemLink = "item:11082", quantityMin = 1, reagents = { { itemID = 10998, quantity = 3 } } },
        { recipeID = 13362, itemLink = "item:10998", quantityMin = 3, reagents = { { itemID = 11082, quantity = 1 } } },
    })
''')
run4('__stub.SetRecipe({ recipeID = 5000, itemLink = "item:7777", quantityMin = 1, reagents = { { itemID = 10998, quantity = 3 } } })')
r = ev4("VendorProfit.RouteLine.Calculate(VendorProfit.Calculate(ProfessionsFrame.CraftingPage.SchematicForm))")
check("loop: lesser essence made from a greater (200 / 3 each)", abs(r.route.cost - 200) < 1e-9)
check("loop: the greater is bought, not made from lesser again",
      r.route.children[1].node.children[1].node.source == "auction")
check("loop: no errors", ev4("#__stub.errors") == 0)

# --- Reagent slots with several options --------------------------------------------
run('''__stub.SetRecipe({
    recipeID = 5001, itemLink = "item:2866", quantityMin = 1,
    reagents = { { itemID = 2840, quantity = 2, options = { 3576 } } },
})''')
r = ev("VendorProfit.RouteLine.Calculate(VendorProfit.Calculate(ProfessionsFrame.CraftingPage.SchematicForm))")
check("slot with options uses the cheapest option (copper bar crafted at 50c)",
      r.route.children[1].node.itemID == COPPER_BAR and r.cost == 100)
check("no errors in the route section", ev("#__stub.errors") == 0)


# =============================================================================
# Queue, plan and shopping
# =============================================================================
def shop_client(sell=600, before_load=""):
    run, ev = route_client(before_load)
    run('__stub.OpenProfession(186, "Mining", %s)' % MINING)
    run('__stub.OpenProfession(164, "Blacksmithing", { %s })' % CUIRASS)
    run('__stub.items["item:2866"].sellPrice = %d' % sell)
    # Have: 12 Bronze Bars in bags, 3 Copper Bars in bags and 2 in the bank.
    run('__stub.bags[2841] = 12; __stub.bags[2840] = 3; __stub.bank[2840] = 2')
    run('__stub.SetRecipe(%s)' % CUIRASS)
    return run, ev


def lines(ev):
    return list(ev("VendorProfit.Panel.Lines()").values())


def has_line(ev, *parts):
    return any(all(p in l for p in parts) for l in lines(ev))


def click(run, name):
    run("VendorProfit.Panel.Buttons().%s:Click()" % name)


QUEUE = "AuctionatorCraftingInfoProfessionsFrame.VendorProfitQueueButton"
run, ev = shop_client()

# --- Queue button --------------------------------------------------------------
check("queue button beside the route line", ev(QUEUE + ":IsShown()") and ev(QUEUE + ".__point[2] == " + ROUTE))
run('__stub.createCount = 10')
run(QUEUE + ':Click()')
check("queued 10 from the Create box", ev("VendorProfit.Order.Entries()[1].crafts") == 10)
check("panel opens", ev("VendorProfit.Panel.IsShown()"))
check("docked beside the professions window", ev("VendorProfitPanel.__point[2] == ProfessionsFrame"))

# --- The plan --------------------------------------------------------------------
plan = ev("VendorProfit.Shopper.Summary().plan")
buy = {l.itemID: l.quantity for l in plan.buyOrder.values()}
check("buys 24 copper ore and 29 tin bars", buy == {COPPER_ORE: 24, TIN_BAR: 29})
crafts = [(c.itemID, c.crafts) for c in plan.crafts.values()]
check("crafts deepest first: copper bars, bronze bars, cuirasses",
      crafts == [(COPPER_BAR, 24), (BRONZE_BAR, 29), (CUIRASS_ID, 10)])
check("uses the 12 bronze bars and 5 copper bars you have",
      plan.uses[BRONZE_BAR] == 12 and plan.uses[COPPER_BAR] == 5)
s_ = ev("VendorProfit.Shopper.Summary()")
check("estimate: 6000 - 1000 had - 3375 to buy = 1625", s_.revenue == 6000 and s_.ownedValue == 1000 and s_.remaining == 3375 and s_.profit == 1625)
check("panel lists what to buy", has_line(ev, "Copper Ore x24", "buy (auction)") and has_line(ev, "Tin Bar x29"))
check("panel lists what you have, with the bank", has_line(ev, "Copper Bar x5", "2 in bank") and has_line(ev, "Bronze Bar x12"))
check("panel lists the crafts", has_line(ev, "Copper Bar x24", "Mining, 24 crafts")
      and has_line(ev, "Bronze Bar x58", "Mining, 29 crafts") and has_line(ev, "Rough Bronze Cuirass x10", "Blacksmithing, 10 crafts"))
check("panel says prices are Auctionator's until the AH opens", has_line(ev, "Auctionator's last scan"))
check("buy button waits for the auction house",
      ev("VendorProfit.Panel.Buttons().buy.__text") == "Open the auction house to buy" and not ev("VendorProfit.Panel.Buttons().buy:IsEnabled()"))

run(QUEUE + ':Click()')
check("queuing again adds to the same entry", ev("#VendorProfit.Order.Entries()") == 1 and ev("VendorProfit.Order.Entries()[1].crafts") == 20)
run('VendorProfit.Order.Entries()[1].crafts = 10; VendorProfit.Order.Changed()')

# --- At the auction house --------------------------------------------------------
run('''
    __stub.ah.listings[2770] = { { unitPrice = 50, quantity = 10 }, { unitPrice = 55, quantity = 20 }, { unitPrice = 80, quantity = 100 } }
    __stub.ah.listings[3576] = { { unitPrice = 75, quantity = 10 }, { unitPrice = 78, quantity = 30 } }
''')
run('__stub.OpenAH()')
check("panel docks beside the auction house", ev("VendorProfitPanel.__point[2] == AuctionHouseFrame"))
check("scan first", ev("VendorProfit.Shopper.Status()") == "idle" and ev("VendorProfit.Panel.Buttons().buy.__text") == "Scan first")
click(run, "scan")
check("scanning", ev("VendorProfit.Shopper.Status()") == "scanning")
run('__stub.Advance(2)')
check("scan done", ev("VendorProfit.Shopper.Status()") == "ready")
check("scanned the two auction items", list(ev("__stub.ah.searches").values()) == [COPPER_ORE, TIN_BAR])
s_ = ev("VendorProfit.Shopper.Summary()")
check("live cost walks the listings: 1270 + 2232", s_.remaining == 1270 + 2232)
check("live profit", abs(s_.profit - (6000 - (12 * (1270 / 24 + 2232 / 29) / 2 + 5 * 1270 / 24) - 3502)) < 1e-6)
check("buy button offers the first purchase",
      ev("VendorProfit.Panel.Buttons().buy.__text") == "Buy 24 Copper Ore (|cffffffff12s 70c|r)" and ev("VendorProfit.Panel.Buttons().buy:IsEnabled()"))

# Buy: quote, then confirm.
click(run, "buy")
check("buy asks for a quote", list(ev("__stub.ah.starts[1]").values()) == [COPPER_ORE, 24] and ev("VendorProfit.Shopper.Status()") == "quoting")
check("no purchase without confirming", ev("#__stub.ah.confirms") == 0)
run('__stub.Advance(0.5)')
check("quote within budget: confirm offered",
      ev("VendorProfit.Shopper.Status()") == "confirm" and ev("VendorProfit.Panel.Buttons().buy.__text") == "Confirm: 24 Copper Ore for |cffffffff12s 70c|r")
check("cancel offered while confirming", ev("VendorProfit.Panel.Buttons().cancel:IsShown()"))
click(run, "buy")
run('__stub.Advance(0.5)')
check("bought: recorded with what it cost", ev("VendorProfitCharDB.order.bought[2770]") == 24 and ev("VendorProfitCharDB.order.spent") == 1270)
check("ore in bags", ev("__stub.bags[2770]") == 24)
check("message says what was bought", has_line(ev, "Bought 24 Copper Ore for"))
check("copper ore off the list", ev("VendorProfit.Shopper.Summary().plan.buy[2770]") is None)
check("next purchase offered", ev("VendorProfit.Panel.Buttons().buy.__text") == "Buy 29 Tin Bar (|cffffffff22s 32c|r)")

# Price went up between scan and buy: the cheap tin bars sold.
run('__stub.ah.listings[3576][1].quantity = 0')
click(run, "buy")
run('__stub.Advance(0.5)')
check("quote above the scan: cancelled, nothing bought", ev("__stub.ah.cancels") == 1 and ev("#__stub.ah.confirms") == 1)
check("says the price went up", any("costs more than scanned" in l for l in lines(ev)))
run('__stub.Advance(2)')
check("rescanned at the new price", ev("VendorProfit.Shopper.Status()") == "ready"
      and ev("VendorProfit.Panel.Buttons().buy.__text") == "Buy 29 Tin Bar (|cffffffff22s 62c|r)")
click(run, "buy"); run('__stub.Advance(0.5)'); click(run, "buy"); run('__stub.Advance(0.5)')
check("tin bars bought", ev("VendorProfitCharDB.order.bought[3576]") == 29 and ev("VendorProfitCharDB.order.spent") == 1270 + 2262)
check("nothing left to buy", ev("VendorProfit.Panel.Buttons().buy.__text") == "Nothing to buy here"
      and has_line(ev, "Nothing to buy: you have everything."))
check("crafts still listed", has_line(ev, "Bronze Bar x58", "29 crafts"))
check("no errors while shopping", ev("#__stub.errors") == 0)

# Crafting the copper bars changes the bags; the plan follows.
run('__stub.bags[2770] = 0; __stub.bags[2840] = 27; __stub.Fire("BAG_UPDATE_DELAYED")')
check("crafted copper bars: their step goes, nothing to buy",
      not has_line(ev, "Copper Bar x24") and ev("#VendorProfit.Shopper.Summary().plan.buyOrder") == 0)

# Closing the auction house.
run('__stub.CloseAH()')
check("panel closes with the auction house", not ev("VendorProfit.Panel.IsShown()"))
run('VendorProfit.Panel.Show()')
check("reopened away from the AH: docked to the professions window", ev("VendorProfitPanel.__point[2] == ProfessionsFrame"))
click(run, "clear")
check("clear empties the order and its record", ev("VendorProfit.Order.IsEmpty()") and ev("VendorProfitCharDB.order.spent") == 0)

# --- Not profitable at live prices --------------------------------------------
run, ev = shop_client(sell=450)
run('__stub.createCount = 10'); run(QUEUE + ':Click()')
check("profitable on Auctionator's prices", ev("VendorProfit.Shopper.Summary().profit") > 0)
run('''
    __stub.ah.listings[2770] = { { unitPrice = 90, quantity = 100 } }
    __stub.ah.listings[3576] = { { unitPrice = 100, quantity = 100 } }
    __stub.ah.listings[2771] = { { unitPrice = 95, quantity = 100 } }
''')
run('__stub.OpenAH()'); click(run, "scan"); run('__stub.Advance(3)')
check("live prices: loses money", ev("VendorProfit.Shopper.Summary().profit") < 0)
check("buy refused", ev("VendorProfit.Panel.Buttons().buy.__text") == "Not profitable" and not ev("VendorProfit.Panel.Buttons().buy:IsEnabled()"))
check("panel warns", has_line(ev, "loses money"))
run('VendorProfit.Shopper.Buy()')
check("even called directly, nothing is bought", ev("#__stub.ah.starts") == 0)
check("buy anyway offered", ev("VendorProfit.Panel.Buttons().anyway:IsShown()"))
click(run, "anyway")
check("buy anyway allows buying", ev("VendorProfit.Panel.Buttons().buy:IsEnabled()") and ev("VendorProfit.Panel.Buttons().buy.__text").startswith("Buy "))
click(run, "scan"); run('__stub.Advance(3)')
check("a new scan asks again", not ev("VendorProfit.Panel.Buttons().buy:IsEnabled()"))

# --- Live prices change the route ------------------------------------------------
run, ev = shop_client()
run('__stub.createCount = 10'); run(QUEUE + ':Click()')
run('''
    __stub.ah.listings[2770] = { { unitPrice = 50, quantity = 100 } }
    __stub.ah.listings[3576] = { { unitPrice = 200, quantity = 100 } }  -- tin bars now dear
    __stub.ah.listings[2771] = { { unitPrice = 60, quantity = 100 } }   -- tin ore cheap
''')
run('__stub.OpenAH()'); click(run, "scan"); run('__stub.Advance(3)')
buy = {l.itemID: l.quantity for l in ev("VendorProfit.Shopper.Summary().plan.buyOrder").values()}
check("tin bars now smelted from tin ore", buy == {COPPER_ORE: 24, TIN_ORE: 29})
check("tin ore scanned too", TIN_ORE in list(ev("__stub.ah.searches").values()))
check("tin bar step added", has_line(ev, "Tin Bar x29", "Mining, 29 crafts"))

# --- Purchases that go to the mailbox -------------------------------------------
run, ev = shop_client()
run('__stub.createCount = 10'); run(QUEUE + ':Click()')
run('''
    __stub.ah.toMail = true
    __stub.ah.listings[2770] = { { unitPrice = 50, quantity = 100 } }
    __stub.ah.listings[3576] = { { unitPrice = 75, quantity = 100 } }
''')
run('__stub.OpenAH()'); click(run, "scan"); run('__stub.Advance(2)')
click(run, "buy"); run('__stub.Advance(0.5)'); click(run, "buy"); run('__stub.Advance(0.5)')
check("ore in the mail, not the bags", ev("__stub.bags[2770]") is None and ev("__stub.mail[2770]") == 24)
check("still counted: not bought twice", ev("VendorProfit.Shopper.Summary().plan.buy[2770]") is None
      and ev("VendorProfit.Panel.Buttons().buy.__text").startswith("Buy 29 Tin Bar"))
run('__stub.bags[2770] = 24; __stub.mail[2770] = 0; __stub.Fire("BAG_UPDATE_DELAYED")')
check("collected from the mail: still counted once", ev("VendorProfit.Shopper.Summary().plan.buy[2770]") is None)
click(run, "recount")
check("recount after collecting: record cleared, bags counted",
      ev("VendorProfitCharDB.order.bought[2770]") is None and ev("VendorProfit.Shopper.Summary().plan.buy[2770]") is None)
check("recount keeps what was spent", ev("VendorProfitCharDB.order.spent") == 1200)

# --- Things going wrong -----------------------------------------------------------
run, ev = shop_client()
run('__stub.createCount = 10'); run(QUEUE + ':Click()')
run('''
    __stub.ah.listings[2770] = { { unitPrice = 50, quantity = 3, own = 3 }, { unitPrice = 52, quantity = 10, own = 2 }, { unitPrice = 60, quantity = 100 } }
    __stub.ah.listings[3576] = { { unitPrice = 75, quantity = 100 } }
''')
run('__stub.OpenAH()')
run('__stub.ah.ready = false')
click(run, "scan"); run('__stub.Advance(2)')
check("waits for the auction house's throttle", ev("#__stub.ah.searches") == 0 and ev("VendorProfit.Shopper.Status()") == "scanning")
run('__stub.ah.ready = true; __stub.ah.dropSearches = 1'); run('__stub.Advance(2)')
check("a search with no reply...", ev("#__stub.ah.searches") == 1 and ev("VendorProfit.Shopper.Status()") == "scanning")
run('__stub.Advance(10)')
check("...is sent again after the timeout", ev("#__stub.ah.searches") >= 3 and ev("VendorProfit.Shopper.Status()") == "ready")
r = ev("VendorProfit.Shopper.Listing(2770)")
check("your own listings left out", r.rows[1].unitPrice == 52 and r.rows[1].quantity == 8)
check("priced without them: 8 x 52 + 16 x 60", ev("VendorProfit.Shopper.Summary().plan.buy[2770].total") == 8 * 52 + 16 * 60)

run('__stub.ah.failNext = true')
searches = ev("#__stub.ah.searches")
click(run, "buy"); run('__stub.Advance(0.5)'); click(run, "buy"); run('__stub.Advance(0.15)')
check("failed purchase: nothing recorded", ev("VendorProfitCharDB.order.bought[2770]") is None and ev("VendorProfitCharDB.order.spent") == 0)
check("failed purchase: says so and rescans", any("failed" in l for l in lines(ev)) and ev("VendorProfit.Shopper.Status()") == "scanning")
run('__stub.Advance(2)')
check("...then ready again", ev("VendorProfit.Shopper.Status()") == "ready" and ev("#__stub.ah.searches") == searches + 1)

run('__stub.ah.noPurchaseReply = true')
click(run, "buy"); run('__stub.Advance(0.5)'); click(run, "buy"); run('__stub.Advance(16)')
check("no reply to a purchase: not recorded, rescanned",
      ev("VendorProfitCharDB.order.spent") == 0 and any("No reply buying" in l for l in lines(ev)))
run('__stub.ah.noPurchaseReply = false; __stub.Advance(3)')
run('__stub.Fire("COMMODITY_PURCHASE_SUCCEEDED")')  # the timed-out purchase went through after all
check("a late success is still recorded", ev("VendorProfitCharDB.order.bought[2770]") == 24)
run('VendorProfitCharDB.order.bought = {}; VendorProfitCharDB.order.spent = 0; VendorProfit.Order.Changed()')

run('__stub.money = 10')
click(run, "buy")
check("not enough gold: no quote asked", any("Not enough gold" in l for l in lines(ev)) and ev("VendorProfit.Shopper.Status()") == "ready")
run('__stub.money = 1000000')

starts = ev("#__stub.ah.starts")
click(run, "buy"); run('__stub.Advance(0.5)')
click(run, "cancel")
check("cancel drops the quote", ev("VendorProfit.Shopper.Status()") == "ready" and ev("__stub.ah.cancels") >= 1)

cancels = ev("__stub.ah.cancels")
click(run, "buy"); run('__stub.Advance(0.5)')
run('__stub.CloseAH()')
check("closing the AH mid-purchase cancels it", ev("__stub.ah.cancels") == cancels + 1 and ev("VendorProfit.Shopper.Status()") == "closed")
check("no errors when things go wrong", ev("#__stub.errors") == 0)

# Not enough listed; more results; things that don't stack.
run, ev = shop_client()
run('__stub.createCount = 10'); run(QUEUE + ':Click()')
run('''
    __stub.ah.pageSize = 1
    __stub.ah.listings[2770] = { { unitPrice = 50, quantity = 5 }, { unitPrice = 51, quantity = 5 } }
    __stub.ah.nonCommodity[3576] = true
''')
run('__stub.OpenAH()'); click(run, "scan"); run('__stub.Advance(3)')
check("asks for more listings when the first page isn't enough", ev("__stub.ah.moreRequests") >= 1
      and ev("VendorProfit.Shopper.Summary().plan.buy[2770].listed") == 10)
check("only 10 listed: says so", has_line(ev, "Copper Ore x24", "only 10 listed") and has_line(ev, "Not enough listed"))
check("buys what's there", ev("VendorProfit.Panel.Buttons().buy.__text").startswith("Buy 10 Copper Ore"))
check("item that doesn't stack: buy it yourself", has_line(ev, "Tin Bar x29", "buy yourself"))

# --- Queue rules and saving -------------------------------------------------------
run, ev = shop_client()
run('__stub.items["item:2866"].sellPrice = 0; AuctionatorCraftingInfoProfessionsFrame:UpdateTotal()')
check("no queue button for items vendors won't buy", not ev(QUEUE + ":IsShown()"))
run('__stub.items["item:2866"].sellPrice = 600; AuctionatorCraftingInfoProfessionsFrame:UpdateTotal()')
run('__stub.createCount = 3'); run(QUEUE + ':Click()')
dump = run('''
    local function dump(v)
        if type(v) == "table" then
            local parts = {}
            for k, x in pairs(v) do
                local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
                parts[#parts + 1] = key .. "=" .. dump(x)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        elseif type(v) == "string" then
            return string.format("%q", v)
        end
        return tostring(v)
    end
    return dump(VendorProfitCharDB)
''')
run5, ev5 = route_client("VendorProfitCharDB = " + dump)
check("order saved across sessions", ev5("VendorProfit.Order.Entries()[1].crafts") == 3)
run5('__stub.OpenAH()')
check("panel opens with the AH when something is queued", ev5("VendorProfit.Panel.IsShown()"))
run5('SlashCmdList.VENDORPROFIT("")')
check("/vprofit toggles the panel", not ev5("VendorProfit.Panel.IsShown()"))
run5('VendorProfit.Order.Remove(1)')
check("removing the last entry clears the order", ev5("VendorProfit.Order.IsEmpty()"))

print()
failed = [label for label, ok in results if not ok]
print("%d passed, %d failed" % (len(results) - len(failed), len(failed)))
sys.exit(1 if failed else 0)
