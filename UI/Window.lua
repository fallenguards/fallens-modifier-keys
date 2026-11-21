local _, ns = ...
-- luacheck: globals SLASH_FALLENSMODIFIERKEYS1 SLASH_FALLENSMODIFIERKEYS2 SlashCmdList
-- luacheck: globals FallensModifierKeys_OnAddonCompartmentClick
-- luacheck: read globals CreateFrame UIParent InCombatLockdown C_Timer GetTime GameTooltip GetBindingText
-- luacheck: read globals CreateKeyChordStringUsingMetaKeyState NineSliceUtil

-- The setup: the action keys, the modifier keys, each on a line. It stands
-- in a window of its own (/fmk, the minimap button; by itself the first
-- time the addon is loaded) or on the addon's page in the game's options:
-- one set of controls, moved to whichever is looked at.
local UI = {}
ns.Window = UI
local Model, Bars, Profiles = ns.Model, ns.Bars, ns.Profiles

local NAME, TITLE = "FallensModifierKeysWindow", "Fallen's Modifier Keys"
local WIDTH, EDGE, TOP, GAP, LINE = 560, 18, 44, 8, 24
local INSIDE = WIDTH - EDGE * 2
-- one line of a modifier key: key, how it works, what changes, the bar, minus, plus
local KEY_W, MODE_W, WHAT_W, TO_W, SMALL_W, KEYS_W, ROW_GAP = 84, 84, 150, 136, 24, 230, 4
-- the twelve key boxes: as wide as the window lets twelve be
local BOX_GAP, NUMBER_H = 3, 14
local BOX_W = math.floor((INSIDE - BOX_GAP * (Model.SPOTS - 1)) / Model.SPOTS)
-- floors: a button grows to its text
local BUTTON_FLOOR, CHROME = 80, 24

local TEXT = {
    intro = "Hold a key and your action keys press another bar. Let go and they are your own again.",
    keysHead = "1. Your action keys",
    keysNote = "The keys your bars will show when your modifier is held. Click a box and press its key.",
    waitSpot = "Press the key for box %d. Backspace empties it, Escape cancels.",
    waiting = "...",
    keysOf = "The keys of %s",
    ownKeys = "Custom key list",
    holdsHead = "2. Your modifier (keys you'll hold) keys",
    holdsWarn = "Warning: this key will now only serve to activate the action bar you set here.",
    hold = "Hold",
    tap = "Tap",
    modeTip = "Hold: its bar is in use while the key is down. Tap: after a tap, for the next key you press.",
    addHold = "Add a modifier key",
    setKey = "Set key",
    press = "Press a key",
    waitHold = "Press the key or mouse button to use as a modifier. Escape cancels.",
    keysPress = "Action keys press",
    shows = "%s shows",
    hidden = "%s (hidden)",
    tryHead = "3. Try it",
    tryNote = "Hold or tap a modifier key now: the bar it uses lights up and shows your keys.",
    profile = "Profile",
    own = "%s (this character)",
    class = "%s (this class)",
    all = "%s (every character)",
    fight = "The window opens out of a fight.",
    welcome = "Type /fmk to set up your modifier keys.",
    later = "You can modify this at any time later via \"/fmk\", the minimap icon, or the addon settings window.",
    moreTip = "Switch one more bar with this key.",
    lessTip = "Take this line off.",
}
UI.TEXT = TEXT
-- mouse buttons a hold key can be, by the name a click gives them
local MOUSE = { MiddleButton = "BUTTON3" }
for n = 4, 31 do MOUSE["Button" .. n] = "BUTTON" .. n end
-- typed characters whose key has another name
local NAMED = { [" "] = "SPACE" }
-- keys that only go with another: never a key by themselves
local ALONE = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true,
    RMETA = true }
-- these empty a box
local CLEAR = { BACKSPACE = true, DELETE = true }

local shell, window, catcher, capture
local rows = {}
local keyAt = 0

local function Warn(why) if why then ns.Warn(why) end end

