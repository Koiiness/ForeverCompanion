-- Bags: inventory and bank snapshots for every character, item search,
-- and selling at merchants.
local _, ns = ...
local C = ns.C
local B = {}
ns.Bags = B

local function scan(bagIDs)
    local out = {}
    for _, bag in ipairs(bagIDs) do
        for slot = 1, C.NumSlots(bag) do
            local info = C.SlotInfo(bag, slot)
            if info and info.id then
                info.bag, info.slot = bag, slot
                -- Item details not loaded yet: the link has no name ("[]"). Ask the
                -- game for it and take another snapshot when it arrives.
                if not info.link or info.link:find("%[%]") then
                    C.RequestLoad(info.id)
                    B.needsRescan = true
                    local better = select(2, C.GetItemInfo(info.id))
                    if better then info.link = better end
                end
                out[#out + 1] = info
            end
        end
    end
    return out
end

function B.SnapshotBags()
    if not ns.char then return end
    ns.char.bags = scan(C.BagIDs())
    ns.char.money = GetMoney()
    ns:Fire("BAGS_CHANGED")
end

local bankOpen = false
function B.SnapshotBank()
    if not ns.char or not bankOpen then return end
    ns.char.bank = scan(C.BankBagIDs())
    ns.char.bankTime = time()
    ns.char.bankGuid = UnitGUID("player")
    ns:Fire("BAGS_CHANGED")
end

ns:Listen("READY", function() ns:Debounce("bags", 2, B.SnapshotBags) end)
ns:On("BAG_UPDATE_DELAYED", function() ns:Debounce("bags", 0.5, B.SnapshotBags) end)
ns:On("BAG_UPDATE", function() ns:Debounce("bags", 1, B.SnapshotBags) end)
ns:On("PLAYER_MONEY", function() if ns.char then ns.char.money = GetMoney() end end)
ns:On("BANKFRAME_OPENED", function() bankOpen = true ns:Debounce("bank", 0.5, B.SnapshotBank) end)
ns:On("PLAYERBANKSLOTS_CHANGED", function() ns:Debounce("bank", 0.5, B.SnapshotBank) end)
ns:On("BANKFRAME_CLOSED", function() B.SnapshotBank() bankOpen = false end)

----------------------------------------------------------------------
-- Search across all characters
----------------------------------------------------------------------
function B.Find(query)
    query = query:lower()
    local results = {}
    for key, char in pairs(ns.db.chars) do
        for _, where in ipairs({ "bags", "bank" }) do
            for _, item in ipairs(char[where] or {}) do
                local name = item.link and item.link:match("%[(.-)%]")
                if name and name:lower():find(query, 1, true) then
                    local r = results[item.id]
                    if not r then r = { link = item.link, where = {} } results[item.id] = r end
                    local k = ns.CharLabel(char, key) .. " (" .. where .. ")"
                    r.where[k] = (r.where[k] or 0) + (item.count or 1)
                end
            end
        end
    end
    return results
end

ns:Command("find", "<name> find an item in bags and banks of all your characters", function(arg)
    if not arg or arg == "" then ns:Print("usage: /fc find <item name>") return end
    local any = false
    for _, r in pairs(B.Find(arg)) do
        any = true
        local parts = {}
        for k, n in pairs(r.where) do parts[#parts + 1] = k .. " x" .. n end
        print("  " .. r.link .. ": " .. table.concat(parts, ", "))
    end
    if not any then ns:Print("nothing matching '" .. arg .. "'. (Banks update when you open them.)") end
end)

----------------------------------------------------------------------
-- Selling
----------------------------------------------------------------------
local merchantOpen = false
ns:On("MERCHANT_SHOW", function()
    merchantOpen = true
    if ns.db.settings.autoSellJunk then C_Timer.After(0.3, function() B.SellJunk(true) end) end
end)
ns:On("MERCHANT_CLOSED", function() merchantOpen = false end)

function B.MerchantOpen() return merchantOpen end

-- Sells items one at a time with a short delay so the server keeps up.
local function sellQueue(queue, total)
    local i = 0
    local function step()
        i = i + 1
        local item = queue[i]
        if not item or not merchantOpen then
            if i > 1 then ns:Print(string.format("sold %d item(s) for about %s.", i - 1, ns.Money(total))) end
            return
        end
        local cur = C.SlotInfo(item.bag, item.slot)
        if cur and cur.id == item.id then C.UseContainerItem(item.bag, item.slot) end
        C_Timer.After(0.15, step)
    end
    step()
end

-- Gray items only.
function B.SellJunk(quiet)
    if not merchantOpen then ns:Print("talk to a vendor first.") return end
    if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
        C_MerchantFrame.SellAllJunkItems()
        if not quiet then ns:Print("sold gray items.") end
        return
    end
    local queue, total = {}, 0
    for _, item in ipairs(scan(C.BagIDs())) do
        if item.quality == 0 and not item.noValue then
            queue[#queue + 1] = item
            total = total + ns.Prices.Vendor(item.id) * (item.count or 1)
        end
    end
    sellQueue(queue, total)
end

-- Everything the advisor marks "Vendor" (grays plus unwanted greens etc.).
function B.SellAdvised()
    if not merchantOpen then ns:Print("talk to a vendor first.") return end
    local queue, total = {}, 0
    for _, item in ipairs(scan(C.BagIDs())) do
        local adv = ns.Disposition.Evaluate(item)
        if adv and adv.action == "VENDOR" then
            queue[#queue + 1] = item
            total = total + adv.vendor
        end
    end
    if #queue == 0 then ns:Print("nothing to sell.") return end
    sellQueue(queue, total)
end

ns:Command("selljunk", "sell gray items (vendor window must be open)", function() B.SellJunk() end)

ns:On("GET_ITEM_INFO_RECEIVED", function()
    if B.needsRescan then
        B.needsRescan = false
        ns:Debounce("bags", 1, B.SnapshotBags)
    end
end)
