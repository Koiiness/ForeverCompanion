-- Disposition: what to do with an item. Compares vendor price, auction
-- value (after the AH cut) and expected disenchant value, and keeps
-- upgrades, quest items and reagents your recipes use.
local _, ns = ...
local C, D, P = ns.C, ns.Data, ns.Prices
local DS = {}
ns.Disposition = DS

DS.Labels = {
    KEEP = "|cff40c0ffKeep|r", VENDOR = "|cffc0c0c0Vendor|r",
    AH = "|cffffd700Auction|r", DE = "|cffb070ffDisenchant|r",
}

local function deRow(ilvl)
    for _, row in ipairs(D.Disenchant) do
        if ilvl >= row[1] and ilvl <= row[2] then return row end
    end
end

-- Possible disenchant results for one item.
-- Returns a list of { id, chance (0-1), min, max }, and the skill needed.
function DS.DEOutcomes(linkOrID)
    local _, _, quality, ilvl, _, _, _, _, equipLoc, _, _, classID = C.GetItemInfo(linkOrID)
    if not quality or quality < 2 or quality > 4 then return end
    if classID ~= 2 and classID ~= 4 then return end
    if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_TABARD" then return end
    local row = deRow(ilvl or 0)
    if not row then return end
    local skill, dust, essence, shard = row[3], row[4], row[5], row[6]
    shard = shard or D.Disenchant[2][6]
    if quality == 2 then
        local odds = (classID == 2) and D.DEOdds.weapon or D.DEOdds.armor
        local out = {
            { id = dust[1], chance = odds.dust, min = dust[2], max = dust[3] },
            { id = essence[1], chance = odds.essence, min = essence[2], max = essence[3] },
        }
        if row[6] then
            out[3] = { id = shard, chance = odds.shard, min = 1, max = 1 }
        else
            out[1].chance = out[1].chance + odds.shard
        end
        table.sort(out, function(a, b) return a.chance > b.chance end)
        return out, skill
    elseif quality == 3 then
        return { { id = shard, chance = 1, min = 1, max = 1 } }, skill + 25
    end
    if (ilvl or 0) >= 56 then
        return { { id = D.NexusCrystal, chance = 1, min = 1, max = 2 } }, skill + 50
    end
    return { { id = shard, chance = 1, min = 2, max = 4 } }, skill + 50
end

-- Expected disenchant value of one item.
-- Returns value (copper), skill needed, partial (some mats unpriced), outcomes.
function DS.DEValue(linkOrID)
    local outcomes, skill = DS.DEOutcomes(linkOrID)
    if not outcomes then return end
    local total, partial = 0, false
    for _, o in ipairs(outcomes) do
        o.price = P.Market(o.id)
        if o.price then
            total = total + o.price * (o.min + o.max) / 2 * o.chance
        else
            partial = true
        end
    end
    return total, skill, partial, outcomes
end

function DS.MatName(id)
    local name = C.GetItemInfo(id)
    if not name then C.RequestLoad(id) end
    return name or ("item " .. id)
end

-- Human-readable disenchant odds, one line per result.
function DS.OddsLines(a)
    local out = {}
    if not a or not a.deOutcomes then return out end
    for _, o in ipairs(a.deOutcomes) do
        local qty = (o.min == o.max) and tostring(o.min) or (o.min .. "-" .. o.max)
        out[#out + 1] = string.format("|cffffffff%3d%%|r  %sx %s  %s", math.floor(o.chance * 100 + 0.5), qty,
            DS.MatName(o.id), o.price and ("|cff909090" .. ns.Money(o.price) .. " each|r") or "|cff909090no price yet|r")
    end
    return out
end

