include("tiles.jl")
include("decomposition.jl")
include("yaku.jl")
include("scoring.jl")
include("shanten.jl")

const WAIT_ORDER = ("ryanmen", "kanchan", "penchan", "shanpon", "tanki", "single", "thirteen")
const WIN_ORDER = ("dealer_ron", "dealer_tsumo", "nondealer_ron", "nondealer_tsumo")
report_count(counts, key) = get(counts, key, 0)
function add_report!(counts, key, amount=1)
    counts[key] = report_count(counts, key) + amount
end
report_pairs(keys, counts) = join(("$key $(report_count(counts, key))" for key in keys), " ")

function read_records(filename)
    records = Tuple{String,Dict{String,String}}[]
    for line in readlines(joinpath("input", filename))
        fields = split(line, ' ')
        values = Dict{String,String}()
        for field in fields[2:end]
            key, value = split(field, '='; limit=2)
            values[String(key)] = String(value)
        end
        push!(records, (String(fields[1]), values))
    end
    return records
end

function read_rules()
    rules = Dict{String,Dict{String,Any}}()
    names = String[]
    for (name, fields) in read_records("rules.txt")
        push!(names, name)
        rules[name] = Dict{String,Any}(key => key == "honba" ? parse(Int, value) : value == "yes" for (
            key,
            value
        ) in fields)
    end
    return rules, names
end

function parse_meld(text)
    kind = text[1:1]
    tiles = parse_tiles(text[2:end])
    block = tiles === nothing ? Int[] : sort!([tile.kind for tile in tiles])
    return (; kind, tiles, block)
end

function valid_meld(meld)
    block = meld.block
    if meld.kind == "C"
        return length(block) == 3 && block[1] < 27 && block[1] % 9 <= 6 && block == collect(block[1]:block[1] + 2)
    end
    meld.kind in ("P", "K", "A") || return false
    return length(block) == (meld.kind == "P" ? 3 : 4) && length(Set(block)) == 1
end

function parse_situation(label, fields, rules)
    melds = fields["melds"] == "-" ? NamedTuple[] : parse_meld.(String.(split(fields["melds"], ',')))
    flags = fields["flags"] == "-" ? Set{String}() : Set(String.(split(fields["flags"], ',')))
    return (
        label=label,
        rule_name=fields["rules"],
        rules=rules[fields["rules"]],
        hand=parse_tiles(fields["hand"]),
        win=parse_tiles(fields["win"]),
        melds=melds,
        dora=parse_tiles(fields["dora"]),
        ura=parse_tiles(fields["ura"]; allow_empty=true),
        discards=parse_tiles(fields["discards"]; allow_empty=true),
        by=fields["by"],
        seat=fields["seat"],
        discarder=fields["from"],
        round=fields["round"],
        seat_tile=WIND_TILES[fields["seat"]],
        round_tile=WIND_TILES[fields["round"]],
        flags=flags,
        closed=all(meld -> meld.kind == "A", melds),
        riichi=any(flag -> flag in flags, ("riichi", "double_riichi")),
        kan_count=count(meld -> meld.kind in ("K", "A"), melds),
        honba=parse(Int, fields["honba"]),
        sticks=parse(Int, fields["sticks"])
    )
end

function prepare_situation(situation)
    meld_tiles = MahjongTile[]
    for meld in situation.melds
        append!(meld_tiles, meld.tiles)
    end
    all_tiles = vcat(situation.hand, situation.win, meld_tiles)
    return (
        ; situation...,
        winning_tile=situation.win[1].kind,
        hand_counts=tile_counts(situation.hand),
        concealed_counts=tile_counts(vcat(situation.hand, situation.win)),
        meld_counts=tile_counts(meld_tiles),
        all_tiles=all_tiles,
        all_counts=tile_counts(all_tiles)
    )
end

