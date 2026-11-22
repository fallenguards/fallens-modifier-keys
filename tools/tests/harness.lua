-- The fake client the tests run the addon in: frames, bindings, secure snippets, the game's bars and two
-- other kinds (bars whose keys go through a helper child, bars of their own buttons), reloads between
-- sessions. Loaded by run.lua in one chunk with a test file, so its locals are the test's too.
-- MODEL: "captured" (a key's release goes to what its press went to) or "relookup".
-- luacheck: ignore

-- the bars of the session being booted: "game", "helper" or "own"
local barWorld = "game"
-- run once the bars stand and before the addon loads: an addon that loads first
local preload
local fails = 0
local char = { guid = "Player-1-0000000A", class = "MAGE", name = "Tester A" }
FallensModifierKeysDB = nil
-- the addon's own table, as the last session made it
local NS
-- one session
local W

local function check(ok, what)
    if ok then
        print("  ok   " .. what)
    else
        fails = fails + 1
        print("  FAIL " .. what)
    end
end

local function fire(event, ...)
    for _, f in ipairs(W.all) do
        if f.scripts.OnEvent and f.events and f.events[event] then f.scripts.OnEvent(f, event, ...) end
    end
end

local Frame = {}
Frame.__index = Frame
local function noop() end
for _, m in ipairs({ "ClearAllPoints", "RegisterForClicks", "EnableMouse", "SetAllPoints", "SetColorTexture",
    "SetJustifyH", "SetJustifyV", "SetFrameStrata", "SetMovable", "SetClampedToScreen", "RegisterForDrag",
    "SetAutoFocus", "SetFontObject", "SetTextColor", "SetWordWrap", "SetBlendMode", "SetMaxLetters",
    "StartMoving", "StopMovingOrSizing", "SetToplevel", "SetNormalFontObject", "SetHighlightFontObject",
    "SetAlpha", "SetHighlightTexture", "SetTexture", "AddLine" }) do
    Frame[m] = noop
end
local function region() return setmetatable({ scripts = {}, attrs = {}, shown = true }, Frame) end
function Frame:RegisterEvent(event)
    self.events = self.events or {}
    self.events[event] = true
end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:GetWidth() return self.w or 45 end
function Frame:GetHeight() return self.h or 45 end
function Frame:GetStringHeight() return 12 end
function Frame:GetStringWidth() return #(self.text or "") * 7 end
function Frame:GetTextWidth() return #(self.text or "") * 7 end
function Frame:SetPoint(...) self.point = { ... } end
function Frame:SetAtlas(atlas) self.atlas = atlas end
function Frame:SetText(v) self.text = v end
-- a button's text: cut short when the button is narrower than it
function Frame:GetFontString()
    self.label = self.label or region()
    self.label.of = self
    return self.label
end
function Frame:IsTruncated() return self.of ~= nil and self.of:GetTextWidth() > self.of:GetWidth() - 12 end
function Frame:GetText() return self.text end
function Frame:SetFrameLevel(level) self.level = level end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:SetEnabled(v) self.off = not v end
function Frame:IsEnabled() return not self.off end
function Frame:SetFocus() W.focus = self end
function Frame:ClearFocus() if W.focus == self then W.focus = nil end end
-- a drop down: its rows are asked for anew each time, the picked one is its text
function Frame:SetupMenu(fill) self.fill = fill; self:GenerateMenu() end
function Frame:GenerateMenu()
    local drop = self
    drop.rows, drop.Text = {}, drop.Text or region()
    drop.fill(drop, { CreateRadio = function(_, label, isOn, pick, data)
        drop.rows[#drop.rows + 1] = { label = label, pick = function() pick(data) end }
        if isOn(data) then drop.Text:SetText(label) end
    end })
end
function Frame:Hide()
    if not self.shown then return end
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Frame:Show()
    if self.shown then return end
    self.shown = true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Frame:GetName() return self.name end
function Frame:GetID() return self.id or 0 end
function Frame:GetParent() return self.parent end
function Frame:SetParent(parent) self.parent = parent end
function Frame:GetCenter() return self.cx or 0, self.cy or 0 end
function Frame:GetEffectiveScale() return 1 end
function Frame:IsForbidden() return false end
function Frame:IsObjectType(t) return self.otype == t end
function Frame:IsProtected() return self.protected or false end
-- addon code may not touch a protected frame in a fight; a snippet may
local function allowed(frame, what)
    assert(not (W.combat and frame.protected and not W.secure), what .. " on a protected frame in a fight")
end
function Frame:SetAttribute(k, v)
    allowed(self, "SetAttribute")
    self.attrs[k] = v
    if self.recount then self:recount() end
    if self.scripts.OnAttributeChanged then self.scripts.OnAttributeChanged(self, k, v) end
end
function Frame:GetAttribute(k) return self.attrs[k] end
-- as the client: a frame ref is kept as an attribute, and only a snippet can ask for it by GetFrameRef
function Frame:SetFrameRef(label, frame)
    allowed(self, "SetFrameRef")
    assert(type(frame) == "table", "SetFrameRef wants a frame")
    self.attrs["frameref-" .. label] = frame
end
function Frame:GetFrameRef(label)
    assert(W.secure, "GetFrameRef is a snippet's call: plain code has none")
    return self.attrs["frameref-" .. label]
end
function Frame:SetScript(k, fn) self.scripts[k] = fn end
function Frame:GetScript(k) return self.scripts[k] end
function Frame:HookScript(k, fn)
    local old = self.scripts[k]
    self.scripts[k] = function(...) if old then old(...) end fn(...) end
end
function Frame:CreateTexture() return region() end
function Frame:CreateFontString() return region() end
function Frame:WrapScript(frame, _, body, after)
    assert(frame.protected, "a wrap runs only on a protected frame")
    frame.wrap, frame.post, frame.header = body, after, self
end
-- the game's secure clock: a frame hides by itself after a time, and its "_onhide" snippet runs
function Frame:RegisterAutoHide(ttl)
    assert(W.secure, "RegisterAutoHide is a snippet's call")
    local frame = self
    frame.hideAt = W.clock + ttl
    W.queue[#W.queue + 1] = function()
        if not frame.shown or W.clock < frame.hideAt then return end
        frame.shown = false
        local body = frame.attrs._onhide
        if body then
            W.secure = true
            local ok, err = pcall(assert(load("local self = ...; " .. body, "onhide", "t", W.env)), frame)
            W.secure = false
            assert(ok, err)
        end
    end
end

-- override bindings: priority ones win, then the latest set
local function setOverride(owner, priority, key, action)
    assert(type(key) == "string" and type(action) == "string", "a binding wants a key and an action")
    W.overrides[owner] = W.overrides[owner] or {}
    W.seq = W.seq + 1
    W.overrides[owner][key] = { action = action, priority = priority and true or false, seq = W.seq }
    W.bindEvents = W.bindEvents + 1
end
function Frame:ClearBindings()
    allowed(self, "ClearBindings")
    W.overrides[self] = {}
end
function Frame:SetBindingClick(priority, key, name, button)
    allowed(self, "SetBindingClick")
    assert(type(name) == "string", "SetBindingClick wants a frame's name")
    setOverride(self, priority, key, "CLICK " .. name .. ":" .. (button or "LeftButton"))
end
function Frame:SetBinding(priority, key, action)
    allowed(self, "SetBinding")
    setOverride(self, priority, key, action)
end
function ClearOverrideBindings(owner) owner:ClearBindings() end
function SetOverrideBindingClick(owner, priority, key, name, button) owner:SetBindingClick(priority, key, name, button) end
-- a call runs after another's: of a global, or of one frame or region
function hooksecurefunc(holder, name, after)
    if type(holder) ~= "table" then holder, name, after = _G, holder, name end
    local old = holder[name]
    holder[name] = function(...)
        old(...)
        after(...)
    end
end

function CreateFrame(otype, name, parent, template)
    local protected = template ~= nil and template:find("Secure") ~= nil
    local f = setmetatable({ name = name, scripts = {}, attrs = {}, shown = true, otype = otype, parent = parent,
        protected = protected }, Frame)
    f.TitleText, f.CloseButton, f.Text = region(), region(), region()
    -- the game's key binding button: lit while it waits for its key
    f.template = template
    if template == "KeyBindingFrameBindingButtonTemplate" then
        f.SelectedHighlight = region()
        function f:SetSelected(on) self.selected = on end
    end
    if name then W.frames[name] = f; _G[name] = f end
    W.all[#W.all + 1] = f
    return f
end
function EnumerateFrames(prev)
    W.walks = W.walks + (prev and 0 or 1)
    if not prev then return W.all[1] end
    for i, f in ipairs(W.all) do
        if f == prev then return W.all[i + 1] end
    end
end

DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) W.chat[#W.chat + 1] = msg end }
UIErrorsFrame = { AddMessage = function(_, msg) W.errors[#W.errors + 1] = msg end }
GameTooltip = setmetatable({ SetOwner = noop, AddLine = noop, scripts = {}, attrs = {} }, Frame)
function GetTime() return W.clock end
function InCombatLockdown() return W.combat end
C_Timer = {
    After = function(_, fn) W.queue[#W.queue + 1] = fn end,
    NewTicker = function(_, fn)
        local ticker = { fn = fn }
        function ticker:Cancel() self.off = true end
        W.tickers[#W.tickers + 1] = ticker
        return ticker
    end,
}
-- time passes: waiting calls run, every ticker beats once
local function flush(seconds)
    W.clock = W.clock + (seconds or 1)
    for _ = 1, 5 do
        local q = W.queue
        W.queue = {}
        for _, fn in ipairs(q) do fn() end
    end
    for _, ticker in ipairs(W.tickers) do
        if not ticker.off then ticker.fn() end
    end
end

function IsKeyDown(key) return W.keyDown[key] or false end
function IsMouseButtonDown(name) return W.keyDown[(name:upper())] or false end
function GetBindingText(key) return key end
GRAY_FONT_COLOR = { WrapTextInColorCode = function(_, text) return text end }
NOT_BOUND, KEY_BOUND = "Not Bound", "Key Bound Successfully"
SETTINGS_BIND_KEY_TO_COMMAND_OR_CANCEL = "Assign Binding for \"%s\" or Press %s to Cancel"
function GetCursorPosition() return W.mouseX or 0, W.mouseY or 0 end
-- the game's options: an addon's page is a frame shown when its name is picked in the list
Settings = {
    RegisterCanvasLayoutCategory = function(page, title)
        local category = { page = page, title = title }
        function category:GetID() return title end
        return category
    end,
    RegisterAddOnCategory = function(category) Settings.listed = category end,
}
date = os.date
function debugstack() return "" end
C_CVar = { GetCVar = function() return "1" end }
function GetBindingName(action) return "name of " .. action end
function GetBuildInfo() return "12.0.0", "70009", "Nov 1 2026", 16001 end
function UnitClass() return char.class, char.class end
function UnitName() return "Tester", "Surname" end
function GetUnitName() return char.name end
function UnitGUID() return char.guid end
function GetRealmName() return "" end
function GetBindingAction(key, withOverrides)
    if withOverrides then
        local best
        for _, set in pairs(W.overrides) do
            local o = set[key]
            if o and (not best or (o.priority and not best.priority) or (o.priority == best.priority and o.seq > best.seq)) then
                best = o
            end
        end
        if best then return best.action end
    end
    return W.base[key] or ""
end
function SetBinding(key, command)
    W.base[key] = command
    fire("UPDATE_BINDINGS")
    return true
end

-- the game's bars: command stem, button name stem, the page the bar shows
local GAME_BARS = {
    { "ACTIONBUTTON", "ActionButton", 1, "MainActionBar" },
    { "MULTIACTIONBAR1BUTTON", "MultiBarBottomLeftButton", 6, "MultiBarBottomLeft" },
    { "MULTIACTIONBAR2BUTTON", "MultiBarBottomRightButton", 5, "MultiBarBottomRight" },
    { "MULTIACTIONBAR3BUTTON", "MultiBarRightButton", 3, "MultiBarRight" },
    { "MULTIACTIONBAR4BUTTON", "MultiBarLeftButton", 4, "MultiBarLeft" },
}
-- The game writes a button's key text afresh at every change of bindings:
-- the key set in the key menu, or a hidden dot when there is none.
local DOT = "*"
local function writeKeys()
    for _, b in ipairs(W.all) do
        if b.command then
            local key
            for k, action in pairs(W.base) do
                if action == b.command and (not key or k < key) then key = k end
            end
            b.HotKey:SetText(key or DOT)
            if key then b.HotKey:Show() else b.HotKey:Hide() end
        end
    end
end
-- a button of the game's: its slot follows its own page, else its bar's
local function gameButton(name, id, bar, command)
    local b = CreateFrame("CheckButton", name, bar, "ActionBarButtonTemplate, SecureActionButtonTemplate")
    b.id, b.attrs.type = id, "action"
    b.command, b.HotKey = command, region()
    function b:recount() self.action = self.id + ((self.attrs.actionpage or self.parent.attrs.actionpage) - 1) * 12 end
    b:recount()
    return b
end
-- a button of another addon's: its slot is its own attribute
local function otherButton(name, slot, bar)
    local b = CreateFrame("CheckButton", name, bar, "SecureActionButtonTemplate")
    b.attrs.type, b.attrs.action = "action", slot
    function b:recount() self.action = self.attrs.action end
    b:recount()
    return b
end

-- the files the addon's toc lists, in its order
local function tocFiles()
    local files = {}
    for line in io.lines("FallensModifierKeys.toc") do
        line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then files[#files + 1] = (line:gsub("\\", "/")) end
    end
    return files
end

-- a new session: the bars, then the addon (and a driver, when a test names one) and a login
local function boot(alone)
    for name in pairs(W and W.frames or {}) do _G[name] = nil end
    W = { frames = {}, all = {}, overrides = {}, queue = {}, tickers = {}, casts = {}, chat = {}, errors = {},
        keyDown = {}, held = {}, base = { ESCAPE = "TOGGLEGAMEMENU", SPACE = "JUMP", Z = "TOGGLESHEATH" },
        seq = 0, clock = 100, combat = false, walks = 0, bindEvents = 0 }
    for i = 1, 6 do W.base[tostring(i)] = "ACTIONBUTTON" .. i end
    W.base["SHIFT-1"] = "ACTIONBUTTON7"
    W.base.F = "MULTIACTIONBAR1BUTTON2"
    SlashCmdList = {}
    UIParent = CreateFrame("Frame", "UIParent")
    Minimap = CreateFrame("Frame", "Minimap", UIParent)
    Minimap.w, Minimap.h, Minimap.cx, Minimap.cy = 140, 140, 1000, 900
    for n, spec in ipairs(GAME_BARS) do
        local bar = CreateFrame("Frame", spec[4], UIParent)
        bar.attrs.actionpage = spec[3]
        -- the last of the game's bars is turned off in its options
        bar.shown = barWorld == "game" and n < #GAME_BARS
        for i = 1, 12 do gameButton(spec[2] .. i, i, bar, spec[1] .. i) end
    end
    local client = CreateFrame("Frame")
    client:RegisterEvent("UPDATE_BINDINGS")
    client:SetScript("OnEvent", writeKeys)
    writeKeys()
    if barWorld == "helper" then
        local bar = CreateFrame("Frame", "SideBarFrame2", UIParent)
        for i = 1, 4 do
            local name = "SideBarButton" .. i
            local b = otherButton(name, 120 + i, bar)
            local hot = CreateFrame("Button", name .. "Hotkey", b, "SecureActionButtonTemplate")
            hot.forwards = b
            if i <= 2 then setOverride(bar, false, "F" .. i, "CLICK " .. name .. "Hotkey:HOTKEY") end
        end
    end
    if barWorld == "own" then
        for n = 1, 2 do
            local bar = CreateFrame("Frame", "OwnBar" .. n, UIParent)
            for i = 1, 4 do
                local b = otherButton("OwnBarButton" .. ((n - 1) * 4 + i), (n - 1) * 12 + i, bar)
                if n == 1 then setOverride(bar, false, tostring(i), "CLICK " .. b.name .. ":Keybind") end
            end
        end
    end
    -- one snippet world per session, as the client keeps per header
    W.env = setmetatable({ newtable = function() return {} end }, { __index = function(t, k)
        if k == "seq" then return rawget(t, k) end
        error("snippet read of a missing global: " .. tostring(k))
    end })
    if preload then preload() end
    NS = {}
    for _, file in ipairs(tocFiles()) do
        assert(loadfile(file))("FallensModifierKeys", NS)
    end
    if DRIVER and not alone then assert(loadfile(DRIVER))() end
    fire("PLAYER_LOGIN")
end

-- a press or release reaching a frame: its wrap first, then what it does
local click
-- a secure button's own action, on the press (the game's "cast on key down" is on)
local function act(frame)
    if frame.attrs.type == "action" then
        W.casts[#W.casts + 1] = frame.action
    elseif frame.attrs.type == "macro" then
        -- a macro's /click lines click as secure code: a wrapped button takes them
        for line in (frame.attrs.macrotext or ""):gmatch("[^\n]+") do
            local name, how, state = line:match("^/click (%S+) (%S+) (%d)$")
            assert(name and W.frames[name], "a macro line the fake client cannot run: " .. line)
            click(W.frames[name], state == "1", how)
        end
    end
end
function click(frame, down, how)
    how = how or "LeftButton"
    if frame.forwards then frame = frame.forwards end
    local message
    if frame.wrap then
        W.secure = true
        local fn = assert(load("local self, button, down, owner = ...; " .. frame.wrap, frame.name, "t", W.env))
        local ok, verdict, said = pcall(fn, frame, how, down, frame.header)
        W.secure = false
        assert(ok, verdict)
        if verdict == false then return end
        message = said
    end
    if down then act(frame) end
    -- the wrap's second snippet runs after the click's own action, when the first handed it a message
    if message ~= nil and frame.post then
        W.secure = true
        local fn = assert(load("local self, message, button, down, owner = ...; " .. frame.post, frame.name, "t", W.env))
        local ok, err = pcall(fn, frame, message, how, down, frame.header)
        W.secure = false
        assert(ok, err)
    end
end
-- the client refuses a wrapped click made by addon code
function Frame:Click(_, down)
    if self.wrap then error("Invalid 'header' frame handle") end
    click(self, down)
end
function Frame:Execute(body)
    assert(not W.combat, "Execute in a fight")
    W.secure = true
    local ok, err = pcall(assert(load("local self = ...; " .. body, "execute", "t", W.env)), self)
    W.secure = false
    assert(ok, err)
end

-- what a key does now: a frame and the click's name, or a command of the game's
local function target(key)
    local action = GetBindingAction(key, true)
    local name, how = action:match("^CLICK (.-):(.*)$")
    if name then return W.frames[name], how, action end
    for _, spec in ipairs(GAME_BARS) do
        local index = action:match("^" .. spec[1] .. "(%d+)$")
        if index then return W.frames[spec[2] .. index], nil, action end
    end
    return nil, nil, action
end
local function settle(before)
    if W.bindEvents ~= before then fire("UPDATE_BINDINGS") end
end
local function press(key)
    local frame, how, action = target(key)
    local before = W.bindEvents
    W.held[key] = { frame, how }
    W.keyDown[key] = true
    W.last = action
    if frame then click(frame, true, how) end
    settle(before)
end
local function release(key)
    local frame, how
    if MODEL == "captured" then
        frame, how = W.held[key][1], W.held[key][2]
    else
        frame, how = target(key)
    end
    local before = W.bindEvents
    W.held[key] = nil
    W.keyDown[key] = nil
    if frame then click(frame, false, how) end
    settle(before)
end
local function tap(key) press(key); release(key) end
-- the slot the last press cast, and what the key was bound to
local function cast() return W.casts[#W.casts] end
