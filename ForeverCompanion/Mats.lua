-- Mats: how you'd get the materials for a recipe, and what that costs you
-- in gold and in leveling time.
--
-- For each material: what your characters already hold, then the cheapest
-- way to get the rest: a vendor, gathering it yourself, farming mobs at your
-- level (you get XP anyway), the auction house, or grinding mobs far below
-- you (slow, and it takes time away from leveling).
local _, ns = ...
local C, D = ns.C, ns.Data
local MA = {}
ns.Mats = MA

-- How much effort each way of getting a material is (lower is better).
local EFFORT = { have = 0, vendor = 1, gather = 2, farm = 3, ah = 4, grind = 6, unknown = 5 }
MA.Effort = EFFORT

-- Items held by each of your characters: { [itemID] = { total, by = { [label] = n } } }
local holdCache, holdTime
function MA.Holdings()
    if holdCache and GetTime() - holdTime < 5 then return holdCache end
    local out = {}
    for key, char in pairs(ns.db.chars) do
        if type(char) == "table" then
            local label = ns.CharLabel(char, key)
            for _, where in ipairs({ "bags", "bank" }) do
                for _, item in ipairs(char[where] or {}) do
                    if item.id then
                        local h = out[item.id]
                        if not h then h = { total = 0, by = {} } out[item.id] = h end
                        h.total = h.total + (item.count or 1)
                        h.by[label] = (h.by[label] or 0) + (item.count or 1)
                    end
                end
            end
        end
    end
    holdCache, holdTime = out, GetTime()
    return out
end

-- Gathering professions your characters have, by item.
local function gatherer(itemID)
    for prof, list in pairs(D.Gathering) do
        for _, g in ipairs(list) do
            if g[1] == itemID then
                for key, char in pairs(ns.db.chars) do
                    for _, p in ipairs(char.professions or {}) do
                        if p.name == prof and (p.rank or 0) >= g[3] then
                            return { who = ns.CharLabel(char, key), prof = prof, me = (char == ns.char) }
                        end
                    end
                end
                return { prof = prof, needSkill = g[3] }  -- nobody can gather it yet
            end
        end
    end
end