-- Items you use rather than sell. Returns a reason, or nil.
-- Profession tools, by item ID and by exact name. Several are technically
-- weapons (Blacksmith Hammer is a mace, Mining Pick an axe), so they're
-- matched exactly rather than by item type.
local TOOL_IDS = {
    [5956] = "Blacksmithing", [2901] = "Mining", [7005] = "Skinning", [6219] = "Engineering",
    [10498] = "Engineering", [9149] = "Alchemy", [6256] = "Fishing", [6365] = "Fishing",
    [6366] = "Fishing", [6367] = "Fishing", [12225] = "Fishing", [19022] = "Fishing", [19970] = "Fishing",
    [6218] = "Enchanting", [6339] = "Enchanting", [11130] = "Enchanting", [11145] = "Enchanting",
    [16207] = "Enchanting", [6948] = "travel",
}
local TOOL_NAMES = {
    ["Blacksmith Hammer"] = "Blacksmithing", ["Mining Pick"] = "Mining", ["Skinning Knife"] = "Skinning",
    ["Arclight Spanner"] = "Engineering", ["Gyromatic Micro-Adjustor"] = "Engineering",
    ["Philosopher's Stone"] = "Alchemy", ["Hearthstone"] = "travel",
}
-- Name patterns for tool families (Forever may add new ones).
local TOOL_PATTERNS = {
    { "^Runed .* Rod$", "Enchanting" }, { "Fishing Pole$", "Fishing" }, { "Pickaxe$", "Mining" },
    { "Blacksmith Hammer$", "Blacksmithing" }, { "Mining Pick$", "Mining" }, { "Skinning Knife$", "Skinning" },
}
-- Trade goods subclass -> professions that use it.
local MATS = {
    [5] = { "Tailoring", "First Aid" }, [6] = { "Leatherworking" }, [7] = { "Blacksmithing", "Engineering" },
    [8] = { "Cooking" }, [9] = { "Alchemy" }, [10] = { "Alchemy", "Blacksmithing", "Leatherworking", "Tailoring", "Engineering" },
    [12] = { "Enchanting" }, [1] = { "Engineering" },
}
DS.ConsumableOutdated = 15  -- consumables this many levels below you are fair game to sell

function DS.ToolFor(itemID, name)
    local prof = (itemID and TOOL_IDS[itemID]) or (name and TOOL_NAMES[name])
    if not prof and name then
        for _, p in ipairs(TOOL_PATTERNS) do
            if name:find(p[1]) then prof = p[2] break end
        end
    end
    return prof
end

function DS.KeepReason(name, classID, subclassID, reqLevel, itemID)
    local tool = DS.ToolFor(itemID, name)
    if tool == "travel" then return "you need this" end
    if tool then return tool .. " tool" end
    if classID == 0 then  -- potions, elixirs, food, water, bandages, scrolls
        local level = UnitLevel("player")
        if (reqLevel or 0) > 0 and reqLevel < level - DS.ConsumableOutdated then return nil end
        return "consumable you can use"
    end
    if classID == 5 then return "class or spell reagent" end
    if classID == 7 and MATS[subclassID] then
        for _, prof in ipairs(MATS[subclassID]) do
            if ns.Professions.Rank(prof) then return "material for your " .. prof end
        end
    end
    return nil
end

