const SEATS = "NESW"
const SUITS = "CDSH"
const RANKS = "23456789TJQKA"
const QS, KS, AS, JD = 36, 37, 38, 22
const DIRECTIONS = Dict('L'=>"LEFT", 'R'=>"RIGHT", 'A'=>"ACROSS", 'H'=>"HOLD")
const RULE_NAMES = ["TARGET", "LIMIT", "MOON", "JACK", "QSBREAK", "BLOOD", "PASS"]
struct CommandError <: Exception
    reason::String
end
fail(reason) = throw(CommandError(reason))
seattext(s::Int) = string(SEATS[s])
cardtext(c::Int) = string(RANKS[mod(c,13)+1], SUITS[div(c,13)+1])
cardstext(cards) = isempty(cards) ? "-" : join(cardtext.(sort(collect(cards))), " ")
rankkey(c::Int) = (mod(c,13), div(c,13))
highkey(c::Int) = (-mod(c,13), div(c,13))
lowest(cards) = first(sort(collect(cards); by=rankkey))
highest(cards) = first(sort(collect(cards); by=highkey))
penalty(c::Int) = c == QS || div(c,13) == 3
nextseat(s::Int, offset::Int) = mod(s-1+offset,4)+1
function seatvalue(word::String)
    length(word) == 1 && first(word) in SEATS || fail("bad seat " * word)
    return findfirst(==(first(word)), SEATS)
end
function cardvalue(word::String)
    length(word) == 2 || fail("bad card " * word)
    word[1] in RANKS && word[2] in SUITS || fail("bad card " * word)
    return 13*(findfirst(==(word[2]),SUITS)-1)+findfirst(==(word[1]),RANKS)-1
end
function bounded(word::String, low::Int, high::Int)
    value = tryparse(Int,word)
    value !== nothing && low <= value <= high || fail("bad value " * word)
    return value
end
pairs(label, values) = label * " " * join((seattext(s)*" "*string(values[s]) for s in 1:4), " ")
mutable struct Generator
    state::Int64
end
function draw!(rng::Generator)
    rng.state = mod(48271*rng.state,2147483647)
    return rng.state
end
struct HandRecord
    number::Int
    direction::String
    points::Vector{Int}
    shooter::Int
    record::Vector{String}
end
struct Snapshot
    hands::Vector{Set{Int}}
    taken::Vector{Set{Int}}
    tricks::Vector{Vector{Tuple{Int,Int}}}
    counts::Vector{Int}
    current::Vector{Tuple{Int,Int}}
    leader::Int
    broken::Bool
    record::Vector{String}
    logsize::Int
    seat::Int
    card::Int
end
mutable struct Game
    rules::Dict{String,String}
    bots::Vector{String}
    rng::Generator
    state::String
    number::Int
    scores::Vector{Int}
    stats::Matrix{Int}
    stacked::Dict{Int,Set{Int}}
    history::Vector{HandRecord}
    log::Vector{Tuple{Int,String}}
    record::Vector{String}
    hands::Vector{Set{Int}}
    taken::Vector{Set{Int}}
    passed::Dict{Int,Vector{Int}}
    direction::Char
    tricks::Vector{Vector{Tuple{Int,Int}}}
    counts::Vector{Int}
    current::Vector{Tuple{Int,Int}}
    leader::Int
    broken::Bool
    undo::Vector{Snapshot}
end
function Game(rules, bots, rng)
    Game(rules,bots,rng,"between",0,zeros(Int,4),zeros(Int,4,4),Dict{Int,Set{Int}}(),
         HandRecord[],Tuple{Int,String}[],String[],[Set{Int}() for _ in 1:4],
         [Set{Int}() for _ in 1:4],Dict{Int,Vector{Int}}(),'H',Vector{Tuple{Int,Int}}[],
         zeros(Int,4),Tuple{Int,Int}[],1,false,Snapshot[])
end
point(g::Game,c::Int) = c == QS ? 13 : div(c,13) == 3 ? 1 : c == JD && g.rules["JACK"] == "ON" ? -10 : 0
points(g::Game,cards) = sum((point(g,c) for c in cards); init=0)
function record!(g::Game, level::Int, line::String)
    push!(g.log,(level,line))
    level > 0 && push!(g.record,line)
end
function beginplay!(g::Game)
    g.state = "playing"
    g.leader = findfirst(hand -> 0 in hand,g.hands)
    record!(g,2,"lead "*seattext(g.leader))
