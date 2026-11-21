-- Runs a test file in the fake client: lua tools/tests/run.lua <test.lua> [captured|relookup] [driver.lua]
-- The harness and the test are loaded as one chunk, so the test uses the harness's locals.
local test, model, driver = arg[1], arg[2] or "captured", arg[3]
local function read(path)
    local file = assert(io.open(path, "r"), "cannot open " .. tostring(path))
    local text = file:read("a")
    file:close()
    return text
end
local here = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local chunk = assert(load("local MODEL, DRIVER = ...\n" .. read(here .. "/harness.lua") .. "\n" .. read(test), "@" .. test))
chunk(model, driver)