function copy_error(all_tiles, rules)
    reds = zeros(Int, 3)
    for tile in all_tiles
        tile.red && (reds[tile.kind ÷ 9 + 1] += 1)
    end
    !rules["red_fives"] && any(>(0), reds) && return "red five not allowed"
    for (index, count) in enumerate(tile_counts(all_tiles))
        count >= 5 && return "too many copies of " * tile_name(index - 1)
    end
    for (index, count) in enumerate(reds)
        count >= 2 && return "too many copies of 0" * string(TILE_SUITS[index])
    end
    return nothing
end

function validate_situation(situation)
    values = Any[situation.hand, situation.win, situation.dora, situation.ura, situation.discards]
    append!(values, [meld.tiles for meld in situation.melds])
    (any(isnothing, values) || length(situation.win) != 1) && return "bad tile notation", situation
    (length(situation.melds) >= 5 || any(
        meld -> !valid_meld(meld),
        situation.melds
    )) && return "bad meld", situation
    length(situation.hand) != 13 - 3 * length(situation.melds) && return "wrong tile count", situation
    situation = prepare_situation(situation)
    observed = vcat(situation.all_tiles, situation.dora, situation.ura, situation.discards)
    error = copy_error(observed, situation.rules)
    error !== nothing && return error, situation
    ((situation.by == "tsumo" && situation.discarder != "-") || (situation.by == "ron" && situation.discarder in (
        "-",
        situation.seat
    ))) && return "invalid discarder", situation
    flags = situation.flags
    valid_flags = Dict(
        "riichi" => situation.closed,
        "double_riichi" => situation.closed && !("riichi" in flags),
        "ippatsu" => situation.riichi && !("rinshan" in flags),
        "haitei" => situation.by == "tsumo" && !("rinshan" in flags),
        "houtei" => situation.by == "ron" && !("chankan" in flags),
        "rinshan" => situation.by == "tsumo" && situation.kan_count >= 1,
        "chankan" => situation.by == "ron",
        "tenhou" => situation.seat == "E" && situation.by == "tsumo" && isempty(situation.melds) && flags == Set(["tenhou"]),
        "chiihou" => situation.seat != "E" && situation.by == "tsumo" && isempty(situation.melds) && flags == Set(["chiihou"])
    )
    for flag in SITUATION_FLAGS
        flag in flags && !valid_flags[flag] && return "invalid flag $flag", situation
    end
    length(situation.dora) != 1 + situation.kan_count && return "invalid dora indicators", situation
    ((situation.riichi && length(situation.ura) != length(situation.dora)) || (!situation.riichi && !isempty(situation.ura))) && return "invalid ura indicators", situation
    situation.riichi && situation.sticks == 0 && return "invalid sticks", situation
    !winning_form(
        situation.concealed_counts,
        length(situation.melds)
    ) && return "not a winning hand", situation
    return nothing, situation
end

function new_candidate(form_type, pair, sets, winning_block, form, wait)
    return (
        ; form_type,
        pair,
        sets,
        winning_block,
        form,
        wait,
        yaku=Tuple{String,Int}[],
        yakuman=Tuple{String,Int}[],
        fu_items=Tuple{String,Int}[],
        multiplier=0,
        han=0,
        fu=0,
        fu_total=0,
        base=0,
        dora=0,
        aka=0,
        ura=0,
        category="none"
    )
end

function make_candidates(situation)
    result = NamedTuple[]
    winning, counts = situation.winning_tile, situation.concealed_counts
    for decomposition in standard_decompositions(counts, length(situation.melds))
        pair, sets = decomposition.pair, decomposition.sets
        blocks = Any[(pair, pair)]
        append!(blocks, sets)
        choices = unique([block for block in blocks if winning in block])
        for chosen in choices
            parts, marked = ["standard"], false
            for block in blocks
                notation = block_notation(block)
                if block == chosen && !marked
                    notation *= "*"
                    marked = true
                end
                push!(parts, notation)
            end
            append!(parts, [meld.kind * block_notation(meld.block) for meld in situation.melds])
            wait = wait_shape("standard", chosen, winning, situation.hand_counts)
            push!(result, new_candidate("standard", pair, sets, chosen, join(parts, " "), wait))
        end
    end
    if isempty(situation.melds) && seven_pairs(counts)
        parts = ["chiitoitsu"]
        for kind in 0:33
            counts[kind + 1] > 0 && push!(parts, block_notation((kind, kind)) * (kind == winning ? "*" : ""))
        end
        push!(result, new_candidate("chiitoitsu", nothing, Any[], nothing, join(parts, " "), "tanki"))
    end
    if isempty(situation.melds) && thirteen_orphans(counts)
        parts = ["kokushi"]
        for kind in YAOCHUU
            push!(parts, block_notation(fill(kind, counts[kind + 1])) * (kind == winning ? "*" : ""))
        end
        wait = wait_shape("kokushi", nothing, winning, situation.hand_counts)
        push!(result, new_candidate("kokushi", nothing, Any[], nothing, join(parts, " "), wait))
    end
    return sort!(result; by=candidate -> candidate.form)
