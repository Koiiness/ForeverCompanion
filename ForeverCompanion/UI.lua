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
    Settings = "Interface\\Icons\\Trade_Engineering",
    Repair = "Interface\\Icons\\Trade_BlackSmithing",
    Coin = "Interface\\Icons\\INV_Misc_Coin_02",
    Quest = "Interface\\GossipFrame\\ActiveQuestIcon",
    Zone = "Interface\\Icons\\INV_Misc_Map_01",
    Clock = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    Trainer = "Interface\\Icons\\INV_Misc_Book_11",
}
local PAGE_ORDER = { "Overview", "Gear", "Bags", "Money", "Professions", "Talents", "Quests", "Settings" }
local PAGE_HINTS = {
    Overview = "Click a to-do item to jump to its page.",
    Gear = "Hover an item for full details. Shift-click to link it in chat.",
    Bags = "Hover an item to see the disenchant odds.",
    Professions = "Open each profession window once so its recipes are recorded.",
    Talents = "Talents come from the game's own tree for your spec.",
    Quests = "Quest colors match the game: yellow gives the best XP for your level.",
    Money = "Covers every character you've logged in with this addon. Prices come from your AH scans.",
    Settings = "Changes save right away.",
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

----------------------------------------------------------------------
-- Sections: each page splits into tabs (P.Section). Only the selected
-- section is drawn, so pages stay short. The tab bar is drawn where the
-- first section starts, after the page has listed all its sections.
----------------------------------------------------------------------
local sectionState = {}   -- page name -> selected section name
local tabRows = {}        -- page name -> how many rows its tab bar used
local sec = {}
local function resetSections() sec = { list = {}, skipping = false, found = false, tabsY = nil } end
resetSections()

-- name: section key; label: tab text (defaults to name); order: tab position (lower first).
function P.Section(name, label, order)
    if not sec.tabsY then
        sec.tabsY = y
        -- Room for the tab bar: one row, or as many as this page needed last time.
        y = y + 52 + 46 * ((tabRows[current] or 1) - 1)
    end
    local seen = false
    for _, s in ipairs(sec.list) do if s.name == name then seen = true break end end
    if not seen then sec.list[#sec.list + 1] = { name = name, label = label or name, order = order or (#sec.list + 1) } end
    sec.skipping = sectionState[current] ~= name
    if not sec.skipping then sec.found = true end
end

function P.Gap(h) if not sec.skipping then y = y + (h or 8) end end

function P.Header(text, right)
    if sec.skipping then return end
    local w = acquire("header", function()
        local f = CreateFrame("Frame", nil, content)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.text:SetPoint("TOPLEFT", 2, -6)
        f.text:SetJustifyH("LEFT")
        f.right = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
    w.right:ClearAllPoints()
    local h = 30
    -- If the title and the right-hand text would collide, put the right text underneath.
    if right and right ~= "" and w.text:GetStringWidth() + w.right:GetStringWidth() + 24 > CONTENT_W then
        w.right:SetPoint("TOPLEFT", w.text, "BOTTOMLEFT", 0, -3)
        h = 46
    else
        w.right:SetPoint("TOPRIGHT", -4, -9)
    end
    place(w, h)
    y = y + 4
end

-- A smaller heading inside a section.
function P.SubHeader(text)
    if sec.skipping then return end
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
    if sec.skipping then return end
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
            f.label:SetWordWrap(false)
            f.label:SetPoint("BOTTOMLEFT", 10, 9)
            f.label:SetPoint("RIGHT", -8, 0)
            f.label:SetJustifyH("LEFT")
            return f
        end)
        w.value:SetFontObject("GameFontHighlightLarge")
        w.value:SetText(t[3] and color(t[3], t[1]) or t[1])
        -- Long values (e.g. a spec name) drop to a smaller font instead of being cut off.
        if w.value:GetStringWidth() > tw - 18 then w.value:SetFontObject("GameFontHighlight") end
        w.label:SetText(t[2])
        w:SetPoint("TOPLEFT", content, "TOPLEFT", (i - 1) * (tw + gap), -y)
        w:SetSize(tw, 54)
    end
    y = y + 54 + 6
end

-- opts: { icon, link, title, sub, right, onClick, tip }
local rowIndex = 0
function P.Row(opts)
    if sec.skipping then return end
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
        f.title:SetWordWrap(true)
        if f.title.SetMaxLines then f.title:SetMaxLines(2) end
        f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.sub:SetJustifyH("LEFT")
        f.sub:SetWordWrap(true)
        if f.sub.SetMaxLines then f.sub:SetMaxLines(4) end
        f.sub2 = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.sub2:SetJustifyH("LEFT")
        f.sub2:SetWordWrap(true)
        if f.sub2.SetMaxLines then f.sub2:SetMaxLines(3) end
        f.sub3 = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.sub3:SetJustifyH("LEFT")
        f.sub3:SetWordWrap(true)
        if f.sub3.SetMaxLines then f.sub3:SetMaxLines(3) end
        f.right = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.right:SetJustifyH("RIGHT")
        f.right:SetWordWrap(false)
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
        w.icon:SetTexture(icon) w.icon:Show() x = 44
    else
        w.icon:Hide()
    end
    -- Text wraps instead of trailing off; the row grows to fit.
    local indent = opts.indent or 0
    local rowW = CONTENT_W - indent
    local rightPad = opts.onClick and 22 or 10
    w.right:ClearAllPoints()
    w.right:SetText(opts.right or "")
    local rightW = opts.right and math.min(200, w.right:GetStringWidth() + 4) or 0
    w.right:SetWidth(math.max(rightW, 1))
    w.right:SetPoint("TOPRIGHT", -rightPad, -7)
    local textW = rowW - x - rightPad - 6
    local titleW = textW - (rightW > 0 and (rightW + 10) or 0)

    w.title:ClearAllPoints()
    w.title:SetPoint("TOPLEFT", x, -7)
    w.title:SetWidth(titleW)
    w.title:SetText(opts.title or (opts.link or ""))
    local h = 7 + w.title:GetStringHeight()
    local prev = w.title
    for _, key in ipairs({ "sub", "sub2", "sub3" }) do
        local fs, text = w[key], opts[key]
        fs:ClearAllPoints()
        if text and text ~= "" then
            fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -3)
            fs:SetWidth(textW)
            fs:SetText(text)
            fs:Show()
            h = h + 3 + fs:GetStringHeight()
            prev = fs
        else
            fs:Hide()
        end
    end
    h = math.max(h + 8, icon and 42 or 30)
    w.arrow:SetShown(opts.onClick ~= nil)
    place(w, h, indent)
    y = y + 2
end


-- A label followed by toggle buttons: { { label, active, onClick } ... }
function P.Choices(label, choices)
    if sec.skipping then return end
    -- The label sits on its own line so long labels never run into the buttons.
    if label and label ~= "" then
        local holder = acquire("choiceLabel", function()
            local f = CreateFrame("Frame", nil, content)
            f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            f.text:SetPoint("BOTTOMLEFT", 2, 3)
            f.text:SetJustifyH("LEFT")
            return f
        end)
        holder.text:SetText((label:gsub(":$", "")))
        holder:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        holder:SetSize(CONTENT_W, 20)
        y = y + 22
    end
    local x, rowY = 0, y
    for _, ch in ipairs(choices) do
        local b = acquire("choice", function()
            local f = CreateFrame("Button", nil, content, "BackdropTemplate")
            f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            f.text:SetPoint("CENTER")
            local hl = f:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.08)
            f:SetScript("OnMouseDown", dragStart)
            f:SetScript("OnClick", function(self) if not wasDrag() and self.fn then self.fn() end end)
            return f
        end)
        b.text:SetText(ch.label)
        local w = math.max(72, b.text:GetStringWidth() + 32)
        if x + w > CONTENT_W and x > 0 then x, rowY = 0, rowY + 48 end
        b:SetPoint("TOPLEFT", content, "TOPLEFT", x, -rowY)
        b:SetSize(w, 40)
        if ch.active then
            b:SetBackdropColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.35)
            b:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
        else
            b:SetBackdropColor(1, 1, 1, 0.04)
            b:SetBackdropBorderColor(1, 1, 1, 0.15)
        end
        b.fn = ch.onClick
        x = x + w + 8
    end
    y = rowY + 50
