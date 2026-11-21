-- Profile rules, no client: lua tools/tests/profiles_test.lua (run from the addon's folder).
local fails = 0
local function check(ok, what)
    if ok then
        print("  ok   " .. what)
    else
        fails = fails + 1
        print("  FAIL " .. what)
    end
end

local saved = {}
local busy = false
-- a login: the module is loaded anew over the same saved table
local function login(id, name, class)
    local ns = {}
    assert(loadfile("Core/Profiles.lua"))("FallensModifierKeys", ns)
    ns.Profiles.Busy = function() return busy end
    ns.Profiles.Load(saved, { id = id, name = name, realm = "Realm", class = class })
    return ns.Profiles
end
local function count(P) return #P.Data().holds end
local function add(P, id) P.Data().holds[#P.Data().holds + 1] = { key = "F" .. id, lines = {}, binds = {} } end
local function names(P)
    local out = {}
    for i, entry in ipairs(P.Names()) do out[i] = entry.name .. (entry.made and "" or "?") end
    return table.concat(out, ", ")
end

print("a new character")
local lock = login("G1", "Fallen Guard", "Warlock")
check(lock.Active() == "Fallen Guard - Realm", "starts on a profile of its own: " .. lock.Active())
check(names(lock) == "Fallen Guard - Realm, Warlock?, Default?", "is offered its own, its class's and everyone's: " .. names(lock))
add(lock, 688)
add(lock, 697)

print("a second character")
local druid = login("G2", "Fallen Naturalist", "Druid")
check(druid.Active() == "Fallen Naturalist - Realm" and count(druid) == 0, "gets none of the first one's hold keys")
add(druid, 774)
check(names(druid) == "Fallen Naturalist - Realm, Druid?, Default?, Fallen Guard - Realm",
    "sees the first one's profile in its list: " .. names(druid))

print("two characters with one first name")
local twin = login("G3", "Fallen", "Mage")
local twin2 = login("G4", "Fallen", "Mage")
check(twin.Active() == twin2.Active(), "share the name of their own profile, as their names are the same")
lock = login("G1", "Fallen Guard", "Warlock")
check(count(lock) == 2, "the first still has its two after the others logged in")

print("the class profile")
local fired = 0
lock.OnChange(function() fired = fired + 1 end)
check(lock.Use("Warlock") and lock.Active() == "Warlock" and count(lock) == 2, "first picked, it starts as the one in use")
check(fired == 1, "a switch tells the listeners")
add(lock, 5782)
check(count(lock) == 3, "a hold key added on it")
lock.Use("Fallen Guard - Realm")
check(count(lock) == 2, "the copy it came from did not change")
lock.Use("Warlock")
local lock2 = login("G5", "Fallen Soul", "Warlock")
check(count(lock2) == 0 and lock2.Active() == "Fallen Soul - Realm", "another warlock starts on its own, empty")
lock2.Use("Warlock")
check(count(lock2) == 3, "and on the class profile sees the class's three")
check(table.concat(lock2.Users("Warlock"), ", ") == "Fallen Guard, Fallen Soul", "both are listed as on it")
druid = login("G2", "Fallen Naturalist", "Druid")
check(names(druid):find("Druid?", 1, true) and druid.Kind("Warlock") == nil, "to a druid it is one more named profile")

print("everyone's profile")
druid.Use("Default")
check(druid.Active() == "Default" and count(druid) == 1, "first picked by the druid, it starts as the druid's")
lock = login("G1", "Fallen Guard", "Warlock")
check(lock.Active() == "Warlock", "the pick is remembered per character")
lock.Use("Default")
check(count(lock) == 1, "the warlock on it sees what the druid put there")
lock.Use("Warlock")

print("names")
check(lock.New("  ") == nil and lock.New(("x"):rep(33)) == nil, "an empty or overlong name is refused")
check(lock.New("default") == nil and lock.New("WARLOCK") == nil, "so is one that exists, whatever its capitals")
check(lock.New("Raid", true) == "Raid" and lock.Active() == "Raid" and count(lock) == 3, "a copy starts as the one in use")
check(lock.New("Solo") == "Solo" and count(lock) == 0, "a new one starts empty")

print("rename")
check(lock.Rename("Warlock", "W") == nil and lock.Rename("Default", "D") == nil, "the three keep their names")
lock2 = login("G5", "Fallen Soul", "Warlock")
lock2.Use("Raid")
check(lock2.Rename("Raid", "Raiding") == "Raiding" and lock2.Active() == "Raiding", "a named one is renamed in use")
lock.Use("Raid")
lock = login("G1", "Fallen Guard", "Warlock")
check(lock.Active() == "Solo", "a character keeps the profile it was on")
saved.chars.G1.profile = "Raid"
lock = login("G1", "Fallen Guard", "Warlock")
check(lock.Active() == "Raiding" and count(lock) == 3, "one left on the old name follows it at login")

print("copy from, reset, delete")
lock.Use("Solo")
check(lock.CopyFrom("Raiding") and count(lock) == 3, "copy from fills the one in use")
add(lock, 1)
lock.Use("Raiding")
check(count(lock) == 3, "and the two stay apart")
lock.Use("Solo")
check(lock.Reset() and count(lock) == 0 and lock.Active() == "Solo", "reset empties the one in use")
check(lock.Delete("Fallen Guard - Realm") == false, "a character's own profile is not deleted")
check(lock.Delete("Solo") and lock.Active() == "Fallen Guard - Realm" and count(lock) == 2,
    "deleting the one in use puts the character on its own")
check(lock.Delete("Raiding") and not names(lock):find("Raiding", 1, true), "deleting another removes it")
lock2 = login("G5", "Fallen Soul", "Warlock")
check(lock2.Active() == "Fallen Soul - Realm", "a character whose profile was deleted is back on its own")

print("in a fight")
busy = true
check(lock.Use("Warlock") == false and lock.Active() == "Fallen Guard - Realm", "no switch")
check(lock.New("Mid") == nil and lock.Reset() == false and lock.Delete("Warlock") == false
    and lock.CopyFrom("Warlock") == false and lock.Rename("Warlock", "X") == nil, "and no other change")
busy = false

print("damaged data")
saved.profiles.Broken = "text"
saved.profiles.Half = {}
saved.chars.G1.profile = "Half"
lock = login("G1", "Fallen Guard", "Warlock")
check(saved.profiles.Broken == nil and saved.profiles.Half == nil, "a damaged profile is dropped")
check(lock.Active() == "Fallen Guard - Realm" and count(lock) == 2, "and its character is back on its own")
saved.profiles, saved.chars, saved.moved = nil, 5, nil
lock = login("G1", "Fallen Guard", "Warlock")
check(lock.Active() == "Fallen Guard - Realm" and count(lock) == 0, "wiped containers are made again")

print("a client that gives no realm")
local function bare(id, name, class)
    local ns = {}
    assert(loadfile("Core/Profiles.lua"))("FallensModifierKeys", ns)
    ns.Profiles.Load(saved, { id = id, name = name, class = class })
    return ns.Profiles
end
saved.profiles["Fallen Naturalist - "] = { holds = { { key = "Z" } }, keys = {} }
saved.chars.G9 = { profile = "Fallen Naturalist - " }
local plain = bare("G9", "Fallen Naturalist", "Druid")
check(plain.Own() == "Fallen Naturalist" and plain.Active() == "Fallen Naturalist", "its own profile is the name alone")
check(count(plain) == 1 and saved.profiles["Fallen Naturalist - "] == nil and plain.Kind(plain.Active()) == "own",
    "one saved with a dangling dash is carried over, hold keys and all")
plain = bare("G9", "Fallen Naturalist", "Druid")
check(plain.Active() == "Fallen Naturalist" and count(plain) == 1, "and stays so on the next login")

print(fails == 0 and "PROFILES: PASS" or ("PROFILES: FAIL (" .. fails .. ")"))
os.exit(fails == 0 and 0 or 1)
