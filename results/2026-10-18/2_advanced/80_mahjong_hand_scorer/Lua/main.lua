local tiles = require('tiles')
local decomposition = require('decomposition')
local yaku = require('yaku')
local scoring = require('scoring')
local shanten = require('shanten')
local wait_order = {'ryanmen', 'kanchan', 'penchan', 'shanpon', 'tanki', 'single', 'thirteen'}
local win_order = {'dealer_ron', 'dealer_tsumo', 'nondealer_ron', 'nondealer_tsumo'}
local function append(target, source) for _, value in ipairs(source) do target[#target + 1] = value end end
local function counter() return setmetatable({}, {__index = function() return 0 end}) end
local function keys(values) local result = {}; for key in pairs(values) do result[#result + 1] = key end; table.sort(result); return result end
local function set_size(values) local count = 0; for _ in pairs(values) do count = count + 1 end; return count end
local function block_key(block) if not block then return '' end; return table.concat(block, ',') end
local function names_text(entries, separator) local names = {}; for _, entry in ipairs(entries) do names[#names + 1] = entry.name end; return table.concat(names, separator) end
local function read_records(filename)
    local records = {}
    for line in io.lines('input/' .. filename) do
        local label, rest = line:match('^(%S+) (.*)$'); local fields = {}
        for item in rest:gmatch('%S+') do local key, value = item:match('^([^=]+)=(.*)$'); fields[key] = value end
        records[#records + 1] = {label = label, fields = fields}
    end
    return records
end
local function read_rules()
    local rules, order = {}, {}
    for _, record in ipairs(read_records('rules.txt')) do
        local values = {}; for key, value in pairs(record.fields) do if key == 'honba' then values[key] = tonumber(value) else values[key] = value == 'yes' end end
        rules[record.label], order[#order + 1] = values, record.label
    end
    return rules, order
end
local function meld(text)
    local result = {kind = text:sub(1, 1), tiles = tiles.parse(text:sub(2)), block = {}}
    if result.tiles then for _, tile in ipairs(result.tiles) do result.block[#result.block + 1] = tile.kind end; table.sort(result.block) end
    return result
end
local function valid_meld(m)
    local block = m.block
    if m.kind == 'C' then return #block == 3 and block[1] < 27 and block[1] % 9 <= 6 and block[2] == block[1] + 1 and block[3] == block[1] + 2 end
    if m.kind ~= 'P' and m.kind ~= 'K' and m.kind ~= 'A' then return false end
    if #block ~= (m.kind == 'P' and 3 or 4) then return false end
    for _, kind in ipairs(block) do if kind ~= block[1] then return false end end
    return true
end
local function situation(label, f, rules)
    local melds, flags = {}, {}
    if f.melds ~= '-' then for text in f.melds:gmatch('[^,]+') do melds[#melds + 1] = meld(text) end end
    if f.flags ~= '-' then for flag in f.flags:gmatch('[^,]+') do flags[flag] = true end end
    local closed, kans = true, 0
    for _, m in ipairs(melds) do if m.kind ~= 'A' then closed = false end; if m.kind == 'K' or m.kind == 'A' then kans = kans + 1 end end
    return {label = label, rule_name = f.rules, rules = rules[f.rules], hand = tiles.parse(f.hand), win = tiles.parse(f.win), melds = melds,
        dora = tiles.parse(f.dora), ura = tiles.parse(f.ura, true), discards = tiles.parse(f.discards, true), by = f.by, seat = f.seat,
        discarder = f['from'], round = f.round, seat_tile = tiles.wind_tiles[f.seat], round_tile = tiles.wind_tiles[f.round], flags = flags,
        closed = closed, riichi = flags.riichi or flags.double_riichi or false, kan_count = kans, honba = tonumber(f.honba), sticks = tonumber(f.sticks)}
end
local function prepare(s)
    s.winning_tile, s.hand_counts = s.win[1].kind, tiles.counts(s.hand)
    local concealed, meld_tiles = {}, {}; append(concealed, s.hand); append(concealed, s.win)
    for _, m in ipairs(s.melds) do append(meld_tiles, m.tiles) end
    s.concealed_counts, s.meld_counts = tiles.counts(concealed), tiles.counts(meld_tiles)
    s.all_tiles = {}; append(s.all_tiles, concealed); append(s.all_tiles, meld_tiles); s.all_counts = tiles.counts(s.all_tiles)
end
local function copy_error(values, rules)
    local reds = {0, 0, 0}
    for _, tile in ipairs(values) do if tile.red then reds[tile.kind // 9 + 1] = reds[tile.kind // 9 + 1] + 1 end end
    if not rules.red_fives then for _, count in ipairs(reds) do if count > 0 then return 'red five not allowed' end end end
    for index, count in ipairs(tiles.counts(values)) do if count >= 5 then return 'too many copies of ' .. tiles.name(index - 1) end end
    for index, count in ipairs(reds) do if count >= 2 then return 'too many copies of 0' .. tiles.suits:sub(index, index) end end
end
local function validate_situation(s)
    for _, field in ipairs({'hand', 'win', 'dora', 'ura', 'discards'}) do if s[field] == nil then return 'bad tile notation' end end
    for _, m in ipairs(s.melds) do if m.tiles == nil then return 'bad tile notation' end end
    if #s.win ~= 1 then return 'bad tile notation' end
    if #s.melds >= 5 then return 'bad meld' end
    for _, m in ipairs(s.melds) do if not valid_meld(m) then return 'bad meld' end end
    if #s.hand ~= 13 - 3 * #s.melds then return 'wrong tile count' end
    prepare(s)
    local observed = {}; append(observed, s.all_tiles); append(observed, s.dora); append(observed, s.ura); append(observed, s.discards)
    local failure = copy_error(observed, s.rules); if failure then return failure end
    if s.by == 'tsumo' and s.discarder ~= '-' or s.by == 'ron' and (s.discarder == '-' or s.discarder == s.seat) then return 'invalid discarder' end
    local flags = s.flags
    local valid = {riichi = s.closed, double_riichi = s.closed and not flags.riichi, ippatsu = s.riichi and not flags.rinshan,
        haitei = s.by == 'tsumo' and not flags.rinshan, houtei = s.by == 'ron' and not flags.chankan,
        rinshan = s.by == 'tsumo' and s.kan_count >= 1, chankan = s.by == 'ron',
        tenhou = s.seat == 'E' and s.by == 'tsumo' and #s.melds == 0 and set_size(flags) == 1,
        chiihou = s.seat ~= 'E' and s.by == 'tsumo' and #s.melds == 0 and set_size(flags) == 1}
    for _, flag in ipairs(yaku.flags) do if flags[flag] and not valid[flag] then return 'invalid flag ' .. flag end end
    if #s.dora ~= 1 + s.kan_count then return 'invalid dora indicators' end
    if s.riichi and #s.ura ~= #s.dora or not s.riichi and #s.ura > 0 then return 'invalid ura indicators' end
    if s.riichi and s.sticks == 0 then return 'invalid sticks' end
    if not decomposition.winning(s.concealed_counts, #s.melds) then return 'not a winning hand' end
end
local function waiting_hand(record, rules)
    local f = record.fields
    return {label = record.label, fields = f, rules = rules[f.rules], hand = tiles.parse(f.hand), dora = tiles.parse(f.dora),
        discards = tiles.parse(f.discards, true), visible = tiles.parse(f.visible, true)}
end
local function validate_waiting(hand)
    for _, field in ipairs({'hand', 'dora', 'discards', 'visible'}) do if hand[field] == nil then return 'bad tile notation' end end
    if #hand.hand ~= 13 then return 'wrong tile count' end
    local observed = {}; append(observed, hand.hand); append(observed, hand.dora); append(observed, hand.discards); append(observed, hand.visible)
    local failure = copy_error(observed, hand.rules)
    if not failure then hand.counts, hand.known_counts = tiles.counts(hand.hand), tiles.counts(observed) end
    return failure
end
local function candidate(form_type, pair, sets, chosen, form, wait)
    return {form_type = form_type, pair = pair, sets = sets, winning_block = chosen, form = form, wait = wait, yaku = {}, yakuman = {}, fu_items = {},
        multiplier = 0, han = 0, fu = 0, fu_total = 0, base = 0, dora = 0, aka = 0, ura = 0, category = 'none'}
end
local function candidates(s)
    local result, winning, counts = {}, s.winning_tile, s.concealed_counts
    for _, split in ipairs(decomposition.standard(counts, #s.melds)) do
        local blocks, choices, chosen_keys = {{split.pair, split.pair}}, {}, {}
        append(blocks, split.sets)
        for _, block in ipairs(blocks) do
            local contains = false; for _, kind in ipairs(block) do if kind == winning then contains = true end end
            local key = block_key(block)
            if contains and not chosen_keys[key] then chosen_keys[key] = true; choices[#choices + 1] = block end
        end
        for _, chosen in ipairs(choices) do
            local parts, marked = {'standard'}, false
            for _, block in ipairs(blocks) do
                local notation = tiles.block(block)
                if block_key(block) == block_key(chosen) and not marked then notation, marked = notation .. '*', true end
                parts[#parts + 1] = notation
            end
            for _, m in ipairs(s.melds) do parts[#parts + 1] = m.kind .. tiles.block(m.block) end
            result[#result + 1] = candidate('standard', split.pair, split.sets, chosen, table.concat(parts, ' '), decomposition.wait_shape('standard', chosen, winning, s.hand_counts))
        end
    end
    if #s.melds == 0 and decomposition.seven_pairs(counts) then
        local parts = {'chiitoitsu'}
        for kind = 0, 33 do if counts[kind + 1] > 0 then parts[#parts + 1] = tiles.block({kind, kind}) .. (kind == winning and '*' or '') end end
        result[#result + 1] = candidate('chiitoitsu', nil, {}, nil, table.concat(parts, ' '), 'tanki')
    end
    if #s.melds == 0 and decomposition.thirteen_orphans(counts) then
        local parts = {'kokushi'}
        for _, kind in ipairs(tiles.yaochuu_kinds) do local block = {}; for _ = 1, counts[kind + 1] do block[#block + 1] = kind end; parts[#parts + 1] = tiles.block(block) .. (kind == winning and '*' or '') end
        result[#result + 1] = candidate('kokushi', nil, {}, nil, table.concat(parts, ' '), decomposition.wait_shape('kokushi', nil, winning, s.hand_counts))
    end
    table.sort(result, function(a, b) return a.form < b.form end); return result
end
local function block_facts(s, c)
    local triplets, sequences, concealed_sequences = {}, {}, {}
    for _, block in ipairs(c.sets) do
        if block[1] == block[#block] then triplets[#triplets + 1] = {block = block, concealed = s.by == 'tsumo' or block_key(block) ~= block_key(c.winning_block), kan = false}
        else sequences[#sequences + 1], concealed_sequences[#concealed_sequences + 1] = block[1], block end
    end
    for _, m in ipairs(s.melds) do
        if m.kind == 'C' then sequences[#sequences + 1] = m.block[1]
        else triplets[#triplets + 1] = {block = m.block, concealed = m.kind == 'A', kan = m.kind == 'K' or m.kind == 'A'} end
    end
    return triplets, sequences, concealed_sequences
end
local function yakuman_names(s, c, kinds, triplets)
    local names, all_honor, all_terminal, all_green, suits = {}, true, true, true, {}
    for _, flag in ipairs({'tenhou', 'chiihou'}) do if s.flags[flag] then names[flag] = true end end
    for kind in pairs(kinds) do all_honor, all_terminal, all_green = all_honor and tiles.honor(kind), all_terminal and tiles.terminal(kind), all_green and tiles.green[kind] == true; suits[kind // 9] = true end
    if all_honor then names.tsuuiisou = true end; if all_terminal then names.chinroutou = true end; if all_green then names.ryuuiisou = true end
    if #s.melds == 0 and set_size(suits) == 1 and not suits[3] then
        local start; for suit in pairs(suits) do start = suit * 9 end
        local complete, pure = s.all_counts[start + 1] >= 3 and s.all_counts[start + 9] >= 3, true
        for rank = 2, 8 do if s.all_counts[start + rank] < 1 then complete = false end end
        for rank = 1, 9 do if s.hand_counts[start + rank] ~= ((rank == 1 or rank == 9) and 3 or 1) then pure = false end end
        if complete then names[pure and 'junsei_chuuren' or 'chuuren'] = true end
    end
    if c.form_type == 'kokushi' then names[c.wait == 'thirteen' and 'kokushi_13' or 'kokushi'] = true end
    if c.form_type == 'standard' then
        local hidden, kans, set = 0, 0, {}
        for _, triplet in ipairs(triplets) do if triplet.concealed then hidden = hidden + 1 end; if triplet.kan then kans = kans + 1 end; set[triplet.block[1]] = true end
        local dragons, winds = 0, 0
        for kind = 31, 33 do if set[kind] then dragons = dragons + 1 end end
        for kind = 27, 30 do if set[kind] then winds = winds + 1 end end
        if hidden == 4 then names[c.wait == 'tanki' and 'suuankou_tanki' or 'suuankou'] = true end
        if dragons == 3 then names.daisangen = true end
        if winds == 4 then names.daisuushii = true end
        if winds == 3 and c.pair >= 27 and c.pair <= 30 then names.shousuushii = true end
        if kans == 4 then names.suukantsu = true end
    end
    return names
end
local function ordinary_names(s, c, kinds, triplets, sequences, concealed_sequences)
    local names, simple, yaochuu, number_suits, honors = {}, true, true, {}, false
    for index = 1, 7 do local flag = yaku.flags[index]; if s.flags[flag] then names[flag] = true end end
    if s.closed and s.by == 'tsumo' then names.menzen_tsumo = true end
    for kind in pairs(kinds) do
        if tiles.yaochuu(kind) then simple = false else yaochuu = false end
        if kind < 27 then number_suits[kind // 9] = true else honors = true end
    end
    if simple and (s.closed or s.rules.open_tanyao) then names.tanyao = true end
    if yaochuu then names.honroutou = true end
    if set_size(number_suits) == 1 then names[honors and 'honitsu' or 'chinitsu'] = true end
    if c.form_type == 'chiitoitsu' then names.chiitoitsu = true end
    if c.form_type ~= 'standard' then return names end
    local pair = c.pair
    local yakuhai_pair = pair >= 31 or pair == s.seat_tile or pair == s.round_tile
    if s.closed and #s.melds == 0 and #concealed_sequences == 4 and not yakuhai_pair and c.wait == 'ryanmen' then names.pinfu = true end
    local repeated, paired, duplicate = counter(), 0, false
    for _, block in ipairs(concealed_sequences) do local key = block_key(block); repeated[key] = repeated[key] + 1 end
    for _, count in pairs(repeated) do paired = paired + count // 2; if count >= 2 then duplicate = true end end
    if s.closed and #concealed_sequences == 4 and paired == 2 then names.ryanpeikou = true elseif s.closed and duplicate then names.iipeikou = true end
    local set, sequence_set, hidden, kans = {}, {}, 0, 0
    for _, triplet in ipairs(triplets) do set[triplet.block[1]] = true; if triplet.concealed then hidden = hidden + 1 end; if triplet.kan then kans = kans + 1 end end
    for _, start in ipairs(sequences) do sequence_set[start] = true end
    for _, entry in ipairs({{31, 'haku'}, {32, 'hatsu'}, {33, 'chun'}, {s.seat_tile, 'jikaze'}, {s.round_tile, 'bakaze'}}) do if set[entry[1]] then names[entry[2]] = true end end
    if #triplets == 4 then names.toitoi = true end; if hidden == 3 then names.sanankou = true end
    for start = 0, 6 do if sequence_set[start] and sequence_set[start + 9] and sequence_set[start + 18] then names.sanshoku_doujun = true end end
    for number = 0, 8 do if set[number] and set[number + 9] and set[number + 18] then names.sanshoku_doukou = true end end
    for suit = 0, 2 do local start = suit * 9; if sequence_set[start] and sequence_set[start + 3] and sequence_set[start + 6] then names.ittsu = true end end
    local blocks = {{pair, pair}}; append(blocks, c.sets); for _, m in ipairs(s.melds) do blocks[#blocks + 1] = m.block end
    local contains_yaochuu = true
    for _, block in ipairs(blocks) do local found = false; for _, kind in ipairs(block) do if tiles.yaochuu(kind) then found = true end end; if not found then contains_yaochuu = false end end
    if #sequences > 0 and contains_yaochuu then names[honors and 'chanta' or 'junchan'] = true end
    if kans == 3 then names.sankantsu = true end
    local dragons = 0; for kind = 31, 33 do if set[kind] then dragons = dragons + 1 end end
    if dragons == 2 and pair >= 31 then names.shousangen = true end
    return names
end
local function evaluate_candidate(s, c)
    local kinds = {}; for index, count in ipairs(s.all_counts) do if count > 0 then kinds[index - 1] = true end end
    local triplets, sequences, concealed_sequences = block_facts(s, c)
    c.yakuman = yaku.yakuman(yakuman_names(s, c, kinds, triplets), s.rules.double_yakuman)
    if #c.yakuman > 0 then
        for _, entry in ipairs(c.yakuman) do c.multiplier = c.multiplier + entry.value end
        c.base, c.category = 8000 * c.multiplier, 'yakuman'; return c
    end
    local names = ordinary_names(s, c, kinds, triplets, sequences, concealed_sequences)
    c.yaku = yaku.ordinary(names, s.closed)
    for _, tile in ipairs(s.dora) do c.dora = c.dora + s.all_counts[tiles.next_dora(tile.kind) + 1] end
    for _, tile in ipairs(s.ura) do c.ura = c.ura + s.all_counts[tiles.next_dora(tile.kind) + 1] end
    for _, tile in ipairs(s.all_tiles) do if tile.red then c.aka = c.aka + 1 end end
    c.fu_items, c.fu_total, c.fu = scoring.fu_breakdown(c.form_type, c.pair, triplets, c.wait, s.closed, s.by, s.seat_tile, s.round_tile, names.pinfu == true)
    if #c.yaku > 0 then
        c.han = c.dora + c.aka + c.ura; for _, entry in ipairs(c.yaku) do c.han = c.han + entry.value end
        c.category, c.base = scoring.limit(c.han, c.fu, s.rules)
    end
    return c
end
local function evaluate_candidates(s) local result = candidates(s); for _, c in ipairs(result) do evaluate_candidate(s, c) end; return result end
local function best_candidate(values)
    local function better(a, b)
        if a.base ~= b.base then return a.base > b.base end
        local ay, by = #a.yakuman > 0, #b.yakuman > 0
        if ay ~= by then return ay end
        if not ay then if a.han ~= b.han then return a.han > b.han end; if a.fu ~= b.fu then return a.fu > b.fu end end
        return a.form < b.form
    end
    local best; for _, c in ipairs(values) do if c.base >= 1 and (best == nil or better(c, best)) then best = c end end; return best
end

local function candidate_line(c)
    local evaluation
    if #c.yakuman > 0 then evaluation = 'yakuman ' .. c.multiplier .. ' base ' .. c.base .. ' yaku ' .. names_text(c.yakuman, ',')
    elseif #c.yaku == 0 then evaluation = 'no_yaku'
    else evaluation = 'han ' .. c.han .. ' fu ' .. c.fu .. ' base ' .. c.base .. ' yaku ' .. names_text(c.yaku, ',') end
    return 'CANDIDATE ' .. c.form .. ' = ' .. c.wait .. ' ' .. evaluation
end
local function winning_lines(s, c)
    local lines = {'FORM ' .. c.form, 'WAIT ' .. c.wait}
    if #c.yakuman > 0 then
        for _, entry in ipairs(c.yakuman) do lines[#lines + 1] = 'YAKUMAN ' .. entry.name .. ' ' .. entry.value end
        lines[#lines + 1] = 'SCORE yakuman ' .. c.multiplier .. ' base ' .. c.base
    else
        for _, entry in ipairs(c.yaku) do lines[#lines + 1] = 'YAKU ' .. entry.name .. ' ' .. entry.value end
        lines[#lines + 1] = 'DORA dora ' .. c.dora .. ' aka ' .. c.aka .. ' ura ' .. c.ura
        for _, item in ipairs(c.fu_items) do lines[#lines + 1] = 'FU ' .. item.name .. ' ' .. item.value end
        lines[#lines + 1] = 'FU total ' .. c.fu_total .. ' ' .. c.fu
        lines[#lines + 1] = 'SCORE han ' .. c.han .. ' fu ' .. c.fu .. ' limit ' .. c.category .. ' base ' .. c.base
    end
    local ron, dealer, nondealer, points = scoring.payments(c.base, s.seat == 'E', s.by)
    if s.by == 'ron' then lines[#lines + 1] = 'PAY ron ' .. ron
    elseif s.seat == 'E' then lines[#lines + 1] = 'PAY tsumo all ' .. nondealer
    else lines[#lines + 1] = 'PAY tsumo dealer ' .. dealer .. ' nondealer ' .. nondealer end
    local honba, sticks = s.honba * s.rules.honba, s.sticks * 1000
    local gain = points + honba + sticks
    lines[#lines + 1] = 'BONUS honba ' .. honba .. ' sticks ' .. sticks; lines[#lines + 1] = 'TOTAL points ' .. points .. ' gain ' .. gain
    local delta = {E = 0, S = 0, W = 0, N = 0}
    if s.by == 'ron' then delta[s.discarder] = -ron - honba
    else for wind in tiles.winds:gmatch('.') do if wind ~= s.seat then delta[wind] = -(wind == 'E' and dealer or nondealer) - honba // 3 end end end
    delta[s.seat] = gain
    local changes = {}; for wind in tiles.winds:gmatch('.') do local value = delta[wind]; changes[#changes + 1] = wind .. ' ' .. (value > 0 and '+' .. value or tostring(value)) end
    lines[#lines + 1] = 'DELTA ' .. table.concat(changes, ' ')
    return lines, points
end
local function process_scores(records, rules, rule_order)
    local lines, summary, statistics, win_counts, wait_counts, han_counts, fu_counts, limit_counts, yaku_counts, rule_counts = {}, {'hand,han,fu,points,yaku'}, counter(), counter(), counter(), counter(), counter(), counter(), counter(), {}
    for _, name in ipairs(rule_order) do rule_counts[name] = counter() end
    local maximum, maximum_hand = 0, '-'
    for _, record in ipairs(records) do
        local s = situation(record.label, record.fields, rules)
        local per_rule = rule_counts[s.rule_name]; per_rule.hands = per_rule.hands + 1
        lines[#lines + 1] = 'HAND ' .. s.label
        local failure = validate_situation(s)
        if failure then
            statistics.errors = statistics.errors + 1; lines[#lines + 1] = 'ERROR ' .. failure; summary[#summary + 1] = s.label .. ',-,-,0,ERROR'
        else
            local waiting = decomposition.waiting_tiles(s.hand_counts, s.meld_counts, #s.melds)
            local waiting_names, waiting_set = {}, {}
            for _, kind in ipairs(waiting) do waiting_names[#waiting_names + 1] = tiles.name(kind); waiting_set[kind] = true end
            lines[#lines + 1] = 'WAITS ' .. table.concat(waiting_names, ' ')
            local evaluated, furiten = evaluate_candidates(s), false
            for _, c in ipairs(evaluated) do lines[#lines + 1] = candidate_line(c) end
            if s.by == 'ron' then for _, tile in ipairs(s.discards) do if waiting_set[tile.kind] then furiten = true end end end
            local best = best_candidate(evaluated)
            if furiten then statistics.furiten = statistics.furiten + 1; lines[#lines + 1] = 'RESULT furiten'; summary[#summary + 1] = s.label .. ',-,-,0,FURITEN'
            elseif best == nil then statistics.no_yaku = statistics.no_yaku + 1; lines[#lines + 1] = 'RESULT no_yaku'; summary[#summary + 1] = s.label .. ',-,-,0,NO_YAKU'
            else
                local report, points = winning_lines(s, best); append(lines, report)
                statistics.wins, statistics.points = statistics.wins + 1, statistics.points + points
                per_rule.wins, per_rule.points = per_rule.wins + 1, per_rule.points + points
                local group = (s.seat == 'E' and 'dealer_' or 'nondealer_') .. s.by
                win_counts[group], wait_counts[best.wait], limit_counts[best.category] = win_counts[group] + 1, wait_counts[best.wait] + 1, limit_counts[best.category] + 1
                local entries = #best.yakuman > 0 and best.yakuman or best.yaku
                for _, entry in ipairs(entries) do yaku_counts[entry.name] = yaku_counts[entry.name] + 1 end
                local han, fu
                if #best.yakuman > 0 then han, fu = 'Y' .. best.multiplier, '-'
                else han, fu = tostring(best.han), tostring(best.fu); han_counts[best.han], fu_counts[best.fu] = han_counts[best.han] + 1, fu_counts[best.fu] + 1 end
                summary[#summary + 1] = s.label .. ',' .. han .. ',' .. fu .. ',' .. points .. ',' .. names_text(entries, ';')
                if points > maximum then maximum, maximum_hand = points, s.label end
            end
        end
    end
    lines[#lines + 1] = 'STATS hands ' .. #records .. ' wins ' .. statistics.wins .. ' furiten ' .. statistics.furiten .. ' no_yaku ' .. statistics.no_yaku .. ' errors ' .. statistics.errors
    local win_parts, wait_parts = {}, {}
    for _, name in ipairs(win_order) do win_parts[#win_parts + 1] = name .. ' ' .. win_counts[name] end
    for _, name in ipairs(wait_order) do wait_parts[#wait_parts + 1] = name .. ' ' .. wait_counts[name] end
    lines[#lines + 1] = 'WINS ' .. table.concat(win_parts, ' '); lines[#lines + 1] = 'WAIT_COUNT ' .. table.concat(wait_parts, ' ')
    for _, han in ipairs(keys(han_counts)) do lines[#lines + 1] = 'HAN_COUNT ' .. han .. ' ' .. han_counts[han] end
    for _, fu in ipairs(keys(fu_counts)) do lines[#lines + 1] = 'FU_COUNT ' .. fu .. ' ' .. fu_counts[fu] end
    for _, category in ipairs(yaku.categories) do lines[#lines + 1] = 'LIMIT ' .. category .. ' ' .. limit_counts[category] end
    for _, definitions in ipairs({yaku.ordinary_table, yaku.yakuman_table}) do
        for _, entry in ipairs(definitions) do local name = entry[1]; if yaku_counts[name] > 0 then lines[#lines + 1] = 'YAKU_COUNT ' .. name .. ' ' .. yaku_counts[name] end end
    end
    lines[#lines + 1] = 'POINTS total ' .. statistics.points .. ' max ' .. maximum .. ' hand ' .. maximum_hand
    for _, name in ipairs(rule_order) do local counts = rule_counts[name]; lines[#lines + 1] = 'RULE ' .. name .. ' hands ' .. counts.hands .. ' wins ' .. counts.wins .. ' points ' .. counts.points end
    return lines, summary
end
local function hypothetical(hand, winning, method, rules)
    local fields = {}; for key, value in pairs(hand.fields) do fields[key] = value end
    fields.melds, fields.win, fields.by = '-', tiles.name(winning), method
    fields['from'] = method == 'tsumo' and '-' or fields.seat == 'E' and 'S' or 'E'
    fields.flags, fields.ura, fields.honba, fields.sticks = fields.riichi == 'yes' and 'riichi' or '-', '-', '0', '0'
    local s = situation(hand.label, fields, rules); prepare(s); return s
end
local function acceptance(hand, current)
    local counts, result = {table.unpack(hand.counts)}, {}
    for kind = 0, 33 do
        if counts[kind + 1] <= 3 then
            counts[kind + 1] = counts[kind + 1] + 1
            local standard, seven, orphans = shanten.numbers(counts)
            counts[kind + 1] = counts[kind + 1] - 1
            if math.min(standard, seven, orphans) < current then result[#result + 1] = {kind = kind, remaining = 4 - hand.known_counts[kind + 1]} end
        end
    end
    return result
end
local function tenpai_lines(hand, waiting, furiten, rules)
    local lines, best = {}, {}
    for _, wait in ipairs(waiting) do
        local results = {}
        for _, method in ipairs({'ron', 'tsumo'}) do
            if method == 'ron' and furiten then results[method] = 'furiten'
            else
                local s = hypothetical(hand, wait.kind, method, rules)
                local c = best_candidate(evaluate_candidates(s))
                if not c then results[method] = 'no_yaku'
                else
                    local _, _, _, points = scoring.payments(c.base, s.seat == 'E', method)
                    results[method] = tostring(points)
                    if best[method] == nil or points > best[method].points then best[method] = {kind = wait.kind, points = points} end
                end
            end
        end
        lines[#lines + 1] = 'WAIT ' .. tiles.name(wait.kind) .. ' left ' .. wait.remaining .. ' ron ' .. results.ron .. ' tsumo ' .. results.tsumo
    end
    local choices = {}
    for _, method in ipairs({'ron', 'tsumo'}) do local value = best[method]; choices[method] = value and tiles.name(value.kind) .. ' ' .. value.points or 'none' end
    lines[#lines + 1] = 'BEST ron ' .. choices.ron .. ' tsumo ' .. choices.tsumo
    return lines
end
local function process_waits(records, rules)
    local lines, statistics, shanten_counts = {}, counter(), counter()
    for _, record in ipairs(records) do
        local hand = waiting_hand(record, rules)
        lines[#lines + 1] = 'HAND ' .. hand.label
        local failure = validate_waiting(hand)
        if failure then statistics.errors = statistics.errors + 1; lines[#lines + 1] = 'ERROR ' .. failure
        else
            local standard, seven, orphans = shanten.numbers(hand.counts)
            local current = math.min(standard, seven, orphans); shanten_counts[current] = shanten_counts[current] + 1
            lines[#lines + 1] = 'SHANTEN standard ' .. standard .. ' chiitoitsu ' .. seven .. ' kokushi ' .. orphans
            local accepted, total = acceptance(hand, current), 0
            for _, wait in ipairs(accepted) do total = total + wait.remaining end
            if current ~= 0 then
                local suffix = {}; for _, wait in ipairs(accepted) do suffix[#suffix + 1] = ' ' .. tiles.name(wait.kind) .. ':' .. wait.remaining end
                lines[#lines + 1] = 'ACCEPT kinds ' .. #accepted .. ' tiles ' .. total .. table.concat(suffix)
            else
                statistics.tenpai = statistics.tenpai + 1
                local discarded, furiten = {}, false
                for _, tile in ipairs(hand.discards) do discarded[tile.kind] = true end
                for _, wait in ipairs(accepted) do if discarded[wait.kind] then furiten = true end end
                if furiten then statistics.furiten = statistics.furiten + 1 end
                lines[#lines + 1] = 'TENPAI kinds ' .. #accepted .. ' tiles ' .. total .. ' furiten ' .. (furiten and 'yes' or 'no')
                append(lines, tenpai_lines(hand, accepted, furiten, rules))
            end
        end
    end
    lines[#lines + 1] = 'STATS hands ' .. #records .. ' errors ' .. statistics.errors .. ' tenpai ' .. statistics.tenpai .. ' furiten ' .. statistics.furiten
    for number = 0, 6 do lines[#lines + 1] = 'SHANTEN_COUNT ' .. number .. ' ' .. shanten_counts[number] end
    return lines
end

local rules, rule_order = read_rules()
local score_lines, summary = process_scores(read_records('hands.txt'), rules, rule_order)
local wait_lines = process_waits(read_records('waits.txt'), rules)
os.execute('mkdir -p output')
for filename, lines in pairs({['scores.txt'] = score_lines, ['waits.txt'] = wait_lines, ['summary.csv'] = summary}) do
    local file = assert(io.open('output/' .. filename, 'w')); file:write(table.concat(lines, '\n'), '\n'); file:close()
end
