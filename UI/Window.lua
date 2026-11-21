local _, ns = ...
-- luacheck: globals SLASH_FALLENSMODIFIERKEYS1 SLASH_FALLENSMODIFIERKEYS2 SlashCmdList
-- luacheck: globals FallensModifierKeys_OnAddonCompartmentClick
-- luacheck: read globals CreateFrame UIParent InCombatLockdown C_Timer GetTime GameTooltip

-- The one window: the action keys, the hold keys, each on a line. /fmk opens
-- it, and it opens by itself the first time the addon is loaded.
local UI = {}
ns.Window = UI
local Model, Bars, Profiles = ns.Model, ns.Bars, ns.Profiles

local NAME, TITLE = "FallensModifierKeysWindow", "Fallen's Modifier Keys"
local WIDTH, EDGE, TOP, GAP, LINE = 480, 18, 34, 8, 24
local INSIDE = WIDTH - EDGE * 2
local KEY_W, WHAT_W, TO_W, SMALL_W, KEYS_W = 96, 140, 130, 24, 230
-- floors: a button grows to its text
local BUTTON_FLOOR, CHROME = 80, 24

local TEXT = {
    intro = "Hold a key and your action keys press another bar. Let go and they are your own again.",
    keysHead = "1. Your action keys",
    keysNote = "The keys you press abilities with.",
    keysOf = "The keys of %s",
    ownKeys = "My own keys",
    addKey = "Add a key",
    dropKey = "Remove last",
    noKeys = "No key yet.",
    holdsHead = "2. Your hold keys",
    holdsNote = "A key you hold down. It stops doing what it did before.",
    addHold = "Add a hold key",
    press = "Press a key",
    waitHold = "Press the key or mouse button to hold. Escape cancels.",
    waitKey = "Press the key to add. Escape cancels.",
    keysPress = "Action keys press",
    shows = "%s shows",
    hidden = "%s (hidden)",
    noMore = "It no longer does %s.",
    tryHead = "3. Try it",
    tryNote = "Hold a hold key now: the bar it uses lights up and shows your keys.",
    profile = "Profile",
    own = "%s (this character)",
    class = "%s (this class)",
    all = "%s (every character)",
    fight = "The window opens out of a fight.",
    welcome = "Type /fmk to set up your hold keys.",
    moreTip = "Switch one more bar with this key.",
    lessTip = "Take this line off.",
}
UI.TEXT = TEXT
-- mouse buttons a hold key can be, by the name a click gives them
local MOUSE = { MiddleButton = "BUTTON3" }
for n = 4, 31 do MOUSE["Button" .. n] = "BUTTON" .. n end
-- typed characters whose key has another name
local NAMED = { [" "] = "SPACE" }

local window, catcher, capture
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

