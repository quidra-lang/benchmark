using Printf

const RALLY_SPORTS = ("TENNIS","TABLETENNIS","BADMINTON","VOLLEYBALL")
const OPTION_RULES = Dict(
    "TENNIS"=>Dict("SETS"=>["3","5"],"DEUCE"=>["AD","NOAD"],"FINAL"=>["TB7","TB10","ADV","SUPER"],"FIRST"=>["A","B"]),
    "TABLETENNIS"=>Dict("GAMES"=>["5","7"],"FIRST"=>["A","B"]),
    "BADMINTON"=>Dict("FIRST"=>["A","B"]),"VOLLEYBALL"=>Dict("FIRST"=>["A","B"]),
    "DARTS"=>Dict("START"=>["501","301","701"],"SETS"=>["1","2","3","4","5"],"LEGS"=>["1","2","3","4","5"],"FIRST"=>["A","B"]),
    "BOWLING"=>Dict{String,Vector{String}}())

mutable struct ScoreMatch
    id::String
    sport::String
    names::Vector{String}
    options::Dict{String,String}
    initial::Vector{Vector{Int}}
    state::Dict{Symbol,Any}
    history::Vector{Any}
end

score_error(message) = throw(ArgumentError(message))
side(text) = text == "A" ? 1 : 2
other(player) = 3-player
pair_text(values) = string(values[1],'-',values[2])
average_text(value) = @sprintf("%d.%02d",div(value,100),value%100)
option_int(m,key) = parse(Int,m.options[key])

function checkout_tables()
    candidates = Tuple{String,Int}[]
    doubles = Tuple{String,Int}[]
    darts = Dict("25"=>(25,false),"BULL"=>(50,true),"MISS"=>(0,false))
    for (prefix,multiplier) in (("S",1),("T",3),("D",2))
        for value in 20:-1:1
            code = prefix*string(value)
            push!(candidates,(code,value*multiplier))
            darts[code] = (value*multiplier,prefix == "D")
            prefix == "D" && push!(doubles,(code,value*multiplier))
        end
    end
    append!(candidates,[("25",25),("BULL",50)])
    push!(doubles,("BULL",50))
    tables = [Dict{Int,Vector{String}}() for i in 1:3]
    for (last,value) in doubles
        !haskey(tables[1],value) && (tables[1][value] = [last])
    end
    for (first,a) in candidates
        for (last,b) in doubles
            !haskey(tables[2],a+b) && (tables[2][a+b] = [first,last])
        end
    end
    for (first,a) in candidates
        for (second,b) in candidates
            for (last,c) in doubles
                !haskey(tables[3],a+b+c) && (tables[3][a+b+c] = [first,second,last])
            end
        end
    end
    return darts,tables
end
const DART_DATA = checkout_tables()
const DARTS = DART_DATA[1]
const CHECKOUTS = DART_DATA[2]

function checkout(score,maximum=3)
    for count in 1:maximum
        haskey(CHECKOUTS[count],score) && return CHECKOUTS[count][score]
    end
    return String[]
end