end

function block_facts(situation, candidate)
    triplets, sequences, concealed_sequences = Any[], Int[], Any[]
    for block in candidate.sets
        if block[1] == block[end]
            concealed = situation.by == "tsumo" || block != candidate.winning_block
            push!(triplets, (block, concealed, false))
        else
            push!(sequences, block[1])
            push!(concealed_sequences, block)
        end
    end
    for meld in situation.melds
        if meld.kind == "C"
            push!(sequences, meld.block[1])
        else
            push!(triplets, (meld.block, meld.kind == "A", meld.kind in ("K", "A")))
        end
    end
    return triplets, sequences, concealed_sequences
end

function yakuman_names(situation, candidate, kinds, triplets)
    names = intersect(situation.flags, Set(["tenhou", "chiihou"]))
    all(is_honor, kinds) && push!(names, "tsuuiisou")
    all(is_terminal, kinds) && push!(names, "chinroutou")
    issubset(kinds, GREEN_TILES) && push!(names, "ryuuiisou")
    suits = Set(kind ÷ 9 for kind in kinds)
    if isempty(situation.melds) && length(suits) == 1 && !any(is_honor, kinds)
        start = first(suits) * 9 + 1
        counts = situation.all_counts[start:start + 8]
        if counts[1] >= 3 && counts[9] >= 3 && all(>=(1), counts[2:8])
            initial = situation.hand_counts[start:start + 8]
            push!(names, initial == [3, 1, 1, 1, 1, 1, 1, 1, 3] ? "junsei_chuuren" : "chuuren")
        end
    end
    candidate.form_type == "kokushi" && push!(names, candidate.wait == "thirteen" ? "kokushi_13" : "kokushi")
    if candidate.form_type == "standard"
        concealed = count(triplet -> triplet[2], triplets)
        triplet_kinds = Set(block[1] for (block, _, _) in triplets)
        dragons, winds = length(intersect(triplet_kinds, Set(31:33))), length(intersect(
            triplet_kinds,
            Set(27:30)
        ))
        concealed == 4 && push!(names, candidate.wait == "tanki" ? "suuankou_tanki" : "suuankou")
        dragons == 3 && push!(names, "daisangen")
        winds == 4 && push!(names, "daisuushii")
        winds == 3 && 27 <= candidate.pair <= 30 && push!(names, "shousuushii")
        count(triplet -> triplet[3], triplets) == 4 && push!(names, "suukantsu")
    end
    return names
end

