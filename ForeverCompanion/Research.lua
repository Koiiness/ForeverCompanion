-- Research: where to get an upgrade for each gear slot. Sources:
--   * dungeons: the in-game dungeon journal (when the client has one) plus
--     every equippable item seen dropping in a dungeon you were in
--   * crafting: recipes your characters know or can still learn, with where
--     the pattern comes from and what it costs on the AH
--   * auction house: items seen in price scans
-- For each slot the best item from each source is kept, so you can compare.
local _, ns = ...
local C, D = ns.C, ns.Data
local R = {}
ns.Research = R

local KINDS = { "quest", "dungeon", "ah", "craft" }
R.KindLabel = { quest = "|cffffff00Quest|r", dungeon = "|cffff8040Dungeon|r", ah = "|cffffd700Auction house|r", craft = "|cff40c0ffCraft|r" }

----------------------------------------------------------------------
-- Dungeon data
----------------------------------------------------------------------
local function dungeonLevels(name)
    if not name then return end
    for _, d in ipairs(D.Dungeons) do
        if name == d[1] or name:find(d[1], 1, true) or d[1]:find(name, 1, true) then return d[2], d[3] end
    end
end

function R.HasJournal()
    return EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex and EJ_SelectInstance and EJ_GetNumLoot
        and C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex and true or false
end

