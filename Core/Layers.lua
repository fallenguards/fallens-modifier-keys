local _, ns = ...
-- luacheck: read globals UIParent CreateFrame InCombatLockdown C_Timer ClearOverrideBindings GetTime
-- luacheck: read globals IsKeyDown IsMouseButtonDown GetBindingAction

-- Hold keys. Each is bound to a secure button of ours; its press and release
-- run a snippet that binds the held one's keys and switches its bars, and
-- puts them back. All of it is secure code, so it works in a fight.
local L = {}
ns.Layers = L
local Bars, Profiles = ns.Bars, ns.Profiles

local ROOT, HOLD = "FallensModifierKeysRoot", "FallensModifierKeysHold"
L.ROOT, L.HOLD = ROOT, HOLD
-- a release the game never sent (the window lost focus) is looked for this often
local STUCK_EVERY, STUCK_AFTER = 0.25, 2

-- the bars the held one switched go back to their own actions
local UNSWAP = [[
    do
        local was = owner:GetAttribute("layer")
        for j = 1, was and owner:GetAttribute("swaps" .. was) or 0 do
            local at = was .. "_" .. j
            local attr, value = owner:GetAttribute("sattr" .. at), owner:GetAttribute("sold" .. at)
            owner:GetFrameRef("swap" .. at):SetAttribute(attr, value)
        end
    end
]]
-- `now` is the one held from here on; the "layer" attribute is set last,
-- so whoever hears it change finds every key and bar already in place
local SWAP = [[
    do
        for j = 1, now and owner:GetAttribute("swaps" .. now) or 0 do
            local at = now .. "_" .. j
            local attr, value = owner:GetAttribute("sattr" .. at), owner:GetAttribute("sval" .. at)
            owner:GetFrameRef("swap" .. at):SetAttribute(attr, value)
        end
    end
]]
-- every hold key on its button, then the held one's keys on top
local BIND = [[
    owner:ClearBindings()
    for i = 1, owner:GetAttribute("holds") or 0 do
        owner:SetBindingClick(true, owner:GetAttribute("hkey" .. i), owner:GetAttribute("hname" .. i))
    end
    do
        for j = 1, now and owner:GetAttribute("binds" .. now) or 0 do
            local at = now .. "_" .. j
            owner:SetBinding(true, owner:GetAttribute("bkey" .. at), owner:GetAttribute("bdo" .. at))
        end
    end
]]
-- The hold key last pressed and still down is the held one. A release with
-- no press before it (its press went to a key of another hold) is nothing.
local HOLD_WRAP = [[
    if down then
        seq = (seq or 0) + 1
        self:SetAttribute("stamp", seq)
    else
        if not self:GetAttribute("stamp") then return false end
        self:SetAttribute("stamp", nil)
    end
    local top, best
    for i = 1, owner:GetAttribute("holds") or 0 do
        local stamp = owner:GetFrameRef("hold" .. i):GetAttribute("stamp")
        if stamp and (not best or stamp > best) then top, best = i, stamp end
    end
    if top ~= owner:GetAttribute("layer") then
        local now = top
]] .. UNSWAP .. SWAP .. BIND .. [[
        owner:SetAttribute("layer", now)
    end
    return false
]]
-- nothing held, every bar its own
local RESET = "local owner = self\n" .. UNSWAP .. [[
    for i = 1, owner:GetAttribute("holds") or 0 do
        owner:GetFrameRef("hold" .. i):SetAttribute("stamp", nil)
    end
    seq = 0
    owner:SetAttribute("layer", nil)
]]

-- the dev addon runs it by hand: a real key cannot be pressed by code
L.WRAP = HOLD_WRAP

local root, plan, signature
local buttons = {}
local listeners = {}
local pending, watch, upFor, trusted, quiet = false, nil, 0, false, 0