local function Tip(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
    GameTooltip:Show()
end
local function NoTip() GameTooltip:Hide() end

local function BarLabel(bar)
    if bar.shown then return bar.title end
    return TEXT.hidden:format(bar.title)
end

-- a key as the bars write it: short
local function Short(key)
    local text = GetBindingText(key, 1)
    if type(text) ~= "string" or text == "" then return key end
    return text
end

-- an action key with the modifiers held, in the game's own order
local function Chord(key)
    if CreateKeyChordStringUsingMetaKeyState then return CreateKeyChordStringUsingMetaKeyState(key) end
    return key
end

-- a key is being waited for: fn(key) takes it; `where`: the section whose note says so
local function Capture(fn, note, where)
    capture = { fn = fn, note = note, where = where }
    catcher:Show()
    catcher:SetFocus()
    UI.Refresh()
end

function UI.EndCapture()
    if not capture then return end
    capture = nil
    catcher:ClearFocus()
    catcher:Hide()
    UI.Refresh()
end

-- a key or mouse button came in while one was waited for
function UI.Pressed(key)
    if not capture or ALONE[key] then return end
    if key == "ESCAPE" then return UI.EndCapture() end
    local ok, why = capture.fn(key)
    if ok then return UI.EndCapture() end
    Warn(why)
end

-- Keys are read from a typing box that holds the focus while one is waited
-- for, never from a frame that takes the keyboard.
local function Catcher()
    local box = CreateFrame("EditBox", nil, UIParent)
    box:Hide()
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontNormal")
    box:SetSize(1, 1)
    box:SetAlpha(0)
    box:SetPoint("TOPLEFT", UIParent, "TOPLEFT")
    box:SetScript("OnKeyDown", function(self, key)
        keyAt = GetTime()
        self:SetText("")
        UI.Pressed(key)
    end)
    -- a client that gives the box only what was typed: the character names the key
    box:SetScript("OnChar", function(self, char)
        self:SetText("")
        if GetTime() ~= keyAt then UI.Pressed(NAMED[char] or char:upper()) end
    end)
    box:SetScript("OnEscapePressed", function() UI.EndCapture() end)
    box:SetScript("OnEditFocusLost", function() UI.EndCapture() end)
    return box
end

local function Text(font, text)
    local line = window:CreateFontString(nil, "ARTWORK", font)
    line:SetJustifyH("LEFT")
    line:SetJustifyV("TOP")
    line:SetWidth(INSIDE)
    line:SetWordWrap(true)
    if text then line:SetText(text) end
    return line
end

local function Fit(button)
    button:SetSize(math.max(BUTTON_FLOOR, (button:GetTextWidth() or 0) + CHROME), LINE)
end

local function Push(label, run, tip)
    local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    button:SetText(label)
    Fit(button)
    button.tip = tip
    button:SetScript("OnClick", run)
    button:SetScript("OnEnter", Tip)
    button:SetScript("OnLeave", NoTip)
    return button
end

local function Drop(width, fill)
    local drop = CreateFrame("DropdownButton", nil, window, "WowStyle1DropdownTemplate")
    drop:SetWidth(width)
    drop:SetupMenu(fill)
    return drop
end

-- the action keys' own drop down: each bar's keys, or the player's own
local function FillKeys(_, root)
    local keys = Profiles.Data().keys
    for _, bar in ipairs(Bars.List()) do
        root:CreateRadio(TEXT.keysOf:format(BarLabel(bar)),
            function(id) return not keys.list and keys.bar == id end,
            function(id) Warn(select(2, Model.UseBar(id))) end, bar.id)
    end
    root:CreateRadio(TEXT.ownKeys, function() return keys.list ~= nil end,
        function() Warn(select(2, Model.UseList())) end, "own")
end

local function FillProfiles(_, root)
    local shape = { own = TEXT.own, class = TEXT.class, all = TEXT.all }
    for _, entry in ipairs(Profiles.Names()) do
        local label = entry.kind and shape[entry.kind]:format(entry.name) or entry.name
        root:CreateRadio(label, function(name) return Profiles.Active() == name end, function(name)
            local ok, why = Profiles.Use(name)
            if not ok then Warn(why) end
        end, entry.name)
    end
end

-- a row's key button waits for its key
function UI.WaitFor(row)
    local index = row.i
    Capture(function(key) return Model.SetHoldKey(index, key) end, TEXT.waitHold, "holds")
    capture.row = row
    UI.Refresh()
end

-- one line of a hold key: its key (on its first line), what changes, the bar it goes to
local function Row(n, i, j)
    if rows[n] then
        rows[n].i, rows[n].j = i, j
        return rows[n]
    end
    -- a drop down fills itself as it is made: its line is known by then
    local row = { i = i, j = j }
    local function Line()
        local hold = Profiles.Data().holds[row.i]
        return hold and hold.lines[row.j]
    end
    -- while it waits, a mouse button clicked on it is the key
    row.key = Push(TEXT.press, function(_, mouse)
        local taken = MOUSE[mouse]
        if capture and capture.row == row then
            if taken then UI.Pressed(taken) else UI.EndCapture() end
            return
        end
        if taken then return end
        UI.WaitFor(row)
    end)
    row.key:RegisterForClicks("AnyUp")
    row.key:SetSize(KEY_W, LINE)
    row.mode = Drop(MODE_W, function(_, root)
        root:CreateRadio(TEXT.hold, function() return not Model.Tap(row.i) end,
            function() Warn(select(2, Model.SetTap(row.i, false))) end, "hold")
        root:CreateRadio(TEXT.tap, function() return Model.Tap(row.i) end,
            function() Warn(select(2, Model.SetTap(row.i, true))) end, "tap")
    end)
    row.mode.tip = TEXT.modeTip
    row.mode:HookScript("OnEnter", Tip)
    row.mode:HookScript("OnLeave", NoTip)
    row.what = Drop(WHAT_W, function(_, root)
        local line = Line()
        if not line then return end
        local function On(what) return line.what == what end
        local function Pick(what) Warn(select(2, Model.SetLine(row.i, row.j, what, nil))) end
        root:CreateRadio(TEXT.keysPress, On, Pick, "keys")
        for _, bar in ipairs(Bars.List()) do
            root:CreateRadio(TEXT.shows:format(BarLabel(bar)), On, Pick, bar.id)
        end
    end)
    row.to = Drop(TO_W, function(_, root)
        local line = Line()
        if not line then return end
        for _, bar in ipairs(Bars.List()) do
            root:CreateRadio(BarLabel(bar), function(id) return line.to == id end,
                function(id) Warn(select(2, Model.SetLine(row.i, row.j, nil, id))) end, bar.id)
        end
    end)
    row.less = Push("-", function()
        local hold = Profiles.Data().holds[row.i]
        if #hold.lines > 1 then
            Warn(select(2, Model.RemoveLine(row.i, row.j)))
        else
            Warn(select(2, Model.RemoveHold(row.i)))
        end
    end, TEXT.lessTip)
    row.less:SetSize(SMALL_W, LINE)
    row.more = Push("+", function() Warn(select(2, Model.AddLine(row.i))) end, TEXT.moreTip)
    row.more:SetSize(SMALL_W, LINE)
    row.note = Text("GameFontDisableSmall")
    rows[n] = row
    return row
end

local function Place(piece, x, y) piece:SetPoint("TOPLEFT", window, "TOPLEFT", EDGE + x, -y) end

-- a line of text at y, as wide as the window lets it be; the y under it
local function Line(piece, y, gap)
    piece:ClearAllPoints()
    Place(piece, 0, y)
    piece:SetPoint("TOPRIGHT", window, "TOPRIGHT", -EDGE, -y)
    piece:Show()
    return y + piece:GetStringHeight() + (gap or GAP)
end

local function Build()
    -- starts shown: hidden before its OnShow is set
    shell = CreateFrame("Frame", NAME, UIParent)
    shell:Hide()
    -- the game's own dialog border over a dark backing, as its own windows wear it
    local back = shell:CreateTexture(nil, "BACKGROUND")
    back:SetPoint("TOPLEFT", shell, "TOPLEFT", 4, -4)
    back:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -4, 4)
    back:SetColorTexture(0.03, 0.03, 0.04, 0.92)
    if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then NineSliceUtil.ApplyLayoutByName(shell, "Dialog") end
    local title = shell:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", shell, "TOP", 0, -16)
    title:SetText(TITLE)
    local close = CreateFrame("Button", nil, shell, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", shell, "TOPRIGHT", -4, -4)
    shell:SetWidth(WIDTH)
    shell:SetPoint("LEFT", UIParent, "LEFT", 80, 80)
    shell:SetFrameStrata("DIALOG")
    shell:SetToplevel(true)
    shell:SetClampedToScreen(true)
    shell:SetMovable(true)
    shell:EnableMouse(true)
    shell:RegisterForDrag("LeftButton")
    shell:SetScript("OnDragStart", shell.StartMoving)
    shell:SetScript("OnDragStop", shell.StopMovingOrSizing)
    -- every control sits on this: in the window, or on the page in the game's options
    window = CreateFrame("Frame", nil, shell)
    window:SetWidth(WIDTH)
    window:SetPoint("TOPLEFT", shell, "TOPLEFT")
    window:SetScript("OnHide", function() UI.EndCapture() end)
    catcher = Catcher()

    window.intro = Text("GameFontHighlight", TEXT.intro)
    window.keysHead = Text("GameFontNormalLarge", TEXT.keysHead)
    window.keysNote = Text("GameFontHighlight", TEXT.keysNote)
    window.keysDrop = Drop(KEYS_W, FillKeys)
    -- One box per button of a bar. A click waits for its key; a right-click
    -- empties it. A bar's own keys become the player's at the first change.
    window.boxes = {}
    for i = 1, Model.SPOTS do
        local box = Push("", function(_, mouse)
            local taken = MOUSE[mouse]
            if capture and capture.box == i then
                if taken then UI.Pressed(taken) else UI.EndCapture() end
                return
            end
            if taken then return end
            if mouse == "RightButton" then return Warn(select(2, Model.SetKey(i, nil))) end
            Capture(function(key)
                if CLEAR[key] then return Model.SetKey(i, nil) end
                return Model.SetKey(i, MOUSE[key] and key or Chord(key))
            end, TEXT.waitSpot:format(i), "keys")
            capture.box = i
            UI.Refresh()
        end)
        box:RegisterForClicks("AnyUp")
        box:SetSize(BOX_W, LINE)
        box.number = window:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        box.number:SetPoint("TOP", box, "BOTTOM", 0, -2)
        box.number:SetText(tostring(i))
        window.boxes[i] = box
    end
    window.holdsHead = Text("GameFontNormalLarge", TEXT.holdsHead)
    window.holdsWarn = Text("GameFontRed", TEXT.holdsWarn)
    window.holdsWait = Text("GameFontHighlight", TEXT.waitHold)
    -- the new key's line stands at once, its key button waiting
    window.addHold = Push(TEXT.addHold, function()
        UI.EndCapture()
        local index, why = Model.AddHold()
        if not index then return Warn(why) end
        for _, row in ipairs(rows) do
            if row.i == index and row.j == 1 and row.key:IsShown() then return UI.WaitFor(row) end
        end
    end)
    window.tryHead = Text("GameFontNormalLarge", TEXT.tryHead)
    window.tryNote = Text("GameFontHighlight", TEXT.tryNote)
    window.later = Text("GameFontHighlight", TEXT.later)
    window.profileLabel = Text("GameFontNormal", TEXT.profile)
    window.profileLabel:SetWidth(0)
    window.profiles = Drop(KEYS_W, FillProfiles)

    Model.OnChange(UI.Refresh)
end

-- lays every piece out again from the profile in use
function UI.Refresh()
    if not (window and window:IsVisible()) then return end
    local data = Profiles.Data()
    local y = Line(window.intro, TOP, GAP * 2)

    y = Line(window.keysHead, y)
    window.keysNote:SetText(capture and capture.where == "keys" and capture.note or TEXT.keysNote)
    y = Line(window.keysNote, y)
    window.keysDrop:ClearAllPoints()
    Place(window.keysDrop, 0, y)
    window.keysDrop:GenerateMenu()
    y = y + LINE + GAP
    local spots = Model.Spots()
    for i, box in ipairs(window.boxes) do
        box:ClearAllPoints()
        Place(box, (i - 1) * (BOX_W + BOX_GAP), y)
        box:SetText(capture and capture.box == i and TEXT.waiting or (spots[i] and Short(spots[i]) or ""))
    end
    y = y + LINE + NUMBER_H + GAP * 2

    y = Line(window.holdsHead, y)
    -- the warning, or while a key is waited for, what to press
    local waiting = capture ~= nil and capture.where == "holds"
    window.holdsWarn:SetShown(not waiting)
    window.holdsWait:SetShown(waiting)
    y = Line(waiting and window.holdsWait or window.holdsWarn, y)
    local used = 0
    for i, hold in ipairs(data.holds) do
        for j in ipairs(hold.lines) do
            used = used + 1
            local row = Row(used, i, j)
            local first = j == 1
            row.key:SetShown(first)
            row.key:SetText(capture and capture.row == row and TEXT.press
                or (hold.key and Model.Label(hold.key) or TEXT.setKey))
            row.key:ClearAllPoints()
            Place(row.key, 0, y)
            row.mode:SetShown(first)
            row.mode:ClearAllPoints()
            Place(row.mode, KEY_W + ROW_GAP, y)
            row.mode:GenerateMenu()
            row.what:ClearAllPoints()
            Place(row.what, KEY_W + MODE_W + ROW_GAP * 2, y)
            row.what:Show()
            row.what:GenerateMenu()
            row.to:ClearAllPoints()
            row.to:SetPoint("LEFT", row.what, "RIGHT", ROW_GAP, 0)
            row.to:Show()
            row.to:GenerateMenu()
            row.less:ClearAllPoints()
            row.less:SetPoint("LEFT", row.to, "RIGHT", ROW_GAP, 0)
            row.less:Show()
            row.more:ClearAllPoints()
            row.more:SetPoint("LEFT", row.less, "RIGHT", 2, 0)
            row.more:SetShown(j == #hold.lines)
            y = y + LINE + GAP / 2
            if j == #hold.lines then
                row.note:SetText(Model.Sentence(i))
                y = Line(row.note, y, GAP * 1.5)
            else
                row.note:Hide()
            end
        end
    end
    for n = used + 1, #rows do
        local row = rows[n]
        row.key:Hide(); row.mode:Hide(); row.what:Hide(); row.to:Hide(); row.less:Hide(); row.more:Hide()
        row.note:Hide()
    end
    window.addHold:ClearAllPoints()
    Place(window.addHold, 0, y)
    y = y + LINE + GAP * 2

    y = Line(window.tryHead, y)
    y = Line(window.tryNote, y, GAP * 2)

    window.profileLabel:ClearAllPoints()
    Place(window.profileLabel, 0, y + 6)
    window.profiles:ClearAllPoints()
    window.profiles:SetPoint("LEFT", window.profileLabel, "RIGHT", GAP, 0)
    window.profiles:GenerateMenu()
    y = Line(window.later, y + LINE + GAP * 2, 0)
    window:SetHeight(y + EDGE)
    shell:SetHeight(y + EDGE)
end

-- the controls go where they are looked at: the window (no parent named) or a page
local function Seat(page)
    ns.Start()
    if not window then Build() end
    -- the bars are looked for anew: one may have come or gone
    ns.Layers.Apply(false, true)
    local parent = page or shell
    window:SetParent(parent)
    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", parent, "TOPLEFT")
    window:Show()
end

function UI.Open()
    if InCombatLockdown() then return ns.Say(TEXT.fight) end
    Seat()
    shell:Show()
    UI.Refresh()
end

-- on the addon's page in the game's options
function UI.Dock(page)
    Seat(page)
    shell:Hide()
    UI.Refresh()
end

function UI.Shown() return shell ~= nil and shell:IsShown() end

function UI.Close()
    UI.EndCapture()
    if shell then shell:Hide() end
end

function UI.Toggle()
    if UI.Shown() then return UI.Close() end
    UI.Open()
end

-- for the tests and the dev addon: the window and its rows
function UI.Parts() return window, rows end

ns.OnStart(function()
    Profiles.OnChange(function() UI.Refresh() end)
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:SetScript("OnEvent", UI.Close)
    -- once per account: the window is where everything starts
    if not ns.db.welcomed then
        C_Timer.After(2, function()
            if ns.db.welcomed then return end
            if InCombatLockdown() then return ns.Say(TEXT.welcome) end
            ns.db.welcomed = true
            UI.Open()
        end)
    end
end)

function FallensModifierKeys_OnAddonCompartmentClick() UI.Toggle() end

SLASH_FALLENSMODIFIERKEYS1 = "/fmk"
SLASH_FALLENSMODIFIERKEYS2 = "/modkeys"
SlashCmdList.FALLENSMODIFIERKEYS = function() UI.Toggle() end