end
function deal!(g::Game)
    g.number += 1
    cycle = g.rules["PASS"]
    g.direction = cycle[mod(g.number-1,length(cycle))+1]
    g.hands = [copy(get(g.stacked,s,Set{Int}())) for s in 1:4]
    used = union(g.hands...)
    deck = [c for c in 0:51 if !(c in used)]
    for i in length(deck):-1:2
        j = Int(mod(draw!(g.rng),i))+1
        deck[i],deck[j] = deck[j],deck[i]
    end
    free = [s for s in 1:4 if !haskey(g.stacked,s)]
    for (i,c) in enumerate(deck)
        push!(g.hands[free[mod(i-1,length(free))+1]],c)
    end
    empty!(g.stacked)
    empty!(g.passed)
    g.taken = [Set{Int}() for _ in 1:4]
    g.tricks = Vector{Tuple{Int,Int}}[]
    g.counts = zeros(Int,4)
    g.current = Tuple{Int,Int}[]
    empty!(g.undo)
    g.record = String[]
    g.broken = false
    record!(g,1,"hand $(g.number) pass $(DIRECTIONS[g.direction])")
    for s in 1:4
        record!(g,2,seattext(s)*": "*cardstext(g.hands[s]))
    end
    if g.direction == 'H'
        beginplay!(g)
    else
        g.state = "passing"
    end
end
function passcards!(g::Game,s::Int,cards::Vector{Int})
    setdiff!(g.hands[s],cards)
    g.passed[s] = copy(cards)
    record!(g,2,seattext(s)*" passes "*cardstext(cards))
    if length(g.passed) == 4
        offset = Dict('L'=>1,'R'=>3,'A'=>2)[g.direction]
        for source in 1:4
            union!(g.hands[nextseat(source,offset)],g.passed[source])
        end
        beginplay!(g)
    end
end
actor(g::Game) = nextseat(g.leader,length(g.current))
function legal(g::Game)
    hand = g.hands[actor(g)]
    if isempty(g.current)
        isempty(g.tricks) && return Set([0])
        safe = Set(c for c in hand if div(c,13) != 3)
        return !g.broken && !isempty(safe) ? safe : copy(hand)
    end
    led = div(g.current[1][2],13)
    followers = Set(c for c in hand if div(c,13) == led)
    !isempty(followers) && return followers
    if isempty(g.tricks) && g.rules["BLOOD"] == "OFF"
        safe = Set(c for c in hand if !penalty(c))
        !isempty(safe) && return safe
    end
    return copy(hand)
end
function choosepass(g::Game,s::Int)
    hand, strategy = g.hands[s], g.bots[s]
    low = sort(collect(hand); by=rankkey)
    high = sort(collect(hand); by=highkey)
    hearts = [c for c in high if div(c,13) == 3]
    special = [c for c in (QS,KS,AS) if c in hand]
    order = Int[]
    if strategy == "LOW"
        order = high
    elseif strategy == "HIGH"
        order = low
    elseif strategy == "MOON"
        order = vcat([c for c in low if div(c,13) != 3],[c for c in low if div(c,13) == 3])
    elseif strategy == "SMART"
        protected = QS in hand && count(c -> div(c,13) == 2,hand) >= 5
        !protected && append!(order,special)
        available = [suit for suit in 0:1 if any(c -> div(c,13) == suit,hand)]
        if !isempty(available)
            suit = first(sort(available; by=t -> (count(c -> div(c,13) == t,hand),t)))
            append!(order,[c for c in high if div(c,13) == suit])
        end
        append!(order,hearts)
        append!(order,high)
    else
        order = vcat(special,hearts,high)
    end
    return unique(order)[1:3]
