using Printf

mutable struct State
    position::Matrix{Int}
    side::Int
    cube::Int
    owner::Int
    pending::Bool
    over::Bool
    score::Vector{Int}
end
struct Play
    position::Matrix{Int}
    moves::Vector{Tuple{Int,Int}}
    key::Vector{Tuple{Int,Int}}
    hits::Set{Int}
    die::Int
    notation::String
end
struct Entry
    record::String
    before::State
    after::State
end
mutable struct Engine
    state::State
    history::Vector{Entry}
    redo::Vector{Entry}
end
mutable struct RandomSource
    value::Int64
end
struct GameResult
    winner::Int
    kind::String
    points::Int
    turns::Int
    start::Int
end
color(side) = side == 1 ? "W" : "B"
owner(s) = s.owner == 0 ? "center" : color(s.owner)
number(s) = parse(Int64, s)
function initial()
    pos = zeros(Int, 2, 26)
    for side in 1:2
        pos[side, 25] = 2
        pos[side, 14] = 5
        pos[side, 9] = 3
        pos[side, 7] = 5
    end
    State(pos, 1, 1, 0, false, false, [0, 0])
end
function random!(rng)
    rng.value = mod(48271*rng.value, 2147483647)
end
die!(rng) = random!(rng) % 6 + 1
pips(pos, side) = sum(p*pos[side, p+1] for p in 1:25)
function keith(pos, side)
    c = pos[side, :]
    total = pips(pos, side)+2*max(c[2]-1, 0)+max(c[3]-1, 0)+max(c[4]-3, 0)
    total + count(iszero, c[5:7])
end
function contact(pos)
    white = pos[1, 26] > 0 ? 25 : 0
    black = pos[2, 26] > 0 ? 0 : 25
    for p in 1:24
        pos[1, p+1] > 0 && (white = max(white, p))
        pos[2, p+1] > 0 && (black = min(black, 25-p))
    end
    white > black
end
function evaluate(pos, side)
    other = 3-side
    P = pips(pos, other)-pips(pos, side)
    G = pos[other, 26]-pos[side, 26]
    S, H, R, A, run = 0, 0, 0, 0, 0
    for p in 1:24
        if pos[side, p+1] >= 2
            run += 1
            R = max(R, run)
            H += p <= 6
            A += p >= 19
        else
            run = 0
        end
        if pos[side, p+1] == 1
            distances = Set(p-q for q in 0:p-1 if pos[other, 26-q] > 0)
            for a in 1:6, b in 1:6
                S += a in distances || b in distances || a+b in distances || (a == b && (3*a in distances || 4*a in distances))
            end
        end
    end
    E = 2*P-S+4*H+3*R+3*A+6*G
    (; E, P, S, H, R, A, G)
end
function cube_decision(s, prohibited=false)
    (s.owner == 3-s.side || s.cube == 64 || prohibited) && return "unavailable"
    if contact(s.position)
        E = evaluate(s.position, s.side).E
        E < 60 && return "no double"
        return E <= 100 ? "double take" : "double drop"
    end
    V = 8*keith(s.position, s.side)-7*keith(s.position, 3-s.side)
    L = s.owner == 0 ? 28 : 21
    V > L && return "no double"
    V >= 14 ? "double take" : "double drop"
end
function submoves(pos, side, die)
    sources = pos[side, 26] > 0 ? [25] : [p for p in 24:-1:1 if pos[side, p+1] > 0]
    home = pos[side, 26] == 0 && all(iszero, pos[side, 8:25])
    moves = Tuple{Int,Int}[]
    for from in sources
        to = from-die
        if to >= 1
            pos[3-side, 26-to] < 2 && push!(moves, (from, to))
        elseif home
            allowed = to == 0 || all(iszero, pos[side, from+2:7])
            allowed && push!(moves, (from, 0))
        end
    end
    moves
