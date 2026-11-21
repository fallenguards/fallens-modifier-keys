local _, ns = ...
-- luacheck: globals FallensModifierKeysDB FallensModifierKeys_AttachDevTools
-- luacheck: read globals CreateFrame UnitGUID UnitName GetUnitName UnitClass GetRealmName issecretvalue
-- luacheck: read globals InCombatLockdown DEFAULT_CHAT_FRAME UIErrorsFrame

-- the dev addon's way in
function FallensModifierKeys_AttachDevTools(take) take(ns) end

-- the dev addon swaps this for its log
function ns.Log() end

ns.TITLE = "Fallen's Modifier Keys and Action Bar Pages"

function ns.Say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffffd100" .. ns.TITLE .. ":|r " .. msg) end

-- red, where the game says what it cannot do
function ns.Warn(why)
    if why and UIErrorsFrame then UIErrorsFrame:AddMessage(why, 1, 0.1, 0.1) end
end

-- names can repeat across characters; the id cannot
local function Who()
    local name = GetUnitName and GetUnitName("player", false) or UnitName("player")
    -- one client gives an empty realm
    local realm = GetRealmName()
    if type(realm) ~= "string" or realm == "" then realm = nil end
    local class = UnitClass("player")
    local id = UnitGUID("player")
    if type(id) ~= "string" or (issecretvalue and issecretvalue(id)) then
        id = tostring(name) .. "-" .. (realm or "")
    end
    return { id = id, name = tostring(name), realm = realm, class = class or "?" }
end

-- keys are bound from secure code: no change in a fight
ns.Profiles.Busy = function() return InCombatLockdown() end

local starters = {}

-- fn() once the saved data is loaded
function ns.OnStart(fn) starters[#starters + 1] = fn end

-- saved data and this character's profile, once
function ns.Start()
    if ns.started then return end
    ns.started = true
    FallensModifierKeysDB = FallensModifierKeysDB or {}
    ns.db = FallensModifierKeysDB
    ns.me = Who()
    ns.Profiles.Load(ns.db, ns.me)
    for _, fn in ipairs(starters) do fn() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function() ns.Start() end)
