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
    # Coins as letters, so money reads "5s 07c" in the checks.
    lua.execute('VendorProfit.COINS = { gold = "g", silver = "s", copper = "c" }')
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
check("files loaded in toc order", FILES == ["Core.lua", "VendorPrices.lua", "VendorLine.lua", "Recipes.lua", "Route.lua", "RouteSection.lua", "Inventory.lua", "Plan.lua", "Order.lua", "QueueButton.lua", "SearchButton.lua", "Shopper.lua", "Crafter.lua", "OpenButton.lua", "Banker.lua", "Merchant.lua", "History.lua", "Panel.lua", "BestCrafts.lua", "BestPanel.lua", "HistoryPanel.lua", "PurchasePanel.lua"])
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
SECTION = "AuctionatorCraftingInfoProfessionsFrame.VendorProfitRoute"
ROUTE = SECTION + ".vendor"


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
      ev(ROUTE + ":IsShown()") and ev(SECTION + ".separator.__point[2] == AuctionatorCraftingInfoProfessionsFrame.VendorProfitLine"))
check("separator titled Cheapest Route, with a gap above",
      ev(SECTION + ".separator.Label:GetText()") == "Cheapest Route" and ev(SECTION + ".separator.__point[5]") < -2
      and ev(SECTION + ".separator:IsShown()"))
check("section lines in order: To Craft, Profit, Vendor Profit",
      ev(SECTION + ".toCraft.__point[2] == " + SECTION + ".separator")
      and ev(SECTION + ".profit.__point[2] == " + SECTION + ".toCraft")
      and ev(SECTION + ".vendor.__point[2] == " + SECTION + ".profit"))
r = ev("VendorProfit.RouteSection.Calculate(VendorProfit.Calculate(ProfessionsFrame.CraftingPage.SchematicForm))")
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
r = ev("VendorProfit.RouteSection.Calculate(VendorProfit.Calculate(ProfessionsFrame.CraftingPage.SchematicForm))")
check("route cost: 7 bronze bars at 62.5c = 438c", r.cost == 438)
check("vendor profit: 147 - 438 = -291", r.vendorProfit == -291)
check("route To Craft: 438", ev(SECTION + ".toCraft:GetText()") == "To Craft: |cffffffff4s 38c|r")
check("route Profit: 1300 x 0.95 - 438 = 797", ev(SECTION + ".profit:GetText()") == "Profit: |cffffffff7s 97c|r")
check("route Vendor Profit: 147 - 438", ev(ROUTE + ":GetText()") == "Vendor Profit: |cffff2020-2s 91c|r")

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
      "    |Ticon2841:0|t Bronze Bar x7 | |cff20ff20craft (Mining, makes 2)|r  |cffffffff4s 38c|r  |cff20ff20saves 8s 01c|r" in tip)
check("tooltip: copper bars nested under bronze bars",
      "        |Ticon2840:0|t Copper Bar x3.5 | |cff20ff20craft (Mining)|r  |cffffffff1s 75c|r  |cff20ff20saves 70c|r" in tip)
check("tooltip: copper ore nested under copper bars",
      "            |Ticon2770:0|t Copper Ore x3.5 | buy (auction)  |cffffffff1s 75c|r" in tip)
check("tooltip: tin bars bought, no saving shown", "        |Ticon3576:0|t Tin Bar x3.5 | buy (auction)  |cffffffff2s 63c|r\n" in tip)
r_ = ev("VendorProfit.RouteSection.Calculate(VendorProfit.Calculate(ProfessionsFrame.CraftingPage.SchematicForm))")
check("crafted steps know their buy price", r_.route.children[1].node.buyCost == 177)
check("tooltip doesn't repeat the section's numbers", "Crafting cost" not in tip and "Vendor profit" not in tip)
check("tooltip: Auctionator's cost and the saving",
      "Auctionator's To Craft | |cffffffff12s 39c|r" in tip and "Saves | |cffffffff8s 01c|r" in tip)
check("tooltip: which professions it used", "Uses your recipes from: Blacksmithing, Mining." in tip)
run('__stub.auctionPrices[2840] = nil; AuctionatorCraftingInfoProfessionsFrame:UpdateTotal()')
check("crafted item with no buy price: no saving shown",
      "        |Ticon2840:0|t Copper Bar x3.5 | |cff20ff20craft (Mining)|r  |cffffffff1s 75c|r\n" in ev("__stub.HoverRoute()"))
run('__stub.auctionPrices[2840] = 70; AuctionatorCraftingInfoProfessionsFrame:UpdateTotal()')
run(SECTION + '.hover.__scripts.OnLeave()')
check("tooltip hides on leave", not ev("GameTooltip.shown"))

# --- Prices change: the route follows ---------------------------------------
run('__stub.auctionPrices[2840] = 40')  # Copper Bar now cheaper to buy than craft
run('AuctionatorCraftingInfoProfessionsFrame:UpdateTotal()')
r = ev("VendorProfit.RouteSection.Calculate(VendorProfit.Calculate(ProfessionsFrame.CraftingPage.SchematicForm))")
check("cheaper copper bars bought instead", r.route.children[1].node.children[1].node.source == "auction")
check("route cost: 7 x (40 + 75) / 2 = 402.5 -> 403", r.cost == 403)
run('__stub.auctionPrices[2840] = 70')

# --- Profit and items vendors won't buy ----------------------------------------
run('__stub.items["item:2866"].sellPrice = 500')
run('AuctionatorCraftingInfoProfessionsFrame:UpdateTotal()')
check("route profit in white: 500 - 438 = 62c", ev(ROUTE + ":GetText()") == "Vendor Profit: |cffffffff62c|r")
run('__stub.items["item:2866"].sellPrice = 0')
run('AuctionatorCraftingInfoProfessionsFrame:UpdateTotal()')
check("can't be vendored: says so", ev(ROUTE + ":GetText()") == "Vendor Profit: |cff808080can't be sold to vendors|r")
check("...and the route tooltip still works", "Rough Bronze Cuirass x1 | |cffffffff4s 38c|r" in ev("__stub.HoverRoute()"))
run('__stub.auctionPrices[2866] = nil; AuctionatorCraftingInfoProfessionsFrame:UpdateTotal()')
check("no auction price: route Profit says so", ev(SECTION + ".profit:GetText()") == "Profit: |cff808080no auction price|r")
run('__stub.auctionPrices[2866] = 1300')
run('__stub.items["item:2866"].sellPrice = 147')

# --- Missing prices ------------------------------------------------------------
run('__stub.auctionPrices[2771] = nil; __stub.auctionPrices[3576] = nil')  # no tin prices at all
run('AuctionatorCraftingInfoProfessionsFrame:UpdateTotal()')
r = ev("VendorProfit.RouteSection.Calculate(VendorProfit.Calculate(ProfessionsFrame.CraftingPage.SchematicForm))")
check("bronze bar has a price, so buying beats a route with a free reagent", r.route.children[1].node.source == "auction")
check("...and the route is complete", not r.route.missing)
run('__stub.auctionPrices[2841] = nil')  # and no bronze price either
run('AuctionatorCraftingInfoProfessionsFrame:UpdateTotal()')
check("only route left counts tin as free and warns on To Craft", "(missing reagent prices)" in ev(SECTION + ".toCraft:GetText()"))
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
      not ev(ROUTE + ":IsShown()") and not ev(SECTION + ".hover:IsShown()") and not ev(SECTION + ".separator:IsShown()"))
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
r = ev4("VendorProfit.RouteSection.Calculate(VendorProfit.Calculate(ProfessionsFrame.CraftingPage.SchematicForm))")
check("loop: lesser essence made from a greater (200 / 3 each)", abs(r.route.cost - 200) < 1e-9)
check("loop: the greater is bought, not made from lesser again",
      r.route.children[1].node.children[1].node.source == "auction")
check("loop: no errors", ev4("#__stub.errors") == 0)

# --- Reagent slots with several options --------------------------------------------
run('''__stub.SetRecipe({
    recipeID = 5001, itemLink = "item:2866", quantityMin = 1,
    reagents = { { itemID = 2840, quantity = 2, options = { 3576 } } },
})''')
r = ev("VendorProfit.RouteSection.Calculate(VendorProfit.Calculate(ProfessionsFrame.CraftingPage.SchematicForm))")
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


DIVIDERS = {"To do", "Already in your bags"}
HEADINGS = {"Queued", "Profit"} | DIVIDERS
STEP = re.compile(r"^\d+\. (.*)$")


def is_heading(line):
    return line in HEADINGS or STEP.match(line) is not None


def section(ev, heading):
    """The panel rows under a heading (or numbered step), up to the next one."""
    ls = lines(ev)
    for i, l in enumerate(ls):
        m = STEP.match(l)
        if l == heading or (m and m.group(1) == heading):
            out = []
            for row in ls[i + 1:]:
                if is_heading(row):
                    break
                out.append(row)
            return out
    return None


def headings(ev):
    return [l for l in lines(ev) if is_heading(l)]


def has_line(ev, *parts):
    return any(all(p in l for p in parts) for l in lines(ev))


BUY = 'VendorProfit.Panel.RowButton("Buy")'
SCAN = 'VendorProfit.Panel.RowButton("Profit")'
CRAFT = 'VendorProfit.Panel.RowButton("Craft")'


def click(run, name):
    """Clicks a panel button: Buy, Scan (on Profit), Clear (on Queued), Cancel (by the price to confirm)."""
    if name == "buy":
        run(BUY + ":Click()")
    elif name == "scan":
        run(SCAN + ":Click()")
    elif name == "cancel":
        run('VendorProfit.Panel.FindButton("Cancel"):Click()')
    else:
        raise ValueError(name)


QUEUE = "AuctionatorCraftingInfoProfessionsFrame.VendorProfitQueueButton"
run, ev = shop_client()

# --- Queue button --------------------------------------------------------------
check("queue a little below the Vendor Profit line", ev(QUEUE + ".__point[5]") == -10)
check("queue button below the route's Vendor Profit line", ev(QUEUE + ":IsShown()") and ev(QUEUE + ".__point[2] == " + ROUTE)
      and ev(QUEUE + ".__point[1]") == "TOPLEFT" and ev(QUEUE + ".__point[3]") == "BOTTOMLEFT")
check("queue button above the tooltip area so it can be clicked",
      ev(QUEUE + ":GetFrameLevel()") > ev(SECTION + ".hover:GetFrameLevel()"))
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
check("panel lists what to buy", has_line(ev, "Copper Ore x24", "| auction  ") and has_line(ev, "Tin Bar x29"))
check("from your bags: 12 bronze bars, 3 copper bars",
      section(ev, "Already in your bags") == ["|Ticon2840:0|t Copper Bar x3", "|Ticon2841:0|t Bronze Bar x12"])
check("from your bank: the other 2 copper bars, to fetch", section(ev, "Take from bank") == ["|Ticon2840:0|t Copper Bar x2"])
check("no mailbox step with nothing in the mail", section(ev, "Collect from mailbox") is None)
check("layout: queued, profit, then the To do steps in order, then what's in your bags",
      headings(ev) == ["Queued", "Profit", "To do", "1. Buy", "2. Take from bank", "3. Craft", "Already in your bags"])
