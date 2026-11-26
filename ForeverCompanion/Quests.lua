-- Quests: XP rate and time to level, quest log triage by difficulty,
-- completed-quest XP, and zone suggestions for your level.
local _, ns = ...
local C, D = ns.C, ns.Data
local Q = {}
ns.Quests = Q

----------------------------------------------------------------------
-- XP tracking (this session)
----------------------------------------------------------------------
local session = { start = nil, xpGained = 0, lastXP = nil, lastMax = nil }

local function onXP()
    local xp, max = UnitXP("player"), UnitXPMax("player")
    if session.lastXP then
        local gained = xp - session.lastXP
        if gained < 0 then gained = (session.lastMax - session.lastXP) + xp end  -- leveled up
        if gained > 0 then session.xpGained = session.xpGained + gained end
    end
    session.lastXP, session.lastMax = xp, max
end

ns:Listen("READY", function()
    session.start = GetTime()
    session.lastXP, session.lastMax = UnitXP("player"), UnitXPMax("player")
end)
ns:On("PLAYER_XP_UPDATE", onXP)

function Q.XPStats()
    local xp, max = UnitXP("player"), UnitXPMax("player")
    local elapsed = session.start and (GetTime() - session.start) or 0
    local perHour = elapsed > 60 and (session.xpGained / elapsed * 3600) or nil
    local toGo = max - xp
    return {
        xp = xp, max = max, toGo = toGo, rested = GetXPExhaustion() or 0,
        perHour = perHour, eta = (perHour and perHour > 0) and (toGo / perHour * 3600) or nil,
        sessionXP = session.xpGained, elapsed = elapsed,
    }
end

----------------------------------------------------------------------
-- Quest log triage
----------------------------------------------------------------------
local function grayLevel(level)
    if GetQuestGreenRange then
        local ok, range = pcall(GetQuestGreenRange)
        if ok and range then return level - range - 1 end
    end
    if level <= 5 then return 0 end
    if level <= 39 then return level - math.floor(level / 10) - 5 end
    return level - math.floor(level / 5) - 1
end

-- Returns a category: "red", "orange", "yellow", "green", "gray"
function Q.Difficulty(qLevel)
    local level = UnitLevel("player")
    local diff = (qLevel or level) - level
    if diff >= 5 then return "red" end
    if diff >= 3 then return "orange" end
    if diff >= -2 then return "yellow" end
    if (qLevel or level) > grayLevel(level) then return "green" end
    return "gray"
end
Q.DiffHex = { red = "ff2020", orange = "ff8040", yellow = "ffff00", green = "40c040", gray = "808080" }

local ADVICE = {
    red = "too hard for now; group up or come back later",
    orange = "doable with care or a friend",
    yellow = "best XP for your level",
    green = "quick and easy",
    gray = "little XP: abandon unless it's on your way",
}

function Q.Triage()
    local out = { complete = {}, active = {}, completeXP = 0 }
    for _, q in ipairs(C.GetQuests()) do
        if not q.header and q.title then
            q.diff = Q.Difficulty(q.level)
            q.xp = C.QuestRewardXP(q.questID)
            q.advice = ADVICE[q.diff]
            if (q.group or 0) > 1 and ns.db.settings.playStyle == "solo" then
                q.advice = "group quest (" .. q.group .. " players): skip it or ask for help"
                if q.diff == "yellow" or q.diff == "green" then q.diff = "orange" end
            end
            if q.complete then
                table.insert(out.complete, q)
                out.completeXP = out.completeXP + (q.xp or 0)
            else
                table.insert(out.active, q)
            end
        end
    end
    local order = { yellow = 1, green = 2, orange = 3, red = 4, gray = 5 }
    table.sort(out.active, function(a, b)
        if order[a.diff] ~= order[b.diff] then return order[a.diff] < order[b.diff] end
        return (a.xp or 0) > (b.xp or 0)
    end)
    return out
end

