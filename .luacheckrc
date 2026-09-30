-- Luacheck configuration for SFUI

stds.wow = {
    globals = {
        "_",
        "sfui",
        "SfuiDB",
    },
    read_globals = {
        "LibStub",
    },
}

std = "lua51+wow"

exclude_files = {
    "Libs/**",
    "scratch/**",
    ".agent/**",
    ".release/**",
}

max_line_length = false
self = false

ignore = {
    "111",      -- Setting non-standard global variable
    "112",      -- Mutating non-standard global variable
    "113",      -- Accessing undefined variable (Blizzard API and frame globals)
    "142",      -- Setting undefined field of global
    "143",      -- Accessing undefined field of global
    "211",      -- Unused local variable
    "212",      -- Unused argument
    "213",      -- Unused loop variable
    "221",      -- Variable is never accessed
    "231",      -- Variable is never accessed / set but not read
    "311",      -- Value assigned to variable is unused
    "312",      -- Value of argument is modified but never used
    "313",      -- Value of loop variable is modified but never used
    "411",      -- Shadowing upvalue
    "412",      -- Shadowing variable
    "413",      -- Shadowing loop variable
    "421",      -- Shadowing upvalue
    "422",      -- Shadowing variable
    "431",      -- Shadowing upvalue
    "432",      -- Shadowing upvalue
    "542",      -- Empty loop body or if branch
    "611",      -- Line contains trailing whitespace
    "612",      -- Line contains only whitespace
    "613",      -- Trailing whitespace in string
    "614",      -- Trailing whitespace in comment
    "631",      -- Line too long
}
