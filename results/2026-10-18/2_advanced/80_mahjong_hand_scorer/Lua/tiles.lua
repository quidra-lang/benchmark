local tiles = {suits = 'mpsz', winds = 'ESWN', wind_tiles = {E = 27, S = 28, W = 29, N = 30},
    yaochuu_kinds = {0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33}, green = {[19] = true, [20] = true, [21] = true, [23] = true, [25] = true, [32] = true}}
function tiles.parse(text, allow_empty)
    if text == '-' then if allow_empty then return {} end; return nil end
    local result, digits = {}, {}
    for character in text:gmatch('.') do
        if character >= '0' and character <= '9' then digits[#digits + 1] = tonumber(character)
        else
            local suit = tiles.suits:find(character, 1, true)
            if not suit or #digits == 0 then return nil end
            suit = suit - 1
            for _, digit in ipairs(digits) do
                if suit == 3 and (digit < 1 or digit > 7) then return nil end
                result[#result + 1] = {kind = suit * 9 + (digit == 0 and 5 or digit) - 1, red = digit == 0}
            end
            digits = {}
        end
    end
    if #result == 0 or #digits > 0 then return nil end
    return result
end
function tiles.name(kind) return (kind % 9 + 1) .. tiles.suits:sub(kind // 9 + 1, kind // 9 + 1) end
function tiles.block(kinds)
    local ordered, digits = {}, {}; for index, kind in ipairs(kinds) do ordered[index] = kind end; table.sort(ordered)
    for _, kind in ipairs(ordered) do digits[#digits + 1] = kind % 9 + 1 end
    return table.concat(digits) .. tiles.suits:sub(ordered[1] // 9 + 1, ordered[1] // 9 + 1)
end
function tiles.counts(values)
    local counts = {}; for index = 1, 34 do counts[index] = 0 end
    for _, tile in ipairs(values) do counts[tile.kind + 1] = counts[tile.kind + 1] + 1 end
    return counts
end
function tiles.honor(kind) return kind >= 27 end
function tiles.terminal(kind) return kind < 27 and (kind % 9 == 0 or kind % 9 == 8) end
function tiles.yaochuu(kind) return tiles.honor(kind) or tiles.terminal(kind) end
function tiles.next_dora(kind)
    if kind < 27 then return kind // 9 * 9 + (kind % 9 + 1) % 9 end
    if kind < 31 then return 27 + (kind - 26) % 4 end
    return 31 + (kind - 30) % 3
end
return tiles