end
function apply_submove(pos, side, move)
    next = copy(pos)
    from, to = move
    next[side, from+1] -= 1
    next[side, to+1] += 1
    hit = to > 0 && next[3-side, 26-to] == 1
    if hit
        next[3-side, 26-to] = 0
        next[3-side, 26] += 1
    end
    next, hit
end
function canonical(moves, hits)
    key = sort(copy(moves); rev=true)
    while true
        first, second = 0, 0
        for (i, pair) in enumerate(key)
            to = pair[2]
            (to == 0 || to in hits) && continue
            j = findfirst(b -> b[1] == to, key)
            if !isnothing(j)
                first, second = i, j
                break
            end
        end
        first == 0 && break
        combined = (key[first][1], key[second][2])
        key = [key[i] for i in eachindex(key) if i != first && i != second]
        push!(key, combined)
        sort!(key; rev=true)
    end
    parts = String[]
    marked = Set{Int}()
    i = 1
    while i <= length(key)
        pair = key[i]
        j = i+1
        while j <= length(key) && key[j] == pair
            j += 1
        end
        from = pair[1] == 25 ? "bar" : string(pair[1])
        to = pair[2] == 0 ? "off" : string(pair[2])
        part = "$from/$to"
        if pair[2] in hits && !(pair[2] in marked)
            part *= "*"
            push!(marked, pair[2])
        end
        j-i >= 2 && (part *= "($(j-i))")
        push!(parts, part)
        i = j
    end
    key, isempty(parts) ? "none" : join(parts, " ")
end
function key_less(a, b)
    for i in 1:min(length(a), length(b))
        a[i] != b[i] && return a[i] > b[i]
    end
    length(a) > length(b)
end
function enumerate_plays(pos, side, d1, d2)
    dice = d1 == d2 ? fill(d1, 4) : [d1, d2]
    possible = Play[]
    maximum = 0
    function search(current, left, path, hits, first)
        push!(possible, Play(current, copy(path), Tuple{Int,Int}[], copy(hits), first, ""))
        maximum = max(maximum, length(path))
        seen = Set{Int}()
        for (i, die) in enumerate(left)
            die in seen && continue
            push!(seen, die)
            rest = [left[j] for j in eachindex(left) if j != i]
            for move in submoves(current, side, die)
                next, hit = apply_submove(current, side, move)
                next_hits = copy(hits)
                hit && push!(next_hits, move[2])
                search(next, rest, [path; [move]], next_hits, isempty(path) ? die : first)
            end
        end
    end
    search(pos, dice, Tuple{Int,Int}[], Set{Int}(), 0)
    larger = maximum == 1 && d1 != d2 && any(p -> length(p.moves) == 1 && p.die == max(d1, d2), possible)
    legal = Play[]
    positions = Set{NTuple{52,Int}}()
    for p in possible
        position_key = Tuple(vec(p.position))
        if length(p.moves) != maximum || larger && p.die != max(d1, d2) || position_key in positions
            continue
        end
        key, notation = canonical(p.moves, p.hits)
        push!(legal, Play(p.position, p.moves, key, p.hits, p.die, notation))
        push!(positions, position_key)
    end
    sort!(legal; lt=(a, b) -> key_less(a.key, b.key))
    legal, possible, maximum
end
function best(plays, side)
    chosen = plays[1]
    score = evaluate(chosen.position, side).E
    for p in plays[2:end]
        value = evaluate(p.position, side).E
        if value > score
            chosen, score = p, value
        end
    end
    chosen, score
end
multiplier(kind) = kind == "gammon" ? 2 : kind == "backgammon" ? 3 : 1
function finish!(s, winner, kind)
    s.pending = false
    s.over = true
    points = multiplier(kind)*s.cube
    s.score[winner] += points
    GameResult(winner, kind, points, 0, 0)
end
function bear_result!(s, winner)
    other = 3-winner
    kind = "single"
    if s.position[other, 1] == 0
        back = s.position[other, 26] > 0 || any(>(0), s.position[other, 20:25])
        kind = back ? "backgammon" : "gammon"
    end
    finish!(s, winner, kind)