check("profit rows: sell prices (auction after the AH cut), expenses, profits", section(ev, "Profit")[:6] == [
    "Vendor price | |cffffffff60s|r", "Auction price | |cffffffff1g 23s 50c|r",
    "Items you have | |cffff2020-10s|r", "Items to buy | |cffff2020-33s 75c|r",
    "Vendor profit | |cffffffff16s 25c|r", "Auction profit | |cffffffff79s 75c|r"])
check("panel lists the crafts", has_line(ev, "Copper Bar x24", "Mining, 24 crafts")
      and has_line(ev, "Bronze Bar x58", "Mining, 29 crafts") and has_line(ev, "Rough Bronze Cuirass x10", "Blacksmithing, 10 crafts"))
check("no notes cluttering the panel", not has_line(ev, "Auctionator's last scan") and not has_line(ev, "loses money"))
check("Open AH says prices are Auctionator's until you scan", "Auctionator's last scan" in ev(BUY + ".tooltip"))
check("buy button waits for the auction house",
      ev(BUY + ".__text") == "Open AH" and not ev(BUY + ":IsEnabled()") and ev(BUY + ".tooltip").startswith("Talk to an auctioneer to buy."))

run('VendorProfit.Panel.Show("best")')
run(QUEUE + ':Click()')
check("queuing from the crafting screen switches the window to the Shopping List", ev("VendorProfit.Panel.ActiveTab()") == "shopping")
check("queuing again adds to the same entry", ev("#VendorProfit.Order.Entries()") == 1 and ev("VendorProfit.Order.Entries()[1].crafts") == 20)
run('VendorProfit.Order.Entries()[1].crafts = 10; VendorProfit.Order.Changed()')

# --- At the auction house --------------------------------------------------------
run('''
    __stub.ah.listings[2770] = { { unitPrice = 50, quantity = 10 }, { unitPrice = 55, quantity = 20 }, { unitPrice = 80, quantity = 100 } }
    __stub.ah.listings[3576] = { { unitPrice = 75, quantity = 10 }, { unitPrice = 78, quantity = 30 } }
''')
run('__stub.OpenAH()')
check("panel docks beside the auction house", ev("VendorProfitPanel.__point[2] == AuctionHouseFrame"))
check("Buy on before a scan: it scans first", ev("VendorProfit.Shopper.Status()") == "idle" and ev(BUY + ".__text") == "Buy"
      and ev(BUY + ":IsEnabled()") and ev(BUY + ".tooltip") == "Scans prices, then starts buying. You confirm each purchase.")
check("Scan is on the Profit heading", ev(SCAN + ".__text") == "Scan" and ev(SCAN + ":IsEnabled()"))
click(run, "scan")
check("scanning", ev("VendorProfit.Shopper.Status()") == "scanning")
run('__stub.Advance(2)')
check("scan done", ev("VendorProfit.Shopper.Status()") == "ready")
check("scanned the two auction items", list(ev("__stub.ah.searches").values()) == [COPPER_ORE, TIN_BAR])
s_ = ev("VendorProfit.Shopper.Summary()")
check("live cost walks the listings: 1270 + 2232", s_.remaining == 1270 + 2232)
check("live profit", abs(s_.profit - (6000 - (12 * (1270 / 24 + 2232 / 29) / 2 + 5 * 1270 / 24) - 3502)) < 1e-6)
check("buy button offers the first purchase",
      ev(BUY + ".__text") == "Buy" and ev(BUY + ":IsEnabled()") and ev(BUY + ".tooltip") == "Buy 24 Copper Ore for |cffffffff12s 70c|r")

# Buy: quote, then confirm.
click(run, "buy")
check("buy asks for a quote", list(ev("__stub.ah.starts[1]").values()) == [COPPER_ORE, 24] and ev("VendorProfit.Shopper.Status()") == "quoting")
check("no purchase without confirming", ev("#__stub.ah.confirms") == 0)
run('__stub.Advance(0.5)')
check("quote within budget: confirm offered",
      ev("VendorProfit.Shopper.Status()") == "confirm" and ev(BUY + ".__text") == "Confirm" and ev(BUY + ":IsEnabled()"))
check("the price to confirm shows under the heading", section(ev, "Buy")[0] == "|cffffd100Confirm: 24 Copper Ore for |cffffffff12s 70c|r|r")
check("cancel beside the price to confirm", ev('VendorProfit.Panel.FindButton("Cancel")') is not None)
click(run, "buy")
run('__stub.Advance(0.5)')
check("bought: what it cost is recorded", ev("VendorProfitCharDB.order.spent") == 1270)
check("went straight to the bags, so nothing counted as in the mail", ev("VendorProfit.Order.InMail(2770)") == 0)
check("ore in bags", ev("__stub.bags[2770]") == 24)
check("message says what was bought", has_line(ev, "Bought 24 Copper Ore for"))
check("copper ore off the list", ev("VendorProfit.Shopper.Summary().plan.buy[2770]") is None)
check("next purchase offered", ev(BUY + ".tooltip") == "Buy 29 Tin Bar for |cffffffff22s 32c|r")

# Price went up between scan and buy: the cheap tin bars sold.
run('__stub.ah.listings[3576][1].quantity = 0')
click(run, "buy")
run('__stub.Advance(0.5)')
check("quote above the scan: cancelled, nothing bought", ev("__stub.ah.cancels") == 1 and ev("#__stub.ah.confirms") == 1)
check("says the price went up", any("costs more than scanned" in l for l in lines(ev)))
run('__stub.Advance(2)')
check("rescanned at the new price", ev("VendorProfit.Shopper.Status()") == "ready"
      and ev(BUY + ".tooltip") == "Buy 29 Tin Bar for |cffffffff22s 62c|r")
click(run, "buy"); run('__stub.Advance(0.5)'); click(run, "buy"); run('__stub.Advance(0.5)')
check("tin bars bought", ev("__stub.bags[3576]") == 29 and ev("VendorProfitCharDB.order.spent") == 1270 + 2262)
check("spent is shown but not taken off the profit", has_line(ev, "Spent on this order so far")
      and ev("VendorProfit.Shopper.Summary().profit") == ev("VendorProfit.Shopper.Summary().revenue") - ev("VendorProfit.Shopper.Summary().ownedValue"))
check("nothing left to buy: the Buy step is gone", ev(BUY) is None and section(ev, "Buy") is None
      and headings(ev)[2:4] == ["To do", "1. Take from bank"])
check("crafts still listed", has_line(ev, "Bronze Bar x58", "29 crafts"))
check("no errors while shopping", ev("#__stub.errors") == 0)

# Crafting the copper bars changes the bags; the plan follows.
run('__stub.bags[2770] = 0; __stub.bags[2840] = 27; __stub.Fire("BAG_UPDATE_DELAYED")')
check("crafted copper bars: their step goes, nothing to buy",
      not has_line(ev, "Copper Bar x24") and ev("#VendorProfit.Shopper.Summary().plan.buyOrder") == 0)

# Moving the panel.
check("panel can be dragged", ev("VendorProfitPanel.__movable") and ev("VendorProfitPanel.__drag[1]") == "LeftButton")
run('__stub.Drag(VendorProfitPanel, 300, 700)')
check("moved position saved", ev("VendorProfitCharDB.panel.left") == 300 and ev("VendorProfitCharDB.panel.top") == 700)
check("not left in the game's layout cache", ev("VendorProfitPanel.__userPlaced") is False)
run('VendorProfit.Panel.Hide(); VendorProfit.Panel.Show()')
check("reopens where it was moved, not docked",
      ev("VendorProfitPanel.__point[1]") == "TOPLEFT" and ev("VendorProfitPanel.__point[2] == UIParent")
      and ev("VendorProfitPanel.__point[4]") == 300 and ev("VendorProfitPanel.__point[5]") == 700)

# Closing the auction house.
run('__stub.CloseAH()')
check("panel stays open when the auction house closes", ev("VendorProfit.Panel.IsShown()"))
run('VendorProfit.Panel.Hide(); __stub.OpenAH()')
check("moved panel opens with the AH where it was left", ev("VendorProfit.Panel.IsShown()") and ev("VendorProfitPanel.__point[2] == UIParent"))
run('SlashCmdList.VENDORPROFIT("reset")')
check("/vprofit reset docks it again", ev("VendorProfitCharDB.panel") is None and ev("VendorProfitPanel.__point[2] == AuctionHouseFrame"))
run('__stub.CloseAH()')
check("...and it still stays open when the auction house closes", ev("VendorProfit.Panel.IsShown()"))
run('VendorProfit.Panel.Hide(); VendorProfit.Panel.Show()')
check("reopened away from the AH: docked to the professions window", ev("VendorProfitPanel.__point[2] == ProfessionsFrame"))
run("VendorProfit.Order.Clear()")
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
check("buy turns into Buy anyway", ev(BUY + ".__text") == "Buy anyway" and ev(BUY + ":IsEnabled()") and ev(BUY + ".tooltip").startswith("Not profitable"))
check("vendor profit shown in red", has_line(ev, "Vendor profit", "|cffff2020-"))
run('VendorProfit.Shopper.Buy()')
check("even called directly, nothing is bought", ev("#__stub.ah.starts") == 0)
click(run, "buy")
check("clicking Buy anyway buys", ev("#__stub.ah.starts") == 1 and ev("VendorProfit.Shopper.Status()") == "quoting")
run('__stub.Advance(0.5)'); click(run, "cancel")
check("after that, plain Buy", ev(BUY + ".__text") == "Buy" and ev(BUY + ".tooltip").startswith("Buy "))
click(run, "scan"); run('__stub.Advance(3)')
check("a new scan asks again", ev(BUY + ".__text") == "Buy anyway")

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
      and ev(BUY + ".tooltip").startswith("Buy 29 Tin Bar"))
check("counted as in the mail", ev("VendorProfit.Order.InMail(2770)") == 24
      and section(ev, "Collect from mailbox") == ["|Ticon2770:0|t Copper Ore x24"])
run('__stub.bags[2770] = 24; __stub.mail[2770] = 0; __stub.Fire("BAG_UPDATE_DELAYED")')
check("collected from the mail: no longer counted as in the mail", ev("VendorProfit.Order.InMail(2770)") == 0)
check("...and still counted once", ev("VendorProfit.Shopper.Summary().plan.buy[2770]") is None
      and ev("VendorProfit.Shopper.Summary().plan.uses[2770]") == 24)
click(run, "buy"); run('__stub.Advance(0.5)'); click(run, "buy"); run('__stub.Advance(0.5)')
check("tin bars in the mail", ev("VendorProfit.Order.InMail(3576)") == 29)
run('__stub.Fire("MAIL_INBOX_UPDATE")')
check("mailbox opened with them there: still counted", ev("VendorProfit.Order.InMail(3576)") == 29)
run('__stub.mail[3576] = 0; __stub.Fire("MAIL_INBOX_UPDATE")')
check("mailbox shows they're gone (used as they arrived): no longer counted, needed again",
      ev("VendorProfit.Order.InMail(3576)") == 0 and ev("VendorProfit.Shopper.Summary().plan.buy[3576].quantity") == 29)

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
check("failed purchase: nothing recorded", ev("VendorProfit.Order.InMail(2770)") == 0 and ev("VendorProfitCharDB.order.spent") == 0)
check("failed purchase: says so and rescans", any("failed" in l for l in lines(ev)) and ev("VendorProfit.Shopper.Status()") == "scanning")
run('__stub.Advance(2)')
check("...then ready again", ev("VendorProfit.Shopper.Status()") == "ready" and ev("#__stub.ah.searches") == searches + 1)

