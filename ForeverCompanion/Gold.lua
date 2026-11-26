-- Gold: a safety net so the addon never pushes you into being broke.
--   * upcoming class training (recorded when you visit your class trainer)
--   * repairs (recorded at vendors that repair; estimated until then)
--   * a savings goal (riding and a mount at 40 by default; /fc goal to change)
-- Your safety net is training for the next few levels plus repairs; gold
-- above that is spendable. Crafting and buying suggestions use it.
local _, ns = ...
local GO = {}
ns.Gold = GO

local function lookahead() return ns.db and ns.db.settings.reserveLevels or 4 end  -- levels of training to keep aside
local REPAIR_FACTOR = 1.5

----------------------------------------------------------------------
-- Recording
----------------------------------------------------------------------
-- Class trainer: spells you haven't learned, with level and cost.
local function recordClassTrainer()
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then return end
    if IsTradeskillTrainer and IsTradeskillTrainer() then return end
    local saved = {}
    if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
        for _, f in ipairs({ "available", "unavailable", "used" }) do
            saved[f] = GetTrainerServiceTypeFilter(f)
            SetTrainerServiceTypeFilter(f, 1)
        end
    end
    local list = {}
    for i = 1, GetNumTrainerServices() do
        local name, rank, category = GetTrainerServiceInfo(i)
        if name and (category == "available" or category == "unavailable") then
            local skillName = GetTrainerServiceSkillReq and GetTrainerServiceSkillReq(i)
            -- Profession recipes are handled elsewhere; keep class spells only.
            if not (skillName and ns.Data.ProfessionNames[skillName]) then
                local level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0
                local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
                if cost > 0 then list[#list + 1] = { name = name, rank = rank, level = level, cost = cost } end
            end
        end
    end
    for f, v in pairs(saved) do SetTrainerServiceTypeFilter(f, v and 1 or 0) end
    if #list > 0 and ns.char then
        ns.char.training = list
        ns.char.trainingTime = time()
        ns:Debug(string.format("recorded %d spells still to learn from your class trainer.", #list))
    end
end
ns:On("TRAINER_SHOW", function() C_Timer.After(0.6, function() pcall(recordClassTrainer) end) end)

-- Repairs: the bill at a vendor that repairs.
ns:On("MERCHANT_SHOW", function()
    if not (ns.char and CanMerchantRepair and CanMerchantRepair() and GetRepairAllCost) then return end
    local cost = GetRepairAllCost()
    if cost and cost > 0 then
        ns.char.lastRepair = math.max(cost, ns.char.lastRepair or 0)
    end
end)

----------------------------------------------------------------------
-- Session gold rate
----------------------------------------------------------------------
local session = {}
ns:Listen("READY", function() session.start, session.money = GetTime(), GetMoney() end)

function GO.Rate()
    if not session.start then return end
    local elapsed = GetTime() - session.start
    if elapsed < 600 then return end           -- needs 10 minutes to mean anything
    return (GetMoney() - session.money) / elapsed * 3600
end

----------------------------------------------------------------------
-- Safety net, goal, spendable
----------------------------------------------------------------------
function GO.Training(upTo)
    local level = UnitLevel("player")
    upTo = upTo or (level + lookahead())
    local total, items = 0, {}
    for _, s in ipairs(ns.char and ns.char.training or {}) do
        if s.level <= upTo then
            total = total + s.cost
            items[#items + 1] = s
        end
    end
    table.sort(items, function(a, b) return a.level < b.level end)
    return total, items, ns.char and ns.char.training ~= nil
end

function GO.RepairBuffer()
    local last = ns.char and ns.char.lastRepair
    if last then return math.floor(last * REPAIR_FACTOR), true end
    return UnitLevel("player") * 300, false   -- rough guess until a repair is seen
end

-- "Class training at levels 34 and 36": the even levels the safety net covers.
function GO.TrainingLabel()
    local level = UnitLevel("player")
    local levels = {}
    for l = level + 1, level + lookahead() do
        if l % 2 == 0 then levels[#levels + 1] = tostring(l) end
    end
    if #levels == 0 then return "Class training" end
    if #levels == 1 then return "Class training at level " .. levels[1] end
    return "Class training at levels " .. table.concat(levels, ", ", 1, #levels - 1) .. " and " .. levels[#levels]
end

-- Returns reserve and its parts { { label, amount, known } }.
function GO.Reserve()
    local train, _, known = GO.Training()
    local repair, repairKnown = GO.RepairBuffer()
    local parts = {
        { label = GO.TrainingLabel(), amount = train, known = known },
        { label = "Repairs", amount = repair, known = repairKnown },
    }
    return train + repair, parts
end

function GO.Spendable()
    return math.max(0, GetMoney() - (GO.Reserve()))
end

-- The savings goal: yours if set, else riding and a mount at 40 (Classic price).
function GO.Goal()
    local g = ns.char and ns.char.goal
    if g == false then return end
    if g then return g end
    if UnitLevel("player") < 40 then
        return { name = "Riding and a mount at level 40", amount = 90 * 10000, default = true }
    end
end

-- Would spending this much be comfortable? Returns ok, reason.
function GO.Affordable(amount)
    if not amount or amount <= 0 then return true end
    local spendable = GO.Spendable()
    if amount <= spendable then return true end
    if amount <= GetMoney() then return false, "would dip into your safety net" end
    return false, "more gold than you have"
end

-- Time to reach an amount at this session's rate.
function GO.TimeTo(amount)
    local rate = GO.Rate()
    local need = amount - GetMoney()
    if need <= 0 then return 0 end
    if not rate or rate <= 0 then return end
    return need / rate * 3600
end

----------------------------------------------------------------------
-- Goal reached card
----------------------------------------------------------------------
ns:On("PLAYER_MONEY", function()
    local g = GO.Goal()
    if not (g and ns.char) then return end
    local have = GetMoney()
    if have >= g.amount and not ns.char.goalCelebrated then
        ns.char.goalCelebrated = true
        if ns.Celebrate then
            ns.Celebrate.Push({ icon = "Interface\\Icons\\INV_Misc_Coin_02", title = "Goal reached!",
                                line1 = "You can afford: " .. g.name,
                                line2 = "You have " .. ns.Money(have) .. ". Nice saving!", sound = "upgrade", duration = 15 })
        end
    elseif have < g.amount * 0.9 then
        ns.char.goalCelebrated = nil   -- celebrate again if you dip and come back
    end
end)

ns:Command("goal", "<gold> <name> set a savings goal (e.g. /fc goal 90 Mount), 'none' to turn off, empty for default", function(arg)
    arg = strtrim(arg or "")
    if arg == "" then ns.char.goal = nil ns:Print("savings goal back to the default.") return end
    if arg:lower() == "none" then ns.char.goal = false ns:Print("savings goal turned off.") return end
    local gold, name = arg:match("^(%d+%.?%d*)%s*(.*)$")
    if not gold then ns:Print("usage: /fc goal 90 Riding and mount") return end
    ns.char.goal = { name = (name ~= "" and name or "Savings goal"), amount = math.floor(tonumber(gold) * 10000) }
    ns.char.goalCelebrated = nil
    ns:Print("savings goal: " .. ns.char.goal.name .. ", " .. ns.Money(ns.char.goal.amount) .. ".")
end)