end
queenplayed(g::Game) = any(cards -> QS in cards,g.taken) || any(p -> p[2] == QS,g.current)
function chooseplay(g::Game)
    s = actor(g)
    hand, playable, strategy = g.hands[s], legal(g), g.bots[s]
    strategy == "LOW" && return lowest(playable)
    strategy == "HIGH" && return highest(playable)
    if strategy == "MOON" && any(other -> other != s && any(penalty,g.taken[other]),1:4)
        strategy = "BASIC"
    end
    if isempty(g.current)
        if strategy == "SMART" && !queenplayed(g) && !(QS in hand)
            small = Set(c for c in playable if div(c,13) == 2 && mod(c,13) < 10)
            !isempty(small) && return lowest(small)
        end
        available = unique([div(c,13) for c in playable])
        suit = first(sort(available; by=t -> ((strategy == "MOON" ? -1 : 1)*count(c -> div(c,13) == t,playable),t)))
        subset = Set(c for c in playable if div(c,13) == suit)
        return strategy == "MOON" ? highest(subset) : lowest(subset)
    end
    led = div(g.current[1][2],13)
    if any(c -> div(c,13) == led,hand)
        winning = maximum(mod(c,13) for (_,c) in g.current if div(c,13) == led)
        lower = Set(c for c in playable if mod(c,13) < winning)
        if strategy == "MOON"
            high = highest(playable)
            return mod(high,13) > winning ? high : lowest(playable)
        end
        !isempty(lower) && return highest(lower)
        if strategy == "SMART" && length(g.current) == 3
            safe = setdiff(playable,Set([QS]))
            return isempty(safe) ? QS : highest(safe)
        end
        return lowest(playable)
    end
    if strategy == "MOON"
        safe = Set(c for c in playable if !penalty(c))
        return lowest(isempty(safe) ? playable : safe)
    end
    QS in playable && return QS
    if strategy == "SMART" && !queenplayed(g)
        AS in playable && return AS
        KS in playable && return KS
    end
    hearts = Set(c for c in playable if div(c,13) == 3)
    return highest(isempty(hearts) ? playable : hearts)
end
function winner(plays::Vector{Tuple{Int,Int}})
    best = plays[1]
    for p in plays
        if div(p[2],13) == div(best[2],13) && mod(p[2],13) > mod(best[2],13)
            best = p
        end
    end
    return best[1]
end
playstext(plays) = join((seattext(s)*" "*cardtext(c) for (s,c) in plays)," ")
function trickline(g::Game,plays,number::Int)
    value = sum(point(g,c) for (_,c) in plays)
    return "trick $number: $(playstext(plays)) -> $(seattext(winner(plays))) $value"
end
function play!(g::Game,c::Int)
    s = actor(g)
    push!(g.undo,Snapshot(deepcopy(g.hands),deepcopy(g.taken),copy(g.tricks),copy(g.counts),
                         copy(g.current),g.leader,g.broken,copy(g.record),length(g.log),s,c))
    delete!(g.hands[s],c)
    push!(g.current,(s,c))
    if div(c,13) == 3 || c == QS && g.rules["QSBREAK"] == "ON"
        g.broken = true
    end
    if length(g.current) == 4
        w = winner(g.current)
        union!(g.taken[w],(card for (_,card) in g.current))
        g.counts[w] += 1
        push!(g.tricks,g.current)
        record!(g,2,trickline(g,g.current,length(g.tricks)))
        g.current = Tuple{Int,Int}[]
        g.leader = w
        length(g.tricks) == 13 && finishhand!(g)
    end
end
function undocard!(g::Game)
    u = pop!(g.undo)
    g.hands,g.taken,g.tricks,g.counts,g.current = u.hands,u.taken,u.tricks,u.counts,u.current
    g.leader,g.broken,g.record = u.leader,u.broken,u.record
    resize!(g.log,u.logsize)
    return u.seat,u.card
end
ranking(g::Game) = sort(collect(1:4); by=s -> (g.scores[s],s))
ended(g::Game,scores) = g.number >= parse(Int,g.rules["LIMIT"]) || maximum(scores) >= parse(Int,g.rules["TARGET"])
function statslines(g::Game)
    ["stats $(seattext(s)) tricks $(g.stats[s,1]) hearts $(g.stats[s,2]) queens $(g.stats[s,3]) moons $(g.stats[s,4])" for s in 1:4]
