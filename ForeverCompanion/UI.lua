-- UI: a window with a sidebar of pages. Each page is built from a few
-- widgets: summary tiles, section headers, item rows (icon, name, detail
-- line, value on the right), progress bars and notes.
local _, ns = ...
local C, D = ns.C, ns.Data
local M = ns.Money

local WIDTH, HEIGHT, SIDEBAR = 780, 560, 160
local CONTENT_W = WIDTH - SIDEBAR - 46
local ACCENT = { 0.5, 0.83, 1 }

local frame, scroll, content, subtitle, footerText, footerButtons, navButtons
local current = "Overview"

-- Drag to scroll: works with a finger on a touch screen and with a mouse.
-- A press that moves more than a few pixels scrolls instead of clicking.
local drag = { active = false, moved = false }
local function dragStart()
    if not scroll then return end
    local _, y = GetCursorPosition()
    drag.active, drag.moved = true, false
    drag.y0, drag.s0 = y, scroll:GetVerticalScroll()
end
local function dragUpdate()
    if not drag.active then return end
    if not IsMouseButtonDown("LeftButton") then drag.active = false return end
    local _, y = GetCursorPosition()
    local dy = (y - drag.y0) / frame:GetEffectiveScale()
    if math.abs(dy) > 6 then drag.moved = true end
    if drag.moved then
        local range = scroll:GetVerticalScrollRange()
        scroll:SetVerticalScroll(math.max(0, math.min(range, drag.s0 + dy)))
    end
end
-- True (once) if the last press was a drag, so it shouldn't count as a click.
local function wasDrag()
    if drag.moved then drag.moved = false return true end
    return false
end

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function color(hex, s) return "|cff" .. hex .. tostring(s) .. "|r" end
local GREEN, RED, GOLD, GRAY, PURPLE, BLUE = "4cff4c", "ff6060", "ffd100", "9a9a9a", "b97cff", "80d4ff"

local function itemIcon(linkOrID)
    if not linkOrID then return end
    local id = C.ItemID(linkOrID)
    if C_Item and C_Item.GetItemIconByID and id then return C_Item.GetItemIconByID(id) end
    if GetItemIcon and id then return GetItemIcon(id) end
    return select(10, C.GetItemInfo(linkOrID))
end

local ICONS = {
    Overview = "Interface\\Icons\\INV_Misc_Book_09",
    Gear = "Interface\\Icons\\INV_Chest_Chain",
    Bags = "Interface\\Icons\\INV_Misc_Bag_08",
    Professions = "Interface\\Icons\\Trade_BlackSmithing",
    Talents = "Interface\\Icons\\Ability_Marksmanship",
    Quests = "Interface\\Icons\\INV_Misc_Note_01",
    Money = "Interface\\Icons\\INV_Misc_Coin_01",
    Repair = "Interface\\Icons\\Trade_BlackSmithing",
    Coin = "Interface\\Icons\\INV_Misc_Coin_02",
    Quest = "Interface\\GossipFrame\\ActiveQuestIcon",
    Zone = "Interface\\Icons\\INV_Misc_Map_01",
    Clock = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    Trainer = "Interface\\Icons\\INV_Misc_Book_11",
}
local PAGE_ORDER = { "Overview", "Gear", "Bags", "Money", "Professions", "Talents", "Quests" }
local PAGE_HINTS = {
    Overview = "Click a to-do item to jump to its page.",
    Gear = "Hover an item for full details. Shift-click to link it in chat.",
    Bags = "Hover an item to see the disenchant odds.",
    Professions = "Open each profession window once so its recipes are recorded.",
    Talents = "Talents come from the game's own tree for your spec.",
    Quests = "Quest colors match the game: yellow gives the best XP for your level.",
    Money = "Covers every character you've logged in with this addon. Prices come from your AH scans.",
}

----------------------------------------------------------------------
-- Widget pools
----------------------------------------------------------------------
local pools = {}
local y = 0

local function acquire(kind, create)
    local pool = pools[kind]
    if not pool then pool = { used = 0 } pools[kind] = pool end
    pool.used = pool.used + 1
    local w = pool[pool.used]
    if not w then w = create() pool[pool.used] = w end
    w:ClearAllPoints()
    w:Show()
    return w
end

local function resetPools()
    for _, pool in pairs(pools) do
        for i = 1, #pool do pool[i]:Hide() end
        pool.used = 0
    end
    y = 0
end

local function place(w, h, indent)
    w:SetPoint("TOPLEFT", content, "TOPLEFT", indent or 0, -y)
    w:SetWidth(CONTENT_W - (indent or 0))
    w:SetHeight(h)
    y = y + h
end

local function newBackdrop(parent, r, g, b, a)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(r, g, b, a)
    f:SetBackdropBorderColor(1, 1, 1, 0.08)
    return f
end

----------------------------------------------------------------------
-- Page builder
----------------------------------------------------------------------
local P = {}

function P.Gap(h) y = y + (h or 8) end

function P.Header(text, right)
    local w = acquire("header", function()
        local f = CreateFrame("Frame", nil, content)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.text:SetPoint("BOTTOMLEFT", 2, 6)
        f.right = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.right:SetPoint("BOTTOMRIGHT", -4, 7)
        f.line = f:CreateTexture(nil, "ARTWORK")
        f.line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.35)
        f.line:SetHeight(1)
        f.line:SetPoint("BOTTOMLEFT", 0, 2)
        f.line:SetPoint("BOTTOMRIGHT", 0, 2)
        return f
    end)
    if y > 0 then y = y + 10 end
    w.text:SetText(text)
    w.right:SetText(right or "")
    place(w, 30)
    y = y + 4
end

-- A smaller heading inside a section.
function P.SubHeader(text)
    local w = acquire("subheader", function()
        local f = CreateFrame("Frame", nil, content)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.text:SetPoint("BOTTOMLEFT", 2, 3)
        return f
    end)
    w.text:SetText(text)
    place(w, 24)
end

-- tiles: { { value, label, hex color } ... }
function P.Tiles(tiles)
    local n = #tiles
    local gap = 8
    local tw = (CONTENT_W - gap * (n - 1)) / n
    for i, t in ipairs(tiles) do
        local w = acquire("tile", function()
            local f = newBackdrop(content, 0.12, 0.13, 0.16, 0.95)
            f.value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
            f.value:SetPoint("TOPLEFT", 10, -10)
            f.value:SetPoint("RIGHT", -8, 0)
            f.value:SetJustifyH("LEFT")
            f.value:SetWordWrap(false)
            f.label = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            f.label:SetPoint("BOTTOMLEFT", 10, 9)
            f.label:SetPoint("RIGHT", -8, 0)
            f.label:SetJustifyH("LEFT")
            return f
        end)
        w.value:SetText(t[3] and color(t[3], t[1]) or t[1])
        w.label:SetText(t[2])
        w:SetPoint("TOPLEFT", content, "TOPLEFT", (i - 1) * (tw + gap), -y)
        w:SetSize(tw, 54)
    end
    y = y + 54 + 6
end