function ordinary_names(situation, candidate, kinds, triplets, sequences, concealed_sequences)
    names = intersect(situation.flags, Set(SITUATION_FLAGS[1:7]))
    situation.closed && situation.by == "tsumo" && push!(names, "menzen_tsumo")
    all(
        kind -> !is_yaochuu(kind),
        kinds
    ) && (situation.closed || situation.rules["open_tanyao"]) && push!(names, "tanyao")
    all(is_yaochuu, kinds) && push!(names, "honroutou")
    number_suits = Set(kind ÷ 9 for kind in kinds if kind < 27)
    honors = any(is_honor, kinds)
    length(number_suits) == 1 && push!(names, honors ? "honitsu" : "chinitsu")
    candidate.form_type == "chiitoitsu" && push!(names, "chiitoitsu")
    candidate.form_type != "standard" && return names
    pair = candidate.pair
    yakuhai_pair = pair >= 31 || pair in (situation.seat_tile, situation.round_tile)
    situation.closed && isempty(situation.melds) && length(concealed_sequences) == 4 && !yakuhai_pair && candidate.wait == "ryanmen" && push!(
        names,
        "pinfu"
    )
    repeated = Dict{Any,Int}()
    for block in concealed_sequences
        add_report!(repeated, block)
    end
    ryanpeikou = situation.closed && length(concealed_sequences) == 4 && sum((count ÷ 2 for count in values(repeated)); init=0) == 2
    if ryanpeikou
        push!(names, "ryanpeikou")
    elseif situation.closed && any(>=(2), values(repeated))
        push!(names, "iipeikou")
    end
    triplet_kinds = Set(block[1] for (block, _, _) in triplets)
    for (kind, name) in (
        (31, "haku"),
        (32, "hatsu"),
        (33, "chun"),
        (situation.seat_tile, "jikaze"),
        (situation.round_tile, "bakaze")
    )
        kind in triplet_kinds && push!(names, name)
    end
    length(triplets) == 4 && push!(names, "toitoi")
    count(triplet -> triplet[2], triplets) == 3 && push!(names, "sanankou")
    sequence_kinds = Set(sequences)
    any(start -> all(suit -> start + suit * 9 in sequence_kinds, 0:2), 0:6) && push!(names, "sanshoku_doujun")
    any(
        number -> all(suit -> number + suit * 9 in triplet_kinds, 0:2),
        0:8
    ) && push!(names, "sanshoku_doukou")
    any(suit -> all(start -> suit * 9 + start in sequence_kinds, (0, 3, 6)), 0:2) && push!(names, "ittsu")
    blocks = Any[(pair, pair)]
    append!(blocks, candidate.sets)
    append!(blocks, [meld.block for meld in situation.melds])
    !isempty(sequences) && all(
        block -> any(is_yaochuu, block),
        blocks
    ) && push!(names, honors ? "chanta" : "junchan")
    count(triplet -> triplet[3], triplets) == 3 && push!(names, "sankantsu")
    length(intersect(triplet_kinds, Set(31:33))) == 2 && pair >= 31 && push!(names, "shousangen")
    return names
end

function evaluate_candidate(situation, candidate)
    kinds = Set(index - 1 for (index, count) in enumerate(situation.all_counts) if count > 0)
    triplets, sequences, concealed_sequences = block_facts(situation, candidate)
    names = yakuman_names(situation, candidate, kinds, triplets)
    yakuman = ordered_yakuman(names, situation.rules["double_yakuman"])
    if !isempty(yakuman)
        multiplier = sum(item[2] for item in yakuman)
        return (
            ; candidate...,
            yakuman=yakuman,
            multiplier=multiplier,
            base=8000 * multiplier,
            category="yakuman"
        )
    end
    names = ordinary_names(situation, candidate, kinds, triplets, sequences, concealed_sequences)
    yaku = ordered_yaku(names, situation.closed)
    dora = sum((situation.all_counts[next_dora(tile.kind) + 1] for tile in situation.dora); init=0)
    ura = sum((situation.all_counts[next_dora(tile.kind) + 1] for tile in situation.ura); init=0)
    aka = count(tile -> tile.red, situation.all_tiles)
    fu_items, fu_total, fu = fu_breakdown(
        candidate.form_type,
        candidate.pair,
        triplets,
        candidate.wait,
        situation.closed,
        situation.by,
        situation.seat_tile,
        situation.round_tile,
        "pinfu" in names
    )
    han, category, base = 0, "none", 0
    if !isempty(yaku)
        han = sum(item[2] for item in yaku) + dora + aka + ura
        category, base = score_limit(han, fu, situation.rules)
    end
    return (
        ; candidate...,
        yaku=yaku,
        dora=dora,
        ura=ura,
        aka=aka,
        fu_items=fu_items,
        fu_total=fu_total,
        fu=fu,
        han=han,
        category=category,
        base=base
    )