function Q.Zones()
    local level = UnitLevel("player")
    local faction = UnitFactionGroup("player")
    local out = {}
    for _, z in ipairs(D.Zones) do
        local name, min, max, fac = z[1], z[2], z[3], z[4]
        if (not fac or fac == faction) and level >= min - 1 and level <= max - 2 then
            out[#out + 1] = string.format("%s (%d-%d)", name, min, max)
        end
    end
    return out
end

----------------------------------------------------------------------
-- Level-up checklist
----------------------------------------------------------------------
ns:On("PLAYER_LEVEL_UP", function(_, newLevel)
    -- The level-up card covers this; chat only when cards are turned off.
    if ns.db.settings.celebrate ~= false then return end
    C_Timer.After(3, function()
        local tips = {}
        if newLevel and newLevel % 2 == 0 then tips[#tips + 1] = "new spells may be at your class trainer" end
        local ups = ns.Gear and ns.Gear.BagUpgrades() or {}
        if #ups > 0 then tips[#tips + 1] = #ups .. " gear upgrade(s) in your bags (/fc gear)" end
        local zones = Q.Zones()
        if #zones > 0 then tips[#tips + 1] = "good zones: " .. table.concat(zones, ", ", 1, math.min(3, #zones)) end
        if #tips > 0 then ns:Print("level " .. (newLevel or UnitLevel("player")) .. "! " .. table.concat(tips, "; ") .. ".") end
    end)
end)

ns:Command("quests", "triage your quest log and show XP rate and zones", function()
    local s = Q.XPStats()
    local t = Q.Triage()
    ns:Print(string.format("%d XP to go. %s/hour this session, level in %s. Rested: %d.",
        s.toGo, s.perHour and math.floor(s.perHour) or "--", ns.Duration(s.eta), s.rested))
    if #t.complete > 0 then
        print(string.format("  Turn in %d completed quest(s) for %d XP (%.0f%% of this level).",
            #t.complete, t.completeXP, s.max > 0 and t.completeXP / s.max * 100 or 0))
    end
    for _, q in ipairs(t.active) do
        print(string.format("  |cff%s[%d] %s|r  %s", Q.DiffHex[q.diff], q.level or 0, q.title, q.advice))
    end
    local zones = Q.Zones()
    if #zones > 0 then print("  Zones for your level: " .. table.concat(zones, ", ")) end
end)

----------------------------------------------------------------------
-- Quest rewards: items offered by quests in your log (rewards and the
-- "choose one" items), so gear research can suggest them.
----------------------------------------------------------------------
local rewardCache, rewardTime
function Q.RewardItems()
    if rewardCache and GetTime() - rewardTime < 30 then return rewardCache end
    local out = {}
    if not GetQuestLogItemLink then return out end
    local modern = C_QuestLog and C_QuestLog.SetSelectedQuest and C_QuestLog.GetSelectedQuest
    local previous = modern and C_QuestLog.GetSelectedQuest() or (GetQuestLogSelection and GetQuestLogSelection())
    local index = 0
    for _, q in ipairs(C.GetQuests()) do
        index = index + 1
        if not q.header and q.questID then
            local ok = pcall(function()
                local nChoices, nRewards
                if modern then
                    C_QuestLog.SetSelectedQuest(q.questID)
                    nChoices = GetNumQuestLogChoices(q.questID, false) or 0
                    nRewards = GetNumQuestLogRewards(q.questID) or 0
                elseif SelectQuestLogEntry then
                    SelectQuestLogEntry(index)
                    nChoices = GetNumQuestLogChoices() or 0
                    nRewards = GetNumQuestLogRewards() or 0
                end
                for i = 1, nChoices or 0 do
                    local link = GetQuestLogItemLink("choice", i)
                    if link then out[#out + 1] = { id = C.ItemID(link), link = link, quest = q.title, choice = true, complete = q.complete } end
                end
                for i = 1, nRewards or 0 do
                    local link = GetQuestLogItemLink("reward", i)
                    if link then out[#out + 1] = { id = C.ItemID(link), link = link, quest = q.title, complete = q.complete } end
                end
            end)
            if not ok then break end
        end
    end
    if modern and previous then pcall(C_QuestLog.SetSelectedQuest, previous)
    elseif SelectQuestLogEntry and previous then pcall(SelectQuestLogEntry, previous) end
    rewardCache, rewardTime = out, GetTime()
    return out
end

ns:On("QUEST_LOG_UPDATE", function()
    if rewardTime and GetTime() - rewardTime > 5 then
        rewardTime = 0
        if ns.Research then ns.Research.Invalidate() end
    end
end)
