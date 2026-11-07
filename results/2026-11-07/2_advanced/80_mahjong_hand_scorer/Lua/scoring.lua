local tiles = require('tiles')
local scoring = {}
function scoring.triplet_fu(block, concealed, kan)
    local name, value
    if kan then name, value = concealed and 'closed_kan' or 'open_kan', concealed and 16 or 8
    else name, value = concealed and 'closed_triplet' or 'open_triplet', concealed and 4 or 2 end
    return {name = name .. ' ' .. tiles.block(block), value = value * (tiles.yaochuu(block[1]) and 2 or 1)}
end
function scoring.fu_breakdown(form, pair, triplets, wait, closed, method, seat, round_wind, pinfu)
    if form == 'chiitoitsu' then return {{name = 'chiitoitsu', value = 25}}, 25, 25 end
    local items = {{name = 'base', value = 20}}
    if closed and method == 'ron' then items[#items + 1] = {name = 'closed_ron', value = 10} end
    if method == 'tsumo' and not pinfu then items[#items + 1] = {name = 'tsumo', value = 2} end
    local pair_value = (pair >= 31 and 2 or 0) + (pair == seat and 2 or 0) + (pair == round_wind and 2 or 0)
    if pair_value > 0 then items[#items + 1] = {name = 'pair ' .. tiles.block({pair, pair}), value = pair_value} end
    for _, triplet in ipairs(triplets) do items[#items + 1] = scoring.triplet_fu(triplet.block, triplet.concealed, triplet.kan) end
    if wait == 'kanchan' or wait == 'penchan' or wait == 'tanki' then items[#items + 1] = {name = 'wait ' .. wait, value = 2} end
    local total = 0; for _, item in ipairs(items) do total = total + item.value end
    if not closed and total == 20 then items[#items + 1] = {name = 'open_pinfu', value = 10}; total = total + 10 end
    return items, total, (total + 9) // 10 * 10
end
function scoring.limit(han, fu, rules)
    if han >= 13 and rules.kazoe_yakuman then return 'kazoe_yakuman', 8000 end
    if han >= 11 then return 'sanbaiman', 6000 end
    if han >= 8 then return 'baiman', 4000 end
    if han >= 6 then return 'haneman', 3000 end
    local base = fu * (1 << (han + 2))
    if han == 5 or base >= 2000 or rules.kiriage and base == 1920 then return 'mangan', 2000 end
    return 'none', base
end
function scoring.round_hundred(value) return (value + 99) // 100 * 100 end
function scoring.payments(base, dealer, method)
    if method == 'ron' then local ron = scoring.round_hundred(base * (dealer and 6 or 4)); return ron, 0, 0, ron end
    if dealer then local payment = scoring.round_hundred(base * 2); return 0, 0, payment, payment * 3 end
    local dealer_payment, nondealer = scoring.round_hundred(base * 2), scoring.round_hundred(base)
    return 0, dealer_payment, nondealer, dealer_payment + 2 * nondealer
end
return scoring
