-- Crates: WoW Forever's Waylaid Crates. You fill a crate with materials,
-- it becomes a Sealed Crate, and turning that in gives Merchant's Favor,
-- which buys profession recipes. Unfilled crates can be sold on the AH;
-- sealed ones can't.
--
-- This module decides, per crate: keep and fill it (when Favor would buy
-- a recipe that makes gear you'd use) or sell it on the auction house.
-- Fill lists and Favor amounts come from community guides (wow.gg) and may
-- change; edit the tables below if the game disagrees.
local _, ns = ...
local C = ns.C
local CR = {}
ns.Crates = CR

-- Category aliases: guides and the game use different words.
local ALIAS = { curiosities = "oddities", fabrics = "cloth", ingots = "bars" }

-- What fills each crate: { item name, amount }. One option is enough.
CR.Fills = {
    Apprentice = {
        herbs = { { "Peacebloom", 20 }, { "Silverleaf", 20 }, { "Earthroot", 10 }, { "Mageroyal", 10 }, { "Briarthorn", 10 } },
        ore = { { "Copper Ore", 20 }, { "Tin Ore", 20 } },
        textiles = { { "Linen Cloth", 40 }, { "Light Leather", 20 } },
        oddities = { { "Strange Dust", 20 }, { "Greater Magic Essence", 4 }, { "Small Glimmering Shard", 6 }, { "Large Glimmering Shard", 2 } },
        cloth = { { "Bolt of Linen Cloth", 20 }, { "Cured Light Hide", 2 } },
        bars = { { "Copper Bar", 20 }, { "Tin Bar", 20 }, { "Bronze Bar", 10 } },
        parts = { { "Handful of Copper Bolts", 16 }, { "Copper Tube", 16 }, { "Copper Modulator", 4 } },
    },
    Journeyman = {
        textiles = { { "Wool Cloth", 20 }, { "Silk Cloth", 40 }, { "Medium Leather", 20 } },
        cloth = { { "Bolt of Woolen Cloth", 6 }, { "Bolt of Silk Cloth", 10 }, { "Cured Medium Hide", 2 } },
        bars = { { "Silver Bar", 10 }, { "Iron Bar", 20 } },
        parts = { { "Bronze Tube", 8 }, { "Whirring Bronze Gizmo", 7 }, { "Bronze Framework", 4 }, { "Gold Power Core", 45 } },
    },
}
-- Merchant's Favor for a sealed crate: { white, green }.
CR.FavorByTier = { Apprentice = { 5, 10 }, Journeyman = { 10, 20 } }
CR.LevelByTier = { Apprentice = 10, Journeyman = 10, Expert = 20, Artisan = 35 }
CR.TurnIn = {
    Horde = "Dokimi at The Crossroads, Barrens (50, 29)",
    Alliance = "Marcy Baker at Three Corners, Redridge Mountains (10, 71)",
}
-- Recipe vendors that take Merchant's Favor (used to spot Favor recipes).
CR.Vendors = {
    "Nina Surefire", "Stondry Darkhammer", "Kalsey Sanden", "Alynsia", "Fritz Fizzle", "Daniel Stitchsong", "Mivin Shadowweave",
    "Apothecary Durelle", "Gor'mak", "Aza'bek", "Beneris", "Fizzlefuse", "Pawani", "Jim'bek",
}

----------------------------------------------------------------------
-- Parsing
----------------------------------------------------------------------
-- Returns { kind = "open" | "sealed" | "unlabeled", tier, category } or nil.
function CR.Parse(name)
    if not name then return end
    local tier, cat = name:match("^Waylaid Crate: (%a+) (.+)$")
    if tier then
        cat = cat:lower()
        return { kind = "open", tier = tier, category = ALIAS[cat] or cat, label = cat }
    end
    tier = name:match("^Sealed (%a+) Crate$")
    if tier then return { kind = "sealed", tier = tier } end
    if name == "Waylaid Crate" then return { kind = "unlabeled" } end
end

----------------------------------------------------------------------
-- Merchant's Favor balance
----------------------------------------------------------------------
function CR.Favor()
    local CI = C_CurrencyInfo
    if CI and CI.GetCurrencyListSize and CI.GetCurrencyListInfo then
        for i = 1, CI.GetCurrencyListSize() do
            local info = CI.GetCurrencyListInfo(i)
            if info and info.name and info.name:find("Merchant's Favor", 1, true) then
                if ns.char then ns.char.favor = info.quantity end
                return info.quantity
            end
        end
    end
    return ns.char and ns.char.favor
end

----------------------------------------------------------------------
-- Bag counts by item name
----------------------------------------------------------------------
local function bagCounts()
    local counts = {}
    for _, item in ipairs(ns.char and ns.char.bags or {}) do
        local name = item.link and item.link:match("%[(.-)%]")
        if name then counts[name] = (counts[name] or 0) + (item.count or 1) end
    end
    return counts
end

-- Fill options for a crate with what you have and what each costs.
function CR.FillOptions(info)
    local list = info.tier and CR.Fills[info.tier] and CR.Fills[info.tier][info.category]
    if not list then return end
    local have = bagCounts()
    local out = {}
    for _, f in ipairs(list) do
        local name, qty = f[1], f[2]
        local id
        for _, item in ipairs(ns.char.bags or {}) do
            if item.link and item.link:match("%[(.-)%]") == name then id = item.id break end
        end
        local price = id and ns.Prices.Market(id)
        out[#out + 1] = { name = name, qty = qty, have = have[name] or 0, cost = price and price * qty }
    end
    table.sort(out, function(a, b)
        local ar, br = a.have >= a.qty, b.have >= b.qty
        if ar ~= br then return ar end
        return (a.cost or math.huge) < (b.cost or math.huge)
    end)
    return out
end

-- True when the item is a fill material for a crate you're carrying.
function CR.FillsHeldCrate(name)
    if not name or not ns.char then return end
    for _, item in ipairs(ns.char.bags or {}) do
        local cname = item.link and item.link:match("%[(.-)%]")
        local info = CR.Parse(cname)
        if info and info.kind == "open" then
            local list = CR.Fills[info.tier] and CR.Fills[info.tier][info.category]
            for _, f in ipairs(list or {}) do
                if f[1] == name then return cname end
            end
        end
    end
end

----------------------------------------------------------------------
-- Favor recipes worth buying
----------------------------------------------------------------------
local function isFavorSource(src)
    if not src then return false end
    if src:find("Favor", 1, true) then return true end
    for _, v in ipairs(CR.Vendors) do
        if src:find(v, 1, true) then return true end
    end
    return false
end

-- Unlearned Favor recipes for your professions, with cost and whether they
-- make an upgrade for you. Best first.
local wantedCache, wantedTime
function CR.WantedRecipes()
    if wantedCache and GetTime() - wantedTime < 10 then return wantedCache end
    local out = {}
    wantedCache, wantedTime = out, GetTime()
    for prof, rec in pairs(ns.char and ns.char.recipes or {}) do
        for name, r in pairs(rec.list or {}) do
            if r.learned == false and isFavorSource(r.source) then
                local cost = r.source and (tonumber(r.source:match("Cost:%s*(%d+)")) or tonumber(r.source:match("(%d+)%s*Merchant's Favor")))
                local link = r.item and select(2, C.GetItemInfo(r.item))
                local cmp = link and ns.Gear.Compare(link)
                local upgrade = cmp and not cmp.unusable and not cmp.partial and cmp.delta > 0.5
                out[#out + 1] = { prof = prof, name = name, cost = cost, link = link, upgrade = upgrade,
                                  delta = upgrade and cmp.delta or 0 }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.upgrade ~= b.upgrade then return a.upgrade end
        if a.delta ~= b.delta then return a.delta > b.delta end
        return (a.cost or 999) < (b.cost or 999)
    end)
    return out
end

----------------------------------------------------------------------
-- Advice for one crate item
----------------------------------------------------------------------
-- a is the Disposition result so far (has a.ah, a.vendor). Returns action, reason.
function CR.Advice(name, quality, a)
    local info = CR.Parse(name)
    if not info then return end
    local faction = UnitFactionGroup("player")
    if info.kind == "sealed" then
        return "KEEP", "turn in to " .. (CR.TurnIn[faction] or "the crate quartermaster") .. " for Merchant's Favor"
    end
    if info.kind == "unlabeled" then
        return "KEEP", "right-click to read its label first"
    end

    local level = UnitLevel("player")
    local need = CR.LevelByTier[info.tier]
    local favorTbl = CR.FavorByTier[info.tier]
    local favor = favorTbl and (quality and quality >= 2 and favorTbl[2] or favorTbl[1])
    local fills = CR.FillOptions(info)
    local ready = fills and fills[1] and fills[1].have >= fills[1].qty and fills[1]
    local fillText = ""
    if ready then
        fillText = string.format("you have %d %s to fill it", ready.have, ready.name)
    elseif fills and fills[1] then
        local f = fills[1]
        fillText = string.format("fill with %d %s%s", f.qty, f.name, f.cost and (" (~" .. ns.Money(f.cost) .. ")") or "")
    end

    -- Is there a Favor recipe that makes gear you'd use?
    local wanted = CR.WantedRecipes()
    local goal = wanted[1] and wanted[1].upgrade and wanted[1] or nil
    local have = CR.Favor() or 0
    if goal and (not goal.cost or goal.cost > have) then
        local short = goal.cost and (" (" .. have .. "/" .. goal.cost .. " Favor)") or ""
        local why = "worth " .. (favor or "?") .. " Favor toward " .. goal.name .. short
        if need and level < need then why = why .. "; usable at level " .. need end
        return "KEEP", why .. (fillText ~= "" and ("; " .. fillText) or "")
    end
    -- No recipe to save for: sell it if the AH pays, otherwise keep for Favor.
    if a.ah and a.ah > (a.vendor or 0) then
        local fillCost = fills and fills[1] and fills[1].cost
        local note = "no Favor recipe you need right now"
        if fillCost and fillCost > a.ah then note = note .. "; filling would cost more than it sells for" end
        return "AH", note
    end
    return "KEEP", "fill for " .. (favor or "some") .. " Merchant's Favor" .. (fillText ~= "" and ("; " .. fillText) or "")
end

-- To-do items for the Overview page.
function CR.Todo()
    local sealed, fillable = 0, {}
    for _, item in ipairs(ns.char and ns.char.bags or {}) do
        local name = item.link and item.link:match("%[(.-)%]")
        local info = CR.Parse(name)
        if info and info.kind == "sealed" then sealed = sealed + (item.count or 1)
        elseif info and info.kind == "open" then
            local fills = CR.FillOptions(info)
            if fills and fills[1] and fills[1].have >= fills[1].qty then
                fillable[#fillable + 1] = { crate = name, with = fills[1] }
            end
        end
    end
    return sealed, fillable
end

ns:On("CURRENCY_DISPLAY_UPDATE", function() CR.Favor() end)
