local board = require('board')
local M = {RACK_SIZE = 7, BINGO_BONUS = 50}
function M.squares(move)
    local result = {}
    for i = 1, #move.word do result[#result + 1] = {move.row + move.direction * (i - 1), move.column + (1 - move.direction) * (i - 1), move.word:sub(i, i)} end
    return result
end
function M.placement(position, move)
    local result = {}
    for _, cell in ipairs(M.squares(move)) do if position[cell[1]][cell[2]] == '.' then result[#result + 1] = cell end end
    return result
end
function M.apply(position, tiles)
    local result = {}
    for r = 1, 15 do result[r] = {}; for c = 1, 15 do result[r][c] = position[r][c] end end
    for _, tile in ipairs(tiles) do result[tile[1]][tile[2]] = tile[3] end
    return result
end
function M.cross_words(position, move)
    local tiles = M.placement(position, move)
    local after, result = M.apply(position, tiles), {}
    for _, tile in ipairs(tiles) do local word = board.run_at(after, tile[1], tile[2], 1 - move.direction); if #word.word >= 2 then result[#result + 1] = word end end
    return result
end
function M.word_score(position, word, values)
    local score, multiplier = 0, 1
    for _, cell in ipairs(M.squares(word)) do
        local r, c, letter = table.unpack(cell)
        local value = letter:match('^[A-Z]$') and values[letter] or 0
        if position[r][c] == '.' then
            local premium = board.PREMIUMS[r][c]
            value = value * (premium == '+' and 2 or premium == '^' and 3 or 1)
            multiplier = multiplier * (premium == '*' and 2 or premium == '#' and 3 or 1)
        end
        score = score + value
    end
    return score * multiplier
end
function M.score_move(position, move, values)
    local words, scores, score = {move}, {}, 0
    for _, word in ipairs(M.cross_words(position, move)) do words[#words + 1] = word end
    for _, word in ipairs(words) do local value = M.word_score(position, word, values); scores[#scores + 1] = {word, value}; score = score + value end
    local tiles = M.placement(position, move)
    if #tiles == 7 then score = score + 50 end
    return score, tiles, scores
end
return M
