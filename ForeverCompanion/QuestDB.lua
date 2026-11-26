-- QuestDB: quests you haven't picked up yet whose rewards are gear, from
-- QuestieDB (installed with Questie). Read through its public API
-- (_G.LibQuestieDB); nothing is copied into saved data.
--
-- Once per session, in small batches so the game doesn't stutter, it walks
-- QuestieDB's items, keeps armor and weapons near your level that a quest
-- rewards, and keeps the quests your race and class can take and haven't
-- completed. Gear research then scores those items like any other source.
local _, ns = ...
local C = ns.C
local QD = {}
ns.QuestDB = QD

QD.rewards = nil        -- list of { item, quest }
QD.status = "not installed"

function QD.Has()
    local L = _G.LibQuestieDB
    return L ~= nil and L.Item ~= nil and L.Quest ~= nil and L.Item.questRewards ~= nil
end

local function masks()
    local L = _G.LibQuestieDB
    local enum = L.Enum or {}
    local class = select(2, UnitClass("player"))
    local raceID = select(3, UnitRace("player"))
    local cm = enum.classKeys and enum.classKeys[class]
    local rm = enum.raceMaskById and enum.raceMaskById[raceID]
    return cm, rm
end

local function completed(qid)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(qid) end
    return false
end

-- Can this character take the quest (ignoring level)?
function QD.Available(qid, cm, rm)
    local Q = _G.LibQuestieDB.Quest
    if not Q.Exists(qid) or completed(qid) then return false end
    local races = Q.requiredRaces(qid)
    if races and races ~= 0 and rm and bit.band(races, rm) == 0 then return false end
    local classes = Q.requiredClasses(qid)
    if classes and classes ~= 0 and cm and bit.band(classes, cm) == 0 then return false end
    local maxLevel = Q.requiredMaxLevel and Q.requiredMaxLevel(qid)
    if maxLevel and maxLevel > 0 and UnitLevel("player") > maxLevel then return false end
    return true
end

local function areaName(areaID)
    if not areaID or areaID <= 0 then return nil end
    if C_Map and C_Map.GetAreaInfo then return C_Map.GetAreaInfo(areaID) end
end

-- Display details for a quest: name, levels, where it starts, prerequisites.
local infoCache = {}
function QD.Info(qid)
    if infoCache[qid] then return infoCache[qid] end
    local L = _G.LibQuestieDB
    local Q, N = L.Quest, L.Npc
    local info = { id = qid, name = Q.name(qid) or ("Quest " .. qid), level = Q.questLevel(qid), req = Q.requiredLevel(qid) }
    local starters = Q.startedBy(qid)
    local npc = starters and starters[1] and starters[1][1]
    if npc and N then
        info.starter = N.name(npc)
        info.zone = areaName(N.zoneID(npc))
    elseif starters and starters[3] and starters[3][1] then
        info.starter = "an item"
    end
    info.zone = info.zone or areaName(Q.zoneOrSort(qid))
    local pre = Q.preQuestSingle(qid) or Q.preQuestGroup(qid)
    if pre then
        for _, p in ipairs(pre) do
            if not completed(p) then info.needs = Q.name(p) break end
        end
    end
    info.inLog = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(qid) ~= nil
    infoCache[qid] = info
    return info
end

