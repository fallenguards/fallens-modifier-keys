local _, ns = ...
-- luacheck: read globals CreateFrame Minimap UIParent Settings GetCursorPosition GameTooltip GetMinimapShape

-- The other ways in to the setup: a button on the minimap and the addon's
-- page in the game's options. /fmk is in UI/Window.lua.
local A = {}
ns.Access = A
local Window = ns.Window

local TITLE = ns.TITLE
local TEXT = {
    tip = "Click to set up your modifier keys. Drag to move this button.",
}
A.TEXT = TEXT
-- the game's own minimap button art: the ring, the dark disc under the icon, the highlight
local RING, DISC, GLOW = 136430, 136467, 136477
-- the key of the addon's logo, by itself: the whole logo is too small to read at this size
local ICON = "Interface\\AddOns\\FallensModifierKeys\\media\\key"
-- where it starts, in degrees around the minimap; how far past the edge it sits
local START, OUT = 215, 5

local atan2 = math.atan2 or math.atan

local button

local function Place()
    local angle = math.rad(ns.db.minimap or START)
    local x, y = math.cos(angle), math.sin(angle)
    local w, h = Minimap:GetWidth() / 2 + OUT, Minimap:GetHeight() / 2 + OUT
    -- a minimap another addon made square: the button runs along its edge
    if GetMinimapShape and GetMinimapShape() ~= "ROUND" then
        local reach = math.sqrt(2)
        x, y = math.max(-w, math.min(x * w * reach, w)), math.max(-h, math.min(y * h * reach, h))
    else
        x, y = x * w, y * h
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- while it is dragged it follows the mouse around the minimap
local function Follow()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    ns.db.minimap = math.deg(atan2(py / scale - my, px / scale - mx)) % 360
    Place()
end

function A.Button()
    if button or not Minimap then return button end
    button = CreateFrame("Button", "FallensModifierKeysMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture(GLOW)
    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetSize(50, 50)
    ring:SetTexture(RING)
    ring:SetPoint("TOPLEFT", button, "TOPLEFT")
    local disc = button:CreateTexture(nil, "BACKGROUND")
    disc:SetSize(24, 24)
    disc:SetTexture(DISC)
    disc:SetPoint("CENTER", button, "CENTER")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture(ICON)
    icon:SetPoint("CENTER", button, "CENTER")
    button:SetScript("OnClick", function() Window.Toggle() end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", Follow) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(TITLE)
        GameTooltip:AddLine(TEXT.tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Place()
    return button
end

-- The page in the game's options, under AddOns: the same setup, seated on
-- the page while it is looked at.
local page = CreateFrame("Frame")
page:Hide()
local head = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
head:SetPoint("TOPLEFT", page, "TOPLEFT", 18, -16)
head:SetText(TITLE)
page:SetScript("OnShow", function(self) Window.Dock(self) end)
A.page = page
if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(page, TITLE)
    Settings.RegisterAddOnCategory(category)
    A.category = category
end

ns.OnStart(A.Button)
