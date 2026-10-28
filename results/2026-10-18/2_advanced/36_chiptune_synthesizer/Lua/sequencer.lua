local parser = require("song_parser")
local M = {}
function M.samples_per_tick(rate, tempo)
    return rate * 5 // (tempo * 2)
end
function M.next_row(song, position, row)
    local jump, pattern_break
    for _, cell in ipairs(parser.cells(song, position, row)) do
        local effect = cell.effect
        if effect then
            if effect.name == "F" and effect.value == 0 then
                return nil
            elseif effect.name == "B" then
                jump = effect.value
            elseif effect.name == "D" then
                pattern_break = effect.value
            end
        end
    end
    if jump == nil and pattern_break == nil then
        if row < 63 then
            return position, row + 1
        end
        return position + 1, 0
    end
    return jump or position + 1, pattern_break and pattern_break < 64 and pattern_break or 0
end
function M.reachable(song)
    local reached = {}
    local position, row = 0, 0
    while position ~= nil and position < #song.order and not reached[position * 64 + row] do
        reached[position * 64 + row] = true
        position, row = M.next_row(song, position, row)
    end
    return reached
end
return M
