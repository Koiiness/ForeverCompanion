-- Core: event bus, saved variables, slash commands, helpers.
local ADDON, ns = ...
ns.name = ADDON

local DEFAULTS = {
    settings = {
        tooltip = true,        -- add advice lines to item tooltips
        autoSellJunk = false,  -- sell gray items automatically at a vendor
        autoScan = true,       -- full AH price scan when the AH opens (once per 15 min)
        touch = false,         -- bigger window for touch screens
        noGrind = true,        -- hide money ideas that need grinding far below your level
        playStyle = "both",    -- "solo", "group" or "both": how dungeons and group quests are weighed
        reserveLevels = 4,     -- levels of class training to keep gold for
        ahCutPct = 5,          -- auction house cut, percent
        ahMinGain = 1000,      -- copper: AH must beat the next option by this much to be worth listing
        specOverride = nil,    -- spec name from Data.Specs, e.g. "Shadow"; nil = detect from talents
        debug = false,
    },
    prices = {},   -- [itemID] = { p = copper per unit, t = time() }
    chars = {},    -- ["Realm - Name"] = per-character data
}

----------------------------------------------------------------------
-- Printing
----------------------------------------------------------------------
local PREFIX = "|cff7fd4ffForever Companion|r: "
function ns:Print(...)
    print(PREFIX .. strjoin(" ", tostringall(...)))
end
-- Errors are kept (last 40) in the saved data so they can be read outside the game.
function ns:LogError(where, err)
    if not ns.db then return end
    ns.db.errors = ns.db.errors or {}
    local list = ns.db.errors
    local msg = tostring(err)
    local last = list[#list]
    if last and last.msg == msg and last.where == where then last.n = (last.n or 1) + 1 last.t = date("%Y-%m-%d %H:%M") return end
    list[#list + 1] = { t = date("%Y-%m-%d %H:%M"), where = tostring(where), msg = msg, n = 1 }
    while #list > 40 do table.remove(list, 1) end
end

function ns:Debug(...)
    if ns.db and ns.db.settings.debug then
        print("|cff888888[FC debug]|r " .. strjoin(" ", tostringall(...)))
    end
end

----------------------------------------------------------------------
-- Events (safe registration: unknown events on this client are skipped)
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, fn)
    if not handlers[event] then
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then
            ns:Debug("event not available on this client:", event)
            return
        end
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, event, ...)
        if not ok then ns:Debug(event, "error:", err) ns:LogError(event, err) end
    end
end)

-- Internal messages between modules ("GEAR_CHANGED", "BAGS_CHANGED", ...)
local listeners = {}
function ns:Listen(msg, fn)
    listeners[msg] = listeners[msg] or {}
    table.insert(listeners[msg], fn)
