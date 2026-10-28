include("board.jl")
include("dictionary_trie.jl")
include("scoring.jl")
include("move_generator.jl")
include("game.jl")

const VOWELS = "AEIOU"
const STRATEGIES = ("score","tiles","equity")
words(parts...) = join(string.(parts)," ")
attributes(items::Pair...) = join(["$(first(p))=$(last(p))" for p in items]," ")
valid_name(value) = occursin(r"^[a-z0-9_]{1,20}$",value)
function valid_number(value,minimum,maximum)
    occursin(r"^(0|[1-9][0-9]*)$",value) || return false
    n = tryparse(Int,value)
    !isnothing(n) && minimum<=n<=maximum
end
valid_rack(value) = 1<=length(value)<=RACK_SIZE && all(l->l in TILE_ORDER,value)
collection(value) = isempty(value) ? "-" : join(sort!(collect(value)))
tile_kind(letter) = isuppercase(letter) ? letter : '?'
function remove_tiles(rack,removed)
    counts = rack_counts(rack)
    for letter in removed
        counts[tile_index(letter)] -= 1
    end
    join([repeat(string(l),counts[tile_index(l)]) for l in sort!(collect(TILE_ORDER))])
end
notation(e) = move_position(e.move)*" "*e.move.word
standard_key(e) = (-e.score,e.move.row,e.move.column,e.move.direction,e.move.word)
function strategy_key(e,strategy)
    prefix = strategy=="score" ? () : strategy=="tiles" ? (-length(e.new_tiles),) : (-e.score-e.value,)
    (prefix...,standard_key(e)...)
end
bump!(totals,key,amount=1) = (totals[key]=get(totals,key,0)+amount)
function read_inputs()
    values,counts,weights = zeros(Int,27),zeros(Int,27),zeros(Int,27)
    for line in readlines("input/tiles.txt")
        (isempty(line) || startswith(line,"#")) && continue
        f = split(line)
        i = tile_index(f[1][1])
        values[i],counts[i],weights[i] = parse.(Int,f[2:end])
    end
    trie,statistics,lengths = WordTrie(),Dict{String,Int}(),Dict{Int,Int}()
    for line in readlines("input/dictionary.txt")
        (isempty(line) || startswith(line,"#")) && continue
        bump!(statistics,"lines")
        if !occursin(r"^[A-Z]{2,15}$",line)
            bump!(statistics,"skipped")
        elseif add_word!(trie,line)
            lengths[length(line)] = get(lengths,length(line),0)+1
        else
            bump!(statistics,"duplicates")
        end
    end
    jobs,current = Vector{String}[],nothing
    for line in readlines("input/jobs.txt")
        if isnothing(current)
            !isempty(line) && !startswith(line,"#") && (current=[line])
        elseif line=="END"
            push!(jobs,current)
            current = nothing
        else
            push!(current,line)
        end
    end
    dictionary_lines = ["DICTIONARY "*attributes("lines"=>get(statistics,"lines",0),"words"=>trie.words,"skipped"=>get(statistics,"skipped",0),
        "duplicates"=>get(statistics,"duplicates",0),"nodes"=>length(trie.children)),
        "lengths"*join([" $n=$(lengths[n])" for n in sort!(collect(keys(lengths)))])]
    a = (
        ;values,
        counts,
        weights,
        trie,
        topn_totals=Dict{String,Int}(),
        validation_totals=Dict{String,Int}(),
        game_totals=Dict{String,Int}()
    )
    a,jobs,dictionary_lines
end
make_board(rows) = [rows[r][c] for r in 1:BOARD_SIZE,c in 1:BOARD_SIZE]
function used_tiles(board)
    result = zeros(Int,27)
    for (_,_,l) in board_tiles(board)
        result[tile_index(tile_kind(l))] += 1
    end
    result
end
function tile_error(a,board,rack)
    counts = used_tiles(board).+rack_counts(rack)
    for (i,l) in enumerate(TILE_ORDER)
        counts[i]>a.counts[i] && return "too many $l"
    end
    nothing
end
function unseen(a,board,rack)
    used = used_tiles(board).+rack_counts(rack)
    join([repeat(string(l),a.counts[i]-used[i]) for (i,l) in enumerate(TILE_ORDER)])