end


-- The "Next up" card: one highlighted suggestion with one main button and
-- "Not now". opts: { icon, title, sub, button, action, onSkip }
function P.Hero(opts)
    if sec.skipping then return end
    local w = acquire("hero", function()
        local f = newBackdrop(content, 0.12, 0.10, 0.04, 0.97)
        f:SetBackdropBorderColor(1, 0.82, 0, 0.75)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetSize(40, 40)
        f.icon:SetPoint("TOPLEFT", 12, -12)
        f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        f.kicker = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.kicker:SetPoint("TOPLEFT", 64, -10)
        f.kicker:SetText("NEXT UP")
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOPLEFT", f.kicker, "BOTTOMLEFT", 0, -3)
        f.title:SetJustifyH("LEFT")
        f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
        f.sub:SetJustifyH("LEFT")
        f.sub:SetSpacing(2)
        f.main = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.main:SetSize(130, 40)
        f.main:SetPoint("BOTTOMRIGHT", -12, 12)
        f.main:SetScript("OnClick", function(self) if self.fn then self.fn() end end)
        f.skip = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.skip:SetSize(100, 40)
        f.skip:SetPoint("RIGHT", f.main, "LEFT", -8, 0)
        f.skip:SetText("Not now")
        f.skip:SetScript("OnClick", function(self) if self.fn then self.fn() end end)
        return f
    end)
    w.icon:SetTexture(opts.icon or "Interface\\Icons\\INV_Misc_Book_09")
    local textW = CONTENT_W - 64 - 16
    w.title:SetWidth(textW)
    w.title:SetText(opts.title)
    w.sub:SetWidth(textW)
    w.sub:SetText(opts.sub or "")
    w.main:SetShown(opts.action ~= nil)
    w.main:SetText(opts.button or "Show me")
    w.main.fn = opts.action
    w.skip:SetShown(opts.onSkip ~= nil)
    w.skip.fn = opts.onSkip
    local textH = 10 + 12 + 3 + w.title:GetStringHeight() + 4 + w.sub:GetStringHeight()
    local h = textH + ((opts.action or opts.onSkip) and 62 or 14)
    place(w, math.max(h, 70))
    y = y + 10
end

-- A teaching tip shown just in time, once. "Got it" hides it for good;
-- the "I know WoW" setting hides all tips.
function P.Tip(key, text)
    if sec.skipping then return end
    if ns.db.settings.knowWoW then return end
    ns.db.tipsSeen = ns.db.tipsSeen or {}
    if ns.db.tipsSeen[key] then return end
    local w = acquire("tip", function()
        local f = newBackdrop(content, 0.10, 0.16, 0.22, 0.95)
        f:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.6)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetSize(24, 24)
        f.icon:SetPoint("TOPLEFT", 10, -10)
        f.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
        f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.text:SetPoint("TOPLEFT", 44, -10)
        f.text:SetJustifyH("LEFT")
        f.text:SetJustifyV("TOP")
        f.text:SetSpacing(2)
        f.button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.button:SetSize(90, 30)
        f.button:SetPoint("BOTTOMRIGHT", -10, 10)
        f.button:SetText("Got it")
        f.button:SetScript("OnClick", function(self)
            ns.db.tipsSeen[self.key] = true
            ns.RenderUI()
        end)
        return f
    end)
    w.button.key = key
    w.text:SetWidth(CONTENT_W - 44 - 110)
    w.text:SetText(text)
    local h = math.max(54, w.text:GetStringHeight() + 22)
    if y > 0 then y = y + 6 end
    place(w, h)
    y = y + 8
end

function P.Note(text, hex)
    if sec.skipping then return end
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

