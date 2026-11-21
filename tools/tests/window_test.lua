-- The setup window in the fake client: lua tools/tests/run.lua tools/tests/window_test.lua
-- luacheck: ignore
local function parts() return NS.Window.Parts() end
local function clickOn(button, mouse) button.scripts.OnClick(button, mouse or "LeftButton") end
local function typeKey(key) W.focus.scripts.OnKeyDown(W.focus, key) end
local function pick(drop, label)
    for _, row in ipairs(drop.rows) do
        if row.label == label then row.pick() return true end
    end
    return false
end
local function has(drop, label)
    for _, row in ipairs(drop.rows) do
        if row.label == label then return true end
    end
    return false
end

print("== the first login")
boot()
check(parts() == nil, "nothing is built at login")
flush(3)
local window, rows = parts()
check(window ~= nil and window:IsShown(), "the window opens by itself")
check(FallensModifierKeysDB.welcomed == true, "and that is remembered")
check(window.keysDrop.Text:GetText() == "The keys of Action Bar 1", "the action keys read: " .. tostring(window.keysDrop.Text:GetText()))
check(#window.boxes == 12 and window.boxes[1]:GetText() == "1" and window.boxes[7]:GetText() == "SHIFT-1"
    and window.boxes[8]:GetText() == "", "twelve boxes show its keys, one per button: box 7 reads " .. tostring(window.boxes[7]:GetText()))
check(has(window.keysDrop, "The keys of Action Bar 5 (hidden)"), "a bar that is off is marked hidden")
check(window.h and window.h > 200, "the window has a height")

