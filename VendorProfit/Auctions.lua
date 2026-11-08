-- Your own auctions: how many of each item you have up for auction.
--
-- The game only lists them at the auction house (C_AuctionHouse owned
-- auctions), so the counts are a snapshot, saved per character and taken
-- whenever the list comes in: when the auction house opens (we ask for it),
-- after you post or cancel (we ask again), and whenever the game's own
-- Auctions tab or another addon asks. Away from the auction house they're as
-- of your last visit: sales and expiries since then don't show until the next.

local ADDON_NAME, ns = ...
local VendorProfit = ns.VendorProfit

local Auctions = {}
VendorProfit.Auctions = Auctions

Auctions.QUERY_DELAY = 0.5 -- seconds: lets a post or cancel land first

local SORTS = { { sortOrder = 0, reverseSort = false } }
local ACTIVE = Enum and Enum.AuctionStatus and Enum.AuctionStatus.Active or 0

local listeners = {}
function Auctions.OnChange(fn)
    listeners[#listeners + 1] = fn
end
local function Changed()
    for _, fn in ipairs(listeners) do
        fn()
    end
end

local function DB()
    VendorProfitCharDB = VendorProfitCharDB or {}
    local db = VendorProfitCharDB
    if type(db.auctions) ~= "table" or type(db.auctions.counts) ~= "table" then
        db.auctions = { counts = {} }
    end
    return db.auctions
end

-- How many of an item you have up for auction (0 if none, or never seen).
function Auctions.Count(itemID)
    return DB().counts[itemID] or 0
end

-- When the counts were last taken, or nil if never.
function Auctions.Time()
    return DB().time
end

local function Read()
    local counts = {}
    for index = 1, C_AuctionHouse.GetNumOwnedAuctions() do
        local info = C_AuctionHouse.GetOwnedAuctionInfo(index)
        local itemID = info and info.itemKey and info.itemKey.itemID
        if itemID and info.status == ACTIVE then
            counts[itemID] = (counts[itemID] or 0) + (info.quantity or 1)
        end
    end
    local db = DB()
    db.counts = counts
    db.time = time()
    Changed()
end

local queryPending = false
local function Query()
    if queryPending then
        return
    end
    queryPending = true
    C_Timer.After(Auctions.QUERY_DELAY, function()
        queryPending = false
        if AuctionHouseFrame and AuctionHouseFrame:IsShown() and C_AuctionHouse.QueryOwnedAuctions then
            C_AuctionHouse.QueryOwnedAuctions(SORTS)
        end
    end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "OWNED_AUCTIONS_UPDATED", "AUCTION_HOUSE_AUCTION_CREATED",
    "AUCTION_CANCELED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "OWNED_AUCTIONS_UPDATED" then
        xpcall(Read, geterrorhandler())
    else
        Query()
    end
end)
