-- Minimap button. Uses LibDataBroker + LibDBIcon when another addon (such
-- as AtlasLoot) has loaded them, so minimap-button collectors pick it up;
-- otherwise draws its own draggable button.
local ADDON, ns = ...

local ICON = "Interface\\Icons\\INV_Misc_Book_09"

local function onClick(button)
    if button == "RightButton" then
        StaticPopup_Show("FOREVERCOMPANION_NOTE", ns.CurrentPage and ns.CurrentPage() or "Overview")
    else
        ns:ToggleUI()
    end
end

local function fillTooltip(tt)
    tt:AddLine("Forever Companion")
    if ns.char then
        local ok, plan = pcall(ns.Research.Plan)
        if ok and plan then
            local q, d = plan.quests[1], plan.dungeons[1]
            if q then tt:AddLine("Quest: " .. q.name, 1, 1, 1) end
            if d then tt:AddLine("Dungeon: " .. d.name .. " (" .. #d.items .. " upgrades)", 1, 1, 1) end
        end
        local r = ns.Spec.Report()
        if r.unspent and r.unspent > 0 then tt:AddLine(r.unspent .. " unspent talent point(s)", 0.3, 1, 0.3) end
    end
    tt:AddLine(" ")
    tt:AddLine("|cffffd100Left-click|r open or close", 0.8, 0.8, 0.8)
    tt:AddLine("|cffffd100Right-click|r leave a note for Claude", 0.8, 0.8, 0.8)
    tt:AddLine("|cffffd100Drag|r move around the minimap", 0.8, 0.8, 0.8)
end

----------------------------------------------------------------------
-- Own button (no libraries)
----------------------------------------------------------------------
local button
local function updatePosition()
    local angle = math.rad(ns.db.minimap.minimapPos or 200)
    local radius = (Minimap:GetWidth() / 2) + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function makeOwnButton()
    button = CreateFrame("Button", "ForeverCompanionMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, b) onClick(b) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        fillTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx, cy = cx / scale, cy / scale
            ns.db.minimap.minimapPos = math.deg(math.atan2(cy - my, cx - mx)) % 360
            updatePosition()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    updatePosition()
    button:SetShown(not ns.db.minimap.hide)
end

----------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------
local usingLib = false
ns:Listen("READY", function()
    ns.db.minimap = ns.db.minimap or { hide = false, minimapPos = 200 }
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDB and DBIcon then
        local obj = LDB:NewDataObject(ADDON, {
            type = "launcher", text = "Forever Companion", icon = ICON,
            OnClick = function(_, b) onClick(b) end,
            OnTooltipShow = function(tt) fillTooltip(tt) end,
        })
        DBIcon:Register(ADDON, obj, ns.db.minimap)
        usingLib = true
    else
        makeOwnButton()
    end
end)

function ns:SetMinimapShown(show)
    ns.db.minimap.hide = not show
    if usingLib then
        local DBIcon = LibStub("LibDBIcon-1.0", true)
        if show then DBIcon:Show(ADDON) else DBIcon:Hide(ADDON) end
    elseif button then
        button:SetShown(show)
    end
end

ns:Command("minimap", "show or hide the minimap button", function()
    ns.db.minimap.hide = not ns.db.minimap.hide
    if usingLib then
        local DBIcon = LibStub("LibDBIcon-1.0", true)
        if ns.db.minimap.hide then DBIcon:Hide(ADDON) else DBIcon:Show(ADDON) end
    elseif button then
        button:SetShown(not ns.db.minimap.hide)
    end
    ns:Print("minimap button " .. (ns.db.minimap.hide and "hidden" or "shown"))
end)