end
function finishhand!(g::Game)
    values = [points(g,cards) for cards in g.taken]
    shooter = something(findfirst(cards -> count(penalty,cards) == 14,g.taken),0)
    if shooter != 0
        values[shooter] -= 26
        method = g.rules["MOON"]
        if method == "AUTO"
            addition = [g.scores[s]+values[s]+(s == shooter ? 0 : 26) for s in 1:4]
            best = first(sort(collect(1:4); by=s -> (addition[s],s)))
            method = ended(g,addition) && best != shooter ? "SUB" : "ADD"
        end
        if method == "SUB"
            values[shooter] -= 26
        else
            for s in 1:4
                s != shooter && (values[s] += 26)
            end
        end
        record!(g,1,"moon $(seattext(shooter)) $method")
    end
    for s in 1:4
        g.scores[s] += values[s]
        g.stats[s,1] += g.counts[s]
        g.stats[s,2] += count(c -> div(c,13) == 3,g.taken[s])
        g.stats[s,3] += QS in g.taken[s]
        g.stats[s,4] += shooter == s
    end
    record!(g,1,pairs("points",values))
    record!(g,1,pairs("scores",g.scores))
    push!(g.history,HandRecord(g.number,DIRECTIONS[g.direction],values,shooter,copy(g.record)))
    g.state = ended(g,g.scores) ? "none" : "between"
    if g.state == "none"
        record!(g,0,"game over hands $(g.number)")
        for (place,s) in enumerate(ranking(g))
            record!(g,0,"rank $place $(seattext(s)) $(g.scores[s])")
        end
        for line in statslines(g)
            record!(g,0,line)
        end
    end
end
function autopass!(g::Game)
    for s in 1:4
        !haskey(g.passed,s) && passcards!(g,s,choosepass(g,s))
    end
end
function autohand!(g::Game)
    g.state == "passing" && autopass!(g)
    while g.state == "playing"
        play!(g,chooseplay(g))
    end
end
function autogame!(g::Game)
    g.state in ("passing","playing") && autohand!(g)
    while g.state != "none"
        deal!(g)
        autohand!(g)
    end
end
function duplicate(cards)
    seen = Set{Int}()
    for c in cards
        c in seen && fail("duplicate card "*cardtext(c))
        push!(seen,c)
    end
end
mutable struct Table
    rules::Dict{String,String}
    bots::Vector{String}
    game::Union{Nothing,Game}
end
active(t::Table) = t.game !== nothing && t.game.state != "none"
function requirestate(t::Table,state::String)
    if state == "game"
        active(t) || fail("no game")
    elseif state == "between"
        requirestate(t,"game")
        t.game.state == "between" || fail("hand in progress")
    elseif state == "hand"
        active(t) && t.game.state in ("passing","playing") || fail("no hand")
    else
        active(t) && t.game.state == state || fail("not "*state)
    end
end
function simulate(t::Table,cmd::String,seed::Int,repetitions::Int)
    rng = Generator(seed)
    if cmd == "GAME"
        g = Game(t.rules,t.bots,rng)
        autogame!(g)
        return vcat(["game seed $seed"],[line for (level,line) in g.log if level <= repetitions])
    end
    rounds = cmd == "ROTATE" ? 4 : 1
    places, totals, statistics = zeros(Int,4,4),zeros(Int,4),zeros(Int,4,4)
    hands = 0
    for rotation in 0:rounds-1
        bots = Vector{String}(undef,4)
        for s in 1:4
            bots[nextseat(s,rotation)] = t.bots[s]
        end
        for _ in 1:repetitions
            g = Game(t.rules,bots,rng)
            autogame!(g)
            hands += g.number
            order = ranking(g)
            for s in 1:4
                actual = nextseat(s,rotation)
                places[s,findfirst(==(actual),order)] += 1
                totals[s] += g.scores[actual]
                statistics[s,:] .+= g.stats[actual,:]
            end
        end
    end
    games = rounds*repetitions
    output = ["$(lowercase(cmd)) seed $seed games $games hands $hands"]
    for s in 1:4
        cents = fld(100*totals[s],games)
        magnitude = abs(cents)
        average = (cents < 0 ? "-" : "")*string(div(magnitude,100))*"."*lpad(string(mod(magnitude,100)),2,'0')
        name = seattext(s)*(cmd == "ROTATE" ? " "*t.bots[s] : "")
        push!(output,"$name places $(join(places[s,:]," ")) total $(totals[s]) average $average tricks $(statistics[s,1]) hearts $(statistics[s,2]) queens $(statistics[s,3]) moons $(statistics[s,4])")
    end
    return output
