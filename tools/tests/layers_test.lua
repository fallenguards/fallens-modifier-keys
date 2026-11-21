-- The addon alone in the fake client: lua tools/tests/run.lua tools/tests/layers_test.lua [captured|relookup]
-- luacheck: ignore
local HOLD1 = "CLICK FallensModifierKeysHold1:LeftButton"
local function does(key) return GetBindingAction(key, true) end
local function held() return NS.Layers.Held() end
local function litCount()
    local n = 0
    for _ in pairs(NS.Show.Lit()) do n = n + 1 end
    return n
end

print("== the game's bars, nothing set up (" .. MODEL .. ")")
boot()
flush(4)
check(NS.Profiles.Data().keys.bar == "ActionButton", "the action keys start as those of the bar with the most keys")
check(does("3") == "ACTIONBUTTON3", "with no hold key every key is the game's")
tap("3")
check(cast() == 3, "3 casts the main bar's third")

print("== one hold key")
local M = NS.Model
check(M.AddHold("z") == 1, "Z becomes a hold key")
check(NS.Profiles.Data().holds[1].lines[1].to == "MultiBarBottomLeftButton", "it points at the first other bar in view")
check(does("Z") == HOLD1, "Z is bound to its hold button")
local second, third = _G.MultiBarBottomLeftButton2.HotKey, _G.MultiBarBottomLeftButton3.HotKey
check(second:GetText() == "F" and second:IsShown() and not third:IsShown(),
    "not held: the second bar's buttons show their own keys, or none")