-- Reads every dungeon's loot for your class into ns.db.journal. Skipped
-- while the journal window is open so it doesn't change what you're viewing.
function R.ScanJournal()
    if not R.HasJournal() or InCombatLockdown() then return false end
    if EncounterJournal and EncounterJournal:IsShown() then return false end
    local classID = select(3, UnitClass("player"))
    local loot, instances = {}, 0
    for tier = 1, EJ_GetNumTiers() do
        EJ_SelectTier(tier)
        local i = 1
        while true do
            local instanceID, name = EJ_GetInstanceByIndex(i, false)
            if not instanceID then break end
            EJ_SelectInstance(instanceID)
            if EJ_SetLootFilter then EJ_SetLootFilter(classID, 0) end
            if C_EncounterJournal.ResetSlotFilter then C_EncounterJournal.ResetSlotFilter() end
            for j = 1, EJ_GetNumLoot() do
                local info = C_EncounterJournal.GetLootInfoByIndex(j)
                if info and info.itemID then
                    local boss = info.encounterID and EJ_GetEncounterInfo and EJ_GetEncounterInfo(info.encounterID)
                    loot[#loot + 1] = { id = info.itemID, instance = name, boss = boss }
                end
            end
            instances = instances + 1
            i = i + 1
        end
    end
    ns.db.journal = { t = time(), loot = loot, class = classID, instances = instances }
    return true
end

----------------------------------------------------------------------
-- AtlasLoot Classic Forever (optional). Its dungeon module holds every
-- dungeon and raid with bosses, items, Forever level ranges and drop rates.
-- Read into memory once per session; nothing is copied into saved data.
----------------------------------------------------------------------
local AL_MODULE = "AtlasLootClassic_DungeonsAndRaids"
R.atlas = nil       -- list of { id, instance, boss, lo, hi, rate, raid }
R.atlasByItem = {}  -- itemID -> first entry
R.atlasStatus = "not installed"

local function cleanName(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return strtrim(s)
end

function R.HasAtlasLoot()
    return _G.AtlasLoot ~= nil and _G.AtlasLoot.ItemDB ~= nil
end

function R.ScanAtlasLoot()
    if R.atlas then return true end
    if not R.HasAtlasLoot() then R.atlasStatus = "not installed" return false end
    if InCombatLockdown() then return false end
    if not C.IsAddOnLoaded(AL_MODULE) then
        local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if load then pcall(load, AL_MODULE) end
        if not C.IsAddOnLoaded(AL_MODULE) then
            R.atlasStatus = "its Dungeons and Raids module is disabled"
            return false
        end
    end
    local AL = _G.AtlasLoot
    local db = AL.ItemDB:Get(AL_MODULE)
    if type(db) ~= "table" then R.atlasStatus = "no dungeon data found" return false end
    local Droprate = AL.Data and AL.Data.Droprate
    local list, byItem = {}, {}
    for key, content in pairs(db) do
        if type(key) == "string" and type(content) == "table" and type(content.items) == "table" then
            local instance = cleanName(content.name) or key
            local lr = type(content.LevelRange) == "table" and content.LevelRange or nil
            local lo, hi = lr and (lr[2] or lr[1]), lr and (lr[3] or lr[2])
            local raid = key:find("Raid") ~= nil
            for _, boss in ipairs(content.items) do
                if type(boss) == "table" then
                    local npc = boss.npcID
                    if type(npc) == "table" then npc = npc[1] end
                    local bossName = cleanName(boss.name)
                    local seen = {}
                    for dk, entries in pairs(boss) do
                        if type(dk) == "number" and type(entries) == "table" then
                            for _, e in ipairs(entries) do
                                local id = type(e) == "table" and e[2]
                                if type(id) == "number" and id > 0 and not seen[id] then
                                    seen[id] = true
                                    local rate = Droprate and npc and Droprate:GetData(npc, id) or nil
                                    local entry = { id = id, instance = instance, boss = bossName, lo = lo, hi = hi,
                                                    rate = rate, raid = raid }
                                    list[#list + 1] = entry
                                    if not byItem[id] then byItem[id] = entry end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    R.atlas, R.atlasByItem = list, byItem
    R.atlasStatus = #list > 0 and ("" .. #list .. " drops") or "no drops found"
    return #list > 0
end

-- Where a pattern for this recipe drops, from AtlasLoot ("Pattern: X" items).
local patternIndex
function R.PatternDrop(recipeName)
    if not recipeName or not R.atlas then return end
    if not patternIndex then
        patternIndex = {}
        local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        for _, e in ipairs(R.atlas) do
            local classID = instant and select(6, instant(e.id))
            if classID == 9 then
                local name = C.GetItemInfo(e.id)
                if name then
                    local short = name:match("^[^:]+: (.+)$")
                    if short then patternIndex[short:lower()] = e end
                else
                    C.RequestLoad(e.id)
                    patternIndex.__incomplete = true
                end
            end
        end
    end
    local hit = patternIndex[recipeName:lower()]
    if not hit and patternIndex.__incomplete then patternIndex = nil end  -- retry once names load
    return hit
end

function R.FormatRate(rate)
    if not rate then return nil end
    if rate >= 10 then return string.format("%.0f%%", rate) end
    return string.format("%.1f%%", rate)
end

local journalTried = false
local function ensureJournal()
    if not R.atlas then pcall(R.ScanAtlasLoot) end
    if journalTried then return end
    journalTried = true
    local j = ns.db.journal
    local classID = select(3, UnitClass("player"))
    if j and j.class == classID and time() - (j.t or 0) < 7 * 86400 and #j.loot > 0 then return end
    pcall(R.ScanJournal)
end

-- Remember equippable items that drop in dungeons (yours or your group's).
local function rememberDrop(link, who)
    local id = C.ItemID(link)
    if not id then return end
    local classID = select(12, C.GetItemInfo(id))
    if classID and classID ~= 2 and classID ~= 4 then return end  -- gear only
    local inInstance, kind = IsInInstance()
    if not inInstance or (kind ~= "party" and kind ~= "raid") then return end
    local instance = GetInstanceInfo()
    ns.db.seenLoot = ns.db.seenLoot or {}
    local rec = ns.db.seenLoot[id]
    if not rec then rec = { instance = instance, n = 0 } ns.db.seenLoot[id] = rec end
    rec.n = rec.n + 1
    rec.t = time()
    if who then rec.boss = who end
end

local countedCorpses = {}
ns:On("LOOT_READY", function()
    if not GetNumLootItems then return end
    local who = UnitExists("target") and UnitIsDead("target") and UnitName("target") or nil
    -- Count each looted corpse once, to work out drop rates from what you see.
    local guid = who and UnitGUID("target")
    local inInstance = IsInInstance()
    if guid and inInstance and not countedCorpses[guid] then
        countedCorpses[guid] = true
        ns.db.seenKills = ns.db.seenKills or {}
        ns.db.seenKills[who] = (ns.db.seenKills[who] or 0) + 1
    end
    for i = 1, GetNumLootItems() do
        local link = GetLootSlotLink(i)
        if link then rememberDrop(link, who) end
    end
end)
ns:On("CHAT_MSG_LOOT", function(_, msg)
    for link in (msg or ""):gmatch("|Hitem:[^|]+|h") do rememberDrop(link) end
end)

----------------------------------------------------------------------
-- Candidate index: slot -> itemID -> { sources }
----------------------------------------------------------------------
local index, indexTime
local waiting = 0

local function slotsFor(itemID)
    local _, _, _, _, _, _, _, _, equipLoc = C.GetItemInfo(itemID)
    if equipLoc == nil then
        if waiting < 300 then C.RequestLoad(itemID) end  -- load in batches
        waiting = waiting + 1
        return
    end
    return D.EquipSlots[equipLoc]
end

local function add(bySlot, itemID, source)
    local slots = slotsFor(itemID)
    if not slots then return end
    for _, slot in ipairs(slots) do
        bySlot[slot] = bySlot[slot] or {}
        local e = bySlot[slot][itemID]
        if not e then e = { id = itemID, sources = {} } bySlot[slot][itemID] = e end
        table.insert(e.sources, source)
    end
end

R.Counts = { quest = 0, dungeon = 0, ah = 0, craft = 0 }
R.memo = {}

function R.BuildIndex()
    if index then return index end
    R.memo = {}
    waiting = 0
    local counts = { quest = 0, dungeon = 0, ah = 0, craft = 0 }
    local bySlot = {}
    for _, q in ipairs(ns.Quests and ns.Quests.RewardItems() or {}) do
        if q.id then
            add(bySlot, q.id, { kind = "quest", quest = q.title or q.quest, choice = q.choice, complete = q.complete })
            counts.quest = counts.quest + 1
        end
    end
    -- Quests you haven't picked up yet (QuestieDB).
    for _, rw in ipairs(ns.QuestDB and ns.QuestDB.rewards or {}) do
        local ok, info = pcall(ns.QuestDB.Info, rw.quest)
        if ok and info and not info.inLog then
            add(bySlot, rw.item, { kind = "quest", quest = info.name, questID = rw.quest, pickup = true, starter = info.starter,
                                   zone = info.zone, needs = info.needs, qlevel = info.level, req = info.req })
            counts.quest = counts.quest + 1
        end
    end
    for _, e in ipairs(R.atlas or {}) do
        add(bySlot, e.id, { kind = "dungeon", instance = e.instance, boss = e.boss, lo = e.lo, hi = e.hi, rate = e.rate,
                            raid = e.raid, atlas = true })
        counts.dungeon = counts.dungeon + 1
    end
    local j = ns.db.journal
    for _, l in ipairs(j and j.loot or {}) do
        local lo, hi = dungeonLevels(l.instance)
        add(bySlot, l.id, { kind = "dungeon", instance = l.instance, boss = l.boss, lo = lo, hi = hi })
        counts.dungeon = counts.dungeon + 1
    end
    for id, rec in pairs(ns.db.seenLoot or {}) do
        local lo, hi = dungeonLevels(rec.instance)
        local kills = rec.boss and ns.db.seenKills and ns.db.seenKills[rec.boss]
        local observed = (kills and kills >= 3) and math.min(100, rec.n / kills * 100) or nil
        add(bySlot, id, { kind = "dungeon", instance = rec.instance, boss = rec.boss, lo = lo, hi = hi, seen = rec.n,
                          rate = observed, observed = observed ~= nil, kills = kills })
        counts.dungeon = counts.dungeon + 1
    end
    for key, char in pairs(ns.db.chars) do
        for prof, rec in pairs(char.recipes or {}) do
            for name, r in pairs(rec.list or {}) do
                if r.item then
                    add(bySlot, r.item, { kind = "craft", prof = prof, recipe = name, learned = r.learned ~= false,
                                          source = r.source, who = ns.CharLabel(char, key), mine = (char == ns.char) })
                    counts.craft = counts.craft + 1
                end
            end
        end
    end
    for itemID in pairs(ns.db.prices) do
        local classID = select(12, C.GetItemInfo(itemID))
        if classID == nil or classID == 2 or classID == 4 then
            add(bySlot, itemID, { kind = "ah" })
            counts.ah = counts.ah + 1
        end
    end
    R.Counts = counts
    index, indexTime = bySlot, GetTime()
    return index
end

local PAIRED = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }

-- Upgrades for one slot. Returns { dungeon = {...}, ah = {...}, craft = {...} },
-- each a list of { id, link, cmp, source, reqLevel } sorted best first.
function R.ForSlot(slot, perKind)
    ensureJournal()
    perKind = perKind or 2
    R.BuildIndex()
    local key = slot .. ":" .. perKind
    if R.memo[key] then return R.memo[key] end
    local level = UnitLevel("player")
    local out = { quest = {}, dungeon = {}, ah = {}, craft = {} }
    for itemID, e in pairs(R.BuildIndex()[slot] or {}) do
        local _, link, _, _, reqLevel = C.GetItemInfo(itemID)
        if link and (reqLevel or 0) <= level + 5 then
            local cmp = ns.Gear.Compare(link)
            if cmp and cmp.partial then waiting = waiting + 1 end
            if cmp and not cmp.unusable and not cmp.partial and cmp.delta > 0.5 and (cmp.slot == slot or PAIRED[slot] == cmp.slot) then
                local seenKind = {}
                for _, s in ipairs(e.sources) do
                    -- Keep the most useful source of each kind (a recipe you know beats one you don't).
                    local prev = seenKind[s.kind]
                    if not prev or (s.kind == "craft" and s.mine and s.learned) then seenKind[s.kind] = s end
                end
                for kind, s in pairs(seenKind) do
                    table.insert(out[kind], { id = itemID, link = link, cmp = cmp, source = s, reqLevel = reqLevel or 0 })
                end
            end
        end
    end
    for _, kind in ipairs(KINDS) do
        table.sort(out[kind], function(a, b)
            if a.cmp.delta ~= b.cmp.delta then return a.cmp.delta > b.cmp.delta end
            return a.id < b.id
        end)
        for i = #out[kind], perKind + 1, -1 do out[kind][i] = nil end
    end
    R.memo[key] = out
    return out
end

function R.Best(slot)
    local best
    for _, list in pairs(R.ForSlot(slot, 1)) do
        if list[1] and (not best or list[1].cmp.delta > best.cmp.delta) then best = list[1] end
    end
    return best
end

-- One line saying where to get it and what it costs.
function R.Describe(entry)
    local s = entry.source
    local text
    if s.kind == "quest" and s.pickup then
        text = "pick up " .. (s.quest or "a quest") .. (s.qlevel and (" [" .. s.qlevel .. "]") or "")
            .. (s.starter and (" from " .. s.starter) or "") .. (s.zone and (" in " .. s.zone) or "")
        if s.needs then text = text .. " |cffff8040(do " .. s.needs .. " first)|r" end
        if s.req and s.req > UnitLevel("player") then text = text .. " |cffff8040(available at level " .. s.req .. ")|r" end
    elseif s.kind == "quest" then
        text = (s.quest or "a quest in your log") .. (s.choice and " (pick it as your reward)" or " (reward)")
            .. (s.complete and "  |cff4cff4cready to turn in|r" or "")
    elseif s.kind == "dungeon" then
        text = (s.instance or "a dungeon") .. (s.boss and (", " .. s.boss) or "")
            .. ((s.lo and s.hi) and string.format(" (levels %d-%d)", s.lo, s.hi) or (s.lo and string.format(" (level %d+)", s.lo) or ""))
            .. (s.seen and string.format(", seen drop %d time%s", s.seen, s.seen > 1 and "s" or "") or "")
        if s.rate then
            text = text .. "  |cffffffff" .. R.FormatRate(s.rate) .. " drop chance|r"
                .. (s.observed and string.format(" |cff9a9a9a(from %d kills you saw)|r", s.kills) or "")
        end
        if s.raid then text = text .. " |cff9a9a9a(raid)|r" end
    elseif s.kind == "ah" then
        local price = ns.Prices.Market(entry.id)
        text = price and ("buy for about " .. ns.Money(price)) or "seen listed"
    else
        local who = s.mine and "You" or s.who
        if s.learned then
            text = s.prof .. ": " .. who .. (s.mine and " know" or " knows") .. " this recipe"
        else
            text = s.prof .. ": " .. (s.mine and "learn" or (s.who .. " could learn")) .. " " .. s.recipe
            local parts = {}
            if s.source and s.source ~= "" then parts[#parts + 1] = s.source end
            local drop = R.PatternDrop(s.recipe)
            if drop then
                parts[#parts + 1] = "pattern drops in " .. drop.instance .. (drop.boss and (", " .. drop.boss) or "")
                    .. (drop.rate and (" " .. R.FormatRate(drop.rate)) or "")
            end
            local patternID, price = ns.Prices.PatternFor(s.recipe)
            if price then parts[#parts + 1] = "pattern on AH ~" .. ns.Money(price)
            elseif patternID then parts[#parts + 1] = "pattern seen on AH" end
            if #parts > 0 then text = text .. "  |cff9a9a9a(" .. table.concat(parts, "; ") .. ")|r" end
        end
    end
    local req = entry.reqLevel > UnitLevel("player") and ("  |cffff8040usable at level " .. entry.reqLevel .. "|r") or ""
    return R.KindLabel[s.kind] .. ": " .. text .. req
end

-- Explains which sources have no data yet and how to fill them.
function R.MissingData()
    local hints = {}
    local c = R.Counts
    if ns.QuestDB and not ns.QuestDB.rewards then
        hints[#hints + 1] = ns.QuestDB.Has() and ("Questie: " .. ns.QuestDB.status .. ".")
            or "Quests you haven't picked up: install Questie to see which quests reward upgrades."
    end
    if not R.atlas then
        hints[#hints + 1] = R.HasAtlasLoot() and ("AtlasLoot: " .. R.atlasStatus .. ".")
            or "Dungeon loot: install AtlasLoot Classic Forever for every dungeon's drops and drop rates."
    end
    if c.dungeon == 0 then
        do
            local level, faction, list = UnitLevel("player"), UnitFactionGroup("player"), {}
            for _, d in ipairs(D.Dungeons) do
                if (not d[4] or d[4] == faction) and level >= d[2] - 2 and level <= d[3] then
                    list[#list + 1] = string.format("%s (%d-%d)", d[1], d[2], d[3])
                end
            end
            hints[#hints + 1] = "Dungeon loot: nothing known yet, so drops are learned as you see them. "
                .. "Run a dungeon and every item that drops is remembered. Dungeons for your level: "
                .. (#list > 0 and table.concat(list, ", ") or "none") .. "."
        end
    end
    if c.ah == 0 and not TSM_API then
        hints[#hints + 1] = "Auction house: no gear prices yet. Open the auction house and a full scan runs by itself."
    end
    local missing = {}
    for _, p in ipairs(ns.char.professions or {}) do
        local craftsGear = p.name == "Tailoring" or p.name == "Leatherworking" or p.name == "Blacksmithing" or p.name == "Engineering"
        if craftsGear and not ns.char.recipes[p.name] then missing[#missing + 1] = p.name end
    end
    if #missing > 0 then
        hints[#hints + 1] = "Crafting: open your " .. table.concat(missing, " and ") .. " window once so craftable gear can be suggested."
    end
    if waiting > 0 then hints[#hints + 1] = "Still loading details for " .. waiting .. " items; this page updates as they arrive." end
    return hints
end

ns:On("GET_ITEM_INFO_RECEIVED", function()
    if waiting > 0 then
        index = nil
        ns:Debounce("research", 2, function() if ns.RefreshUI then ns.RefreshUI() end end)
    end
end)
ns:On("EJ_LOOT_DATA_RECIEVED", function() index = nil end)
ns:Listen("PRICES_CHANGED", function() index = nil end)
ns:Listen("GEAR_CHANGED", function() index = nil end)
function R.Invalidate() index = nil end
ns:Listen("PROFESSIONS_CHANGED", function() index = nil end)

----------------------------------------------------------------------
-- Plan: roll every slot's upgrades up into "do these quests" and "run
-- these dungeons", best first.
----------------------------------------------------------------------
function R.Plan()
    local level = UnitLevel("player")
    local dungeons, quests = {}, {}
    local seenItem = {}
    for _, slot in ipairs(D.SlotOrder) do
        local finds = R.ForSlot(slot, 3)
        for _, f in ipairs(finds.dungeon) do
            local s = f.source
            local key = s.instance or "?"
            -- When it fits: now (in range or a quick run below you), soon (within
            -- 6 levels), or not at all. Raids only from level 55.
            local when, inLevels, below = "now", nil, false
            if s.lo and level < s.lo - 1 then when, inLevels = "soon", s.lo - level end
            if s.hi and level > s.hi + 4 then below = true end
            local skip = (inLevels and inLevels > 6) or (s.raid and level < 55)
            if not skip then
                local d = dungeons[key]
                if not d then
                    d = { name = key, lo = s.lo, hi = s.hi, items = {}, score = 0, when = when, inLevels = inLevels, below = below }
                    dungeons[key] = d
                end
                local k = key .. ":" .. f.id
                if not seenItem[k] then
                    seenItem[k] = true
                    local chance = s.rate and math.min(1, s.rate / 100) or 0.15
                    d.score = d.score + f.cmp.delta * (0.5 + chance)
                    d.items[#d.items + 1] = { f = f, slot = slot }
                end
            end
        end
        for _, f in ipairs(finds.quest) do
            local key = f.source.quest or "?"
            local q = quests[key]
            if not q then
                local req = f.source.req
                q = { name = key, items = {}, score = 0, complete = f.source.complete, pickup = f.source.pickup,
                      starter = f.source.starter, zone = f.source.zone, needs = f.source.needs, req = req,
                      when = (req and req > level) and "soon" or "now", inLevels = (req and req > level) and (req - level) or nil }
                quests[key] = q
            end
            local k = key .. ":" .. f.id
            if not seenItem[k] then
                seenItem[k] = true
                q.score = q.score + f.cmp.delta
                q.items[#q.items + 1] = { f = f, slot = slot, choice = f.source.choice }
            end
        end
    end
    local dl, ql = {}, {}
    for _, d in pairs(dungeons) do
        table.sort(d.items, function(a, b) return a.f.cmp.delta > b.f.cmp.delta end)
        dl[#dl + 1] = d
    end
    for _, q in pairs(quests) do
        table.sort(q.items, function(a, b) return a.f.cmp.delta > b.f.cmp.delta end)
        ql[#ql + 1] = q
    end
    table.sort(dl, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.name < b.name end)
    table.sort(ql, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.name < b.name end)
    return { dungeons = dl, quests = ql }
end