-- fn(index or nil, plan) when the held one changes
function L.OnLayer(fn) listeners[#listeners + 1] = fn end
-- what is built now: per hold key its binds, swaps and lit buttons
function L.Plan() return plan end
function L.Held() return root and root:GetAttribute("layer") or nil end

local function Tell()
    local held = L.Held()
    for _, fn in ipairs(listeners) do fn(held, plan) end
end

-- the keys of each place, in order: a bar's own, or the player's list
local function ActionKeys(keys, holdKeys)
    local out = {}
    if type(keys.list) == "table" then
        for i, key in ipairs(keys.list) do
            out[i] = (type(key) == "string" and not holdKeys[key]) and { key } or {}
        end
        return out
    end
    local bar = Bars.Bar(keys.bar)
    for i, button in ipairs(bar and bar.buttons or {}) do
        out[i] = {}
        for _, key in ipairs(Bars.Keys(button)) do
            if not holdKeys[key] then table.insert(out[i], key) end
        end
    end
    return out
end

-- the same for a profile: a hold key is never an action key
function L.ActionKeys(profile)
    local holdKeys = {}
    for _, hold in ipairs(profile.holds) do holdKeys[hold.key or ""] = true end
    return ActionKeys(profile.keys, holdKeys)
end

-- What each hold key does, from the profile and the bars as they are now.
-- A line "keys": the action keys press a bar. Any other: that bar shows
-- another's actions in place. A bind: one key for one button.
function L.Build(profile)
    local out = { holds = {} }
    local holdKeys, seen = {}, {}
    for _, hold in ipairs(profile.holds) do
        if type(hold.key) == "string" then holdKeys[hold.key] = true end
    end
    local keys = ActionKeys(profile.keys, holdKeys)
    for _, hold in ipairs(profile.holds) do
        if type(hold.key) == "string" and hold.key ~= "" and not seen[hold.key] then
            seen[hold.key] = true
            local built = { key = hold.key, binds = {}, swaps = {}, lit = {}, source = hold }
            local at = {}
            local function Bind(key, button)
                if key == hold.key then return end
                local entry = { key = key, action = Bars.Press(button), button = button:GetName() }
                if at[key] then built.binds[at[key]] = entry else
                    built.binds[#built.binds + 1] = entry
                    at[key] = #built.binds
                end
            end
            for _, line in ipairs(hold.lines or {}) do
                local to = Bars.Bar(line.to)
                if to and line.what == "keys" then
                    for i, button in ipairs(to.buttons) do
                        for _, key in ipairs(keys[i] or {}) do Bind(key, button) end
                        if keys[i] and keys[i][1] then
                            built.lit[#built.lit + 1] = { button = button:GetName(), key = keys[i][1] }
                        end
                    end
                elseif to and Bars.Bar(line.what) and line.what ~= line.to then
                    for i, button in ipairs(Bars.Bar(line.what).buttons) do
                        local slot = Bars.Home(to, i)
                        local attr, value, old
                        if slot then attr, value, old = Bars.Swap(button, slot) end
                        if attr then
                            built.swaps[#built.swaps + 1] = { button = button:GetName(), attr = attr, value = value,
                                old = old }
                            built.lit[#built.lit + 1] = { button = button:GetName() }
                        end
                    end
                end
            end
            for _, bind in ipairs(hold.binds or {}) do
                local button = Bars.Named(bind.button)
                if button and type(bind.key) == "string" then
                    Bind(bind.key, button)
                    built.lit[#built.lit + 1] = { button = bind.button, key = bind.key }
                end
            end
            out.holds[#out.holds + 1] = built
        end
    end
    return out
end

local function Signature(built)
    local parts = {}
    for _, hold in ipairs(built.holds) do
        parts[#parts + 1] = "H" .. hold.key
        for _, bind in ipairs(hold.binds) do parts[#parts + 1] = bind.key .. ">" .. bind.action end
        for _, swap in ipairs(hold.swaps) do
            parts[#parts + 1] = swap.button .. ":" .. swap.attr .. "=" .. swap.value .. "/" .. tostring(swap.old)
        end
        for _, lit in ipairs(hold.lit) do parts[#parts + 1] = lit.button .. "*" .. tostring(lit.key) end
    end
    return table.concat(parts, "|")
end

local function Root()
    if root then return root end
    root = CreateFrame("Frame", ROOT, UIParent, "SecureHandlerBaseTemplate")
    root:HookScript("OnAttributeChanged", function(_, name)
        if name == "layer" then L.Changed() end
    end)
    return root
end

local function Button(i)
    if buttons[i] then return buttons[i] end
    -- starts shown: a key's click reaches it either way, and it draws nothing
    local button = CreateFrame("Button", HOLD .. i, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyDown", "AnyUp")
    Root():WrapScript(button, "OnClick", HOLD_WRAP)
    root:SetFrameRef("hold" .. i, button)
    buttons[i] = button
    return button
end

-- the built plan goes to the secure side; nothing is held after it
local function Push(built)
    Root():Execute(RESET)
    ClearOverrideBindings(root)
    root:SetAttribute("holds", #built.holds)
    for i, hold in ipairs(built.holds) do
        Button(i)
        root:SetAttribute("hkey" .. i, hold.key)
        root:SetAttribute("hname" .. i, HOLD .. i)
        root:SetAttribute("binds" .. i, #hold.binds)
        for j, bind in ipairs(hold.binds) do
            root:SetAttribute("bkey" .. i .. "_" .. j, bind.key)
            root:SetAttribute("bdo" .. i .. "_" .. j, bind.action)
        end
        root:SetAttribute("swaps" .. i, #hold.swaps)
        for j, swap in ipairs(hold.swaps) do
            local at = i .. "_" .. j
            root:SetFrameRef("swap" .. at, _G[swap.button])
            root:SetAttribute("sattr" .. at, swap.attr)
            root:SetAttribute("sval" .. at, swap.value)
            root:SetAttribute("sold" .. at, swap.old)
        end
    end
    root:Execute("local owner, now = self, nil\n" .. BIND)
    quiet = GetTime() + 1
end

-- Builds from the profile in use and binds. In a fight, or with a hold key
-- down, it waits. `force`: also when nothing changed. `deep`: the bars are
-- looked for anew, not only their keys.
function L.Apply(force, deep)
    if not ns.started then return false end
    if InCombatLockdown() or (L.Held() and not force) then
        pending = true
        return false
    end
    pending = false
    -- a held one's keys mask what the keys do by themselves: off before they are read
    if L.Held() then
        root:Execute(RESET)
        root:Execute("local owner, now = self, nil\n" .. BIND)
    end
    Bars.Forget(deep)
    local built = L.Build(Profiles.Data())
    local sig = Signature(built)
    if sig == signature and not force then return false end
    plan, signature = built, sig
    Push(built)
    ns.Log(("layers: %d hold keys bound"):format(#built.holds))
    Tell()
    return true
end

local function KeyDown(key)
    local n = key:match("^BUTTON(%d+)$")
    if n then return IsMouseButtonDown("Button" .. n) end
    return IsKeyDown(key)
end

-- a hold key that reads as up while it counts as held: its release was lost
local function Stuck()
    local held = L.Held()
    local hold = held and plan and plan.holds[held]
    if not hold then return false end
    if KeyDown(hold.key) then
        upFor, trusted = 0, true
        return false
    end
    -- a key the game never reads as down proves nothing by reading as up
    if not trusted then return false end
    upFor = upFor + 1
    return upFor >= STUCK_AFTER
end

function L.Changed()
    local held = L.Held()
    ns.Log(("layers: held %s at %.2f"):format(tostring(held), GetTime()))
    upFor, trusted, quiet = 0, false, GetTime() + 1
    if held and not watch then
        watch = C_Timer.NewTicker(STUCK_EVERY, function()
            if not L.Held() then
                watch:Cancel()
                watch = nil
                if pending then L.Apply() end
            elseif Stuck() and not InCombatLockdown() then
                local key = plan.holds[L.Held()].key
                ns.Log(("layers: a release of %s was lost, keys put back; the key did \"%s\""):format(key,
                    GetBindingAction(key, true)))
                L.Apply(true)
            end
        end)
    end
    Tell()
end

ns.OnStart(function()
    Profiles.OnChange(function() L.Apply() end)
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("UPDATE_BINDINGS")
    local due = false
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if pending then L.Apply() end
            return
        end
        -- our own snippets change bindings too: those are not looked at
        if due or GetTime() < quiet then return end
        due = true
        C_Timer.After(0.5, function()
            due = false
            L.Apply()
        end)
    end)
    L.Apply(false, true)
    -- bars of other addons are placed after login
    C_Timer.After(3, function() L.Apply(false, true) end)
end)