print("== a hold key by pressing it")
clickOn(window.addHold)
check(W.focus ~= nil and window.addHold:GetText() == NS.Window.TEXT.press, "Add a hold key waits for a key")
check(window.holdsWait:IsShown() and not window.holdsWarn:IsShown(), "while it waits, the line says what to press")
typeKey("LSHIFT")
check(#NS.Profiles.Data().holds == 0 and W.focus ~= nil, "Shift alone is refused and it still waits")
typeKey("Z")
check(#NS.Profiles.Data().holds == 1 and NS.Profiles.Data().holds[1].key == "Z", "Z is the hold key")
check(W.focus == nil and window.addHold:GetText() == NS.Window.TEXT.addHold, "the wait is over")
local row = rows[1]
check(row.key:IsShown() and row.key:GetText() == "Z", "its row shows the key")
check(row.what.Text:GetText() == "Action keys press", "what changes: " .. tostring(row.what.Text:GetText()))
check(row.to.Text:GetText() == "Action Bar 2", "the bar: " .. tostring(row.to.Text:GetText()))
check(row.note:GetText() == "1 2 3 4 5 6 SHIFT-1 press Action Bar 2.", "the line under it: " .. tostring(row.note:GetText()))
check(window.holdsWarn:IsShown() and window.holdsWarn:GetText() == NS.Window.TEXT.holdsWarn and not window.holdsWait:IsShown(),
    "the warning stands under the heading again")
press("Z")
press("2")
check(cast() == 62, "and the key works with the window open")
release("2")
release("Z")

print("== a mouse button as a hold key")
clickOn(window.addHold)
clickOn(window.addHold, "Button4")
check(#NS.Profiles.Data().holds == 2 and NS.Profiles.Data().holds[2].key == "BUTTON4", "mouse button 4 is the second")
clickOn(window.addHold)
typeKey("ESCAPE")
check(#NS.Profiles.Data().holds == 2 and W.focus == nil, "Escape ends a wait and adds nothing")

print("== the drop downs")
check(pick(rows[2].to, "Action Bar 4"), "the second key is pointed at Action Bar 4")
check(NS.Profiles.Data().holds[2].lines[1].to == "MultiBarRightButton" and rows[2].to.Text:GetText() == "Action Bar 4",
    "and it is")
check(pick(rows[1].what, "Action Bar 1 shows"), "the first key is set to switch the main bar in place")
check(NS.Profiles.Data().holds[1].lines[1].what == "ActionButton", "and it is")
check(rows[1].note:GetText():find("Action Bar 1 shows Action Bar 2.", 1, true) == 1, "its line reads: " .. rows[1].note:GetText())
press("Z")
check(_G.ActionButton4.action == 64, "held: the main bar shows the second bar")
release("Z")
clickOn(rows[1].more)
check(#NS.Profiles.Data().holds[1].lines == 2 and rows[2].i == 1 and rows[2].j == 2 and not rows[2].key:IsShown(),
    "plus gives the key a second line, with no key button of its own")
check(rows[3].i == 2 and rows[3].key:GetText() == "BUTTON4", "the second key moved down a row")
clickOn(rows[2].less)
check(#NS.Profiles.Data().holds[1].lines == 1 and rows[2].i == 2, "minus takes the line off")
clickOn(rows[2].less)
check(#NS.Profiles.Data().holds == 1 and not rows[2].key:IsShown(), "minus on a key's only line takes the key off")

print("== a key changed in place")
clickOn(rows[1].key)
check(rows[1].key:GetText() == NS.Window.TEXT.press, "a click on the key waits for a new one")
typeKey("X")
check(NS.Profiles.Data().holds[1].key == "X" and rows[1].key:GetText() == "X", "X it is")
check(GetBindingAction("Z", true) == "TOGGLESHEATH", "Z does what it did before")

print("== a key box")
local list
clickOn(window.boxes[8])
check(W.focus ~= nil and window.boxes[8]:GetText() == NS.Window.TEXT.waiting, "a click on box 8 waits for its key")
check(window.keysNote:GetText() == NS.Window.TEXT.waitSpot:format(8), "the note says what to press")
typeKey("LSHIFT")
check(W.focus ~= nil and list == nil, "Shift alone is nothing and it still waits; the bar's keys are still in use")
typeKey("Q")
list = NS.Profiles.Data().keys.list
check(list ~= nil and window.keysDrop.Text:GetText() == "Custom key list", "a key set: the bar's keys became a custom list")
check(list[8] == "Q" and window.boxes[8]:GetText() == "Q" and W.focus == nil, "Q is the key of box 8, and the wait is over")
check(window.keysNote:GetText() == NS.Window.TEXT.keysNote, "the note reads as before")
check(window.boxes[1]:GetText() == "1" and window.boxes[9]:GetText() == "", "the other boxes are as they were")
clickOn(window.boxes[2])
typeKey("Q")
check(list[2] == "Q" and list[8] == false and window.boxes[8]:GetText() == "", "Q given to box 2 leaves box 8")
clickOn(window.boxes[2], "RightButton")
check(list[2] == false and window.boxes[2]:GetText() == "", "a right-click empties a box")
clickOn(window.boxes[5])
typeKey("BACKSPACE")
check(list[5] == false and W.focus == nil, "Backspace empties the waiting box")
clickOn(window.boxes[5])
clickOn(window.boxes[5], "Button5")
check(list[5] == "BUTTON5", "a mouse button clicked on the waiting box is its key")
clickOn(window.boxes[6])
typeKey("ESCAPE")
check(list[6] == "6" and W.focus == nil, "Escape leaves a box as it was")
clickOn(window.boxes[3])
typeKey("X")
check(list[3] == "3" and W.focus ~= nil and W.errors[#W.errors] == NS.Model.TEXT.isHold:format("X"),
    "a hold key is refused, in red, and it still waits")
typeKey("ESCAPE")

print("== held or tapped, for each key")
check(rows[1].mode:IsShown() and rows[1].mode.Text:GetText() == "Hold", "a key starts as held")
check(pick(rows[1].mode, "Tap") and NS.Model.Tap(1) == true and rows[1].mode.Text:GetText() == "Tap", "its drop down sets it to a tap")
clickOn(window.boxes[3])
typeKey("X")
check(list[3] == "X", "a tapped key can be an action key too")
check(pick(rows[1].mode, "Hold") and NS.Model.Tap(1) == false, "and back to held")
W.errors = {}

print("== a fight")
W.combat = true
fire("PLAYER_REGEN_DISABLED")
check(not window:IsShown(), "the window shuts")
NS.Window.Open()
check(not window:IsShown() and W.chat[#W.chat]:find(NS.Window.TEXT.fight, 1, true), "and says why it will not open")
W.combat = false
fire("PLAYER_REGEN_ENABLED")
SlashCmdList.FALLENSMODIFIERKEYS("")
check(window:IsShown(), "/fmk opens it after the fight")

print("== the next login")
boot()
flush(3)
check(parts() == nil, "it does not open by itself again")
SlashCmdList.FALLENSMODIFIERKEYS("")
window, rows = parts()
check(window:IsShown() and rows[1].key:GetText() == "X", "/fmk opens it with the hold key in it")
check(#W.errors == 0, "no error line was shown")

print(fails == 0 and "WINDOW TEST: PASS" or ("WINDOW TEST: FAIL (" .. fails .. ")"))
os.exit(fails == 0 and 0 or 1)