end
function board_error(a,rows,rack)
    length(rows)!=BOARD_SIZE && return "board rows $(length(rows))"
    for (i,row) in enumerate(rows)
        !occursin(r"^[.A-Za-z]{15}$",row) && return "bad board row $i"
    end
    board = make_board(rows)
    error = tile_error(a,board,rack)
    !isnothing(error) && return error
    !isempty(board_tiles(board)) && board[CENTER...]=='.' && return "center empty"
    !connected(board) && return "disconnected"
    for word in board_words(board)
        !has_word(a.trie,uppercase(word.word)) && return "unknown word $(word.word) at $(move_position(word))"
    end
    nothing
end
function job_error(a,job,seen)
    f = split(job[1])
    kind,name = f[1:2]
    !valid_name(name) && return "bad name"
    name in seen && return "duplicate name"
    if kind=="TOPN"
        !valid_number(f[3],1,99) && return "bad count"
        !(f[4] in STRATEGIES) && return "bad order"
        rack = split(job[2])[2]
        !valid_rack(rack) && return "bad rack"
        return board_error(a,job[4:end],rack)
    elseif kind=="VALIDATE"
        rows = String[]
        for line in job[3:end]
            startswith(line,"MOVE") && break
            push!(rows,line)
        end
        return board_error(a,rows,"")
    end
    !valid_number(f[3],1,2147483646) && return "bad seed"
    !(2<=length(job)-1<=4) && return "bad player count $(length(job)-1)"
    names = Set{String}()
    for (i,line) in enumerate(job[2:end])
        player = split(line)
        (!valid_name(player[2]) || !(player[3] in STRATEGIES) || (kind=="GAME" && !valid_number(
            player[4],
            0,
            99
        ))) && return "bad player $i"
        player[2] in names && return "duplicate player $i"
        push!(names,player[2])
    end
    nothing
end
function leave_value(a,rack)
    counts = rack_counts(rack)
    duplicates = sum(max(0,n-1) for n in counts[1:26])
    vowels = sum(counts[tile_index(l)] for l in VOWELS)
    consonants = sum(counts[i] for (i,l) in enumerate(LETTERS) if !(l in VOWELS))
    sum((a.weights[tile_index(l)] for l in rack);init=0)-4duplicates-3max(0,abs(vowels-consonants)-1)
end
function best_leave(a,rack)
    letters = collect(rack)
    candidates = Set{String}()
    for mask in 0:(1<<length(letters))-2
        push!(candidates,join(sort!([l for (i,l) in enumerate(letters) if mask&(1<<(i-1))!=0])))
    end
    argmin(k->(-leave_value(a,k),-length(k),k),candidates)
end
function evaluate_move(a,board,rack,move)
    scored = score_move(board,move,a.values)
    leave = remove_tiles(rack,[tile_kind(l) for (_,_,l) in scored.new_tiles])
    word_list = join(["$(w.word):$s" for (w,s) in scored.words],',')
    (
        move=move,
        score=scored.score,
        new_tiles=scored.new_tiles,
        words=word_list,
        leave=leave,
        value=leave_value(a,leave)
    )
end
function legal_moves(a,board,rack)
    sort!([evaluate_move(a,board,rack,m) for m in generate_moves(board,rack,a.trie)];by=standard_key)
end
function position_summary(board)
    listed,occupied = board_words(board),board_tiles(board)
    longest = isempty(listed) ? "-" : argmax(w->length(w.word),listed).word
    blanks = count(t->islowercase(t[3]),occupied)
    counts = [count(t->PREMIUMS[t[1]][t[2]]==p,occupied) for p in "#*^+"]
    "position "*attributes("tiles"=>length(occupied),"words"=>length(listed),"longest"=>longest,"blanks"=>blanks,
        "premiums"=>"TW:$(counts[1]),DW:$(counts[2]),TL:$(counts[3]),DL:$(counts[4])")
