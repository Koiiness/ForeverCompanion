-- Money: a gold plan across all your characters, from what the addon has
-- saved for each of them (bags, bank, gold, professions, recipes) and
-- auction prices.
--   * cash in: what each character holds that sells (grays, AH items)
--   * mail to your enchanter: unbound greens worth more disenchanted
--   * craft and sell: the most profitable recipes any character knows
--   * gather and sell: best-paying herbs, ore and leather each gatherer can get
local _, ns = ...
local C, D = ns.C, ns.Data
local MO = {}
ns.MoneyPlan = MO

local function rank(char, prof)
    for _, p in ipairs(char.professions or {}) do
        if p.name == prof then return p.rank or 0, p.max end
    end
end

local function cut() return 1 - (ns.db.settings.ahCutPct or 5) / 100 end

-- Value of an item on any character, without upgrade checks (those only
-- make sense for the character you're on).
function MO.ItemValue(item)
    local id = item.id
    local name, _, quality, _, reqLevel, _, _, _, _, _, sell, classID, subclassID = C.GetItemInfo(item.link or id)
    if not name then C.RequestLoad(id) return end
    local count = item.count or 1
    local v = { id = id, link = item.link, name = name, quality = quality, count = count, classID = classID,
                vendor = item.noValue and 0 or (sell or 0) * count, bound = item.bound }
    if classID == 12 or (ns.Crates and ns.Crates.Parse(name)) then v.keep = true end
    if ns.Disposition.KeepReason(name, classID, subclassID, reqLevel, id) then v.keep = true end
    local market = ns.Prices.Market(id)
    if market and not item.bound then v.ah = market * count * cut() end
    local de, skill = ns.Disposition.DEValue(item.link or id)
    if de then v.de, v.deSkill = de, skill end
    return v
end

-- Buy cost of one material: AH price, else about 4x its vendor sell price
-- (what vendors charge for thread, vials and the like).
local function matCost(id)
    local p = ns.Prices.Market(id)
    if p then return p, true end
    local sell = select(11, C.GetItemInfo(id))
    if sell and sell > 0 then return sell * 4, false end
end

function MO.Plan()
    local plan = { chars = {}, mail = {}, crafts = {}, gather = {}, totalGold = 0, totalCash = 0 }
    local list = {}
    for key, char in pairs(ns.db.chars) do
        if type(char) == "table" and char.name then list[#list + 1] = { key = key, char = char } end
    end

    -- Your best enchanter.
    local ench
    for _, e in ipairs(list) do
        local r = rank(e.char, "Enchanting")
        if r and (not ench or r > ench.rank) then ench = { key = e.key, char = e.char, rank = r } end
    end
    plan.enchanter = ench
    local minGain = ns.db.settings.ahMinGain or 1000

    for _, e in ipairs(list) do
        local c = e.char
        local row = { key = e.key, char = c, label = ns.CharLabel(c, e.key), gold = c.money or 0,
                      junk = 0, ah = 0, ahItems = 0, mailDE = 0, mailItems = {} }
        plan.totalGold = plan.totalGold + row.gold
        local isEnchanter = ench and ench.char == c
        for _, where in ipairs({ "bags", "bank" }) do
            for _, item in ipairs(c[where] or {}) do
                local v = item.id and MO.ItemValue(item)
                if v and not v.keep then
                    if v.quality == 0 then
                        row.junk = row.junk + v.vendor
                    elseif v.de and not v.bound and ench and ench.rank >= (v.deSkill or 999) and not isEnchanter
                        and v.de > math.max(v.ah or 0, v.vendor) + minGain / 2 then
                        row.mailDE = row.mailDE + v.de
                        row.mailItems[#row.mailItems + 1] = v
                    elseif v.ah and v.ah >= v.vendor + minGain then
                        row.ah = row.ah + v.ah
                        row.ahItems = row.ahItems + 1
                    end
                end
            end
        end
        row.total = row.junk + row.ah + row.mailDE
        plan.totalCash = plan.totalCash + row.total
        plan.chars[#plan.chars + 1] = row
        if #row.mailItems > 0 then plan.mail[#plan.mail + 1] = row end

        -- Crafts: learned recipes whose product sells for more than its materials.
        for prof, rec in pairs(c.recipes or {}) do
            for name, r in pairs(rec.list or {}) do
                if r.learned ~= false and r.item and r.mats and #r.mats > 0 then
                    local market = ns.Prices.Market(r.item)
                    if market then
                        local cost, estimated = 0, false
                        for _, m in ipairs(r.mats) do
                            local p, exact = matCost(m.id)
                            if not p then cost = nil break end
                            cost = cost + p * m.qty
                            if not exact then estimated = true end
                        end
                        local value = market * cut()
                        if cost and value - cost > 0 then
                            -- How you'd get the materials, and what that costs in gold and time.
                            local mp = ns.Mats and ns.Mats.Plan(r, value)
                            local factor = 1
                            if mp then
                                factor = ({ [0] = 1.1, [1] = 1, [2] = 1, [3] = 0.95, [4] = 0.85, [5] = 0.6, [6] = 0.35 })[mp.effort] or 1
                                if mp.expensive then factor = factor * 0.7 end
                            end
                            plan.crafts[#plan.crafts + 1] = { who = row.label, prof = prof, recipe = name, item = r.item,
                                                              value = value, cost = cost, profit = value - cost, estimated = estimated,
                                                              mp = mp, score = (value - cost) * factor }
                        end
                    end
                end
            end
        end

        -- Gathering: best-paying things this character can gather.
        for prof, items in pairs(D.Gathering) do
            local r = rank(c, prof)
            if r then
                local can, nextUp = {}, nil
                for _, g in ipairs(items) do
                    local price = ns.Prices.Market(g[1])
                    if g[3] <= r then
                        if price then can[#can + 1] = { id = g[1], name = g[2], price = price } end
                    elseif not nextUp then
                        nextUp = { id = g[1], name = g[2], skill = g[3], price = price }
                    end
                end
                table.sort(can, function(a, b) return a.price > b.price end)
                plan.gather[#plan.gather + 1] = { who = row.label, prof = prof, rank = r, best = can, nextUp = nextUp }
            end
        end
    end

    table.sort(plan.chars, function(a, b) return a.total > b.total end)
    table.sort(plan.mail, function(a, b) return a.mailDE > b.mailDE end)
    -- Keep the best version of each recipe (several characters may know it).
    -- Best first, counting effort: grinding or pricey materials push a recipe down.
    table.sort(plan.crafts, function(a, b) return (a.score or a.profit) > (b.score or b.profit) end)
    local seen, crafts = {}, {}
    for _, cr in ipairs(plan.crafts) do
        if not seen[cr.recipe] then seen[cr.recipe] = true crafts[#crafts + 1] = cr end
    end
    plan.crafts = crafts
    table.sort(plan.gather, function(a, b)
        local ap, bp = a.best[1] and a.best[1].price or 0, b.best[1] and b.best[1].price or 0
        return ap > bp
    end)
    return plan
end
