local _, ns = ...
-- luacheck: read globals UIParent GetTime GetBindingAction EnumerateFrames

-- Action bars, whoever made them, found by what they are.
local B = {}
ns.Bars = B

-- the game's own bars: button name, binding command, the page its buttons show
local CLIENT_BARS = {
    { "ActionButton", "ACTIONBUTTON", 1 },
    { "MultiBarBottomLeftButton", "MULTIACTIONBAR1BUTTON", 6 },
    { "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON", 5 },
    { "MultiBarRightButton", "MULTIACTIONBAR3BUTTON", 3 },
    { "MultiBarLeftButton", "MULTIACTIONBAR4BUTTON", 4 },
    { "MultiBar5Button", "MULTIACTIONBAR5BUTTON", 13 },
    { "MultiBar6Button", "MULTIACTIONBAR6BUTTON", 14 },
    { "MultiBar7Button", "MULTIACTIONBAR7BUTTON", 15 },
}
local PER_BAR = 12
local TEXT = { bar = "Action Bar %d" }
local MODS = { "", "SHIFT-", "CTRL-", "ALT-", "CTRL-SHIFT-", "ALT-SHIFT-", "ALT-CTRL-", "ALT-CTRL-SHIFT-" }
local OTHER_KEYS = {
    "-", "=", "[", "]", "\\", ";", "'", ",", ".", "/", "`", "SPACE", "TAB", "ENTER", "BACKSPACE", "DELETE", "INSERT",
    "HOME", "END", "PAGEUP", "PAGEDOWN", "UP", "DOWN", "LEFT", "RIGHT", "NUMPADDIVIDE", "NUMPADMULTIPLY",
    "NUMPADMINUS", "NUMPADPLUS", "NUMPADDECIMAL", "MOUSEWHEELUP", "MOUSEWHEELDOWN",
}
-- the game's gamepad mode has bars and a bind dialog of its own: not ours to switch
local PAD_FRAMES = "^Gamepad"
-- nor are the game's bars that come and go by themselves: vehicle, totems
local GAME_SPECIAL = { "^OverrideActionBar", "^MultiCast", "^PossessActionBar" }

local universe, keyMap, keyMapAt, bars, barsAt
local masked = {}

-- Keys bound over by this addon itself (its hold keys): what such a key
-- does is read under that binding, so it still counts as its button's key.
function B.Mask(keys) masked = keys or {} end