end

evaluate_candidates(situation) = [evaluate_candidate(
    situation,
    candidate
) for candidate in make_candidates(situation)]

function best_candidate(candidates)
    eligible = [candidate for candidate in candidates if candidate.base >= 1]
    isempty(eligible) && return nothing
    return argmin(
        candidate -> (
            -candidate.base,
            -Int(!isempty(candidate.yakuman)),
            isempty(candidate.yakuman) ? -candidate.han : 0,
            isempty(candidate.yakuman) ? -candidate.fu : 0,
            candidate.form
        ),
        eligible
    )
end

function candidate_line(candidate)
    if !isempty(candidate.yakuman)
        evaluation = "yakuman $(candidate.multiplier) base $(candidate.base) yaku " * join(
            (name for (name, _) in candidate.yakuman),
            ","
        )
    elseif isempty(candidate.yaku)
        evaluation = "no_yaku"
    else
        evaluation = "han $(candidate.han) fu $(candidate.fu) base $(candidate.base) yaku " * join(
            (name for (name, _) in candidate.yaku),
            ","
        )
    end
    return "CANDIDATE $(candidate.form) = $(candidate.wait) $evaluation"
end

function winning_lines(situation, candidate)
    lines = ["FORM " * candidate.form, "WAIT " * candidate.wait]
    if !isempty(candidate.yakuman)
        append!(lines, ["YAKUMAN $name $multiplier" for (name, multiplier) in candidate.yakuman])
        push!(lines, "SCORE yakuman $(candidate.multiplier) base $(candidate.base)")
    else
        append!(lines, ["YAKU $name $han" for (name, han) in candidate.yaku])
        push!(lines, "DORA dora $(candidate.dora) aka $(candidate.aka) ura $(candidate.ura)")
        append!(lines, ["FU $item $value" for (item, value) in candidate.fu_items])
        push!(lines, "FU total $(candidate.fu_total) $(candidate.fu)")
        push!(
            lines,
            "SCORE han $(candidate.han) fu $(candidate.fu) limit $(candidate.category) base $(candidate.base)"
        )
    end
    payment = payments(candidate.base, situation.seat == "E", situation.by)
    if situation.by == "ron"
        push!(lines, "PAY ron $(payment.ron)")
    elseif situation.seat == "E"
        push!(lines, "PAY tsumo all $(payment.nondealer)")
    else
        push!(lines, "PAY tsumo dealer $(payment.dealer) nondealer $(payment.nondealer)")
    end
    honba, sticks = situation.honba * situation.rules["honba"], situation.sticks * 1000
    gain = payment.points + honba + sticks
    push!(lines, "BONUS honba $honba sticks $sticks")
    push!(lines, "TOTAL points $(payment.points) gain $gain")
    delta = Dict(wind => 0 for wind in WINDS)
    if situation.by == "ron"
        delta[situation.discarder] = -payment.ron - honba
    else
        for wind in WINDS
            wind == situation.seat && continue
            amount = wind == "E" ? payment.dealer : payment.nondealer
            delta[wind] = -amount - honba ÷ 3
        end
    end
    delta[situation.seat] = gain
    changes = join(("$wind " * (delta[wind] > 0 ? "+" : "") * string(delta[wind]) for wind in WINDS), " ")
    push!(lines, "DELTA " * changes)
    return lines, payment.points
end

