-- Core: event bus, saved variables, slash commands, helpers.
local ADDON, ns = ...
ns.name = ADDON

local DEFAULTS = {
    settings = {
        tooltip = true,        -- add advice lines to item tooltips
        autoSellJunk = false,  -- sell gray items automatically at a vendor
        autoScan = true,       -- full AH price scan when the AH opens (once per 15 min)
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

function ns:CharKey()
    return realmName() .. " - " .. (UnitName("player") or "?")
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
    -- Early versions saved characters with a blank realm (" - Name").
    local oldKey = " - " .. (UnitName("player") or "?")
    if oldKey ~= key and chars[oldKey] and not chars[key] then
        chars[key], chars[oldKey] = chars[oldKey], nil
    end
    chars[key] = chars[key] or {}
    local char = chars[key]
    char.name = UnitName("player")
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
    ns.char = char
    ns:Fire("READY")
    ns:Print("loaded. Type |cffffff00/fc|r to open, |cffffff00/fc help|r for commands.")
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
    table.insert(ns.db.notes, { t = date("%Y-%m-%d %H:%M"), char = ns:CharKey(), level = UnitLevel("player"),
                                page = page, zone = GetZoneText and GetZoneText() or nil, text = text })
    return true
end

ns:Command("note", "<text> leave a note for Claude (saved when you /reload or log out)", function(arg)
    if ns:AddNote(arg) then
        ns:Print("note saved. Type /reload (or log out) so the game writes it to disk, then tell Claude to check your notes.")
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
