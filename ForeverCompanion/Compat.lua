-- Compat: one place that hides API differences. WoW Forever runs on the
-- modern (Mainline) API with Classic-style content, so every call prefers the
-- C_* namespace and falls back to the old global function when it is missing.
local _, ns = ...
local C = {}
ns.C = C

local CC = C_Container

----------------------------------------------------------------------
-- Items
----------------------------------------------------------------------
-- name, link, quality, ilvl, reqLevel, class, subclass, maxStack, equipLoc,
-- texture, sellPrice, classID, subclassID, bindType
-- Item info is kept once seen: the game drops items from its cache and
-- reloads them later, which made upgrade lists flicker as items vanished
-- and came back.
local infoCache = {}
local function pack(...) return { n = select("#", ...), ... } end
function C.GetItemInfo(item)
    if not item then return end
    local hit = infoCache[item]
    if hit then return unpack(hit, 1, hit.n) end
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local res = pack(f(item))
    if res[1] then infoCache[item] = res end
    return unpack(res, 1, res.n)
end

function C.ItemID(link)
    if type(link) == "number" then return link end
    if not link then return end
    return tonumber(link:match("item:(%d+)"))
end

function C.EffectiveILvl(link)
    local f = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    if f then
        local v = f(link)
        if v and v > 0 then return v end
    end
    local _, _, _, ilvl = C.GetItemInfo(link)
    return ilvl
end

function C.GetItemStats(link)
    local f = (C_Item and C_Item.GetItemStats) or GetItemStats
    if not f or not link then return {} end
    return f(link) or {}
end

function C.RequestLoad(id)
    if id and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
end