run('__stub.ah.noPurchaseReply = true')
click(run, "buy"); run('__stub.Advance(0.5)'); click(run, "buy"); run('__stub.Advance(16)')
check("no reply to a purchase: not recorded, rescanned",
      ev("VendorProfitCharDB.order.spent") == 0 and any("No reply buying" in l for l in lines(ev)))
run('__stub.ah.noPurchaseReply = false; __stub.Advance(3)')
run('__stub.Fire("COMMODITY_PURCHASE_SUCCEEDED")')  # the timed-out purchase went through after all
check("a late success is still recorded", ev("VendorProfitCharDB.order.spent") == 8 * 52 + 16 * 60 and ev("VendorProfit.Order.InMail(2770)") == 24)
run('VendorProfitCharDB.order.inMail = {}; VendorProfitCharDB.order.lastSeen = {}; VendorProfitCharDB.order.spent = 0; VendorProfit.Order.Changed()')

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
    __stub.ah.listings[3576] = { { unitPrice = 75, quantity = 40 } } -- what a browse shows of it
''')
run('__stub.OpenAH()'); click(run, "scan"); run('__stub.Advance(3)')
check("asks for more listings when the first page isn't enough", ev("__stub.ah.moreRequests") >= 1
      and ev("VendorProfit.Shopper.Summary().plan.buy[2770].listed") == 10)
check("only 10 listed: says so", has_line(ev, "Copper Ore x24", "only 10 listed"))
check("buys what's there", ev(BUY + ".tooltip").startswith("Buy 10 Copper Ore"))
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


# --- Crafting counts the order down (the "profit changed" bug) ------------------
# Queue 2, buy everything, craft one: the order must give the same answer as
# clearing it and queuing 1 fresh.
def craft(run, recipe_id, used, made):
    """Crafts once: takes reagents from bags, adds the result, fires the events."""
    for item_id, n in used.items():
        run('__stub.bags[%d] = (__stub.bags[%d] or 0) - %d' % (item_id, item_id, n))
    for item_id, n in made.items():
        run('__stub.bags[%d] = (__stub.bags[%d] or 0) + %d' % (item_id, item_id, n))
    run('__stub.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", %d)' % recipe_id)
    run('__stub.Fire("BAG_UPDATE_DELAYED")')

run, ev = shop_client()
run('__stub.bags[2841] = 0; __stub.bags[2840] = 0; __stub.bank[2840] = 0')
run('__stub.createCount = 2'); run(QUEUE + ':Click()')
run('''
    __stub.ah.listings[2770] = { { unitPrice = 50, quantity = 100 } }
    __stub.ah.listings[3576] = { { unitPrice = 75, quantity = 100 } }
''')
run('__stub.OpenAH()'); click(run, "scan"); run('__stub.Advance(2)')
for _ in range(2):
    click(run, "buy"); run('__stub.Advance(0.5)'); click(run, "buy"); run('__stub.Advance(0.5)')
check("bought 7 ore and 7 tin bars for 2 cuirasses (14 bronze bars)", ev("__stub.bags[2770]") == 7 and ev("__stub.bags[3576]") == 7)

# Craft the first cuirass all the way: 4 copper bars, 4 bronze smelts (making
# 8 bars), then the cuirass, leaving 1 bronze bar, 3 ore and 3 tin bars.
for _ in range(4):
    craft(run, 2657, {COPPER_ORE: 1}, {COPPER_BAR: 1})
check("crafting intermediates doesn't count the order down", ev("VendorProfit.Order.Entries()[1].crafts") == 2)
for _ in range(4):
    craft(run, 2659, {COPPER_BAR: 1, TIN_BAR: 1}, {BRONZE_BAR: 2})
craft(run, 2670, {BRONZE_BAR: 7}, {CUIRASS_ID: 1})
check("crafting the queued item counts it down", ev("VendorProfit.Order.Entries()[1].crafts") == 1)
run('__stub.bags[2866] = 0; __stub.Fire("BAG_UPDATE_DELAYED")')  # sold it
old = ev("VendorProfit.Shopper.Summary()")
old_profit, old_buy = old.profit, {l.itemID: l.quantity for l in old.plan.buyOrder.values()}
check("plan works from what's left: 1 bronze bar, 3 ore, 3 tin bars", ev("__stub.bags[2841]") == 1
      and old.plan.uses[BRONZE_BAR] == 1 and old.plan.uses[COPPER_ORE] == 3 and old.plan.uses[TIN_BAR] == 3)
check("nothing more to buy", old_buy == {})

run('VendorProfit.Order.Clear()')
run('__stub.createCount = 1'); run(QUEUE + ':Click()')
fresh = ev("VendorProfit.Shopper.Summary()")
check("same profit as clearing and queuing again", abs(fresh.profit - old_profit) < 1e-6)
check("same shopping list as queuing again", {l.itemID: l.quantity for l in fresh.plan.buyOrder.values()} == old_buy)

for _ in range(3):
    craft(run, 2657, {COPPER_ORE: 1}, {COPPER_BAR: 1})
craft(run, 2670, {BRONZE_BAR: 7}, {CUIRASS_ID: 1})
check("crafting the last one finishes the order", ev("VendorProfit.Order.IsEmpty()") and ev("VendorProfitCharDB.order.spent") == 0)
run('__stub.Fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast", 2670)')
check("other people's casts ignored", ev("#__stub.errors") == 0)

# Saved data from 1.2.x is tidied.
run6, ev6 = route_client("VendorProfitCharDB = { order = { entries = {}, snapshot = { [1] = 2 }, bought = { [1] = 3 }, spent = 5 } }")
run6('VendorProfit.Order.Entries()')
check("old snapshot and purchase record dropped", ev6("VendorProfitCharDB.order.snapshot") is None and ev6("VendorProfitCharDB.order.bought") is None)


# --- Craft button ------------------------------------------------------------------
run, ev = shop_client()
run('__stub.bags[2841] = 0; __stub.bags[2840] = 0; __stub.bank[2840] = 0')
run('__stub.createCount = 2'); run(QUEUE + ':Click()')
OPEN = "VendorProfitOpenProfessionButton"
check("blacksmithing open, first step is mining: offers to open it",
      ev(CRAFT + ".__text") == "Open Mining" and ev(CRAFT + ".tooltip") == "Open Mining to craft Copper Bar" and ev(CRAFT + ":IsEnabled()"))
check("next step marked on the left", any(l.startswith("|cffffd100\u00bb|r ") and "Copper Bar x7" in l for l in lines(ev)))
check("a secure button covers the craft button and casts Smelting (how Mining opens)",
      ev(OPEN + ":IsShown()") and ev(OPEN + ':GetAttribute("type")') == "spell" and ev(OPEN + ':GetAttribute("spell")') == "Smelting")
check("cover placed on the screen, not anchored to the panel",
      ev(OPEN + ".__point[2] == UIParent") and ev(OPEN + ".__point[4]") == ev(CRAFT + ":GetLeft()"))
check("cover is on top", ev(OPEN + ".__strata") == "DIALOG")
run('__stub.inCombat = true; __stub.Fire("PLAYER_REGEN_DISABLED")')
check("combat starting hides the cover", not ev(OPEN + ":IsShown()"))
run('VendorProfit.Panel.Refresh()')
check("in combat: says to open it after combat, not clickable",
      ev(CRAFT + ".tooltip") == "Open Mining after combat to craft Copper Bar" and not ev(CRAFT + ":IsEnabled()") and not ev(OPEN + ":IsShown()"))
run('__stub.inCombat = false; __stub.Fire("PLAYER_REGEN_ENABLED")')
check("after combat the cover is back", ev(OPEN + ":IsShown()") and ev(CRAFT + ":IsEnabled()"))
run('VendorProfit.Panel.Hide()')
check("hiding the panel hides the cover", not ev(OPEN + ":IsShown()"))
run('VendorProfit.Panel.Show()')
run('VendorProfitPanel.__scripts.OnDragStart(VendorProfitPanel)')
check("dragging the panel hides the cover", not ev(OPEN + ":IsShown()"))
run('VendorProfitPanel.__scripts.OnDragStop(VendorProfitPanel)')
check("...and it's back after the drag", ev(OPEN + ":IsShown()"))
run('__stub.OpenProfession(186, "Mining", %s)' % MINING)
check("mining open: no cover", not ev(OPEN + ":IsShown()"))
check("mining open but no ore: missing materials",
      ev(CRAFT + ".__text") == "Craft" and ev(CRAFT + ".tooltip") == "Missing materials for Copper Bar" and not ev(CRAFT + ":IsEnabled()"))
run('__stub.bank[2770] = 7; __stub.Fire("BAG_UPDATE_DELAYED")')
check("ore only in the main bank: can't craft with it", ev(CRAFT + ".tooltip") == "Missing materials for Copper Bar")
run('__stub.bank[2770] = 0')
run('__stub.bags[2770] = 7; __stub.bags[3576] = 7; __stub.Fire("BAG_UPDATE_DELAYED")')
check("materials in the bags (the game's own count says 0): craft the copper bars", ev(CRAFT + ".tooltip") == "Craft Copper Bar, 7 times" and ev(CRAFT + ":IsEnabled()"))
run(CRAFT + ":Click()")
check("a click without a mouse down first crafts one (the game's quirk)", list(ev("__stub.crafted[1]").values()) == [2657, 1])
run(CRAFT + ".__scripts.OnMouseDown(" + CRAFT + ")")
run('__stub.Advance(0.05)')
run(CRAFT + ":Click()")
check("pressed then clicked: crafts all 7", list(ev("__stub.crafted[2]").values()) == [2657, 7])
run('__stub.casting = "Smelt Copper"; __stub.Fire("UNIT_SPELLCAST_START", "player")')
check("while casting: button waits", ev(CRAFT + ".__text") == "Crafting..." and not ev(CRAFT + ":IsEnabled()"))
run('__stub.casting = nil; __stub.bags[2770] = 0; __stub.bags[2840] = 7; __stub.Fire("BAG_UPDATE_DELAYED")')
check("copper bars made: next is bronze bars", ev(CRAFT + ".tooltip") == "Craft Bronze Bar, 7 times" and any(l.startswith("|cffffd100\u00bb|r ") and "Bronze Bar x14" in l for l in lines(ev)))
run('__stub.bags[2840] = 0; __stub.bags[3576] = 0; __stub.bags[2841] = 14; __stub.Fire("BAG_UPDATE_DELAYED")')
check("bronze made: the cuirass is in blacksmithing", ev(CRAFT + ".__text") == "Open Blacksmithing"
      and ev(CRAFT + ".tooltip") == "Open Blacksmithing to craft Rough Bronze Cuirass")
check("cover casts Blacksmithing", ev(OPEN + ':GetAttribute("spell")') == "Blacksmithing" and ev(OPEN + ":IsShown()"))
run('__stub.OpenProfession(164, "Blacksmithing", { %s })' % CUIRASS)
check("blacksmithing open: craft the cuirasses", ev(CRAFT + ".tooltip") == "Craft Rough Bronze Cuirass, 2 times")
run('VendorProfit.Order.Clear()')
check("empty order: no craft button", ev(CRAFT) is None)
check("no errors from crafting", ev("#__stub.errors") == 0)


# --- Search button -------------------------------------------------------------------
run, ev = shop_client()
SEARCH = "AuctionatorCraftingInfoProfessionsFrame.VendorProfitSearchButton"
check("search hidden while the auction house is closed", not ev(SEARCH + ":IsShown()"))
run('__stub.OpenAH()')
check("search shown at the auction house, top right of the section",
      ev(SEARCH + ":IsShown()") and ev(SEARCH + ".__point[1]") == "TOPRIGHT" and ev(SEARCH + ".__point[2] == " + SECTION + ".separator"))
check("search sized like Auctionator's: same template, 22 high, as wide as its text",
      ev(SEARCH + ".__h") == 22 and ev(SEARCH + ".__w") == 6 * 6 + 40)
check("search clickable over the tooltip area", ev(SEARCH + ":GetFrameLevel()") > ev(SECTION + ".hover:GetFrameLevel()"))
tree = list(ev("VendorProfit.Route.TreeItems(2866, VendorProfit.Recipes.ReagentsFromSchematic(VendorProfit.Calculate(ProfessionsFrame.CraftingPage.SchematicForm).recipeSchematic))").values())
check("tree: the item, then reagents before what they're made from, including options the route doesn't use",
      tree == [CUIRASS_ID, BRONZE_BAR, COPPER_BAR, TIN_BAR, COPPER_ORE, TIN_ORE])
run('__stub.items["item:2866"].bind = 1')  # the cuirass binds on pickup
run('''
    __stub.ah.listings[2841] = { { unitPrice = 40, quantity = 50 } }
    __stub.ah.listings[2840] = { { unitPrice = 70, quantity = 50 } }
    __stub.ah.auctionatorSaves = true