-- opts: { icon, link, title, sub, right, onClick, tip }
local rowIndex = 0
function P.Row(opts)
    local w = acquire("row", function()
        local f = CreateFrame("Button", nil, content)
        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints()
        f.hl = f:CreateTexture(nil, "HIGHLIGHT")
        f.hl:SetAllPoints()
        f.hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.12)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetSize(28, 28)
        f.icon:SetPoint("LEFT", 6, 0)
        f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetJustifyH("LEFT")
        f.title:SetWordWrap(false)
        f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.sub:SetJustifyH("LEFT")
        f.sub:SetWordWrap(false)
        f.sub2 = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.sub2:SetJustifyH("LEFT")
        f.sub2:SetWordWrap(false)
        f.sub3 = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.sub3:SetJustifyH("LEFT")
        f.sub3:SetWordWrap(false)
        f.right = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.right:SetJustifyH("RIGHT")
        f.right:SetPoint("RIGHT", -10, 0)
        f.right:SetWidth(170)
        f.arrow = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        f.arrow:SetPoint("RIGHT", -4, 0)
        f.arrow:SetText(">")
        f:RegisterForClicks("LeftButtonUp")
        f:SetScript("OnEnter", function(self)
            if self.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.link)
                GameTooltip:Show()
            elseif self.tip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        f:SetScript("OnLeave", GameTooltip_Hide)
        f:SetScript("OnMouseDown", dragStart)
        f:SetScript("OnClick", function(self)
            if wasDrag() then return end
            if self.link and IsModifiedClick() and HandleModifiedItemClick then
                HandleModifiedItemClick(self.link)
            elseif self.onClick then
                self.onClick()
            end
        end)
        return f
    end)
    rowIndex = rowIndex + 1
    w.bg:SetColorTexture(1, 1, 1, rowIndex % 2 == 0 and 0.035 or 0.015)
    w.link, w.tip, w.onClick = opts.link, opts.tip, opts.onClick
    local icon = opts.icon or (opts.link and itemIcon(opts.link))
    local x = 10
    if icon then
        w.icon:SetTexture(icon) w.icon:Show() x = 42
    else
        w.icon:Hide()
    end
    if opts.sub3 and not opts.sub2 then opts.sub2, opts.sub3 = opts.sub3, nil end
    local h = opts.sub3 and 66 or (opts.sub2 and 52 or (opts.sub and 38 or 26))
    w.sub3:ClearAllPoints()
    if opts.sub3 then
        w.sub3:SetPoint("TOPLEFT", w.sub2, "BOTTOMLEFT", 0, -3)
        w.sub3:SetText(opts.sub3)
        w.sub3:SetWidth(CONTENT_W - x - 14 - (opts.indent or 0))
        w.sub3:Show()
    else
        w.sub3:Hide()
    end
    w.title:ClearAllPoints()
    w.sub:ClearAllPoints()
    w.sub2:ClearAllPoints()
    if opts.sub2 then
        w.sub2:SetPoint("TOPLEFT", w.sub, "BOTTOMLEFT", 0, -3)
        w.sub2:SetText(opts.sub2)
        w.sub2:SetWidth(CONTENT_W - x - 190 - (opts.indent or 0))
        w.sub2:Show()
    else
        w.sub2:Hide()
    end
    if opts.sub then
        w.title:SetPoint("TOPLEFT", x, -5)
        w.sub:SetPoint("TOPLEFT", w.title, "BOTTOMLEFT", 0, -3)
        w.sub:SetText(opts.sub)
        w.sub:SetWidth(CONTENT_W - x - 190 - (opts.indent or 0))
        w.sub:Show()
    else
        w.title:SetPoint("LEFT", x, 0)
        w.sub:Hide()
    end
    w.title:SetText(opts.title or (opts.link or ""))
    w.title:SetWidth(CONTENT_W - x - 190 - (opts.indent or 0))
    w.right:SetText(opts.right or "")
    w.right:ClearAllPoints()
    if opts.sub2 or opts.sub3 then
        -- Value sits on the title line so the two detail lines can use the full width.
        w.right:SetPoint("TOPRIGHT", opts.onClick and -20 or -10, -5)
        w.sub:SetWidth(CONTENT_W - x - 14 - (opts.indent or 0))
        w.sub2:SetWidth(CONTENT_W - x - 14 - (opts.indent or 0))
    else
        w.right:SetPoint("RIGHT", opts.onClick and -20 or -10, 0)
    end
    w.arrow:SetShown(opts.onClick ~= nil)
    place(w, h, opts.indent)
    y = y + 2
end

-- A label followed by toggle buttons: { { label, active, onClick } ... }
function P.Choices(label, choices)
    local holder = acquire("choiceLabel", function()
        local f = CreateFrame("Frame", nil, content)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.text:SetPoint("LEFT", 2, 0)
        return f
    end)
    holder.text:SetText(label)
    holder:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    holder:SetSize(100, 24)
    local x, rowY = 100, y
    for _, ch in ipairs(choices) do
        local b = acquire("choice", function()
            local f = CreateFrame("Button", nil, content, "BackdropTemplate")
            f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            f.text:SetPoint("CENTER")
            local hl = f:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.08)
            f:SetScript("OnMouseDown", dragStart)
            f:SetScript("OnClick", function(self) if not wasDrag() and self.fn then self.fn() end end)
            return f
        end)
        b.text:SetText(ch.label)
        local w = b.text:GetStringWidth() + 20
        if x + w > CONTENT_W then x, rowY = 100, rowY + 28 end
        b:SetPoint("TOPLEFT", content, "TOPLEFT", x, -rowY)
        b:SetSize(w, 24)
        if ch.active then
            b:SetBackdropColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.35)
            b:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
        else
            b:SetBackdropColor(1, 1, 1, 0.04)
            b:SetBackdropBorderColor(1, 1, 1, 0.15)
        end
        b.fn = ch.onClick
        x = x + w + 6
    end
    y = rowY + 32
end

function P.Note(text, hex)
    local w = acquire("note", function()
        local f = CreateFrame("Frame", nil, content)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.text:SetPoint("TOPLEFT", 4, 0)
        f.text:SetJustifyH("LEFT")
        f.text:SetJustifyV("TOP")
        f.text:SetSpacing(2)
        return f
    end)
    w.text:SetWidth(CONTENT_W - 8)
    w.text:SetText(hex and color(hex, text) or text)
    place(w, w.text:GetStringHeight() + 6)
end

function P.Bar(label, value, max, hex)
    local w = acquire("bar", function()
        local f = CreateFrame("Frame", nil, content)
        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetColorTexture(1, 1, 1, 0.08)
        f.bg:SetPoint("TOPLEFT", 0, -16)
        f.bg:SetPoint("BOTTOMRIGHT")
        f.fill = f:CreateTexture(nil, "ARTWORK")
        f.fill:SetPoint("TOPLEFT", f.bg, "TOPLEFT")
        f.fill:SetPoint("BOTTOMLEFT", f.bg, "BOTTOMLEFT")
        f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.label:SetPoint("TOPLEFT", 0, 0)
        f.value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.value:SetPoint("TOPRIGHT", 0, 0)
        return f
    end)
    local pct = (max and max > 0) and math.min(1, value / max) or 0
    local r, g, b = 0.5, 0.83, 1
    if hex then r, g, b = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 end
    w.fill:SetColorTexture(r, g, b, 0.85)
    w.fill:SetWidth(math.max(1, (CONTENT_W) * pct))
    w.label:SetText(label)
    w.value:SetText(string.format("%s / %s", value, max))
    place(w, 26)
    y = y + 4
end

----------------------------------------------------------------------
-- Pages
----------------------------------------------------------------------
local pages = {}
local function go(page) return function() current = page ns.RenderUI() end end