-- a key is being waited for: fn(key) takes it
local function Capture(fn, note)
    capture = { fn = fn, note = note }
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
    if not capture then return end
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
    row.key = Push(TEXT.press, function(_, mouse)
        local taken = MOUSE[mouse]
        if capture and capture.row == row then
            if taken then UI.Pressed(taken) else UI.EndCapture() end
            return
        end
        if taken then return end
        local index = row.i
        Capture(function(key) return Model.SetHoldKey(index, key) end, TEXT.waitHold)
        capture.row = row
        UI.Refresh()
    end)
    row.key:RegisterForClicks("AnyUp")
    row.key:SetSize(KEY_W, LINE)
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
    window = CreateFrame("Frame", NAME, UIParent, "BasicFrameTemplateWithInset")
    window:Hide()
    window:SetWidth(WIDTH)
    window:SetPoint("LEFT", UIParent, "LEFT", 80, 80)
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    if window.TitleText then window.TitleText:SetText(TITLE) end
    window:SetScript("OnHide", function() UI.EndCapture() end)
    catcher = Catcher()

    window.intro = Text("GameFontHighlight", TEXT.intro)
    window.keysHead = Text("GameFontNormalLarge", TEXT.keysHead)
    window.keysNote = Text("GameFontHighlight", TEXT.keysNote)
    window.keysDrop = Drop(KEYS_W, FillKeys)
    window.addKey = Push(TEXT.addKey, function()
        if capture then return UI.EndCapture() end
        Capture(function(key)
            local ok, why = Model.AddKey(key)
            -- stays open: the next key is the next place
            if ok then return false end
            return false, why
        end, TEXT.waitKey)
    end)
    window.dropKey = Push(TEXT.dropKey, function()
        local list = Profiles.Data().keys.list
        if list then Warn(select(2, Model.RemoveKey(#list))) end
    end)
    window.keys = Text("GameFontNormal")
    window.holdsHead = Text("GameFontNormalLarge", TEXT.holdsHead)
    window.holdsNote = Text("GameFontHighlight", TEXT.holdsNote)
    -- while it waits, a mouse button clicked on it is the key
    window.addHold = Push(TEXT.addHold, function(_, mouse)
        local taken = MOUSE[mouse]
        if capture and capture.add then
            if taken then UI.Pressed(taken) else UI.EndCapture() end
            return
        end
        if taken then return end
        Capture(function(key) return Model.AddHold(key) end, TEXT.waitHold)
        capture.add = true
        UI.Refresh()
    end)
    window.addHold:RegisterForClicks("AnyUp")
    window.tryHead = Text("GameFontNormalLarge", TEXT.tryHead)
    window.tryNote = Text("GameFontHighlight", TEXT.tryNote)
    window.profileLabel = Text("GameFontNormal", TEXT.profile)
    window.profileLabel:SetWidth(0)
    window.profiles = Drop(KEYS_W, FillProfiles)

    Model.OnChange(UI.Refresh)
end

-- lays every piece out again from the profile in use
function UI.Refresh()
    if not (window and window:IsShown()) then return end
    local data = Profiles.Data()
    local y = Line(window.intro, TOP, GAP * 2)

    y = Line(window.keysHead, y)
    y = Line(window.keysNote, y)
    window.keysDrop:ClearAllPoints()
    Place(window.keysDrop, 0, y)
    window.keysDrop:GenerateMenu()
    local own = data.keys.list ~= nil
    window.addKey:SetShown(own)
    window.dropKey:SetShown(own)
    window.addKey:SetText(capture and not capture.row and not capture.add and TEXT.press or TEXT.addKey)
    Fit(window.addKey)
    window.addKey:ClearAllPoints()
    window.addKey:SetPoint("LEFT", window.keysDrop, "RIGHT", GAP, 0)
    window.dropKey:ClearAllPoints()
    window.dropKey:SetPoint("LEFT", window.addKey, "RIGHT", GAP / 2, 0)
    y = y + LINE + GAP
    local labels = Model.KeyLabels()
    window.keys:SetText(#labels > 0 and table.concat(labels, "   ") or TEXT.noKeys)
    y = Line(window.keys, y, GAP * 2)

    y = Line(window.holdsHead, y)
    window.holdsNote:SetText(capture and capture.note or TEXT.holdsNote)
    y = Line(window.holdsNote, y)
    local used = 0
    for i, hold in ipairs(data.holds) do
        for j in ipairs(hold.lines) do
            used = used + 1
            local row = Row(used, i, j)
            local first = j == 1
            row.key:SetShown(first)
            row.key:SetText(capture and capture.row == row and TEXT.press or Model.Label(hold.key))
            row.key:ClearAllPoints()
            Place(row.key, 0, y)
            row.what:ClearAllPoints()
            Place(row.what, KEY_W + GAP, y)
            row.what:Show()
            row.what:GenerateMenu()
            row.to:ClearAllPoints()
            row.to:SetPoint("LEFT", row.what, "RIGHT", GAP, 0)
            row.to:Show()
            row.to:GenerateMenu()
            row.less:ClearAllPoints()
            row.less:SetPoint("LEFT", row.to, "RIGHT", GAP, 0)
            row.less:Show()
            row.more:ClearAllPoints()
            row.more:SetPoint("LEFT", row.less, "RIGHT", 2, 0)
            row.more:SetShown(j == #hold.lines)
            y = y + LINE + GAP / 2
            if j == #hold.lines then
                local does = Model.Does(hold.key)
                row.note:SetText(Model.Sentence(i) .. (does and (" " .. TEXT.noMore:format(does)) or ""))
                y = Line(row.note, y, GAP * 1.5)
            else
                row.note:Hide()
            end
        end
    end
    for n = used + 1, #rows do
        local row = rows[n]
        row.key:Hide(); row.what:Hide(); row.to:Hide(); row.less:Hide(); row.more:Hide(); row.note:Hide()
    end
    window.addHold:SetText(capture and capture.add and TEXT.press or TEXT.addHold)
    Fit(window.addHold)
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
    window:SetHeight(y + LINE + EDGE)
end

function UI.Open()
    if InCombatLockdown() then return ns.Say(TEXT.fight) end
    ns.Start()
    if not window then Build() end
    -- the bars are looked for anew: one may have come or gone
    ns.Layers.Apply(false, true)
    window:Show()
    UI.Refresh()
end

function UI.Toggle()
    if window and window:IsShown() then return window:Hide() end
    UI.Open()
end

-- for the tests and the dev addon: the window and its rows
function UI.Parts() return window, rows end

ns.OnStart(function()
    Profiles.OnChange(function() UI.Refresh() end)
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:SetScript("OnEvent", function()
        if window then window:Hide() end
    end)
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
