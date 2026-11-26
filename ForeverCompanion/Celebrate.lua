-- Celebrate: a small card with a sound when something good happens.
--   * you get an item that's an upgrade (loot, quest reward, mail, AH...)
--   * you get gear you'll be able to wear in a few levels
--   * you level up: what's new for you at the new level
-- Cards show one at a time at the top of the screen. /fc celebrate turns them off.
local _, ns = ...
local C, D = ns.C, ns.Data
local CE = {}
ns.Celebrate = CE

local GOLD = { 1, 0.82, 0 }
local queue, card = {}, nil

local function enabled() return ns.db and ns.db.settings.celebrate ~= false end

local function playSound(kind)
    local id
    if SOUNDKIT then
        id = (kind == "level" and SOUNDKIT.UI_LEVEL_UP_GAIN) or SOUNDKIT.UI_EPICLOOT_TOAST or SOUNDKIT.UI_GARRISON_FOLLOWER_LEARN_TRAIT
    end
    pcall(PlaySound, id or 888, "Master")
end

----------------------------------------------------------------------
-- The card
----------------------------------------------------------------------
local function buildCard()
    local f = CreateFrame("Frame", "ForeverCompanionToast", UIParent, "BackdropTemplate")
    f:SetSize(380, 96)
    f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    f:SetBackdropColor(0.07, 0.06, 0.04, 0.96)
    f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
    f:EnableMouse(true)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(46, 46)
    f.icon:SetPoint("LEFT", 14, 4)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, 2)
    f.title:SetPoint("RIGHT", -34, 0)
    f.title:SetJustifyH("LEFT")

    f.line1 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.line1:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.line1:SetPoint("RIGHT", -14, 0)
    f.line1:SetJustifyH("LEFT")
    f.line1:SetWordWrap(false)

    f.line2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.line2:SetPoint("TOPLEFT", f.line1, "BOTTOMLEFT", 0, -4)
    f.line2:SetPoint("RIGHT", -14, 0)
    f.line2:SetJustifyH("LEFT")
    f.line2:SetSpacing(2)

    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", 2, 2)
    f.close:SetScript("OnClick", function() CE.Next() end)

    f.button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.button:SetSize(110, 26)
    f.button:SetPoint("BOTTOMRIGHT", -12, 10)
    f.button:SetScript("OnClick", function()
        local action = f.action
        if action then action() end
    end)

    -- Fade out after a while, but not while you're hovering or touching it.
    f:SetScript("OnUpdate", function(self, elapsed)
        if self:IsMouseOver() then self.timeLeft = math.max(self.timeLeft or 0, 3) return end
        self.timeLeft = (self.timeLeft or 0) - elapsed
        if self.timeLeft < 1 then self:SetAlpha(math.max(0, self.timeLeft)) end
        if self.timeLeft <= 0 then CE.Next() end
    end)
    f:Hide()
    return f
end

local function show(c)
    card = card or buildCard()
    card.icon:SetTexture(c.icon or "Interface\\Icons\\INV_Misc_Gift_01")
    card.title:SetText(c.title)
    card.line1:SetText(c.line1 or "")
    card.line2:SetText(c.line2 or "")
    card:SetHeight(c.line2 and c.line2 ~= "" and 112 or 96)
    card.action = c.action
    card.button:SetShown(c.action ~= nil)
    card.button:SetText(c.buttonText or "Equip")
    card.button:SetEnabled(not (c.needsOutOfCombat and InCombatLockdown()))
    card.timeLeft = c.duration or 12
    card:SetAlpha(1)
    card:Show()
    if c.sound then playSound(c.sound) end
end

function CE.Next()
    if card then card:Hide() end
    local c = table.remove(queue, 1)
    if c then show(c) end
end