-- item: { id, link, count, quality, bound, noValue }
function DS.Evaluate(item)
    local id = item.id or C.ItemID(item.link)
    if not id then return end
    local name, link, quality, _, reqLevel, _, _, _, equipLoc, _, sellPrice, classID, subclassID = C.GetItemInfo(item.link or id)
    if not name then C.RequestLoad(id) return end
    local s = ns.db.settings
    local count = item.count or 1
    local a = { id = id, link = item.link or link, count = count, quality = quality }
    a.vendor = item.noValue and 0 or (sellPrice or 0) * count

    local market, src, age = P.Market(id)
    if market then
        a.market, a.ahSource, a.ahAge = market * count, src, age
        if not item.bound then a.ah = market * count * (1 - s.ahCutPct / 100) end
    end

    local de, skill, partial, outcomes = DS.DEValue(a.link)
    if de then
        a.de, a.deSkill, a.dePartial, a.deOutcomes = de, skill, partial, outcomes
        local rank = ns.Professions.Rank("Enchanting")
        a.canDE = rank ~= nil and rank >= skill
    end

    local function decide(action, reason) a.action, a.reason = action, reason return a end

    if classID == 12 then return decide("KEEP", "quest item") end
    if ns.Crates then
        local action, why = ns.Crates.Advice(name, quality, a)
        if action then return decide(action, why) end
        local crate = ns.Crates.FillsHeldCrate(name)
        if crate then return decide("KEEP", "fills your " .. crate) end
    end
    if quality == 0 then return decide("VENDOR", "junk") end
    local keep = DS.KeepReason(name, classID, subclassID, reqLevel, id)
    if keep then return decide("KEEP", keep) end

    local isGear = equipLoc and equipLoc ~= "" and (classID == 2 or classID == 4)
    if isGear and ns.Gear then
        local cmp = ns.Gear.Compare(a.link)
        a.cmp = cmp
        if cmp and cmp.note == "equipped" then return decide("KEEP", "equipped") end
        if cmp and not cmp.unusable and cmp.delta > 0.5 then
            local when = cmp.note and (" (" .. cmp.note .. ")") or ""
            return decide("KEEP", string.format("upgrade +%.1f%s", cmp.delta, when))
        end
    end
    if ns.Professions.IsReagent(id) then return decide("KEEP", "used by your recipes") end

    -- Pick the best paying option. Listing on the AH has to be worth the
    -- trip: it must beat the next best option by at least ahMinGain.
    local best, bestVal = "VENDOR", a.vendor
    if a.canDE and a.de and a.de > bestVal then best, bestVal = "DE", a.de end
    if a.ah and a.ah >= bestVal + s.ahMinGain then best, bestVal = "AH", a.ah end

    if best == "VENDOR" and a.vendor == 0 and not a.ah and not a.de then
        return decide("KEEP", "no known value")
    end
    local reason
    if best == "VENDOR" and not market and not item.bound then reason = "no AH price yet" end
    if a.de and not a.canDE and a.de > bestVal then
        reason = (reason and reason .. "; " or "") .. "an enchanter could get ~" .. ns.Money(a.de)
    end
    return decide(best, reason)
end

function DS.Describe(a)
    local parts = { "Vendor " .. ns.Money(a.vendor) }
    if a.market then
        parts[#parts + 1] = "AH " .. (a.ah and ("~" .. ns.Money(a.ah) .. " net") or "bound") .. " (" .. a.ahSource .. ")"
    end
    if a.de then
        parts[#parts + 1] = "DE ~" .. ns.Money(a.de) .. (a.dePartial and "?" or "") ..
            (a.canDE and "" or (" (needs " .. a.deSkill .. " Enchanting)"))
    end
    local line = table.concat(parts, " | ")
    if a.action then
        line = line .. "  ->  " .. DS.Labels[a.action] .. (a.reason and (" (" .. a.reason .. ")") or "")
    end
    return line
end

-- Evaluate everything in your bags. Returns list, totals by action.
function DS.EvaluateBags()
    local list, totals = {}, { KEEP = 0, VENDOR = 0, AH = 0, DE = 0 }
    for _, item in ipairs(ns.char and ns.char.bags or {}) do
        local a = DS.Evaluate(item)
        if a then
            list[#list + 1] = a
            local v = (a.action == "AH" and a.ah) or (a.action == "DE" and a.de) or (a.action == "VENDOR" and a.vendor) or 0
            totals[a.action] = totals[a.action] + v
        end
    end
    local order = { AH = 1, DE = 2, VENDOR = 3, KEEP = 4 }
    table.sort(list, function(x, y)
        if order[x.action] ~= order[y.action] then return order[x.action] < order[y.action] end
        return (x.ah or x.de or x.vendor or 0) > (y.ah or y.de or y.vendor or 0)
    end)
    return list, totals
end

ns:Command("bags", "advice for every item in your bags: vendor, disenchant or auction", function()
    local list, totals = DS.EvaluateBags()
    for _, a in ipairs(list) do
        if a.action ~= "KEEP" then print("  " .. a.link .. (a.count > 1 and (" x" .. a.count) or "") .. "  " .. DS.Describe(a)) end
    end
    ns:Print(string.format("auction ~%s, disenchant ~%s, vendor %s.",
        ns.Money(totals.AH), ns.Money(totals.DE), ns.Money(totals.VENDOR)))
end)