''')
toCraftBefore = ev(SECTION + ".toCraft:GetText()")
run(SEARCH + ':Click()')
check("click: looking up, button off until done", ev("VendorProfit.BestCrafts.Scanning()") == "items" and not ev(SEARCH + ":IsEnabled()"))
run('__stub.Advance(1)')
lookups = [list(x.values()) for x in ev("__stub.ah.itemKeySearches").values()]
check("one batch request for the whole tree, not a search per item",
      lookups == [[BRONZE_BAR, COPPER_BAR, TIN_BAR, COPPER_ORE, TIN_ORE]] and ev("__stub.searched") is None
      and ev("#__stub.ah.searches") == 0)
check("bind-on-pickup items left out", CUIRASS_ID not in lookups[0])
check("done: button back on", not ev("VendorProfit.BestCrafts.IsScanning()") and ev(SEARCH + ":IsEnabled()"))
check("route updates from the prices Auctionator saved", ev(SECTION + ".toCraft:GetText()") != toCraftBefore)
check("Best Crafts' message untouched", ev("VendorProfit.BestCrafts.Message() == nil"))
run('__stub.ah.auctionatorSaves = false')
run(SEARCH + ':GetScript("OnEnter")(' + SEARCH + ')')
check("tooltip says shift-click lists them in Auctionator", any("Shift-click" in (l.left or "") for l in ev("GameTooltip.lines").values()))

# No answer: says so in chat.
run('__stub.ah.dropBrowse = true; ' + SEARCH + ':Click(); __stub.Advance(16); __stub.ah.dropBrowse = false')
check("no answer: stops, button back on, says so", not ev("VendorProfit.BestCrafts.IsScanning()") and ev(SEARCH + ":IsEnabled()")
      and any("Try Search again" in str(m) for m in ev("__stub.printed or {}").values()))

# Shift-click: Auctionator's own search, listing every item.
run('__stub.shift = true')
run(SEARCH + ':Click()')
names = [t.searchString for t in ev("__stub.searched").values()]
check("shift-click searches Auctionator for every item in the tree, exact names", names == ["Bronze Bar", "Copper Bar", "Tin Bar", "Copper Ore", "Tin Ore"]
      and all(t.isExact for t in ev("__stub.searched").values()))
check("...leaving out bind-on-pickup items", "Rough Bronze Cuirass" not in names)
run('__stub.items["item:2771"].cached = false; __stub.searched = nil')
run(SEARCH + ':Click()')
check("waits for item names to load", ev("__stub.searched") is None)
run('__stub.LoadItem("item:2771")')
check("...then searches", len(list(ev("__stub.searched").values())) == 5)
run('__stub.shift = false')
run('__stub.CloseAH()')
check("search hides when the auction house closes", not ev(SEARCH + ":IsShown()"))
check("no errors from searching", ev("#__stub.errors") == 0)


# --- Buy before scanning: scans, then goes on to buy ----------------------------------
run, ev = shop_client()
run('__stub.SetRecipe(%s)' % CUIRASS)
run('__stub.createCount = 10'); run(QUEUE + ':Click()')
run('''
    __stub.ah.listings[2770] = { { unitPrice = 50, quantity = 10 }, { unitPrice = 55, quantity = 20 }, { unitPrice = 80, quantity = 100 } }
    __stub.ah.listings[3576] = { { unitPrice = 75, quantity = 10 }, { unitPrice = 78, quantity = 30 } }