pages.Overview = function()
    local c = ns.char
    local s = ns.Quests.XPStats()
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
    local level = UnitLevel("player")
    local _, totals = ns.Disposition.EvaluateBags()
    P.Tiles({
        { level, level < maxLevel and string.format("Level (%.0f%% to next)", s.max > 0 and s.xp / s.max * 100 or 0) or "Level (max)", GOLD },
        { string.format("%.1f", c.avgIlvl or 0), "Average item level" },
        { M(GetMoney()), "Gold on hand" },
        { M(totals.AH + totals.DE + totals.VENDOR), "Bag items you can cash in", GREEN },
    })

    -- Your plan: what to do now at your level, then what's coming up.
    local plan = ns.Research.Plan()
    local tri = ns.Quests.Triage()
    local QD = ns.QuestDB
    local xpLeft = level < maxLevel and (s.max - s.xp) or nil
    P.Header("Your plan", xpLeft and string.format("level %d  ·  %d XP to %d", level, xpLeft, level + 1) or ("level " .. level))

    local function upgradeList(items, n)
        local parts = {}
        for j = 1, math.min(n, #items) do
            local it = items[j]
            parts[#parts + 1] = (D.SlotNames[it.slot] or "?") .. color(GREEN, string.format(" +%.1f", it.f.cmp.delta))
                .. ((it.f.source.rate and it.f.source.kind == "dungeon") and color(GRAY, " " .. ns.Research.FormatRate(it.f.source.rate)) or "")
        end
        return table.concat(parts, ", ")
    end
    local function questRow(q)
        local verb = q.pickup and "Pick up " or (q.complete and "Turn in " or "Finish ")
        local where = q.pickup and ((q.starter and (" from " .. q.starter) or "") .. (q.zone and (" in " .. q.zone) or "")) or ""
        local parts = {}
        for j = 1, math.min(2, #q.items) do
            local it = q.items[j]
            parts[#parts + 1] = (it.f.link or "?") .. color(GREEN, string.format(" +%.1f", it.f.cmp.delta)) .. (it.choice and color(GRAY, " (choose it)") or "")
        end
        P.Row({ icon = ICONS.Quest, title = verb .. color(GOLD, q.name) .. color(GRAY, where)
                    .. (q.needs and color("ff8040", "  (do " .. q.needs .. " first)") or ""),
                sub = "Upgrade reward: " .. table.concat(parts, ", "), onClick = go("Quests"),
                right = q.when == "soon" and color(GRAY, "at level " .. (q.req or "?")) or (q.complete and color(GREEN, "ready") or nil) })
    end
    local function dungeonRow(d)
        local lv = (d.lo and d.hi) and string.format("levels %d-%d", d.lo, d.hi) or nil
        local note = d.below and color(GRAY, "  ·  below your level, quick run") or ""
        P.Row({ icon = ICONS.Zone, title = "Run " .. color(GOLD, d.name) .. (lv and color(GRAY, "  ·  " .. lv) or "") .. note,
                sub = string.format("%d upgrade%s: ", #d.items, #d.items > 1 and "s" or "") .. upgradeList(d.items, 3),
                right = d.when == "soon" and color(GRAY, "in " .. d.inLevels .. " level" .. (d.inLevels > 1 and "s" or "")) or nil,
                onClick = go("Gear") })
    end

    P.SubHeader("Now")
    local nowCount = 0
    -- 1. Turn in finished quests: free XP.
    if #tri.complete > 0 then
        local names = {}
        for i = 1, math.min(3, #tri.complete) do names[#names + 1] = tri.complete[i].title end
        P.Row({ icon = ICONS.Quest, title = string.format("Turn in %d finished quest%s", #tri.complete, #tri.complete > 1 and "s" or ""),
                sub = table.concat(names, ", ") .. (#tri.complete > 3 and ", ..." or ""),
                right = tri.completeXP > 0 and color(GREEN, string.format("%d XP%s", tri.completeXP,
                    xpLeft and tri.completeXP >= xpLeft and "  (levels you!)" or "")) or nil, onClick = go("Quests") })
        nowCount = nowCount + 1
    end
    -- 2. Where to quest for XP right now.
    if QD and QD.zones and #QD.zones > 0 then
        for i = 1, math.min(2, #QD.zones) do
            local z = QD.zones[i]
            local ok, names = pcall(QD.SampleNames, z, 3)
            P.Row({ icon = ICONS.Zone, title = "Quest in " .. color(GOLD, z.name),
                    sub = string.format("%d quests at your level you haven't done", z.count) .. (ok and (": " .. table.concat(names, ", ")) or ""),
                    onClick = go("Quests") })
            nowCount = nowCount + 1
        end
    elseif #tri.active > 0 then
        local good = 0
        for _, q in ipairs(tri.active) do if q.diff == "yellow" or q.diff == "orange" or q.diff == "green" then good = good + 1 end end
        if good > 0 then
            P.Row({ icon = ICONS.Quest, title = string.format("Work on the %d quest%s in your log at your level", good, good > 1 and "s" or ""),
                    sub = "Yellow and orange give the most XP", onClick = go("Quests") })
            nowCount = nowCount + 1
        end
    end
    -- 3. Quests with upgrade rewards you can do now, then dungeons in range.
    local soonQ, soonD = {}, {}
    local shownQ = 0
    for _, q in ipairs(plan.quests) do
        if q.when == "soon" then soonQ[#soonQ + 1] = q
        elseif shownQ < 3 then questRow(q) shownQ = shownQ + 1 nowCount = nowCount + 1 end
    end
    local shownD = 0
    for _, d in ipairs(plan.dungeons) do
        if d.when == "soon" then soonD[#soonD + 1] = d
        elseif shownD < 2 then dungeonRow(d) shownD = shownD + 1 nowCount = nowCount + 1 end
    end
    if nowCount == 0 then P.Note("Nothing specific yet. Keep questing; this fills in as data loads.", GRAY) end

    if #soonQ > 0 or #soonD > 0 then
        P.SubHeader("Coming up")
        for i = 1, math.min(2, #soonQ) do questRow(soonQ[i]) end
        table.sort(soonD, function(a, b) return (a.inLevels or 0) < (b.inLevels or 0) end)
        for i = 1, math.min(2, #soonD) do dungeonRow(soonD[i]) end
    end
    local missing = {}
    if not ns.Research.HasAtlasLoot() then missing[#missing + 1] = "AtlasLoot Classic Forever (dungeon drops)" end
    if not (QD and QD.Has()) then missing[#missing + 1] = "Questie (quests and questing zones)" end
    if #missing > 0 then P.Note("Install " .. table.concat(missing, " and ") .. " for a fuller plan.", GRAY) end

    P.Header("Next steps")
    local n = 0
    local r = ns.Spec.Report()
    if r.unspent and r.unspent > 0 then
        local pick = ns.Spec.NextPick(r)
        P.Row({ icon = ICONS.Talents, title = string.format("Spend %d talent point%s", r.unspent, r.unspent > 1 and "s" or ""),
                sub = pick and ("Suggested next: " .. pick.name) or nil, onClick = go("Talents") })
        n = n + 1
    end
    local ups = ns.Gear.BagUpgrades()
    for i = 1, math.min(3, #ups) do
        local u = ups[i]
        P.Row({ link = u.link, title = "Equip " .. u.link, sub = (D.SlotNames[u.cmp.slot] or "") .. ": " .. (ns.Gear.Why(u.link, u.cmp) or "better for your spec"),
                right = color(GREEN, string.format("+%.1f", u.cmp.delta)), onClick = go("Gear") })
        n = n + 1
    end
    local t = ns.Quests.Triage()
    for _, p in ipairs(c.professions or {}) do
        local hint = ns.Professions.TrainerHint(p)
        if hint and hint:find("^Visit") then
            P.Row({ icon = ICONS.Trainer, title = p.name .. ": visit your trainer", sub = hint, onClick = go("Professions") })
            n = n + 1
        end
    end
    local worst
    for slot, g in pairs(c.gear or {}) do
        if g.dura and (not worst or g.dura < worst.dura) then worst = { slot = slot, dura = g.dura } end
    end
    if worst and worst.dura < 0.25 then
        P.Row({ icon = ICONS.Repair, title = "Repair your gear",
                sub = string.format("%s is at %d%% durability", D.SlotNames[worst.slot] or "An item", worst.dura * 100), onClick = go("Gear") })
        n = n + 1
    end
    local sealed, fillable = ns.Crates.Todo()
    if sealed > 0 then
        P.Row({ icon = ICONS.Bags, title = string.format("Turn in %d sealed crate%s", sealed, sealed > 1 and "s" or ""),
                sub = ns.Crates.TurnIn[UnitFactionGroup("player")] or "", onClick = go("Professions") })
        n = n + 1
    end
    for _, f in ipairs(fillable) do
        P.Row({ icon = ICONS.Bags, title = "Fill " .. f.crate, sub = string.format("You have %d %s (needs %d)", f.with.have, f.with.name, f.with.qty),
                onClick = go("Professions") })
        n = n + 1
    end
    do
        local ok, mp = pcall(ns.MoneyPlan.Plan)
        if ok and mp and (mp.crafts[1] or #mp.mail > 0) then
            local bits = {}
            if mp.crafts[1] then bits[#bits + 1] = "craft " .. mp.crafts[1].recipe .. " (+" .. M(mp.crafts[1].profit) .. " each)" end
            if #mp.mail > 0 then bits[#bits + 1] = "mail greens to your enchanter" end
            P.Row({ icon = ICONS.Money, title = "Make gold", sub = table.concat(bits, ", "), onClick = go("Money") })
            n = n + 1
        end
    end
    if totals.AH + totals.DE + totals.VENDOR > 0 then
        local parts = {}
        if totals.AH > 0 then parts[#parts + 1] = "auction ~" .. M(totals.AH) end
        if totals.DE > 0 then parts[#parts + 1] = "disenchant ~" .. M(totals.DE) end
        if totals.VENDOR > 0 then parts[#parts + 1] = "vendor " .. M(totals.VENDOR) end
        P.Row({ icon = ICONS.Bags, title = "Clear out your bags", sub = table.concat(parts, ", "), onClick = go("Bags") })
        n = n + 1
    end
    if n == 0 then P.Note("Nothing pressing. Go adventure!", GRAY) end

    if level < maxLevel then
        P.Header("Leveling")
        P.Bar("Experience", s.xp, s.max, "b97cff")
        P.Row({ icon = ICONS.Clock, title = "Time to next level",
                sub = s.perHour and (math.floor(s.perHour) .. " XP per hour this session") or "Needs a few minutes of play to measure",
                right = ns.Duration(s.eta), onClick = go("Quests") })
        if s.rested > 0 then
            P.Row({ icon = "Interface\\Icons\\Spell_Nature_Sleep", title = "Rested XP", sub = "Kills give double XP until it runs out",
                    right = s.rested .. " XP" })
        end
    end
end

pages.Gear = function()
    local c = ns.char
    local weights, role = ns.Gear.Weights()
    local ups = ns.Gear.BagUpgrades()
    local worst = 1
    for _, g in pairs(c.gear or {}) do if g.dura and g.dura < worst then worst = g.dura end end
    local spec, manual, how, guess = ns:GetSpec()
    P.Tiles({
        { spec.name .. "  " .. color(GRAY, spec.role), manual and "Spec (chosen by you)" or (guess and "Spec (guessed)" or "Spec (detected)"), guess and "ff8040" or BLUE },
        { string.format("%.1f", c.avgIlvl or 0), "Average item level" },
        { #ups, "Upgrades in your bags", #ups > 0 and GREEN or nil },
        { string.format("%d%%", worst * 100), "Lowest durability", worst < 0.25 and RED or nil },
    })

    local wl = {}
    for k, v in pairs(weights) do wl[#wl + 1] = { k, v } end
    table.sort(wl, function(a, b) return a[2] > b[2] end)
    local names = D.StatNames
    local ws = {}
    for i = 1, math.min(5, #wl) do ws[#ws + 1] = names[wl[i][1]] or wl[i][1] end
    local choices = { { label = "Auto", active = not manual, onClick = function() ns:SetSpec("auto") ns.Gear.Snapshot() end } }
    for _, s in ipairs(D.Specs[c.class] or {}) do
        choices[#choices + 1] = { label = s.name .. "  " .. color(GRAY, s.role), active = manual and s.name == spec.name,
            onClick = function() ns.db.settings.specOverride = s.name ns.Gear.Snapshot() end }
    end
    P.Choices("Score gear for:", choices)
    if guess then
        P.Note("Your spec couldn't be detected: no talent points could be read. Click your spec above so gear is scored correctly.", "ff8040")
    elseif not manual then
        P.Note("Detected " .. how .. ".", GRAY)
    end
    P.Note("Stat priority for " .. spec.name .. ": " .. table.concat(ws, " > ") .. ".", GRAY)

    P.Header("Upgrades in your bags", #ups > 0 and color(GREEN, #ups .. " found") or nil)
    if #ups == 0 then P.Note("None right now. Gear you loot is checked automatically.", GRAY) end
    for _, u in ipairs(ups) do
        P.Row({ link = u.link, sub = "Replaces " .. (u.cmp.current or "an empty slot") .. " in " .. (D.SlotNames[u.cmp.slot] or "?")
                .. (u.cmp.note and (", " .. color(GOLD, u.cmp.note)) or ""),
                sub2 = ns.Gear.Why(u.link, u.cmp, 5),
                right = color(GREEN, string.format("+%.1f%s", u.cmp.delta, u.cmp.pct and string.format("  (%+.0f%%)", u.cmp.pct) or "")) })
    end

    local weak = ns.Gear.WeakSlots()
    P.Header("What to chase next", "your weakest slots first")
    if #weak == 0 then P.Note("Every slot is reasonable for your level.", GRAY) end
    local R = ns.Research
    for i = 1, math.min(5, #weak) do
        local w = weak[i]
        if w.link then
            P.Row({ link = w.link, title = color(GOLD, D.SlotNames[w.slot]) .. "   " .. w.link,
                    sub = "Item level " .. w.ilvl, right = color(RED, w.gap .. " levels behind") })
        else
            P.Row({ icon = "Interface\\PaperDoll\\UI-Backpack-EmptySlot", title = color(GOLD, D.SlotNames[w.slot]),
                    sub = "Nothing equipped", right = color(RED, "empty") })
        end
        -- Best option from each source, so crafting doesn't hide AH and dungeon gear.
        local finds = R.ForSlot(w.slot, 1)
        local any = false
        for _, kind in ipairs({ "quest", "dungeon", "ah", "craft" }) do
            local f = finds[kind][1]
            if f then
                any = true
                local main, detail = R.Describe(f)
                P.Row({ link = f.link, title = f.link, sub = main, sub2 = detail, sub3 = ns.Gear.Why(f.link, f.cmp),
                        right = color(GREEN, string.format("+%.1f", f.cmp.delta)), indent = 24 })
            end
        end
        if not any then
            P.Note("      No known upgrade yet from quests, dungeons, the auction house or crafting.", GRAY)
        end
    end
    local counts = R.Counts
    P.Note(string.format("Searched %d dungeon items, %d auction house items and %d craftable items.",
        counts.dungeon, counts.ah, counts.craft), GRAY)
    -- Other slots can still have good finds.
    local weakSet = {}
    for _, w in ipairs(weak) do weakSet[w.slot] = true end
    local extra = {}
    for _, slot in ipairs(D.SlotOrder) do
        if not weakSet[slot] then
            local f = R.Best(slot)
            if f then f.slot = slot extra[#extra + 1] = f end
        end
    end
    table.sort(extra, function(a, b)
        if a.cmp.delta ~= b.cmp.delta then return a.cmp.delta > b.cmp.delta end
        return a.id < b.id
    end)
    if #extra > 0 then
        P.Header("Other upgrades you could get")
        for i = 1, math.min(6, #extra) do
            local f = extra[i]
            local main, detail = R.Describe(f)
            P.Row({ link = f.link, title = color(GOLD, D.SlotNames[f.slot]) .. "   " .. f.link, sub = main, sub2 = detail, sub3 = ns.Gear.Why(f.link, f.cmp),
                    right = color(GREEN, string.format("+%.1f", f.cmp.delta)) })
        end
    end
    for _, hint in ipairs(R.MissingData()) do P.Note(hint, GRAY) end

    P.Header("Equipped")
    for _, slot in ipairs(D.SlotOrder) do
        local g = c.gear[slot]
        if g then
            local dura = ""
            if g.dura and g.dura < 0.5 then dura = ", " .. color(RED, string.format("%d%% durability", g.dura * 100)) end
            P.Row({ link = g.link, sub = D.SlotNames[slot] .. ", item level " .. g.ilvl .. dura,
                    right = color(GRAY, string.format("score %.0f", g.score)) })
        end
    end
end

pages.Bags = function()
    local list, totals = ns.Disposition.EvaluateBags()
    local counts = { AH = 0, DE = 0, VENDOR = 0, KEEP = 0 }
    for _, a in ipairs(list) do counts[a.action] = counts[a.action] + 1 end
    P.Tiles({
        { M(totals.AH), counts.AH .. " to auction", GOLD },
        { M(totals.DE), counts.DE .. " to disenchant", PURPLE },
        { M(totals.VENDOR), counts.VENDOR .. " to vendor" },
        { counts.KEEP, "to keep", BLUE },
    })

    local src = ns.Prices.SourceName()
    local scanInfo = ""
    if not TSM_API and not (Auctionator and Auctionator.API) then
        local last = ns.db.lastFullScan
        scanInfo = last and (" Last full scan " .. ns.Duration(time() - last) .. " ago.") or " No scan yet: open the auction house and a scan starts by itself."
    end
    local ench = ns.Professions.Rank("Enchanting")
    P.Note("Auction prices from " .. src .. "." .. scanInfo .. "\n" ..
        (ench and ("You can disenchant items that need up to " .. ench .. " Enchanting.") or
            "You don't have Enchanting, so items aren't marked Disenchant. Their disenchant value is still shown for reference."), GRAY)

    local sections = {
        { "AH", "Sell on the auction house", "Worth more there than at a vendor, even after the 5% cut." },
        { "DE", "Disenchant", "The materials are worth more than selling the item." },
        { "VENDOR", "Sell to a vendor", "Nothing beats the vendor price." },
        { "KEEP", "Keep", "Upgrades, quest items and materials your recipes use." },
    }
    for _, sec in ipairs(sections) do
        local action, title, why = sec[1], sec[2], sec[3]
        if counts[action] > 0 then
            local total = action == "AH" and totals.AH or action == "DE" and totals.DE or action == "VENDOR" and totals.VENDOR or nil
            P.Header(ns.Disposition.Labels[action] .. "  " .. color("ffffff", title), total and M(total) or nil)
            P.Note(why, GRAY)
            for _, a in ipairs(list) do
                if a.action == action then
                    local alt = {}
                    if action ~= "VENDOR" and a.vendor > 0 then alt[#alt + 1] = "vendor " .. M(a.vendor) end
                    if action ~= "AH" and a.ah then alt[#alt + 1] = "auction ~" .. M(a.ah) end
                    if action ~= "DE" and a.de and a.de > 0 then alt[#alt + 1] = "disenchant ~" .. M(a.de) end
                    local sub = a.reason or ""
                    if #alt > 0 then sub = sub .. (sub ~= "" and "   " or "") .. color(GRAY, "Other options: " .. table.concat(alt, ", ")) end
                    local value = (action == "AH" and a.ah) or (action == "DE" and a.de) or (action == "VENDOR" and a.vendor) or nil
                    P.Row({ link = a.link, title = a.link .. (a.count > 1 and color(GRAY, "  x" .. a.count) or ""),
                            sub = sub ~= "" and sub or nil, right = value and M(value) or nil })
                end
            end
        end
    end
    if #list == 0 then P.Note("Your bags are empty.", GRAY) end
end

pages.Professions = function()
    local c = ns.char
    local PR = ns.Professions
    local CR = ns.Crates
    local profs = c.professions or {}
    if #profs == 0 then
        P.Note("You haven't learned any professions yet. Profession trainers are in every capital city.", GRAY)
        return
    end

    -- Overview tiles: each profession's skill, plus Merchant's Favor.
    local tiles = {}
    for _, p in ipairs(profs) do
        if #tiles < 3 then
            local capped = (p.rank or 0) >= (p.max or 1)
            tiles[#tiles + 1] = { string.format("%d/%d", p.rank or 0, p.max or 0), p.name .. (capped and "  (capped)" or ""), capped and "ff8040" or nil }
        end
    end
    local favor = CR.Favor()
    tiles[#tiles + 1] = { favor or "?", "Merchant's Favor", GOLD }
    P.Tiles(tiles)

    local CHANCE = { optimal = "always a skill point", medium = "usually a skill point", easy = "sometimes a skill point" }
    local function recipeRow(name, r, chance)
        if not r then return end
        local plan = PR.Plan(r)
        local short, long = PR.Verdict(plan)
        local mp = ns.Mats.Plan(r, plan.value)
        local link = r.item and select(2, ns.C.GetItemInfo(r.item))
        local make = plan.canMake and color(GREEN, "  ·  can make now") or color("ff8080", "  ·  missing materials")
        P.Row({ link = link, icon = (not link) and ICONS.Professions or nil,
                title = color(PR.DiffColor[r.diff] or "ffffff", name) .. (chance and color(GRAY, "  ·  " .. chance) or "") .. make,
                sub = ns.Mats.Line(mp), sub2 = ns.Mats.Summary(mp) .. color(GRAY, "   ·   Then: ") .. long, right = short })
    end

    for _, p in ipairs(profs) do
        P.Header(p.name, string.format("%d / %d", p.rank or 0, p.max or 0))
        P.Bar("Skill", p.rank or 0, p.max or 0, (p.rank or 0) >= (p.max or 1) and "ff8040" or "4cc94c")
        local hint = PR.TrainerHint(p)
        if hint then P.Row({ icon = ICONS.Trainer, title = color(GOLD, hint) }) end
        local rec = c.recipes[p.name]
        local gathering = p.name == "Herbalism" or p.name == "Mining" or p.name == "Skinning" or p.name == "Fishing"
        if rec then
            local ups = PR.SkillUps(p.name)
            P.SubHeader("Level it up")
            if #ups == 0 then
                P.Note("None of your recipes give skill points anymore. See Recipes to get below, or visit a trainer.", GRAY)
            end
            for i = 1, math.min(4, #ups) do
                recipeRow(ups[i].name, PR.Recipe(p.name, ups[i].name), CHANCE[ups[i].diff])
            end
            local money = PR.Profitable(p.name, 3)
            if #money > 0 then
                P.SubHeader("Make money")
                for _, m in ipairs(money) do recipeRow(m.name, m.r) end
            end
            local toGet = PR.ToGet(p.name, 5)
            P.SubHeader("Recipes to get")
            if #toGet == 0 then
                P.Note("No unlearned recipe makes an upgrade or a profit right now (with the prices known so far).", GRAY)
            end
            for _, g in ipairs(toGet) do
                local why
                if g.upgrade then
                    local w = ns.Gear.Why(select(2, ns.C.GetItemInfo(g.r.item)) or "", g.plan.result.cmp)
                    why = color(GREEN, string.format("Upgrade +%.1f", g.delta)) .. (w and (": " .. w) or "")
                else
                    why = color(GREEN, "Profit ~" .. M(g.profit) .. " each") .. color(GRAY, " (sells for more than its materials)")
                end
                local link = select(2, ns.C.GetItemInfo(g.r.item))
                local gmp = ns.Mats.Plan(g.r, g.plan.value)
                P.Row({ link = link, title = g.name, sub = why, sub2 = color(GRAY, "Get it: ") .. g.where,
                        sub3 = color(GRAY, "Materials: ") .. ns.Mats.Summary(gmp),
                        right = g.cost and color(GOLD, g.cost) or nil })
            end
        elseif not gathering then
            P.Note("Open your " .. p.name .. " window once so its recipes are recorded.", GOLD)
        end
    end

    -- Merchant's Favor: crates and the recipes Favor can buy.
    local wanted = CR.WantedRecipes()
    local sealed, fillable = CR.Todo()
    if sealed > 0 or #fillable > 0 or #wanted > 0 then
        P.Header("Merchant's Favor", favor and (favor .. " Favor") or nil)
        if sealed > 0 then
            P.Row({ icon = ICONS.Bags, title = string.format("Turn in %d sealed crate%s", sealed, sealed > 1 and "s" or ""),
                    sub = CR.TurnIn[UnitFactionGroup("player")] or "" })
        end
        for _, f in ipairs(fillable) do
            P.Row({ icon = ICONS.Bags, title = "Fill " .. f.crate, sub = string.format("You have %d %s (needs %d)", f.with.have, f.with.name, f.with.qty) })
        end
        for i = 1, math.min(5, #wanted) do
            local w = wanted[i]
            P.Row({ link = w.link, icon = (not w.link) and ICONS.Trainer or nil, title = w.name .. color(GRAY, "  ·  " .. w.prof),
                    sub = w.upgrade and color(GREEN, string.format("Makes an upgrade for you (+%.1f)", w.delta)) or color(GRAY, "Doesn't make an upgrade for you right now"),
                    right = w.cost and color(GOLD, w.cost .. " Favor") or nil })
        end
    end

    local others = {}
    for key, other in pairs(ns.db.chars) do
        if other ~= c and other.professions and #other.professions > 0 then
            local parts = {}
            for _, p in ipairs(other.professions) do parts[#parts + 1] = p.name .. " " .. (p.rank or 0) end
            others[#others + 1] = { ns.CharLabel(other, key), table.concat(parts, ", ") }
        end
    end
    if #others > 0 then
        P.Header("Your other characters")
        for _, o in ipairs(others) do P.Row({ title = o[1], sub = o[2] }) end
    end
end

pages.Money = function()
    local plan = ns.MoneyPlan.Plan()
    local best = plan.crafts[1]
    P.Tiles({
        { M(plan.totalGold), "Gold on all characters", GOLD },
        { M(plan.totalCash), "Ready to cash in", GREEN },
        { best and M(best.profit) or "--", "Best craft profit (each)" },
        { plan.enchanter and plan.enchanter.rank or "none", "Your best Enchanting skill", PURPLE },
    })
    if not next(ns.db.prices) and not TSM_API and not (Auctionator and Auctionator.API) then
        P.Note("No auction prices yet. Open the auction house once and a price scan runs by itself; this page fills in after that.", GOLD)
    end

    P.Header("Cash in", M(plan.totalCash))
    local any = false
    for _, row in ipairs(plan.chars) do
        if row.total > 0 then
            any = true
            local parts = {}
            if row.ah > 0 then parts[#parts + 1] = string.format("auction %d item%s ~%s", row.ahItems, row.ahItems > 1 and "s" or "", M(row.ah)) end
            if row.mailDE > 0 then parts[#parts + 1] = "disenchant ~" .. M(row.mailDE) end
            if row.junk > 0 then parts[#parts + 1] = "vendor junk " .. M(row.junk) end
            local me = row.char == ns.char
            P.Row({ icon = ICONS.Coin, title = row.label .. color(GRAY, "  ·  " .. M(row.gold) .. " on hand") .. (me and color(BLUE, "  (you)") or ""),
                    sub = table.concat(parts, ", "), right = color(GREEN, M(row.total)), onClick = me and go("Bags") or nil })
        end
    end
    if not any then P.Note("Nothing to sell right now on any character (as of their last login).", GRAY) end

    if plan.enchanter and #plan.mail > 0 then
        P.Header("Mail to your enchanter", ns.CharLabel(plan.enchanter.char))
        P.Note("These unbound items are worth more as enchanting materials than sold. Mail them to "
            .. ns.CharLabel(plan.enchanter.char) .. " to disenchant.", GRAY)
        for _, row in ipairs(plan.mail) do
            local links = {}
            for i = 1, math.min(3, #row.mailItems) do links[#links + 1] = row.mailItems[i].link or row.mailItems[i].name end
            local more = #row.mailItems - 3
            P.Row({ icon = ICONS.Bags, title = "From " .. row.label,
                    sub = table.concat(links, ", ") .. (more > 0 and color(GRAY, " and " .. more .. " more") or ""),
                    right = color(PURPLE, "~" .. M(row.mailDE)) })
        end
    end

    P.Header("Craft and sell", "profit after materials")
    P.Choices("Grinding:", {
        { label = "Skip grinds", active = ns.db.settings.noGrind, onClick = function() ns.db.settings.noGrind = true ns.RenderUI() end },
        { label = "Show everything", active = not ns.db.settings.noGrind, onClick = function() ns.db.settings.noGrind = false ns.RenderUI() end },
    })
    if (plan.hiddenGrind or 0) > 0 then
        P.Note(string.format("%d recipe%s hidden because the materials mean grinding mobs far below your level.",
            plan.hiddenGrind, plan.hiddenGrind > 1 and "s" or ""), GRAY)
    end
    if #plan.crafts == 0 then
        P.Note("No profitable recipes found yet. Open each character's profession windows once so recipes are recorded, and scan the AH.", GRAY)
    end
    for i = 1, math.min(6, #plan.crafts) do
        local cr = plan.crafts[i]
        local link = select(2, ns.C.GetItemInfo(cr.item))
        P.Row({ link = link, title = color(GOLD, cr.recipe) .. color(GRAY, "  ·  " .. cr.who .. ", " .. cr.prof),
                sub = cr.mp and ns.Mats.Line(cr.mp) or nil,
                sub2 = (cr.mp and (ns.Mats.Summary(cr.mp) .. color(GRAY, "   ·   ")) or "")
                    .. string.format("sells ~%s after the AH cut, materials worth ~%s", M(cr.value), M(cr.cost)),
                right = color(GREEN, "+" .. M(cr.profit)) })
    end

    if #plan.gather > 0 then
        P.Header("Gather and sell")
        for _, g in ipairs(plan.gather) do
            local parts = {}
            for i = 1, math.min(3, #g.best) do parts[#parts + 1] = g.best[i].name .. " ~" .. M(g.best[i].price) end
            local nextLine
            if g.nextUp then
                nextLine = color(GRAY, string.format("At %d skill: %s%s", g.nextUp.skill, g.nextUp.name,
                    g.nextUp.price and (" ~" .. M(g.nextUp.price) .. " each") or ""))
            end
            P.Row({ icon = ICONS.Zone, title = g.who .. color(GRAY, string.format("  ·  %s %d", g.prof, g.rank)),
                    sub = #parts > 0 and ("Best to farm: " .. table.concat(parts, ", ") .. " each") or color(GRAY, "No prices yet for what they can gather"),
                    sub2 = nextLine })
        end
    end
    P.Note("Other characters' numbers are from the last time you logged in on them. Log in on each once (and open their bank and profession windows) to include them.", GRAY)
end

pages.Talents = function()
    local r = ns.Spec.Report()
    local spec = r.spec
    local label = r.manual and "Spec (chosen by you)" or (r.guess and "Spec (guessed)" or "Spec (detected)")
    if r.modern then
        P.Tiles({ { spec.name .. "  " .. color(GRAY, spec.role), label, r.guess and "ff8040" or BLUE } })
        P.Header("Couldn't read your talents")
        P.Note("The game didn't report a talent tree Forever Companion can read. Gear advice still works using the spec above; " ..
            "pick a different one on the Gear page if it's wrong.", GRAY)
        P.Note("What the game reports (also saved so it can be checked outside the game):", GRAY)
        for _, line in ipairs(ns.Spec.SaveDiagnostics()) do P.Row({ title = line }) end
        return
    end
    local tiles = { { spec.name .. "  " .. color(GRAY, spec.role), label, r.guess and "ff8040" or BLUE } }
    for i, tree in ipairs(r.trees) do
        if #tiles >= 3 then break end
        tiles[#tiles + 1] = { tree.points, (tree.name or ("Tree " .. i)) .. (i == r.specTree and "  (your spec)" or ""),
                              i == r.specTree and GOLD or nil }
    end
    tiles[#tiles + 1] = { r.unspent, "Unspent points", r.unspent > 0 and GREEN or nil }
    P.Tiles(tiles)
    P.Note("Gear is scored for " .. ns:SpecLabel() .. ", " .. tostring(r.how) .. ".", r.guess and "ff8040" or GRAY)

    local tree = r.specTree and r.trees[r.specTree]
    P.Header("Your " .. spec.name .. " talents", tree and (tree.points .. " points") or nil)
    local any = false
    for _, t in ipairs(tree and tree.talents or {}) do
        if t.rank > 0 then
            any = true
            P.Row({ title = t.name, right = t.rank >= t.max and color(GREEN, "maxed") or string.format("%d / %d", t.rank, t.max) })
        end
    end
    if not any then P.Note(tree and "No points in this tree yet." or "Couldn't tell which tree is " .. spec.name .. ".", GRAY) end

    local g = r.guide
    if g then
        local treeName = {}
        for _, s in ipairs(D.Specs[ns.char.class] or {}) do treeName[s.tree] = treeName[s.tree] or s.name end
        local function why(s)
            local parts = {}
            if s.tree and s.tree ~= spec.tree then parts[#parts + 1] = treeName[s.tree] .. " talent" end
            if s.note then parts[#parts + 1] = s.note end
            return #parts > 0 and table.concat(parts, ". ") or nil
        end
        P.Header("Best talent to take next", g.build.name)
        if g.best then
            local b = g.best
            P.Row({ icon = ICONS.Talents, title = color(GOLD, b.name) .. string.format("   rank %d of %d", b.rank + 1, b.max),
                    sub = why(b) or ("Next step in the " .. spec.name .. " build"),
                    right = string.format("%d / %d", b.rank, b.max) })
            if b.tree and b.tree ~= spec.tree and g.bestInTree then
                local s = g.bestInTree
                P.Row({ title = "Rather stay in " .. spec.name .. "?  " .. s.name .. string.format("   rank %d of %d", s.rank + 1, s.max),
                        sub = s.note or "The next " .. spec.name .. " pick in the same build", right = string.format("%d / %d", s.rank, s.max) })
            end
        else
            P.Note(#g.remaining > 0 and "The next talents in the build are locked; spend points higher in the tree first."
                or "You've finished this build.", GRAY)
        end
        if #g.remaining > 1 then
            P.Header("Coming up in this build")
            local shown = 0
            for _, s in ipairs(g.remaining) do
                if s ~= g.best and shown < 6 then
                    shown = shown + 1
                    P.Row({ title = s.name .. color(GRAY, string.format("  to %d/%d", s.target, s.max)), sub = why(s),
                            right = s.open and string.format("%d / %d", s.rank, s.max) or color(GRAY, "locked") })
                end
            end
        end
        local missing = {}
        for _, s in ipairs(g.steps) do if not s.found then missing[s.name] = true end end
        local m = {}
        for name in pairs(missing) do m[#m + 1] = name end
        if #m > 0 then P.Note("Not in your talent tree (renamed or removed in Forever): " .. table.concat(m, ", "), GRAY) end
        P.Note("Build: " .. g.build.name .. ", from " .. g.build.source .. ". Points are listed in the order to take them.", GRAY)
    else
        P.Header("What you can take next", "from the game's " .. spec.name .. " tree")
        local shown = 0
        for _, t in ipairs(r.next or {}) do
            if shown >= 8 then break end
            shown = shown + 1
            P.Row({ title = t.open and t.name or color(GRAY, t.name),
                    sub = t.open and (t.rank > 0 and "Keep ranking this up" or "Available now") or "Locked until you spend more points in this tree",
                    right = string.format("%d / %d", t.rank, t.max) })
        end
        if shown == 0 then P.Note("Nothing left to take in this tree.", GRAY) end
        P.Note("There's no Forever build for " .. spec.name .. " built in yet, so this is the tree order, not a recommendation. "
            .. "Leave a Note to Claude with the spec you want and a build can be added.", GRAY)
    end

    -- Other trees, briefly.
    for i, other in ipairs(r.trees) do
        if i ~= r.specTree and other.points > 0 then
            local names = {}
            for _, t in ipairs(other.talents) do if t.rank > 0 then names[#names + 1] = t.name .. " " .. t.rank end end
            P.Note((other.name or ("Tree " .. i)) .. ": " .. table.concat(names, ", "), GRAY)
        end
    end
end

pages.Quests = function()
    local s = ns.Quests.XPStats()
    local t = ns.Quests.Triage()
    P.Tiles({
        { s.toGo, "XP to next level", PURPLE },
        { s.perHour and math.floor(s.perHour) or "--", "XP per hour" },
        { ns.Duration(s.eta), "Time to level" },
        { t.completeXP, "XP waiting to turn in", t.completeXP > 0 and GREEN or nil },
    })
    if #t.complete > 0 then
        P.Header("Ready to turn in", color(GREEN, string.format("%.0f%% of a level", s.max > 0 and t.completeXP / s.max * 100 or 0)))
        for _, q in ipairs(t.complete) do
            P.Row({ icon = ICONS.Quest, title = q.title, right = q.xp > 0 and (q.xp .. " XP") or nil })
        end
    end
    P.Header("In progress", "best first")
    if #t.active == 0 then P.Note("Your quest log is empty. Pick up quests in one of the zones below.", GRAY) end
    for _, q in ipairs(t.active) do
        local hex = ns.Quests.DiffHex[q.diff]
        P.Row({ title = color(hex, string.format("[%d]  %s", q.level or 0, q.title)), sub = q.advice,
                right = q.xp > 0 and (q.xp .. " XP") or nil })
    end
    P.Header("Zones for your level")
    local zones = ns.Quests.Zones()
    if #zones == 0 then P.Note("No suggestions for this level.", GRAY) end
    for _, z in ipairs(zones) do P.Row({ icon = ICONS.Zone, title = z }) end
end

----------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------
local function updateFooter()
    local isBags = current == "Bags"
    local atVendor = ns.Bags.MerchantOpen()
    for _, b in ipairs(footerButtons) do
        b:SetShown(isBags)
        if atVendor then b:Enable() else b:Disable() end
    end
    if isBags and not atVendor then
        footerText:SetText(color(GRAY, "Talk to a vendor to use the sell buttons."))
    else
        footerText:SetText(color(GRAY, PAGE_HINTS[current] or ""))
    end
    footerText:ClearAllPoints()
    if isBags then footerText:SetPoint("LEFT", footerButtons[2], "RIGHT", 12, 0)
    else footerText:SetPoint("BOTTOMLEFT", SIDEBAR + 14, 16) end
end

function ns.RenderUI()
    if not (frame and frame:IsShown() and ns.char) then return end
    resetPools()
    rowIndex = 0
    local ok, err = pcall(pages[current])
    if not ok then
        ns:LogError("page " .. current, err)
        P.Note("Something went wrong drawing this page (saved to the error log): " .. tostring(err), RED)
    end
    content:SetHeight(math.max(y + 10, 10))
    for name, b in pairs(navButtons) do b:SetActive(name == current) end
    local c = ns.char
    subtitle:SetText(string.format("%s, level %d %s", c.name or "", UnitLevel("player"), UnitClass("player") or ""))
    updateFooter()
end
ns.RefreshUI = function() ns:Debounce("ui", 0.3, ns.RenderUI) end

local function navButton(parent, name, index)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SIDEBAR - 16, 34)
    b:SetPoint("TOPLEFT", 8, -8 - (index - 1) * 38)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    b.bar:SetPoint("TOPLEFT")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetWidth(3)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(22, 22)
    b.icon:SetPoint("LEFT", 10, 0)
    b.icon:SetTexture(ICONS[name])
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
    b.label:SetText(name)
    function b:SetActive(on)
        self.bar:SetShown(on)
        self.bg:SetColorTexture(1, 1, 1, on and 0.09 or 0)
        self.label:SetFontObject(on and "GameFontNormal" or "GameFontHighlight")
    end
    b:SetScript("OnClick", function() current = name scroll:SetVerticalScroll(0) ns.RenderUI() end)
    return b
end

local function build()
    frame = CreateFrame("Frame", "ForeverCompanionFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0.06, 0.065, 0.08, 0.97)
    frame:SetBackdropBorderColor(0.3, 0.32, 0.38, 1)
    tinsert(UISpecialFrames, "ForeverCompanionFrame")  -- Escape closes it

    -- Title bar
    local bar = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bar:SetColorTexture(0.1, 0.11, 0.14, 1)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(40)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -13)
    title:SetText("Forever Companion")
    subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("LEFT", title, "RIGHT", 14, 0)
    subtitle:SetTextColor(0.7, 0.7, 0.7)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -5)

    -- Sidebar
    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT", 1, -41)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(SIDEBAR)
    local sbg = side:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints()
    sbg:SetColorTexture(0.08, 0.085, 0.105, 1)
    navButtons = {}
    for i, name in ipairs(PAGE_ORDER) do navButtons[name] = navButton(side, name, i) end
    local help = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("BOTTOMLEFT", 12, 14)
    help:SetWidth(SIDEBAR - 20)
    help:SetJustifyH("LEFT")
    help:SetText("/fc help for commands\nDrag the title bar to move")
    local noteBtn = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
    noteBtn:SetSize(SIDEBAR - 20, 24)
    noteBtn:SetPoint("BOTTOMLEFT", help, "TOPLEFT", -2, 8)
    noteBtn:SetText("Note to Claude")
    noteBtn:SetScript("OnClick", function() StaticPopup_Show("FOREVERCOMPANION_NOTE", current) end)
    noteBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Leave a note about what you see. It's saved with the page you're on; /reload or log out, then ask Claude to read your notes.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    noteBtn:SetScript("OnLeave", GameTooltip_Hide)
    local touchBtn = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
    touchBtn:SetSize(SIDEBAR - 20, 24)
    touchBtn:SetPoint("BOTTOMLEFT", noteBtn, "TOPLEFT", 0, 6)
    local function touchLabel() touchBtn:SetText("Touch mode: " .. (ns.db.settings.touch and "on" or "off")) end
    touchLabel()
    touchBtn:SetScript("OnClick", function() ns:SetTouch(not ns.db.settings.touch) touchLabel() end)
    touchBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Makes the window bigger so it's easier to tap. You can drag lists to scroll either way.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    touchBtn:SetScript("OnLeave", GameTooltip_Hide)

    -- Scrollable content
    scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", SIDEBAR + 14, -54)
    scroll:SetPoint("BOTTOMRIGHT", -32, 46)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 10)
    scroll:SetScrollChild(content)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", dragStart)
    content:EnableMouse(true)
    content:SetScript("OnMouseDown", dragStart)
    frame:SetScript("OnUpdate", dragUpdate)

    -- Footer
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.06)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", SIDEBAR + 1, 40)
    line:SetPoint("BOTTOMRIGHT", -1, 40)
    footerButtons = {}
    local function footerButton(label, tip, fn)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(150, 24)
        if #footerButtons == 0 then b:SetPoint("BOTTOMLEFT", SIDEBAR + 14, 9)
        else b:SetPoint("LEFT", footerButtons[#footerButtons], "RIGHT", 8, 0) end
        b:SetText(label)
        b:SetScript("OnClick", fn)
        b:SetMotionScriptsWhileDisabled(true)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        footerButtons[#footerButtons + 1] = b
    end
    footerButton("Sell gray junk", "Sells every gray (poor quality) item.", function() ns.Bags.SellJunk() end)
    footerButton("Sell 'Vendor' items", "Sells everything in the Sell to a vendor section. You'll be asked first.",
        function() StaticPopup_Show("FOREVERCOMPANION_SELL") end)
    footerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footerText:SetJustifyH("LEFT")

    frame:SetScale(ns.db.settings.touch and 1.25 or 1)
    frame:SetScript("OnShow", ns.RenderUI)
    frame:Hide()
end

StaticPopupDialogs["FOREVERCOMPANION_SELL"] = {
    text = "Sell every item in the 'Sell to a vendor' list? You can buy back the last 12 items from the vendor.",
    button1 = YES, button2 = NO,
    OnAccept = function() ns.Bags.SellAdvised() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function ns:ToggleUI()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end

for _, msg in ipairs({ "GEAR_CHANGED", "BAGS_CHANGED", "PROFESSIONS_CHANGED", "PRICES_CHANGED" }) do
    ns:Listen(msg, ns.RefreshUI)
end
ns:On("QUEST_LOG_UPDATE", function() if current == "Quests" or current == "Overview" then ns.RefreshUI() end end)
ns:On("PLAYER_XP_UPDATE", function() ns.RefreshUI() end)
ns:On("MERCHANT_SHOW", function() ns.RefreshUI() end)
ns:On("MERCHANT_CLOSED", function() ns.RefreshUI() end)

BINDING_HEADER_FOREVERCOMPANION = "Forever Companion"
BINDING_NAME_FOREVERCOMPANION_TOGGLE = "Toggle window"

function ForeverCompanion_Toggle() ns:ToggleUI() end

ns.CurrentPage = function() return current end

StaticPopupDialogs["FOREVERCOMPANION_NOTE"] = {
    text = "Note to Claude about the %s page (saved when you /reload or log out):",
    button1 = "Save", button2 = CANCEL,
    hasEditBox = 1, editBoxWidth = 320, maxLetters = 500,
    OnShow = function(self)
        local eb = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
        if eb then eb:SetText("") eb:SetFocus() end
    end,
    OnAccept = function(self)
        local eb = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
        if eb and ns:AddNote(eb:GetText()) then ns:Print("note saved. /reload or log out so it's written to disk.") end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        if ns:AddNote(self:GetText()) then ns:Print("note saved. /reload or log out so it's written to disk.") end
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- Touch mode: a bigger window that's easier to tap.
function ns:SetTouch(on)
    ns.db.settings.touch = on and true or false
    if frame then frame:SetScale(on and 1.25 or 1) end
    ns:Print("touch mode " .. (on and "on" or "off") .. ".")
end
ns:Command("touch", "toggle touch mode (bigger window, easier to tap)", function() ns:SetTouch(not ns.db.settings.touch) end)
