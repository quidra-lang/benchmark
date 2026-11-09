package.path = 'Lua/?.lua;' .. package.path
local board = require('board')
local Trie = require('dictionary_trie')
local generator = require('move_generator')
local scoring = require('scoring')
local game = require('game')
local LETTERS, TILE_ORDER, VOWELS = generator.LETTERS, game.TILE_ORDER, 'AEIOU'
local values, tile_counts, weights = {}, {}, {}
local function fields(line)
    local result = {}
    for word in line:gmatch('%S+') do result[#result + 1] = word end
    return result
end
local function append(destination, source) for _, item in ipairs(source) do destination[#destination + 1] = item end end
local function count_chars(text)
    local result = {}
    for i = 1, #text do local letter = text:sub(i, i); result[letter] = (result[letter] or 0) + 1 end
    return result
end
local function sorted_keys(set)
    local result = {}
    for key in pairs(set) do result[#result + 1] = key end
    table.sort(result)
    return result
end
local function sorted_string(text)
    local letters = {}
    for i = 1, #text do letters[i] = text:sub(i, i) end
    table.sort(letters)
    return table.concat(letters)
end
local function collection(text) return #text == 0 and '-' or sorted_string(text) end
local function valid_name(text) return #text >= 1 and #text <= 20 and text:match('^[a-z0-9_]+$') ~= nil end
local function valid_number(text, minimum, maximum)
    if not text:match('^%d+$') or #text > 1 and text:sub(1, 1) == '0' then return false end
    local value = tonumber(text)
    return value ~= nil and value >= minimum and value <= maximum
end
local function valid_rack(text) return #text >= 1 and #text <= 7 and text:match('^[A-Z?]+$') ~= nil end
local function tile_kind(letter) return letter:match('^[A-Z]$') and letter or '?' end
local function remove_tiles(rack, removed)
    local counts = count_chars(rack)
    for i = 1, #removed do local letter = removed:sub(i, i); counts[letter] = counts[letter] - 1 end
    local result = {}
    for _, letter in ipairs(sorted_keys(counts)) do result[#result + 1] = string.rep(letter, counts[letter]) end
    return table.concat(result)
end
local function read_board(job, first, last)
    local result = {}
    for i = first, last do
        local row = {}
        for c = 1, #job[i] do row[c] = job[i]:sub(c, c) end
        result[#result + 1] = row
    end
    return result
end
for line in io.lines('input/tiles.txt') do
    if line ~= '' and line:sub(1, 1) ~= '#' then local f = fields(line); values[f[1]], tile_counts[f[1]], weights[f[1]] = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]) end
end
local trie, dictionary_counts, lengths = Trie.new(), {lines = 0, skipped = 0, duplicates = 0}, {}
for line in io.lines('input/dictionary.txt') do
    if line ~= '' and line:sub(1, 1) ~= '#' then
        dictionary_counts.lines = dictionary_counts.lines + 1
        if #line < 2 or #line > 15 or not line:match('^[A-Z]+$') then dictionary_counts.skipped = dictionary_counts.skipped + 1
        elseif trie:add(line) then lengths[#line] = (lengths[#line] or 0) + 1 else dictionary_counts.duplicates = dictionary_counts.duplicates + 1 end
    end
end
local dictionary_lines = {'DICTIONARY lines=' .. dictionary_counts.lines .. ' words=' .. trie.words .. ' skipped=' .. dictionary_counts.skipped .. ' duplicates=' .. dictionary_counts.duplicates .. ' nodes=' .. trie.nodes}
local length_line = 'lengths'
for _, length in ipairs(sorted_keys(lengths)) do length_line = length_line .. ' ' .. length .. '=' .. lengths[length] end
dictionary_lines[2] = length_line
local jobs, current = {}, nil
for line in io.lines('input/jobs.txt') do
    if not current then if line ~= '' and line:sub(1, 1) ~= '#' then current = {line} end
    elseif line == 'END' then jobs[#jobs + 1], current = current, nil
    else current[#current + 1] = line end
end
local topn_totals, validation_totals, game_totals = {}, {}, {}
local function add_total(totals, key, value) totals[key] = (totals[key] or 0) + (value or 1) end
local function used_tiles(position)
    local result = {}
    for _, tile in ipairs(board.tiles(position)) do local kind = tile_kind(tile[3]); result[kind] = (result[kind] or 0) + 1 end
    return result
end
local function tile_error(position, rack)
    local counts = used_tiles(position)
    for i = 1, #rack do local letter = rack:sub(i, i); counts[letter] = (counts[letter] or 0) + 1 end
    for i = 1, 27 do local letter = TILE_ORDER:sub(i, i); if (counts[letter] or 0) > tile_counts[letter] then return 'too many ' .. letter end end
    return nil
end
local function unseen(position, rack)
    local counts, result = used_tiles(position), {}
    for i = 1, #rack do local letter = rack:sub(i, i); counts[letter] = (counts[letter] or 0) + 1 end
    for i = 1, 27 do local letter = TILE_ORDER:sub(i, i); result[#result + 1] = string.rep(letter, tile_counts[letter] - (counts[letter] or 0)) end
    return table.concat(result)
end
local function board_error(position, rack)
    if #position ~= 15 then return 'board rows ' .. #position end
    for i, row in ipairs(position) do
        if #row ~= 15 then return 'bad board row ' .. i end
        for _, letter in ipairs(row) do if not letter:match('^[.A-Za-z]$') then return 'bad board row ' .. i end end
    end
    local reason = tile_error(position, rack)
    if reason then return reason end
    if #board.tiles(position) > 0 and position[8][8] == '.' then return 'center empty' end
    if not board.connected(position) then return 'disconnected' end
    for _, word in ipairs(board.words(position)) do if not trie:contains(word.word:upper()) then return 'unknown word ' .. word.word .. ' at ' .. board.position(word) end end
    return nil
end
local function strategy_valid(strategy) return strategy == 'score' or strategy == 'tiles' or strategy == 'equity' end
local function job_error(job, seen)
    local header = fields(job[1])
    local kind, name = header[1], header[2]
    if not valid_name(name) then return 'bad name' end
    if seen[name] then return 'duplicate name' end
    if kind == 'TOPN' then
        if not valid_number(header[3], 1, 99) then return 'bad count' end
        if not strategy_valid(header[4]) then return 'bad order' end
        local rack = fields(job[2])[2]
        if not valid_rack(rack) then return 'bad rack' end
        return board_error(read_board(job, 4, #job), rack)
    elseif kind == 'VALIDATE' then
        local last = #job
        for i = 3, #job do if job[i]:sub(1, 4) == 'MOVE' then last = i - 1; break end end
        return board_error(read_board(job, 3, last), '')
    end
    if not valid_number(header[3], 1, 2147483646) then return 'bad seed' end
    if #job - 1 < 2 or #job - 1 > 4 then return 'bad player count ' .. (#job - 1) end
    local player_names = {}
    for i = 2, #job do
        local player = fields(job[i])
        if not valid_name(player[2]) or not strategy_valid(player[3]) or kind == 'GAME' and not valid_number(player[4], 0, 99) then return 'bad player ' .. (i - 1) end
        if player_names[player[2]] then return 'duplicate player ' .. (i - 1) end
        player_names[player[2]] = true
    end
    return nil
end
local function leave_value(rack)
    local counts, duplicates, vowels, consonants, total = count_chars(rack), 0, 0, 0, 0
    for i = 1, #rack do total = total + weights[rack:sub(i, i)] end
    for i = 1, 26 do
        local letter = LETTERS:sub(i, i)
        local count = counts[letter] or 0
        duplicates = duplicates + math.max(0, count - 1)
        if VOWELS:find(letter, 1, true) then vowels = vowels + count else consonants = consonants + count end
    end
    return total - 4 * duplicates - 3 * math.max(0, math.abs(vowels - consonants) - 1)
end
local function best_leave(rack)
    local counts, best, best_value = count_chars(rack), nil, nil
    local letters = sorted_keys(counts)
    local function visit(index, candidate)
        if index > #letters then
            if #candidate < #rack then
                local value = leave_value(candidate)
                if best == nil or value > best_value or value == best_value and (#candidate > #best or #candidate == #best and candidate < best) then best, best_value = candidate, value end
            end
            return
        end
        local letter = letters[index]
        for count = 0, counts[letter] do visit(index + 1, candidate .. string.rep(letter, count)) end
    end
    visit(1, '')
    return best
end
local function evaluate(position, rack, move)
    local score, tiles, word_scores = scoring.score_move(position, move, values)
    local removed, words = {}, {}
    for _, tile in ipairs(tiles) do removed[#removed + 1] = tile_kind(tile[3]) end
    for _, entry in ipairs(word_scores) do words[#words + 1] = entry[1].word .. ':' .. entry[2] end
    local leave = remove_tiles(rack, table.concat(removed))
    return {move = move, score = score, new_tiles = tiles, words = table.concat(words, ','), leave = leave, value = leave_value(leave)}
end
local function standard_less(a, b)
    if a.score ~= b.score then return a.score > b.score end
    local x, y = a.move, b.move
    if x.row ~= y.row then return x.row < y.row end
    if x.column ~= y.column then return x.column < y.column end
    if x.direction ~= y.direction then return x.direction < y.direction end
    return x.word < y.word
end
local function strategy_less(a, b, strategy)
    if strategy == 'tiles' and #a.new_tiles ~= #b.new_tiles then return #a.new_tiles > #b.new_tiles end
    if strategy == 'equity' and a.score + a.value ~= b.score + b.value then return a.score + a.value > b.score + b.value end
    return standard_less(a, b)
end
local function chosen_move(legal, strategy)
    local best = legal[1]
    for i = 2, #legal do if strategy_less(legal[i], best, strategy) then best = legal[i] end end
    return best
end
local function notation(evaluated) return board.position(evaluated.move) .. ' ' .. evaluated.move.word end
local function legal_moves(position, rack)
    local moves = {}
    for _, move in ipairs(generator.generate(position, rack, trie)) do moves[#moves + 1] = evaluate(position, rack, move) end
    table.sort(moves, standard_less)
    return moves
end
local function position_summary(position)
    local words, occupied, longest, blanks, premiums = board.words(position), board.tiles(position), '-', 0, {['#'] = 0, ['*'] = 0, ['^'] = 0, ['+'] = 0, ['.'] = 0}
    for _, word in ipairs(words) do if longest == '-' or #word.word > #longest then longest = word.word end end
    for _, tile in ipairs(occupied) do
        if tile[3]:match('^[a-z]$') then blanks = blanks + 1 end
        local premium = board.PREMIUMS[tile[1]][tile[2]]
        premiums[premium] = premiums[premium] + 1
    end
    return 'position tiles=' .. #occupied .. ' words=' .. #words .. ' longest=' .. longest .. ' blanks=' .. blanks .. ' premiums=TW:' .. premiums['#'] .. ',DW:' .. premiums['*'] .. ',TL:' .. premiums['^'] .. ',DL:' .. premiums['+']
end
local function topn(job)
    local header = fields(job[1])
    local name, count, order, rack = header[2], tonumber(header[3]), header[4], fields(job[2])[2]
    local position = read_board(job, 4, #job)
    local legal, shown = legal_moves(position, rack), {}
    for _, move in ipairs(legal) do shown[#shown + 1] = move end
    table.sort(shown, function(a, b) return strategy_less(a, b, order) end)
    while #shown > count do table.remove(shown) end
    local unseen_tiles, anchors = unseen(position, rack), generator.anchors(position)
    local statistics = {}
    for _, oriented in ipairs({position, board.transpose(position)}) do
        local squares, dead, letters = 0, 0, 0
        for _, allowed in pairs(generator.cross_checks(oriented, trie)) do local number = #sorted_keys(allowed); squares, letters = squares + 1, letters + number; if number == 0 then dead = dead + 1 end end
        statistics[#statistics + 1] = squares .. ',' .. dead .. ',' .. letters
    end
    local vowels, consonants, blanks = 0, 0, 0
    for i = 1, #rack do local letter = rack:sub(i, i); if letter == '?' then blanks = blanks + 1 elseif VOWELS:find(letter, 1, true) then vowels = vowels + 1 else consonants = consonants + 1 end end
    local across, bingos, blank_moves, best_scores = 0, 0, 0, {}
    for _, move in ipairs(legal) do
        if move.move.direction == 0 then across = across + 1 end
        if #move.new_tiles == 7 then bingos = bingos + 1 end
        for _, tile in ipairs(move.new_tiles) do if tile[3]:match('^[a-z]$') then blank_moves = blank_moves + 1; break end end
        local number = #move.new_tiles
        if not best_scores[number] or move.score > best_scores[number] then best_scores[number] = move.score end
    end
    local lines = {'TOPN ' .. name .. ' n=' .. count .. ' order=' .. order .. ' rack=' .. collection(rack), 'board tiles=' .. #board.tiles(position) .. ' anchors=' .. #anchors,
        'unseen count=' .. #unseen_tiles .. ' tiles=' .. collection(unseen_tiles), 'rack vowels=' .. vowels .. ' consonants=' .. consonants .. ' blanks=' .. blanks .. ' value=' .. game.points(rack, values),
        'checks across=' .. statistics[1] .. ' down=' .. statistics[2], 'moves total=' .. #legal .. ' across=' .. across .. ' down=' .. (#legal - across) .. ' bingos=' .. bingos .. ' blanks=' .. blank_moves}
    local best_line = 'best_by_tiles'
    for number = 1, 7 do best_line = best_line .. ' ' .. number .. '=' .. (best_scores[number] or '-') end
    lines[#lines + 1] = best_line
    local keep = best_leave(rack)
    lines[#lines + 1] = 'exchange keep=' .. collection(keep) .. ' value=' .. leave_value(keep)
    local anagrams = trie:anagrams(rack)
    table.sort(anagrams, function(a, b) return #a > #b or #a == #b and a < b end)
    local anagram_count = #anagrams
    while #anagrams > 10 do table.remove(anagrams) end
    lines[#lines + 1] = 'anagrams total=' .. anagram_count .. ' top=' .. (#anagrams > 0 and table.concat(anagrams, ',') or '-')
    for _, word in ipairs(board.words(position)) do
        if #word.word >= 3 then
            local front, back = {}, {}
            for i = 1, 26 do local letter = LETTERS:sub(i, i); if trie:contains(letter .. word.word:upper()) then front[#front + 1] = letter end; if trie:contains(word.word:upper() .. letter) then back[#back + 1] = letter end end
            if #front > 0 or #back > 0 then lines[#lines + 1] = 'hook ' .. board.position(word) .. ' ' .. word.word .. ' front=' .. (#front > 0 and table.concat(front) or '-') .. ' back=' .. (#back > 0 and table.concat(back) or '-') end
        end
    end
    local nets
    if #unseen_tiles >= 1 and #unseen_tiles <= 7 and #shown > 0 then
        nets = {}
        local best = 1
        for i, move in ipairs(shown) do local replies = legal_moves(scoring.apply(position, move.new_tiles), unseen_tiles); nets[i] = move.score - (#replies > 0 and replies[1].score or 0); if nets[i] > nets[best] then best = i end end
        lines[#lines + 1] = 'endgame opponent=' .. collection(unseen_tiles) .. ' best=' .. best .. ' net=' .. nets[best]
    end
    for i, move in ipairs(shown) do lines[#lines + 1] = i .. ' ' .. notation(move) .. ' score=' .. move.score .. ' tiles=' .. #move.new_tiles .. ' leave=' .. collection(move.leave) .. ' value=' .. move.value .. (nets and ' net=' .. nets[i] or '') .. ' words=' .. move.words end
    add_total(topn_totals, 'moves', #legal); add_total(topn_totals, 'bingos', bingos)
    return lines
end

local function record_error(position, player, rack, action)
    if not valid_name(player) then return 'bad player' end
    if not valid_rack(rack) then return 'bad rack' end
    local reason = tile_error(position, rack)
    if reason then return reason end
    if #action == 1 and action[1] == 'PASS' then return nil end
    if action[1] == 'EXCHANGE' then
        local returned = action[2]
        if not valid_rack(returned) then return 'bad exchange' end
        local available, requested = count_chars(rack), count_chars(returned)
        for i = 1, #returned do local letter = returned:sub(i, i); if requested[letter] > (available[letter] or 0) then return 'rack lacks ' .. letter end end
        return nil
    end
    local row, column, direction = board.parse_position(action[1])
    if not row then return 'bad position' end
    local word = action[2]
    if #word < 2 or #word > 15 or not word:match('^[A-Za-z]+$') then return 'bad word' end
    local move = {row = row, column = column, direction = direction, word = word}
    local cells = scoring.squares(move)
    for _, cell in ipairs(cells) do if not board.inside(cell[1], cell[2]) then return 'off board' end end
    for _, cell in ipairs(cells) do local letter = position[cell[1]][cell[2]]; if letter ~= '.' and letter ~= cell[3] then return 'mismatch at ' .. board.square_name(cell[1], cell[2]) end end
    local dr, dc = direction, 1 - direction
    for _, cell in ipairs({{row - dr, column - dc}, {row + dr * #word, column + dc * #word}}) do if board.inside(cell[1], cell[2]) and position[cell[1]][cell[2]] ~= '.' then return 'not whole word' end end
    local tiles = scoring.placement(position, move)
    if #tiles == 0 then return 'no new tiles' end
    local available = count_chars(rack)
    for _, tile in ipairs(tiles) do local letter = tile_kind(tile[3]); if (available[letter] or 0) == 0 then return 'rack lacks ' .. letter end; available[letter] = available[letter] - 1 end
    if #board.tiles(position) == 0 then
        local covered = false
        for _, tile in ipairs(tiles) do if tile[1] == 8 and tile[2] == 8 then covered = true end end
        if not covered then return 'center not covered' end
    else
        local connected = false
        for _, tile in ipairs(tiles) do for _, neighbor in ipairs(board.neighbors(tile[1], tile[2])) do if position[neighbor[1]][neighbor[2]] ~= '.' then connected = true end end end
        if not connected then return 'not connected' end
    end
    local words = {move}
    append(words, scoring.cross_words(position, move))
    for _, formed in ipairs(words) do if not trie:contains(formed.word:upper()) then return 'unknown word ' .. formed.word .. ' at ' .. board.position(formed) end end
    return nil, move
end
local function validate(job)
    local position = read_board(job, 3, 17)
    local lines, players, player_order, totals = {'VALIDATE ' .. fields(job[1])[2]}, {}, {}, {valid = 0, invalid = 0, score = 0, best = 0, loss = 0}
    for index = 18, #job do
        local record = fields(job[index])
        local player, rack, action = record[2], record[3], {}
        for i = 4, #record do action[#action + 1] = record[i] end
        local prefix = 'move ' .. (index - 17) .. ' ' .. player .. ' ' .. table.concat(action, ' ')
        local reason, move = record_error(position, player, rack, action)
        if reason ~= 'bad player' then
            if not players[player] then players[player] = {moves = 0, valid = 0, score = 0, loss = 0}; player_order[#player_order + 1] = player end
            players[player].moves = players[player].moves + 1
        end
        if reason then lines[#lines + 1] = prefix .. ' invalid ' .. reason; totals.invalid = totals.invalid + 1
        else
            local legal = legal_moves(position, rack)
            local best, score, evaluated, rank = #legal > 0 and legal[1].score or 0, 0, nil, nil
            if move then
                evaluated = evaluate(position, rack, move)
                score = evaluated.score
                local target = generator.placement_key(evaluated.new_tiles)
                for i, candidate in ipairs(legal) do if generator.placement_key(candidate.new_tiles) == target then rank = i; break end end
            end
            local statistics = players[player]
            statistics.valid, statistics.score, statistics.loss = statistics.valid + 1, statistics.score + score, statistics.loss + best - score
            totals.valid, totals.score, totals.best, totals.loss = totals.valid + 1, totals.score + score, totals.best + best, totals.loss + best - score
            if move then
                lines[#lines + 1] = prefix .. ' score=' .. score .. ' total=' .. statistics.score .. ' tiles=' .. #evaluated.new_tiles .. ' rank=' .. rank .. '/' .. #legal .. ' best=' .. best .. ' words=' .. evaluated.words
                position = scoring.apply(position, evaluated.new_tiles)
            else lines[#lines + 1] = prefix .. ' score=0 total=' .. statistics.score .. ' moves=' .. #legal .. ' best=' .. best end
        end
    end
    for _, player in ipairs(player_order) do local statistics = players[player]; lines[#lines + 1] = 'player ' .. player .. ' moves=' .. statistics.moves .. ' valid=' .. statistics.valid .. ' score=' .. statistics.score .. ' loss=' .. statistics.loss end
    lines[#lines + 1] = 'total valid=' .. totals.valid .. ' invalid=' .. totals.invalid .. ' score=' .. totals.score .. ' best=' .. totals.best .. ' loss=' .. totals.loss
    lines[#lines + 1] = position_summary(position)
    append(lines, board.display(position))
    add_total(validation_totals, 'moves', #job - 17)
    for _, key in ipairs({'valid', 'invalid', 'loss'}) do add_total(validation_totals, key, totals[key]) end
    return lines
end
local function ordinary_game(job)
    local header = fields(job[1])
    local name, seed = header[2], tonumber(header[3])
    local random, players = game.generator(seed), {}
    local bag = game.make_bag(tile_counts, random)
    local position, lines = board.empty(), {'GAME ' .. name .. ' seed=' .. seed .. ' players=' .. (#job - 1)}
    for i = 2, #job do
        local player = fields(job[i])
        local threshold = tonumber(player[4])
        players[#players + 1] = {name = player[2], strategy = player[3], threshold = threshold, rack = game.draw(bag, 7), score = 0, plays = 0, bingos = 0, exchanges = 0, passes = 0, top = 0, loss = 0}
        lines[#lines + 1] = 'player ' .. (i - 1) .. ' ' .. player[2] .. ' strategy=' .. player[3] .. ' threshold=' .. threshold
    end
    local turn, consecutive, outgoing, highlight = 0, 0, nil, nil
    while true do
        local index = turn % #players + 1
        local player = players[index]
        turn = turn + 1
        local rack = player.rack
        local legal = legal_moves(position, rack)
        local candidate = chosen_move(legal, player.strategy)
        local prefix = 'turn ' .. turn .. ' ' .. player.name .. ' rack=' .. collection(rack) .. ' moves=' .. #legal
        if candidate and not (candidate.score < player.threshold and #bag >= 7) then
            local best = legal[1].score
            position = scoring.apply(position, candidate.new_tiles)
            player.score = player.score + candidate.score
            local drawn = game.draw(bag, 7 - #candidate.leave)
            player.rack = candidate.leave .. drawn
            player.plays, player.top, player.loss = player.plays + 1, math.max(player.top, candidate.score), player.loss + best - candidate.score
            if #candidate.new_tiles == 7 then player.bingos = player.bingos + 1 end
            consecutive = 0
            if not highlight or candidate.score > highlight.move.score then highlight = {turn = turn, player = player.name, move = candidate} end
            lines[#lines + 1] = prefix .. ' best=' .. best .. ' play ' .. notation(candidate) .. ' score=' .. candidate.score .. ' total=' .. player.score .. ' draw=' .. collection(drawn) .. ' bag=' .. #bag
            if #player.rack == 0 and #bag == 0 then outgoing = index; break end
        elseif #bag >= 7 then
            local keep = best_leave(rack)
            local drawn = game.exchange(bag, remove_tiles(rack, keep), random)
            player.rack, player.exchanges, consecutive = keep .. drawn, player.exchanges + 1, consecutive + 1
            lines[#lines + 1] = prefix .. ' exchange keep=' .. collection(keep) .. ' draw=' .. collection(drawn) .. ' bag=' .. #bag
        else
            player.passes, consecutive = player.passes + 1, consecutive + 1
            lines[#lines + 1] = prefix .. ' pass bag=' .. #bag
        end
        if consecutive == 6 then break end
    end
    lines[#lines + 1] = outgoing and 'end reason=out player=' .. players[outgoing].name .. ' turns=' .. turn or 'end reason=scoreless turns=' .. turn
    local adjustments, final_scores, standings = {}, {}, {}
    for i, player in ipairs(players) do adjustments[i] = -game.points(player.rack, values) end
    if outgoing then
        adjustments[outgoing] = 0
        for i, player in ipairs(players) do if i ~= outgoing then adjustments[outgoing] = adjustments[outgoing] + game.points(player.rack, values) end end
    end
    local maximum
    for i, player in ipairs(players) do
        final_scores[i], standings[i] = player.score + adjustments[i], i
        if not maximum or final_scores[i] > maximum then maximum = final_scores[i] end
        local adjustment = adjustments[i] > 0 and '+' .. adjustments[i] or tostring(adjustments[i])
        lines[#lines + 1] = 'final ' .. player.name .. ' score=' .. player.score .. ' rack=' .. collection(player.rack) .. ' adjust=' .. adjustment .. ' total=' .. final_scores[i]
    end
    table.sort(standings, function(a, b) return final_scores[a] > final_scores[b] or final_scores[a] == final_scores[b] and a < b end)
    for rank, i in ipairs(standings) do
        local player = players[i]
        lines[#lines + 1] = 'standing ' .. rank .. ' ' .. player.name .. ' total=' .. final_scores[i] .. ' plays=' .. player.plays .. ' bingos=' .. player.bingos .. ' exchanges=' .. player.exchanges .. ' passes=' .. player.passes .. ' top=' .. player.top .. ' loss=' .. player.loss
    end
    local winners = {}
    for i, player in ipairs(players) do if final_scores[i] == maximum then winners[#winners + 1] = player.name end end
    lines[#lines + 1] = 'winner ' .. table.concat(winners, ',')
    if highlight then lines[#lines + 1] = 'highlight turn=' .. highlight.turn .. ' player=' .. highlight.player .. ' play ' .. notation(highlight.move) .. ' score=' .. highlight.move.score end
    lines[#lines + 1] = position_summary(position)
    append(lines, board.display(position))
    add_total(game_totals, 'turns', turn)
    for _, player in ipairs(players) do for _, key in ipairs({'plays', 'exchanges', 'passes', 'bingos'}) do add_total(game_totals, key, player[key]) end end
    return lines
end
local function duplicate_game(job)
    local header = fields(job[1])
    local name, seed = header[2], tonumber(header[3])
    local random = game.generator(seed)
    local bag = game.make_bag(tile_counts, random)
    local position, rack, players, totals = board.empty(), game.draw(bag, 7), {}, {}
    local lines = {'DUPLICATE ' .. name .. ' seed=' .. seed .. ' players=' .. (#job - 1)}
    for i = 2, #job do
        local player = fields(job[i])
        players[#players + 1], totals[#totals + 1] = {player[2], player[3]}, 0
        lines[#lines + 1] = 'player ' .. (i - 1) .. ' ' .. player[2] .. ' strategy=' .. player[3]
    end
    local round, master_total, reason = 0, 0, 'stuck'
    while true do
        local legal = legal_moves(position, rack)
        if #legal == 0 then break end
        round = round + 1
        local master, picks = legal[1], {}
        for i, player in ipairs(players) do local move = chosen_move(legal, player[2]); totals[i] = totals[i] + move.score; picks[i] = move.score end
        master_total = master_total + master.score
        lines[#lines + 1] = 'round ' .. round .. ' rack=' .. collection(rack) .. ' moves=' .. #legal .. ' master ' .. notation(master) .. ' score=' .. master.score .. ' picks=' .. table.concat(picks, ',')
        position = scoring.apply(position, master.new_tiles)
        rack = master.leave .. game.draw(bag, 7 - #master.leave)
        if #rack == 0 then reason = 'out'; break end
    end
    lines[#lines + 1] = 'end reason=' .. reason .. ' rounds=' .. round .. (reason == 'stuck' and ' rack=' .. collection(rack) or '')
    lines[#lines + 1] = 'master total=' .. master_total
    local maximum = totals[1]
    for _, total in ipairs(totals) do maximum = math.max(maximum, total) end
    local winners = {}
    for i, player in ipairs(players) do
        local percent = master_total >= 1 and 100 * totals[i] // master_total or 0
        lines[#lines + 1] = 'final ' .. player[1] .. ' total=' .. totals[i] .. ' percent=' .. percent
        if totals[i] == maximum then winners[#winners + 1] = player[1] end
    end
    lines[#lines + 1] = 'winner ' .. table.concat(winners, ',')
    lines[#lines + 1] = position_summary(position)
    append(lines, board.display(position))
    add_total(game_totals, 'rounds', round)
    return lines
end
local move_blocks, validation_blocks, game_blocks, seen = {dictionary_lines}, {}, {}, {}
for _, job in ipairs(jobs) do
    local header = fields(job[1])
    local kind, name, destination, totals, key = header[1], header[2]
    if kind == 'TOPN' then destination, totals, key = move_blocks, topn_totals, 'jobs'
    elseif kind == 'VALIDATE' then destination, totals, key = validation_blocks, validation_totals, 'jobs'
    else destination, totals, key = game_blocks, game_totals, kind == 'GAME' and 'games' or 'duplicates' end
    add_total(totals, key)
    local reason = job_error(job, seen)
    seen[name] = true
    if reason then destination[#destination + 1] = {kind .. ' ' .. name, 'error ' .. reason}; add_total(totals, 'errors')
    elseif kind == 'TOPN' then destination[#destination + 1] = topn(job)
    elseif kind == 'VALIDATE' then destination[#destination + 1] = validate(job)
    elseif kind == 'GAME' then destination[#destination + 1] = ordinary_game(job)
    else destination[#destination + 1] = duplicate_game(job) end
end
for _, specification in ipairs({{move_blocks, topn_totals, {'jobs', 'errors', 'moves', 'bingos'}}, {validation_blocks, validation_totals, {'jobs', 'errors', 'moves', 'valid', 'invalid', 'loss'}}, {game_blocks, game_totals, {'games', 'duplicates', 'errors', 'turns', 'rounds', 'plays', 'exchanges', 'passes', 'bingos'}}}) do
    local parts = {'SUMMARY'}
    for _, key in ipairs(specification[3]) do parts[#parts + 1] = key .. '=' .. (specification[2][key] or 0) end
    specification[1][#specification[1] + 1] = {table.concat(parts, ' ')}
end
for _, output in ipairs({{'moves.txt', move_blocks}, {'validation.txt', validation_blocks}, {'game.txt', game_blocks}}) do
    local blocks = {}
    for _, block in ipairs(output[2]) do blocks[#blocks + 1] = table.concat(block, '\n') end
    local file = assert(io.open('output/' .. output[1], 'wb'))
    file:write(table.concat(blocks, '\n\n'), '\n')
    file:close()
end
