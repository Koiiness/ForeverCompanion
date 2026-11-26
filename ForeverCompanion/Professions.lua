-- Professions: skill levels, known recipes (recorded when you open a
-- profession window), the reagents those recipes use, and skill-up tips.
local _, ns = ...
local C, D = ns.C, ns.Data
local PR = {}
ns.Professions = PR

local DIFF = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }
local DIFF_COLOR = { optimal = "ff8040", medium = "ffff00", easy = "40c040", trivial = "808080" }
PR.DiffColor = DIFF_COLOR

function PR.SnapshotSkills()
    if not ns.char then return end
    ns.char.professions = C.GetProfessions()
    ns:Fire("PROFESSIONS_CHANGED")
end

function PR.Rank(name)
    for _, p in ipairs(ns.char and ns.char.professions or {}) do
        if p.name == name then return p.rank, p.max end
    end
end

-- Strip color codes and line breaks from game text ("|cffffd200Vendor:|r Name|n...").
function PR.CleanText(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", ", "):gsub("\n", ", ")
    s = s:gsub("|T.-|t", ""):gsub("%s+", " "):gsub(",%s*,", ","):gsub("^[,%s]+", ""):gsub("[,%s]+$", "")
    return s
end

local announced = {}
local function store(profName, recipes)
    if not profName or profName == "" or not next(recipes) then
        ns:Debug("recipe scan found nothing yet for", profName)
        return
    end
    ns.char.recipes[profName] = { list = recipes, t = time() }
    local known, total = 0, 0
    for _, r in pairs(recipes) do
        total = total + 1
        if r.learned ~= false then known = known + 1 end
    end
    if not announced[profName] then
        announced[profName] = true
        ns:Print(string.format("recorded %d known %s recipes (%d more you can still learn).", known, profName, total - known))
    end
    PR.SnapshotSkills()
end

local function addReagent(id) if id then ns.char.reagents[id] = true end end

----------------------------------------------------------------------
-- Modern trade skill UI
----------------------------------------------------------------------
local function scanModern()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return false end
    if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
        or (T.IsNPCCrafting and T.IsNPCCrafting()) then return true end
    local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    local profName = base and base.professionName
    if not profName and T.GetTradeSkillLine then profName = select(2, T.GetTradeSkillLine()) end
    if not profName and GetProfessions then
        -- Fall back to the profession whose window is open.
        local child = T.GetChildProfessionInfo and T.GetChildProfessionInfo()
        profName = child and (child.parentProfessionName or child.professionName)
    end
    local recipes = {}
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        local info = T.GetRecipeInfo(id)
        local item
        if info and T.GetRecipeOutputItemData then
            local ok, o = pcall(T.GetRecipeOutputItemData, id)
            if ok and o then item = o.itemID or C.ItemID(o.hyperlink) end
        end
        if info and not item and T.GetRecipeItemLink then
            local ok, l = pcall(T.GetRecipeItemLink, id)
            if ok then item = C.ItemID(l) end
        end
        if info and not info.learned and info.name then
            local source
            if T.GetRecipeSourceText then
                local ok, txt = pcall(T.GetRecipeSourceText, id)
                if ok and txt then source = PR.CleanText(txt) end
            end
            recipes[info.name] = { learned = false, item = item, source = source }
        end
        if info and info.learned then
            recipes[info.name] = { diff = DIFF[info.relativeDifficulty] or "?", num = info.numAvailable or 0, item = item }
        end
        -- Materials for every recipe (learned or not), so unlearned ones can be
        -- costed too. Only learned recipes mark their materials as "keep".
        if info and info.name and recipes[info.name] then
            if T.GetRecipeSchematic then
                local ok, s = pcall(T.GetRecipeSchematic, id, false)
                if ok and s and s.reagentSlotSchematics then
                    local mats = {}
                    for _, slot in ipairs(s.reagentSlotSchematics) do
                        if info.learned then
                            for _, r in ipairs(slot.reagents or {}) do addReagent(r.itemID) end
                        end
                        local first = slot.reagents and slot.reagents[1]
                        if first and first.itemID and slot.required ~= false then
                            mats[#mats + 1] = { id = first.itemID, qty = slot.quantityRequired or 1 }
                        end
                    end
                    recipes[info.name].mats = mats
                end
            end
        end
    end
    store(profName, recipes)
    return true
end

----------------------------------------------------------------------
-- Classic trade skill and craft (Enchanting) windows
----------------------------------------------------------------------
local function scanLegacyTrade()
    if not (GetNumTradeSkills and GetTradeSkillInfo and GetTradeSkillLine) then return end
    local profName = GetTradeSkillLine()
    if not profName or profName == "UNKNOWN" then return end
    local recipes = {}
    for i = 1, GetNumTradeSkills() do
        local name, kind, num = GetTradeSkillInfo(i)
        if name and kind ~= "header" and kind ~= "subheader" then
            local mats = {}
            recipes[name] = { diff = kind, num = num or 0, item = GetTradeSkillItemLink and C.ItemID(GetTradeSkillItemLink(i)), mats = mats }
            for j = 1, (GetTradeSkillNumReagents and GetTradeSkillNumReagents(i) or 0) do
                local rid = C.ItemID(GetTradeSkillReagentItemLink(i, j))
                addReagent(rid)
                local _, _, count = GetTradeSkillReagentInfo(i, j)
                if rid then mats[#mats + 1] = { id = rid, qty = count or 1 } end
            end
        end
    end
    store(profName, recipes)
end

local function scanLegacyCraft()
    if not (GetNumCrafts and GetCraftInfo) then return end
    local profName = GetCraftDisplaySkillLine and GetCraftDisplaySkillLine()
    if not profName then return end
    local recipes = {}
    for i = 1, GetNumCrafts() do
        local name, _, kind, num = GetCraftInfo(i)
        if name and kind ~= "header" then
            local mats = {}
            recipes[name] = { diff = kind, num = num or 0, mats = mats }
            for j = 1, (GetCraftNumReagents and GetCraftNumReagents(i) or 0) do
                local rid = C.ItemID(GetCraftReagentItemLink(i, j))
                addReagent(rid)
                local _, _, count = GetCraftReagentInfo(i, j)
                if rid then mats[#mats + 1] = { id = rid, qty = count or 1 } end
            end
        end
    end
    store(profName, recipes)
end

local function scanTrade()
    if not scanModern() then scanLegacyTrade() end
end

ns:Listen("READY", function() ns:Debounce("skills", 3, PR.SnapshotSkills) end)
ns:On("SKILL_LINES_CHANGED", function() ns:Debounce("skills", 1, PR.SnapshotSkills) end)
ns:On("TRADE_SKILL_SHOW", function() ns:Debounce("trade", 1, scanTrade) end)
ns:On("TRADE_SKILL_LIST_UPDATE", function() ns:Debounce("trade", 1, scanTrade) end)
ns:On("TRADE_SKILL_DATA_SOURCE_CHANGED", function() ns:Debounce("trade", 1, scanTrade) end)
ns:On("TRADE_SKILL_UPDATE", function() ns:Debounce("trade", 1, scanTrade) end)
ns:On("CRAFT_SHOW", function() ns:Debounce("craft", 1, scanLegacyCraft) end)
ns:On("CRAFT_UPDATE", function() ns:Debounce("craft", 1, scanLegacyCraft) end)

----------------------------------------------------------------------
-- Advice
----------------------------------------------------------------------
-- Recipes that still give skill-ups, best first.
function PR.SkillUps(profName)
    local rec = ns.char.recipes[profName]
    if not rec then return {} end
    local order = { optimal = 1, medium = 2, easy = 3 }
    local out = {}
    for name, r in pairs(rec.list) do
        if r.learned ~= false and order[r.diff] then out[#out + 1] = { name = name, diff = r.diff, num = r.num } end
    end
    table.sort(out, function(a, b)
        if order[a.diff] ~= order[b.diff] then return order[a.diff] < order[b.diff] end
        if (a.num > 0) ~= (b.num > 0) then return a.num > 0 end
        return a.name < b.name
    end)
    return out
end

-- Trainer reminder when you are capped at a tier.
function PR.TrainerHint(p)
    if not p.max or not p.rank then return end
    local level = UnitLevel("player")
    for _, tier in ipairs(D.ProfessionTiers) do
        if p.max == tier.max and p.rank >= p.max - 10 then
            if level >= tier.level then
                return "Visit a trainer to learn " .. tier.next .. "."
            end
            return tier.next .. " unlocks at level " .. tier.level .. "."
        end
    end
end

----------------------------------------------------------------------
-- Craft plan: materials (needed / in bags / cost) and what to do with
-- the item once made.
----------------------------------------------------------------------
local function holdings()
    local have = {}
    for _, where in ipairs({ "bags", "bank" }) do
        for _, item in ipairs(ns.char and ns.char[where] or {}) do
            if item.id then have[item.id] = (have[item.id] or 0) + (item.count or 1) end
        end
    end
    return have
end

-- Returns { matsText, matsCost, costKnown, canMake, result (Disposition), value, profit, verdict }
function PR.Plan(r)
    local have = holdings()
    local parts, cost, known, canMake = {}, 0, true, true
    for _, m in ipairs(r.mats or {}) do
        local name = C.GetItemInfo(m.id) or ("item " .. m.id)
        if not C.GetItemInfo(m.id) then C.RequestLoad(m.id) end
        local h = have[m.id] or 0
        local price = ns.Prices.Market(m.id)
        if price then cost = cost + price * m.qty else known = false end
        if h < m.qty then canMake = false end
        parts[#parts + 1] = string.format("%dx %s %s", m.qty, name,
            h >= m.qty and ("|cff4cff4c(have " .. h .. ")|r") or ("|cffff6060(have " .. h .. ")|r"))
    end
    local plan = { matsText = #parts > 0 and table.concat(parts, ", ") or "materials not recorded yet",
                   matsCost = cost, costKnown = known and #parts > 0, canMake = canMake and #parts > 0 }
    if r.item then
        local a = ns.Disposition.Evaluate({ id = r.item, count = 1 })
        plan.result = a
        if a then
            local DS = ns.Disposition
            if a.cmp and not a.cmp.unusable and not a.cmp.partial and a.cmp.delta > 0.5 then
                plan.verdict = string.format("|cff4cff4cEquip it|r (+%.1f for %s)", a.cmp.delta, ns:SpecLabel())
            else
                plan.value = (a.action == "AH" and a.ah) or (a.action == "DE" and a.de) or (a.action == "VENDOR" and a.vendor) or nil
                plan.verdict = DS.Labels[a.action] .. (plan.value and (" ~" .. ns.Money(plan.value)) or "")
                    .. (a.reason and ("|cff9a9a9a (" .. a.reason .. ")|r") or "")
                if plan.value and plan.costKnown then plan.profit = plan.value - cost end
            end
        end
    end
    return plan
end

-- Known recipes that make money, most profitable first.
function PR.Profitable(profName, limit)
    local rec = ns.char.recipes[profName]
    local out = {}
    for name, r in pairs(rec and rec.list or {}) do
        if r.learned ~= false and r.item then
            local plan = PR.Plan(r)
            if plan.profit and plan.profit > 0 then out[#out + 1] = { name = name, r = r, plan = plan } end
        end
    end
    table.sort(out, function(a, b)
        if a.plan.profit ~= b.plan.profit then return a.plan.profit > b.plan.profit end
        return a.name < b.name
    end)
    for i = #out, (limit or 5) + 1, -1 do out[i] = nil end
    return out
end

-- Materials as one readable line: icon, amount and name, green when you
-- have enough, red with what you have when you don't.
function PR.MatsLine(r)
    if not r.mats or #r.mats == 0 then return "|cff9a9a9amaterials not recorded yet|r" end
    local have = holdings()
    local parts = {}
    for _, m in ipairs(r.mats) do
        local name = C.GetItemInfo(m.id)
        if not name then C.RequestLoad(m.id) end
        local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(m.id)) or (GetItemIcon and GetItemIcon(m.id))
        local h = have[m.id] or 0
        local text = string.format("%d %s", m.qty, name or "...")
        if h >= m.qty then text = "|cffd0ffd0" .. text .. "|r"
        else text = "|cffff8080" .. text .. "|r |cff9a9a9a(have " .. h .. ")|r" end
        parts[#parts + 1] = (icon and ("|T" .. icon .. ":14:14|t ") or "") .. text
    end
    return table.concat(parts, "   ")
end

-- Short verdict for the right side: text, plus a longer explanation.
function PR.Verdict(plan)
    local a = plan.result
    if not a then return "|cff9a9a9a?|r", "Crafted item not recorded yet" end
    if a.cmp and not a.cmp.unusable and not a.cmp.partial and a.cmp.delta > 0.5 then
        local why = ns.Gear.Why(select(2, C.GetItemInfo(a.id)) or a.link, a.cmp)
        return string.format("|cff4cff4cEquip +%.1f|r", a.cmp.delta), "Upgrade for you" .. (why and (": " .. why) or "")
    end
    local label = ({ AH = "|cffffd700Auction|r", DE = "|cffb070ffDisenchant|r", VENDOR = "|cffc0c0c0Vendor|r", KEEP = "|cff40c0ffKeep|r" })[a.action] or a.action
    local short = label .. (plan.value and (" " .. ns.Money(plan.value)) or "")
    local long = (a.reason and (a.reason:sub(1, 1):upper() .. a.reason:sub(2)) or "")
    if plan.profit then
        local p = plan.profit >= 0 and ("|cff4cff4cprofit " .. ns.Money(plan.profit) .. "|r") or ("|cffff6060loss " .. ns.Money(-plan.profit) .. "|r")
        long = (long ~= "" and (long .. ", ") or "") .. p .. " after materials (~" .. ns.Money(plan.matsCost) .. ")"
    elseif plan.costKnown then
        long = (long ~= "" and (long .. ", ") or "") .. "materials ~" .. ns.Money(plan.matsCost)
    end
    return short, long
end

-- Recipes you don't know yet that are worth getting: ones that make an
-- upgrade for you, then ones that make money. Each with where to get it.
function PR.ToGet(profName, limit)
    local rec = ns.char.recipes[profName]
    local out = {}
    for name, r in pairs(rec and rec.list or {}) do
        if r.learned == false and r.item then
            local plan = PR.Plan(r)
            local a = plan.result
            local upgrade = a and a.cmp and not a.cmp.unusable and not a.cmp.partial and a.cmp.delta > 0.5
            local profit = plan.profit and plan.profit > 0 and plan.profit or nil
            if upgrade or profit then
                local where, cost = {}, nil
                if r.source and r.source ~= "" then where[#where + 1] = r.source end
                local qdText = ns.QuestDB and ns.QuestDB.PatternSourceText(name)
                if qdText then where[#where + 1] = qdText end
                local favor = r.source and (tonumber(r.source:match("Cost:%s*(%d+)")))
                if favor and ns.Crates and r.source and (r.source:find("Favor") or r.source:find("Cost")) then cost = favor .. " Favor" end
                local patternID, patternPrice = ns.Prices.PatternFor(name)
                if patternPrice then
                    where[#where + 1] = "pattern on the AH ~" .. ns.Money(patternPrice)
                    cost = cost or ("~" .. ns.Money(patternPrice))
                end
                local drop = ns.Research and ns.Research.PatternDrop(name)
                if drop then
                    where[#where + 1] = "drops in " .. drop.instance .. (drop.boss and (", " .. drop.boss) or "")
                        .. (drop.rate and (" " .. ns.Research.FormatRate(drop.rate)) or "")
                end
                out[#out + 1] = { name = name, r = r, plan = plan, upgrade = upgrade, delta = upgrade and a.cmp.delta or 0,
                                  profit = profit, where = #where > 0 and table.concat(where, "; ") or "source unknown", cost = cost }
            end
        end
    end
    table.sort(out, function(x, y)
        if x.upgrade ~= y.upgrade then return x.upgrade end
        if x.delta ~= y.delta then return x.delta > y.delta end
        if (x.profit or 0) ~= (y.profit or 0) then return (x.profit or 0) > (y.profit or 0) end
        return x.name < y.name
    end)
    for i = #out, (limit or 6) + 1, -1 do out[i] = nil end
    return out
end

function PR.Recipe(profName, recipeName)
    local rec = ns.char.recipes[profName]
    return rec and rec.list[recipeName]
end

function PR.IsReagent(itemID) return ns.char and ns.char.reagents[itemID] or false end

ns:Command("prof", "show professions, skill-up recipes and trainer reminders", function()
    PR.SnapshotSkills()
    for _, p in ipairs(ns.char.professions) do
        print(string.format("  |cffffff00%s|r %d/%d", p.name, p.rank or 0, p.max or 0))
        local hint = PR.TrainerHint(p)
        if hint then print("    " .. hint) end
        local ups = PR.SkillUps(p.name)
        for i = 1, math.min(3, #ups) do
            print(string.format("    |cff%s%s|r%s", DIFF_COLOR[ups[i].diff], ups[i].name,
                ups[i].num > 0 and (" (can make " .. ups[i].num .. ")") or ""))
        end
        if not ns.char.recipes[p.name] then print("    Open this profession once to record its recipes.") end
    end
end)

----------------------------------------------------------------------
-- Cleanup: keep each character's recipe data consistent with its own
-- professions. Early versions could mix characters' data together.
----------------------------------------------------------------------
function PR.Cleanup(char)
    char = char or ns.char
    if not char then return end
    local have = {}
    for _, p in ipairs(char.professions or {}) do have[p.name] = true end
    -- Only prune once professions are known (they load a moment after login).
    if next(have) then
        for prof in pairs(char.recipes or {}) do
            if not have[prof] then
                char.recipes[prof] = nil
                ns:Debug("removed", prof, "recipes that belonged to another character")
            end
        end
    end
    -- Materials this character uses: rebuilt from its own learned recipes.
    local reagents = {}
    for _, rec in pairs(char.recipes or {}) do
        for _, r in pairs(rec.list or {}) do
            if r.learned ~= false then
                for _, m in ipairs(r.mats or {}) do reagents[m.id] = true end
            end
        end
    end
    char.reagents = reagents
end

ns:Listen("PROFESSIONS_CHANGED", function() PR.Cleanup() end)