end
result_line(r) = "result $(color(r.winner)) $(r.kind) $(r.points)"
function make_play!(engine, play, d1, d2)
    before = deepcopy(engine.state)
    s = engine.state
    side = s.side
    s.position = copy(play.position)
    result = nothing
    if s.position[side, 1] == 15
        result = bear_result!(s, side)
    else
        s.side = 3-side
    end
    record = "$(color(side)) $d1-$d2 $(play.notation)"
    push!(engine.history, Entry(record, before, deepcopy(s)))
    empty!(engine.redo)
    !isnothing(result) && println(result_line(result))
end
function parse_play(words)
    words == ["none"] && return Tuple{Int,Int}[]
    moves = Tuple{Int,Int}[]
    for word in words
        m = match(r"^(bar|[1-9]|1[0-9]|2[0-4])(?:/(?:[1-9]|1[0-9]|2[0-4])\*?)*(?:/off|/(?:[1-9]|1[0-9]|2[0-4])\*?)(?:\([234]\))?$", word)
        isnothing(m) && return nothing
        count = 1
        if endswith(word, ')')
            count = parse(Int, word[end-1:end-1])
            word = word[1:end-3]
        end
        points = Int[]
        for part in split(word, '/')
            point = part == "bar" ? 25 : part == "off" ? 0 : parse(Int, replace(part, "*"=>""))
            push!(points, point)
        end
        for i in 1:length(points)-1
            points[i] <= points[i+1] && return nothing
            append!(moves, fill((points[i], points[i+1]), count))
        end
    end
    moves
end
function validate_play(pos, side, moves, legal, possible, maximum)
    final = copy(pos)
    destinations = Set{Int}()
    nonbar, bear = false, false
    for (from, to) in moves
        final[side, from+1] -= 1
        final[side, to+1] += 1
        push!(destinations, to)
        nonbar |= from != 25
        bear |= to == 0
    end
    for to in destinations
        if to > 0 && pos[3-side, 26-to] == 1
            final[3-side, 26-to] = 0
            final[3-side, 26] += 1
        end
    end
    any(x -> x < 0, final[side, 2:26]) && return nothing, "no checker"
    final[side, 26] > 0 && nonbar && return nothing, "bar"
    any(to -> to > 0 && pos[3-side, 26-to] >= 2, destinations) && return nothing, "blocked"
    bear && (final[side, 26] > 0 || any(>(0), final[side, 8:25])) && return nothing, "bear-off"
    for p in legal
        p.position == final && return p, ""
    end
    matched = [p for p in possible if p.position == final]
    any(p -> length(p.moves) < maximum, matched) && return nothing, "too few dice"
    !isempty(matched) && return nothing, "larger die required"
    nothing, "impossible"
end
function simulation(original, rng, strategies; opening=false, target=0, score=[0, 0], crawford=false, verbose=false)
    s = deepcopy(original)
    first_dice = [0, 0]
    if opening
        while first_dice[1] == first_dice[2]
            first_dice = [die!(rng), die!(rng)]
        end
        s.side = first_dice[1] > first_dice[2] ? 1 : 2
    end
    start, turns, t = s.side, 0, 1
    while true
        side, other = s.side, 3-s.side
        if opening && t == 1
            d1, d2 = first_dice
        else
            prohibited = target > 0 && (crawford || score[side]+s.cube >= target)
            decision = cube_decision(s, prohibited)
            if decision in ("double take", "double drop")
                verbose && println("$t $(color(side)) doubles $(s.cube*2)")
                if decision == "double drop"
                    verbose && println("$t $(color(other)) drops")
                    r = finish!(s, side, "drop")
                    return GameResult(r.winner, r.kind, r.points, turns, start)
                end
                s.cube *= 2
                s.owner = other
                verbose && println("$t $(color(other)) takes")
            end
            d1, d2 = die!(rng), die!(rng)
        end
        plays, _, _ = enumerate_plays(s.position, side, d1, d2)
        chosen = plays[1]
        if strategies[side] == "BEST"
            chosen, _ = best(plays, side)
        elseif strategies[side] == "RANDOM"
            chosen = plays[random!(rng) % length(plays)+1]
        end
        s.position = copy(chosen.position)
        turns += 1
        verbose && println("$t $(color(side)) $d1-$d2 $(chosen.notation)")
        if s.position[side, 1] == 15
            r = bear_result!(s, side)
            return GameResult(r.winner, r.kind, r.points, turns, start)
        end
        s.side = other
        t += 1
    end