end
function ns:Fire(msg, ...)
    for _, fn in ipairs(listeners[msg] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then ns:Debug(msg, "error:", err) ns:LogError(msg, err) end
    end
end

-- Coalesce bursts of events (BAG_UPDATE fires many times per loot).
local pending = {}
function ns:Debounce(key, delay, fn)
    if pending[key] then return end
    pending[key] = true
    C_Timer.After(delay, function()
        pending[key] = nil
        local ok, err = pcall(fn)
        if not ok then ns:Debug(key, "error:", err) ns:LogError(key, err) end
    end)
end

----------------------------------------------------------------------
-- Formatting helpers
----------------------------------------------------------------------
function ns.Money(copper)
    if not copper then return "?" end
    copper = math.floor(copper + 0.5)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then return string.format("|cffffd700%dg|r %ds", g, s) end
    if s > 0 then return string.format("%ds %dc", s, c) end
    return string.format("%dc", c)
end

function ns.Color(hex, text) return "|cff" .. hex .. tostring(text) .. "|r" end

function ns.Duration(seconds)
    if not seconds or seconds == math.huge or seconds ~= seconds then return "--" end
    seconds = math.floor(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

----------------------------------------------------------------------
-- Saved variables
----------------------------------------------------------------------
local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            applyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function realmName()
    local r = GetRealmName and GetRealmName()
    if not r or r == "" then r = GetNormalizedRealmName and GetNormalizedRealmName() end
    if not r or r == "" then r = "Forever" end
    return r
end

-- Characters are keyed by their unique character ID (GUID). Name and realm
-- aren't enough: the realm can read as blank at login, and several
-- characters can share a name on different realms.
function ns:CharKey()
    return UnitGUID("player") or (realmName() .. " - " .. (UnitName("player") or "?"))
end

-- Full character name. Forever names have a first and last name; the last
-- name may come back as UnitName's second value or in GetUnitName's "First-Last".
function ns:FullName()
    local first, second = UnitName("player")
    if second and second ~= "" then return first .. " " .. second end
    local full = GetUnitName and GetUnitName("player", true)
    if full and full ~= "" then return (full:gsub("%-", " ")) end
    return first
end

-- How to show a character: "Peaches Foryouandme (Priest 33)".
function ns.CharLabel(char, key)
    if not char or not char.name then return tostring(key) end
    local class = char.class and (char.class:sub(1, 1) .. char.class:sub(2):lower()) or nil
    return (char.fullName or char.name) .. ((class or char.level) and (" (" .. (class or "") .. (char.level and (" " .. char.level) or "") .. ")") or "")
end

ns:On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    ForeverCompanionDB = ForeverCompanionDB or {}
    applyDefaults(ForeverCompanionDB, DEFAULTS)
    ns.db = ForeverCompanionDB
end)

ns:On("PLAYER_LOGIN", function()
    local key = ns:CharKey()
    local chars = ns.db.chars
    -- Older versions keyed characters by "Realm - Name", which mixed up
    -- same-named characters. Adopt an old entry only if its class matches.
    if not chars[key] then
        local myName, myClass = UnitName("player"), select(2, UnitClass("player"))
        for _, old in ipairs({ " - " .. (myName or "?"), "Forever - " .. (myName or "?"), realmName() .. " - " .. (myName or "?") }) do
            local o = chars[old]
            if old ~= key and o and not o.guid and o.class == myClass then
                chars[key], chars[old] = o, nil
                break
            end
        end
    end
    chars[key] = chars[key] or {}
    local char = chars[key]
    char.guid = UnitGUID("player")
    char.name = UnitName("player")
    char.fullName = ns:FullName()
    char.realm = realmName()
    char.class = select(2, UnitClass("player"))
    char.faction = UnitFactionGroup("player")
    char.level = UnitLevel("player")
    char.gear = char.gear or {}
    char.bags = char.bags or {}
    char.bank = char.bank or {}
    char.professions = char.professions or {}
    char.recipes = char.recipes or {}
    char.reagents = char.reagents or {}
    -- Bank snapshots from before banks recorded their owner may belong to another
    -- character; drop them (they come back the next time you open your bank).
    if char.bank and #char.bank > 0 and char.bankGuid ~= char.guid then
        char.bank = {}
        char.bankTime = nil
    end
    ns.char = char
    ns:Fire("READY")
    if not ns.db.welcomed then
        ns.db.welcomed = true
        ns:Print("welcome! Type |cffffff00/fc|r or click the minimap button to open it, |cffffff00/fc help|r for commands.")
    end
end)

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
local commands = {}
function ns:Command(name, help, fn) commands[name] = { help = help, fn = fn } end

local function printHelp()
    ns:Print("commands:")
    local names = {}
    for k in pairs(commands) do names[#names + 1] = k end
    table.sort(names)
    for _, k in ipairs(names) do
        print("  |cffffff00/fc " .. k .. "|r  " .. commands[k].help)
    end
end

SLASH_FOREVERCOMPANION1 = "/fc"
SLASH_FOREVERCOMPANION2 = "/forevercompanion"
SlashCmdList.FOREVERCOMPANION = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        if ns.ToggleUI then ns:ToggleUI() end
        return
    end
    if cmd == "help" then printHelp() return end
    local c = commands[cmd]
    if c then c.fn(rest) else
        ns:Print("unknown command '" .. cmd .. "'.")
        printHelp()
    end
end

ns:Command("tooltip", "toggle advice lines on item tooltips", function()
    ns.db.settings.tooltip = not ns.db.settings.tooltip
    ns:Print("tooltip advice " .. (ns.db.settings.tooltip and "on" or "off"))
end)

ns:Command("autosell", "toggle selling gray items automatically at vendors", function()
    ns.db.settings.autoSellJunk = not ns.db.settings.autoSellJunk
    ns:Print("auto-sell junk " .. (ns.db.settings.autoSellJunk and "on" or "off"))
end)

ns:Command("debug", "toggle debug messages", function()
    ns.db.settings.debug = not ns.db.settings.debug
    ns:Print("debug " .. (ns.db.settings.debug and "on" or "off"))
end)

ns:Command("role", "tank, healer, dps, a spec name (e.g. fire, shadow, bear), or auto to detect from talents", function(arg)
    if not ns:SetSpec(arg) then
        local names = {}
        for _, s in ipairs(ns.Data.Specs[ns.char.class] or {}) do names[#names + 1] = s.name:lower() end
        ns:Print("try: tank, healer, dps, auto, or one of: " .. table.concat(names, ", "))
        return
    end
    local _, manual = ns:GetSpec()
    ns:Print("gear is now scored for " .. ns:SpecLabel() .. (manual and " (chosen by you)" or " (from your talents)"))
    ns.Gear.Snapshot()
end)

----------------------------------------------------------------------
-- Notes: messages you leave from inside the game. They're stored in the
-- saved data (written when you /reload or log out), where Claude can read them.
----------------------------------------------------------------------
function ns:AddNote(text)
    text = strtrim(text or "")
    if text == "" then return false end
    ns.db.notes = ns.db.notes or {}
    local page = ns.CurrentPage and ns.CurrentPage() or nil
    table.insert(ns.db.notes, { t = date("%Y-%m-%d %H:%M"), char = ns.CharLabel(ns.char, ns:CharKey()), level = UnitLevel("player"),
                                page = page, zone = GetZoneText and GetZoneText() or nil, text = text })
    return true
end

ns:Command("note", "<text> leave a note (saved when you /reload or log out)", function(arg)
    if ns:AddNote(arg) then
        ns:Print("note saved. It's written to disk when you /reload or log out.")
    else
        ns:Print("usage: /fc note <what you want to say>")
    end
end)

ns:Command("notes", "list your saved notes", function()
    local notes = ns.db.notes or {}
    if #notes == 0 then ns:Print("no notes yet. Add one with /fc note <text>.") return end
    for i, n in ipairs(notes) do print(string.format("  %d. [%s] %s", i, n.t, n.text)) end
end)

ns:Command("clearnotes", "delete all saved notes", function()
    ns.db.notes = {}
    ns:Print("notes cleared.")
end)

ns:Command("errors", "show errors the addon has caught", function()
    local list = ns.db.errors or {}
    if #list == 0 then ns:Print("no errors logged.") return end
    for _, e in ipairs(list) do print(string.format("  [%s] %s x%d: %s", e.t, e.where, e.n or 1, e.msg)) end
end)

----------------------------------------------------------------------
-- Catch Lua errors from this addon and AtlasLoot (including ones outside
-- our own safety wrappers, like button clicks) and keep them in the log.
-- The game's normal error handling still runs afterwards.
----------------------------------------------------------------------
local pendingErrors = {}
do
    local previous = geterrorhandler and geterrorhandler()
    if seterrorhandler and previous then
        seterrorhandler(function(msg, ...)
            pcall(function()
                local text = tostring(msg)
                local stack = debugstack and debugstack(3, 8, 0) or ""
                if text:find("ForeverCompanion", 1, true) or text:find("AtlasLoot", 1, true) or text:find("AtlasBIS", 1, true)
                    or stack:find("ForeverCompanion", 1, true) then
                    local entry = text .. (stack ~= "" and ("\n" .. stack) or "")
                    if ns.db then ns:LogError("lua", entry) else pendingErrors[#pendingErrors + 1] = entry end
                end
            end)
            return previous(msg, ...)
        end)
    end
end
ns:Listen("READY", function()
    for _, e in ipairs(pendingErrors) do ns:LogError("lua (startup)", e) end
    wipe(pendingErrors)
end)

----------------------------------------------------------------------
-- Resetting saved character data (prices, notes and settings are kept).
----------------------------------------------------------------------
local function freshChar(char)
    for _, k in ipairs({ "gear", "bags", "bank", "professions", "recipes", "reagents" }) do char[k] = {} end
    char.bankTime, char.bankGuid, char.avgIlvl, char.favor = nil, nil, nil, nil
end

StaticPopupDialogs["FOREVERCOMPANION_RESET"] = {
    text = "Clear Forever Companion's saved data for %s?\n\nPrices, notes and settings are kept. Bags and gear refresh right away; open your bank and profession windows again to record them.",
    button1 = YES, button2 = NO,
    OnAccept = function(_, all)
        if all then
            for key, char in pairs(ns.db.chars) do
                if char == ns.char then freshChar(char) else ns.db.chars[key] = nil end
            end
        else
            freshChar(ns.char)
        end
        if ns.Research then ns.Research.Invalidate() end
        if ns.Bags then ns.Bags.SnapshotBags() end
        if ns.Gear then ns.Gear.Snapshot() end
        if ns.Professions then ns.Professions.SnapshotSkills() end
        ns:Print(all and "cleared saved data for all characters." or "cleared saved data for this character.")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

ns:Command("reset", "clear this character's saved data (asks first)", function()
    local dialog = StaticPopup_Show("FOREVERCOMPANION_RESET", ns.CharLabel(ns.char, ns:CharKey()))
    if dialog then dialog.data = false end
end)

ns:Command("resetall", "clear saved data for every character (asks first)", function()
    local dialog = StaticPopup_Show("FOREVERCOMPANION_RESET", "ALL characters")
    if dialog then dialog.data = true end
end)