local scanning = false
function QD.StartScan()
    if scanning or QD.rewards then return end
    if not QD.Has() then QD.status = "not installed" return end
    local L = _G.LibQuestieDB
    local ok, ids = pcall(L.Item.GetAllIds)
    if not ok or type(ids) ~= "table" then QD.status = "couldn't read QuestieDB" return end
    scanning = true
    QD.status = "reading quests..."
    local level = UnitLevel("player")
    local cm, rm = masks()
    local I = L.Item
    local out, i = {}, 0
    local ticker
    ticker = C_Timer.NewTicker(0.05, function()
        if InCombatLockdown() then return end
        local n = 0
        while i < #ids and n < 400 do
            i, n = i + 1, n + 1
            local id = ids[i]
            pcall(function()
                local cls = I.class(id)
                if cls == 2 or cls == 4 then
                    local rl = I.requiredLevel(id) or 0
                    if rl <= level + 5 and rl >= level - 10 then
                        local quests = I.questRewards(id)
                        for _, q in ipairs(quests or {}) do
                            if QD.Available(q, cm, rm) then
                                out[#out + 1] = { item = id, quest = q }
                                C.RequestLoad(id)
                            end
                        end
                    end
                end
            end)
        end
        if i >= #ids then
            ticker:Cancel()
            scanning = false
            QD.rewards = out
            QD.status = #out .. " quest rewards near your level"
            if ns.Research then ns.Research.Invalidate() end
            if ns.RefreshUI then ns.RefreshUI() end
        end
    end)
end

-- Start a little after login; rescan when you level up or finish a quest.
----------------------------------------------------------------------
-- Questing zones: quests you can take at your level that you haven't done,
-- grouped by zone, so the plan can say "Quest in Desolace: 14 quests".
----------------------------------------------------------------------
QD.zones = nil    -- list of { name, count, quests = { id... } }, most quests first
local zoneScanning = false

function QD.StartZoneScan()
    if zoneScanning or QD.zones or not QD.Has() then return end
    local L = _G.LibQuestieDB
    local Q, N = L.Quest, L.Npc
    local ok, ids = pcall(Q.GetAllIds)
    if not ok or type(ids) ~= "table" then return end
    zoneScanning = true
    local level = UnitLevel("player")
    local faction = UnitFactionGroup("player")
    local myFaction = faction == "Horde" and "H" or "A"
    local cm, rm = masks()
    local byZone, i = {}, 0
    local ticker
    ticker = C_Timer.NewTicker(0.05, function()
        if InCombatLockdown() then return end
        local n = 0
        while i < #ids and n < 300 do
            i, n = i + 1, n + 1
            local q = ids[i]
            pcall(function()
                local ql, req = Q.questLevel(q), Q.requiredLevel(q) or 0
                -- Worth doing now: not gray, not more than 3 levels above you.
                if ql and ql > 0 and ql >= level - 3 and ql <= level + 3 and req <= level and QD.Available(q, cm, rm) then
                    local inLog = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(q)
                    if not inLog then
                        local starters = Q.startedBy(q)
                        local npc = starters and starters[1] and starters[1][1]
                        -- Skip quests given by NPCs hostile to your faction.
                        local friendly = not npc or not N.friendlyToFaction or (N.friendlyToFaction(npc) or "AH"):find(myFaction, 1, true)
                        local zone = (npc and N.zoneID(npc)) or Q.zoneOrSort(q)
                        if friendly and zone and zone > 0 then
                            local z = byZone[zone]
                            if not z then z = { area = zone, quests = {} } byZone[zone] = z end
                            z.quests[#z.quests + 1] = q
                        end
                    end
                end
            end)
        end
        if i >= #ids then
            ticker:Cancel()
            zoneScanning = false
            local list = {}
            for area, z in pairs(byZone) do
                z.name = areaName(area) or ("Zone " .. area)
                z.count = #z.quests
                list[#list + 1] = z
            end
            table.sort(list, function(a, b)
                if a.count ~= b.count then return a.count > b.count end
                return a.name < b.name
            end)
            QD.zones = list
            if ns.RefreshUI then ns.RefreshUI() end
        end
    end)
end

----------------------------------------------------------------------
-- Pattern sources: where to get the recipe item (Pattern:, Plans:, ...)
-- for a recipe you haven't learned: vendors, mob drops, quests, objects.
-- Forever's client doesn't report recipe sources, so this fills the gap.
----------------------------------------------------------------------
local RECIPE_PREFIXES = { "Pattern: ", "Plans: ", "Formula: ", "Recipe: ", "Schematic: ", "Manual: ", "Design: ", "Technique: " }
QD.nameIndexReady = false

-- Builds QuestieDB's item name index in small steps so there's no freeze.
function QD.BuildNameIndex()
    if QD.nameIndexReady or QD.nameIndexBuilding or not QD.Has() then return end
    local I = _G.LibQuestieDB.Item
    if not I.BuildNameIndexAsync then
        QD.nameIndexReady = I.IdsByName ~= nil
        return
    end
    QD.nameIndexBuilding = true
    local co = coroutine.create(function() I.BuildNameIndexAsync(400) end)
    local ticker
    ticker = C_Timer.NewTicker(0.05, function()
        if InCombatLockdown() then return end
        local ok = coroutine.resume(co)
        if not ok or coroutine.status(co) == "dead" then
            ticker:Cancel()
            QD.nameIndexBuilding = false
            QD.nameIndexReady = ok
            if ns.Research then ns.Research.Invalidate() end
            if ns.RefreshUI then ns.RefreshUI() end
        end
    end)
end

local sourceCache = {}
-- Returns { itemID, vendors = {..}, drops = {..}, quests = {..}, objects = {..}, favor = bool } or nil.
function QD.PatternSources(recipeName)
    if not (recipeName and QD.Has() and QD.nameIndexReady) then return end
    local cached = sourceCache[recipeName]
    if cached ~= nil then return cached or nil end
    local L = _G.LibQuestieDB
    local I, N, Q, O = L.Item, L.Npc, L.Quest, L.Object
    local ids
    for _, pre in ipairs(RECIPE_PREFIXES) do
        local ok, r = pcall(I.IdsByName, pre .. recipeName)
        if ok and r and #r > 0 then ids = r break end
    end
    if not ids then sourceCache[recipeName] = false return end
    local myFaction = UnitFactionGroup("player") == "Horde" and "H" or "A"
    local favorVendors = {}
    for _, v in ipairs(ns.Crates and ns.Crates.Vendors or {}) do favorVendors[v] = true end
    local out = { itemID = ids[1], vendors = {}, drops = {}, quests = {}, objects = {}, favor = false }
    local seen = {}
    local function npcEntry(npc)
        local name = N.name(npc)
        if not name or seen[name] then return end
        seen[name] = true
        local f = N.friendlyToFaction and N.friendlyToFaction(npc)
        return { name = name, zone = areaName(N.zoneID(npc)), friendly = (f == nil) or f:find(myFaction, 1, true) ~= nil }
    end
    for _, id in ipairs(ids) do
        pcall(function()
            for _, npc in ipairs(I.vendors(id) or {}) do
                local e = npcEntry(npc)
                if e then
                    out.vendors[#out.vendors + 1] = e
                    if favorVendors[e.name] then out.favor = true end
                end
            end
            for _, npc in ipairs(I.npcDrops(id) or {}) do
                local e = npcEntry(npc)
                if e then out.drops[#out.drops + 1] = e end
            end
            for _, q in ipairs(I.questRewards(id) or {}) do out.quests[#out.quests + 1] = Q.name(q) or ("quest " .. q) end
            if O then
                for _, o in ipairs(I.objectDrops(id) or {}) do out.objects[#out.objects + 1] = O.name(o) or "an object" end
            end
        end)
    end
    -- Vendors friendly to you first.
    table.sort(out.vendors, function(a, b)
        if a.friendly ~= b.friendly then return a.friendly end
        return a.name < b.name
    end)
    sourceCache[recipeName] = out
    return out
end

-- One line: "sold by X (Zone); drops from Y (Zone) and 4 more; quest reward: Z".
function QD.PatternSourceText(recipeName)
    local s = QD.PatternSources(recipeName)
    if not s then return end
    local parts = {}
    local function list(entries, verb, max)
        if #entries == 0 then return end
        local names = {}
        for i = 1, math.min(max, #entries) do
            local e = entries[i]
            names[#names + 1] = e.name .. (e.zone and (" (" .. e.zone .. ")") or "")
        end
        local more = #entries - max
        parts[#parts + 1] = verb .. " " .. table.concat(names, ", ") .. (more > 0 and (" and " .. more .. " more") or "")
    end
    list(s.vendors, "sold by", 2)
    list(s.drops, "drops from", 2)
    if #s.quests > 0 then parts[#parts + 1] = "quest reward: " .. table.concat(s.quests, ", ", 1, math.min(2, #s.quests)) end
    if #s.objects > 0 then parts[#parts + 1] = "found in " .. s.objects[1] end
    if #parts == 0 then return end
    return table.concat(parts, "; ") .. (s.favor and " |cffffd100(Merchant's Favor)|r" or "")
end

-- A few quest names from a zone, for the plan.
function QD.SampleNames(zone, max)
    local Q = _G.LibQuestieDB.Quest
    local out = {}
    for i = 1, math.min(max or 3, #zone.quests) do out[#out + 1] = Q.name(zone.quests[i]) or "?" end
    return out
end

ns:Listen("READY", function()
    C_Timer.After(10, QD.StartScan)
    C_Timer.After(20, QD.StartZoneScan)
    C_Timer.After(30, QD.BuildNameIndex)
end)
ns:On("PLAYER_LEVEL_UP", function()
    QD.rewards = nil
    QD.zones = nil
    wipe(infoCache)
    C_Timer.After(5, QD.StartScan)
    C_Timer.After(15, QD.StartZoneScan)
end)
ns:On("QUEST_TURNED_IN", function() wipe(infoCache) end)
ns:On("QUEST_ACCEPTED", function() wipe(infoCache) end)
