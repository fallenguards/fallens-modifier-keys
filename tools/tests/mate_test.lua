-- With Fallen's Flyouts beside it, as far as the two addons agreed. The other addon here is a stand-in that
-- keeps its side: lua tools/tests/run.lua tools/tests/mate_test.lua [captured|relookup]
-- luacheck: ignore
local fly
local function does(key) return GetBindingAction(key, true) end
local function root() return _G.FallensModifierKeysRoot end

-- Its side: a root with "open" and the open one's pick and close keys, an
-- opener per flyout as its host's child, the host's keys bound to it, and
-- the three calls. A hold key is left out of everything it binds.
preload = function()
    fly = { watchers = {}, hosts = {}, picks = { ["1"] = true, ["2"] = true, ["3"] = true }, changed = 0 }
    fly.root = CreateFrame("Frame", "FallensFlyoutsRoot", UIParent, "SecureHandlerBaseTemplate")
    function fly.host(name, f, key)
        fly.hosts[name] = f
        local opener = CreateFrame("Button", "FallensFlyoutsOpener" .. f, _G[name], "SecureActionButtonTemplate")
        opener.key, opener.live = key, true
        fly.bind()
    end
    -- Its lists, written out of a fight: each flyout's opener and opener keys, a hold key left out.
    function fly.list()
        if W.combat then return end
        local holds, units = {}, 0
        for _, key in ipairs(fly.provider and fly.provider.HoldKeys() or {}) do holds[key] = true end
        for _, f in pairs(fly.hosts) do units = math.max(units, f) end
        fly.root:SetAttribute("units", units)
        for f = 1, units do
            local opener = _G["FallensFlyoutsOpener" .. f]
            local key = opener and opener.live and opener.key
            fly.root:SetAttribute("opener" .. f, "FallensFlyoutsOpener" .. f)
            fly.root:SetAttribute("okeys" .. f, (key and not holds[key]) and 1 or 0)
            fly.root:SetAttribute("okey" .. f .. "_1", key)
            fly.root:SetAttribute("obtn" .. f .. "_1", key and (fly.picks[key] and "tap" or "LeftButton"))
        end
    end
    -- its BIND, from those lists: openers, then the open one's picks; never a key the held layer takes
    function fly.bind()
        fly.list()
        local was = W.secure
        W.secure = true
        fly.root:ClearBindings()
        local mine = _G.FallensModifierKeysRoot
        local layer = mine and mine:GetAttribute("layer")
        for f = 1, fly.root:GetAttribute("units") or 0 do
            if fly.root:GetAttribute("okeys" .. f) == 1 then
                local key = fly.root:GetAttribute("okey" .. f .. "_1")
                if not (layer and mine:GetAttribute("lkey" .. layer .. "_" .. key)) then
                    fly.root:SetBindingClick(true, key, fly.root:GetAttribute("opener" .. f),
                        fly.root:GetAttribute("obtn" .. f .. "_1"))
                end
            end
        end
        local holds = {}
        for _, key in ipairs(fly.provider and fly.provider.HoldKeys() or {}) do holds[key] = true end
        local open = fly.root:GetAttribute("open")
        for i = 1, open and fly.root:GetAttribute("pkeys" .. open) or 0 do
            local key = fly.root:GetAttribute("pkey" .. open .. "_" .. i)
            if not holds[key] then fly.root:SetBindingClick(true, key, "FallensFlyoutsEntry" .. open .. "_" .. i) end
        end
        W.secure = was
    end
    function fly.open(f)
        local was = W.secure
        W.secure = true
        fly.root:SetAttribute("open", f)
        if f then
            fly.root:SetAttribute("pkeys" .. f, 3)
            for i = 1, 3 do fly.root:SetAttribute("pkey" .. f .. "_" .. i, tostring(i)) end
            fly.root:SetAttribute("ckeys", 1)
            fly.root:SetAttribute("ckey1", "ESCAPE")
        end
        W.secure = was
        fly.bind()
    end
    function FallensFlyouts_KeyTarget(name, key)
        local f = fly.hosts[name]
        if not f then return nil end
        return "FallensFlyoutsOpener" .. f, fly.picks[key] and "tap" or "LeftButton"
    end
    function FallensFlyouts_Watch(fn) fly.watchers[#fly.watchers + 1] = fn end
    function FallensFlyouts_Layers(provider) fly.provider = provider end
    function FallensFlyouts_LayersChanged()
        fly.changed = fly.changed + 1
        fly.bind()
    end
    function fly.laid()
        for _, fn in ipairs(fly.watchers) do fn() end
    end
end

print("== the two addons meet (" .. MODEL .. ")")
boot()
flush(4)
local M = NS.Model
check(fly.provider ~= nil and #fly.watchers == 1, "this addon gave the other its hold keys and listens for its lays")
-- his own setup: a flyout on the main bar's first button (key 1) and on the second bar's fifth
fly.host("ActionButton1", 5, "1")
fly.host("MultiBarBottomLeftButton5", 3)
fly.laid()
check(does("1") == "CLICK FallensFlyoutsOpener5:tap", "1 opens the flyout on the main bar's first")

print("== a hold key that was a flyout's key")
local changed = fly.changed
check(M.AddHold("1") == 1, "1 becomes a hold key")
check(fly.changed == changed + 1, "the other addon is told once")
check(table.concat(fly.provider.HoldKeys(), " ") == "1", "and can read the hold keys")
check(does("1") == "CLICK FallensModifierKeysHold1:LeftButton", "1 is the hold key, no flyout's")
check(root():GetAttribute("frameref-flyouts") == fly.root, "this addon's secure code can read the other's root")
changed = fly.changed
M.SetLine(1, 1, "keys", "MultiBarBottomLeftButton")
check(fly.changed == changed, "a change that leaves the hold keys alone tells it nothing")

print("== a layer key sent to a button with a flyout")
press("1")
check(fly.provider.Held() == true, "held: the other addon can see a hold is down")
check(does("5") == "CLICK FallensFlyoutsOpener3:LeftButton", "held: 5 opens the flyout on the second bar's fifth")
check(does("4") == "MULTIACTIONBAR1BUTTON4", "held: 4 presses a button with no flyout as before")
check(root():GetAttribute("lkey1_5") == true and root():GetAttribute("lkey1_4") == true
    and root():GetAttribute("lkey1_1") == nil, "held: the layer's keys can be looked up by name")
-- the flyout opens: the other addon binds again, as it does on every open and shut
fly.open(3)
check(does("1") == "CLICK FallensModifierKeysHold1:LeftButton", "its flyout open: 1 is still the hold key")
check(does("2") == "CLICK FallensFlyoutsEntry3_2:LeftButton", "its flyout open: 2 picks from it")
check(does("4") == "MULTIACTIONBAR1BUTTON4", "its flyout open: 4 is still the second bar's fourth")
fly.open(nil)
check(does("2") == "MULTIACTIONBAR1BUTTON2", "its flyout shut: 2 is the second bar's second again")
release("1")
check(fly.provider.Held() == false and does("5") == "ACTIONBUTTON5", "let go: 5 is the main bar's fifth")

print("== a hold pressed while a flyout is open")
fly.open(3)
press("1")
check(does("2") == "CLICK FallensFlyoutsEntry3_2:LeftButton" and does("3") == "CLICK FallensFlyoutsEntry3_3:LeftButton",
    "its pick keys stay its own")
check(does("4") == "MULTIACTIONBAR1BUTTON4", "the other layer keys are bound")
check(does("ESCAPE") == "TOGGLEGAMEMENU", "nothing of this addon's is on its shut key")
release("1")
fly.open(nil)

print("== a flyout made or removed")
fly.host("MultiBarBottomLeftButton4", 2)
fly.laid()
press("1")
check(does("4") == "CLICK FallensFlyoutsOpener2:LeftButton", "a new flyout on the second bar's fourth: 4 opens it")
release("1")
fly.hosts.MultiBarBottomLeftButton4 = nil
_G.FallensFlyoutsOpener2.live = false
fly.laid()
press("1")
check(does("4") == "MULTIACTIONBAR1BUTTON4", "it is removed: 4 presses the button again")
release("1")
W.combat = true
fly.hosts.MultiBarBottomLeftButton5 = nil
fly.laid()
press("1")
check(does("5") == "CLICK FallensFlyoutsOpener3:LeftButton", "a fight: nothing is rebuilt")
release("1")
W.combat = false
fire("PLAYER_REGEN_ENABLED")
press("1")
check(does("5") == "MULTIACTIONBAR1BUTTON5", "after it: 5 presses the button")
release("1")

print("== a key with a flyout at home, sent elsewhere by the layer")
fly.host("ActionButton2", 6, "2")
fly.laid()
check(does("2") == "CLICK FallensFlyoutsOpener6:tap", "2 opens the flyout on the main bar's second")
W.combat = true
press("1")
check(does("2") == "MULTIACTIONBAR1BUTTON2", "held: 2 is the second bar's second, not its own flyout")
-- a flyout opens and shuts during the hold: the other addon binds again, twice, leaving 2 to the layer
fly.open(3)
fly.open(nil)
check(does("2") == "MULTIACTIONBAR1BUTTON2", "held, after a flyout was used: still so")
release("1")
check(does("2") == "CLICK FallensFlyoutsOpener6:tap", "let go, in a fight: 2 opens its own flyout again at once")
W.combat = false
fire("PLAYER_REGEN_ENABLED")

print("== a bar with a flyout switched in place")
check(M.SetLine(1, 1, "ActionButton", "MultiBarBottomLeftButton") == true, "1: the main bar shows the second bar")
press("1")
check(_G.ActionButton2.action == 62, "held: the main bar's second holds the second bar's")
check(does("2") == "ACTIONBUTTON2", "held: 2 presses it, its own flyout stays shut")
check(does("3") == "ACTIONBUTTON3", "held: a button with no flyout keeps its key as it is")
press("2")
check(cast() == 62, "held: 2 casts what the button shows")
release("2")
fly.bind()
check(does("2") == "ACTIONBUTTON2", "held, after the other addon binds again: still so")
release("1")
fly.bind()
check(does("2") == "CLICK FallensFlyoutsOpener6:tap" and _G.ActionButton2.action == 2, "let go: 2 opens its flyout again")

print("== a tapped key and a flyout")
check(M.SetLine(1, 1, "keys", "MultiBarBottomLeftButton") == true and M.SetTap(1, true) == true, "1 is set to a tap, its keys sent to the second bar")
tap("1")
local passed = does("4"):match("^CLICK (FallensModifierKeysKey%d+):LeftButton$")
check(passed ~= nil, "tapped: 4 goes through a button of this addon's")
-- a flyout made while the layer is on: taken in once the layer is over
fly.host("MultiBarBottomLeftButton4", 2)
fly.laid()
tap("ESCAPE")
flush(1)
tap("1")
passed = does("4"):match("^CLICK (FallensModifierKeysKey%d+):LeftButton$")
check(passed and _G[passed]:GetAttribute("macrotext") == "/click FallensFlyoutsOpener2 tap 1\n/click FallensFlyoutsOpener2 tap 0",
    "tapped, with a flyout on that button: the press is passed to its opener as a tap, down and up")
tap("ESCAPE")
check(NS.Layers.Held() == nil and M.SetTap(1, false) == true and M.SetLine(1, 1, "ActionButton", "MultiBarBottomLeftButton") == true,
    "Escape ends it; 1 is held again")

print("== the hold key is given up")
changed = fly.changed
check(M.RemoveHold(1) == true and fly.changed == changed + 1, "1 is no hold key: the other addon is told")
check(does("1") == "CLICK FallensFlyoutsOpener5:tap", "and 1 opens its flyout again")
check(#W.errors == 0, "no error line was shown")

print(fails == 0 and "MATE TEST: PASS" or ("MATE TEST: FAIL (" .. fails .. ")"))
os.exit(fails == 0 and 0 or 1)