''')
run('__stub.OpenAH()')
click(run, "buy")
check("Buy before a scan: scans", ev("VendorProfit.Shopper.Status()") == "scanning")
run('__stub.Advance(2)')
check("...then asks for the first quote, no second click", ev("VendorProfit.Shopper.Status()") in ("quoting", "confirm")
      and list(ev("__stub.ah.starts[1]").values()) == [COPPER_ORE, 24])
run('__stub.Advance(0.5)')
check("...and waits for you to confirm", ev("VendorProfit.Shopper.Status()") == "confirm" and ev("#__stub.ah.confirms") == 0)
run('VendorProfit.Shopper.Cancel()')
run('__stub.CloseAH(); __stub.ah.starts = {}')
# Losing money: the scan stops at Buy anyway.
run('__stub.ah.listings[2770] = { { unitPrice = 5000, quantity = 100 } }')
run('__stub.OpenAH()')
click(run, "buy")
run('__stub.Advance(2)')
check("order loses money: scanned, nothing quoted, Buy anyway offered", ev("VendorProfit.Shopper.Status()") == "ready"
      and ev("#__stub.ah.starts") == 0 and ev(BUY + ".__text") == "Buy anyway")
check("no errors", ev("#__stub.errors") == 0)


# --- Scan: one batch lookup first, then listings only for what's bought ---------------
def batch_client():
    run, ev = shop_client()
    run('__stub.SetRecipe(%s)' % CUIRASS)
    run('__stub.createCount = 10'); run(QUEUE + ':Click()')
    run('''
        __stub.ah.listings[2770] = { { unitPrice = 50, quantity = 10 }, { unitPrice = 55, quantity = 20 }, { unitPrice = 80, quantity = 100 } }
        __stub.ah.listings[3576] = { { unitPrice = 75, quantity = 10 }, { unitPrice = 78, quantity = 30 } }
        __stub.auctionPrices[2841] = 10 -- Auctionator remembers cheap bronze bars, but none are listed now
    ''')
    run('__stub.OpenAH()')
    return run, ev
run, ev = batch_client()
click(run, "scan")
check("scan starts with a batch lookup of the whole order", ev("VendorProfit.Shopper.IsLookingUp()")
      and ev(BUY + ".tooltip") == "Looking up prices for the whole order...")
run('__stub.Advance(3)')
lookups = [sorted(x.values()) for x in ev("__stub.ah.itemKeySearches").values()]
check("one batch request with every item in the order's tree", lookups == [sorted([CUIRASS_ID, BRONZE_BAR, COPPER_BAR, TIN_BAR, COPPER_ORE, TIN_ORE])])
check("then listings only for what's bought: nothing searched for the unlisted bronze bars",
      list(ev("__stub.ah.searches").values()) == [COPPER_ORE, TIN_BAR] and ev("VendorProfit.Shopper.Status()") == "ready")
check("bronze bars crafted, not bought at Auctionator's stale price", ev("VendorProfit.Shopper.Summary().plan.buy[2841]") is None)
check("purchases still priced from the listings", ev(BUY + ".tooltip") == "Buy 24 Copper Ore for |cffffffff12s 70c|r")
check("Best Crafts' message untouched", ev("VendorProfit.BestCrafts.Message() == nil"))

# The batch lookup gets no answer: the scan goes on without it.
run, ev = batch_client()
run('__stub.ah.dropBrowse = true')
click(run, "scan"); run('__stub.Advance(16)')
run('__stub.ah.dropBrowse = false; __stub.Advance(3)')
check("batch lookup unanswered: listings scanned anyway", ev("VendorProfit.Shopper.Status()") == "ready"
      and COPPER_ORE in list(ev("__stub.ah.searches").values()) and ev(BUY + ".tooltip").startswith("Buy 24 Copper Ore"))

# Best Crafts busy scanning: no batch lookup, same as before.
run, ev = batch_client()
run('__stub.ah.dropBrowse = true; VendorProfit.BestCrafts.Scan(VendorProfit.Recipes.OpenProfession())')
click(run, "scan")
check("Best Crafts busy: straight to the listings", not ev("VendorProfit.Shopper.IsLookingUp()"))
run('__stub.Advance(3)')
check("...and done", ev("VendorProfit.Shopper.Status()") == "ready" and ev(BUY + ".tooltip").startswith("Buy 24 Copper Ore"))
run('__stub.CloseAH()')
check("no errors", ev("#__stub.errors") == 0)


# --- Profit history ---------------------------------------------------------------------
# Test Ring: one Copper Bar makes one, which sells to a vendor for 2s.
RING2 = """{ recipeID = 9201, itemLink = "item:2903", quantityMin = 1, reagents = { { itemID = 2840, quantity = 1 } } }"""
def history_client():
    run, ev = shop_client()
    run('__stub.items["item:2903"] = { name = "Test Ring", cached = true, sellPrice = 200 }')
    run('__stub.items["item:2840"].name = "Copper Bar"')
    run('__stub.bags[2840] = 0; __stub.bank[2840] = 0')
    run('__stub.OpenProfession(164, "Blacksmithing", { %s, %s }); __stub.Advance(1)' % (CUIRASS, RING2))
    return run, ev
craft = lambda run: run('__stub.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 9201)')
H = "VendorProfit.History"
run, ev = history_client()
run('VendorProfit.Panel.Show("history")')
check("history tab: empty to start, saying what it tracks", ev("VendorProfit.Panel.ActiveTab()") == "history"
      and ev("VendorProfit.HistoryPanel.Frame().empty:IsShown()") and ev("VendorProfitPanel.tabs.history.label") == "Profit History")

# Day 1: buy a Copper Bar at auction for 1s (taken from its mail), craft, sell to a vendor for 2s.
run('__stub.invoiceMails = { { itemID = 2840, n = 1, subject = "Auction won: Copper Bar", invoice = { type = "buyer", itemName = "Copper Bar", bid = 100, count = 1 } } }')
run('__stub.Fire("MAIL_INBOX_UPDATE"); TakeInboxItem(1)')
check("auction purchase recorded at what you paid, from its mail", ev(H + ".Recorded(2840)") == 1
      and ev("VendorProfitCharDB.history.stock[2840][1].cost") == 100)
run('TakeInboxItem(1)')
check("taking the same mail twice records it once", ev(H + ".Recorded(2840)") == 1)
craft(run)
check("craft: the bar's cost goes into the ring", ev(H + ".Recorded(2840)") == 0 and ev(H + ".Recorded(2903)") == 1
      and ev("VendorProfitCharDB.history.stock[2903][1].cost") == 100)
run('__stub.bags[2903] = 1; __stub.OpenMerchant({})')
run('__stub.SellItem(2903, 1)')
sales = lambda: [dict(sale.items()) for sale in ev(H + ".Sales()").values()]
check("vendor sale recorded from the buyback list: cost 1s, sold 2s", [(x["n"], x["how"], x["cost"], x["sold"], x["bought"]) for x in sales()]
      == [(1, "vendor", 100, 200, 100)])

# Day 2: the bar costs 1s 50c from a vendor; the ring sells at auction for 1s 90c less a 10c cut.
run('__stub.CloseMerchant(); __stub.OpenMerchant({ { itemID = 2840, price = 150 } })')
run('BuyMerchantItem(1, 1)')
check("vendor purchase recorded at what you paid", ev(H + ".Recorded(2840)") == 1 and ev("VendorProfitCharDB.history.stock[2840][1].cost") == 150)
run('__stub.CloseMerchant()')
craft(run)
run('__stub.invoiceMails = { { money = 180, subject = "Auction successful: Test Ring", invoice = { type = "seller", itemName = "Test Ring", bid = 190, consignment = 10, count = 1 } } }')
run('__stub.Fire("MAIL_INBOX_UPDATE"); TakeInboxMoney(1)')
check("auction sale recorded when its money is taken: 1s 90c less the 10c cut, against the 1s 50c it cost",
      [(x["how"], x["cost"], x["sold"]) for x in sales()] == [("auction", 150, 180), ("vendor", 100, 200)])

# A craft from your own bars: valued at market (Auctionator: 1s 20c), none of it bought.
run('__stub.auctionPrices[2840] = 120')
craft(run)
market = ev("VendorProfit.Route.UnitCost(2840)")
check("own reagents at market value (the cheapest way to get one now)", market > 0
      and ev("VendorProfitCharDB.history.stock[2903][1].cost") == market and ev("VendorProfitCharDB.history.stock[2903][1].bought") == 0)

# Selling and buying back: undone.
run('__stub.bags[2903] = 1; __stub.OpenMerchant({})')
run('__stub.SellItem(2903, 1)')
check("sold again", len(sales()) == 3)
run('BuybackItem(#__stub.buyback); __stub.Advance(0.1)')
check("bought back: that sale is gone, its cost back on the ring", len(sales()) == 2 and ev(H + ".Recorded(2903)") == 1)
run('__stub.SellItem(2903, 1)')
check("sold once more after the buyback: one new sale", len(sales()) == 3 and sales()[0]["cost"] == round(market))
run('__stub.bags[2903] = 1; __stub.SellItem(2903, 1)')
check("selling one with no recorded cost (made before tracking): left out", len(sales()) == 3)
run('__stub.CloseMerchant()')

# The tab: newest first, totals, a breakdown on hover.
run('VendorProfit.Panel.Show("history")')
rows = list(ev("VendorProfit.HistoryPanel.Lines()").values())
check("listed newest first: date, item, how, cost, sold for, profit", len(rows) == 3
      and rows[1].endswith("|cffffffff1s 50c|r | |cffffffff1s 80c|r | |cffffffff30c|r") and " | Auction | " in rows[1]
      and " | Vendor | " in rows[2] and rows[2].endswith("|cffffffff1s|r | |cffffffff2s|r | |cffffffff1s|r"))
total = ev('VendorProfit.FormatMoney(%d)' % (100 + 30 + 200 - round(market)))
check("totals: all of it and the last 7 days", ev("VendorProfit.HistoryPanel.Frame().total:GetText()")
      == "Profit: %s from 3 sales. Last 7 days: %s." % (total, total))
run('VendorProfit.HistoryPanel.Row(1).hit:GetScript("OnEnter")()')
tip = [(l.left, l.right) for l in ev("GameTooltip.lines").values()]
check("hover: what was bought and what was your own items at market value", ("Bought", "|cffffffff0c|r") in tip
      and ("Your own items, at market value", ev('VendorProfit.FormatMoney(%d)' % round(market))) in tip)
check("window wider for the history's columns", ev("VendorProfitPanel:GetWidth()") == 540)
run('SlashCmdList.VENDORPROFIT("history")')
check("/vprofit history toggles it", not ev("VendorProfit.Panel.IsShown()"))

# Bought reagents that go some other way (mailed to an alt) stop counting, once things settle.
run('__stub.CloseMerchant(); __stub.OpenMerchant({ { itemID = 2840, price = 150 } }); BuyMerchantItem(1, 2); __stub.CloseMerchant()')
run('__stub.bags[2840] = 0; __stub.Advance(7); __stub.Fire("BAG_UPDATE_DELAYED"); __stub.Advance(7)')
check("reagents you no longer have stop counting", ev(H + ".Recorded(2840)") == 0)
craft(run)
run('__stub.bags[2903] = 0; __stub.Advance(7); __stub.Fire("BAG_UPDATE_DELAYED"); __stub.Advance(7)')
check("crafted items out of your bags still count (they may be up for auction)", ev(H + ".Recorded(2903)") == 1)
run('__stub.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 12345)')
check("other spells aren't crafts", ev(H + ".Recorded(2903)") == 1)
check("no errors", ev("#__stub.errors") == 0)

# Purchase History: every purchase above, newest first, what each one cost.
run('VendorProfit.Panel.Show("purchases")')
bought = list(ev("VendorProfit.PurchasePanel.Lines()").values())
check("purchases listed newest first: date, item, from, each, total, now", len(bought) == 3
      and "|t Copper Bar x2 | Vendor | |cffffffff1s 50c|r | |cffffffff3s|r | " in bought[0]
      and "|t Copper Bar | Vendor | |cffffffff1s 50c|r | |cffffffff1s 50c|r | " in bought[1]
      and "|t Copper Bar | Auction | |cffffffff1s|r | |cffffffff1s|r | " in bought[2])
check("...with today's cheapest price to compare", bought[2].endswith(ev('VendorProfit.FormatMoney(math.min(150, %d))' % 120)))
check("window as wide as the history", ev("VendorProfitPanel:GetWidth()") == 540 and ev("VendorProfitPanel.tabs.purchases.label") == "Purchase History")
run('VendorProfit.PurchasePanel.Row(1).hit:GetScript("OnEnter")()')
check("hover: what you paid each, and the cheapest now", ("You paid each", "|cffffffff1s 50c|r") in [(l.left, l.right) for l in ev("GameTooltip.lines").values()])
run('VendorProfitCharDB.history.purchases = {}; VendorProfit.Panel.Refresh()')
check("none yet: says where they come from", ev("VendorProfit.PurchasePanel.Frame().empty:IsShown()"))
run('SlashCmdList.VENDORPROFIT("purchases")')
check("/vprofit purchases toggles it", not ev("VendorProfit.Panel.IsShown()"))
run('for i = 1, 510 do VendorProfit.History.Bought(2840, 1, 100, "vendor") end')
check("keeps the last 500", ev("#VendorProfitCharDB.history.purchases") == 500)


# --- Known vendor prices ---------------------------------------------------------------
run, ev = shop_client()
run('__stub.auctionPrices[2320] = 13')
check("Coarse Thread with no vendor price from Auctionator yet: the usual 10c", ev("(VendorProfit.GetBuyPrices(2320))") == 10
      and ev("select(2, VendorProfit.GetBuyPrices(2320))") == 13)
run('__stub.vendorPrices[2320] = 12')
check("...Auctionator's recorded price wins once it has one", ev("(VendorProfit.GetBuyPrices(2320))") == 12)
check("items vendors don't sell: no vendor price", ev("(VendorProfit.GetBuyPrices(2866))") is None)
# /vprofit prices: the open vendor's prices in the list's format, to paste in.
run('__stub.items["item:2321"] = { name = "Fine Thread", cached = true }')
run('__stub.items["item:2320"] = { name = "Coarse Thread", cached = true }')
run('__stub.items["item:99999"] = { name = "New Thing", cached = true }')
run('SlashCmdList.VENDORPROFIT("prices")')
check("/vprofit prices away from a vendor says to talk to one", ev("VendorProfitPriceExport") is None
      and any("talk to a vendor first" in m for m in ev("__stub.printed").values()))
run('''__stub.OpenMerchant({ { itemID = 2321, price = 120 }, { itemID = 2320, price = 50, stackCount = 5 },
    { itemID = 99999, price = 7 }, { itemID = 2880, price = 100, numAvailable = 3 }, { itemID = 2324, price = 25, extended = true } })''')
run('SlashCmdList.VENDORPROFIT("prices")')
text = ev("VendorProfitPriceExport.edit.__text")
check("lists the vendor's prices in the file's format, per item, sorted, marking new and changed",
      text.split("\n") == ["    [2320] = 10, -- Coarse Thread", "    [2321] = 120, -- Fine Thread (was 100)", "    [99999] = 7, -- New Thing (new)"])
check("...leaving out limited stock and items that cost more than gold", "2880" not in text and "2324" not in text)
check("ready to copy", ev("VendorProfitPriceExport:IsShown()") and ev("VendorProfitPriceExport.edit.__highlighted")
      and ev("VendorProfitPriceExport.note:GetText()") == "3 items, 2 new or changed. Copy (Ctrl+C) the lines you want into VendorPrices.lua.")
run('__stub.CloseMerchant()')
check("only Auctionator needed: the list is the addon's own", ev("VendorProfit.KNOWN_VENDOR_PRICES[2320]") == 10
      and ev("TSM_API") is None)


# --- Buying from a vendor ------------------------------------------------------------
# Bronze Shield: 2 Bronze Bars (in bags) and 1 Weak Flux (vendor only, 1s).
SHIELD = """{ recipeID = 9001, itemLink = "item:2900", quantityMin = 1,
    reagents = { { itemID = 2841, quantity = 2 }, { itemID = 2880, quantity = 1 } } }"""
run, ev = shop_client()
run('__stub.items["item:2900"] = { name = "Bronze Shield", cached = true, sellPrice = 900 }')
run('__stub.items["item:2880"] = { name = "Weak Flux", cached = true, sellPrice = 25 }')
run('__stub.vendorPrices[2880] = 100')
run('__stub.OpenProfession(164, "Blacksmithing", { %s, %s })' % (CUIRASS, SHIELD))
run('__stub.SetRecipe(%s)' % SHIELD)
run('__stub.createCount = 3'); run(QUEUE + ':Click()')
check("flux to buy from a vendor", section(ev, "Buy") == ["|Ticon2880:0|t Weak Flux x3 | vendor  |cffffffff3s|r"])
check("away from vendors: says to find one, not the auction house",
      ev(BUY + ".__text") == "Buy" and not ev(BUY + ":IsEnabled()") and "sold by vendors" in ev(BUY + ".tooltip"))
run('VendorProfit.Panel.Hide()')
run('__stub.OpenMerchant({ { itemID = 3371, price = 20, stackCount = 5 } })')
check("a vendor that doesn't sell it: no buying, window stays shut", not ev("VendorProfit.Panel.IsShown()"))
run('__stub.CloseMerchant()')
run('__stub.OpenMerchant({ { itemID = 3371, price = 20 }, { itemID = 2880, price = 90 } })')
check("a vendor that sells it: the window opens beside it", ev("VendorProfit.Panel.IsShown()")
      and ev("VendorProfitPanel.__point[2] == MerchantFrame"))
check("Buy on, saying what it buys here", ev(BUY + ":IsEnabled()") and ev(BUY + ".__text") == "Buy"
      and ev(BUY + ".tooltip") == "Buy from this vendor: 3 Weak Flux, for |cffffffff2s 70c|r.")
money = ev("__stub.money")
run(BUY + ":Click()")
check("bought exactly what's needed in one go", [(b.itemID, b.quantity) for b in ev("__stub.merchantBuys").values()] == [(2880, 3)]
      and ev("__stub.money") == money - 270)
run('__stub.Fire("BAG_UPDATE_DELAYED")')
check("nothing left to buy: the Buy step is gone", ev(BUY) is None)
check("spent recorded", ev("VendorProfitCharDB.order.spent") == 270)
check("says what it bought", any("bought 3 Weak Flux from the vendor" in m for m in ev("__stub.printed").values()))

# A double click: the second click finds the purchase on its way, not still needed.
run('__stub.Advance(0.1); __stub.bags[2880] = 0; __stub.merchantBuys = {}; __stub.merchantDelay = 0.5; VendorProfit.Order.Changed()')
run('__stub.CloseMerchant(); __stub.OpenMerchant({ { itemID = 2880, price = 90 } })')
run(BUY + ":Click()")
check("after buying, Buy waits for the purchase to arrive", ev(BUY + ".__text") == "Buying..." and not ev(BUY + ":IsEnabled()")
      and ev(BUY + ".tooltip") == "Waiting for your purchase to reach your bags.")
run(BUY + ":Click(); VendorProfit.Merchant.Buy(VendorProfit.Merchant.Offers(VendorProfit.Shopper.Summary().plan))")
check("double click (or a second call): bought once", len(list(ev("__stub.merchantBuys").values())) == 1)
check("nothing more offered while it's on its way", ev("#VendorProfit.Merchant.Offers(VendorProfit.Shopper.Summary().plan)") == 0)
run('__stub.Advance(1)')
check("arrived: nothing left to buy", ev(BUY) is None and ev("__stub.bags[2880]") == 3)
# Never arrives: Buy comes back after a while.
run('__stub.bags[2880] = 0; __stub.merchantBuys = {}; __stub.merchantLost = true; VendorProfit.Order.Changed()')
run(BUY + ":Click()")
check("lost purchase: waiting", ev(BUY + ".__text") == "Buying...")
run('__stub.Advance(11)')
check("...then Buy is back", ev(BUY + ".__text") == "Buy" and ev(BUY + ":IsEnabled()"))
run('__stub.merchantLost = false; __stub.merchantDelay = nil')

# Sold in batches of 5, and limited stock; short of gold.
run('__stub.Advance(0.1); __stub.bags[2880] = 0; __stub.merchantBuys = {}; VendorProfit.Order.Changed()')
run('__stub.CloseMerchant(); __stub.OpenMerchant({ { itemID = 2880, price = 400, stackCount = 5 } })')
check("batches: buys whole batches", ev(BUY + ".tooltip") == "Buy from this vendor: 5 Weak Flux, for |cffffffff4s|r.")
run(BUY + ":Click()")
check("one batch at a time (no quantity)", [(b.itemID, b.quantity) for b in ev("__stub.merchantBuys").values()] == [(2880, None)])
run('__stub.Advance(0.1); __stub.bags[2880] = 0; __stub.merchantBuys = {}; __stub.money = 150; VendorProfit.Order.Changed()')
run('__stub.CloseMerchant(); __stub.OpenMerchant({ { itemID = 2880, price = 100 } })')
run(BUY + ":Click()")
check("short of gold: buys what it can, and says so", [(b.itemID, b.quantity) for b in ev("__stub.merchantBuys").values()] == [(2880, 1)]
      and any("not enough gold" in m for m in ev("__stub.printed").values()))
run('__stub.money = 1000000; __stub.merchantBuys = {}')
run('__stub.CloseMerchant(); __stub.OpenMerchant({ { itemID = 2880, price = 100, extended = true } })')
check("items that cost more than gold aren't bought", not ev(BUY + ":IsEnabled()"))
run('__stub.CloseMerchant()')

# Something planned from the auction house that a vendor sells for less.
run('__stub.Advance(0.1); __stub.bags[2880] = 5; VendorProfit.Order.Clear()')
run('__stub.SetRecipe(%s)' % CUIRASS)
run('__stub.createCount = 10'); run(QUEUE + ':Click()')
run('__stub.OpenMerchant({ { itemID = 3576, price = 60 }, { itemID = 2770, price = 99 } })')
check("vendor sells tin bars cheaper than the auction house: bought here; copper ore dearer: left for the AH",
      ev(BUY + ".tooltip").startswith("Buy from this vendor: 29 Tin Bar,") and "Tin Bar" in ev(BUY + ".tooltip")
      and "Copper Ore" not in ev(BUY + ".tooltip"))
run('__stub.CloseMerchant()')
check("no errors at the vendor", ev("#__stub.errors") == 0)


# --- Taking things out of the bank --------------------------------------------------
# Need 7 copper bars and 7 tin bars for 2 cuirasses. Have none in bags; the
# bank has 5 copper bars in one tab slot and 4 + 10 in another tab, and 10 tin bars.
run, ev = shop_client()
run('__stub.bags[2841] = 0; __stub.bags[2840] = 0; __stub.bank[2840] = 0')
run('''
    __stub.PutInBank(6, 1, 2840, 5)
    __stub.PutInBank(7, 3, 2840, 4)
    __stub.PutInBank(7, 4, 2840, 10)
    __stub.PutInBank(8, 1, 3576, 10)
