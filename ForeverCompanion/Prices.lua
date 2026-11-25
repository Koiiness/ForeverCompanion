-- Prices: market value per item.
--   1. TradeSkillMaster or Auctionator, when loaded.
--   2. Otherwise this addon's own data: a full AH scan runs automatically each
--      time you open the auction house (the server allows one per 15 minutes),
--      and anything you browse is recorded too. Each item keeps one price per
--      day for 14 days; the market value is the median of those days, so one
--      odd listing doesn't swing it.
local ADDON, ns = ...
local C = ns.C
local P = {}
ns.Prices = P

local DAY = 86400
local KEEP_DAYS = 14
local SCAN_COOLDOWN = 15 * 60 + 5
local STALE = 3 * DAY

local function today() return math.floor(time() / DAY) end

local function median(t)
    local v = {}
    for _, p in pairs(t) do v[#v + 1] = p end
    if #v == 0 then return end
    table.sort(v)
    local mid = math.floor((#v + 1) / 2)
    if #v % 2 == 1 then return v[mid] end
    return (v[mid] + v[mid + 1]) / 2
end

-- Returns copper per unit, source name, age in seconds (own data only).
function P.Market(itemID)
    if not itemID then return end
    if TSM_API and TSM_API.GetCustomPriceValue then
        local ok, v = pcall(TSM_API.GetCustomPriceValue, "dbmarket", "i:" .. itemID)
        if ok and v and v > 0 then return v, "TSM" end
    end
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.GetAuctionPriceByItemID then
        local ok, v = pcall(api.GetAuctionPriceByItemID, ADDON, itemID)
        if ok and v and v > 0 then return v, "Auctionator" end
    end
    local rec = ns.db and ns.db.prices[itemID]
    if rec then
        local age = time() - (rec.t or 0)
        local value = (rec.h and median(rec.h)) or rec.p
        return value, (age > STALE) and "old scan" or "scan", age
    end
end

function P.Vendor(itemID)
    return select(11, C.GetItemInfo(itemID)) or 0
end

----------------------------------------------------------------------
-- Recipe items (patterns, plans, formulas...) by name, so a craftable
-- upgrade can show what its pattern costs on the AH.
----------------------------------------------------------------------
local RECIPE_PREFIXES = { "Pattern: ", "Plans: ", "Formula: ", "Recipe: ", "Schematic: ", "Manual: ", "Design: ", "Technique: " }

function P.NoteRecipeItem(name, itemID)
    for _, pre in ipairs(RECIPE_PREFIXES) do
        if name:sub(1, #pre) == pre then
            ns.db.recipeItems = ns.db.recipeItems or {}
            ns.db.recipeItems[name:sub(#pre + 1):lower()] = itemID
            return
        end
    end
end

-- Returns the pattern's itemID and market price (either may be nil).
function P.PatternFor(recipeName)
    if not recipeName then return end
    local map = ns.db.recipeItems or {}
    local id = map[recipeName:lower()]
    if not id and GetTime() - (P.lastNameSweep or -999) > 60 then
        -- Fall back to names of priced items already loaded (at most once a minute).
        P.lastNameSweep = GetTime()
        for itemID in pairs(ns.db.prices) do
            local n = C.GetItemInfo(itemID)
            if n then P.NoteRecipeItem(n, itemID) end
        end
        id = (ns.db.recipeItems or {})[recipeName:lower()]
    end
    if not id then return end
    return id, P.Market(id)
end

function P.SourceName()
    if TSM_API then return "TradeSkillMaster" end
    if Auctionator and Auctionator.API then return "Auctionator" end
    return "Forever Companion scans"
end

----------------------------------------------------------------------
-- Recording
----------------------------------------------------------------------
-- Sets today's price for an item. `replace` is used by full scans (the
-- whole market at once); browsing only ever lowers today's price.
local function record(itemID, unitPrice, replace)
    if not itemID or not unitPrice or unitPrice <= 0 then return end
    local prices = ns.db.prices
    local rec = prices[itemID]
    if not rec then rec = {} prices[itemID] = rec end
    rec.h = rec.h or {}
    local d = today()
    if replace or not rec.h[d] or unitPrice < rec.h[d] then rec.h[d] = unitPrice end
    rec.p, rec.t = rec.h[d], time()
    for day in pairs(rec.h) do
        if day < d - KEEP_DAYS then rec.h[day] = nil end
    end
end

ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    if not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then return end
    for _, r in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
        if r.itemKey and r.minPrice then record(r.itemKey.itemID, r.minPrice) end
    end
end)

ns:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, itemID)
    local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
    if info and info.unitPrice then record(itemID, info.unitPrice) end
end)

ns:On("ITEM_SEARCH_RESULTS_UPDATED", function(_, itemKey)
    if not itemKey then return end
    local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, 1)
    if info and info.buyoutAmount then record(itemKey.itemID, info.buyoutAmount) end
end)

-- Old-style AH list (fallback for clients without C_AuctionHouse).
ns:On("AUCTION_ITEM_LIST_UPDATE", function()
    if not (GetNumAuctionItems and GetAuctionItemInfo) then return end
    for i = 1, GetNumAuctionItems("list") do
        local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = GetAuctionItemInfo("list", i)
        if itemID and buyout and buyout > 0 and count and count > 0 then record(itemID, buyout / count) end
    end
end)

----------------------------------------------------------------------
-- Full scan
----------------------------------------------------------------------
local scanning = false
local scanButton

function P.ScanCooldown()
    local last = ns.db.lastFullScan or 0
    return math.max(0, SCAN_COOLDOWN - (time() - last))
end

local function updateButton()
    if not scanButton then return end
    local cd = P.ScanCooldown()
    if scanning then
        scanButton:SetText("Scanning...") scanButton:Disable()
    elseif cd > 0 then
        scanButton:SetText(string.format("Next scan %d:%02d", math.floor(cd / 60), cd % 60)) scanButton:Disable()
    else
        scanButton:SetText("Scan prices now") scanButton:Enable()
    end
end

function P.StartScan(auto)
    if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then
        if not auto then ns:Print("full scans aren't available on this client. Browsing the AH still records prices.") end
        return
    end
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        if not auto then ns:Print("open the auction house first.") end
        return
    end
    if scanning then return end
    local cd = P.ScanCooldown()
    if cd > 0 then
        if not auto then ns:Print(string.format("the server allows one full scan every 15 minutes. Try again in %d:%02d.", math.floor(cd / 60), cd % 60)) end
        return
    end
    local ok = pcall(C_AuctionHouse.ReplicateItems)
    if not ok then
        if auto then ns:Print("couldn't start the automatic scan. Click 'Scan prices now' on the auction house window.") end
        return
    end
    scanning = true
    ns.db.lastFullScan = time()
    updateButton()
    ns:Print("scanning auction prices. This takes a few seconds; keep the AH open.")
    -- Give up if the server never answers.
    C_Timer.After(60, function() if scanning then scanning = false updateButton() end end)
end

----------------------------------------------------------------------
-- Which auctions are worth keeping. The server sends every auction in a
-- full scan; only items that matter to you are stored.
----------------------------------------------------------------------
-- Recipe item subclass -> profession.
local RECIPE_PROF = { [1] = "Leatherworking", [2] = "Tailoring", [3] = "Engineering", [4] = "Blacksmithing",
                      [5] = "Cooking", [6] = "Alchemy", [7] = "First Aid", [8] = "Enchanting", [9] = "Fishing" }

local function instant(itemID)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not f then return end
    local _, _, _, equipLoc, _, classID, subclassID = f(itemID)
    return equipLoc, classID, subclassID
end

-- Items you own, craft or use, on any of your characters.
function P.RelevantSet()
    local set, names = {}, {}
    for _, char in pairs(ns.db.chars) do
        for _, where in ipairs({ "bags", "bank" }) do
            for _, it in ipairs(char[where] or {}) do if it.id then set[it.id] = true end end
        end
        for id in pairs(char.reagents or {}) do set[id] = true end
        for _, rec in pairs(char.recipes or {}) do
            for name, r in pairs(rec.list or {}) do
                if r.item then set[r.item] = true end
                for _, m in ipairs(r.mats or {}) do set[m.id] = true end
                if r.learned == false then names[name:lower()] = true end
            end
        end
    end
    for _, row in ipairs(ns.Data.Disenchant) do
        set[row[4][1]], set[row[5][1]] = true, true
        if row[6] then set[row[6]] = true end
    end
    set[ns.Data.NexusCrystal] = true
    local fills = {}
    for _, tier in pairs(ns.Crates and ns.Crates.Fills or {}) do
        for _, list in pairs(tier) do for _, f in ipairs(list) do fills[f[1]] = true end end
    end
    return set, names, fills
end

-- itemID, auction name, usable-by-you flag, required level.
local function relevant(ctx, itemID, name, usable, reqLevel, quality)
    if ctx.set[itemID] then return true end
    if name then
        if ctx.fills[name] or name:find("^Waylaid Crate") then return true end
    end
    local equipLoc, classID, subclassID = instant(itemID)
    if (classID == 2 or classID == 4) and equipLoc and ns.Data.EquipSlots[equipLoc] then
        -- Gear you can wear, near your level, green or better.
        local lvl = ctx.level
        return usable and (quality or 0) >= 2 and (reqLevel or 0) <= lvl + 5 and (reqLevel or 0) >= lvl - 12
    end
    if classID == 9 then
        local prof = RECIPE_PROF[subclassID]
        if prof and ctx.profs[prof] then
            -- Patterns for recipes you haven't learned.
            local short = name and name:match("^[^:]+: (.+)$")
            return short == nil or ctx.names[short:lower()] == true
        end
    end
    return false
end

local function scanContext()
    local set, names, fills = P.RelevantSet()
    local profs = {}
    for _, char in pairs(ns.db.chars) do
        for _, p in ipairs(char.professions or {}) do profs[p.name] = true end
    end
    return { set = set, names = names, fills = fills, profs = profs, level = UnitLevel("player") }
end

ns:On("REPLICATE_ITEM_LIST_UPDATE", function()
    if not scanning then return end
    scanning = false
    local ctx = scanContext()
    -- Per item, take a low-but-not-lowest price: the price at the cheapest
    -- 15% of listed units. This ignores a single underpriced auction.
    local byItem = {}
    local n = C_AuctionHouse.GetNumReplicateItems()
    for i = 0, n - 1 do
        local name, _, count, quality, usable, level, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
        local keep = itemID and (byItem[itemID] or relevant(ctx, itemID, name, usable, level, quality))
        if keep and name then P.NoteRecipeItem(name, itemID) end
        if keep and buyout and buyout > 0 and count and count > 0 then
            local list = byItem[itemID]
            if not list then list = {} byItem[itemID] = list end
            list[#list + 1] = { buyout / count, count }
        end
    end
    local items = 0
    for itemID, list in pairs(byItem) do
        table.sort(list, function(a, b) return a[1] < b[1] end)
        local total = 0
        for _, e in ipairs(list) do total = total + e[2] end
        local target, seen, price = math.max(1, total * 0.15), 0, list[1][1]
        for _, e in ipairs(list) do
            seen = seen + e[2]
            price = e[1]
            if seen >= target then break end
        end
        record(itemID, price, true)
        items = items + 1
    end
    ns:Print(string.format("price scan done: read %d auctions, kept prices for %d items that matter to you.", n, items))
    updateButton()
    ns:Fire("PRICES_CHANGED")
end)

local function ensureButton()
    if scanButton or not AuctionHouseFrame then return end
    scanButton = CreateFrame("Button", nil, AuctionHouseFrame, "UIPanelButtonTemplate")
    scanButton:SetSize(150, 22)
    scanButton:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", -30, -1)
    scanButton:SetScript("OnClick", function() P.StartScan(false) end)
    scanButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Forever Companion price scan")
        GameTooltip:AddLine("Reads every auction so bag advice knows what items sell for. The server allows one scan every 15 minutes.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    scanButton:SetScript("OnLeave", GameTooltip_Hide)
    -- Keep the countdown current while the AH is open.
    local elapsed = 0
    scanButton:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 1 then elapsed = 0 updateButton() end
    end)
end

-- Version 2 stores only relevant items; drop the old full-market data once.
ns:Listen("READY", function()
    if (ns.db.pricesVersion or 1) < 2 then
        ns.db.prices = {}
        ns.db.recipeItems = {}
        ns.db.lastFullScan = nil
        ns.db.pricesVersion = 2
    end
end)

ns:On("AUCTION_HOUSE_SHOW", function()
    C_Timer.After(0.5, function()
        ensureButton()
        updateButton()
        if ns.db.settings.autoScan and not TSM_API then P.StartScan(true) end
    end)
end)
ns:On("AUCTION_HOUSE_CLOSED", function() scanning = false ns:Fire("PRICES_CHANGED") end)

ns:Command("scan", "full AH price scan now (stand at the auctioneer)", function() P.StartScan(false) end)

ns:Command("autoscan", "toggle the automatic price scan when you open the AH", function()
    ns.db.settings.autoScan = not ns.db.settings.autoScan
    ns:Print("automatic AH scan " .. (ns.db.settings.autoScan and "on" or "off"))
end)

ns:Command("price", "<item link or ID> show vendor, AH and disenchant value", function(arg)
    local id = C.ItemID(arg) or tonumber(arg)
    if not id then ns:Print("shift-click an item into the command, e.g. /fc price [item]") return end
    local adv = ns.Disposition and ns.Disposition.Evaluate({ id = id, link = select(2, C.GetItemInfo(id)), count = 1 })
    if not adv then ns:Print("item info not loaded yet; try again in a second.") return end
    ns:Print(ns.Disposition.Describe(adv))
    for _, line in ipairs(ns.Disposition.OddsLines(adv)) do print("    " .. line) end
end)