function score_hands(rules, rule_order, records)
    lines, summary = String[], ["hand,han,fu,points,yaku"]
    stats, win_counts, wait_counts = Dict{Any,Int}(), Dict{Any,Int}(), Dict{Any,Int}()
    han_counts, fu_counts, limit_counts, yaku_counts = Dict{Any,Int}(), Dict{Any,Int}(), Dict{Any,Int}(), Dict{Any,Int}()
    rule_counts = Dict(name => Dict{Any,Int}() for name in rule_order)
    maximum, maximum_hand = 0, "-"
    for (label, fields) in records
        situation = parse_situation(label, fields, rules)
        add_report!(rule_counts[situation.rule_name], "hands")
        push!(lines, "HAND $label")
        error, situation = validate_situation(situation)
        if error !== nothing
            add_report!(stats, "errors")
            push!(lines, "ERROR $error")
            push!(summary, "$label,-,-,0,ERROR")
            continue
        end
        waiting = waiting_tiles(situation.hand_counts, situation.meld_counts, length(situation.melds))
        push!(lines, "WAITS " * join(tile_name.(waiting), " "))
        evaluated = evaluate_candidates(situation)
        append!(lines, candidate_line.(evaluated))
        if situation.by == "ron" && any(tile -> tile.kind in waiting, situation.discards)
            add_report!(stats, "furiten")
            push!(lines, "RESULT furiten")
            push!(summary, "$label,-,-,0,FURITEN")
            continue
        end
        best = best_candidate(evaluated)
        if best === nothing
            add_report!(stats, "no_yaku")
            push!(lines, "RESULT no_yaku")
            push!(summary, "$label,-,-,0,NO_YAKU")
            continue
        end
        report, points = winning_lines(situation, best)
        append!(lines, report)
        add_report!(stats, "wins")
        add_report!(stats, "points", points)
        add_report!(rule_counts[situation.rule_name], "wins")
        add_report!(rule_counts[situation.rule_name], "points", points)
        group = (situation.seat == "E" ? "dealer_" : "nondealer_") * situation.by
        add_report!(win_counts, group)
        add_report!(wait_counts, best.wait)
        add_report!(limit_counts, best.category)
        names = isempty(best.yakuman) ? best.yaku : best.yakuman
        for (name, _) in names
            add_report!(yaku_counts, name)
        end
        if isempty(best.yakuman)
            han, fu = string(best.han), string(best.fu)
            add_report!(han_counts, best.han)
            add_report!(fu_counts, best.fu)
        else
            han, fu = "Y$(best.multiplier)", "-"
        end
        push!(summary, "$label,$han,$fu,$points," * join((name for (name, _) in names), ";"))
        if points > maximum
            maximum, maximum_hand = points, label
        end
    end
    push!(
        lines,
        "STATS hands $(length(records)) wins $(report_count(stats, "wins")) furiten $(report_count(stats, "furiten")) no_yaku $(report_count(stats, "no_yaku")) errors $(report_count(stats, "errors"))"
    )
    push!(lines, "WINS " * report_pairs(WIN_ORDER, win_counts))
    push!(lines, "WAIT_COUNT " * report_pairs(WAIT_ORDER, wait_counts))
    append!(lines, ["HAN_COUNT $han $(han_counts[han])" for han in sort!(collect(keys(han_counts)))])
    append!(lines, ["FU_COUNT $fu $(fu_counts[fu])" for fu in sort!(collect(keys(fu_counts)))])
    append!(
        lines,
        ["LIMIT $category $(report_count(limit_counts, category))" for category in SCORE_CATEGORIES]
    )
    for name in vcat([row[1] for row in YAKU_TABLE], [row[1] for row in YAKUMAN_TABLE])
        report_count(yaku_counts, name) > 0 && push!(lines, "YAKU_COUNT $name $(yaku_counts[name])")
    end
    push!(lines, "POINTS total $(report_count(stats, "points")) max $maximum hand $maximum_hand")
    for name in rule_order
        push!(lines, "RULE $name " * report_pairs(("hands", "wins", "points"), rule_counts[name]))
    end
    return lines, summary
end

function hypothetical(label, fields, winning, method, rules)
    values = copy(fields)
    values["melds"], values["win"], values["by"] = "-", tile_name(winning), method
    values["from"] = method == "tsumo" ? "-" : fields["seat"] == "E" ? "S" : "E"
    values["flags"] = fields["riichi"] == "yes" ? "riichi" : "-"
    values["ura"], values["honba"], values["sticks"] = "-", "0", "0"
    return prepare_situation(parse_situation(label, values, rules))
end

