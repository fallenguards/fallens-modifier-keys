local _, ns = ...
-- luacheck: read globals UIParent CreateFrame InCombatLockdown C_Timer ClearOverrideBindings GetTime
-- luacheck: read globals IsKeyDown IsMouseButtonDown GetBindingAction
-- luacheck: read globals FallensFlyouts_KeyTarget FallensFlyouts_Watch FallensFlyouts_Layers
-- luacheck: read globals FallensFlyouts_LayersChanged

-- Hold keys. Each is bound to a secure button of ours; its press and release
-- run a snippet that binds the held one's keys and switches its bars, and
-- puts them back. All of it is secure code, so it works in a fight.
local L = {}
ns.Layers = L
local Bars, Profiles = ns.Bars, ns.Profiles

local ROOT, HOLD, KEY = "FallensModifierKeysRoot", "FallensModifierKeysHold", "FallensModifierKeysKey"
L.ROOT, L.HOLD, L.KEY = ROOT, HOLD, KEY
-- Fallen's Flyouts binds from a root of its own. The two agreed: a hold key
-- is never a key of a flyout, a layer key sent to a button with a flyout is
-- bound to what that addon names (the flyout opens), and the keys of an
-- open flyout are left alone. It reads "layer" and "lkey<n>_<KEY>" here,
-- and leaves an opener key of its own unbound while the held layer has it.
-- Its binding runs only when a flyout opens or shuts, so once that layer is
-- off the key is bound here to its opener, as it binds it ("lany_<KEY>":
-- the keys any layer takes). While a flyout is open its keys are its own,
-- a hold key among them too, but for one that is down then ("hdown_<KEY>",
-- set from a held key's press to its release): bound over, its release
-- would be lost.
local FLYOUTS_ROOT = "FallensFlyoutsRoot"
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
-- Every hold key on its button, then the held one's keys on top; a key
-- that picks from or shuts an open flyout stays that flyout's, a hold key
-- too.
local BIND = [[
    owner:ClearBindings()
    do
        local theirs = owner:GetFrameRef("flyouts")
        local open = theirs and theirs:GetAttribute("open")
        local kept, taken = newtable(), newtable()
        if open then
            for i = 1, theirs:GetAttribute("pkeys" .. open) or 0 do
                kept[theirs:GetAttribute("pkey" .. open .. "_" .. i) or ""] = true
            end
            for i = 1, theirs:GetAttribute("ckeys") or 0 do
                kept[theirs:GetAttribute("ckey" .. i) or ""] = true
            end
        end
        -- a hold key the open flyout uses is bound under that flyout's own binding, and is ours again when it shuts
        for i = 1, owner:GetAttribute("holds") or 0 do
            local key = owner:GetAttribute("hkey" .. i)
            owner:SetBindingClick(not kept[key], key, owner:GetAttribute("hname" .. i))
        end
        for j = 1, now and owner:GetAttribute("binds" .. now) or 0 do
            local at = now .. "_" .. j
            local key = owner:GetAttribute("bkey" .. at)
            taken[key] = true
            if not kept[key] then owner:SetBinding(true, key, owner:GetAttribute("bdo" .. at)) end
        end
        for f = 1, theirs and theirs:GetAttribute("units") or 0 do
            local name = theirs:GetAttribute("opener" .. f)
            for i = 1, theirs:GetAttribute("okeys" .. f) or 0 do
                local at = f .. "_" .. i
                local key = theirs:GetAttribute("okey" .. at)
                if key and name and owner:GetAttribute("lany_" .. key) and not taken[key] and not kept[key] then
                    owner:SetBindingClick(true, key, name, theirs:GetAttribute("obtn" .. at))
                end
            end
        end
        -- a tapped layer stays on: Escape lets go of it
        if now and owner:GetAttribute("tap" .. now) and not kept.ESCAPE then
            owner:SetBindingClick(true, "ESCAPE", owner:GetAttribute("hname" .. now), "cancel")
        end
    end
]]
-- Each hold key works one of two ways. Held: the one last pressed and
-- still down is the held one; a release with no press before it (its
-- press went to a key of another hold) is nothing, and letting one go
-- leaves a tapped layer on. Tapped: a press turns its layer on and it
-- stays ("latched"); a press of the same key with it on, or Escape, turns
-- it off.
local HOLD_WRAP = [[
    if self:GetAttribute("tap") then
        if not down then return false end
        local now = self:GetAttribute("index")
        if button == "cancel" or owner:GetAttribute("layer") == now then now = nil end
]] .. UNSWAP .. SWAP .. BIND .. [[
        owner:SetAttribute("latched", now and true or nil)
        owner:SetAttribute("layer", now)
        return false
    end
    local mine = "hdown_" .. owner:GetAttribute("hkey" .. self:GetAttribute("index"))
    if down then
        seq = (seq or 0) + 1
        self:SetAttribute("stamp", seq)
        owner:SetAttribute(mine, true)
    else
        if not self:GetAttribute("stamp") then return false end
        self:SetAttribute("stamp", nil)
        owner:SetAttribute(mine, nil)
    end
    local top, best
    for i = 1, owner:GetAttribute("holds") or 0 do
        local stamp = owner:GetFrameRef("hold" .. i):GetAttribute("stamp")
        if stamp and (not best or stamp > best) then top, best = i, stamp end
    end
    if top ~= owner:GetAttribute("layer") and (top or not owner:GetAttribute("latched")) then
        local now = top
]] .. UNSWAP .. SWAP .. BIND .. [[
        owner:SetAttribute("latched", nil)
        owner:SetAttribute("layer", now)
    end
    return false
]]
-- nothing held, every bar its own
local RESET = "local owner = self\n" .. UNSWAP .. [[
    for i = 1, owner:GetAttribute("holds") or 0 do
        owner:GetFrameRef("hold" .. i):SetAttribute("stamp", nil)
        owner:SetAttribute("hdown_" .. (owner:GetAttribute("hkey" .. i) or ""), nil)
    end
    seq = 0
    owner:SetAttribute("latched", nil)
    owner:SetAttribute("layer", nil)
]]

-- A tapped layer's keys go through buttons of ours that pass the press on
-- (a macro clicking the target down and up), so the secure side sees the
-- key and can end the layer with it. Ended after the release, once the
-- button has acted; a release with no press of its own before it (the
-- tap that turned the layer on) is nothing.
local KEY_PRE = [[
    if down then
        self:SetAttribute("mid", true)
        return
    end
    if not self:GetAttribute("mid") then return false end
    self:SetAttribute("mid", nil)
    return nil, "spent"
]]
local KEY_POST = [[
    local now = nil
]] .. UNSWAP .. SWAP .. BIND .. [[
    owner:SetAttribute("latched", nil)
    owner:SetAttribute("layer", nil)
]]

-- the dev addon runs it by hand: a real key cannot be pressed by code
L.WRAP = HOLD_WRAP

local root, plan, signature
local buttons, proxies, published = {}, {}, {}
local holdSet, told = "", false
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

-- The frame and click the other addon names for a key meant for this
-- button; nil: no flyout on it. `tapped`: the press is passed on with its
-- release in the same instant, so it is sent as that addon's "tap" (a key
-- that cannot be held), whatever the key.
local function Flyout(button, key, tapped)
    if not FallensFlyouts_KeyTarget then return nil end
    local frame, click = FallensFlyouts_KeyTarget(button:GetName(), key)
    if type(frame) ~= "string" then return nil end
    return "CLICK " .. frame .. ":" .. (tapped and "tap" or click or "LeftButton")
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