function create_match(tokens)
    id,sport = tokens[2:3]
    names = sport == "BOWLING" ? tokens[4:4] : tokens[4:5]
    initial = sport == "VOLLEYBALL" ? [parse.(Int,split(tokens[i],',')) for i in 6:7] : Vector{Int}[]
    if sport == "BOWLING"
        first_option = 5
    elseif sport == "VOLLEYBALL"
        first_option = 8
    else
        first_option = 6
    end
    options = Dict(key=>values[1] for (key,values) in OPTION_RULES[sport])
    seen = Set{String}()
    for token in tokens[first_option:end]
        parts = split(token,'=';keepempty=true)
        length(parts) == 2 || score_error("invalid option")
        key,value = String.(parts)
        haskey(OPTION_RULES[sport],key) && value in OPTION_RULES[sport][key] && !(key in seen) || score_error("invalid option")
        push!(seen,key)
        options[key] = value
    end
    first = haskey(options,"FIRST") ? side(options["FIRST"]) : 1
    stats = Dict(key=>[0,0] for key in (:points,:served,:servewins,:runmax,:holds,:games,:breaks,:opportunities,:converted,:darts,:scored,:busts,:high,:tons,:maximums,:attempts,:hits))
    state = Dict{Symbol,Any}(:p=>[0,0],:g=>[0,0],:won=>[0,0],:server=>first,:winner=>0,
        :completed=>NTuple{4,Int}[],:stats=>stats,:last=>0,:run=>0)
    if sport == "VOLLEYBALL"
        state[:lineups] = deepcopy(initial)
        state[:subs],state[:timeouts] = [0,0],[0,0]
    elseif sport == "BOWLING"
        state[:frames] = [Int[] for i in 1:10]
        state[:marks] = [String[] for i in 1:10]
        state[:frame],state[:standing],state[:fresh] = 1,10,true
    elseif sport == "DARTS"
        start = parse(Int,options["START"])
        state[:legs],state[:remaining] = [0,0],[start,start]
        state[:turn],state[:turnscore],state[:turnstart],state[:legnumber] = String[],0,start,0
    end
    return ScoreMatch(id,sport,names,options,initial,state,Any[])
end

function tennis_mode(m)
    s = m.state
    final = s[:won][1] == s[:won][2] == div(option_int(m,"SETS"),2)
    final && m.options["FINAL"] == "SUPER" && return "SUPER"
    s[:g] == [6,6] && !(final && m.options["FINAL"] == "ADV") && return "TB"
    return "NORMAL"
end

function rally_server(m)
    s = m.state
    if m.sport == "TENNIS"
        if tennis_mode(m) != "NORMAL" && isodd(div(sum(s[:p])+1,2))
            return other(s[:server])
        end
    elseif m.sport == "TABLETENNIS"
        first = side(m.options["FIRST"])
        isodd(length(s[:completed])) && (first = other(first))
        total = sum(s[:p])
        flip = total < 20 ? isodd(div(total,2)) : isodd(total)
        return flip ? other(first) : first
    end
    return s[:server]
end

function rally_outcome(m,winner)
    s = m.state
    points = copy(s[:p])
    points[winner] += 1
    loser = other(winner)
    game = false
    unit = false
    if m.sport == "TENNIS"
        mode = tennis_mode(m)
        if mode == "NORMAL"
            game = points[winner] >= 4 && (m.options["DEUCE"] == "NOAD" || points[winner]-points[loser] >= 2)
            games = s[:g][winner]+1
            unit = game && games >= 6 && games-s[:g][loser] >= 2
        else
            final = s[:won][1] == s[:won][2] == div(option_int(m,"SETS"),2)
            target = mode == "SUPER" || (final && m.options["FINAL"] == "TB10") ? 10 : 7
            unit = points[winner] >= target && points[winner]-points[loser] >= 2
        end
        needed = div(option_int(m,"SETS"),2)+1
    elseif m.sport == "TABLETENNIS"
        unit = points[winner] >= 11 && points[winner]-points[loser] >= 2
        needed = div(option_int(m,"GAMES"),2)+1
    elseif m.sport == "BADMINTON"
        unit = points[winner] == 30 || (points[winner] >= 21 && points[winner]-points[loser] >= 2)
        needed = 2
    else
        target = length(s[:completed]) == 4 ? 15 : 25
        unit = points[winner] >= target && points[winner]-points[loser] >= 2
        needed = 3
    end
    return game,unit,unit && s[:won][winner]+1 == needed
end