end
function command!(t::Table,words::Vector{String})
    cmd,args = words[1],words[2:end]
    known = split("RULE BOT SETTINGS GAME MATCH ROTATE NEW ABANDON STACK DEAL SHOW PASS PLAY AUTO UNDO CLAIM LEGAL PREVIEW SCORE TAKEN TRICKS VOIDS UNSEEN STATS HISTORY REPLAY")
    cmd in known || fail("unknown command "*cmd)
    if cmd == "RULE"
        name,value = args
        name in RULE_NAMES || fail("unknown rule "*name)
        if name in ("TARGET","LIMIT")
            bounded(value,1,name == "TARGET" ? 1000 : 100)
        else
            good = name == "PASS" ? 1 <= length(value) <= 8 && all(c -> c in "LRAH",value) :
                   name == "MOON" ? value in ("ADD","SUB","AUTO") : value in ("ON","OFF")
            good || fail("bad value "*value)
        end
        active(t) && fail("game in progress")
        t.rules[name] = value
        return ["rule $name $value"]
    elseif cmd == "BOT"
        s = seatvalue(args[1])
        args[2] in ("BASIC","LOW","HIGH","SMART","MOON") || fail("bad value "*args[2])
        t.bots[s] = args[2]
        return ["bot $(seattext(s)) $(args[2])"]
    elseif cmd == "SETTINGS"
        return ["rules "*join((name*" "*t.rules[name] for name in RULE_NAMES)," "),pairs("bots",t.bots)]
    elseif cmd in ("GAME","MATCH","ROTATE")
        seed = bounded(args[1],1,2147483646)
        repetitions = bounded(args[2],cmd == "GAME" ? 0 : 1,cmd == "GAME" ? 2 : cmd == "MATCH" ? 50 : 10)
        return simulate(t,cmd,seed,repetitions)
    elseif cmd == "NEW"
        seed = bounded(args[1],1,2147483646)
        active(t) && fail("game in progress")
        t.game = Game(t.rules,t.bots,Generator(seed))
        return ["new game seed $seed"]
    elseif cmd == "ABANDON"
        requirestate(t,"game")
        t.game = nothing
        return ["game abandoned"]
    end
    s = cmd in ("STACK","PASS","PLAY","CLAIM") ? seatvalue(args[1]) : 0
    cards = cmd in ("STACK","PASS","PLAY") ? cardvalue.(args[2:end]) : Int[]
    cmd == "STACK" && length(cards) != 13 && fail("need 13 cards")
    cmd == "AUTO" && !(args[1] in ("PASS","CARD","TRICK","HAND","GAME")) && fail("bad value "*args[1])
    if cmd in ("STACK","DEAL")
        requirestate(t,"between")
    elseif cmd == "SHOW"
        requirestate(t,"hand")
    elseif cmd == "PASS"
        requirestate(t,"passing")
    elseif cmd in ("PLAY","UNDO","CLAIM","LEGAL","PREVIEW","TAKEN","TRICKS","VOIDS","UNSEEN")
        requirestate(t,"playing")
    elseif cmd in ("SCORE","STATS","HISTORY","REPLAY")
        requirestate(t,"game")
    elseif cmd == "AUTO"
        mode = args[1]
        requirestate(t,mode == "PASS" ? "passing" : mode in ("CARD","TRICK") ? "playing" : mode == "HAND" ? "hand" : "game")
    end
    g = t.game
    before = length(g.log)
    output = String[]
    if cmd == "STACK"
        duplicate(cards)
        for c in cards, other in 1:4
            other != s && c in get(g.stacked,other,Set{Int}()) && fail(cardtext(c)*" stacked for "*seattext(other))
        end
        g.stacked[s] = Set(cards)
        return ["stacked "*seattext(s)]
    elseif cmd == "DEAL"
        deal!(g)
    elseif cmd == "SHOW"
        return [seattext(s)*": "*cardstext(g.hands[s]) for s in 1:4]
    elseif cmd == "PASS"
        haskey(g.passed,s) && fail(seattext(s)*" already passed")
        duplicate(cards)
        for c in cards
            c in g.hands[s] || fail(seattext(s)*" does not hold "*cardtext(c))
        end
        passcards!(g,s,cards)
    elseif cmd == "PLAY"
        c = cards[1]
        s == actor(g) || fail("waiting for "*seattext(actor(g)))
        c in g.hands[s] || fail(seattext(s)*" does not hold "*cardtext(c))
        if !(c in legal(g))
            isempty(g.current) && fail(isempty(g.tricks) ? "must lead 2C" : "hearts not broken")
            led = div(g.current[1][2],13)
            any(held -> div(held,13) == led,g.hands[s]) && fail("must follow "*string(SUITS[led+1]))
            fail("no points on first trick")
        end
        push!(output,seattext(s)*" plays "*cardtext(c))
        play!(g,c)
    elseif cmd == "AUTO"
        mode = args[1]
        if mode == "PASS"
            autopass!(g)
        elseif mode == "CARD"
            s,c = actor(g),chooseplay(g)
            push!(output,seattext(s)*" plays "*cardtext(c))
            play!(g,c)
        elseif mode == "TRICK"
            completed = length(g.tricks)
            while g.state == "playing" && length(g.tricks) == completed
                play!(g,chooseplay(g))
            end
        elseif mode == "HAND"
            autohand!(g)
        else
            autogame!(g)
        end
    elseif cmd == "UNDO"
        isempty(g.undo) && fail("nothing to undo")
        s,c = undocard!(g)
        return ["undo $(seattext(s)) $(cardtext(c))"]
    elseif cmd == "CLAIM"
        s == actor(g) || fail("waiting for "*seattext(actor(g)))
        isempty(g.current) || fail("trick in progress")
        for c in g.hands[s], other in 1:4
            if other != s && any(d -> div(d,13) == div(c,13) && mod(d,13) > mod(c,13),g.hands[other])
                fail("claim rejected")
            end
        end
        remaining = union(g.hands...)
        countleft = 13-length(g.tricks)
        union!(g.taken[s],remaining)
        g.counts[s] += countleft
        g.hands = [Set{Int}() for _ in 1:4]
        record!(g,2,"claim $(seattext(s)) tricks $countleft points $(points(g,remaining))")
        finishhand!(g)
    elseif cmd == "LEGAL"
        return ["legal $(seattext(actor(g))): $(cardstext(legal(g))) bot $(cardtext(chooseplay(g)))"]
    elseif cmd == "PREVIEW"
        for c in sort(collect(legal(g)))
            trial = deepcopy(g)
            completed = length(trial.tricks)
            play!(trial,c)
            while trial.state == "playing" && length(trial.tricks) == completed
                play!(trial,chooseplay(trial))
            end
            trick = trial.tricks[end]
            value = sum(point(g,card) for (_,card) in trick)
            push!(output,"preview $(cardtext(c)) -> $(seattext(winner(trick))) $value")
        end
        return output
    elseif cmd == "SCORE"
        output = [pairs("scores",g.scores)]
        g.state == "playing" && push!(output,pairs("taken",[points(g,cards) for cards in g.taken]))
        return output
    elseif cmd == "TAKEN"
        return [seattext(s)*": "*cardstext(Set(c for c in g.taken[s] if point(g,c) != 0)) for s in 1:4]
    elseif cmd == "TRICKS"
        output = [trickline(g,trick,n) for (n,trick) in enumerate(g.tricks)]
        !isempty(g.current) && push!(output,"current: "*playstext(g.current))
        return isempty(output) ? ["no tricks"] : output
    elseif cmd == "VOIDS"
        missing = [Set{Int}() for _ in 1:4]
        for trick in vcat(g.tricks,[g.current])
            isempty(trick) && continue
            led = div(trick[1][2],13)
            for (who,c) in trick
                div(c,13) != led && push!(missing[who],led)
            end
        end
        values = [isempty(item) ? "-" : join((SUITS[suit+1] for suit in sort(collect(item)))) for item in missing]
        return [pairs("voids",values)]
    elseif cmd == "UNSEEN"
        who = actor(g)
        unseen = setdiff(Set(0:51),g.hands[who],union(g.taken...),Set(c for (_,c) in g.current))
        return ["unseen $(seattext(who)): $(cardstext(unseen))"]
    elseif cmd == "STATS"
        return statslines(g)
    elseif cmd == "HISTORY"
        for h in g.history
            line = "hand $(h.number) pass $(h.direction) "*pairs("points",h.points)
            h.shooter != 0 && (line *= " moon "*seattext(h.shooter))
            push!(output,line)
        end
        return isempty(output) ? ["no hands"] : output
    elseif cmd == "REPLAY"
        h = bounded(args[1],1,length(g.history))
        return copy(g.history[h].record)
    end
    append!(output,[line for (_,line) in g.log[before+1:end]])
    return output
end
function main()
    lines = readlines()
    rules = Dict(zip(RULE_NAMES,["100","100","ADD","OFF","OFF","OFF","LRAH"]))
    table = Table(rules,fill("BASIC",4),nothing)
    for line in lines[2:parse(Int,lines[1])+1]
        try
            for result in command!(table,String.(split(line,' ')))
                println(result)
            end
        catch error
            error isa CommandError || rethrow()
            println("error: ",error.reason)
        end
    end
end
main()
