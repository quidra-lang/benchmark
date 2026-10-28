function triplet_fu(kinds, concealed, kan)
    if kan
        kind, value = concealed ? ("closed_kan", 16) : ("open_kan", 8)
    else
        kind, value = concealed ? ("closed_triplet", 4) : ("open_triplet", 2)
    end
    return kind * " " * block_notation(kinds), value * (is_yaochuu(kinds[1]) ? 2 : 1)
end

function fu_breakdown(form, pair, triplets, wait, closed, method, seat, round_wind, pinfu)
    form == "chiitoitsu" && return [("chiitoitsu", 25)], 25, 25
    items = [("base", 20)]
    closed && method == "ron" && push!(items, ("closed_ron", 10))
    method == "tsumo" && !pinfu && push!(items, ("tsumo", 2))
    pair_value = 2 * (Int(pair >= 31) + Int(pair == seat) + Int(pair == round_wind))
    pair_value > 0 && push!(items, ("pair " * block_notation((pair, pair)), pair_value))
    for (kinds, concealed, kan) in triplets
        push!(items, triplet_fu(kinds, concealed, kan))
    end
    wait in ("kanchan", "penchan", "tanki") && push!(items, ("wait " * wait, 2))
    total = sum(item[2] for item in items)
    if !closed && total == 20
        push!(items, ("open_pinfu", 10))
        total += 10
    end
    return items, total, cld(total, 10) * 10
end

function score_limit(han, fu, rules)
    han >= 13 && rules["kazoe_yakuman"] && return "kazoe_yakuman", 8000
    han >= 11 && return "sanbaiman", 6000
    han >= 8 && return "baiman", 4000
    han >= 6 && return "haneman", 3000
    base = fu * 2^(han + 2)
    (han == 5 || base >= 2000 || rules["kiriage"] && base == 1920) && return "mangan", 2000
    return "none", base
end

round_hundred(value) = cld(value, 100) * 100
function payments(base, dealer, method)
    if method == "ron"
        ron = round_hundred(base * (dealer ? 6 : 4))
        return (ron=ron, dealer=0, nondealer=0, points=ron)
    elseif dealer
        nondealer = round_hundred(base * 2)
        return (ron=0, dealer=0, nondealer=nondealer, points=3 * nondealer)
    end
    dealer_payment, nondealer = round_hundred(base * 2), round_hundred(base)
    return (ron=0, dealer=dealer_payment, nondealer=nondealer, points=dealer_payment + 2 * nondealer)
end
