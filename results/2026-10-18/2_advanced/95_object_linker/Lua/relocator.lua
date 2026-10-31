local R = {}
R.types = { "ABS32", "REL32", "ABS16", "HI16", "LO16", "GPREL16", "CALL24" }
R.widths = { ABS32 = 4, REL32 = 4, ABS16 = 2, HI16 = 2, LO16 = 2, GPREL16 = 2, CALL24 = 3 }
local ranges = { ABS32 = { -2147483648, 4294967296 }, REL32 = { -2147483648, 2147483648 },
    ABS16 = { -32768, 65536 }, HI16 = { -2147483648, 4294967296 }, GPREL16 = { -32768, 32768 }, CALL24 = { -33554432, 33554432 } }
function R.unpaired(relocations, index)
    local current, following = relocations[index], relocations[index + 1]
    return current.type == "HI16" and (not following or following.type ~= "LO16" or following.symbol ~= current.symbol or following.addend ~= current.addend)
end
function R.calculate(kind, symbol, addend, place, gp)
    local value = symbol + addend
    if kind == "REL32" or kind == "CALL24" then value = value - place elseif kind == "GPREL16" then value = value - gp end
    local field
    if kind == "HI16" then field = ((value % 4294967296 + 32768) // 65536) % 65536
    elseif kind == "CALL24" then field = (value // 4) % 16777216
    else field = value % (1 << (8 * R.widths[kind])) end
    local range = ranges[kind]
    return value, field, not range or (range[1] <= value and value < range[2])
end
return R