function point_event!(m,winner)
    s = m.state
    stats = s[:stats]
    server = rally_server(m)
    game,unit,finished = rally_outcome(m,winner)
    mode = m.sport == "TENNIS" ? tennis_mode(m) : ""
    opportunity = false
    if mode == "NORMAL"
        opportunity = rally_outcome(m,other(server))[1]
    end
    record = [1,winner,server,Int(opportunity),Int(game),s[:p]...,s[:g]...,s[:won]...,s[:server],length(s[:completed]),s[:last],s[:run],stats[:runmax][winner],0,0]
    stats[:points][winner] += 1
    stats[:served][server] += 1
    winner == server && (stats[:servewins][server] += 1)
    s[:run] = s[:last] == winner ? s[:run]+1 : 1
    s[:last] = winner
    stats[:runmax][winner] = max(stats[:runmax][winner],s[:run])
    if opportunity
        stats[:opportunities][other(server)] += 1
        winner != server && (stats[:converted][winner] += 1)
    end
    s[:p][winner] += 1
    if m.sport == "TENNIS"
        if game
            stats[:games][server] += 1
            if winner == server
                stats[:holds][winner] += 1
            else
                stats[:breaks][winner] += 1
            end
            s[:g][winner] += 1
            s[:server] = other(s[:server])
        elseif unit
            s[:server] = other(s[:server])
        end
        if unit
            if mode == "SUPER"
                push!(s[:completed],(s[:p][1],s[:p][2],2,0))
            elseif mode == "TB"
                s[:g][winner] += 1
                push!(s[:completed],(s[:g][1],s[:g][2],1,s[:p][other(winner)]))
            else
                push!(s[:completed],(s[:g][1],s[:g][2],0,0))
            end
        end
    elseif m.sport == "BADMINTON"
        s[:server] = winner
    elseif m.sport == "VOLLEYBALL" && winner != server
        s[:server] = winner
        lineup = s[:lineups][winner]
        s[:lineups][winner] = vcat(lineup[2:end],lineup[1])
        record[18] = 1
    end
    if unit
        m.sport != "TENNIS" && push!(s[:completed],(s[:p][1],s[:p][2],0,0))
        s[:won][winner] += 1
        if finished
            s[:winner] = winner
        else
            if m.sport == "VOLLEYBALL"
                record[17] = 1
                append!(record,vcat(s[:lineups][1],s[:lineups][2],s[:subs],s[:timeouts]))
                s[:lineups] = deepcopy(m.initial)
                s[:subs],s[:timeouts] = [0,0],[0,0]
                first = side(m.options["FIRST"])
                s[:server] = iseven(length(s[:completed])) ? first : other(first)
            end
            s[:p],s[:g] = [0,0],[0,0]
        end
    elseif game
        s[:p] = [0,0]
    end
    push!(m.history,Int32.(record))
end

function roll_event!(s,pins)
    pins <= s[:standing] || score_error("too many pins")
    frame = s[:frame]
    if s[:fresh] && pins == 10
        mark = "X"
    elseif pins == s[:standing]
        mark = "/"
    else
        mark = pins == 0 ? "-" : string(pins)
    end
    push!(s[:frames][frame],pins)
    push!(s[:marks][frame],mark)
    s[:standing] -= pins
    s[:fresh] = false
    rolls = s[:frames][frame]
    if frame < 10
        if (length(rolls) == 1 && pins == 10) || length(rolls) == 2
            s[:frame] += 1
            s[:standing],s[:fresh] = 10,true
        end
    else
        complete = length(rolls) == 3 || (length(rolls) == 2 && rolls[1] != 10 && sum(rolls) < 10)
        if complete
            s[:winner] = 1
        elseif s[:standing] == 0
            s[:standing],s[:fresh] = 10,true
        end
    end
end

function bowling_scores(s)
    scores = Union{Nothing,Int}[nothing for i in 1:10]
    for frame in 1:10
        rolls = s[:frames][frame]
        isempty(rolls) && continue
        later = [pin for i in frame+1:10 for pin in s[:frames][i]]
        if frame == 10
            s[:winner] != 0 && (scores[frame] = sum(rolls))
        elseif rolls[1] == 10
            length(later) >= 2 && (scores[frame] = 10+sum(later[1:2]))
        elseif length(rolls) == 2
            if sum(rolls) == 10
                !isempty(later) && (scores[frame] = 10+later[1])
            else
                scores[frame] = sum(rolls)
            end
        end
    end
    return scores
end

function complete_turn!(s,player)
    score = s[:turnscore]
    stats = s[:stats]
    stats[:high][player] = max(stats[:high][player],score)
    score >= 100 && (stats[:tons][player] += 1)
    score == 180 && (stats[:maximums][player] += 1)
