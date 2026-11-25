-- Gear: item scoring with class/role stat weights, upgrade checks and a
-- snapshot of what is equipped.
local _, ns = ...
local C, D = ns.C, ns.Data
local G = {}
ns.Gear = G

----------------------------------------------------------------------
-- Spec and role. Roles are Tank, Healer or DPS; the spec (Shadow, Fire,
-- Feral (Bear)...) decides which stat weights apply.
----------------------------------------------------------------------
local function myClass() return ns.char and ns.char.class or select(2, UnitClass("player")) end
local function firstWord(s) return s and s:lower():match("^(%a+)") end

local function matchSpec(specs, name)
    local w = firstWord(name)
    if not w then return end
    for _, s in ipairs(specs) do
        if firstWord(s.name) == w then return s end
    end
end

local specCache, specCacheTime

local function specForTree(specs, tree)
    for _, sp in ipairs(specs) do if sp.tree == tree then return sp end end
end

-- Spell names in your spellbook (talents that give abilities show up here).
local function spellbookNames()
    local names = {}
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemName then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
            if line then
                for j = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                    local n = C_SpellBook.GetSpellBookItemName(j, bank)
                    if n then names[#names + 1] = n end
                end
            end
        end
    elseif GetNumSpellTabs and GetSpellTabInfo then
        local getName = GetSpellBookItemName or GetSpellName
        for i = 1, GetNumSpellTabs() do
            local _, _, offset, num = GetSpellTabInfo(i)
            for j = offset + 1, offset + num do
                local n = getName and getName(j, BOOKTYPE_SPELL or "spell")
                if n then names[#names + 1] = n end
            end
        end
    end
    return names
end

-- Returns spec, explanation of how it was found, and whether it's a guess.
local function detectSpec()
    local class = myClass()
    local specs = D.Specs[class]
    if not specs then return { name = "Unknown", role = "DPS", w = "dps" }, "unknown class", true end
    local lookup = D.TalentTree[class] or {}
    local treeNames = {}
    for _, sp in ipairs(specs) do treeNames[sp.tree] = treeNames[sp.tree] or sp.name end

    -- 1. Talents you've taken, matched by name to their classic tree.
    local talents = C.GetTalentTrees()
    if talents then
        local votes, total = { 0, 0, 0 }, 0
        for _, tree in ipairs(talents.trees) do
            for _, t in ipairs(tree.talents) do
                local idx = t.rank > 0 and lookup[t.name:lower()]
                if idx then votes[idx] = votes[idx] + t.rank total = total + t.rank end
            end
        end
        if total > 0 then
            local best = 1
            for i = 2, 3 do if votes[i] > votes[best] then best = i end end
            return specForTree(specs, best), string.format("from your talents (%d of %d points in %s)",
                votes[best], total, treeNames[best] or "?"), false
        end
        -- 2. Talents with points, but names we don't know: use the tree they're in.
        local bestTree, bestIdx, bestPts = nil, nil, 0
        for i, tree in ipairs(talents.trees) do
            if tree.points > bestPts then bestTree, bestIdx, bestPts = tree, i, tree.points end
        end
        if bestTree then
            local s = matchSpec(specs, bestTree.name)
            if s then return s, "from your talent tree (" .. bestPts .. " points in " .. bestTree.name .. ")", false end
            if #talents.trees == 3 then return specForTree(specs, bestIdx), "from your talent tree layout", false end
        end
    end

    -- 3. Talent abilities in your spellbook (Inner Focus, Power Infusion...).
    local ok, names = pcall(spellbookNames)
    if ok then
        local votes, total = { 0, 0, 0 }, 0
        for _, n in ipairs(names) do
            local idx = lookup[n:lower()]
            if idx then votes[idx] = votes[idx] + 1 total = total + 1 end
        end
        if total > 0 then
            local best = 1
            for i = 2, 3 do if votes[i] > votes[best] then best = i end end
            return specForTree(specs, best), "from talent abilities in your spellbook", false
        end
    end

    -- 4. The game's specialization, if it has one.
    local specName = C.GetSpecialization()
    local s = matchSpec(specs, specName)
    if s then return s, "from your specialization", false end

    -- 5. Nothing found: assume the recommended leveling spec, and say so.
    local build = D.LevelingBuilds[class]
    return (build and specForTree(specs, build.tree)) or specs[1],
        "guessed: no talent points could be read. Pick your spec on the Gear page", true
end

-- Returns spec, chosen-by-hand flag, how it was detected, guessed flag.
local specHow, specGuess
function ns:GetSpec()
    local specs = D.Specs[myClass()] or {}
    local override = ns.db and ns.db.settings.specOverride
    if override then
        for _, s in ipairs(specs) do if s.name == override then return s, true, "chosen by you", false end end
    end
    if not specCache then
        local before = ns.lastSpecName
        specCache, specHow, specGuess = detectSpec()
        ns.lastSpecName = specCache.name
        if before and before ~= specCache.name and ns.Research then ns.Research.Invalidate() end
        specCacheTime = GetTime()
    end
    return specCache, false, specHow, specGuess
end
function ns:InvalidateSpec() specCache = nil end

-- Internal stat-weight key for the current spec.
function ns:GetRole() return (ns:GetSpec()).w end
function ns:SpecLabel()
    local s, _, _, guess = ns:GetSpec()
    return s.name .. " (" .. s.role .. ")" .. (guess and "?" or "")
end

-- arg: "tank", "healer", "dps", a spec name ("fire", "bear"), or "auto".
function ns:SetSpec(arg)
    arg = (arg or ""):lower()
    local specs = D.Specs[myClass()] or {}
    if arg == "" or arg == "auto" then ns.db.settings.specOverride = nil return true end
    local want = ({ tank = "Tank", healer = "Healer", heal = "Healer", dps = "DPS" })[arg]
    local pick
    if want then
        ns.db.settings.specOverride = nil
        local auto = ns:GetSpec()
        if auto.role == want then pick = auto end
        if not pick then
            local build = D.LevelingBuilds[myClass()]
            for _, s in ipairs(specs) do
                if s.role == want and (not pick or (build and s.tree == build.tree)) then pick = s end
            end
        end
    else
        for _, s in ipairs(specs) do
            if s.name:lower():find(arg, 1, true) then pick = s break end
        end
    end
    if not pick then return false end
    ns.db.settings.specOverride = pick.name
    return true
end

for _, ev in ipairs({ "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED",
                      "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
                      "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
    ns:On(ev, function() ns:InvalidateSpec() end)
end

function G.Weights()
    local class = myClass()
    local role = ns:GetRole()
    local byClass = D.Weights[class]
    return (byClass and byClass[role]) or D.Weights.GENERIC[role] or D.Weights.GENERIC.dps, role
end

----------------------------------------------------------------------
-- Stats
----------------------------------------------------------------------
local STAT_KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi",
    ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
    ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
    ITEM_MOD_CRIT_RATING_SHORT = "critRating", ITEM_MOD_HIT_RATING_SHORT = "hitRating",
    ITEM_MOD_HASTE_RATING_SHORT = "haste", ITEM_MOD_MASTERY_RATING_SHORT = "mastery",
    ITEM_MOD_VERSATILITY = "vers", RESISTANCE0_NAME = "armor",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def", ITEM_MOD_DODGE_RATING_SHORT = "dodgeRating",
    ITEM_MOD_PARRY_RATING_SHORT = "parryRating", ITEM_MOD_BLOCK_RATING_SHORT = "blockRating",
    ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_POWER_REGEN0_SHORT = "mp5",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
}
-- Classic-style "Equip:" effects that are not reported as item stats.
local TEXT_PATTERNS = {
    { "critical strike with spells by (%d+)%%", "crit" },
    { "chance to get a critical strike by (%d+)%%", "crit" },
    { "chance to hit with spells by (%d+)%%", "hit" },
    { "chance to hit by (%d+)%%", "hit" },
    { "damage and healing done by magical spells and effects by up to (%d+)", "sp" },
    { "healing done by spells and effects by up to (%d+)", "heal" },
    { "^Equip: %+(%d+) ranged Attack Power", "rap" },
    { "^Equip: %+(%d+) Attack Power", "ap" },
    { "[Rr]estores (%d+) mana per 5 sec", "mp5" },
    { "Increased Defense %+(%d+)", "def" },
    { "chance to dodge an attack by (%d+)%%", "dodge" },
    { "chance to parry an attack by (%d+)%%", "parry" },
    { "chance to block attacks with a shield by (%d+)%%", "block" },
}
-- Ratings converted to percent with a rough level-60 conversion.
local RATING_PER_PCT = { critRating = { "crit", 14 }, hitRating = { "hit", 10 },
                         dodgeRating = { "dodge", 12 }, parryRating = { "parry", 20 }, blockRating = { "block", 5 } }

-- Returns stats and whether they're complete. Items whose data hasn't
-- loaded yet aren't cached, so they get re-read instead of keeping a
-- half-finished score (which made recommendations flicker).
local statCache = {}
function G.Stats(link)
    if not link then return {}, true end
    if statCache[link] then return statCache[link], true end
    local out = {}
    for k, v in pairs(C.GetItemStats(link)) do
        local key = STAT_KEYS[k]
        if key then out[key] = (out[key] or 0) + v end
    end
    for key, conv in pairs(RATING_PER_PCT) do
        if out[key] then out[conv[1]] = (out[conv[1]] or 0) + out[key] / conv[2]; out[key] = nil end
    end
    local fromText = {}
    local lines, tipComplete = C.TooltipLines(link)
    for _, line in ipairs(lines) do
        for _, p in ipairs(TEXT_PATTERNS) do
            local n = line:match(p[1])
            if n then fromText[p[2]] = (fromText[p[2]] or 0) + tonumber(n); break end
        end
    end
    for k, v in pairs(fromText) do
        if not out[k] then out[k] = v end
    end
    local complete = tipComplete and C.GetItemInfo(link) ~= nil
    if complete then statCache[link] = out end
    return out, complete
end

-- Returns score and whether the item data was complete.
function G.Score(link, weights)
    if not link then return 0, true end
    weights = weights or G.Weights()
    local stats, complete = G.Stats(link)
    local total = 0
    for stat, value in pairs(stats) do
        total = total + value * (weights[stat] or 0)
    end
    return total, complete
end

----------------------------------------------------------------------
-- Set bonuses
----------------------------------------------------------------------
local STAT_WORDS = { strength = "str", agility = "agi", stamina = "sta", intellect = "int", spirit = "spi",
    armor = "armor", ["attack power"] = "ap", ["ranged attack power"] = "rap", ["spell power"] = "sp",
    defense = "def", ["all stats"] = "all" }

-- Stats described in an effect line such as "Set: +8 Spirit." or
-- "Set: Increases healing done by spells and effects by up to 22."
function G.EffectStats(text)
    local out = {}
    for _, p in ipairs(TEXT_PATTERNS) do
        if p[1]:sub(1, 1) ~= "^" then
            local n = text:match(p[1])
            if n then out[p[2]] = (out[p[2]] or 0) + tonumber(n) end
        end
    end
    for n, word in text:gmatch("%+(%d+) ([%a ]+)") do
        local key = STAT_WORDS[word:lower():gsub("%s+$", "")]
        if key == "all" then
            for _, k in ipairs({ "str", "agi", "sta", "int", "spi" }) do out[k] = (out[k] or 0) + tonumber(n) end
        elseif key then
            out[key] = (out[key] or 0) + tonumber(n)
        end
    end
    return out
end

-- Set name, pieces equipped, total pieces and bonuses from an item's tooltip.
local setCache = {}
function G.SetInfo(link)
    if not link then return end
    local cached = setCache[link]
    if cached ~= nil then return cached or nil end
    local lines, complete = C.TooltipLines(link)
    local info = { bonuses = {} }
    for _, l in ipairs(lines) do
        local n, have, total = l:match("^(.-) %((%d+)/(%d+)%)$")
        if n and not info.name then info.name, info.have, info.total = n, tonumber(have), tonumber(total) end
        local need, txt = l:match("^%((%d+)%) Set: (.+)$")
        if need then info.bonuses[#info.bonuses + 1] = { need = tonumber(need), text = txt } end
    end
    if not info.name then info = false end
    if complete then setCache[link] = info end
    return info or nil
end

-- Value of a set bonus for your spec. Effects that aren't plain stats
-- (procs, cooldown changes) count as a quarter of an average equipped item.
function G.BonusValue(text, weights)
    local total = 0
    for stat, v in pairs(G.EffectStats(text)) do total = total + v * (weights[stat] or 0) end
    if total > 0 then return total, true end
    local sum, n = 0, 0
    for _, g in pairs(ns.char and ns.char.gear or {}) do sum, n = sum + (g.score or 0), n + 1 end
    return n > 0 and (sum / n) * 0.25 or 3, false
end

-- What you'd lose by unequipping the item in `slot`: value, set name, bonus text.
function G.SetLoss(slot, weights, replacementLink)
    local link = GetInventoryItemLink("player", slot)
    local info = G.SetInfo(link)
    if not info or not info.have then return 0 end
    local rep = replacementLink and G.SetInfo(replacementLink)
    if rep and rep.name == info.name then return 0 end  -- swapping within the same set
    local loss, lost = 0, {}
    for _, b in ipairs(info.bonuses) do
        if b.need == info.have then
            loss = loss + G.BonusValue(b.text, weights)
            lost[#lost + 1] = b.text
        end
    end
    return loss, info.name, info.have, table.concat(lost, "; ")
end

ns:On("PLAYER_EQUIPMENT_CHANGED", function() wipe(setCache) end)

----------------------------------------------------------------------
-- Can the player use it?
----------------------------------------------------------------------
local function maxArmorType(class, level)
    local best = 1
    for sub, lvl in pairs(D.ArmorBest[class] or {}) do
        if level >= lvl and sub > best then best = sub end
    end
    return best
end

-- Returns usable (bool), reason (string or nil), levelRequired
function G.CanUse(link)
    local _, _, _, _, reqLevel, _, _, _, equipLoc, _, _, classID, subclassID = C.GetItemInfo(link)
    if not equipLoc or equipLoc == "" then return false, "not equippable" end
    local class = ns.char and ns.char.class or select(2, UnitClass("player"))
    local level = UnitLevel("player")
    if classID == 4 and subclassID and subclassID >= 1 and subclassID <= 4 and equipLoc ~= "INVTYPE_CLOAK" then
        if subclassID > maxArmorType(class, 999) then return false, "wrong armor type" end
    end
    if classID == 2 and D.WeaponSkills[class] and not D.WeaponSkills[class][subclassID] then
        return false, "your class can't use this weapon type"
    end
    if equipLoc == "INVTYPE_SHIELD" and not (class == "WARRIOR" or class == "PALADIN" or class == "SHAMAN") then
        return false, "your class can't use shields"
    end
    if reqLevel and reqLevel > level then return true, "requires level " .. reqLevel, reqLevel end
    return true
end

local function canDualWield()
    if CanDualWield then return CanDualWield() end
    local class = ns.char and ns.char.class
    local lvl = D.DualWield[class]
    return lvl and UnitLevel("player") >= lvl
end

----------------------------------------------------------------------
-- Compare against what is equipped
----------------------------------------------------------------------
local function equippedLink(slot) return GetInventoryItemLink("player", slot) end

-- Returns { delta, pct, slot, current = link or nil, note } or nil when the
-- item isn't gear for this character.
function G.Compare(link)
    if not link then return end
    local usable, reason = G.CanUse(link)
    if not usable then return { delta = 0, note = reason, unusable = true } end
    local equipLoc = select(9, C.GetItemInfo(link))
    local slots = D.EquipSlots[equipLoc]
    if not slots then return end
    local weights = G.Weights()
    local newScore, complete = G.Score(link, weights)
    local cur, slot, curLink

    if equipLoc == "INVTYPE_2HWEAPON" then
        cur = G.Score(equippedLink(16), weights) + G.Score(equippedLink(17), weights)
        slot, curLink = 16, equippedLink(16)
    else
        local mh = equippedLink(16)
        local mhIs2H = mh and select(9, C.GetItemInfo(mh)) == "INVTYPE_2HWEAPON"
        if mhIs2H and (equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE") then
            return { delta = 0, note = "you use a two-hander" }
        end
        for _, s in ipairs(slots) do
            if not (s == 17 and equipLoc == "INVTYPE_WEAPON" and not canDualWield()) then
                local l = equippedLink(s)
                local sc = G.Score(l, weights)
                if not l then sc = 0 end
                if cur == nil or sc < cur then cur, slot, curLink = sc, s, l end
            end
        end
    end
    if not slot then return end
    if curLink == link then return { delta = 0, slot = slot, current = curLink, note = "equipped" } end
    -- Losing a set bonus counts against the replacement.
    local loss, setName, setHave, lostText = G.SetLoss(slot, weights, link)
    if equipLoc == "INVTYPE_2HWEAPON" then
        local l2 = G.SetLoss(17, weights, link)
        loss = loss + l2
    end
    local delta = newScore - (cur or 0) - loss
    local pct = (cur and cur > 0) and (delta / cur * 100) or nil
    local note = reason
    if loss > 0 and setName then
        local breaks = string.format("breaks %s %d-piece bonus (-%.1f)", setName, setHave, loss)
        note = note and (note .. "; " .. breaks) or breaks
    end
    return { delta = delta, pct = pct, slot = slot, current = curLink, note = note, partial = not complete,
             setLoss = loss, setName = setName, lostBonus = lostText }
end

----------------------------------------------------------------------
-- Snapshot of equipped gear
----------------------------------------------------------------------
function G.Snapshot()
    local char = ns.char
    if not char then return end
    local weights = G.Weights()
    char.gear = {}
    local sum, n = 0, 0
    for _, slot in ipairs(D.SlotOrder) do
        local link = equippedLink(slot)
        if link and link:find("%[%]") then C_Timer.After(2, function() ns:Debounce("gear", 0.5, G.Snapshot) end) end
        if link then
            local ilvl = C.EffectiveILvl(link) or 0
            local cur, max = GetInventoryItemDurability(slot)
            char.gear[slot] = { link = link, ilvl = ilvl, score = G.Score(link, weights),
                                dura = (cur and max and max > 0) and (cur / max) or nil }
            sum, n = sum + ilvl, n + 1
        end
    end
    char.avgIlvl = n > 0 and (sum / n) or 0
    char.level = UnitLevel("player")
    ns:Fire("GEAR_CHANGED")
end

-- Upgrades sitting in your bags (from the bag snapshot).
----------------------------------------------------------------------
-- Why: the stat changes behind a comparison, biggest impact first.
-- e.g. "+12 Intellect, +6 Spirit, -4 Stamina, loses Rotmender's 4-piece bonus"
----------------------------------------------------------------------
local function fmtStat(key, d)
    local name = D.StatNames[key] or key
    if D.PercentStats[key] then return string.format("%+.1f%% %s", d, name):gsub("%.0%%", "%%") end
    if key == "dps" then return string.format("%+.1f %s", d, name) end
    return string.format("%+d %s", math.floor(d + (d >= 0 and 0.5 or -0.5)), name)
end

-- Returns a colored, comma-separated explanation (or nil), and a plain list.
function G.Why(link, cmp, limit)
    if not (link and cmp and cmp.slot) or cmp.unusable then return end
    limit = limit or 4
    local weights = G.Weights()
    local new = G.Stats(link)
    local old = {}
    local function addFrom(l)
        if not l then return end
        for k, v in pairs(G.Stats(l)) do old[k] = (old[k] or 0) + v end
    end
    if select(9, C.GetItemInfo(link)) == "INVTYPE_2HWEAPON" then
        addFrom(GetInventoryItemLink("player", 16))
        addFrom(GetInventoryItemLink("player", 17))
    else
        addFrom(cmp.current)
    end
    local diffs, keys = {}, {}
    for k in pairs(new) do keys[k] = true end
    for k in pairs(old) do keys[k] = true end
    for k in pairs(keys) do
        local d = (new[k] or 0) - (old[k] or 0)
        local w = d * (weights[k] or 0)
        if math.abs(d) > 0.05 and w ~= 0 then diffs[#diffs + 1] = { k = k, d = d, w = w } end
    end
    table.sort(diffs, function(a, b)
        if math.abs(a.w) ~= math.abs(b.w) then return math.abs(a.w) > math.abs(b.w) end
        return a.k < b.k
    end)
    local parts, plain = {}, {}
    if not cmp.current then
        parts[#parts + 1] = "|cff4cff4cfills an empty slot|r"
        plain[#plain + 1] = "fills an empty slot"
    end
    for i = 1, math.min(limit, #diffs) do
        local x = diffs[i]
        local s = fmtStat(x.k, x.d)
        parts[#parts + 1] = (x.w > 0 and "|cff4cff4c" or "|cffff6060") .. s .. "|r"
        plain[#plain + 1] = s
    end
    if (cmp.setLoss or 0) > 0 and cmp.setName then
        local s = "loses " .. cmp.setName .. " set bonus"
        parts[#parts + 1] = "|cffff6060" .. s .. "|r"
        plain[#plain + 1] = s
    end
    local newIlvl, oldIlvl = C.EffectiveILvl(link), cmp.current and C.EffectiveILvl(cmp.current)
    if newIlvl and oldIlvl and newIlvl ~= oldIlvl then
        parts[#parts + 1] = string.format("|cff9a9a9a%+d item levels|r", newIlvl - oldIlvl)
    end
    if #parts == 0 then return end
    return table.concat(parts, ", "), plain
end

function G.BagUpgrades()
    local out = {}
    local seen = {}
    for _, item in ipairs(ns.char and ns.char.bags or {}) do
        if item.link and not seen[item.link] then
            seen[item.link] = true
            local cmp = G.Compare(item.link)
            if cmp and not cmp.unusable and not cmp.partial and cmp.delta > 0.5 then
                out[#out + 1] = { link = item.link, cmp = cmp }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.cmp.delta ~= b.cmp.delta then return a.cmp.delta > b.cmp.delta end
        return a.link < b.link
    end)
    return out
end

-- Slots whose item level lags your level (or are empty).
function G.WeakSlots()
    local level = UnitLevel("player")
    local out = {}
    for _, slot in ipairs(D.SlotOrder) do
        local g = ns.char.gear[slot]
        local relicClass = ns.char.class == "PALADIN" or ns.char.class == "SHAMAN" or ns.char.class == "DRUID"
        if slot ~= 18 or not relicClass then
            if not g then
                if slot ~= 17 or canDualWield() or ns.char.class == "PALADIN" or ns.char.class == "SHAMAN"
                    or ns.char.class == "WARRIOR" or ns.char.class == "PRIEST" or ns.char.class == "MAGE"
                    or ns.char.class == "WARLOCK" or ns.char.class == "DRUID" then
                    local mh = ns.char.gear[16]
                    local mhIs2H = mh and select(9, C.GetItemInfo(mh.link)) == "INVTYPE_2HWEAPON"
                    if not (slot == 17 and mhIs2H) then out[#out + 1] = { slot = slot, gap = level } end
                end
            elseif g.ilvl < level - 5 then
                out[#out + 1] = { slot = slot, gap = level - g.ilvl, link = g.link, ilvl = g.ilvl }
            end
        end
    end
    table.sort(out, function(a, b) return a.gap > b.gap end)
    return out
end

ns:Listen("READY", function() ns:Debounce("gear", 2, G.Snapshot) end)
ns:On("PLAYER_EQUIPMENT_CHANGED", function() ns:Debounce("gear", 0.5, G.Snapshot) end)
ns:On("UPDATE_INVENTORY_DURABILITY", function() ns:Debounce("gear", 1, G.Snapshot) end)
ns:On("PLAYER_LEVEL_UP", function() ns:Debounce("gear", 1, G.Snapshot) end)
ns:On("CHARACTER_POINTS_CHANGED", function() wipe(statCache) ns:Debounce("gear", 1, G.Snapshot) end)
ns:On("PLAYER_TALENT_UPDATE", function() ns:Debounce("gear", 1, G.Snapshot) end)

ns:Command("gear", "list gear upgrades in your bags and weakest slots", function()
    G.Snapshot()
    local ups = G.BagUpgrades()
    ns:Print(string.format("scoring for %s, average item level %.1f", ns:SpecLabel(), ns.char.avgIlvl or 0))
    if #ups == 0 then print("  No upgrades in your bags.") end
    for _, u in ipairs(ups) do
        print(string.format("  %s  +%.1f%s in %s", u.link, u.cmp.delta,
            u.cmp.pct and string.format(" (%.0f%%)", u.cmp.pct) or "", D.SlotNames[u.cmp.slot] or "?"))
    end
end)
