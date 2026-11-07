local rally_sports = {TENNIS = true, TABLETENNIS = true, BADMINTON = true, VOLLEYBALL = true}
local option_rules = {
    TENNIS = {SETS = {'3', '5'}, DEUCE = {'AD', 'NOAD'}, FINAL = {'TB7', 'TB10', 'ADV', 'SUPER'}, FIRST = {'A', 'B'}},
    TABLETENNIS = {GAMES = {'5', '7'}, FIRST = {'A', 'B'}},
    BADMINTON = {FIRST = {'A', 'B'}}, VOLLEYBALL = {FIRST = {'A', 'B'}},
    DARTS = {START = {'501', '301', '701'}, SETS = {'1', '2', '3', '4', '5'}, LEGS = {'1', '2', '3', '4', '5'}, FIRST = {'A', 'B'}},
    BOWLING = {}
}
local function score_error(message) error(message, 0) end
local function side(text) return text == 'A' and 1 or 2 end
local function other(player) return 3 - player end
local function pair_text(values) return values[1] .. '-' .. values[2] end
local function clone(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = clone(item) end
    return result
end
local function append_all(target, items)
    table.move(items, 1, #items, #target + 1, target)
end
local function sum(values)
    local total = 0
    for _, value in ipairs(values) do total = total + value end
    return total
end
local function pack_record(record)
    return string.pack(string.rep('i4', #record), table.unpack(record))
end
local function contains(values, needle)
    for _, value in ipairs(values) do
        if value == needle then return true end
    end
    return false
end
local function checkout_tables()
    local candidates, doubles = {}, {}
    local darts = {['25'] = {25, false}, BULL = {50, true}, MISS = {0, false}}
    for _, item in ipairs({{'S', 1}, {'T', 3}, {'D', 2}}) do
        local prefix, multiplier = item[1], item[2]
        for value = 20, 1, -1 do
            local code = prefix .. value
            candidates[#candidates + 1] = {code, value * multiplier}
            darts[code] = {value * multiplier, prefix == 'D'}
            if prefix == 'D' then doubles[#doubles + 1] = {code, value * multiplier} end
        end
    end
    candidates[#candidates + 1] = {'25', 25}
    candidates[#candidates + 1] = {'BULL', 50}
    doubles[#doubles + 1] = {'BULL', 50}
    local tables = {{}, {}, {}}
    for _, last in ipairs(doubles) do
        if not tables[1][last[2]] then tables[1][last[2]] = {last[1]} end
    end
    for _, first in ipairs(candidates) do
        for _, last in ipairs(doubles) do
            local total = first[2] + last[2]
            if not tables[2][total] then tables[2][total] = {first[1], last[1]} end
        end
    end
    for _, first in ipairs(candidates) do
        for _, second in ipairs(candidates) do
            for _, last in ipairs(doubles) do
                local total = first[2] + second[2] + last[2]
                if not tables[3][total] then tables[3][total] = {first[1], second[1], last[1]} end
            end
        end
    end
    return darts, tables
end
local dart_data, checkout_data = checkout_tables()
local function checkout(score, maximum)
    for count = 1, maximum or 3 do
        if checkout_data[count][score] then return checkout_data[count][score] end
    end
    return {}
end
local function create_match(tokens)
    local m = {id = tokens[2], sport = tokens[3], names = {tokens[4]}, options = {}, initial = {}, history = {}}
    if m.sport ~= 'BOWLING' then m.names[2] = tokens[5] end
    local first_option
    if m.sport == 'VOLLEYBALL' then
        for player = 1, 2 do
            m.initial[player] = {}
            for number in tokens[player + 5]:gmatch('[^,]+') do
                m.initial[player][#m.initial[player] + 1] = tonumber(number)
            end
        end
        first_option = 8
    elseif m.sport == 'BOWLING' then
        first_option = 5
    else
        first_option = 6
    end
    local rules, seen = option_rules[m.sport], {}
    for key, values in pairs(rules) do m.options[key] = values[1] end
    for index = first_option, #tokens do
        local key, value = tokens[index]:match('^([^=]+)=([^=]+)$')
        if not key or not rules[key] or not contains(rules[key], value) or seen[key] then score_error('invalid option') end
        seen[key] = true
        m.options[key] = value
    end
    local first = side(m.options.FIRST or 'A')
    local stats = {}
    for _, key in ipairs({'points', 'served', 'servewins', 'runmax', 'holds', 'games', 'breaks', 'opportunities', 'converted',
        'darts', 'scored', 'busts', 'high', 'tons', 'maximums', 'attempts', 'hits'}) do
        stats[key] = {0, 0}
    end
    local s = {p = {0, 0}, g = {0, 0}, won = {0, 0}, server = first, winner = 0, completed = {}, stats = stats, last = 0, run = 0}
    if m.sport == 'VOLLEYBALL' then
        s.lineups = clone(m.initial)
        s.subs = {0, 0}
        s.timeouts = {0, 0}
    elseif m.sport == 'BOWLING' then
        s.frames, s.marks = {}, {}
        for frame = 1, 10 do
            s.frames[frame], s.marks[frame] = {}, {}
        end
        s.frame, s.standing, s.fresh = 1, 10, true
    elseif m.sport == 'DARTS' then
        local start = tonumber(m.options.START)
        s.legs, s.remaining, s.turn = {0, 0}, {start, start}, {}
        s.turnscore, s.turnstart, s.legnumber = 0, start, 0
    end
    m.state = s
    return m
end
local function tennis_mode(m)
    local s = m.state
    local final = s.won[1] == tonumber(m.options.SETS) // 2 and s.won[1] == s.won[2]
    if final and m.options.FINAL == 'SUPER' then return 'SUPER' end
    if s.g[1] == 6 and s.g[2] == 6 and not (final and m.options.FINAL == 'ADV') then return 'TB' end
    return 'NORMAL'
end
local function rally_server(m)
    local s = m.state
    if m.sport == 'TENNIS' then
        if tennis_mode(m) ~= 'NORMAL' and ((sum(s.p) + 1) // 2) % 2 == 1 then return other(s.server) end
    elseif m.sport == 'TABLETENNIS' then
        local first = side(m.options.FIRST)
        if #s.completed % 2 == 1 then first = other(first) end
        local total = sum(s.p)
        local flip
        if total < 20 then flip = (total // 2) % 2 == 1 else flip = total % 2 == 1 end
        if flip then return other(first) end
        return first
    end
    return s.server
end
local function rally_outcome(m, winner)
    local s = m.state
    local points = {s.p[1], s.p[2]}
    points[winner] = points[winner] + 1
    local loser = other(winner)
    local game, unit, needed = false, false, 0
    if m.sport == 'TENNIS' then
        local mode = tennis_mode(m)
        if mode == 'NORMAL' then
            game = points[winner] >= 4 and (m.options.DEUCE == 'NOAD' or points[winner] - points[loser] >= 2)
            local games = s.g[winner] + 1
            unit = game and games >= 6 and games - s.g[loser] >= 2
        else
            local final = s.won[1] == s.won[2] and s.won[1] == tonumber(m.options.SETS) // 2
            local target = 7
            if mode == 'SUPER' or (final and m.options.FINAL == 'TB10') then target = 10 end
            unit = points[winner] >= target and points[winner] - points[loser] >= 2
        end
        needed = tonumber(m.options.SETS) // 2 + 1
    elseif m.sport == 'TABLETENNIS' then
        unit = points[winner] >= 11 and points[winner] - points[loser] >= 2
        needed = tonumber(m.options.GAMES) // 2 + 1
    elseif m.sport == 'BADMINTON' then
        unit = points[winner] == 30 or (points[winner] >= 21 and points[winner] - points[loser] >= 2)
        needed = 2
    else
        local target = #s.completed == 4 and 15 or 25
        unit = points[winner] >= target and points[winner] - points[loser] >= 2
        needed = 3
    end
    return game, unit, unit and s.won[winner] + 1 == needed
end
local function point_event(m, winner)
    local server = rally_server(m)
    local game, unit, finished = rally_outcome(m, winner)
    local mode = m.sport == 'TENNIS' and tennis_mode(m) or ''
    local opportunity = mode == 'NORMAL' and rally_outcome(m, other(server))
    local s = m.state
    local record = {1, winner, server, opportunity and 1 or 0, game and 1 or 0, s.p[1], s.p[2], s.g[1], s.g[2],
        s.won[1], s.won[2], s.server, #s.completed, s.last, s.run, s.stats.runmax[winner], 0, 0}
    s.stats.points[winner] = s.stats.points[winner] + 1
    s.stats.served[server] = s.stats.served[server] + 1
    if winner == server then s.stats.servewins[server] = s.stats.servewins[server] + 1 end
    s.run = s.last == winner and s.run + 1 or 1
    s.last = winner
    s.stats.runmax[winner] = math.max(s.stats.runmax[winner], s.run)
    if opportunity then
        s.stats.opportunities[other(server)] = s.stats.opportunities[other(server)] + 1
        if winner ~= server then s.stats.converted[winner] = s.stats.converted[winner] + 1 end
    end
    s.p[winner] = s.p[winner] + 1
    if m.sport == 'TENNIS' then
        if game then
            s.stats.games[server] = s.stats.games[server] + 1
            if winner == server then
                s.stats.holds[winner] = s.stats.holds[winner] + 1
            else
                s.stats.breaks[winner] = s.stats.breaks[winner] + 1
            end
            s.g[winner] = s.g[winner] + 1
            s.server = other(s.server)
        elseif unit then
            s.server = other(s.server)
        end
        if unit then
            if mode == 'SUPER' then
                s.completed[#s.completed + 1] = {s.p[1], s.p[2], 2, 0}
            elseif mode == 'TB' then
                s.g[winner] = s.g[winner] + 1
                s.completed[#s.completed + 1] = {s.g[1], s.g[2], 1, s.p[other(winner)]}
            else
                s.completed[#s.completed + 1] = {s.g[1], s.g[2], 0, 0}
            end
        end
    elseif m.sport == 'BADMINTON' then
        s.server = winner
    elseif m.sport == 'VOLLEYBALL' and winner ~= server then
        s.server = winner
        local lineup = s.lineups[winner]
        local first = table.remove(lineup, 1)
        lineup[#lineup + 1] = first
        record[18] = 1
    end
    if unit then
        if m.sport ~= 'TENNIS' then s.completed[#s.completed + 1] = {s.p[1], s.p[2], 0, 0} end
        s.won[winner] = s.won[winner] + 1
        if finished then
            s.winner = winner
        else
            if m.sport == 'VOLLEYBALL' then
                record[17] = 1
                append_all(record, s.lineups[1])
                append_all(record, s.lineups[2])
                append_all(record, s.subs)
                append_all(record, s.timeouts)
                s.lineups = clone(m.initial)
                s.subs, s.timeouts = {0, 0}, {0, 0}
                local first = side(m.options.FIRST)
                s.server = #s.completed % 2 == 0 and first or other(first)
            end
            s.p, s.g = {0, 0}, {0, 0}
        end
    elseif game then
        s.p = {0, 0}
    end
    m.history[#m.history + 1] = pack_record(record)
end
local function roll_event(s, pins)
    if pins > s.standing then score_error('too many pins') end
    local frame, mark = s.frame, nil
    if s.fresh and pins == 10 then
        mark = 'X'
    elseif pins == s.standing then
        mark = '/'
    else
        mark = pins == 0 and '-' or tostring(pins)
    end
    local rolls = s.frames[frame]
    rolls[#rolls + 1] = pins
    s.marks[frame][#s.marks[frame] + 1] = mark
    s.standing = s.standing - pins
    s.fresh = false
    if frame < 10 then
        if (#rolls == 1 and pins == 10) or #rolls == 2 then
            s.frame, s.standing, s.fresh = frame + 1, 10, true
        end
    else
        local complete = #rolls == 3 or (#rolls == 2 and rolls[1] ~= 10 and sum(rolls) < 10)
        if complete then
            s.winner = 1
        elseif s.standing == 0 then
            s.standing, s.fresh = 10, true
        end
    end
end
local function bowling_scores(s)
    local scores = {}
    for frame = 1, 10 do
        local rolls = s.frames[frame]
        if #rolls > 0 then
            local later = {}
            for index = frame + 1, 10 do append_all(later, s.frames[index]) end
            if frame == 10 then
                if s.winner ~= 0 then scores[frame] = sum(rolls) end
            elseif rolls[1] == 10 then
                if #later >= 2 then scores[frame] = 10 + later[1] + later[2] end
            elseif #rolls == 2 then
                if sum(rolls) == 10 then
                    if #later > 0 then scores[frame] = 10 + later[1] end
                else
                    scores[frame] = sum(rolls)
                end
            end
        end
    end
    return scores
end
local function total_bowling(s)
    local scores, total = bowling_scores(s), 0
    for frame = 1, 10 do total = total + (scores[frame] or 0) end
    return total
end
local function complete_turn(s, player)
    local score = s.turnscore
    s.stats.high[player] = math.max(s.stats.high[player], score)
    if score >= 100 then s.stats.tons[player] = s.stats.tons[player] + 1 end
    if score == 180 then s.stats.maximums[player] = s.stats.maximums[player] + 1 end
end
local function next_turn(s)
    s.server = other(s.server)
    s.turn, s.turnscore = {}, 0
    s.turnstart = s.remaining[s.server]
end
local function dart_event(m, code)
    local dart = dart_data[code]
    if not dart then score_error('invalid dart') end
    local s = m.state
    local player, value, double = s.server, dart[1], dart[2]
    local before = s.remaining[player]
    s.stats.darts[player] = s.stats.darts[player] + 1
    if before == 50 or (before <= 40 and before % 2 == 0) then s.stats.attempts[player] = s.stats.attempts[player] + 1 end
    local remaining = before - value
    if remaining < 0 or remaining == 1 or (remaining == 0 and not double) then
        s.stats.busts[player] = s.stats.busts[player] + 1
        s.stats.scored[player] = s.stats.scored[player] - s.turnscore
        s.remaining[player] = s.turnstart
        next_turn(s)
        return
    end
    s.stats.scored[player] = s.stats.scored[player] + value
    s.remaining[player] = remaining
    s.turnscore = s.turnscore + value
    s.turn[#s.turn + 1] = code
    if remaining == 0 then
        s.stats.hits[player] = s.stats.hits[player] + 1
        complete_turn(s, player)
        s.legs[player] = s.legs[player] + 1
        local set_over = s.legs[player] == tonumber(m.options.LEGS)
        if set_over then
            s.completed[#s.completed + 1] = {s.legs[1], s.legs[2], 0, 0}
            s.won[player] = s.won[player] + 1
        end
        if set_over and s.won[player] == tonumber(m.options.SETS) then
            s.winner = player
            return
        end
        if set_over then s.legs = {0, 0} end
        s.legnumber = s.legnumber + 1
        local first = side(m.options.FIRST)
        s.server = s.legnumber % 2 == 0 and first or other(first)
        local start = tonumber(m.options.START)
        s.remaining, s.turn = {start, start}, {}
        s.turnscore, s.turnstart = 0, start
    elseif #s.turn == 3 then
        complete_turn(s, player)
        next_turn(s)
    end
end
local function undo_event(m)
    if #m.history == 0 then score_error('nothing to undo') end
    local record = table.remove(m.history)
    if type(record) == 'table' then
        m.state = record
        return
    end
    local data = {string.unpack(string.rep('i4', #record // 4), record)}
    local s = m.state
    if data[1] == 2 then
        s.lineups[data[2]][data[3]] = data[4]
        s.subs[data[2]] = s.subs[data[2]] - 1
    elseif data[1] == 3 then
        s.timeouts[data[2]] = s.timeouts[data[2]] - 1
    else
        local winner, server = data[2], data[3]
        s.stats.points[winner] = s.stats.points[winner] - 1
        s.stats.served[server] = s.stats.served[server] - 1
        if winner == server then s.stats.servewins[server] = s.stats.servewins[server] - 1 end
        if data[4] == 1 then
            s.stats.opportunities[other(server)] = s.stats.opportunities[other(server)] - 1
            if winner ~= server then s.stats.converted[winner] = s.stats.converted[winner] - 1 end
        end
        if data[5] == 1 then
            s.stats.games[server] = s.stats.games[server] - 1
            if winner == server then
                s.stats.holds[winner] = s.stats.holds[winner] - 1
            else
                s.stats.breaks[winner] = s.stats.breaks[winner] - 1
            end
        end
        if data[17] == 1 then
            s.lineups = {{table.unpack(data, 19, 24)}, {table.unpack(data, 25, 30)}}
            s.subs, s.timeouts = {data[31], data[32]}, {data[33], data[34]}
        end
        if data[18] == 1 then
            local lineup = s.lineups[winner]
            local last = table.remove(lineup)
            table.insert(lineup, 1, last)
        end
        s.p, s.g, s.won = {data[6], data[7]}, {data[8], data[9]}, {data[10], data[11]}
        s.server, s.winner = data[12], 0
        while #s.completed > data[13] do table.remove(s.completed) end
        s.last, s.run = data[14], data[15]
        s.stats.runmax[winner] = data[16]
    end
end
local function event(m, command, args)
    local correct = (command == 'POINT' and rally_sports[m.sport]) or (command == 'ROLL' and m.sport == 'BOWLING') or
        (command == 'THROW' and m.sport == 'DARTS') or ((command == 'SUB' or command == 'TIMEOUT') and m.sport == 'VOLLEYBALL')
    if not correct then score_error('wrong event') end
    local events
    if command == 'POINT' then
        events = {}
        for index = 1, #args[1] do events[index] = args[1]:sub(index, index) end
    elseif command == 'SUB' or command == 'TIMEOUT' then
        events = {''}
    else
        events = args
    end
    for _, value in ipairs(events) do
        if m.state.winner ~= 0 then score_error('match over') end
        if command == 'POINT' then
            point_event(m, side(value))
        elseif command == 'ROLL' then
            local old = clone(m.state)
            roll_event(m.state, tonumber(value))
            m.history[#m.history + 1] = old
        elseif command == 'THROW' then
            local old = clone(m.state)
            dart_event(m, value)
            m.history[#m.history + 1] = old
        elseif command == 'SUB' then
            local player = side(args[1])
            local outgoing, incoming = tonumber(args[2]), tonumber(args[3])
            local lineup, position = m.state.lineups[player], nil
            for index, shirt in ipairs(lineup) do
                if shirt == outgoing then position = index end
            end
            if not position then score_error('player not on court') end
            if contains(lineup, incoming) then score_error('player already on court') end
            if m.state.subs[player] >= 6 then score_error('no substitutions left') end
            m.history[#m.history + 1] = pack_record({2, player, position, outgoing})
            lineup[position] = incoming
            m.state.subs[player] = m.state.subs[player] + 1
        else
            local player = side(args[1])
            if m.state.timeouts[player] >= 2 then score_error('no timeouts left') end
            m.history[#m.history + 1] = pack_record({3, player})
            m.state.timeouts[player] = m.state.timeouts[player] + 1
        end
    end
end
local function completed_text(record, winner)
    local a, b = record[1], record[2]
    if winner == 2 then a, b = b, a end
    local text = a .. '-' .. b
    if record[3] == 2 then return '[' .. text .. ']' end
    if record[3] == 1 then return text .. '(' .. record[4] .. ')' end
    return text
end
local function situation(m, player)
    local game, unit, finished = rally_outcome(m, player)
    if finished then return 'match point' end
    if unit then
        if m.sport == 'TENNIS' or m.sport == 'VOLLEYBALL' then return 'set point' end
        return 'game point'
    end
    if game then return player == rally_server(m) and 'game point' or 'break point' end
    return ''
end
local function score_line(m)
    local s = m.state
    if m.sport == 'BOWLING' then
        local parts, scores, cumulative = {m.id .. ': ' .. m.names[1]}, bowling_scores(s), 0
        for frame = 1, 10 do
            if #s.frames[frame] == 0 then break end
            local text = table.concat(s.marks[frame])
            if scores[frame] then
                cumulative = cumulative + scores[frame]
                text = text .. '(' .. cumulative .. ')'
            end
            parts[#parts + 1] = text
        end
        return table.concat(parts, ' ')
    end
    local names = {m.names[1], m.names[2]}
    if s.winner == 0 then
        local player = rally_sports[m.sport] and rally_server(m) or s.server
        names[player] = names[player] .. '*'
    end
    local parts = {m.id .. ': ' .. names[1] .. ' vs ' .. names[2]}
    if m.sport == 'DARTS' then
        append_all(parts, {'sets', pair_text(s.won), 'legs', pair_text(s.legs), 'score', pair_text(s.remaining)})
        if s.winner == 0 then
            if #s.turn > 0 then
                parts[#parts + 1] = 'turn'
                append_all(parts, s.turn)
            end
            local answer = checkout(s.remaining[s.server], 3 - #s.turn)
            if #answer > 0 then
                parts[#parts + 1] = 'checkout'
                append_all(parts, answer)
            end
        end
    else
        for _, record in ipairs(s.completed) do parts[#parts + 1] = completed_text(record) end
        if s.winner == 0 then
            if m.sport == 'TENNIS' then
                local mode = tennis_mode(m)
                if mode == 'SUPER' then
                    parts[#parts + 1] = '[' .. pair_text(s.p) .. ']'
                else
                    parts[#parts + 1] = pair_text(s.g)
                    if mode == 'TB' then
                        parts[#parts + 1] = pair_text(s.p)
                    elseif m.options.DEUCE == 'AD' and math.min(s.p[1], s.p[2]) >= 3 then
                        local label
                        if s.p[1] == s.p[2] then
                            label = '40-40'
                        elseif s.p[1] > s.p[2] then
                            label = 'AD-40'
                        else
                            label = '40-AD'
                        end
                        parts[#parts + 1] = label
                    else
                        local labels = {'0', '15', '30', '40'}
                        parts[#parts + 1] = labels[s.p[1] + 1] .. '-' .. labels[s.p[2] + 1]
                    end
                end
            else
                parts[#parts + 1] = pair_text(s.p)
                if m.sport == 'VOLLEYBALL' then append_all(parts, {'server', tostring(s.lineups[s.server][1])}) end
            end
            for player = 1, 2 do
                local label = situation(m, player)
                if label ~= '' then parts[#parts + 1] = '(' .. label .. ' ' .. m.names[player] .. ')' end
            end
        end
    end
    return table.concat(parts, ' ')
end
local function stats_lines(m)
    local s, output = m.state, {}
    local stats = s.stats
    if m.sport == 'BOWLING' then
        local strikes, spares, open = 0, 0, 0
        for frame = 1, 10 do
            for _, mark in ipairs(s.marks[frame]) do
                if mark == 'X' then strikes = strikes + 1 end
                if mark == '/' then spares = spares + 1 end
            end
            local rolls = s.frames[frame]
            if #rolls >= 2 and rolls[1] ~= 10 and rolls[1] + rolls[2] < 10 then open = open + 1 end
        end
        local future = clone(s)
        while future.winner == 0 do roll_event(future, future.standing) end
        return {m.id .. ' ' .. m.names[1] .. ': strikes ' .. strikes .. ' spares ' .. spares .. ' open ' .. open .. ' max ' .. total_bowling(future)}
    end
    for player = 1, 2 do
        local text
        if m.sport == 'DARTS' then
            local darts = stats.darts[player]
            local average = darts == 0 and 0 or (stats.scored[player] * 300) // darts
            text = 'darts ' .. darts .. ' average ' .. string.format('%d.%02d', average // 100, average % 100) ..
                ' busts ' .. stats.busts[player] .. ' high ' .. stats.high[player] .. ' tons ' .. stats.tons[player] ..
                ' 180s ' .. stats.maximums[player] .. ' doubles ' .. stats.hits[player] .. '/' .. stats.attempts[player]
        else
            text = 'points ' .. stats.points[player] .. ' serve ' .. stats.servewins[player] .. '/' .. stats.served[player] .. ' run ' .. stats.runmax[player]
            if m.sport == 'TENNIS' then
                text = text .. ' holds ' .. stats.holds[player] .. '/' .. stats.games[player] .. ' breaks ' .. stats.breaks[player] ..
                    ' break points ' .. stats.converted[player] .. '/' .. stats.opportunities[player]
            elseif m.sport == 'VOLLEYBALL' then
                text = text .. ' subs ' .. s.subs[player] .. ' timeouts ' .. s.timeouts[player] .. ' lineup ' .. table.concat(s.lineups[player], ',')
            end
        end
        output[#output + 1] = m.id .. ' ' .. m.names[player] .. ': ' .. text
    end
    return output
end
local function result_line(m)
    local s = m.state
    if s.winner == 0 then score_error('match not finished') end
    if m.sport == 'BOWLING' then return m.id .. ': ' .. m.names[1] .. ' ' .. total_bowling(s) end
    local records, winner = {}, s.winner
    for _, record in ipairs(s.completed) do records[#records + 1] = completed_text(record, winner) end
    return m.id .. ': ' .. m.names[winner] .. ' def. ' .. m.names[other(winner)] .. ' ' .. table.concat(records, ' ')
end
local matches = {}
local function execute(line)
    local tokens = {}
    for token in line:gmatch('%S+') do tokens[#tokens + 1] = token end
    local command = tokens[1]
    if command == 'MATCH' then
        if matches[tokens[2]] then score_error('duplicate match') end
        local m = create_match(tokens)
        matches[m.id] = m
        return {}
    end
    if command == 'CHECKOUT' then
        local answer = checkout(tonumber(tokens[2]))
        local text = #answer == 0 and 'none' or table.concat(answer, ' ')
        return {'checkout ' .. tokens[2] .. ': ' .. text}
    end
    if command == 'STANDINGS' then
        local totals, names = {}, {}
        for _, m in pairs(matches) do
            if m.sport ~= 'BOWLING' and m.state.winner ~= 0 then
                for player = 1, 2 do
                    local name = m.names[player]
                    if not totals[name] then
                        totals[name] = {0, 0}
                        names[#names + 1] = name
                    end
                    local index = player == m.state.winner and 1 or 2
                    totals[name][index] = totals[name][index] + 1
                end
            end
        end
        table.sort(names, function(a, b)
            if totals[a][1] ~= totals[b][1] then return totals[a][1] > totals[b][1] end
            if totals[a][2] ~= totals[b][2] then return totals[a][2] < totals[b][2] end
            return a < b
        end)
        local entries = {}
        for _, name in ipairs(names) do entries[#entries + 1] = name .. ' ' .. pair_text(totals[name]) end
        return {'standings: ' .. (#entries == 0 and 'none' or table.concat(entries, ', '))}
    end
    local m = matches[tokens[2]]
    if not m then score_error('unknown match') end
    if command == 'POINT' or command == 'ROLL' or command == 'THROW' or command == 'SUB' or command == 'TIMEOUT' then
        local args = {table.unpack(tokens, 3)}
        event(m, command, args)
    elseif command == 'UNDO' then
        undo_event(m)
    elseif command == 'SCORE' then
        return {score_line(m)}
    elseif command == 'STATS' then
        return stats_lines(m)
    elseif command == 'RESULT' then
        return {result_line(m)}
    end
    return {}
end
local count = tonumber(io.read('*l'))
for _ = 1, count do
    local ok, result = pcall(execute, io.read('*l'))
    if ok then
        for _, line in ipairs(result) do io.write(line, '\n') end
    else
        io.write('ERROR ', result, '\n')
    end
end