-- Left-hand text lines of an item tooltip, without showing a tooltip.
local scanTip
-- Returns the lines and whether the tooltip was complete (item data loaded).
function C.TooltipLines(link)
    local out = {}
    if not link then return out, false end
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local data = C_TooltipInfo.GetHyperlink(link)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                if line.leftText then out[#out + 1] = line.leftText end
            end
        end
        local complete = #out > 1 and not (out[1] or ""):find(RETRIEVING_ITEM_INFO or "Retrieving item information", 1, true)
        return out, complete
    end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "ForeverCompanionScanTip", nil, "GameTooltipTemplate")
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    scanTip:ClearLines()
    scanTip:SetHyperlink(link)
    for i = 1, scanTip:NumLines() do
        local fs = _G["ForeverCompanionScanTipTextLeft" .. i]
        local t = fs and fs:GetText()
        if t then out[#out + 1] = t end
    end
    local complete = #out > 1 and not (out[1] or ""):find(RETRIEVING_ITEM_INFO or "Retrieving item information", 1, true)
    return out, complete
end

function C.IsAddOnLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    return IsAddOnLoaded and IsAddOnLoaded(name)
end

----------------------------------------------------------------------
-- Containers
----------------------------------------------------------------------
function C.NumSlots(bag)
    if CC and CC.GetContainerNumSlots then return CC.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

-- Returns a table { id, link, count, quality, bound, noValue } or nil.
function C.SlotInfo(bag, slot)
    if CC and CC.GetContainerItemInfo then
        local i = CC.GetContainerItemInfo(bag, slot)
        if not i then return end
        return { id = i.itemID, link = i.hyperlink, count = i.stackCount or 1, quality = i.quality,
                 bound = i.isBound, noValue = i.hasNoValue }
    end
    if not GetContainerItemInfo then return end
    local tex, count, _, quality, _, _, link, _, noValue, id, bound = GetContainerItemInfo(bag, slot)
    if not tex then return end
    return { id = id, link = link, count = count or 1, quality = quality, bound = bound, noValue = noValue }
end

function C.UseContainerItem(bag, slot)
    if CC and CC.UseContainerItem then return CC.UseContainerItem(bag, slot) end
    return UseContainerItem(bag, slot)
end

function C.BagIDs()
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    local t = {}
    for i = 0, last do t[#t + 1] = i end
    return t
end

function C.BankBagIDs()
    local t = {}
    if Enum and Enum.BagIndex then
        for k, v in pairs(Enum.BagIndex) do
            if type(k) == "string" and k:find("Bank") and not k:find("Account") then
                t[#t + 1] = v
            end
        end
    end
    if #t == 0 then
        t[1] = BANK_CONTAINER or -1
        local first = (NUM_BAG_SLOTS or 4) + 1
        for i = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do t[#t + 1] = i end
    end
    table.sort(t)
    return t
end

----------------------------------------------------------------------
-- Professions (skill ranks)
----------------------------------------------------------------------
function C.GetProfessions()
    local out = {}
    if GetProfessions and GetProfessionInfo then
        local list = { GetProfessions() }
        for i = 1, 6 do
            local idx = list[i]
            if idx then
                local name, icon, rank, max = GetProfessionInfo(idx)
                if name then out[#out + 1] = { name = name, rank = rank, max = max, icon = icon } end
            end
        end
        if #out > 0 then return out end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        local known = ns.Data.ProfessionNames
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
            if name and not isHeader and known[name] then
                out[#out + 1] = { name = name, rank = rank, max = max }
            end
        end
    end
    return out
end

----------------------------------------------------------------------
-- Talents
----------------------------------------------------------------------
local function spellName(spellID)
    if not spellID then return end
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
    return GetSpellInfo and (GetSpellInfo(spellID))
end

-- Modern talent trees (C_ClassTalents / C_Traits). Each tree ID, or each
-- sub-tree inside one, becomes one entry in `trees`.
local function traitTalents()
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo) then return end
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return end
    local config = C_Traits.GetConfigInfo(configID)
    if not (config and config.treeIDs and #config.treeIDs > 0) then return end
    local trees, byKey, unspent = {}, {}, 0
    for _, treeID in ipairs(config.treeIDs) do
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
            local node = C_Traits.GetNodeInfo(configID, nodeID)
            if node and node.ID and node.ID ~= 0 and node.isVisible ~= false then
                local entryID = (node.activeEntry and node.activeEntry.entryID) or (node.entryIDs and node.entryIDs[1])
                local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
                local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                local name = def and (def.overrideName or spellName(def.spellID))
                if name then
                    local key = treeID .. ":" .. (node.subTreeID or 0)
                    local tree = byKey[key]
                    if not tree then
                        tree = { name = nil, points = 0, talents = {} }
                        if node.subTreeID and C_Traits.GetSubTreeInfo then
                            local sub = C_Traits.GetSubTreeInfo(configID, node.subTreeID)
                            tree.name = sub and sub.name
                        end
                        byKey[key] = tree
                        trees[#trees + 1] = tree
                    end
                    local rank = node.ranksPurchased or node.currentRank or 0
                    tree.points = tree.points + rank
                    tree.talents[#tree.talents + 1] = { name = name, rank = rank, max = node.maxRanks or 1,
                                                        tier = node.posY or 0, col = node.posX or 0, available = node.isAvailable }
                end
            end
        end
        if C_Traits.GetTreeCurrencyInfo then
            for _, cur in ipairs(C_Traits.GetTreeCurrencyInfo(configID, treeID, false) or {}) do
                unspent = unspent + (cur.quantity or 0)
            end
        end
    end
    if #trees == 0 then return end
    for i, t in ipairs(trees) do t.name = t.name or ((#trees == 1) and "Talents" or ("Tree " .. i)) end
    return { trees = trees, unspent = unspent, modernTrees = true }
end

-- Returns { trees = { {name, points, talents = { {name, rank, max} } } }, unspent }
-- or nil when no talent trees can be read on this client.
function C.GetTalentTrees()
    local modern = traitTalents()
    if modern then return modern end
    if not (GetNumTalentTabs and GetTalentTabInfo) then return end
    local n = GetNumTalentTabs()
    if not n or n == 0 then return end
    local trees = {}
    for t = 1, n do
        local a, b, c, d, e = GetTalentTabInfo(t)
        local name, points
        if type(a) == "number" then  -- (id, name, description, icon, pointsSpent, ...)
            name, points = b, e
        else                         -- (name, icon, pointsSpent, ...)
            name, points = a, c
        end
        local tree = { name = name, points = tonumber(points) or 0, talents = {} }
        if GetNumTalents and GetTalentInfo then
            for i = 1, (GetNumTalents(t) or 0) do
                local tname, _, tier, col, rank, max = GetTalentInfo(t, i)
                if tname then tree.talents[#tree.talents + 1] = { name = tname, rank = rank or 0, max = max or 0, tier = tier or 0, col = col or 0 } end
            end
            local sum = 0
            for _, tl in ipairs(tree.talents) do sum = sum + tl.rank end
            if sum > tree.points then tree.points = sum end
        end
        trees[t] = tree
    end
    local unspent
    if UnitCharacterPoints then unspent = UnitCharacterPoints("player")
    elseif GetUnspentTalentPoints then unspent = GetUnspentTalentPoints() end
    local total = 0
    for _, t in ipairs(trees) do total = total + #t.talents end
    if total == 0 then return end  -- functions exist but return nothing on this client
    return { trees = trees, unspent = unspent }
end

-- What talent APIs this client has, for /fc talentdebug.
function C.TalentDiagnostics()
    local out = {}
    local function add(k, v) out[#out + 1] = k .. ": " .. tostring(v) end
    add("GetNumTalentTabs", GetNumTalentTabs and (GetNumTalentTabs() or "nil") or "missing")
    add("UnitCharacterPoints", UnitCharacterPoints and UnitCharacterPoints("player") or "missing")
    add("C_ClassTalents", C_ClassTalents and "yes" or "missing")
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        local id = C_ClassTalents.GetActiveConfigID()
        add("active config", id)
        local cfg = id and C_Traits and C_Traits.GetConfigInfo(id)
        if cfg and cfg.treeIDs then
            for _, t in ipairs(cfg.treeIDs) do add("  tree " .. t .. " nodes", #(C_Traits.GetTreeNodes(t) or {})) end
        end
    end
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    add("specialization", getSpec and (getSpec() or "nil") or "missing")
    return out
end

-- Modern specialization fallback: returns name, role ("TANK"/"HEALER"/"DAMAGER").
function C.GetSpecialization()
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    if not (getSpec and getInfo) then return end
    local idx = getSpec()
    if not idx or idx == 0 then return end
    local _, name, _, _, role = getInfo(idx)
    return name, role, idx
end

----------------------------------------------------------------------
-- Quest log
----------------------------------------------------------------------
-- Returns a list of { title, level, questID, complete, header }
function C.GetQuests()
    local out = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local n = C_QuestLog.GetNumQuestLogEntries()
        for i = 1, n do
            local q = C_QuestLog.GetInfo(i)
            if q and not q.isHidden then
                local complete = false
                if not q.isHeader and q.questID and C_QuestLog.IsComplete then
                    complete = C_QuestLog.IsComplete(q.questID)
                end
                out[#out + 1] = { title = q.title, level = q.level, questID = q.questID,
                                  header = q.isHeader, complete = complete, group = q.suggestedGroup }
            end
        end
        return out
    end
    if GetNumQuestLogEntries and GetQuestLogTitle then
        for i = 1, GetNumQuestLogEntries() do
            local title, level, group, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
            if title then
                out[#out + 1] = { title = title, level = level, questID = questID, header = isHeader,
                                  complete = (isComplete == 1 or isComplete == true), group = group }
            end
        end
    end
    return out
end

function C.QuestRewardXP(questID)
    -- The old API only reports the selected quest, so only trust the modern one.
    if not (C_QuestLog and C_QuestLog.GetInfo) or not GetQuestLogRewardXP or not questID then return 0 end
    local ok, xp = pcall(GetQuestLogRewardXP, questID)
    return ok and xp or 0
end