function P.Bar(label, value, max, hex, valueText)
    if sec.skipping then return end
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
    w.value:SetText(valueText or string.format("%s / %s", value, max))
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
    -- Next up: the single best thing to do right now (Not now skips it for this session).
    do
        local skipped = ns.skippedNext or {}
        ns.skippedNext = skipped
        local function skip(key) return function() skipped[key] = true ns.RenderUI() end end
        local hero
        local xpLeftNow = level < maxLevel and (s.max - s.xp) or nil
        -- 1. An upgrade in your bags you can wear now.
        for _, u in ipairs(ns.Gear.BagUpgrades()) do
            local req = select(5, ns.C.GetItemInfo(u.link)) or 0
            if req <= level and not skipped["up:" .. u.link] then
                hero = { icon = itemIcon(u.link), title = "Upgrade in your bags: " .. u.link,
                         sub = (D.SlotNames[u.cmp.slot] or "") .. ", " .. ns.Gear.UpText(u.cmp) .. " for " .. ns:SpecLabel()
                             .. (ns.Gear.Why(u.link, u.cmp, 3) and ("\n" .. ns.Gear.Why(u.link, u.cmp, 3)) or ""),
                         button = "Equip", onSkip = skip("up:" .. u.link),
                         action = function()
                             if InCombatLockdown() then ns:Print("you can equip it after combat.") return end
                             local equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
                             if equip then equip(u.link, u.cmp.slot) end
                         end }
                break
            end
        end
        -- 2. A talent point.
        local r = ns.Spec.Report()
        if not hero and r.unspent and r.unspent > 0 and not skipped.talent then
            local pick = ns.Spec.NextPick(r)
            hero = { icon = ICONS.Talents, title = string.format("%d talent point%s ready", r.unspent, r.unspent > 1 and "s" or ""),
                     sub = pick and ("Suggested: " .. pick.name .. (pick.note and (". " .. pick.note) or "")) or "Open your talents to spend it.",
                     button = "Talents", action = go("Talents"), onSkip = skip("talent") }
        end
        -- 3. Finished quests that would level you up.
        local tri = ns.Quests.Triage()
        if not hero and #tri.complete > 0 and not skipped.turnin then
            local levels = xpLeftNow and tri.completeXP >= xpLeftNow
            hero = { icon = ICONS.Quest, title = string.format("Turn in %d finished quest%s", #tri.complete, #tri.complete > 1 and "s" or ""),
                     sub = (tri.completeXP > 0 and (tri.completeXP .. " XP") or "Free rewards") .. (levels and ", enough to level up!" or " waiting for you."),
                     button = "Show quests", action = go("Quests"), onSkip = skip("turnin") }
        end
        -- 4. Where to quest.
        local QDn = ns.QuestDB
        if not hero and QDn and QDn.zones and QDn.zones[1] and not skipped.zone then
            local z = QDn.zones[1]
            hero = { icon = ICONS.Zone, title = "Good place to quest: " .. z.name,
                     sub = string.format("%d quests at your level you haven't done yet.", z.count),
                     button = "See the plan", action = function() ns.RenderUI() end, onSkip = skip("zone") }
        end
        if hero then
            if hero.button == "See the plan" then hero.action = nil end
            P.Hero(hero)
        end
    end

    P.Tiles({
        { level, level < maxLevel and string.format("Level (%.0f%% to next)", s.max > 0 and s.xp / s.max * 100 or 0) or "Level (max)", GOLD },
        { string.format("%.1f", c.avgIlvl or 0), "Average item level" },
        { M(GetMoney()), "Gold on hand" },
        { M(totals.AH + totals.DE + totals.VENDOR), "Bag items you can cash in", GREEN },
    })

    P.Section("Plan", "Now", 1)
    -- Your plan: what to do now at your level, then what's coming up.
    local plan = ns.Research.Plan()
    local tri = ns.Quests.Triage()
    local QD = ns.QuestDB
    local xpLeft = level < maxLevel and (s.max - s.xp) or nil
    P.Header("Your plan", xpLeft and string.format("level %d  ·  %d XP to %d", level, xpLeft, level + 1) or ("level " .. level))
    P.Tip("plan", "This plan updates as you play. It picks quests, zones and dungeons that fit your level and your gear. Tap any row for details; nothing here is required.")

    -- Something to look forward to: what the next level brings.
    if level < maxLevel then
        local nl = ns.Research.NextLevel()
        local bits = {}
        if nl.talent then bits[#bits + 1] = "a talent point" end
        if nl.spells then bits[#bits + 1] = #nl.spells == 1 and nl.spells[1] or (#nl.spells .. " new spells at your trainer") end
        for i = 1, math.min(2, #nl.items) do bits[#bits + 1] = nl.items[i] end
        if #bits > 0 then
            P.Row({ icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight", title = string.format("Next up: level %d", nl.level),
                    sub = "Brings " .. table.concat(bits, ", "), right = color(PURPLE, xpLeft .. " XP to go"), onClick = go("Gear") })
        end
    end

    local function upgradeList(items, n)
        local parts = {}
        for j = 1, math.min(n, #items) do
            local it = items[j]
            parts[#parts + 1] = (D.SlotNames[it.slot] or "?") .. color(GREEN, " " .. ns.Gear.UpText(it.f.cmp))
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
            parts[#parts + 1] = (it.f.link or "?") .. color(GREEN, " " .. ns.Gear.UpText(it.f.cmp)) .. (it.choice and color(GRAY, " (choose it)") or "")
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

    local nowCount = 0
    -- 1. Turn in finished quests: free XP.
    if #tri.complete > 0 then
        local names = {}
        for i = 1, math.min(3, #tri.complete) do names[#names + 1] = tri.complete[i].title end
        P.Row({ icon = ICONS.Quest, title = string.format("Turn in %d finished quest%s", #tri.complete, #tri.complete > 1 and "s" or ""),
                sub = table.concat(names, ", ") .. (#tri.complete > 3 and ", ..." or ""),
                right = tri.completeXP > 0 and color(GREEN, string.format("%d XP%s", tri.completeXP,
                    xpLeft and tri.completeXP >= xpLeft and "  (enough to level up!)" or "")) or nil, onClick = go("Quests") })
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
    -- Play style: solo players see one dungeon (and a nudge to group up), groups see more.
    local style = ns.db.settings.playStyle or "both"
    local maxD = style == "solo" and 1 or (style == "group" and 3 or 2)
    for _, d in ipairs(plan.dungeons) do
        if d.when == "soon" then soonD[#soonD + 1] = d
        elseif shownD < maxD then dungeonRow(d) shownD = shownD + 1 nowCount = nowCount + 1 end
    end
    if style == "solo" and shownD > 0 then
        P.Note("Dungeons need a group: try the Group Finder or ask your guild.", GRAY)
    end
    if nowCount == 0 then P.Note("Nothing specific yet. Keep questing; this fills in as data loads.", GRAY) end

    if #soonQ > 0 or #soonD > 0 then
        P.Section("Coming", "Coming up", 2)
        for i = 1, math.min(2, #soonQ) do questRow(soonQ[i]) end
        table.sort(soonD, function(a, b) return (a.inLevels or 0) < (b.inLevels or 0) end)
        for i = 1, math.min(2, #soonD) do dungeonRow(soonD[i]) end
    end
    local missing = {}
    if not ns.Research.HasAtlasLoot() then missing[#missing + 1] = "AtlasLoot Classic Forever (dungeon drops)" end
    if not (QD and QD.Has()) then missing[#missing + 1] = "Questie (quests and questing zones)" end
    if #missing > 0 then P.Note("Install " .. table.concat(missing, " and ") .. " for a fuller plan.", GRAY) end

    P.Section("Plan", "Now", 1)
    P.SubHeader("Also worth doing")
    local n = 0
    do
        local reserve = ns.Gold.Reserve()
        if GetMoney() < reserve then
            local gap = reserve - GetMoney()
            local cash = totals.AH + totals.DE + totals.VENDOR
            local how = cash >= gap and ("Selling your bag items (~" .. M(cash) .. ") would cover it.")
                or (cash > 0 and ("Selling your bag items (~" .. M(cash) .. ") gets you closer; quests pay gold too.") or "Quest rewards and vendoring loot will get you there.")
            P.Row({ icon = ICONS.Coin, title = color(GOLD, "Safety net: " .. M(GetMoney()) .. " of " .. M(reserve)),
                    sub = "Covers repairs and your next class training. " .. how, onClick = go(cash > 0 and "Bags" or "Money") })
            n = n + 1
        end
    end
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
                right = color(GREEN, ns.Gear.UpText(u.cmp)), onClick = go("Gear") })
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
        P.Row({ icon = ICONS.Repair, title = "Gear needs a repair soon",
                sub = string.format("%s is at %d%% durability. Any vendor with an anvil icon can repair it.", D.SlotNames[worst.slot] or "An item", worst.dura * 100), onClick = go("Gear") })
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
            if #mp.mail > 0 then bits[#bits + 1] = "mail green-quality gear to your enchanter to disenchant" end
            P.Row({ icon = ICONS.Money, title = "Make gold", sub = table.concat(bits, ", "), onClick = go("Money") })
            n = n + 1
        end
    end
    if totals.AH + totals.DE + totals.VENDOR > 0 then
        local parts = {}
        if totals.AH > 0 then parts[#parts + 1] = "auction ~" .. M(totals.AH) end
        if totals.DE > 0 then parts[#parts + 1] = "disenchant ~" .. M(totals.DE) end
        if totals.VENDOR > 0 then parts[#parts + 1] = "vendor " .. M(totals.VENDOR) end
        P.Row({ icon = ICONS.Bags, title = "Bag items worth ~" .. M(totals.AH + totals.DE + totals.VENDOR), sub = table.concat(parts, ", "), onClick = go("Bags") })
        n = n + 1
    end
    if n == 0 then P.Note("Nothing pressing. Go adventure!", GRAY) end

    if level < maxLevel then
        P.Section("Leveling", "Leveling", 3)
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
    P.Section("Spec", "Spec & stats", 3)
    local choices = { { label = "Auto", active = not manual, onClick = function() ns:SetSpec("auto") ns.Gear.Snapshot() end } }
    for _, s in ipairs(D.Specs[c.class] or {}) do
        choices[#choices + 1] = { label = s.name .. "  " .. color(GRAY, s.role), active = manual and s.name == spec.name,
            onClick = function() ns.db.settings.specOverride = s.name ns.Gear.Snapshot() end }
    end
    P.Choices("Score gear for:", choices)
    if guess then
        P.Note(UnitLevel("player") < 10 and "Talents start at level 10. Until then, pick the role you play above so gear advice fits." or "Your spec couldn't be detected from your talents. Pick the one you play above so gear advice fits.", GRAY)
    elseif not manual then
        P.Note("Detected " .. how .. ".", GRAY)
    end
    P.Note("Stat priority for " .. spec.name .. ": " .. table.concat(ws, " > ") .. ".", GRAY)

    P.Section("Upgrades", "Upgrades", 1)
    P.Header("Upgrades in your bags", #ups > 0 and color(GREEN, #ups .. " found") or nil)
    P.Tip("upgrades", "Green numbers show how much better an item is for your spec. Stats matter more than item level: the Spec & stats tab shows which stats help you most.")
    if #ups == 0 then P.Note("None right now. Gear you pick up is checked automatically, and you'll get a card when it's an upgrade.", GRAY) end
    for _, u in ipairs(ups) do
        local req = select(5, ns.C.GetItemInfo(u.link)) or 0
        local canNow = req <= UnitLevel("player")
        P.Row({ link = u.link, sub = "Replaces " .. (u.cmp.current or "an empty slot") .. " in " .. (D.SlotNames[u.cmp.slot] or "?")
                .. (u.cmp.note and (", " .. color(GOLD, u.cmp.note)) or ""),
                sub2 = ns.Gear.Why(u.link, u.cmp, 5),
                right = color(GREEN, ns.Gear.UpText(u.cmp)) .. (canNow and color(GRAY, "  tap to equip") or ""),
                onClick = canNow and function()
                    if InCombatLockdown() then ns:Print("you can equip it after combat.") return end
                    local equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
                    if equip then equip(u.link, u.cmp.slot) end
                end or nil })
    end

    -- Chase: one row per weak slot with its best find, other sources in brief.
    P.Section("Chase", "What to chase", 1.2)
    local weak = ns.Gear.WeakSlots()
    if #weak == 0 then P.Note("Every slot is in good shape for your level.", GRAY) end
    local R = ns.Research
    local KIND_SHORT = { quest = "quest", dungeon = "dungeon", ah = "AH", craft = "craft" }
    local function alsoLine(finds, best)
        local parts = {}
        for _, kind in ipairs({ "quest", "dungeon", "ah", "craft" }) do
            local f = finds[kind][1]
            if f and f ~= best then
                local s = f.source
                local extra = ""
                if kind == "dungeon" then extra = " " .. (s.instance or "") .. (s.rate and (" " .. R.FormatRate(s.rate)) or "")
                elseif kind == "ah" then local p = ns.Prices.Market(f.id) extra = p and (" ~" .. M(p)) or ""
                elseif kind == "quest" then extra = " " .. (s.quest or "")
                elseif kind == "craft" then extra = " " .. (s.prof or "") end
                parts[#parts + 1] = KIND_SHORT[kind] .. extra .. " (" .. ns.Gear.UpText(f.cmp) .. ")"
            end
        end
        return #parts > 0 and color(GRAY, "Also: " .. table.concat(parts, "  ·  ")) or nil
    end
    for i = 1, math.min(6, #weak) do
        local w = weak[i]
        local finds = R.ForSlot(w.slot, 1)
        local best
        for _, kind in ipairs({ "quest", "dungeon", "ah", "craft" }) do
            local f = finds[kind][1]
            if f and (not best or f.cmp.delta > best.cmp.delta) then best = f end
        end
        local now = w.link and (w.link .. color(GRAY, "  item level " .. w.ilvl)) or color(GRAY, "nothing equipped")
        if best then
            local main, detail = R.Describe(best)
            P.Row({ link = best.link, title = color(GOLD, D.SlotNames[w.slot]) .. "   " .. best.link,
                    sub = main .. (detail and ("\n" .. detail) or ""), sub2 = alsoLine(finds, best),
                    sub3 = color(GRAY, "Now: ") .. now, right = color(GREEN, ns.Gear.UpText(best.cmp)) })
        else
            P.Row({ icon = w.link and nil or "Interface\\PaperDoll\\UI-Backpack-EmptySlot", link = w.link,
                    title = color(GOLD, D.SlotNames[w.slot]) .. "   " .. (w.link or "Empty slot"),
                    sub = color(GRAY, "No upgrade found yet from quests, dungeons, the AH or crafting."),
                    right = color(GRAY, w.link and (w.gap .. " levels below you") or "empty") })
        end
    end
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
        P.SubHeader("Other slots")
        for i = 1, math.min(5, #extra) do
            local f = extra[i]
            local main, detail = R.Describe(f)
            P.Row({ link = f.link, title = color(GOLD, D.SlotNames[f.slot]) .. "   " .. f.link, sub = main, sub2 = detail,
                    right = color(GREEN, ns.Gear.UpText(f.cmp)) })
        end
    end
    for _, hint in ipairs(R.MissingData()) do P.Note(hint, GRAY) end

    -- Coming soon: upgrades that unlock in the next few levels.
    P.Section("Soon", "Coming soon", 1.5)
    P.Header("Coming soon", "unlocks in the next few levels")
    local soon = ns.Research.ComingSoon(4)
    if #soon == 0 then
        P.Note("Nothing new unlocks in the next few levels yet. Quest rewards and dungeon drops show up here as the addon finds them.", GRAY)
    end
    for i = 1, math.min(8, #soon) do
        local f = soon[i]
        local main, detail = ns.Research.Describe(f)
        P.Row({ link = f.link, title = color(GOLD, "Level " .. f.reqLevel) .. "   " .. f.link,
                sub = (D.SlotNames[f.slot] or "") .. ": " .. main, sub2 = detail, sub3 = ns.Gear.Why(f.link, f.cmp),
                right = color(GREEN, ns.Gear.UpText(f.cmp)) })
    end

    P.Section("Equipped", "Equipped", 2)
    P.Header("Equipped")
    for _, slot in ipairs(D.SlotOrder) do
        local g = c.gear[slot]
        if g then
            local dura = ""
            if g.dura and g.dura < 0.5 then dura = ", " .. color(RED, string.format("%d%% durability", g.dura * 100)) end
            P.Row({ link = g.link, sub = D.SlotNames[slot] .. ", item level " .. g.ilvl .. dura,
                    right = color(GRAY, "item level " .. (g.ilvl or "?")), tip = string.format("Score for your spec: %.0f", g.score or 0) })
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
    local sectionNotes = {
        AH = "Auction prices from " .. src .. "." .. scanInfo,
        DE = ench and ("You can disenchant items that need up to " .. ench .. " Enchanting.") or nil,
        VENDOR = not ench and "You don't have Enchanting, so nothing is marked Disenchant; hover an item for its disenchant value." or nil,
    }
    local short = { AH = "Auction", DE = "Disenchant", VENDOR = "Vendor", KEEP = "Keep" }

    local sections = {
        { "AH", "Sell on the auction house", "Worth more there than at a vendor, even after the auction house's 5% fee." },
        { "DE", "Disenchant", "The materials are worth more than selling the item." },
        { "VENDOR", "Sell to a vendor", "Nothing beats the vendor price." },
        { "KEEP", "Keep", "Upgrades, quest items and materials your recipes use." },
    }
    for i, sd in ipairs(sections) do
        local action, title, why = sd[1], sd[2], sd[3]
        if counts[action] > 0 then
            local total = action == "AH" and totals.AH or action == "DE" and totals.DE or action == "VENDOR" and totals.VENDOR or nil
            P.Section(action, short[action] .. " (" .. counts[action] .. ")", i)
            P.Header(ns.Disposition.Labels[action] .. "  " .. color("ffffff", title), total and M(total) or nil)
            local bagTips = {
                AH = "The auction house sells to other players. It keeps 5% of the sale, and listing costs a small deposit you get back if it sells.",
                DE = "Disenchanting (part of Enchanting) breaks gear into enchanting materials. Hover an item to see what it can turn into.",
                VENDOR = "Gray items are junk: any merchant buys them. The Sell gray junk button below does it in one tap at a vendor.",
                KEEP = "Kept items are things you'll use: upgrades, potions and food, profession tools, and crafting materials.",
            }
            P.Tip("bags-" .. action, bagTips[action])
            P.Note(why .. (sectionNotes[action] and ("  " .. sectionNotes[action]) or ""), GRAY)
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
        P.Note("No professions yet. A gathering pair is the easiest start: Herbalism or Mining earns gold from level 5 while you quest, and Skinning goes with either. Profession trainers are in every capital city.", GRAY)
        return
    end

    -- Overview tiles: each profession's skill, plus Merchant's Favor.
    local tiles = {}
    for _, p in ipairs(profs) do
        if #tiles < 3 then
            local capped = (p.rank or 0) >= (p.max or 1)
            tiles[#tiles + 1] = { string.format("%d/%d", p.rank or 0, p.max or 0), p.name .. (capped and "  (trainer raises the cap)" or ""), capped and "ff8040" or nil }
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
        local make = plan.canMake and color(GREEN, "  ·  can make now") or color(GRAY, "  ·  need materials")
        P.Row({ link = link, icon = (not link) and ICONS.Professions or nil,
                title = color(PR.DiffColor[r.diff] or "ffffff", name) .. (chance and color(GRAY, "  ·  " .. chance) or "") .. make,
                sub = ns.Mats.Line(mp), sub2 = ns.Mats.Summary(mp) .. color(GRAY, "   ·   Then: ") .. long, right = short })
    end

    for pi, p in ipairs(profs) do
        P.Section(p.name, p.name, pi)
        P.Header(p.name, string.format("%d / %d", p.rank or 0, p.max or 0))
        P.Tip("professions", "You can learn two main professions, plus Cooking, First Aid and Fishing. Recipe colors show skill points: orange always gives one, yellow usually, green sometimes, gray never.")
        P.Bar("Skill", p.rank or 0, p.max or 0, (p.rank or 0) >= (p.max or 1) and "ff8040" or "4cc94c")
        local hint = PR.TrainerHint(p)
        if hint then P.Row({ icon = ICONS.Trainer, title = color(GOLD, hint) }) end
        local rec = c.recipes[p.name]
        local gathering = p.name == "Herbalism" or p.name == "Mining" or p.name == "Skinning" or p.name == "Fishing"
        if rec then
            local ups = PR.SkillUps(p.name)
            P.SubHeader("Level it up")
            if #ups == 0 then
                P.Note("Your recipes are all gray now (no more skill points). A trainer or Recipes to get has new ones.", GRAY)
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
                if (g.gap or 0) > 0 then why = why .. color("ff8040", string.format("  ·  %d skill points away", g.gap)) end
                local link = select(2, ns.C.GetItemInfo(g.r.item))
                local gmp = ns.Mats.Plan(g.r, g.plan.value)
                P.Row({ link = link, title = g.name, sub = why, sub2 = color(GRAY, "Get it: ") .. g.where,
                        sub3 = color(GRAY, "Materials: ") .. ns.Mats.Summary(gmp),
                        right = g.cost and (ns.Gold.Affordable(g.costCopper) and color(GOLD, g.cost) or color(GRAY, g.cost .. "  after your safety net")) or nil })
            end
        elseif not gathering then
            P.Note("Open your " .. p.name .. " window once so its recipes are recorded.", GOLD)
        end
    end

    -- Merchant's Favor: crates and the recipes Favor can buy.
    local wanted = CR.WantedRecipes()
    local sealed, fillable = CR.Todo()
    if sealed > 0 or #fillable > 0 or #wanted > 0 then
        P.Section("Favor", "Merchant's Favor", 90)
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
        P.Section("Alts", "Other characters", 95)
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

    -- Safety net: gold to keep for training and repairs, and your savings goal.
    do
        local GO = ns.Gold
        local money = GetMoney()
        local reserve, parts = GO.Reserve()
        local spendable = GO.Spendable()
        P.Section("Safety", "Safety net", 0)
        P.Header("Your gold safety net", "on this character")
        P.Tip("safety", "Your safety net keeps gold for what every character needs: new spells from your class trainer, and repairs. Gold above it is yours to spend on fun.")
        P.Bar("Safety net", math.min(money, reserve), math.max(reserve, 1), money >= reserve and "4cff4c" or "ffd100",
            M(math.min(money, reserve)) .. " of " .. M(reserve))
        P.Row({ icon = ICONS.Coin, title = "Spendable", sub = "What you can spend on crafting and the AH without touching your safety net",
                right = spendable > 0 and color(GREEN, M(spendable)) or color(GRAY, "0, all set aside") })
        P.Row({ icon = ICONS.Repair, title = "Safety net", sub = "Kept aside for the things you'll need", right = M(reserve) })
        for _, p in ipairs(parts) do
            local note = p.known and "" or color(GRAY, (p.label:find("training") and "  (visit your class trainer once to see the real cost)" or "  (estimate until your next repair)"))
            P.Row({ title = "      " .. p.label .. note, right = color(GRAY, M(p.amount)), indent = 24 })
        end
        local _, upcoming, known = GO.Training()
        if known and #upcoming > 0 then
            P.SubHeader("Coming up at your class trainer")
            for i = 1, math.min(6, #upcoming) do
                local s = upcoming[i]
                P.Row({ title = s.name .. (s.rank and s.rank ~= "" and color(GRAY, "  " .. s.rank) or ""),
                        sub = s.level <= UnitLevel("player") and color(GREEN, "you can learn this now") or ("at level " .. s.level),
                        right = M(s.cost) })
            end
        end
        local goal = GO.Goal()
        if goal then
            P.SubHeader("Saving for")
            P.Bar(goal.name .. (goal.default and color(GRAY, "  (Classic price; change in Settings > Gold)") or ""), math.min(money, goal.amount), goal.amount,
                money >= goal.amount and "4cff4c" or "ffd100", M(money) .. " / " .. M(goal.amount))
            local rate, eta = GO.Rate(), GO.TimeTo(goal.amount)
            local msg
            if money >= goal.amount then msg = color(GREEN, "You can afford it now.")
            elseif eta then msg = string.format("At this session's pace (%s per hour) you'll have it in about %s of play.", M(rate), ns.Duration(eta))
            else msg = "Play a little longer this session and the addon will estimate how long it'll take." end
            P.Note(msg, GRAY)
        end
    end

    P.Section("Cash", "Cash in", 1)
    P.Header("Cash in", M(plan.totalCash))
    P.Note("Other characters' numbers are from the last time you logged in on them. Log in on each once (and open their bank and profession windows) to include them.", GRAY)
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
        P.Section("Mail", "Mail to enchanter", 2)
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

    P.Section("Craft", "Craft & sell", 3)
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
        P.Section("Gather", "Gather & sell", 4)
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
end

pages.Settings = function()
    local s = ns.db.settings
    local function set(key, value) return function() s[key] = value ns.RenderUI() end end
    local function onOff(key, default)
        local v = s[key]
        if v == nil then v = default end
        return v
    end

    P.Section("Play", "How you play", 1)
    P.Header("How you play")
    local style = s.playStyle or "both"
    P.Choices("Leveling:", {
        { label = "Mostly solo", active = style == "solo", onClick = set("playStyle", "solo") },
        { label = "Mostly in groups", active = style == "group", onClick = set("playStyle", "group") },
        { label = "Both", active = style == "both", onClick = set("playStyle", "both") },
    })
    P.Note("Solo: your plan shows one dungeon and flags group quests. Groups: more dungeons in your plan.", GRAY)
    local spec, manual = ns:GetSpec()
    P.Row({ icon = ICONS.Talents, title = "Spec for gear: " .. ns:SpecLabel(), sub = manual and "Chosen by you" or "Detected from your talents",
            right = color(GRAY, "change"), onClick = go("Gear") })
    P.Choices("Grinding:", {
        { label = "Skip grinds", active = onOff("noGrind", true), onClick = set("noGrind", true) },
        { label = "Show everything", active = not onOff("noGrind", true), onClick = set("noGrind", false) },
    })

    P.Choices("Tips for newer players:", {
        { label = "Show tips", active = not s.knowWoW, onClick = set("knowWoW", false) },
        { label = "I know WoW (hide tips)", active = s.knowWoW == true, onClick = set("knowWoW", true) },
        { label = "Show all tips again", active = false, onClick = function() ns.db.tipsSeen = {} s.knowWoW = false ns.RenderUI() end },
    })

    P.Section("Gold", "Gold", 2)
    P.Header("Gold safety net")
    local levels = s.reserveLevels or 4
    P.Choices("Keep gold for training:", {
        { label = "Next 2 levels", active = levels == 2, onClick = set("reserveLevels", 2) },
        { label = "Next 4", active = levels == 4, onClick = set("reserveLevels", 4) },
        { label = "Next 6", active = levels == 6, onClick = set("reserveLevels", 6) },
    })
    local goal = ns.Gold.Goal()
    P.Choices("Savings goal:", {
        { label = "Mount at 40", active = goal ~= nil and goal.default == true, onClick = function() ns.char.goal = nil ns.RenderUI() end },
        { label = "None", active = goal == nil, onClick = function() ns.char.goal = false ns.RenderUI() end },
    })
    P.Note(((goal and not goal.default) and ("Custom goal: " .. goal.name .. ", " .. M(goal.amount) .. ".  ") or "")
        .. "For your own goal type /fc goal <gold> <name>, e.g. /fc goal 50 Epic staff.", GRAY)
    P.Choices("Sell gray items at vendors:", {
        { label = "Automatically", active = onOff("autoSellJunk", false), onClick = set("autoSellJunk", true) },
        { label = "I'll press the button", active = not onOff("autoSellJunk", false), onClick = set("autoSellJunk", false) },
    })
    P.Choices("Scan AH prices:", {
        { label = "When I open the AH", active = onOff("autoScan", true), onClick = set("autoScan", true) },
        { label = "Only when I ask", active = not onOff("autoScan", true), onClick = set("autoScan", false) },
    })

    P.Section("Alerts", "Alerts & display", 3)
    P.Header("Alerts")
    P.Choices("Upgrade and level-up cards:", {
        { label = "On", active = onOff("celebrate", true), onClick = set("celebrate", true) },
        { label = "Off", active = not onOff("celebrate", true), onClick = set("celebrate", false) },
        { label = "Preview", active = false, onClick = function() SlashCmdList.FOREVERCOMPANION("testcard") end },
    })
    P.Choices("Card sound:", {
        { label = "On", active = onOff("celebrateSound", true), onClick = set("celebrateSound", true) },
        { label = "Off", active = not onOff("celebrateSound", true), onClick = set("celebrateSound", false) },
    })
    P.Choices("Advice on item tooltips:", {
        { label = "On", active = onOff("tooltip", true), onClick = set("tooltip", true) },
        { label = "Off", active = not onOff("tooltip", true), onClick = set("tooltip", false) },
    })
    P.Header("Display")
    P.Choices("Touch mode (bigger window):", {
        { label = "On", active = onOff("touch", false), onClick = function() ns:SetTouch(true) ns.RenderUI() end },
        { label = "Off", active = not onOff("touch", false), onClick = function() ns:SetTouch(false) ns.RenderUI() end },
    })
    local mmShown = not (ns.db.minimap and ns.db.minimap.hide)
    P.Choices("Minimap button:", {
        { label = "Show", active = mmShown, onClick = function() ns:SetMinimapShown(true) ns.RenderUI() end },
        { label = "Hide", active = not mmShown, onClick = function() ns:SetMinimapShown(false) ns.RenderUI() end },
    })

    P.Section("Data", "Data", 4)
    P.Header("Saved data")
    P.Note("Each character's bags, bank, gear and recipes are saved so pages can plan across characters. Prices, notes and settings are shared.", GRAY)
    P.Row({ icon = ICONS.Bags, title = "Reset this character's data", sub = "Bags and gear refresh right away; open your bank and profession windows again.",
            onClick = function() SlashCmdList.FOREVERCOMPANION("reset") end })
    P.Row({ icon = ICONS.Bags, title = "Reset every character's data", sub = "Prices, notes and settings are kept.",
            onClick = function() SlashCmdList.FOREVERCOMPANION("resetall") end })
    P.Row({ icon = ICONS.Quest, title = "Show errors the addon caught", sub = "Also saved for troubleshooting",
            onClick = function() SlashCmdList.FOREVERCOMPANION("errors") end })
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
    P.Section("Taken", "Your talents", 2)
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
        P.Section("Next", "Best next", 1)
        P.Header("Best talent to take next", g.build.name)
        P.Tip("talents", "You get a talent point every level from 10. This shows the next pick in a proven leveling build; your class trainer can reset talents for a small fee if you change your mind.")
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
            P.Note(#g.remaining > 0 and "The next talents in the build unlock after more points in this tree."
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
        P.Section("Next", "Best next", 1)
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
        P.Note("No suggested build for " .. spec.name .. " yet, so these are listed in tree order.", GRAY)
    end

    -- Other trees, briefly (with your talents).
    P.Section("Taken", "Your talents", 2)
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
        P.Section("Turn in", "Turn in (" .. #t.complete .. ")", 1)
        P.Header("Ready to turn in", color(GREEN, string.format("%.0f%% of a level", s.max > 0 and t.completeXP / s.max * 100 or 0)))
        for _, q in ipairs(t.complete) do
            P.Row({ icon = ICONS.Quest, title = q.title, right = q.xp > 0 and (q.xp .. " XP") or nil })
        end
    end
    P.Section("Active", "In progress (" .. #t.active .. ")", 2)
    P.Header("In progress", "best first")
    P.Tip("quests", "Quest colors compare the quest to your level: yellow and orange give the best XP, green is quick and easy, gray gives little XP, red is too hard for now.")
    if #t.active == 0 then P.Note("Your quest log is empty. The Zones tab shows good places to pick some up.", GRAY) end
    for _, q in ipairs(t.active) do
        local hex = ns.Quests.DiffHex[q.diff]
        P.Row({ title = color(hex, string.format("[%d]  %s", q.level or 0, q.title)), sub = q.advice,
                right = q.xp > 0 and (q.xp .. " XP") or nil })
    end
    P.Section("Zones", "Zones", 3)
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

-- The tab bar for the current page's sections.
local function drawSectionTabs()
    if not sec.tabsY or #sec.list < 2 then return end
    local list = {}
    for _, s in ipairs(sec.list) do list[#list + 1] = s end
    table.sort(list, function(a, b) return a.order < b.order end)
    local x, rowY = 0, sec.tabsY + 4
    for _, s in ipairs(list) do
        local b = acquire("sectiontab", function()
            local f = CreateFrame("Button", nil, content, "BackdropTemplate")
            f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            f.text:SetPoint("CENTER")
            f.line = f:CreateTexture(nil, "ARTWORK")
            f.line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
            f.line:SetPoint("BOTTOMLEFT", 1, 1)
            f.line:SetPoint("BOTTOMRIGHT", -1, 1)
            f.line:SetHeight(2)
            local hl = f:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.08)
            f:SetScript("OnMouseDown", dragStart)
            f:SetScript("OnClick", function(self)
                if wasDrag() then return end
                sectionState[current] = self.section
                scroll:SetVerticalScroll(0)
                ns.RenderUI()
            end)
            return f
        end)
        local active = sectionState[current] == s.name
        b.section = s.name
        b.text:SetText(s.label)
        b.text:SetFontObject(active and "GameFontNormal" or "GameFontHighlight")
        b.line:SetShown(active)
        b:SetBackdropColor(1, 1, 1, active and 0.10 or 0.03)
        b:SetBackdropBorderColor(1, 1, 1, active and 0.25 or 0.10)
        local w = b.text:GetStringWidth() + 32
        if x + w > CONTENT_W and x > 0 then x, rowY = 0, rowY + 46 end
        b:SetPoint("TOPLEFT", content, "TOPLEFT", x, -rowY)
        b:SetSize(w, 40)
        x = x + w + 8
    end
    return math.floor((rowY - sec.tabsY - 4) / 46) + 1
end

function ns.RenderUI()
    if not (frame and frame:IsShown() and ns.char) then return end
    resetPools()
    resetSections()
    rowIndex = 0
    local ok, err = pcall(pages[current])
    -- No section drawn (first visit, or the remembered one is gone): open the
    -- first tab and draw again.
    if ok and sec.tabsY and not sec.found and #sec.list > 0 then
        local first = sec.list[1]
        for _, s in ipairs(sec.list) do if s.order < first.order then first = s end end
        sectionState[current] = first.name
        resetPools()
        resetSections()
        rowIndex = 0
        ok, err = pcall(pages[current])
    end
    sec.skipping = false
    local rows = drawSectionTabs()
    -- Tabs wrapped onto more rows than space was left for: draw again with room.
    if rows and rows ~= (tabRows[current] or 1) then
        tabRows[current] = rows
        return ns.RenderUI()
    end
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
    b:SetSize(SIDEBAR - 16, 40)
    b:SetPoint("TOPLEFT", 8, -8 - (index - 1) * 44)
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
    noteBtn:SetSize(SIDEBAR - 20, 32)
    noteBtn:SetPoint("BOTTOMLEFT", help, "TOPLEFT", -2, 8)
    noteBtn:SetText("Leave a note")
    noteBtn:SetScript("OnClick", function() StaticPopup_Show("FOREVERCOMPANION_NOTE", current) end)
    noteBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Leave a note about what you see. It's saved with the page you're on (written to disk when you /reload or log out).", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    noteBtn:SetScript("OnLeave", GameTooltip_Hide)

    -- Scrollable content
    scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", SIDEBAR + 14, -54)
    scroll:SetPoint("BOTTOMRIGHT", -32, 58)
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
    line:SetPoint("BOTTOMLEFT", SIDEBAR + 1, 52)
    line:SetPoint("BOTTOMRIGHT", -1, 52)
    footerButtons = {}
    local function footerButton(label, tip, fn)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(160, 36)
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
    text = "Note about the %s page (saved when you /reload or log out):",
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
