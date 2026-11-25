-- Spec: your talents as the game reports them (Forever's own trees), the
-- tree that belongs to your spec, what you can take next there, and a
-- reminder about unspent points.
local _, ns = ...
local C, D = ns.C, ns.Data
local S = {}
ns.Spec = S

local function firstWord(s) return s and s:lower():match("^(%a+)") end

-- Which of the game's trees belongs to this spec: by name, then by the
-- classic talents it contains, then by tab position.
local function treeForSpec(trees, spec, class)
    for i, t in ipairs(trees) do
        if t.name and firstWord(t.name) == firstWord(spec.name) then return i end
    end
    local lookup = D.TalentTree[class] or {}
    local best, bestHits = nil, 0
    for i, t in ipairs(trees) do
        local hits = 0
        for _, tl in ipairs(t.talents) do
            if lookup[tl.name:lower()] == spec.tree then hits = hits + 1 end
        end
        if hits > bestHits then best, bestHits = i, hits end
    end
    if best then return best end
    if #trees == 3 then return spec.tree end
    if #trees == 1 then return 1 end
end

local applyGuide  -- defined below; declared here so S.Report can call it

-- Returns a report table used by the UI and /fc spec.
function S.Report()
    local class = ns.char.class
    local spec, manual, how, guess = ns:GetSpec()
    local r = { spec = spec, manual = manual, how = how, guess = guess, role = ns:SpecLabel() }
    local talents = C.GetTalentTrees()
    if not talents then
        r.modern = true
        r.specName = C.GetSpecialization()
        return r
    end
    r.trees = talents.trees
    r.unspent = talents.unspent or 0
    r.specTree = treeForSpec(talents.trees, spec, class)
    -- Next picks: talents in your spec's tree not yet maxed, top rows first.
    local tree = r.specTree and talents.trees[r.specTree]
    r.next = {}
    if tree then
        for _, t in ipairs(tree.talents) do
            if t.rank < t.max then
                -- Classic rule: each row needs 5 more points in the tree. Forever's
                -- modern trees report availability directly.
                local open
                if t.available ~= nil then open = t.available
                else open = tree.points >= (math.max(1, t.tier or 1) - 1) * 5 end
                r.next[#r.next + 1] = { name = t.name, rank = t.rank, max = t.max, tier = t.tier or 0, col = t.col or 0, open = open }
            end
        end
        table.sort(r.next, function(a, b)
            if a.open ~= b.open then return a.open end
            if a.tier ~= b.tier then return a.tier < b.tier end
            return a.col < b.col
        end)
    end
    applyGuide(r, class)
    return r
end

-- Walks the Forever build for your spec and finds where you are in it.
-- Fills r.guide = { build, steps = { {name, target, rank, max, open, found, tree} }, best, bestInTree }
function applyGuide(r, class)
    local build = D.ForeverBuilds[class] and D.ForeverBuilds[class][r.spec.name]
    if not build then return end
    local have = {}
    for _, tree in ipairs(r.trees) do
        for _, t in ipairs(tree.talents) do have[t.name:lower()] = t end
    end
    local lookup = D.TalentTree[class] or {}
    local target, steps = {}, {}
    for entry in build.order:gmatch("[^,]+") do
        local name, pts = entry:match("^%s*(.-):(%d+)%s*$")
        if name then
            local key = name:lower()
            target[key] = (target[key] or 0) + tonumber(pts)
            local t = have[key]
            steps[#steps + 1] = { name = name, target = target[key], rank = t and t.rank or 0, max = t and t.max or target[key],
                                  found = t ~= nil, open = t == nil or t.available ~= false, tree = lookup[key],
                                  note = build.notes and build.notes[name] }
        end
    end
    local g = { build = build, steps = steps, remaining = {} }
    for _, s in ipairs(steps) do
        if s.found and s.rank < s.target then
            g.remaining[#g.remaining + 1] = s
            if not g.best and s.open then g.best = s end
            if not g.bestInTree and s.open and s.tree == r.spec.tree then g.bestInTree = s end
        end
    end
    r.guide = g
end

-- The best talent to take next: from the Forever build when there is one,
-- otherwise the first open talent in your spec's tree.
function S.NextPick(r)
    if r.guide then return r.guide.best end
    for _, t in ipairs(r.next or {}) do
        if t.open then return t end
    end
end

-- Saved so the talent setup can be checked from outside the game.
function S.SaveDiagnostics()
    local lines = C.TalentDiagnostics()
    local talents = C.GetTalentTrees()
    for i, t in ipairs(talents and talents.trees or {}) do
        local names = {}
        for _, tl in ipairs(t.talents) do names[#names + 1] = string.format("%s %d/%d r%s", tl.name, tl.rank, tl.max, tostring(tl.tier)) end
        lines[#lines + 1] = string.format("tree %d '%s' points %d: %s", i, tostring(t.name), t.points, table.concat(names, ", "))
    end
    local spec, manual, how = ns:GetSpec()
    lines[#lines + 1] = "spec: " .. spec.name .. (manual and " (manual)" or "") .. ", " .. tostring(how)
    ns.db.diag = ns.db.diag or {}
    ns.db.diag.talents = { t = date("%Y-%m-%d %H:%M"), lines = lines }
    return lines
end

ns:Command("talentdebug", "print (and save) what the game reports about your talents", function()
    ns:Print("talent check (also saved for troubleshooting):")
    for _, line in ipairs(S.SaveDiagnostics()) do print("  " .. line) end
end)

local function nag()
    if not ns.char then return end
    pcall(S.SaveDiagnostics)
    local r = S.Report()
    if r.unspent and r.unspent > 0 then
        local pick = S.NextPick(r)
        ns:Print(string.format("you have %d unspent talent point%s.%s", r.unspent, r.unspent > 1 and "s" or "",
            pick and (" Next in " .. r.spec.name .. ": |cffffff00" .. pick.name .. "|r.") or ""))
    end
end

ns:On("PLAYER_LEVEL_UP", function() C_Timer.After(2, nag) end)
ns:Listen("READY", function() C_Timer.After(8, nag) end)

ns:Command("spec", "show your spec, talents and what to take next", function()
    local r = S.Report()
    ns:Print("gear is scored for " .. r.role .. ", " .. tostring(r.how) .. ".")
    if r.modern then
        print("  The game didn't report talent trees. Run /fc talentdebug.")
        return
    end
    for i, tree in ipairs(r.trees) do
        print(string.format("  %s: %d%s", tree.name or ("Tree " .. i), tree.points, i == r.specTree and "  (your spec)" or ""))
    end
    for i = 1, math.min(5, #r.next) do
        local t = r.next[i]
        print(string.format("    %s %d/%d%s", t.name, t.rank, t.max, t.open and "" or " (locked)"))
    end
    if r.unspent > 0 then print("  Unspent points: " .. r.unspent) end
end)