''')
run('__stub.createCount = 2'); run(QUEUE + ':Click()')
check("bank section lists what to fetch", section(ev, "Take from bank") == ["|Ticon2840:0|t Copper Bar x7", "|Ticon3576:0|t Tin Bar x7"])
TAKE = 'VendorProfit.Panel.RowButton("Take from bank")'
check("take button on the bank heading, off until the bank opens",
      ev(TAKE + ":IsShown()") and ev(TAKE + ".__text") == "Take" and not ev(TAKE + ":IsEnabled()")
      and ev(TAKE + ".tooltip") == "Open your bank to take these out.")
run('VendorProfit.Panel.Hide()')
run('__stub.OpenBank()')
check("opening the bank opens the panel when there's something to fetch", ev("VendorProfit.Panel.IsShown()"))
check("docked beside the bank", ev("VendorProfitPanel.__point[2] == BankFrame"))
moves = ev("(VendorProfit.Banker.PlanMoves({ { itemID = 2840, quantity = 7 }, { itemID = 3576, quantity = 7 } }))")
mv = [(m.bag, m.slot, m.itemID, m.quantity) for m in moves.values()]
check("plans exact amounts, smallest stacks first", mv == [(7, 3, 2840, 4), (6, 1, 2840, 3), (8, 1, 3576, 7)])
check("take button on once the bank is open", ev(TAKE + ":IsEnabled()"))
run(TAKE + ':Click()')
check("moving", ev("VendorProfit.Banker.IsMoving()") and ev(TAKE + ".__text") == "Taking...")
run('__stub.Advance(2)')
check("moved exactly: 7 copper bars and 7 tin bars into the bags", ev("__stub.bags[2840]") == 7 and ev("__stub.bags[3576]") == 7)
check("rest stays in the bank", ev("__stub.bank[2840]") == 12 and ev("__stub.bank[3576]") == 3)
check("split, not whole stacks", [tuple(x.values()) for x in ev("__stub.splits").values()] == [(7, 3, 4), (6, 1, 3), (8, 1, 7)])
check("says it's done", any("Took everything from the bank" in l for l in lines(ev)))
run('__stub.Fire("BAG_UPDATE_DELAYED")')
check("bank section gone, items now from bags", section(ev, "Take from bank") is None
      and section(ev, "Already in your bags")[:2] == ["|Ticon2840:0|t Copper Bar x7", "|Ticon3576:0|t Tin Bar x7"]
      and headings(ev)[2:4] == ["To do", "1. Craft"])
run('__stub.CloseBank()')
check("stays open when the bank closes", ev("VendorProfit.Panel.IsShown()"))
check("no errors from the bank", ev("#__stub.errors") == 0)

# Waiting for locks, full bags, missing items, bank closing.
run, ev = shop_client()
run('__stub.bags[2841] = 0; __stub.bags[2840] = 0; __stub.bank[2840] = 0')
run('__stub.PutInBank(6, 1, 2840, 3); __stub.PutInBank(6, 2, 2840, 3)')
run('__stub.OpenBank()')
run('__stub.lockMoves = true')
run('VendorProfit.Banker.Withdraw({ { itemID = 2840, quantity = 6 } })')
run('__stub.Advance(1)')
check("waits while the moved item is locked", ev("#__stub.splits") == 1 and ev("VendorProfit.Banker.IsMoving()"))
run('__stub.containers[0][1].locked = false; __stub.lockMoves = false; __stub.Advance(1)')
check("then does the next move", ev("#__stub.splits") == 2 and ev("__stub.bags[2840]") == 6)
run('__stub.Advance(1)')
check("into a different bag slot", ev("__stub.containers[0][2].count") == 3)

run, ev = shop_client()
run('__stub.PutInBank(6, 1, 2840, 3)')
run('__stub.FillBags(); __stub.OpenBank()')
run('VendorProfit.Banker.Withdraw({ { itemID = 2840, quantity = 3 } })'); run('__stub.Advance(1)')
check("full bags: stops and says so", not ev("VendorProfit.Banker.IsMoving()") and ev("(VendorProfit.Banker.Message())") == "Your bags are full.")

run, ev = shop_client()
run('__stub.PutInBank(6, 1, 2840, 2); __stub.OpenBank()')
run('VendorProfit.Banker.Withdraw({ { itemID = 2840, quantity = 5 } })'); run('__stub.Advance(1)')
check("takes what's there and says some wasn't", ev("__stub.bags[2840]") == 3 + 2
      and ev("(VendorProfit.Banker.Message())") == "Took what was there; some of it wasn't in the bank.")
run('VendorProfit.Banker.Withdraw({ { itemID = 9999, quantity = 1 } })')
check("nothing of it in the bank: says so", ev("(VendorProfit.Banker.Message())") == "None of these are in the bank.")

run, ev = shop_client()
run('__stub.PutInBank(6, 1, 2840, 2); __stub.PutInBank(6, 2, 2840, 2); __stub.OpenBank()')
run('VendorProfit.Banker.Withdraw({ { itemID = 2840, quantity = 4 } })')
run('__stub.CloseBank(); __stub.Advance(1)')
check("bank closing mid-way stops", not ev("VendorProfit.Banker.IsMoving()") and ev("#__stub.splits") == 1)
run('VendorProfit.Banker.Withdraw({ { itemID = 2840, quantity = 1 } })')
check("can't take with the bank closed", ev("#__stub.splits") == 1)
check("no errors from bank edge cases", ev("#__stub.errors") == 0)


# --- Auction profit without an auction price; dividers ------------------------------
run, ev = shop_client()
run('__stub.createCount = 10'); run(QUEUE + ':Click()')
run('__stub.auctionPrices[2866] = nil; VendorProfit.Order.Changed()')
check("no auction price for the item: auction price and profit say so",
      has_line(ev, "Auction price", "no auction price") and has_line(ev, "Auction profit", "no auction price"))


# --- Profit as a sum; Clear on Queued; one craft -------------------------------------
run, ev = shop_client()
run('__stub.createCount = 1'); run(QUEUE + ':Click()')
prof = section(ev, "Profit")
check("profit rows in order",
      [l.split(" | ")[0] for l in prof[:6]] == ["Vendor price", "Auction price", "Items you have", "Items to buy", "Vendor profit", "Auction profit"])
check("one craft, not '1 crafts'", has_line(ev, "Rough Bronze Cuirass x1", "Blacksmithing, 1 craft") and not has_line(ev, "1 crafts"))
check("no Clear button on Queued", ev('VendorProfit.Panel.RowButton("Queued")') is None)
check("no buttons left at the bottom", ev('VendorProfit.Panel.FindButton("Scan again")') is None)


# --- Money: two-digit silver and copper after a larger coin --------------------------
run, ev = client()
for copper, text in [(507, "5s 07c"), (570, "5s 70c"), (7, "7c"), (500, "5s"), (10507, "1g 05s 07c"),
                     (10007, "1g 07c"), (10000, "1g"), (0, "0c"), (-507, "5s 07c")]:
    check("coins: %d -> %s" % (copper, text), ev("VendorProfit.FormatCoins(%d)" % copper) == text)
check("loss in red with a minus", ev("VendorProfit.FormatMoney(-507)") == "|cffff2020-5s 07c|r")


# --- Best Crafts ------------------------------------------------------------------------
# Blacksmithing: cuirass (7 bronze), shoulders (5 bronze), copper vest (8 copper bars).
SHOULDERS = """{ recipeID = 3328, itemLink = "item:2865", quantityMin = 1, reagents = { { itemID = 2841, quantity = 5 } } }"""
VEST = """{ recipeID = 2671, itemLink = "item:2867", quantityMin = 1, reagents = { { itemID = 2840, quantity = 8 } } }"""
run, ev = route_client()
run('__stub.items["item:2866"].sellPrice = 600')
run('__stub.items["item:2865"] = { name = "Rough Bronze Shoulders", cached = true, sellPrice = 400 }')
run('__stub.items["item:2867"] = { name = "Copper Chain Vest", cached = true, sellPrice = 150 }')
run('__stub.auctionPrices[2865] = 700; __stub.auctionPrices[2867] = 300')
run('__stub.OpenProfession(186, "Mining", %s)' % MINING)
run('__stub.OpenProfession(164, "Blacksmithing", { %s, %s, %s })' % (CUIRASS, SHOULDERS, VEST))
run('__stub.SetRecipe(%s)' % CUIRASS)
TITLEBTN = "VendorProfitProfessionsButton"
B = "VendorProfit.BestPanel.Frame()"
check("no Best Crafts button on the recipe", ev("AuctionatorCraftingInfoProfessionsFrame.VendorProfitBestButton") is None)
check("Vendor Profit button in the professions title bar, left of the close button (and TSM's)",
      ev(TITLEBTN + ".__text") == "Vendor Profit" and ev(TITLEBTN + ".__point[2] == ProfessionsFrame")
      and ev(TITLEBTN + ".__point[1]") == "TOPRIGHT" and ev(TITLEBTN + ".__point[4]") == -111)
check("...above the window's border art", ev(TITLEBTN + ":GetFrameLevel()") >= 502)
run(TITLEBTN + ":Click()")
check("opens the Vendor Profit window on its Best Crafts tab",
      ev("VendorProfit.Panel.IsShown()") and ev("VendorProfit.Panel.ActiveTab()") == "best"
      and ev("VendorProfit.BestPanel.IsShown()") and ev("VendorProfitPanel.__title") == "Vendor Profit"
      and ev(B + ".heading:GetText()") == "Best Crafts: Blacksmithing")
check("one window: Best Crafts is a page in it", ev(B + ":GetParent() == VendorProfitPanel") and ev("VendorProfitBestCrafts") is None)
check("side tabs on the window's right edge, Best Crafts checked",
      ev("VendorProfitPanel.tabs.best:GetChecked()") and not ev("VendorProfitPanel.tabs.shopping:GetChecked()")
      and ev("VendorProfitPanel.tabs.shopping.__point[3]") == "TOPRIGHT"
      and ev("VendorProfitPanel.tabs.shopping.label") == "Shopping List" and ev("VendorProfitPanel.tabs.best.label") == "Best Crafts")
check("only the Best Crafts page shows", ev(B + ":IsShown()") and not ev("VendorProfitPanel.tabs ~= nil and VendorProfit.Panel.FindButton('Remove')"))
run('VendorProfit.Order.Clear()')
run("VendorProfitPanel.tabs.shopping:Click()")
check("window above the professions window and the like, raised when clicked",
      ev("VendorProfitPanel.__strata") == "HIGH" and ev("VendorProfitPanel.__toplevel"))
check("short page: the window is still tall enough for both side tabs",
      ev("VendorProfitPanel:GetHeight()") >= ev("VendorProfitPanel.tabs.best.__point[5] * -1") + 32)
check("Shopping List back to its own width", ev("VendorProfitPanel:GetWidth()") == 380)
check("Shopping List tab switches pages", ev("VendorProfit.Panel.ActiveTab()") == "shopping" and not ev(B + ":IsShown()")
      and ev("VendorProfitPanel.tabs.shopping:GetChecked()") and not ev("VendorProfit.BestPanel.IsShown()"))
run(TITLEBTN + ":Click()")
check("title button on another tab: switches to Best Crafts", ev("VendorProfit.Panel.ActiveTab()") == "best" and ev("VendorProfit.Panel.IsShown()"))
run(TITLEBTN + ":Click()")
check("...and again: closes the window", not ev("VendorProfit.Panel.IsShown()"))
run(TITLEBTN + ":Click()")
best = lambda: list(ev("VendorProfit.BestPanel.Lines()").values())
ranked = best()
check("vendor tab first, ranked: cuirass 600 - 438, shoulders 400 - 313, then the losing vest in red",
      ev("VendorProfit.BestPanel.Tab()") == "vendor" and ranked[:2] == [
          "1. |Ticon2866:0|t Rough Bronze Cuirass | |cffffffff1s 62c|r",
          "2. |Ticon2865:0|t Rough Bronze Shoulders | |cffffffff87c|r"]
      and len(ranked) == 3 and ranked[2].startswith("3. |Ticon2867:0|t Copper Chain Vest | |cffff2020-"))
# Every saved recipe is listed: ones with no profit to rank go last, saying why.
HELM = """{ recipeID = 9101, itemLink = "item:2901", quantityMin = 1, reagents = { { itemID = 7777, quantity = 1 } } }"""
RING = """{ recipeID = 9102, itemLink = "item:2902", quantityMin = 1, reagents = { { itemID = 2841, quantity = 1 } } }"""
run('__stub.items["item:2901"] = { name = "Mystery Helm", cached = true, sellPrice = 900 }')
run('__stub.items["item:2902"] = { name = "Plain Ring", cached = true, sellPrice = 0 }')
run('__stub.items["item:7777"] = { name = "Strange Ore", cached = true }')
run('__stub.OpenProfession(164, "Blacksmithing", { %s, %s, %s, %s, %s }); __stub.Advance(1)' % (CUIRASS, SHOULDERS, VEST, HELM, RING))
every = best()
check("all recipes listed, not just the top 10: priced ones ranked, then the rest unnumbered",
      len(every) == 5 and every[0].startswith("1. ") and every[2].startswith("3. ")
      and every[3] == "|cff808080-  |r|Ticon2901:0|t Mystery Helm | |cff808080no price: Strange Ore|r"
      and every[4] == "|cff808080-  |r|Ticon2902:0|t Plain Ring | |cff808080no vendor price|r")
check("investment column: what one craft's items cost along the cheapest route",
      ev("VendorProfit.BestPanel.Row(1).investment:GetText()") == "|cffffffff4s 38c|r"
      and ev("VendorProfit.BestPanel.Row(2).investment:GetText()") == "|cffffffff3s 13c|r"
      and ev(B + ".investmentHeading.label") == "Investment" and ev(B + ".profitHeading.label") == "Profit")
check("ROI column: profit as a share of the investment, losses in red",
      ev("VendorProfit.BestPanel.Row(1).roi:GetText()") == "37%" and ev("VendorProfit.BestPanel.Row(2).roi:GetText()") == "28%"
      and ev("VendorProfit.BestPanel.Row(3).roi:GetText()").startswith("|cffff2020-"))
check("+ to queue, a magnifying glass to show", ev("VendorProfit.BestPanel.Row(1).queue.__text") == "+"
      and ev("VendorProfit.BestPanel.Row(1).show.icon.__texture") == "Interface\\Common\\UI-Searchbox-Icon"
      and ev("VendorProfit.BestPanel.Row(1).queue:GetWidth()") == 22)
check("sorted by profit, highest first, by default: its heading marked",
      ev("VendorProfit.BestPanel.Sort().key") == "profit" and "Arrow-Down" in ev(B + ".profitHeading.text:GetText()")
      and "Arrow" not in ev(B + ".investmentHeading.text:GetText()"))
run(B + ".investmentHeading:Click()")
order = lambda: [l.split(" | ")[0] for l in best()]
check("click Investment: biggest investment first; unpriced stay last",
      [o.split(" ")[-1] for o in order()[:3]] == ["Cuirass", "Vest", "Shoulders"] and order()[3].startswith("|cff808080-")
      and order()[0].startswith("1. "))
run(B + ".investmentHeading:Click()")
check("click again: reversed", [o.split(" ")[-1] for o in order()[:3]] == ["Shoulders", "Vest", "Cuirass"]
      and "Arrow-Up" in ev(B + ".investmentHeading.text:GetText()"))
run(B + ".nameHeading:Click()")
check("Recipe: A to Z first", [o.split("|t ")[-1] for o in order()[:3]] == ["Copper Chain Vest", "Rough Bronze Cuirass", "Rough Bronze Shoulders"])
run(B + ".roiHeading:Click()")
check("ROI: highest first", [o.split(" ")[-1] for o in order()[:3]] == ["Cuirass", "Shoulders", "Vest"])
check("the sort is saved", ev("VendorProfitCharDB.bestSort.key") == "roi")
run(B + ".profitHeading:Click()")
check("no investment where a reagent has no price; shown where only the sale price is missing",
      ev("VendorProfit.BestPanel.Row(4).investment:GetText()") == "" and ev("VendorProfit.BestPanel.Row(5).investment:GetText()") != "")
check("Best Crafts is wider than the Shopping List, for the columns", ev("VendorProfitPanel:GetWidth()") == 480)
check("unpriced ones can still be queued and shown", ev("VendorProfit.BestPanel.Row(4).queue:IsShown()") and ev("VendorProfit.BestPanel.Row(4).show:IsShown()"))
check("the list scrolls: a scroll frame holding the rows", ev(B + ".scroll.__scrollChild == " + B + ".list")
      and ev(B + ".scroll:GetHeight()") == 5 * 22 and ev(B + ".list:GetHeight()") == 5 * 22)
run(B + '.scroll:SetVerticalScroll(40)')
run(B + '.tabs.auction:Click()')
check("auction tab: no auction price for the ring; scrolled back to the top", best()[4].endswith("no auction price|r")
      and ev(B + ".scroll:GetVerticalScroll()") == 0)
run(B + '.tabs.vendor:Click()')
# Many recipes: the list shows 14 at a time.
many = ", ".join('{ recipeID = %d, itemLink = "item:2866", quantityMin = 1, reagents = { { itemID = 2841, quantity = 7 } } }' % (20000 + i) for i in range(20))
run('__stub.OpenProfession(164, "Blacksmithing", { %s }); __stub.Advance(1)' % many)
check("20 recipes: all there, 14 rows tall, the rest scrolls", len(best()) == 20
      and ev(B + ".scroll:GetHeight()") == 14 * 22 and ev(B + ".list:GetHeight()") == 20 * 22)
run('__stub.OpenProfession(164, "Blacksmithing", { %s, %s, %s }); __stub.Advance(1)' % (CUIRASS, SHOULDERS, VEST))
check("vendor tab lit", ev(B + ".tabs.vendor.__lit") and not ev(B + ".tabs.auction.__lit"))
run(B + ".tabs.auction:Click()")
check("auction tab: after the cut, 1235 - 438 and 665 - 313",
      best()[:2] == ["1. |Ticon2866:0|t Rough Bronze Cuirass | |cffffffff7s 97c|r",
                     "2. |Ticon2865:0|t Rough Bronze Shoulders | |cffffffff3s 52c|r"])
run(B + ".tabs.vendor:Click()")
check("says prices are Auctionator's", "Prices from Auctionator's last scan." in ev(B + ".status:GetText()"))
check("scan off away from the auction house", not ev(B + ".scan:IsEnabled()")
      and ev(B + ".scan.tooltip") == "Open the auction house to look up live prices.")

# Show and Queue.
run("__stub.professionsTab = 2; VendorProfit.BestPanel.Row(2).show:Click()")
check("Show selects the recipe in the professions window directly, on its recipes tab, without asking the server",
      ev("__stub.selectedRecipe") == 3328 and ev("__stub.professionsTab") == 1 and ev("__stub.openedRecipe") is None)
run("ProfessionsFrame.CraftingPage.SelectRecipe = nil; VendorProfit.BestPanel.Row(2).show:Click()")
check("...falling back to opening it through the game", ev("__stub.openedRecipe") == 3328)
run("function ProfessionsFrame.CraftingPage:SelectRecipe(info) __stub.selectedRecipe = info.recipeID end; __stub.openedRecipe = nil")
run("VendorProfit.BestPanel.Row(1).queue:Click()")
check("Queue adds one craft to the shopping order",
      ev("VendorProfit.Order.Entries()[1].recipeID") == 2670 and ev("VendorProfit.Order.Entries()[1].crafts") == 1
      and ev("VendorProfit.Order.Entries()[1].profession") == "Blacksmithing")
check("...and stays on Best Crafts", ev("VendorProfit.BestPanel.IsShown()"))
run("VendorProfit.Order.Clear()")

# Every unique item across the profession's trees.
items = list(ev("VendorProfit.BestCrafts.Items(164)").values())
check("unique items of every recipe's tree, merged",
      items == [CUIRASS_ID, BRONZE_BAR, COPPER_BAR, TIN_BAR, COPPER_ORE, TIN_ORE, 2867, 2865])

# Scan at the auction house: bronze bars listed at 40c (cheaper than smelting).
run('''
    __stub.ah.listings[2841] = { { unitPrice = 40, quantity = 50 }, { unitPrice = 45, quantity = 50 } }
    __stub.ah.listings[2840] = { { unitPrice = 70, quantity = 50 } }
    __stub.ah.listings[3576] = { { unitPrice = 75, quantity = 50 } }
    __stub.ah.listings[2770] = { { unitPrice = 50, quantity = 50 } }
    __stub.ah.listings[2866] = { { unitPrice = 1300, quantity = 3 } }
    __stub.items["item:2865"].bind = 1
    VendorProfit.BestCrafts.BATCH = 3
