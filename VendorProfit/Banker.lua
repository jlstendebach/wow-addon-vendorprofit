-- Taking exactly what the order needs out of the bank, from the shopping
-- panel's "From your bank" section, while the bank is open.
--
-- Moves work the way TradeSkillMaster does them: split the amount needed off
-- a bank slot onto the cursor, drop it into an empty bag slot, and wait for
-- the slots to unlock before the next move. One move at a time.

local _, ns = ...
local VendorProfit = ns.VendorProfit
local L = VendorProfit.L

local Banker = {}
VendorProfit.Banker = Banker

Banker.MOVE_INTERVAL = 0.2   -- seconds between moves
Banker.MOVE_TIMEOUT = 5      -- give up on a move that never finishes

local bankOpen = false
local moving              -- { queue = { move, ... }, current = move, reserved = { ["bag:slot"] = true }, someMissing }
local message, messageIsError

local listeners = {}
function Banker.OnChange(fn)
    listeners[#listeners + 1] = fn
end
local function Changed()
    for _, fn in ipairs(listeners) do
        fn()
    end
end

function Banker.IsBankOpen()
    return bankOpen
end

function Banker.IsMoving()
    return moving ~= nil
end

function Banker.Message()
    return message, messageIsError
end

-- Containers ---------------------------------------------------------------------

-- Your bags that take any item (not the reagent bag, which only takes
-- reagents).
local function BagIDs()
    local ids = {}
    for bag = 0, NUM_BAG_SLOTS do
        ids[#ids + 1] = bag
    end
    return ids
end

-- The bank's containers: the bank tabs after your bags, plus the old bank
-- and reagent bank containers where they exist.
local function BankIDs()
    local ids = {}
    local constants = Constants and Constants.InventoryConstants
    local first = NUM_BAG_SLOTS + ((constants and constants.NumReagentBagSlots) or 0) + 1
    local count = (constants and constants.NumCharacterBankSlots) or 0
    for bag = first, first + count - 1 do
        ids[#ids + 1] = bag
    end
    for _, bag in ipairs({ BANK_CONTAINER, REAGENTBANK_CONTAINER }) do
        if bag then
            ids[#ids + 1] = bag
        end
    end
    return ids
end

local function SlotInfo(bag, slot)
    return C_Container.GetContainerItemInfo(bag, slot)
end

local function FindEmptyBagSlot(reserved)
    for _, bag in ipairs(BagIDs()) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local key = bag .. ":" .. slot
            if SlotInfo(bag, slot) == nil and not reserved[key] then
                return bag, slot, key
            end
        end
    end
end

-- Moves to take items = { { itemID, quantity }, ... } out of the bank:
-- { bag, slot, itemID, quantity }, smallest stacks first so fewer slots end
-- up split. Also returns how many of each couldn't be found.
function Banker.PlanMoves(items)
    local stacks = {}
    for _, bag in ipairs(BankIDs()) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = SlotInfo(bag, slot)
            if info and info.itemID then
                local list = stacks[info.itemID] or {}
                list[#list + 1] = { bag = bag, slot = slot, count = info.stackCount or 1 }
                stacks[info.itemID] = list
            end
        end
    end

    local moves, missing = {}, {}
    for _, item in ipairs(items) do
        local left = item.quantity
        local list = stacks[item.itemID] or {}
        table.sort(list, function(a, b) return a.count < b.count end)
        for _, stack in ipairs(list) do
            if left <= 0 then
                break
            end
            local take = math.min(stack.count, left)
            moves[#moves + 1] = { bag = stack.bag, slot = stack.slot, itemID = item.itemID, quantity = take }
            left = left - take
        end
        if left > 0 then
            missing[item.itemID] = left
        end
    end
    return moves, missing
end

-- Moving -------------------------------------------------------------------------

local function Finish(text, isError)
    moving = nil
    message, messageIsError = text, isError
    Changed()
end

local Step

-- Waits for the last move's slots to unlock, then does the next.
local function WaitThenStep(started)
    C_Timer.After(Banker.MOVE_INTERVAL, function()
        if moving == nil then
            return
        end
        local current = moving.current
        if current then
            local source = SlotInfo(current.bag, current.slot)
            local target = SlotInfo(current.toBag, current.toSlot)
            local locked = (source and source.isLocked) or (target and target.isLocked)
            if locked then
                if GetTime() - started > Banker.MOVE_TIMEOUT then
                    Finish(L.BANK_MOVE_STUCK, true)
                else
                    WaitThenStep(started)
                end
                return
            end
        end
        Step()
    end)
end

function Step()
    if moving == nil then
        return
    end
    if not bankOpen then
        Finish(L.BANK_CLOSED_MID, true)
        return
    end
    local move = table.remove(moving.queue, 1)
    if move == nil then
        if moving.someMissing then
            Finish(L.BANK_SOME_MISSING, true)
        else
            Finish(L.BANK_DONE)
        end
        return
    end
    local info = SlotInfo(move.bag, move.slot)
    if info == nil or info.itemID ~= move.itemID then
        -- The bank changed under us: plan again from what's there now.
        Finish(L.BANK_CHANGED, true)
        return
    end
    local bag, slot, key = FindEmptyBagSlot(moving.reserved)
    if bag == nil then
        Finish(L.BAGS_FULL, true)
        return
    end
    moving.reserved[key] = true
    move.toBag, move.toSlot = bag, slot
    moving.current = move

    ClearCursor()
    C_Container.SplitContainerItem(move.bag, move.slot, math.min(move.quantity, info.stackCount or move.quantity))
    if GetCursorInfo() == "item" then
        C_Container.PickupContainerItem(bag, slot)
    end
    ClearCursor()
    WaitThenStep(GetTime())
end

-- Takes items = { { itemID, quantity }, ... } out of the bank.
function Banker.Withdraw(items)
    if not bankOpen or moving ~= nil then
        return
    end
    local moves, missing = Banker.PlanMoves(items)
    if #moves == 0 then
        message, messageIsError = L.BANK_NOTHING_FOUND, true
        Changed()
        return
    end
    message = nil
    moving = { queue = moves, reserved = {}, someMissing = next(missing) ~= nil }
    Changed()
    Step()
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    bankOpen = event == "BANKFRAME_OPENED"
    if not bankOpen then
        message = nil
    end
    Changed()
end)