end
function topn(a,job)
    _,name,count_text,order = split(job[1])
    n = parse(Int,count_text)
    rack = String(split(job[2])[2])
    board = make_board(job[4:end])
    moves = legal_moves(a,board,rack)
    shown = sort(copy(moves);by=m->strategy_key(m,order))[1:min(n,length(moves))]
    hidden,anchor_squares = unseen(a,board,rack),anchors(board)
    checks = [cross_checks(board,a.trie),cross_checks(transpose_board(board),a.trie)]
    statistics = [join(
        [length(check),count(isempty,values(check)),sum(length,values(check);init=0)],
        ','
    ) for check in checks]
    vowels = count(l->l in VOWELS,rack)
    consonants = count(l->l in LETTERS && !(l in VOWELS),rack)
    across = count(m->m.move.direction==0,moves)
    bingos = count(m->length(m.new_tiles)==RACK_SIZE,moves)
    blanks = count(m->any(t->islowercase(t[3]),m.new_tiles),moves)
    lines = [words("TOPN",name,attributes("n"=>n,"order"=>order,"rack"=>collection(rack))),
        "board "*attributes("tiles"=>length(board_tiles(board)),"anchors"=>length(anchor_squares)),
        "unseen "*attributes("count"=>length(hidden),"tiles"=>collection(hidden)),
        "rack "*attributes(
            "vowels"=>vowels,
            "consonants"=>consonants,
            "blanks"=>count(==('?'),rack),
            "value"=>collection_points(rack,a.values)
        ),
        "checks "*attributes("across"=>statistics[1],"down"=>statistics[2]),
        "moves "*attributes(
            "total"=>length(moves),
            "across"=>across,
            "down"=>length(moves)-across,
            "bingos"=>bingos,
            "blanks"=>blanks
        )]
    scores = String[]
    for t in 1:RACK_SIZE
        matching = [m.score for m in moves if length(m.new_tiles)==t]
        push!(scores,"$t="*(isempty(matching) ? "-" : string(maximum(matching))))
    end
    push!(lines,"best_by_tiles "*join(scores,' '))
    keep = best_leave(a,rack)
    push!(lines,"exchange "*attributes("keep"=>collection(keep),"value"=>leave_value(a,keep)))
    found = sort!(anagrams(a.trie,rack);by=w->(-length(w),w))
    push!(
        lines,
        "anagrams "*attributes(
            "total"=>length(found),
            "top"=>(isempty(found) ? "-" : join(found[1:min(10,end)],','))
        )
    )
    for word in board_words(board)
        length(word.word)<3 && continue
        front = join([l for l in LETTERS if has_word(a.trie,l*uppercase(word.word))])
        back = join([l for l in LETTERS if has_word(a.trie,uppercase(word.word)*l)])
        if !isempty(front) || !isempty(back)
            push!(
                lines,
                words(
                    "hook",
                    move_position(word),
                    word.word,
                    attributes("front"=>(isempty(front) ? "-" : front),"back"=>(isempty(back) ? "-" : back))
                )
            )
        end
    end
    nets = Int[]
    if 1<=length(hidden)<=RACK_SIZE && !isempty(shown)
        for move in shown
            replies = legal_moves(a,apply_move(board,move.new_tiles),hidden)
            push!(nets,move.score-(isempty(replies) ? 0 : replies[1].score))
        end
        best = argmax(nets)
        push!(lines,"endgame "*attributes("opponent"=>collection(hidden),"best"=>best,"net"=>nets[best]))
    end
    for (i,m) in enumerate(shown)
        line = words(
            i,
            notation(m),
            attributes(
                "score"=>m.score,
                "tiles"=>length(m.new_tiles),
                "leave"=>collection(m.leave),
                "value"=>m.value
            )
        )
        !isempty(nets) && (line*=" net=$(nets[i])")
        push!(lines,line*" words="*m.words)
    end
    bump!(a.topn_totals,"moves",length(moves))
    bump!(a.topn_totals,"bingos",bingos)
    lines