''')
run('__stub.OpenAH()')
check("scan on at the auction house", ev("" + B + ".scan:IsEnabled()"))
run("" + B + ".scan:Click()")
check("scanning", ev("VendorProfit.BestCrafts.IsScanning()") and ev("" + B + ".scan.__text") == "Scanning...")
run('__stub.Advance(2)')
lookups = [list(x.values()) for x in ev("__stub.ah.itemKeySearches").values()]
check("looked up in batches, not one search per item", lookups == [[2866, 2841, 2840], [3576, 2770, 2771], [2867]])
check("bind-on-pickup items not looked up", 2865 not in sum(lookups, []))
check("no per-item searches", ev("#__stub.ah.searches") == 0)
check("done", not ev("VendorProfit.BestCrafts.IsScanning()")
      and "Live prices from" in ev("" + B + ".status:GetText()")
      and "Live prices updated." in ev("" + B + ".status:GetText()"))
check("re-ranked with live prices: bronze bars at 40c, so cuirass 600 - 280 and shoulders 400 - 200",
      best()[:2] == ["1. |Ticon2866:0|t Rough Bronze Cuirass | |cffffffff3s 20c|r",
                 "2. |Ticon2865:0|t Rough Bronze Shoulders | |cffffffff2s|r"])
check("items with nothing listed have no auction price now", ev("select(2, VendorProfit.BestCrafts.Prices(2771))") is None)

# Results that aren't ours are ignored; no answer times out; closing the AH stops it.
run('__stub.ah.dropBrowse = true; ' + B + '.scan:Click(); __stub.Advance(1)')
run('__stub.ah.browseResults = { { itemKey = { itemID = 99999 }, minPrice = 1, totalQuantity = 1 } }; __stub.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")')
check("someone else's browse results ignored", ev("VendorProfit.BestCrafts.IsScanning()"))
run('__stub.Advance(16)')
check("no answer: stops and says so", not ev("VendorProfit.BestCrafts.IsScanning()")
      and "didn't answer" in ev("" + B + ".status:GetText()"))
run(B + '.scan:Click(); __stub.Advance(1); __stub.CloseAH()')
check("closing the auction house stops a scan", not ev("VendorProfit.BestCrafts.IsScanning()")
      and "closed before the scan finished" in ev("" + B + ".status:GetText()"))
run('__stub.ah.dropBrowse = false')

# At the auction house with something queued, the window stays on Best Crafts,
# and closing the auction house leaves it open.
run('VendorProfit.Order.Clear()')
run('__stub.CloseAH()')
check("open away from the auction house on Best Crafts", ev("VendorProfit.BestPanel.IsShown()"))
run('VendorProfit.BestPanel.Row(1).queue:Click(); __stub.OpenAH()')
check("auction house opens with an order: stays on Best Crafts", ev("VendorProfit.Panel.ActiveTab()") == "best" and ev("VendorProfit.Panel.IsShown()"))
run('__stub.CloseAH()')
check("auction house closes: Best Crafts stays open", ev("VendorProfit.BestPanel.IsShown()"))
run('VendorProfit.Panel.Hide(); __stub.OpenAH()')
check("window closed, auction house opens with an order: Shopping List", ev("VendorProfit.Panel.ActiveTab()") == "shopping" and ev("VendorProfit.Panel.IsShown()"))
run('__stub.CloseAH()')
check("...and stays open when it closes", ev("VendorProfit.Panel.IsShown()"))
run('VendorProfit.Order.Clear(); VendorProfit.Panel.Show("best")')

# Closing the professions window leaves it open; /vprofit best toggles it.
run('__stub.CloseProfession()')
check("stays open when the professions window closes", ev("VendorProfit.BestPanel.IsShown()"))
check("...still listing the last profession's best crafts", len(best()) == 3)
run('__stub.openedRecipe = nil; VendorProfit.BestPanel.Row(1).show:Click()')
check("Show off with the professions window closed, saying to open it", ev("__stub.openedRecipe") is None and ev("__stub.selectedRecipe") == 3328
      and not ev("VendorProfit.BestPanel.Row(1).show:IsEnabled()") and ev("VendorProfit.BestPanel.Row(1).show.icon.__desaturated"))
run('VendorProfit.BestPanel.Row(1).show:GetScript("OnEnter")(VendorProfit.BestPanel.Row(1).show)')
check("...in its tooltip", ev("GameTooltip.lines[1].left") == "Open Blacksmithing to see this recipe.")
check("Queue still works", ev("VendorProfit.BestPanel.Row(1).queue:IsEnabled()"))
run('__stub.OpenProfession(164, "Blacksmithing", { %s, %s, %s })' % (CUIRASS, SHOULDERS, VEST))
check("reopening the profession turns Show back on", ev("VendorProfit.BestPanel.Row(1).show:IsEnabled()"))
run('SlashCmdList.VENDORPROFIT("best")')
check("/vprofit best closes it", not ev("VendorProfit.Panel.IsShown()"))
run('SlashCmdList.VENDORPROFIT("best")')
check("...and opens it", ev("VendorProfit.BestPanel.IsShown()"))
run('__stub.tradeSkill.linked = true; VendorProfit.BestPanel.Refresh()')
check("no profession of yours open: says to open one", best() == []
      and "Open one of your professions" in ev("" + B + ".status:GetText()"))
run('__stub.tradeSkill.linked = false')
check("no errors from Best Crafts", ev("#__stub.errors") == 0)

print()
failed = [label for label, ok in results if not ok]
print("%d passed, %d failed" % (len(results) - len(failed), len(failed)))
sys.exit(1 if failed else 0)