function tenpai_lines(label, fields, waiting, furiten, rules)
    lines = String[]
    best = Dict{String,Any}("ron" => nothing, "tsumo" => nothing)
    for (kind, remaining) in waiting
        results = Dict{String,String}()
        for method in ("ron", "tsumo")
            if method == "ron" && furiten
                results[method] = "furiten"
                continue
            end
            situation = hypothetical(label, fields, kind, method, rules)
            candidate = best_candidate(evaluate_candidates(situation))
            if candidate === nothing
                results[method] = "no_yaku"
                continue
            end
            points = payments(candidate.base, situation.seat == "E", method).points
            results[method] = string(points)
            (best[method] === nothing || points > best[method][2]) && (best[method] = (kind, points))
        end
        push!(
            lines,
            "WAIT $(tile_name(kind)) left $remaining ron $(results["ron"]) tsumo $(results["tsumo"])"
        )
    end
    choices = Dict(method => best[method] === nothing ? "none" : "$(tile_name(best[method][1])) $(best[method][2])" for method in (
        "ron",
        "tsumo"
    ))
    push!(lines, "BEST ron $(choices["ron"]) tsumo $(choices["tsumo"])")
    return lines
end

function analyze_waits(rules, records)
    lines, stats, counts = String[], Dict{Any,Int}(), Dict{Any,Int}()
    for (label, fields) in records
        push!(lines, "HAND $label")
        hand, dora = parse_tiles(fields["hand"]), parse_tiles(fields["dora"])
        discards = parse_tiles(fields["discards"]; allow_empty=true)
        visible = parse_tiles(fields["visible"]; allow_empty=true)
        error = nothing
        if any(isnothing, (hand, dora, discards, visible))
            error = "bad tile notation"
        elseif length(hand) != 13
            error = "wrong tile count"
        else
            error = copy_error(vcat(hand, dora, discards, visible), rules[fields["rules"]])
        end
        if error !== nothing
            add_report!(stats, "errors")
            push!(lines, "ERROR $error")
            continue
        end
        hand_counts = tile_counts(hand)
        known_counts = tile_counts(vcat(hand, dora, discards, visible))
        standard, seven, orphans = shanten_numbers(hand_counts)
        current = min(standard, seven, orphans)
        add_report!(counts, current)
        push!(lines, "SHANTEN standard $standard chiitoitsu $seven kokushi $orphans")
        accepted = Tuple{Int,Int}[]
        for kind in 0:33
            hand_counts[kind + 1] >= 4 && continue
            hand_counts[kind + 1] += 1
            advancing = minimum(shanten_numbers(hand_counts)) < current
            hand_counts[kind + 1] -= 1
            advancing && push!(accepted, (kind, 4 - known_counts[kind + 1]))
        end
        total = sum((remaining for (_, remaining) in accepted); init=0)
        if current != 0
            suffix = join(" $(tile_name(kind)):$remaining" for (kind, remaining) in accepted)
            push!(lines, "ACCEPT kinds $(length(accepted)) tiles $total" * suffix)
            continue
        end
        add_report!(stats, "tenpai")
        discarded = Set(tile.kind for tile in discards)
        furiten = any(entry -> entry[1] in discarded, accepted)
        add_report!(stats, "furiten", Int(furiten))
        push!(lines, "TENPAI kinds $(length(accepted)) tiles $total furiten $(furiten ? "yes" : "no")")
        append!(lines, tenpai_lines(label, fields, accepted, furiten, rules))
    end
    push!(
        lines,
        "STATS hands $(length(records)) errors $(report_count(stats, "errors")) tenpai $(report_count(stats, "tenpai")) furiten $(report_count(stats, "furiten"))"
    )
    append!(lines, ["SHANTEN_COUNT $number $(report_count(counts, number))" for number in 0:6])
    return lines
end

function main()
    rules, rule_order = read_rules()
    scores, summary = score_hands(rules, rule_order, read_records("hands.txt"))
    waits = analyze_waits(rules, read_records("waits.txt"))
    mkpath("output")
    for (filename, lines) in (("scores.txt", scores), ("waits.txt", waits), ("summary.csv", summary))
        write(joinpath("output", filename), join(lines, "\n") * "\n")
    end
end

main()