-- The same for one hold key of a profile. Under a held one no hold key is
-- an action key: one is down and the others switch. Under a tapped one
-- every key is, hold keys too: its layer is on with no key down. With no
-- hold named: as shown in the window, where a hold key is left out only
-- when none is tapped.
function L.ActionKeys(profile, hold)
    local holdKeys, anyTap = {}, false
    for _, other in ipairs(profile.holds) do
        holdKeys[other.key or ""] = true
        anyTap = anyTap or other.tap == true
    end
    if (hold and hold.tap) or (not hold and anyTap) then holdKeys = {} end
    return ActionKeys(profile.keys, holdKeys)
end

-- the macro that passes a key's press on to what `action` presses
local function Macro(action, button)
    local frame, how = action:match("^CLICK (.-):(.*)$")
    if not frame then frame, how = button, "LeftButton" end
    return ("/click %s %s 1\n/click %s %s 0"):format(frame, how, frame, how)
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
    for _, hold in ipairs(profile.holds) do
        if type(hold.key) == "string" and hold.key ~= "" and not seen[hold.key] then
            seen[hold.key] = true
            local built = { key = hold.key, binds = {}, swaps = {}, lit = {}, source = hold, tap = hold.tap == true }
            local keys = L.ActionKeys(profile, hold)
            local at = {}
            -- `plain`: the button itself is pressed, whatever flyout it has
            local function Bind(key, button, plain)
                if key == hold.key and not built.tap then return end
                local action = plain and Bars.Press(button, true) or Flyout(button, key, built.tap)
                    or Bars.Press(button)
                local entry = { key = key, action = action, button = button:GetName() }
                -- tapped, a key sent to another button goes through a button of ours
                if built.tap and not plain then entry.macro = Macro(action, entry.button) end
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
                            -- its own keys open its own flyout: while it shows another action they press it
                            for _, key in ipairs(Bars.Keys(button)) do
                                if not holdKeys[key] and Flyout(button, key) then Bind(key, button, true) end
                            end
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

