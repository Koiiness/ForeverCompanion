-- Tooltip: adds upgrade info, the best thing to do with the item, every
-- option's value, and disenchant odds to item tooltips.
local _, ns = ...
local C = ns.C

local ACCENT = { 0.5, 0.83, 1 }
local GRAY = { 0.6, 0.6, 0.6 }

local function bagItemFor(link)
    for _, item in ipairs(ns.char and ns.char.bags or {}) do
        if item.link == link then return item end
    end
end

local function money(v) return v and ns.Money(v) or "|cff808080-|r" end

local function addLines(tooltip)
    if not (ns.db and ns.db.settings.tooltip and ns.char) then return end
    if InCombatLockdown() then return end  -- Forever restricts some data in combat
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local _, link = tooltip:GetItem()
    if not link or type(link) ~= "string" then return end

    local item = bagItemFor(link) or { id = C.ItemID(link), link = link, count = 1 }
    local a = ns.Disposition.Evaluate(item)
    if not a then return end
    local DS = ns.Disposition

    tooltip:AddLine(" ")
    tooltip:AddLine("Forever Companion", ACCENT[1], ACCENT[2], ACCENT[3])

    -- Upgrade line
    local cmp = a.cmp
    if cmp and cmp.unusable then
        tooltip:AddLine("Can't use: " .. (cmp.note or "?"), 1, 0.4, 0.4)
    elseif cmp and cmp.slot and cmp.note ~= "equipped" then
        local d = cmp.delta
        local r, g, b = 0.75, 0.75, 0.75
        local word = "Same as equipped"
        if d > 0.5 then r, g, b, word = 0.3, 1, 0.3, "Upgrade"
        elseif d < -0.5 then r, g, b, word = 1, 0.45, 0.45, "Downgrade" end
        tooltip:AddDoubleLine(string.format("%s for %s (%s)", word, ns.Data.SlotNames[cmp.slot] or "gear", ns:SpecLabel()),
            string.format("%+.1f%s", d, cmp.pct and string.format("  %+.0f%%", cmp.pct) or ""), r, g, b, r, g, b)
        local why = ns.Gear.Why(link, cmp, 5)
        if why then tooltip:AddLine("Why: " .. why, 0.85, 0.85, 0.85, true) end
        if cmp.note then tooltip:AddLine(cmp.note, GRAY[1], GRAY[2], GRAY[3]) end
    end

    -- Verdict
    local count = a.count > 1 and (" (stack of " .. a.count .. ")") or ""
    tooltip:AddDoubleLine("Best: " .. DS.Labels[a.action] .. count, a.reason or "", 1, 1, 1, GRAY[1], GRAY[2], GRAY[3])

    -- Values side by side
    if a.action ~= "KEEP" or a.vendor > 0 or a.market or a.de then
        tooltip:AddDoubleLine("  Sell to vendor", money(a.vendor), 0.85, 0.85, 0.85, 1, 1, 1)
        local ahText = a.ah and ("~" .. ns.Money(a.ah) .. " after cut") or (a.market and "soulbound" or "no price yet")
        tooltip:AddDoubleLine("  Auction house" .. (a.ahSource and (" (" .. a.ahSource .. ")") or ""), ahText, 0.85, 0.85, 0.85, 1, 1, 1)
        if a.de then
            local who = a.canDE and "" or (" (needs " .. a.deSkill .. " Enchanting)")
            tooltip:AddDoubleLine("  Disenchant" .. who, "~" .. ns.Money(a.de) .. (a.dePartial and " +?" or ""),
                0.85, 0.85, 0.85, 1, 1, 1)
        end
    end

    -- Disenchant odds
    local odds = DS.OddsLines(a)
    if #odds > 0 then
        tooltip:AddLine("Disenchants into:", 0.7, 0.45, 1)
        for _, line in ipairs(odds) do tooltip:AddLine("  " .. line, 0.85, 0.85, 0.85) end
    end
    tooltip:Show()
end

ns:Listen("READY", function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            pcall(addLines, tooltip)
        end)
    else
        for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
            tip:HookScript("OnTooltipSetItem", function(self) pcall(addLines, self) end)
        end
    end
end)