end
function record_error(a,board,player,rack,action)
    !valid_name(player) && return "bad player",nothing
    !valid_rack(rack) && return "bad rack",nothing
    error = tile_error(a,board,rack)
    !isnothing(error) && return error,nothing
    length(action)==1 && action[1]=="PASS" && return nothing,nothing
    if action[1]=="EXCHANGE"
        returned = action[2]
        !valid_rack(returned) && return "bad exchange",nothing
        available,requested = rack_counts(rack),rack_counts(returned)
        for l in returned
            requested[tile_index(l)]>available[tile_index(l)] && return "rack lacks $l",nothing
        end
        return nothing,nothing
    end
    parsed = parse_position(action[1])
    isnothing(parsed) && return "bad position",nothing
    word = String(action[2])
    !occursin(r"^[A-Za-z]{2,15}$",word) && return "bad word",nothing
    move = (;parsed...,word)
    cells = move_cells(move)
    any(t->!inside(t[1],t[2]),cells) && return "off board",nothing
    for (r,c,l) in cells
        !(board[r,c] in ('.',l)) && return "mismatch at $(square_name(r,c))",nothing
    end
    dr,dc = move.direction,1-move.direction
    before = (move.row-dr,move.column-dc)
    after = (move.row+dr*length(word),move.column+dc*length(word))
    any(p->inside(p...) && board[p...]!='.',(before,after)) && return "not whole word",nothing
    new_tiles = placement(board,move)
    isempty(new_tiles) && return "no new tiles",nothing
    available = rack_counts(rack)
    for (_,_,l) in new_tiles
        tile = tile_kind(l)
        available[tile_index(tile)]==0 && return "rack lacks $tile",nothing
        available[tile_index(tile)] -= 1
    end
    if isempty(board_tiles(board))
        !any(t->(t[1],t[2])==CENTER,new_tiles) && return "center not covered",nothing
    elseif !any(board[p...]!='.' for (r,c,_) in new_tiles for p in neighbors(r,c))
        return "not connected",nothing
    end
    for formed in vcat([move],cross_words(board,move))
        !has_word(
            a.trie,
            uppercase(formed.word)
        ) && return "unknown word $(formed.word) at $(move_position(formed))",nothing
    end
    nothing,move
end
function validate_job(a,job)
    name = split(job[1])[2]
    board = make_board(job[3:2+BOARD_SIZE])
    records = job[3+BOARD_SIZE:end]
    lines,player_order,players,totals = ["VALIDATE $name"],String[],Dict{String,Dict{String,Int}}(),Dict{String,Int}()
    for (i,line) in enumerate(records)
        f = split(line)
        player,rack,action = String(f[2]),String(f[3]),f[4:end]
        prefix = words("move",i,player,join(action,' '))
        error,move = record_error(a,board,player,rack,action)
        if error!="bad player"
            if !haskey(players,player)
                players[player] = Dict{String,Int}()
                push!(player_order,player)
            end
            bump!(players[player],"moves")
        end
        if !isnothing(error)
            push!(lines,prefix*" invalid "*error)
            bump!(totals,"invalid")
            continue
        end
        legal = legal_moves(a,board,rack)
        best,score = isempty(legal) ? 0 : legal[1].score,0
        evaluated,rank = nothing,0
        if !isnothing(move)
            evaluated = evaluate_move(a,board,rack,move)
            score = evaluated.score
            target = placement_key(evaluated.new_tiles)
            rank = findfirst(e->placement_key(e.new_tiles)==target,legal)
        end
        statistics = players[player]
        for (key,amount) in (("valid",1),("score",score),("loss",best-score))
            bump!(statistics,key,amount)
            bump!(totals,key,amount)
        end
        bump!(totals,"best",best)
        if isnothing(move)
            push!(
                lines,
                prefix*" "*attributes(
                    "score"=>0,
                    "total"=>statistics["score"],
                    "moves"=>length(legal),
                    "best"=>best
                )
            )
        else
            push!(
                lines,
                prefix*" "*attributes(
                    "score"=>score,
                    "total"=>statistics["score"],
                    "tiles"=>length(evaluated.new_tiles),
                    "rank"=>"$rank/$(length(legal))",
                    "best"=>best,
                    "words"=>evaluated.words
                )
            )
            board = apply_move(board,evaluated.new_tiles)
        end
    end
    for player in player_order
        s = players[player]
        push!(
            lines,
            words(
                "player",
                player,
                attributes((key=>get(s,key,0) for key in ("moves","valid","score","loss"))...)
            )
        )
    end
    push!(
        lines,
        "total "*attributes((key=>get(totals,key,0) for key in ("valid","invalid","score","best","loss"))...)
    )
    push!(lines,position_summary(board))
    append!(lines,board_display(board))
    bump!(a.validation_totals,"moves",length(records))
    for key in ("valid","invalid","loss")
        bump!(a.validation_totals,key,get(totals,key,0))
    end
    lines