check(does("3") == "ACTIONBUTTON3", "not held: 3 is still the main bar's")
local casts = #W.casts
tap("Z")
check(#W.casts == casts and held() == nil, "a tap of the hold key casts nothing and leaves nothing held")
press("Z")
check(held() == 1, "held: the layer is on")
check(does("3") == "MULTIACTIONBAR1BUTTON3", "held: 3 is the second bar's third")
check(does("SHIFT-1") == "MULTIACTIONBAR1BUTTON7", "held: a key with Shift follows too")
check(does("Z") == HOLD1, "held: the hold key stays its own")
check(NS.Show.Lit().MultiBarBottomLeftButton3 == "3", "held: the bar's third is lit and shows 3")
check(NS.Show.Lit().ActionButton3 == nil, "held: the main bar is not lit")
check(second:GetText() == "2" and third:GetText() == "3" and third:IsShown(),
    "held: each button's own key text reads its new key, after the game wrote its own again")
check(_G.ActionButton3.HotKey:GetText() == "3", "held: the main bar's key text is left alone")
press("3")
check(cast() == 63, "held: 3 casts the second bar's third")
release("3")
release("Z")
check(held() == nil and does("3") == "ACTIONBUTTON3", "let go: 3 is the main bar's again")
check(litCount() == 0, "let go: nothing is lit")
check(second:GetText() == "F" and second:IsShown() and not third:IsShown(),
    "let go: the buttons show their own keys again, or none")
tap("3")
check(cast() == 3, "let go: 3 casts the main bar's third")
check(M.Sentence(1) == "1 2 3 4 5 6 SHIFT-1 press Action Bar 2.", "its line reads: " .. M.Sentence(1))

print("== in a fight")
W.combat = true
press("Z")
press("4")
check(cast() == 64, "a fight: held, 4 casts the second bar's fourth")
release("4")
release("Z")
tap("4")
check(cast() == 4, "a fight: let go, 4 casts the main bar's fourth")
press("Z")
press("5")
release("Z")
release("5")
check(held() == nil and does("5") == "ACTIONBUTTON5", "a fight: the hold key let go first leaves every key its own")
tap("5")
check(cast() == 5, "a fight: and 5 casts the main bar's fifth")
local added, why = M.AddHold("X")
check(added == nil and why == M.TEXT.fight, "a fight: no hold key is added, and it says why")
W.combat = false
fire("PLAYER_REGEN_ENABLED")

print("== two hold keys")
check(M.AddHold("X") == 2, "X becomes the second")
check(NS.Profiles.Data().holds[2].lines[1].to == "MultiBarBottomRightButton", "it points at the next bar")
press("Z")
press("X")
check(held() == 2 and does("3") == "MULTIACTIONBAR2BUTTON3", "both down: the last pressed counts")
release("X")
check(held() == 1 and does("3") == "MULTIACTIONBAR1BUTTON3", "the last let go: the first counts again")
press("X")
release("Z")
check(held() == 2 and does("3") == "MULTIACTIONBAR2BUTTON3", "the first let go: the last still counts")
release("X")
check(held() == nil and does("3") == "ACTIONBUTTON3", "both let go: every key its own")
check(select(2, M.AddHold("Z")) == M.TEXT.taken:format("Z"), "a hold key is not added twice")
check(select(2, M.AddHold("SHIFT-Q")) == M.TEXT.combo, "a key with Shift is refused")
check(select(2, M.AddHold("ESCAPE")) == M.TEXT.noKey, "Escape is refused")

print("== a bar switched in place")
check(M.SetLine(2, 1, "ActionButton", "MultiBarRightButton") == true, "X: the main bar shows the fourth bar")
check(_G.ActionButton3.action == 3, "not held: the main bar's third holds its own")
press("X")
check(_G.ActionButton3.action == 27, "held: the main bar's third holds the fourth bar's third")
check(does("3") == "ACTIONBUTTON3", "held: its key is the same key")
check(NS.Show.Lit().ActionButton3 == false, "held: it is lit, with no key of ours on it")
press("3")
check(cast() == 27, "held: 3 casts it")
release("3")
release("X")
check(_G.ActionButton3.action == 3, "let go: the main bar's third holds its own again")
W.combat = true
press("X")
check(_G.ActionButton12.action == 36, "a fight: held, the whole bar is switched")
release("X")
check(_G.ActionButton12.action == 12, "a fight: let go, it is back")
W.combat = false
check(M.SetLine(2, 1, "ActionButton", "MultiBarLeftButton") == true, "X: the main bar shows a bar that is turned off")
press("X")
check(_G.ActionButton2.action == 38, "held: it shows that bar's actions")
press("Z")
check(_G.ActionButton2.action == 2 and does("2") == "MULTIACTIONBAR1BUTTON2", "the other hold key pressed: the bar is back, the keys go to its bar")
release("Z")
check(_G.ActionButton2.action == 38, "that one let go: switched again")
release("X")
check(_G.ActionButton2.action == 2, "let go: back")
check(M.AddLine(2) == true and M.SetLine(2, 2, "MultiBarBottomLeftButton", "MultiBarBottomRightButton") == true,
    "X: a second bar is switched by the same key")
press("X")
check(_G.ActionButton1.action == 37 and _G.MultiBarBottomLeftButton1.action == 49, "held: both bars are switched")
release("X")
check(_G.ActionButton1.action == 1 and _G.MultiBarBottomLeftButton1.action == 61, "let go: both are back")
check(M.RemoveLine(2, 2) == true, "the second line is taken off")

print("== a key of its own")
check(M.Bind(1, "t", "MultiBarRightButton5") == true, "Z: T is given to one button")
press("Z")
check(does("T") == "MULTIACTIONBAR3BUTTON5", "held: T is that button")
press("T")
check(cast() == 29, "held: T casts it")
release("T")
release("Z")
check(does("T") == "", "let go: T is nothing again")
check(M.Unbind(1, "T") == true, "the key is taken off")

print("== a hold key that was an action key")
check(M.AddHold("2") == 3, "2 becomes a hold key")
press("Z")
check(does("2") == "CLICK FallensModifierKeysHold3:LeftButton", "held: 2 is no action key")
check(does("3") == "MULTIACTIONBAR1BUTTON3", "held: the others still are")
release("Z")
check(M.RemoveHold(3) == true and does("2") == "ACTIONBUTTON2", "taken off, 2 is the main bar's again")

print("== a release the game never sent")
press("Z")
flush(0.25)
W.keyDown.Z, W.held.Z = nil, nil
flush(0.25)
check(held() == 1, "one look is not enough")
flush(0.25)
check(held() == nil and does("3") == "ACTIONBUTTON3", "the key reads up twice: the keys are put back")
press("Z")
check(does("3") == "MULTIACTIONBAR1BUTTON3" and #NS.Layers.Plan().holds[1].binds >= 7,
    "after that the hold key still sends every action key (" .. #NS.Layers.Plan().holds[1].binds .. " keys)")
release("Z")
W.combat = true
press("Z")
flush(0.25)
W.keyDown.Z, W.held.Z = nil, nil
flush(0.25)
flush(0.25)
check(held() == 1, "a fight: nothing can be put back from our side")
tap("Z")
check(held() == nil, "a fight: the next tap of the key puts it right")
W.combat = false

print("== the key menu changes a key")
flush(2)
SetBinding("G", "ACTIONBUTTON8")
flush(2)
press("Z")
check(does("G") == "MULTIACTIONBAR1BUTTON8", "a key newly set on the main bar is an action key")
release("Z")

print("== the bars are not searched on every press")
flush(6)
local walks = W.walks
for _ = 1, 5 do tap("Z") end
flush(2)
check(W.walks == walks, "five taps of a hold key walk no frames")

print("== keys of the player's own")
check(M.UseList() == true, "the action keys become a list")
check(table.concat(NS.Profiles.Data().keys.list, " ") == "1 2 3 4 5 6 SHIFT-1 G", "it starts as the bar's keys")
check(M.AddKey("q") == true, "Q is added")
check(select(2, M.AddKey("Z")) == M.TEXT.isHold:format("Z"), "a hold key is refused")
press("Z")
check(does("Q") == "MULTIACTIONBAR1BUTTON9", "held: Q is the ninth")
release("Z")
check(M.RemoveKey(9) == true, "Q is taken off")
check(M.UseBar("ActionButton") == true and NS.Profiles.Data().keys.list == nil, "back to the bar's keys")

print("== after a reload")
boot()
flush(4)
check(does("Z") == HOLD1, "the hold keys are bound again")
press("Z")
press("1")
check(cast() == 61, "and work")
release("1")
release("Z")
check(#W.errors == 0, "no error line was shown")

print("== a login in a fight")
boot()
W.combat = true
fire("PLAYER_REGEN_DISABLED")
flush(4)
W.combat = false
fire("PLAYER_REGEN_ENABLED")
flush(1)
check(does("Z") == HOLD1, "the hold keys are bound")

print("== another character")
char = { guid = "Player-1-0000000B", class = "DRUID", name = "Tester B" }
boot()
flush(4)
check(#NS.Profiles.Data().holds == 0 and does("Z") == "TOGGLESHEATH", "it has no hold keys of the first")
check(NS.Profiles.Use("Tester A") == true, "it takes the first one's profile")
flush(1)
check(does("Z") == HOLD1, "and its hold keys")
char = { guid = "Player-1-0000000A", class = "MAGE", name = "Tester A" }

print("== bars of their own buttons")
barWorld = "own"
FallensModifierKeysDB = nil
boot()
flush(4)
M = NS.Model
check(NS.Profiles.Data().keys.bar == "@OwnBar1", "the action keys start as those of the bar in use")
check(M.AddHold("Z") == 1 and NS.Profiles.Data().holds[1].lines[1].to == "@OwnBar2", "Z points at the other bar")
press("Z")
check(does("3") == "CLICK OwnBarButton7:Keybind", "held: 3 clicks the other bar's third as its own bar's keys click theirs")
press("3")
check(cast() == 15, "held: 3 casts it")
release("3")
release("Z")
tap("3")
check(cast() == 3, "let go: 3 casts its own")
check(M.SetLine(1, 1, "@OwnBar1", "@OwnBar2") == true, "Z: the first bar shows the second")
press("Z")
check(_G.OwnBarButton2.action == 14, "held: its second holds the other's")
release("Z")
check(_G.OwnBarButton2.action == 2, "let go: its own")

print("== bars whose keys go through a helper")
barWorld = "helper"
FallensModifierKeysDB = nil
boot()
flush(4)
M = NS.Model
check(M.AddHold("Z") == 1, "Z is a hold key")
NS.Profiles.Data().keys.bar, NS.Profiles.Data().keys.list = nil, { "Q", "E", "R" }
check(M.SetLine(1, 1, "keys", "@SideBarFrame2") == true, "Z: Q E R press the side bar")
press("Z")
check(does("Q") == "CLICK SideBarButton1Hotkey:HOTKEY", "held: Q clicks the first as its own key does")
check(does("R") == "CLICK SideBarButton3Hotkey:HOTKEY", "held: R clicks a button with no key of its own the same way")
press("R")
check(cast() == 123, "held: R casts it")
release("R")
release("Z")
barWorld = "game"

print(fails == 0 and "LAYERS TEST: PASS" or ("LAYERS TEST: FAIL (" .. fails .. ")"))
os.exit(fails == 0 and 0 or 1)