end
function board(s)
    function format_row(values)
        join(lpad.(values[1:6], 3)) * " |" * join(lpad.(values[7:12], 3))
    end
    for half in 0:1
        points = half == 0 ? collect(13:24) : collect(12:-1:1)
        half == 0 && println(format_row(string.(points)))
        for row in 1:5
            level = half == 0 ? row : 6-row
            fields = String[]
            for p in points
                count, letter = s.position[1, p+1], "W"
                if count == 0
                    count, letter = s.position[2, 26-p], "B"
                end
                value = count >= level ? letter : "."
                level == 5 && count > 5 && (value = string(count))
                push!(fields, value)
            end
            println(format_row(fields))
        end
        if half == 0
            status = s.over ? "game over" : s.pending ? "$(color(s.side)) doubles" : "$(color(s.side)) to move"
            println("bar W$(s.position[1, 26]) B$(s.position[2, 26]) | off W$(s.position[1, 1]) B$(s.position[2, 1]) | cube $(s.cube) $(owner(s)) | $status")
        else
            println(format_row(string.(points)))
        end
    end
end
function execute!(engine, words)
    cmd, a = words[1], words[2:end]
    noargs = ["NEW", "SHOW", "BOARD", "PIPS", "RACE", "EVAL", "SHOTS", "CUBE", "DOUBLE", "TAKE", "DROP", "SCORE", "HISTORY"]
    others = ["POS", "MOVES", "PLAY", "AUTO", "HINT", "RESIGN", "UNDO", "REDO", "GAME", "MATCH", "STATS"]
    if !(cmd in noargs || cmd in others)
        println("ERROR unknown command")
        return
    end
    arg(at, lo, hi) = at <= length(a) && lo <= number(a[at]) <= hi
    valid = !(cmd in noargs) || isempty(a)
    if cmd == "POS"
        valid = length(a) == 4
    elseif cmd in ("MOVES", "AUTO")
        valid = length(a) == 2 && arg(1, 1, 6) && arg(2, 1, 6)
    elseif cmd == "PLAY"
        valid = length(a) >= 3 && arg(1, 1, 6) && arg(2, 1, 6)
    elseif cmd == "HINT"
        valid = length(a) == 3 && arg(1, 1, 6) && arg(2, 1, 6) && arg(3, 1, 1000)
    elseif cmd == "RESIGN"
        valid = length(a) == 1 && a[1] in ("single", "gammon", "backgammon")
    elseif cmd in ("UNDO", "REDO")
        valid = length(a) == 1 && arg(1, 1, 1000)
    elseif cmd == "GAME"
        valid = length(a) == 3 && arg(1, 1, 2147483646) && all(x -> x in ("BEST", "FIRST", "RANDOM"), a[2:3])
    elseif cmd == "MATCH"
        valid = length(a) == 2 && arg(1, 1, 15) && arg(2, 1, 2147483646)
    elseif cmd == "STATS"
        valid = length(a) == 2 && arg(1, 1, 50) && arg(2, 1, 2147483646)
    end
    if cmd == "POS" && valid
        points = number.(split(a[1], ','))
        valid = length(points) == 24 && arg(2, 0, 15) && arg(3, 0, 15) && a[4] in ("W", "B")
        s = initial()
        s.position .= 0
        s.score = copy(engine.state.score)
        if valid
            s.position[1, 26], s.position[2, 26] = number(a[2]), number(a[3])
            for (i, value) in enumerate(points)
                if value > 0
                    s.position[1, i+1] = value
                elseif value < 0
                    s.position[2, 26-i] = -value
                end
            end
            for side in 1:2
                s.position[side, 1] = 15-sum(s.position[side, 2:26])
                valid &= 0 <= s.position[side, 1] <= 14
            end
            s.side = a[4] == "W" ? 1 : 2
        end
        if valid
            engine.state = s
            empty!(engine.history)
            empty!(engine.redo)
            println("OK")
            return
        end
    end
    if !valid
        println(cmd == "POS" ? "ERROR bad position" : "ERROR bad arguments")
        return
    end
    s = engine.state
    after = ["RACE", "MOVES", "PLAY", "AUTO", "HINT", "EVAL", "SHOTS", "CUBE", "DOUBLE", "TAKE", "DROP", "RESIGN", "GAME"]
    pending = ["PLAY", "AUTO", "CUBE", "DOUBLE", "RESIGN", "GAME"]
    if s.over && cmd in after
        println("ERROR game over")
        return
    elseif s.pending && cmd in pending
        println("ERROR double pending")
        return
    end
    if cmd == "NEW"
        fresh = initial()
        fresh.score = copy(s.score)
        engine.state = fresh
        empty!(engine.history)
        empty!(engine.redo)
        println("OK")
    elseif cmd == "SHOW"
        points = [s.position[1, p+1]-s.position[2, 26-p] for p in 1:24]
        println("POS $(join(points, ',')) $(s.position[1, 26]) $(s.position[2, 26]) $(color(s.side))")
    elseif cmd == "BOARD"
        board(s)
    elseif cmd == "PIPS"
        println("pips W $(pips(s.position, 1)) B $(pips(s.position, 2))")
    elseif cmd == "RACE"
        println(contact(s.position) ? "contact" : "race W $(keith(s.position, 1)) B $(keith(s.position, 2))")
    elseif cmd == "EVAL"
        v = evaluate(s.position, s.side)
        println("eval $(v.E) pips $(v.P) blots $(v.S) home $(v.H) prime $(v.R) anchors $(v.A) bar $(v.G)")
    elseif cmd in ("MOVES", "PLAY", "AUTO", "HINT")
        d1, d2 = number.(a[1:2])
        if cmd == "PLAY"
            moves = parse_play(a[3:end])
            if isnothing(moves)
                println("ILLEGAL syntax")
                return
            end
            legal, possible, maximum = enumerate_plays(s.position, s.side, d1, d2)
            play, reason = validate_play(s.position, s.side, moves, legal, possible, maximum)
            if !isempty(reason)
                println("ILLEGAL ", reason)
            else
                println("OK ", play.notation)
                make_play!(engine, play, d1, d2)
            end
            return
        end
        legal, _, _ = enumerate_plays(s.position, s.side, d1, d2)
        if cmd == "MOVES"
            foreach(p -> println(p.notation), legal)
            println("total ", length(legal))
        elseif cmd == "AUTO"
            play, value = best(legal, s.side)
            println("OK $(play.notation) eval $value")
            make_play!(engine, play, d1, d2)
        else
            scores = [evaluate(p.position, s.side).E for p in legal]
            order = sortperm(eachindex(legal); by=i -> (-scores[i], i))
            for i in order[1:min(number(a[3]), length(order))]
                println("$(scores[i]) $(legal[i].notation)")
            end
        end
    elseif cmd == "SHOTS"
        blots = [p for p in 24:-1:1 if s.position[s.side, p+1] == 1]
        counts = Dict(p=>0 for p in blots)
        total = 0
        rolls = String[]
        for a in 6:-1:1, b in a:-1:1
            legal, _, _ = enumerate_plays(s.position, 3-s.side, a, b)
            hit = Set(p for p in blots if any(play -> 25-p in play.hits, legal))
            weight = a == b ? 1 : 2
            if !isempty(hit)
                total += weight
                push!(rolls, "$a-$b")
            end
            for p in hit
                counts[p] += weight
            end
        end
        println("shots $total/36", isempty(rolls) ? "" : " " * join(rolls, " "))
        for p in blots
            println("blot $p $(counts[p])/36")
        end
    elseif cmd == "CUBE"
        println("cube ", cube_decision(s))
    elseif cmd == "DOUBLE"
        if s.owner == 3-s.side || s.cube == 64
            println("ERROR cube unavailable")
        else
            s.pending = true
            empty!(engine.redo)
            println("OK double ", s.cube*2)
        end
    elseif cmd == "TAKE"
        if !s.pending
            println("ERROR no double")
        else
            s.pending = false
            s.cube *= 2
            s.owner = 3-s.side
            empty!(engine.redo)
            println("OK take $(s.cube) $(owner(s))")
        end
    elseif cmd == "DROP"
        if !s.pending
            println("ERROR no double")
        else
            result = finish!(s, s.side, "drop")
            empty!(engine.redo)
            println("OK drop")
            println(result_line(result))
        end
    elseif cmd == "RESIGN"
        result = finish!(s, 3-s.side, a[1])
        empty!(engine.redo)
        println("OK resign")
        println(result_line(result))
    elseif cmd == "SCORE"
        println("score W $(s.score[1]) B $(s.score[2])")
    elseif cmd == "HISTORY"
        println("history ", length(engine.history))
        for (i, entry) in enumerate(engine.history)
            println("$i $(entry.record)")
        end
    elseif cmd == "UNDO"
        n = number(a[1])
        if n > length(engine.history)
            println("ERROR cannot undo")
        else
            index = length(engine.history)-n+1
            engine.state = deepcopy(engine.history[index].before)
            engine.redo = [engine.history[index:end]; engine.redo]
            engine.history = engine.history[1:index-1]
            println("OK")
        end
    elseif cmd == "REDO"
        n = number(a[1])
        if n > length(engine.redo)
            println("ERROR cannot redo")
        else
            engine.state = deepcopy(engine.redo[n].after)
            append!(engine.history, engine.redo[1:n])
            engine.redo = engine.redo[n+1:end]
            println("OK")
        end
    elseif cmd == "GAME"
        result = simulation(s, RandomSource(number(a[1])), a[2:3]; verbose=true)
        println(result_line(result))
    elseif cmd == "MATCH"
        target, seed = number.(a)
        rng = RandomSource(seed)
        score, used, game = [0, 0], false, 0
        while Base.maximum(score) < target
            game += 1
            crawford = !used && Base.maximum(score) == target-1
            used |= crawford
            r = simulation(initial(), rng, ["BEST", "BEST"]; opening=true, target=target, score=score, crawford=crawford)
            score[r.winner] += r.points
            label = crawford ? " crawford" : ""
            println("game $game$label start $(color(r.start)) turns $(r.turns) result $(color(r.winner)) $(r.kind) $(r.points) score $(score[1])-$(score[2])")
        end
        winner = score[1] >= target ? 1 : 2
        println("match $(color(winner)) $(score[1])-$(score[2])")
    elseif cmd == "STATS"
        count, seed = number.(a)
        rng = RandomSource(seed)
        kinds = ["single", "gammon", "backgammon", "drop"]
        counts = Dict(kind=>[0, 0] for kind in kinds)
        points, turns = [0, 0], 0
        for _ in 1:count
            r = simulation(initial(), rng, ["BEST", "BEST"]; opening=true)
            counts[r.kind][r.winner] += 1
            points[r.winner] += r.points
            turns += r.turns
        end
        for kind in kinds
            println("$kind W $(counts[kind][1]) B $(counts[kind][2])")
        end
        println("points W $(points[1]) B $(points[2])")
        println("turns $turns")
    end
end
function main()
    engine = Engine(initial(), Entry[], Entry[])
    n = parse(Int, readline())
    for _ in 1:n
        execute!(engine, String.(split(readline())))
    end
end
main()