end

function next_turn!(s)
    s[:server] = other(s[:server])
    s[:turn],s[:turnscore] = String[],0
    s[:turnstart] = s[:remaining][s[:server]]
end

function dart_event!(m,code)
    haskey(DARTS,code) || score_error("invalid dart")
    s = m.state
    stats = s[:stats]
    player = s[:server]
    value,double = DARTS[code]
    before = s[:remaining][player]
    stats[:darts][player] += 1
    (before == 50 || (before <= 40 && iseven(before))) && (stats[:attempts][player] += 1)
    remaining = before-value
    if remaining < 0 || remaining == 1 || (remaining == 0 && !double)
        stats[:busts][player] += 1
        stats[:scored][player] -= s[:turnscore]
        s[:remaining][player] = s[:turnstart]
        next_turn!(s)
        return
    end
    stats[:scored][player] += value
    s[:remaining][player] = remaining
    s[:turnscore] += value
    push!(s[:turn],code)
    if remaining == 0
        stats[:hits][player] += 1
        complete_turn!(s,player)
        s[:legs][player] += 1
        set_over = s[:legs][player] == option_int(m,"LEGS")
        if set_over
            push!(s[:completed],(s[:legs][1],s[:legs][2],0,0))
            s[:won][player] += 1
        end
        if set_over && s[:won][player] == option_int(m,"SETS")
            s[:winner] = player
            return
        end
        set_over && (s[:legs] = [0,0])
        s[:legnumber] += 1
        first = side(m.options["FIRST"])
        s[:server] = iseven(s[:legnumber]) ? first : other(first)
        start = option_int(m,"START")
        s[:remaining] = [start,start]
        s[:turn],s[:turnscore],s[:turnstart] = String[],0,start
    elseif length(s[:turn]) == 3
        complete_turn!(s,player)
        next_turn!(s)
    end
end

function undo_event!(m)
    isempty(m.history) && score_error("nothing to undo")
    record = pop!(m.history)
    if record isa Dict
        m.state = record
        return
    end
    data = Int.(record)
    s = m.state
    if data[1] == 2
        s[:lineups][data[2]][data[3]] = data[4]
        s[:subs][data[2]] -= 1
    elseif data[1] == 3
        s[:timeouts][data[2]] -= 1
    else
        winner,server = data[2:3]
        stats = s[:stats]
        stats[:points][winner] -= 1
        stats[:served][server] -= 1
        winner == server && (stats[:servewins][server] -= 1)
        if data[4] == 1
            stats[:opportunities][other(server)] -= 1
            winner != server && (stats[:converted][winner] -= 1)
        end
        if data[5] == 1
            stats[:games][server] -= 1
            if winner == server
                stats[:holds][winner] -= 1
            else
                stats[:breaks][winner] -= 1
            end
        end
        if data[17] == 1
            s[:lineups] = [data[19:24],data[25:30]]
            s[:subs],s[:timeouts] = data[31:32],data[33:34]
        end
        if data[18] == 1
            lineup = s[:lineups][winner]
            s[:lineups][winner] = vcat(lineup[end],lineup[1:end-1])
        end
        s[:p],s[:g],s[:won] = data[6:7],data[8:9],data[10:11]
        s[:server],s[:winner] = data[12],0
        resize!(s[:completed],data[13])
        s[:last],s[:run] = data[14],data[15]
        stats[:runmax][winner] = data[16]
    end
end

