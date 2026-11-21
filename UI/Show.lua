local _, ns = ...
-- luacheck: read globals CreateFrame GetBindingText hooksecurefunc

-- While a hold key is down: the buttons it uses light up, and each one's
-- own key text reads the key that presses it now.
local S = {}
ns.Show = S

-- the game's own art: the glow of an open flyout's button, a bar button's mouseover ring
local GLOW, RING = "UI-HUD-ActionBar-IconFrame-FlyoutBorderShadow", "UI-HUD-ActionBar-IconFrame-Mouseover"
-- sizes on the game's 45 button; a button of another size scales them
local BAR_BUTTON, GLOW_OUT, KEY_X, KEY_Y = 45, 4, -5, -5

local pool, lit = {}, {}

-- a key as the bars write it: short
local function Short(key)
    local text = GetBindingText(key, 1)
    if type(text) ~= "string" or text == "" then return key end
    return text
end

-- The button's own key text is the one written on. The game writes it again
-- whenever bindings change, which every hold does: each write and each
-- show or hide of the game's is kept as what to put back, and ours goes
-- over it at once, so nothing flickers.
local function Take(entry, hotkey)
    entry.hotkey = hotkey
    entry.was, entry.wasShown = hotkey:GetText(), hotkey:IsShown()
    hooksecurefunc(hotkey, "SetText", function(_, text)
        if entry.ours or not entry.text then return end
        entry.was = text
        entry.ours = true
        hotkey:SetText(entry.text)
        entry.ours = false
    end)
    local function Seen()
        if entry.ours or not entry.text then return end
        entry.wasShown = hotkey:IsShown()
        entry.ours = true
        hotkey:Show()
        entry.ours = false
    end
    hooksecurefunc(hotkey, "Hide", Seen)
    hooksecurefunc(hotkey, "Show", Seen)
    hooksecurefunc(hotkey, "SetShown", Seen)
end

local function Entry(name)
    if pool[name] then return pool[name] end
    local button = _G[name]
    if type(button) ~= "table" or not button.GetFrameLevel then return nil end
    local size = (button:GetWidth() or BAR_BUTTON) / BAR_BUTTON
    local entry = {}
    local over = CreateFrame("Frame", nil, button)
    over:Hide()
    over:SetAllPoints(button)
    local glow = over:CreateTexture(nil, "BACKGROUND")
    glow:SetAtlas(GLOW)
    glow:SetPoint("TOPLEFT", over, "TOPLEFT", -GLOW_OUT * size, GLOW_OUT * size)
    glow:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", GLOW_OUT * size, -GLOW_OUT * size)
    local ring = over:CreateTexture(nil, "ARTWORK")
    ring:SetAtlas(RING)
    ring:SetAllPoints(over)
    entry.over = over
    local hotkey = button.HotKey
    if type(hotkey) == "table" and hotkey.SetText and hotkey.GetText then
        Take(entry, hotkey)
    else
        -- a button with no key text of its own gets one where the game's sits
        entry.own = over:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
        entry.own:SetPoint("TOPRIGHT", over, "TOPRIGHT", KEY_X * size, KEY_Y * size)
    end
    pool[name] = entry
    return entry
end

local function Write(entry, text)
    if entry.own then return entry.own:SetText(text) end
    local hotkey = entry.hotkey
    if text and not entry.text then entry.was, entry.wasShown = hotkey:GetText(), hotkey:IsShown() end
    entry.text = text
    entry.ours = true
    if text then
        hotkey:SetText(text)
        hotkey:Show()
    else
        hotkey:SetText(entry.was)
        hotkey:SetShown(entry.wasShown)
    end
    entry.ours = false
end

-- the buttons lit now, by name, each with the key written on it or false
function S.Lit()
    local out = {}
    for name, entry in pairs(lit) do out[name] = entry.label or false end
    return out
end

function S.Layer(held, plan)
    for name, entry in pairs(lit) do
        entry.over:Hide()
        if entry.label then Write(entry, nil) end
        entry.label = nil
        lit[name] = nil
    end
    -- nothing held: every button that can light gets its pieces now, out of a fight
    if not held then
        for _, hold in ipairs(plan and plan.holds or {}) do
            for _, piece in ipairs(hold.lit) do Entry(piece.button) end
        end
        return
    end
    local hold = plan and plan.holds[held]
    for _, piece in ipairs(hold and hold.lit or {}) do
        local entry = Entry(piece.button)
        if entry then
            entry.label = piece.key and Short(piece.key) or nil
            if entry.label then Write(entry, entry.label) end
            entry.over:Show()
            lit[piece.button] = entry
        end
    end
end

ns.Layers.OnLayer(S.Layer)
