local _, ns = ...
-- luacheck: read globals GetBindingAction GetBindingText GetBindingName

-- Every change to a setup goes through here: checked, saved, bound.
local M = {}
ns.Model = M
local Bars, Profiles, Layers = ns.Bars, ns.Profiles, ns.Layers

local TEXT = {
    fight = "Modifier keys change only out of a fight.",
    noKey = "That key cannot be used here.",
    combo = "A modifier key is one key on its own, without Shift, Ctrl or Alt.",
    taken = "%s is a modifier key already.",
    isHold = "%s is a modifier key you hold.",
    keysPress = "%s press %s",
    shows = "%s shows %s",
    nothing = "Does nothing yet.",
    noKeys = "your action keys",
    extra = "%d more of your own",
    gone = "a bar that is not there",
}
M.TEXT = TEXT
-- keys that only go with another, and keys the game keeps
local NEVER = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true,
    RMETA = true, UNKNOWN = true, ESCAPE = true, ENTER = true, BUTTON1 = true, BUTTON2 = true,
    MOUSEWHEELUP = true, MOUSEWHEELDOWN = true, PRINTSCREEN = true }

local listeners = {}

-- fn() after any change
function M.OnChange(fn) listeners[#listeners + 1] = fn end

local function Done()
    Layers.Apply()
    for _, fn in ipairs(listeners) do fn() end
    return true
end

local function Data() return Profiles.Data() end

-- a key as the game shows it
function M.Label(key)
    if type(key) ~= "string" then return "" end
    return GetBindingText and GetBindingText(key, "KEY_") or key
end

-- a pressed key as a hold key: its name, or nil and why not
function M.Key(key)
    if type(key) ~= "string" or key == "" then return nil, TEXT.noKey end
    key = key:upper()
    if NEVER[key] then return nil, TEXT.noKey end
    if key:find("^PAD") then return nil, TEXT.noKey end
    if key:find("-", 1, true) and #key > 1 then return nil, TEXT.combo end
    return key
end

-- what a key does when it is no hold key, in the game's words; nil for nothing
function M.Does(key)
    local action = GetBindingAction(key)
    if type(action) ~= "string" or action == "" then return nil end
    local name = GetBindingName and GetBindingName(action) or _G["BINDING_NAME_" .. action]
    return type(name) == "string" and name ~= "" and name or action
end

local function HoldAt(key, except)
    for i, hold in ipairs(Data().holds) do
        if hold.key == key and i ~= except then return i end
    end
end

-- the bar a new hold key points at: the first shown one that is not the action keys' own
local function Next()
    local home, used = Data().keys.bar, {}
    for _, hold in ipairs(Data().holds) do
        for _, line in ipairs(hold.lines or {}) do used[line.to or ""] = true end
    end
    local spare
    for _, bar in ipairs(Bars.List()) do
        if bar.shown and bar.id ~= home then
            if not used[bar.id] then return bar.id end
            spare = spare or bar.id
        end
    end
    return spare
end

-- A new hold key and its line. With no key given the line stands with its
-- key still to be set (one such at a time: asked again, it is that one).
function M.AddHold(pressed)
    if Profiles.Busy() then return nil, TEXT.fight end
    local holds = Data().holds
    local key = false
    if pressed == nil then
        for i, hold in ipairs(holds) do
            if not hold.key then return i end
        end
    else
        local why
        key, why = M.Key(pressed)
        if not key then return nil, why end
        if HoldAt(key) then return nil, TEXT.taken:format(M.Label(key)) end
    end
    holds[#holds + 1] = { key = key, lines = { { what = "keys", to = Next() } }, binds = {} }
    Done()
    return #holds
end

-- no key given: the line stays, its key to be set again
function M.SetHoldKey(i, pressed)
    if Profiles.Busy() then return nil, TEXT.fight end
    local hold = Data().holds[i]
    if not hold then return nil end
    if pressed == nil then
        hold.key = false
        return Done()
    end
    local key, why = M.Key(pressed)
    if not key then return nil, why end
    if HoldAt(key, i) then return nil, TEXT.taken:format(M.Label(key)) end
    hold.key = key
    return Done()
end

function M.RemoveHold(i)
    if Profiles.Busy() then return nil, TEXT.fight end
    if not Data().holds[i] then return nil end
    table.remove(Data().holds, i)
    return Done()
end

-- what: "keys" (the action keys press bar `to`) or a bar's id (it shows bar `to`)
function M.SetLine(i, j, what, to)
    if Profiles.Busy() then return nil, TEXT.fight end
    local hold = Data().holds[i]
    local line = hold and hold.lines[j]
    if not line then return nil end
    line.what, line.to = what or line.what, to or line.to
    return Done()
end

function M.AddLine(i)
    if Profiles.Busy() then return nil, TEXT.fight end
    local hold = Data().holds[i]
    if not hold then return nil end
    hold.lines[#hold.lines + 1] = { what = "keys", to = Next() }
    return Done()
end

function M.RemoveLine(i, j)
    if Profiles.Busy() then return nil, TEXT.fight end
    local hold = Data().holds[i]
    if not (hold and hold.lines[j]) then return nil end
    table.remove(hold.lines, j)
    return Done()
end

-- the action keys follow a bar's own keys
function M.UseBar(id)
    if Profiles.Busy() then return nil, TEXT.fight end
    if not Bars.Bar(id) then return nil end
    local keys = Data().keys
    keys.bar, keys.list = id, nil
    return Done()
end

-- how many spots a set of action keys has: one per button of a bar
M.SPOTS = 12

-- the first key of each spot, false for a spot with none
function M.Spots()
    local out, places = {}, Layers.ActionKeys(Data())
    for i = 1, M.SPOTS do out[i] = places[i] and places[i][1] or false end
    return out
end

-- or are the player's own, one per spot; starts from what the bar gave
function M.UseList()
    if Profiles.Busy() then return nil, TEXT.fight end
    local keys = Data().keys
    if keys.list then return true end
    keys.list = M.Spots()
    return Done()
end

-- The key of spot i; nil empties it. A key given to a second spot leaves
-- its first. A bar's keys become the player's own at the first change.
function M.SetKey(i, pressed)
    if Profiles.Busy() then return nil, TEXT.fight end
    if type(i) ~= "number" or i < 1 or i > M.SPOTS then return nil end
    local key = false
    if pressed ~= nil then
        if type(pressed) ~= "string" or pressed == "" then return nil end
        key = pressed:upper()
        if NEVER[key] then return nil, TEXT.noKey end
        -- a modifier key can be an action key only where a tapped one's layer is on
        if HoldAt(key) and not M.AnyTap() then return nil, TEXT.isHold:format(M.Label(key)) end
    end
    local keys = Data().keys
    if not keys.list then keys.list = M.Spots() end
    for n = 1, M.SPOTS do
        if keys.list[n] == nil or (key and keys.list[n] == key) then keys.list[n] = false end
    end
    keys.list[i] = key
    return Done()
end

-- How hold i works. Tapped: its layer stays on for the next key. Held (as
-- it starts): its layer is on while the key is down.
function M.SetTap(i, on)
    if Profiles.Busy() then return nil, TEXT.fight end
    local hold = Data().holds[i]
    if not hold then return nil end
    hold.tap = on and true or nil
    return Done()
end
function M.Tap(i)
    local hold = Data().holds[i]
    return hold ~= nil and hold.tap == true
end
function M.AnyTap()
    for _, hold in ipairs(Data().holds) do
        if hold.tap then return true end
    end
    return false
end

-- one key for one button while hold i is down; a key set twice moves
function M.Bind(i, pressed, button)
    if Profiles.Busy() then return nil, TEXT.fight end
    local hold = Data().holds[i]
    if not (hold and Bars.Named(button)) or type(pressed) ~= "string" then return nil end
    local key = pressed:upper()
    if NEVER[key] or key == hold.key then return nil, TEXT.noKey end
    M.Unbind(i, key, true)
    hold.binds[#hold.binds + 1] = { key = key, button = button }
    return Done()
end

function M.Unbind(i, key, quiet)
    if Profiles.Busy() then return nil, TEXT.fight end
    local hold = Data().holds[i]
    if not hold then return nil end
    for n = #hold.binds, 1, -1 do
        if hold.binds[n].key == key then table.remove(hold.binds, n) end
    end
    if quiet then return true end
    return Done()
end

-- A profile is made whole, and a new one starts with the action keys of
-- the bar that has the most keys.
function M.Seed()
    local data = Data()
    for i = #data.holds, 1, -1 do
        local hold = data.holds[i]
        if type(hold) ~= "table" then
            table.remove(data.holds, i)
        else
            -- a line may stand with its key still to be set
            if type(hold.key) ~= "string" or hold.key == "" then hold.key = false end
            if type(hold.lines) ~= "table" then hold.lines = {} end
            if type(hold.binds) ~= "table" then hold.binds = {} end
        end
    end
    local keys = data.keys
    -- a list has a place for every spot
    if type(keys.list) == "table" then
        for n = 1, M.SPOTS do
            if type(keys.list[n]) ~= "string" or keys.list[n] == "" then keys.list[n] = false end
        end
    end
    if keys.bar or keys.list then return end
    local bar = Bars.Busiest()
    if bar then keys.bar = bar.id end
end

-- the action keys in order, as shown: one label per place that has a key
function M.KeyLabels(hold)
    local out = {}
    for _, place in ipairs(Layers.ActionKeys(Data(), hold)) do
        if place[1] then out[#out + 1] = M.Label(place[1]) end
    end
    return out
end

-- what hold i does, in words
function M.Sentence(i)
    local hold = Data().holds[i]
    if not hold then return "" end
    local parts = {}
    for _, line in ipairs(hold.lines) do
        local to = Bars.Title(line.to) or TEXT.gone
        if line.what == "keys" then
            local labels = M.KeyLabels(hold)
            local keys = #labels > 0 and table.concat(labels, " ") or TEXT.noKeys
            parts[#parts + 1] = TEXT.keysPress:format(keys, to)
        else
            parts[#parts + 1] = TEXT.shows:format(Bars.Title(line.what) or TEXT.gone, to)
        end
    end
    if #hold.binds > 0 then parts[#parts + 1] = TEXT.extra:format(#hold.binds) end
    if #parts == 0 then return TEXT.nothing end
    return table.concat(parts, ". ") .. "."
end

ns.OnStart(function()
    M.Seed()
    Layers.Apply()
    Profiles.OnChange(function()
        M.Seed()
        Done()
    end)
end)