function event!(m,command,args)
    correct = (command == "POINT" && m.sport in RALLY_SPORTS) || (command == "ROLL" && m.sport == "BOWLING") ||
        (command == "THROW" && m.sport == "DARTS") || (command in ("SUB","TIMEOUT") && m.sport == "VOLLEYBALL")
    correct || score_error("wrong event")
    if command == "POINT"
        events = string.(collect(args[1]))
    elseif command in ("SUB","TIMEOUT")
        events = [""]
    else
        events = args
    end
    for value in events
        m.state[:winner] == 0 || score_error("match over")
        if command == "POINT"
            point_event!(m,side(value))
        elseif command == "ROLL"
            old = deepcopy(m.state)
            roll_event!(m.state,parse(Int,value))
            push!(m.history,old)
        elseif command == "THROW"
            old = deepcopy(m.state)
            dart_event!(m,value)
            push!(m.history,old)
        elseif command == "SUB"
            player = side(args[1])
            outgoing,incoming = parse.(Int,args[2:3])
            lineup = m.state[:lineups][player]
            position = findfirst(==(outgoing),lineup)
            position !== nothing || score_error("player not on court")
            incoming in lineup && score_error("player already on court")
            m.state[:subs][player] < 6 || score_error("no substitutions left")
            push!(m.history,Int32[2,player,position,outgoing])
            lineup[position] = incoming
            m.state[:subs][player] += 1
        else
            player = side(args[1])
            m.state[:timeouts][player] < 2 || score_error("no timeouts left")
            push!(m.history,Int32[3,player])
            m.state[:timeouts][player] += 1
        end
    end
end

function completed_text(record,winner=1)
    a,b,kind,extra = record
    if winner == 2
        a,b = b,a
    end
    text = string(a,'-',b)
    kind == 2 && return "["*text*"]"
    return kind == 1 ? text*"($extra)" : text
end

function situation(m,player)
    game,unit,finished = rally_outcome(m,player)
    finished && return "match point"
    if unit
        return m.sport in ("TENNIS","VOLLEYBALL") ? "set point" : "game point"
    end
    if game
        return player == rally_server(m) ? "game point" : "break point"
    end
    return ""
end

function score_line(m)
    s = m.state
    if m.sport == "BOWLING"
        parts = [m.id*": "*m.names[1]]
        scores = bowling_scores(s)
        cumulative = 0
        for frame in 1:10
            isempty(s[:frames][frame]) && break
            text = join(s[:marks][frame])
            if scores[frame] !== nothing
                cumulative += scores[frame]
                text *= "($cumulative)"
            end
            push!(parts,text)
        end
        return join(parts," ")
    end
    names = copy(m.names)
    if s[:winner] == 0
        player = m.sport in RALLY_SPORTS ? rally_server(m) : s[:server]
        names[player] *= "*"
    end
    parts = [m.id*": "*names[1]*" vs "*names[2]]
    if m.sport == "DARTS"
        append!(parts,["sets",pair_text(s[:won]),"legs",pair_text(s[:legs]),"score",pair_text(s[:remaining])])
        if s[:winner] == 0
            if !isempty(s[:turn])
                push!(parts,"turn")
                append!(parts,s[:turn])
            end
            answer = checkout(s[:remaining][s[:server]],3-length(s[:turn]))
            if !isempty(answer)
                push!(parts,"checkout")
                append!(parts,answer)
            end
        end
    else
        append!(parts,completed_text.(s[:completed]))
        if s[:winner] == 0
            if m.sport == "TENNIS"
                mode = tennis_mode(m)
                if mode == "SUPER"
                    push!(parts,"["*pair_text(s[:p])*"]")
                else
                    push!(parts,pair_text(s[:g]))
                    if mode == "TB"
                        push!(parts,pair_text(s[:p]))
                    elseif m.options["DEUCE"] == "AD" && minimum(s[:p]) >= 3
                        if s[:p][1] == s[:p][2]
                            push!(parts,"40-40")
                        else
                            push!(parts,s[:p][1] > s[:p][2] ? "AD-40" : "40-AD")
                        end
                    else
                        labels = ["0","15","30","40"]
                        push!(parts,labels[s[:p][1]+1]*"-"*labels[s[:p][2]+1])
                    end
                end
            else
                push!(parts,pair_text(s[:p]))
                if m.sport == "VOLLEYBALL"
                    append!(parts,["server",string(s[:lineups][s[:server]][1])])
                end
            end
            for player in 1:2
                label = situation(m,player)
                !isempty(label) && push!(parts,"($label $(m.names[player]))")
            end
        end
    end
    return join(parts," ")
end