-- The flyout openers on keys a layer of ours takes, as that addon's root
-- lists them now: a change there is a change to what is bound here.
local function Openers(built)
    local theirs = _G[FLYOUTS_ROOT]
    if type(theirs) ~= "table" or not theirs.GetAttribute then return "" end
    local ours, parts = {}, {}
    for _, hold in ipairs(built.holds) do
        for _, bind in ipairs(hold.binds) do ours[bind.key] = true end
    end
    for f = 1, theirs:GetAttribute("units") or 0 do
        for i = 1, theirs:GetAttribute("okeys" .. f) or 0 do
            local at = f .. "_" .. i
            local key = theirs:GetAttribute("okey" .. at)
            if key and ours[key] then
                parts[#parts + 1] = key .. ">" .. tostring(theirs:GetAttribute("opener" .. f)) .. ":"
                    .. tostring(theirs:GetAttribute("obtn" .. at))
            end
        end
    end
    return table.concat(parts, "|")
end

local function Signature(built)
    local parts = {}
    for _, hold in ipairs(built.holds) do
        parts[#parts + 1] = (hold.tap and "T" or "H") .. hold.key
        for _, bind in ipairs(hold.binds) do
            parts[#parts + 1] = bind.key .. ">" .. bind.action .. (bind.macro and "~" or "")
        end
        for _, swap in ipairs(hold.swaps) do
            parts[#parts + 1] = swap.button .. ":" .. swap.attr .. "=" .. swap.value .. "/" .. tostring(swap.old)
        end
        for _, lit in ipairs(hold.lit) do parts[#parts + 1] = lit.button .. "*" .. tostring(lit.key) end
    end
    return table.concat(parts, "|") .. "#" .. Openers(built)
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
    button:SetAttribute("index", i)
    buttons[i] = button
    return button
end

local function Proxy(n)
    if proxies[n] then return proxies[n] end
    -- starts shown: as the hold buttons
    local button = CreateFrame("Button", KEY .. n, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("type", "macro")
    Root():WrapScript(button, "OnClick", KEY_PRE, KEY_POST)
    proxies[n] = button
    return button
end

-- the built plan goes to the secure side; nothing is held after it
local function Push(built)
    Root():Execute(RESET)
    ClearOverrideBindings(root)
    if _G[FLYOUTS_ROOT] then root:SetFrameRef("flyouts", _G[FLYOUTS_ROOT]) end
    local now, passed = {}, 0
    root:SetAttribute("holds", #built.holds)
    for i, hold in ipairs(built.holds) do
        Button(i):SetAttribute("tap", hold.tap or nil)
        root:SetAttribute("tap" .. i, hold.tap or nil)
        root:SetAttribute("hkey" .. i, hold.key)
        root:SetAttribute("hname" .. i, HOLD .. i)
        root:SetAttribute("binds" .. i, #hold.binds)
        for j, bind in ipairs(hold.binds) do
            -- what the key is bound to: the target itself, or the button of ours that passes it on
            bind.bound = bind.action
            if bind.macro then
                passed = passed + 1
                local proxy = Proxy(passed)
                proxy:SetAttribute("macrotext", bind.macro)
                proxy:SetAttribute("mid", nil)
                bind.bound = "CLICK " .. KEY .. passed .. ":LeftButton"
            end
            root:SetAttribute("bkey" .. i .. "_" .. j, bind.key)
            root:SetAttribute("bdo" .. i .. "_" .. j, bind.bound)
            -- which keys each layer takes, and any layer, for a lookup by name
            now["lkey" .. i .. "_" .. bind.key] = true
            now["lany_" .. bind.key] = true
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
    for name in pairs(published) do
        if not now[name] then root:SetAttribute(name, nil) end
    end
    for name in pairs(now) do root:SetAttribute(name, true) end
    published = now
    root:Execute("local owner, now = self, nil\n" .. BIND)
    quiet = GetTime() + 1
end

-- the hold keys in use, as a list
function L.HoldKeys()
    local out = {}
    for _, hold in ipairs(plan and plan.holds or {}) do out[#out + 1] = hold.key end
    return out
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
    local holdKeys = {}
    for _, hold in ipairs(Profiles.Data().holds) do holdKeys[hold.key or ""] = true end
    Bars.Mask(holdKeys)
    Bars.Forget(deep)
    local built = L.Build(Profiles.Data())
    local sig = Signature(built)
    -- the flyouts' root is made at their first lay, which may come after ours
    local theirs = _G[FLYOUTS_ROOT]
    local unmet = theirs ~= nil and (root == nil or root:GetAttribute("frameref-flyouts") == nil)
    if sig == signature and not force and not unmet then return false end
    plan, signature = built, sig
    Push(built)
    ns.Log(("layers: %d hold keys bound"):format(#built.holds))
    Tell()
    -- The flyouts give up a key that became a hold key, and take back one
    -- that stopped being one. They take our root at the same call, so they
    -- are told once more when both roots stand.
    local set = table.concat(L.HoldKeys(), " ")
    if FallensFlyouts_LayersChanged and (set ~= holdSet or (theirs and not told)) then
        holdSet, told = set, theirs ~= nil
        FallensFlyouts_LayersChanged()
    end
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
    -- a change that waited for a tapped layer to end
    if not held and pending and not watch then
        C_Timer.After(0.05, function()
            if pending then L.Apply() end
        end)
    end
    -- a tapped layer is on with its key up: nothing is stuck
    if held and not watch and not (plan and plan.holds[held] and plan.holds[held].tap) then
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
    if FallensFlyouts_Layers then
        FallensFlyouts_Layers({
            Held = function() return L.Held() ~= nil end,
            HoldKeys = L.HoldKeys,
            Root = function() return root end,
        })
    end
    -- a flyout made, moved or removed changes what a key for its button is bound to
    if FallensFlyouts_Watch then FallensFlyouts_Watch(function() L.Apply() end) end
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
