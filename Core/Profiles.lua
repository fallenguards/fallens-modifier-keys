local _, ns = ...

-- Named setups of hold keys. Each character picks one.
local P = {}
ns.Profiles = P

local ALL = "Default"
local NAME_MAX = 32
local FIGHT = "Profiles change only out of a fight."
local db, me
local listeners = {}

-- the addon sets it: true while changes must wait
P.Busy = function() return false end

local function Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, item in pairs(v) do out[k] = Copy(item) end
    return out
end

-- holds: the hold keys; keys: the action keys
local function Fresh() return { holds = {}, keys = {} } end
P.Fresh = Fresh

local function Sound(profile)
    return type(profile) == "table" and type(profile.holds) == "table" and type(profile.keys) == "table"
end

local function Record() return db.chars[me.id] end

local function Fire()
    for _, fn in ipairs(listeners) do fn(P.Data(), P.Active()) end
end

-- fn(data, name) after the profile in use changes
function P.OnChange(fn) listeners[#listeners + 1] = fn end

-- the client may give no realm: then the name alone
function P.Own()
    if me.realm then return me.name .. " - " .. me.realm end
    return me.name
end
function P.Class() return me.class end
function P.Everyone() return ALL end
function P.Active() return Record().profile end
-- this character's own saved record: what is true of it alone
function P.Mine() return Record() end
function P.Data() return db.profiles[P.Active()] end

-- the three every character is offered
local function Standard()
    return { { name = P.Own(), kind = "own" }, { name = P.Class(), kind = "class" }, { name = ALL, kind = "all" } }
end

-- "own", "class" or "all" for this character's three
function P.Kind(name)
    for _, entry in ipairs(Standard()) do
        if entry.name == name then return entry.kind end
    end
end

-- the three first, then the rest by name
function P.Names()
    local out, seen, rest = Standard(), {}, {}
    for _, entry in ipairs(out) do
        entry.made = db.profiles[entry.name] ~= nil
        seen[entry.name] = true
    end
    for name in pairs(db.profiles) do
        if not seen[name] then rest[#rest + 1] = name end
    end
    table.sort(rest, function(a, b) return a:lower() < b:lower() end)
    for _, name in ipairs(rest) do out[#out + 1] = { name = name, made = true } end
    return out
end

-- the characters on a profile, by name
function P.Users(name)
    local out = {}
    for _, record in pairs(db.chars) do
        if record.profile == name and record.name then out[#out + 1] = record.name end
    end
    table.sort(out)
    return out
end

-- a trimmed name, or nil and why not
function P.Check(text, except)
    local name = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
    if name == "" then return nil, "Type a name." end
    if #name > NAME_MAX then return nil, ("Names are at most %d letters."):format(NAME_MAX) end
    local low = name:lower()
    for _, entry in ipairs(P.Names()) do
        if entry.name ~= except and entry.name:lower() == low then return nil, "A profile has that name already." end
    end
    return name
end

function P.Use(name)
    if type(name) ~= "string" then return false end
    if name == P.Active() then return true end
    if P.Busy() then return false, FIGHT end
    if not db.profiles[name] then
        -- one of the three, first picked: starts as the one in use
        if not P.Kind(name) then return false end
        db.profiles[name] = Copy(P.Data())
        db.moved[name] = nil
    end
    Record().profile = name
    Fire()
    return true
end

-- copy: from the one in use, else empty. Switches to it.
function P.New(text, copy)
    if P.Busy() then return nil, FIGHT end
    local name, why = P.Check(text)
    if not name then return nil, why end
    if copy then
        db.profiles[name] = Copy(P.Data())
    else
        db.profiles[name] = Fresh()
    end
    db.moved[name] = nil
    P.Use(name)
    return name
end

function P.Rename(old, text)
    if P.Busy() then return nil, FIGHT end
    if not db.profiles[old] then return nil, "No such profile." end
    if P.Kind(old) then return nil, "That profile keeps its name." end
    local name, why = P.Check(text, old)
    if not name then return nil, why end
    if name == old then return name end
    db.profiles[name] = db.profiles[old]
    db.profiles[old] = nil
    -- characters on it follow at their next login
    db.moved[old] = name
    db.moved[name] = nil
    if Record().profile == old then Record().profile = name end
    Fire()
    return name
end

-- a character falls back to its own, so that one stays
function P.Delete(name)
    if P.Busy() then return false, FIGHT end
    if not db.profiles[name] then return false, "No such profile." end
    if name == P.Own() then return false, "This character's own profile stays. Reset empties it." end
    if name == P.Active() then
        db.profiles[P.Own()] = db.profiles[P.Own()] or Fresh()
        Record().profile = P.Own()
    end
    db.profiles[name] = nil
    db.moved[name] = nil
    Fire()
    return true
end

-- the one in use becomes a copy of another
function P.CopyFrom(name)
    if P.Busy() then return false, FIGHT end
    if not db.profiles[name] or name == P.Active() then return false, "No such profile." end
    db.profiles[P.Active()] = Copy(db.profiles[name])
    Fire()
    return true
end

function P.Reset()
    if P.Busy() then return false, FIGHT end
    db.profiles[P.Active()] = Fresh()
    Fire()
    return true
end

-- who: id (never repeats), name, realm, class
function P.Load(saved, who)
    db, me = saved, who
    if type(db.profiles) ~= "table" then db.profiles = {} end
    if type(db.chars) ~= "table" then db.chars = {} end
    if type(db.moved) ~= "table" then db.moved = {} end
    -- a damaged profile is dropped, not patched
    for name, profile in pairs(db.profiles) do
        if type(name) ~= "string" or not Sound(profile) then db.profiles[name] = nil end
    end
    if type(db.chars[who.id]) ~= "table" then db.chars[who.id] = {} end
    -- one saved with an empty realm: the name alone
    local dashed = who.name .. " - "
    if not who.realm and db.profiles[dashed] and not db.profiles[who.name] then
        db.profiles[who.name], db.profiles[dashed] = db.profiles[dashed], nil
        db.moved[dashed] = who.name
    end
    local record = Record()
    record.name, record.class = who.name, who.class
    local name = record.profile
    -- a renamed profile is followed
    for _ = 1, 10 do
        if name == nil or db.profiles[name] or not db.moved[name] then break end
        name = db.moved[name]
    end
    -- a new character, or one whose profile is gone: its own
    if type(name) ~= "string" or not db.profiles[name] then name = P.Own() end
    db.profiles[name] = db.profiles[name] or Fresh()
    record.profile = name
    return db.profiles[name]
end