function stats_lines(m)
    s = m.state
    stats = s[:stats]
    if m.sport == "BOWLING"
        marks = [mark for frame in s[:marks] for mark in frame]
        open = count(rolls -> length(rolls) >= 2 && rolls[1] != 10 && sum(rolls[1:2]) < 10,s[:frames])
        future = deepcopy(s)
        while future[:winner] == 0
            roll_event!(future,future[:standing])
        end
        maximum = sum(bowling_scores(future))
        return ["$(m.id) $(m.names[1]): strikes $(count(==("X"),marks)) spares $(count(==("/"),marks)) open $open max $maximum"]
    end
    output = String[]
    for player in 1:2
        prefix = "$(m.id) $(m.names[player]): "
        if m.sport == "DARTS"
            darts = stats[:darts][player]
            average = darts == 0 ? 0 : div(stats[:scored][player]*300,darts)
            text = "darts $darts average $(average_text(average)) busts $(stats[:busts][player]) high $(stats[:high][player]) tons $(stats[:tons][player]) 180s $(stats[:maximums][player]) doubles $(stats[:hits][player])/$(stats[:attempts][player])"
        else
            text = "points $(stats[:points][player]) serve $(stats[:servewins][player])/$(stats[:served][player]) run $(stats[:runmax][player])"
            if m.sport == "TENNIS"
                text *= " holds $(stats[:holds][player])/$(stats[:games][player]) breaks $(stats[:breaks][player]) break points $(stats[:converted][player])/$(stats[:opportunities][player])"
            elseif m.sport == "VOLLEYBALL"
                text *= " subs $(s[:subs][player]) timeouts $(s[:timeouts][player]) lineup $(join(s[:lineups][player],","))"
            end
        end
        push!(output,prefix*text)
    end
    return output
end

function result_line(m)
    s = m.state
    s[:winner] != 0 || score_error("match not finished")
    m.sport == "BOWLING" && return "$(m.id): $(m.names[1]) $(sum(bowling_scores(s)))"
    winner = s[:winner]
    scores = [completed_text(record,winner) for record in s[:completed]]
    return "$(m.id): $(m.names[winner]) def. $(m.names[other(winner)]) "*join(scores," ")
end

function execute(line,matches)
    tokens = String.(split(line,' '))
    command = tokens[1]
    if command == "MATCH"
        haskey(matches,tokens[2]) && score_error("duplicate match")
        m = create_match(tokens)
        matches[m.id] = m
        return String[]
    elseif command == "CHECKOUT"
        answer = checkout(parse(Int,tokens[2]))
        return ["checkout $(tokens[2]): "*(isempty(answer) ? "none" : join(answer," "))]
    elseif command == "STANDINGS"
        totals = Dict{String,Vector{Int}}()
        for m in values(matches)
            if m.sport != "BOWLING" && m.state[:winner] != 0
                winner = m.state[:winner]
                for player in 1:2
                    record = get!(totals,m.names[player],[0,0])
                    record[player == winner ? 1 : 2] += 1
                end
            end
        end
        names = sort(collect(keys(totals));by=name -> (-totals[name][1],totals[name][2],name))
        return ["standings: "*(isempty(names) ? "none" : join(["$name $(totals[name][1])-$(totals[name][2])" for name in names],", "))]
    end
    haskey(matches,tokens[2]) || score_error("unknown match")
    m = matches[tokens[2]]
    if command in ("POINT","ROLL","THROW","SUB","TIMEOUT")
        event!(m,command,tokens[3:end])
    elseif command == "UNDO"
        undo_event!(m)
    elseif command == "SCORE"
        return [score_line(m)]
    elseif command == "STATS"
        return stats_lines(m)
    elseif command == "RESULT"
        return [result_line(m)]
    end
    return String[]
end

function main()
    matches = Dict{String,ScoreMatch}()
    for i in 1:parse(Int,readline())
        line = readline()
        try
            foreach(println,execute(line,matches))
        catch exception
            exception isa ArgumentError || rethrow()
            println("ERROR ",exception.msg)
        end
    end
end
main()
