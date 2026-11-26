-- Share: notes and recent errors as text ready to paste into Discord.
-- WoW can't reach the clipboard, so this opens a window with the text
-- already selected: press Cmd+C (Mac) or Ctrl+C (Windows), then paste.
local ADDON, ns = ...
local SH = {}
ns.Share = SH

local LIMIT = 1900   -- Discord allows 2000 characters per message

local function version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get(ADDON, "Version") or "?"
end

-- First line of an error, without the stack.
local function shortError(msg)
    msg = tostring(msg or ""):match("^[^\n]*") or ""
    return (msg:gsub("Interface/AddOns/", ""))
end

function SH.Text()
    local c = ns.char
    local who = c and ns.CharLabel(c, ns:CharKey()) or (UnitName("player") or "?")
    local header = string.format("**Forever Companion %s feedback** from %s, %s", version(), who, date("%Y-%m-%d"))
    local notes = ns.db.notes or {}
    local errors = ns.db.errors or {}
    local lines = { header }
    if #notes == 0 and #errors == 0 then
        lines[#lines + 1] = "(No notes or errors yet. Leave a note with the button in the sidebar or /fc note <text>.)"
        return table.concat(lines, "\n"), 0, 0
    end

    -- Newest notes first; drop the oldest if the message would be too long.
    local noteLines = {}
    for i = #notes, 1, -1 do
        local n = notes[i]
        noteLines[#noteLines + 1] = string.format("- [%s] %s page, level %s%s: %s", n.t or "?", n.page or "?",
            tostring(n.level or "?"), n.zone and (", " .. n.zone) or "", n.text or "")
    end
    local errLines = {}
    for i = #errors, math.max(1, #errors - 4), -1 do
        local e = errors[i]
        errLines[#errLines + 1] = string.format("- [%s] %s%s: %s", e.t or "?", e.where or "?",
            (e.n or 1) > 1 and (" x" .. e.n) or "", shortError(e.msg))
    end

    local function compose(nNotes)
        local out = { header }
        if nNotes > 0 then
            out[#out + 1] = "Notes:"
            for i = 1, nNotes do out[#out + 1] = noteLines[i] end
            if nNotes < #noteLines then out[#out + 1] = string.format("(%d older notes not included; send again after clearing these)", #noteLines - nNotes) end
        end
        if #errLines > 0 then
            out[#out + 1] = "Errors (newest first):"
            for _, l in ipairs(errLines) do out[#out + 1] = l end
        end
        return table.concat(out, "\n")
    end
    local count = #noteLines
    local text = compose(count)
    while #text > LIMIT and count > 1 do
        count = count - 1
        text = compose(count)
    end
    if #text > LIMIT then text = text:sub(1, LIMIT) .. "..." end
    return text, count, #errLines
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------
local win
local function build()
    local f = CreateFrame("Frame", "ForeverCompanionShare", UIParent, "BackdropTemplate")
    f:SetSize(560, 400)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.06, 0.065, 0.08, 0.98)
    f:SetBackdropBorderColor(0.5, 0.83, 1, 0.8)
    tinsert(UISpecialFrames, "ForeverCompanionShare")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Share notes")
    local help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    help:SetPoint("RIGHT", -14, 0)
    help:SetJustifyH("LEFT")
    help:SetText("The text is selected. Press |cffffd100" .. (IsMacClient and IsMacClient() and "Cmd+C" or "Ctrl+C")
        .. "|r to copy it, then paste it into Discord for the addon's author.")
    f.help = help

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -64)
    scroll:SetPoint("BOTTOMRIGHT", -34, 60)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetFontObject("ChatFontNormal")
    box:SetWidth(500)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    -- Keep the text as built (typing is ignored) and keep it selected.
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(f.text or "") self:HighlightText() end
    end)
    box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    scroll:SetScrollChild(box)
    f.box = box

    local function button(label, x, fn)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(170, 36)
        b:SetPoint("BOTTOMLEFT", x, 14)
        b:SetText(label)
        b:SetScript("OnClick", fn)
        return b
    end
    button("Select all again", 14, function() box:SetFocus() box:HighlightText() end)
    f.clear = button("Clear notes I've sent", 194, function()
        StaticPopup_Show("FOREVERCOMPANION_CLEARNOTES")
    end)
    local count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("BOTTOMRIGHT", -16, 26)
    f.count = count
    f:Hide()
    return f
end

function SH.Open()
    win = win or build()
    local text, nNotes, nErrors = SH.Text()
    win.text = text
    win.box:SetText(text)
    win.count:SetText(string.format("%d note%s, %d error%s, %d characters", nNotes, nNotes == 1 and "" or "s",
        nErrors, nErrors == 1 and "" or "s", #text))
    win:Show()
    win.box:SetFocus()
    win.box:HighlightText()
end

StaticPopupDialogs["FOREVERCOMPANION_CLEARNOTES"] = {
    text = "Clear your notes and the error log? Do this after you've pasted them into Discord.",
    button1 = YES, button2 = NO,
    OnAccept = function()
        ns.db.notes = {}
        ns.db.errors = {}
        if win and win:IsShown() then SH.Open() end
        ns:Print("notes and errors cleared.")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

ns:Command("share", "copy your notes and recent errors to paste into Discord", function() SH.Open() end)