-- Vendors and mob drops for a material from QuestieDB.
local qdCache = {}
local function questieSources(itemID)
    if qdCache[itemID] ~= nil then return qdCache[itemID] or nil end
    local L = _G.LibQuestieDB
    if not (L and L.Item and L.Npc) then return end
    local I, N = L.Item, L.Npc
    local out = { vendors = {}, drops = {} }
    local myFaction = UnitFactionGroup("player") == "Horde" and "H" or "A"
    pcall(function()
        for _, npc in ipairs(I.vendors(itemID) or {}) do
            local f = N.friendlyToFaction and N.friendlyToFaction(npc)
            if not f or f:find(myFaction, 1, true) then
                out.vendors[#out.vendors + 1] = { name = N.name(npc), zone = C_Map and C_Map.GetAreaInfo and N.zoneID(npc) and C_Map.GetAreaInfo(N.zoneID(npc)) }
            end
        end
        for _, npc in ipairs(I.npcDrops(itemID) or {}) do
            out.drops[#out.drops + 1] = { name = N.name(npc), lo = N.minLevel(npc), hi = N.maxLevel(npc),
                                          zone = C_Map and C_Map.GetAreaInfo and N.zoneID(npc) and C_Map.GetAreaInfo(N.zoneID(npc)) }
        end
    end)
    qdCache[itemID] = out
    return out
end

-- How to get `qty` of a material. Returns
-- { id, name, qty, have, missing, holders, how, effort, cost (gold to spend), value (market value of all qty), text }
function MA.Source(itemID, qty)
    local level = UnitLevel("player")
    local name = C.GetItemInfo(itemID)
    if not name then C.RequestLoad(itemID) end
    local h = MA.Holdings()[itemID]
    local have = h and h.total or 0
    local s = { id = itemID, name = name or "...", qty = qty, have = have, missing = math.max(0, qty - have), holders = h and h.by }
    local market = ns.Prices.Market(itemID)
    local sell = select(11, C.GetItemInfo(itemID))
    s.value = (market or (sell and sell * 4) or 0) * qty

    if s.missing == 0 then
        s.how, s.effort, s.cost = "have", EFFORT.have, 0
        return s
    end
    local q = questieSources(itemID)
    local g = gatherer(itemID)
    -- 1. A vendor sells it.
    if q and #q.vendors > 0 then
        local v = q.vendors[1]
        s.how, s.effort, s.cost = "vendor", EFFORT.vendor, (sell and sell * 4 or market or 0) * s.missing
        s.where = v.name .. (v.zone and (" (" .. v.zone .. ")") or "")
        return s
    end
    -- 2. One of your characters can gather it.
    if g and g.who then
        s.how, s.effort, s.cost, s.where = "gather", EFFORT.gather, 0, g.who .. ", " .. g.prof
        return s
    end
    -- 3. Mobs drop it. At your level it's free XP; far below you it's a grind.
    local bestDrop
    for _, d in ipairs(q and q.drops or {}) do
        local mid = ((d.lo or 0) + (d.hi or d.lo or 0)) / 2
        local gap = level - mid
        if not bestDrop or math.abs(gap) < math.abs(bestDrop.gap) then bestDrop = { d = d, gap = gap } end
    end
    if bestDrop and bestDrop.gap <= 5 and bestDrop.gap >= -3 then
        local d = bestDrop.d
        s.how, s.effort, s.cost = "farm", EFFORT.farm, 0
        s.where = d.name .. (d.lo and string.format(" (level %d%s)", d.lo, (d.hi and d.hi ~= d.lo) and ("-" .. d.hi) or "") or "")
            .. (d.zone and (" in " .. d.zone) or "")
        return s
    end
    -- 4. The auction house.
    if market then
        s.how, s.effort, s.cost = "ah", EFFORT.ah, market * s.missing
        return s
    end
    -- 5. Only from mobs far below you (or above you).
    if bestDrop then
        local d = bestDrop.d
        s.how, s.effort, s.cost = "grind", EFFORT.grind, 0
        s.where = d.name .. (d.lo and string.format(" (level %d)", d.lo) or "") .. (d.zone and (" in " .. d.zone) or "")
        s.tooHigh = bestDrop.gap < -3
        return s
    end
    s.how, s.effort, s.cost = "unknown", EFFORT.unknown, 0
    if g and g.needSkill then s.where = g.prof .. " " .. g.needSkill end
    return s
end

local HOW_TEXT = {
    have = "|cff4cff4chave|r", vendor = "|cffd0d0d0vendor|r", gather = "|cff80d4ffgather|r",
    farm = "|cff80d4fffarm|r", ah = "|cffffd700AH|r", grind = "|cffff8040grind|r", unknown = "|cff9a9a9a?|r",
}

-- One readable line for a material: "4 Wool Cloth: have 12" / "2 Iron Ore: AH ~30s".
function MA.Text(s)
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(s.id)
    local head = (icon and ("|T" .. icon .. ":14:14|t ") or "") .. s.qty .. " " .. s.name .. ": "
    if s.how == "have" then
        local who = {}
        if s.holders then
            for label, n in pairs(s.holders) do
                if label ~= ns.CharLabel(ns.char, ns:CharKey()) then who[#who + 1] = label:match("^(%S+ %S+)") or label end
            end
        end
        return head .. HOW_TEXT.have .. (#who > 0 and ("|cff9a9a9a (on " .. table.concat(who, ", ") .. ")|r") or "")
    end
    local got = s.have > 0 and ("have " .. s.have .. ", ") or ""
    local detail = ""
    if s.how == "vendor" then detail = " ~" .. ns.Money(s.cost) .. (s.where and (" at " .. s.where) or "")
    elseif s.how == "gather" or s.how == "farm" or s.how == "grind" then detail = s.where and (" " .. s.where) or ""
    elseif s.how == "ah" then detail = " ~" .. ns.Money(s.cost)
    elseif s.how == "unknown" and s.where then detail = " (needs " .. s.where .. ")" end
    return head .. got .. HOW_TEXT[s.how] .. "|cff9a9a9a" .. detail .. "|r"
end

local VERDICT = {
    [0] = { "Mats on hand", "4cff4c" },
    [1] = { "Cheap to make", "4cff4c" },
    [2] = { "Gather the mats", "80d4ff" },
    [3] = { "Farm while leveling", "80d4ff" },
    [4] = { "Buy mats on the AH", "ffd700" },
    [5] = { "Mats source unknown", "9a9a9a" },
    [6] = { "Grind (slow, no XP)", "ff8040" },
}

-- Plan for a recipe: per-material sources and an overall verdict.
-- Returns { mats = {...}, effort, verdict, color, spend (gold out of pocket), value (market value of all mats), expensive }
function MA.Plan(r, sellValue)
    local plan = { mats = {}, effort = 0, spend = 0, value = 0 }
    for _, m in ipairs(r.mats or {}) do
        local s = MA.Source(m.id, m.qty)
        plan.mats[#plan.mats + 1] = s
        plan.effort = math.max(plan.effort, s.effort)
        plan.spend = plan.spend + (s.cost or 0)
        plan.value = plan.value + (s.value or 0)
    end
    if #plan.mats == 0 then plan.effort = EFFORT.unknown end
    local v = VERDICT[plan.effort] or VERDICT[5]
    plan.verdict, plan.color = v[1], v[2]
    -- Expensive: more than a quarter of your gold, or more than the item sells for.
    local gold = GetMoney and GetMoney() or 0
    if plan.spend > 0 and ((gold > 0 and plan.spend > gold * 0.25) or (sellValue and plan.spend > sellValue)) then
        plan.expensive = true
    end
    return plan
end

function MA.Line(plan)
    local parts = {}
    for _, s in ipairs(plan.mats) do parts[#parts + 1] = MA.Text(s) end
    return #parts > 0 and table.concat(parts, "    ") or "|cff9a9a9amaterials not recorded yet|r"
end

function MA.Summary(plan)
    local text = "|cff" .. plan.color .. plan.verdict .. "|r"
    if plan.spend > 0 then text = text .. "|cff9a9a9a, spend ~" .. ns.Money(plan.spend) .. "|r" end
    if plan.expensive then text = text .. " |cffff6060(expensive)|r" end
    return text
end

ns:Listen("BAGS_CHANGED", function() holdCache = nil end)