end
function ordinary_game(a,job)
    _,name,seed_text = split(job[1])
    seed = parse(Int,seed_text)
    random = Minstd(seed)
    bag = make_bag(a.counts,random)
    board = fill('.',BOARD_SIZE,BOARD_SIZE)
    players = NamedTuple[]
    lines = [words("GAME",name,attributes("seed"=>seed,"players"=>length(job)-1))]
    for (i,line) in enumerate(job[2:end])
        f = split(line)
        p = (
            name=String(f[2]),
            strategy=String(f[3]),
            threshold=parse(Int,f[4]),
            rack=draw_tiles!(bag,RACK_SIZE),
            score=0,
            statistics=Dict{String,Int}()
        )
        push!(players,p)
        push!(lines,words("player",i,p.name,attributes("strategy"=>p.strategy,"threshold"=>p.threshold)))
    end
    turn,consecutive,outgoing,highlight = 0,0,0,nothing
    while true
        index = turn%length(players)+1
        player = players[index]
        turn += 1
        rack,statistics = player.rack,player.statistics
        legal = legal_moves(a,board,rack)
        candidate = isempty(legal) ? nothing : argmin(m->strategy_key(m,player.strategy),legal)
        prefix = words("turn",turn,player.name,attributes("rack"=>collection(rack),"moves"=>length(legal)))
        if !isnothing(candidate) && !(candidate.score<player.threshold && length(bag)>=RACK_SIZE)
            best = legal[1].score
            board = apply_move(board,candidate.new_tiles)
            drawn = draw_tiles!(bag,RACK_SIZE-length(candidate.leave))
            player = (;player...,score=player.score+candidate.score,rack=candidate.leave*drawn)
            bump!(statistics,"plays")
            bump!(statistics,"bingos",length(candidate.new_tiles)==RACK_SIZE)
            statistics["top"] = max(get(statistics,"top",0),candidate.score)
            bump!(statistics,"loss",best-candidate.score)
            consecutive = 0
            if isnothing(highlight) || candidate.score>highlight.move.score
                highlight = (turn=turn,player=player.name,move=candidate)
            end
            push!(
                lines,
                prefix*" best=$best play "*notation(candidate)*" "*attributes(
                    "score"=>candidate.score,
                    "total"=>player.score,
                    "draw"=>collection(drawn),
                    "bag"=>length(bag)
                )
            )
            players[index] = player
            if isempty(player.rack) && isempty(bag)
                outgoing = index
                break
            end
        elseif length(bag)>=RACK_SIZE
            keep = best_leave(a,rack)
            returned = remove_tiles(rack,keep)
            drawn = exchange_tiles!(bag,returned,random)
            player = (;player...,rack=keep*drawn)
            bump!(statistics,"exchanges")
            consecutive += 1
            push!(
                lines,
                prefix*" exchange "*attributes(
                    "keep"=>collection(keep),
                    "draw"=>collection(drawn),
                    "bag"=>length(bag)
                )
            )
            players[index] = player
        else
            bump!(statistics,"passes")
            consecutive += 1
            push!(lines,prefix*" pass bag=$(length(bag))")
        end
        consecutive==6 && break
    end
    push!(
        lines,
        outgoing==0 ? "end reason=scoreless turns=$turn" : "end reason=out player=$(players[outgoing].name) turns=$turn"
    )
    adjustments = [-collection_points(p.rack,a.values) for p in players]
    outgoing!=0 && (adjustments[outgoing]=sum(collection_points(
        p.rack,
        a.values
    ) for (i,p) in enumerate(players) if i!=outgoing))
    final_scores = [p.score+adjustment for (p,adjustment) in zip(players,adjustments)]
    for (p,adjustment,final) in zip(players,adjustments,final_scores)
        adjusted = adjustment>0 ? "+$adjustment" : string(adjustment)
        push!(
            lines,
            words(
                "final",
                p.name,
                attributes("score"=>p.score,"rack"=>collection(p.rack),"adjust"=>adjusted,"total"=>final)
            )
        )
    end
    standings = sort!(collect(eachindex(players));by=i->(-final_scores[i],i))
    for (rank,i) in enumerate(standings)
        p = players[i]
        push!(
            lines,
            words(
                "standing",
                rank,
                p.name,
                "total=$(final_scores[i])",
                attributes((key=>get(p.statistics,key,0) for key in (
                    "plays",
                    "bingos",
                    "exchanges",
                    "passes",
                    "top",
                    "loss"
                ))...)
            )
        )
    end
    push!(
        lines,
        "winner "*join([p.name for (i,p) in enumerate(players) if final_scores[i]==maximum(final_scores)],',')
    )
    if !isnothing(highlight)
        push!(
            lines,
            "highlight "*attributes(
                "turn"=>highlight.turn,
                "player"=>highlight.player
            )*" play "*notation(highlight.move)*" score=$(highlight.move.score)"
        )
    end
    push!(lines,position_summary(board))
    append!(lines,board_display(board))
    bump!(a.game_totals,"turns",turn)
    for p in players,key in ("plays","exchanges","passes","bingos")
        bump!(a.game_totals,key,get(p.statistics,key,0))
    end
    lines
