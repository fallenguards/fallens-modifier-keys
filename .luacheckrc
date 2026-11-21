std = "lua51"
max_line_length = 120

-- the tests run under plain Lua with a fake client of their own
exclude_files = { "tools/**", "dev/**" }

ignore = {
    "122",  -- setting a field on a frame of the game's
}

globals = {
    "FallensModifierKeysDB",
    "FallensModifierKeys_AttachDevTools",
    "FallensModifierKeys_OnAddonCompartmentClick",
    "SlashCmdList",
    "SLASH_FALLENSMODIFIERKEYS1",
    "SLASH_FALLENSMODIFIERKEYS2",
}