function CE.Push(c)
    if not enabled() then return end
    if card and card:IsShown() then
        queue[#queue + 1] = c
    else
        show(c)
    end
end

-- Equip buttons only work out of combat.
ns:On("PLAYER_REGEN_ENABLED", function() if card and card:IsShown() then card.button:SetEnabled(true) end end)
ns:On("PLAYER_REGEN_DISABLED", function() if card and card:IsShown() and card.action then card.button:SetEnabled(false) end end)

----------------------------------------------------------------------
-- New items
----------------------------------------------------------------------
local baseline       -- [link] = count, from the last bag snapshot
local pending = {}   -- links waiting for item data before they can be judged

-- Counts by item ID (links can change when an item's name finishes loading),
-- plus one link per ID to judge with.
local function countBags()
    local t, links = {}, {}
    for _, item in ipairs(ns.char and ns.char.bags or {}) do
        if item.id then
            t[item.id] = (t[item.id] or 0) + (item.count or 1)
            if item.link and not item.link:find("%[%]") then links[item.id] = item.link end
        end
    end
    return t, links
end

local function equipAction(link, slot)
    return function()
        if InCombatLockdown() then ns:Print("you can equip it after combat.") return end
        local equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
        if equip then equip(link, slot) end
        CE.Next()
    end
end

local function judge(link)
    local name, _, _, _, reqLevel, _, _, _, equipLoc, icon, _, classID = C.GetItemInfo(link)
    if not name then return false end            -- not loaded yet: try again later
    if not (classID == 2 or classID == 4) or not D.EquipSlots[equipLoc] then return true end
    local cmp = ns.Gear.Compare(link)
    if not cmp or cmp.partial then return false end
    if cmp.unusable or cmp.delta <= 0.5 or cmp.note == "equipped" then return true end
    local why = ns.Gear.Why(link, cmp, 3)
    local slotName = D.SlotNames[cmp.slot] or "gear"
    local pct = cmp.pct and string.format("%+.0f%%", cmp.pct) or string.format("+%.1f", cmp.delta)
    local level = UnitLevel("player")
    if (reqLevel or 0) > level then
        CE.Push({ icon = icon, title = "|cff80d4ffSaved for later|r", line1 = link,
                  line2 = string.format("Upgrade for your %s at level %d (%s for %s).", slotName, reqLevel, pct, ns:SpecLabel()),
                  duration = 8 })
    else
        CE.Push({ icon = icon, title = "Upgrade!", line1 = link,
                  line2 = string.format("|cff4cff4c%s|r for %s, %s%s", pct, ns:SpecLabel(), slotName, why and ("\n" .. why) or ""),
                  sound = "upgrade", action = equipAction(link, cmp.slot), buttonText = "Equip", needsOutOfCombat = true })
    end
    return true
end

local function check()
    if not (enabled() and ns.char) then baseline = (countBags()) return end
    local now, links = countBags()
    if not baseline then baseline = now return end   -- first look after login: nothing is "new"
    for id, n in pairs(now) do
        if n > (baseline[id] or 0) then
            local link = links[id] or select(2, C.GetItemInfo(id))
            if link then pending[link] = GetTime() end
        end
    end
    baseline = now
    for link, t in pairs(pending) do
        local ok, done = pcall(judge, link)
        if not ok or done or GetTime() - t > 10 then pending[link] = nil end
    end
end

ns:Listen("BAGS_CHANGED", check)
ns:On("GET_ITEM_INFO_RECEIVED", function()
    if next(pending) then ns:Debounce("celebrate", 0.5, check) end
end)

----------------------------------------------------------------------
-- Level up
----------------------------------------------------------------------
ns:On("PLAYER_LEVEL_UP", function(_, newLevel)
    if not enabled() then return end
    C_Timer.After(2.5, function()
        local lines = {}
        local r = ns.Spec and ns.Spec.Report()
        if r and r.unspent and r.unspent > 0 then
            local pick = ns.Spec.NextPick(r)
            lines[#lines + 1] = "Talent point ready" .. (pick and (": take |cffffd100" .. pick.name .. "|r") or "")
        end
        if newLevel and newLevel % 2 == 0 then lines[#lines + 1] = "Visit your class trainer for new spells" end
        local ups = ns.Gear.BagUpgrades()
        if #ups > 0 then
            lines[#lines + 1] = string.format("%d upgrade%s in your bags you can wear now", #ups, #ups > 1 and "s" or "")
        end
        local zones = ns.Quests and ns.Quests.Zones() or {}
        if #zones > 0 then lines[#lines + 1] = "Good zones: " .. table.concat(zones, ", ", 1, math.min(2, #zones)) end
        CE.Push({ icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight", title = "Level " .. (newLevel or UnitLevel("player")) .. "!",
                  line1 = "Nice work. Here's what's new:", line2 = table.concat(lines, "\n"), sound = "level",
                  action = function() ns:ToggleUI() CE.Next() end, buttonText = "Open plan", duration = 15 })
    end)
end)

ns:Command("celebrate", "toggle upgrade and level-up cards", function()
    ns.db.settings.celebrate = not enabled()
    ns:Print("celebrations " .. (enabled() and "on" or "off") .. ".")
end)
ns:Command("testcard", "show a sample upgrade card", function()
    local prev = ns.db.settings.celebrate
    ns.db.settings.celebrate = true
    CE.Push({ icon = "Interface\\Icons\\INV_Chest_Cloth_17", title = "Upgrade!", line1 = "|cff1eff00[Sample Robe]|r",
              line2 = "|cff4cff4c+14%|r for " .. ns:SpecLabel() .. ", Chest\n|cff4cff4c+12 Intellect|r, |cff4cff4c+6 Spirit|r",
              sound = "upgrade" })
    ns.db.settings.celebrate = prev
end)