end
function duplicate_game(a,job)
    _,name,seed_text = split(job[1])
    seed = parse(Int,seed_text)
    random = Minstd(seed)
    bag,board = make_bag(a.counts,random),fill('.',BOARD_SIZE,BOARD_SIZE)
    rack = draw_tiles!(bag,RACK_SIZE)
    players = [String.(split(line)[2:end]) for line in job[2:end]]
    totals = zeros(Int,length(players))
    lines = [words("DUPLICATE",name,attributes("seed"=>seed,"players"=>length(players)))]
    for (i,p) in enumerate(players)
        push!(lines,words("player",i,p[1],"strategy="*p[2]))
    end
    round_number,master_total,reason = 0,0,"stuck"
    while true
        legal = legal_moves(a,board,rack)
        isempty(legal) && break
        round_number += 1
        master = legal[1]
        choices = [argmin(m->strategy_key(m,p[2]),legal) for p in players]
        for (i,m) in enumerate(choices)
            totals[i] += m.score
        end
        master_total += master.score
        push!(
            lines,
            words(
                "round",
                round_number,
                attributes("rack"=>collection(rack),"moves"=>length(legal)),
                "master",
                notation(master),
                attributes("score"=>master.score,"picks"=>join([m.score for m in choices],','))
            )
        )
        board = apply_move(board,master.new_tiles)
        rack = master.leave*draw_tiles!(bag,RACK_SIZE-length(master.leave))
        if isempty(rack)
            reason = "out"
            break
        end
    end
    push!(
        lines,
        "end "*attributes(
            "reason"=>reason,
            "rounds"=>round_number
        )*(reason=="stuck" ? " rack="*collection(rack) : "")
    )
    push!(lines,"master total=$master_total")
    for (p,total) in zip(players,totals)
        percent = master_total>=1 ? 100total÷master_total : 0
        push!(lines,words("final",p[1],attributes("total"=>total,"percent"=>percent)))
    end
    push!(lines,"winner "*join([p[1] for (p,total) in zip(players,totals) if total==maximum(totals)],','))
    push!(lines,position_summary(board))
    append!(lines,board_display(board))
    bump!(a.game_totals,"rounds",round_number)
    lines
end
function main()
    a,jobs,dictionary_lines = read_inputs()
    move_blocks,validation_blocks,game_blocks = [dictionary_lines],Vector{String}[],Vector{String}[]
    seen = Set{String}()
    for job in jobs
        kind,name = split(job[1])[1:2]
        if kind=="TOPN"
            destination,totals,key = move_blocks,a.topn_totals,"jobs"
        elseif kind=="VALIDATE"
            destination,totals,key = validation_blocks,a.validation_totals,"jobs"
        else
            destination,totals,key = game_blocks,a.game_totals,kind=="GAME" ? "games" : "duplicates"
        end
        bump!(totals,key)
        error = job_error(a,job,seen)
        push!(seen,name)
        if !isnothing(error)
            push!(destination,["$kind $name","error "*error])
            bump!(totals,"errors")
        elseif kind=="TOPN"
            push!(destination,topn(a,job))
        elseif kind=="VALIDATE"
            push!(destination,validate_job(a,job))
        elseif kind=="GAME"
            push!(destination,ordinary_game(a,job))
        else
            push!(destination,duplicate_game(a,job))
        end
    end
    summaries = [(move_blocks,a.topn_totals,("jobs","errors","moves","bingos")),
        (validation_blocks,a.validation_totals,("jobs","errors","moves","valid","invalid","loss")),
        (
            game_blocks,
            a.game_totals,
            ("games","duplicates","errors","turns","rounds","plays","exchanges","passes","bingos")
        )]
    mkpath("output")
    for (filename,(blocks,totals,keys)) in zip(("moves.txt","validation.txt","game.txt"),summaries)
        push!(blocks,["SUMMARY "*attributes((key=>get(totals,key,0) for key in keys)...)])
        write(joinpath("output",filename),join([join(block,"\n") for block in blocks],"\n\n")*"\n")
    end
end
main()