local function Universe()
    if universe then return universe end
    local base = {}
    for c = 65, 90 do base[#base + 1] = string.char(c) end
    for d = 0, 9 do
        base[#base + 1] = tostring(d)
        base[#base + 1] = "NUMPAD" .. d
    end
    for f = 1, 24 do base[#base + 1] = "F" .. f end
    for b = 3, 31 do base[#base + 1] = "BUTTON" .. b end
    for _, key in ipairs(OTHER_KEYS) do base[#base + 1] = key end
    universe = {}
    for _, mod in ipairs(MODS) do
        for _, key in ipairs(base) do universe[#universe + 1] = mod .. key end
    end
    return universe
end

-- what every key does now: action to its keys
function B.KeyMap(fresh)
    local now = GetTime()
    if not fresh and keyMap and now - keyMapAt < 1 then return keyMap end
    keyMap, keyMapAt = {}, now
    for _, key in ipairs(Universe()) do
        local action = masked[key] and GetBindingAction(key) or GetBindingAction(key, true)
        if action and action ~= "" then
            local keys = keyMap[action]
            if not keys then
                keys = {}
                keyMap[action] = keys
            end
            keys[#keys + 1] = key
        end
    end
    return keyMap
end

local function Client(name)
    for n, bar in ipairs(CLIENT_BARS) do
        local index = name:match("^" .. bar[1] .. "(%d+)$")
        if index then return bar, tonumber(index), n end
    end
end

function B.Slot(button)
    local slot = button.action
    if type(slot) ~= "number" or slot <= 0 then slot = button:GetAttribute("action") end
    if type(slot) == "number" and slot > 0 then return slot end
end

local function IsButton(frame)
    local name = frame:GetName()
    return frame:IsObjectType("CheckButton") and frame:IsProtected() and type(name) == "string"
        and not name:find(PAD_FRAMES) and frame:GetAttribute("type") == "action" and B.Slot(frame) ~= nil
end

-- a saved name back to its button, if it still is one
function B.Named(name)
    local frame = type(name) == "string" and _G[name]
    if type(frame) ~= "table" or type(frame.IsObjectType) ~= "function" then return nil end
    if frame:IsForbidden() or not IsButton(frame) then return nil end
    return frame
end

local function Trailing(name) return tonumber(name:match("(%d+)$")) or 0 end

local function Special(name)
    for _, pattern in ipairs(GAME_SPECIAL) do
        if name:find(pattern) then return true end
    end
    return false
end

local function Shown(list)
    for _, button in ipairs(list) do
        if button:IsVisible() then return true end
    end
    return false
end

-- Every bar: id, title, buttons in order, shown. The game's first, by their
-- numbers; then any other, one per frame its buttons sit in.
function B.List(fresh)
    local now = GetTime()
    if not fresh and bars and now - barsAt < 5 then return bars end
    bars, barsAt = {}, now
    local taken = {}
    for n, bar in ipairs(CLIENT_BARS) do
        local buttons = {}
        for i = 1, PER_BAR do
            local button = B.Named(bar[1] .. i)
            if button then
                buttons[#buttons + 1] = button
                taken[button] = true
            end
        end
        if #buttons > 0 then
            bars[#bars + 1] = { id = bar[1], title = TEXT.bar:format(n), buttons = buttons, page = bar[3] }
        end
    end
    local groups, order = {}, {}
    local frame = EnumerateFrames()
    while frame do
        if not frame:IsForbidden() and not taken[frame] and IsButton(frame) then
            local parent = frame:GetParent()
            local name = parent and parent ~= UIParent and parent:GetName()
            if type(name) == "string" and not name:find(PAD_FRAMES) and not Special(name) then
                if not groups[name] then
                    groups[name] = {}
                    order[#order + 1] = name
                end
                table.insert(groups[name], frame)
            end
        end
        frame = EnumerateFrames(frame)
    end
    table.sort(order)
    for _, name in ipairs(order) do
        local buttons = groups[name]
        table.sort(buttons, function(a, b)
            local x, y = Trailing(a:GetName()), Trailing(b:GetName())
            if x ~= y then return x < y end
            return a:GetName() < b:GetName()
        end)
        -- one button alone is no bar
        if #buttons > 1 then bars[#bars + 1] = { id = "@" .. name, title = name, buttons = buttons } end
    end
    for _, bar in ipairs(bars) do bar.shown = Shown(bar.buttons) end
    return bars
end

function B.Bar(id, fresh)
    if type(id) ~= "string" then return nil end
    for _, bar in ipairs(B.List(fresh)) do
        if bar.id == id then return bar end
    end
end

function B.Title(id)
    local bar = B.Bar(id)
    return bar and bar.title or nil
end

-- a key may click the button itself or a helper child of it
local function Within(frame, host)
    for _ = 1, 3 do
        if type(frame) ~= "table" or type(frame.IsForbidden) ~= "function" or frame:IsForbidden() then return false end
        if frame == host then return true end
        frame = frame:GetParent()
    end
    return false
end

-- the click a key of its own sends this button now: the action, the frame's name, the click's name
local function OwnClick(host)
    for action in pairs(B.KeyMap()) do
        local target, how = action:match("^CLICK (.-):(.*)$")
        if target and Within(_G[target], host) then return action, target, how end
    end
end

-- the keys that press this button now
function B.Keys(host)
    local keys = {}
    local bar, index = Client(host:GetName())
    local command = bar and (bar[2] .. index)
    for action, list in pairs(B.KeyMap()) do
        local target = action:match("^CLICK (.-):")
        if action == command or (target and Within(_G[target], host)) then
            for _, key in ipairs(list) do keys[#keys + 1] = key end
        end
    end
    table.sort(keys)
    return keys
end

-- What a key is bound to so it presses this button. The game's own button
-- takes its own command. Any other: the click its own key sends, else the
-- click a key sends a button of the same make (the same name but for its
-- number), else a plain click. `plain`: never what its own key does now.
function B.Press(button, plain)
    local name = button:GetName()
    local bar, index = Client(name)
    if bar then return bar[2] .. index end
    local mine = not plain and OwnClick(button)
    if mine then return mine end
    local stem = name:match("^(.-)%d+$")
    for _, other in ipairs(stem and B.List() or {}) do
        for _, like in ipairs(other.buttons) do
            local theirs = like:GetName()
            if like ~= button and theirs:match("^(.-)%d+$") == stem then
                local _, target, how = OwnClick(like)
                if target and target:sub(1, #theirs) == theirs then
                    local helper = name .. target:sub(#theirs + 1)
                    if _G[helper] then return "CLICK " .. helper .. ":" .. how end
                end
            end
        end
    end
    return "CLICK " .. name .. ":LeftButton"
end

-- the slot a bar's place holds when nothing is switched
function B.Home(bar, i)
    if bar.page then return (bar.page - 1) * PER_BAR + i end
    local button = bar.buttons[i]
    return button and B.Slot(button)
end

-- How a button is made to show another slot, and how it is put back:
-- attribute, value, value to restore. nil: it cannot.
function B.Swap(button, slot)
    local id = button:GetID()
    if type(id) == "number" and id > 0 then
        local page = (slot - id) / PER_BAR + 1
        if page < 1 or page ~= math.floor(page) then return nil end
        return "actionpage", page, nil
    end
    local own = button:GetAttribute("action")
    if type(own) ~= "number" then return nil end
    return "action", slot, own
end

-- the bar with the most keys on it: the likeliest home of the action keys
function B.Busiest()
    local best, most = nil, 0
    for _, bar in ipairs(B.List()) do
        local count = 0
        for _, button in ipairs(bar.buttons) do
            if #B.Keys(button) > 0 then count = count + 1 end
        end
        if bar.shown and count > most then best, most = bar, count end
    end
    return best
end

-- the keys are read anew; with `deep` the bars are looked for anew too
function B.Forget(deep)
    keyMap = nil
    if deep then bars = nil end
end
