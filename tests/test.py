"""Loads VendorProfit into a stubbed WoW client + Auctionator (real Lua 5.1)
and checks the Vendor Profit line.

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
check("files loaded in toc order", FILES == ["VendorProfit.lua"])
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

print()
failed = [label for label, ok in results if not ok]
print("%d passed, %d failed" % (len(results) - len(failed), len(failed)))
sys.exit(1 if failed else 0)
