const KINDS = ['I', 'O', 'T', 'S', 'Z', 'J', 'L']
const OPERATIONS = ["L", "R", "LL", "RR", "SD", "DD", "CW", "CCW", "HD", "LOCK", "HOLD"]
const COMMANDS = Set(["NEW", "PRINT", "NEXT", "PREVIEW", "STATUS", "ANALYZE", "ROW", "GARBAGE", "ATTACK", "TICK", "UNDO", "SAVE", "LOAD", "SPINS", "HINT", "AUTO"])
const AFTER_END = Set(["PRINT", "NEXT", "PREVIEW", "STATUS", "ANALYZE", "LOAD"])
const STATES = ['0', 'R', '2', 'L']
const CLEAR_NAMES = ["SINGLE", "DOUBLE", "TRIPLE", "TETRIS", "TSPIN_MINI", "TSPIN_MINI_SINGLE", "TSPIN_MINI_DOUBLE", "TSPIN", "TSPIN_SINGLE", "TSPIN_DOUBLE", "TSPIN_TRIPLE"]
const FRAMES = [
    ["....", "####", "....", "...."], ["##", "##"], [".#.", "###", "..."],
    [".##", "##.", "..."], ["##.", ".##", "..."], ["#..", "###", "..."], ["..#", "###", "..."]
]
const ORDINARY_KICKS = [
    [(0,0),(-1,0),(-1,1),(0,-2),(-1,-2)],
    [(0,0),(1,0),(1,-1),(0,2),(1,2)],
    [(0,0),(1,0),(1,-1),(0,2),(1,2)],
    [(0,0),(-1,0),(-1,1),(0,-2),(-1,-2)],
    [(0,0),(1,0),(1,1),(0,-2),(1,-2)],
    [(0,0),(-1,0),(-1,-1),(0,2),(-1,2)],
    [(0,0),(-1,0),(-1,-1),(0,2),(-1,2)],
    [(0,0),(1,0),(1,1),(0,-2),(1,-2)]
]
const I_KICKS = [
    [(0,0),(-2,0),(1,0),(-2,-1),(1,2)],
    [(0,0),(2,0),(-1,0),(2,1),(-1,-2)],
    [(0,0),(-1,0),(2,0),(-1,2),(2,-1)],
    [(0,0),(1,0),(-2,0),(1,-2),(-2,1)],
    [(0,0),(2,0),(-1,0),(2,1),(-1,-2)],
    [(0,0),(-2,0),(1,0),(-2,-1),(1,2)],
    [(0,0),(1,0),(-2,0),(1,-2),(-2,1)],
    [(0,0),(-1,0),(2,0),(-1,2),(2,-1)]
]
const KICK_STATES = [(0,1),(1,0),(1,2),(2,1),(2,3),(3,2),(3,0),(0,3)]
const SHAPES = let all = Vector{Vector{Vector{Tuple{Int,Int}}}}()
    for pattern in FRAMES
        n = length(pattern)
        blocks = Tuple{Int,Int}[]
        for (j,row) in enumerate(pattern)
            for (i,char) in enumerate(row)
                if char == '#'
                    push!(blocks,(i-1,j-1))
                end
            end
        end
        rotations = [blocks]
        for _ in 1:3
            blocks = [(n-1-b[2],b[1]) for b in blocks]
            push!(rotations,blocks)
        end
        push!(all,rotations)
    end
    all
end

struct GameOver <: Exception end
Base.@kwdef mutable struct Stats
    drops::Int=0
    holds::Int=0
    operations::Int=0
    faults::Int=0
    perfect::Int=0
    sent::Int=0
    cancelled::Int=0
    received::Int=0
    combo::Int=0
    chain::Int=0
    kinds::Vector{Int}=zeros(Int,7)
    clears::Vector{Int}=zeros(Int,11)
end
Base.@kwdef mutable struct State
    board::Vector{Int}=zeros(Int,22)
    random::Int=1
    queue::Vector{Int}=Int[]
    hold::Int=0
    used_hold::Bool=false
    kind::Int=1
    position::Tuple{Int,Int,Int}=(0,4,22)
    last::Int=0
    test::Int=0
    keys::Int=0
    drop::Int=0
    fall::Int=0
    ground::Int=0
    resets::Int=0
    lowest::Int=0
    initial_level::Int=1
    level::Int=1
    score::Int=0
    lines::Int=0
    pieces::Int=0
    streak::Int=0
    chain::Int=0
    pending::Vector{Int}=Int[]
    ended::Bool=false
    stats::Stats=Stats()
end
mutable struct Game
    number::Int
    s::State
    history::Vector{State}
    start::State
    saves::Dict{String,Tuple{State,Vector{State},State}}
end
struct Route
    position::Tuple{Int,Int,Int}
    parent::Int
    operation::Int
end
mutable struct Candidate
    kind::Int
    value::Int
    operations::Vector{Int}
    order::Int
end

seed_step(x::Int) = mod(48271*x,2147483647)
spawn(kind::Int) = (0,kind==2 ? 5 : 4,22)
piece_cells(kind::Int,p::Tuple{Int,Int,Int}) = [(p[2]+b[1],p[3]-b[2]) for b in SHAPES[kind][p[1]+1]]
lowest(kind::Int,p::Tuple{Int,Int,Int}) = minimum(b[2] for b in piece_cells(kind,p))
function bag(random::Int)
    pieces = collect(1:7)
    for i in 7:-1:2
        random = seed_step(random)
        j = mod(random,i)+1
        pieces[i],pieces[j] = pieces[j],pieces[i]
    end
    random,pieces
end
function fits(board::Vector{Int},kind::Int,p::Tuple{Int,Int,Int})
    for (x,y) in piece_cells(kind,p)
        if x<1 || x>10 || y<1 || y>22 || (board[y] & (1<<(x-1))) != 0
            return false
        end
    end
    true
end
function move(board::Vector{Int},kind::Int,p::Tuple{Int,Int,Int},op::Int)
    if op==7 || op==8
        b = mod(p[1]+(op==7 ? 1 : 3),4)
        row = findfirst(x->x==(p[1],b),KICK_STATES)
        offsets = kind==2 ? [(0,0)] : (kind==1 ? I_KICKS : ORDINARY_KICKS)[row]
        for (i,d) in enumerate(offsets)
            q = (b,p[2]+d[1],p[3]+d[2])
            if fits(board,kind,q)
                return q,i
            end
        end
        return nothing
    end
    dx = op==1 || op==3 ? -1 : op==2 || op==4 ? 1 : 0
    dy = dx==0 ? -1 : 0
    repeat = op==3 || op==4 || op==6
    q=p
    changed=false
    while true
        next = (q[1],q[2]+dx,q[3]+dy)
        fits(board,kind,next) || break
        q=next
        changed=true
        repeat || break
    end
    changed ? (q,0) : nothing
end
landing(board,kind,p) = let result=move(board,kind,p,6); result === nothing ? p : result[1] end
function placed(board::Vector{Int},kind::Int,p::Tuple{Int,Int,Int})
    next=copy(board)
    for (x,y) in piece_cells(kind,p)
        next[y] |= 1<<(x-1)
    end
    remaining=filter(!=(1023),next)
    n=22-length(remaining)
    append!(remaining,zeros(Int,n))
    remaining,n
end
function evaluate(board::Vector{Int},cleared::Int)
    heights=zeros(Int,10)
    holes=0
    for c in 1:10
        for r in 22:-1:1
            if (board[r] & (1<<(c-1))) != 0
                heights[c]=r
                break
            end
        end
        for r in 1:heights[c]
            if (board[r] & (1<<(c-1))) == 0
                holes += 1
            end
        end
    end
    bump=sum(abs(heights[c]-heights[c+1]) for c in 1:9)
    (heights,holes,bump,76*cleared-51*sum(heights)-36*holes-18*bump)
end
function routes(board::Vector{Int},kind::Int,start::Tuple{Int,Int,Int},target=nothing)
    fits(board,kind,start) || return Route[],nothing
    entries=[Route(start,0,0)]
    seen=Set([start])
    i=1
    while i<=length(entries)
        entry=entries[i]
        if target !== nothing && landing(board,kind,entry.position)==target
            return entries,i
        end
        for op in 1:8
            result=move(board,kind,entry.position,op)
            result === nothing && continue
            p=result[1]
            if !(p in seen)
                push!(seen,p)
                push!(entries,Route(p,i,op))
            end
        end
        i+=1
    end
    target === nothing ? (entries,nothing) : (Route[],nothing)
end
function shortest(routes::Vector{Route},index::Int)
    ops=Int[]
    while routes[index].parent>0
        push!(ops,routes[index].operation)
        index=routes[index].parent
    end
    reverse!(ops)
end
function t_spin(board::Vector{Int},p::Tuple{Int,Int,Int},test::Int)
    corners=[(p[2],p[3]),(p[2]+2,p[3]),(p[2]+2,p[3]-2),(p[2],p[3]-2)]
    blocked=Bool[]
    for (x,y) in corners
        push!(blocked,x<1 || x>10 || y<1 || y>22 || (board[y] & (1<<(x-1))) != 0)
    end
    count(identity,blocked)<3 && return 0
    blocked[p[1]+1] && blocked[mod(p[1]+1,4)+1] || test==5 ? 2 : 1
end
function clear_info(spin::Int,n::Int)
    if spin==2
        return 8+n,[400,800,1200,1600][n+1],[0,2,4,6][n+1]
    elseif spin==1
        return 5+n,[100,200,400][n+1],[0,0,1][n+1]
    end
    n==0 ? 0 : n,[0,100,300,500,800][n+1],[0,0,1,2,4][n+1]
end
ops_text(ops) = join((OPERATIONS[i] for i in ops)," ")
function add_bag!(game::Game)
    s=game.s
    s.random,pieces=bag(s.random)
    append!(s.queue,pieces)
end
function next_piece!(game::Game)
    s=game.s
    kind=popfirst!(s.queue)
    length(s.queue)<5 && add_bag!(game)
    kind
end
function game_over!(game::Game,reason::String)
    println("game over $reason")
    summary(game)
    game.s.ended=true
    throw(GameOver())
end
function spawn_piece!(game::Game,kind::Int)
    s=game.s
    s.kind=kind;s.position=spawn(kind);s.last=0;s.test=0;s.keys=0;s.drop=0;s.fall=0;s.ground=0;s.resets=0
    s.lowest=lowest(kind,s.position)
    fits(s.board,kind,s.position) || game_over!(game,"block out")
end
function new_game(number::Int,seed::Int,level::Int)
    s=State(random=seed,initial_level=level,level=level)
    game=Game(number,s,State[],deepcopy(s),Dict{String,Tuple{State,Vector{State},State}}())
    add_bag!(game)
    spawn_piece!(game,next_piece!(game))
    game.start=deepcopy(game.s)
    game
end
function update!(s::State,p,last,test=0)
    s.position=p;s.last=last;s.test=test
    row=lowest(s.kind,p)
    if row<s.lowest
        s.lowest=row;s.resets=0
    end
end
grounded(s::State) = move(s.board,s.kind,s.position,5) === nothing
function drops!(s::State,points::Int)
    s.score+=points;s.drop+=points;s.stats.drops+=points
end
function insert_garbage!(game::Game,n::Int,hole::Int)
    s=game.s
    if any(!=(0),s.board[end-n+1:end])
        game_over!(game,"top out")
    end
    s.board=vcat(fill(1023 ⊻ (1<<(hole-1)),n),s.board[1:end-n])
end
function operation!(game::Game,op::Int)
    s=game.s
    if op<=8
        s.keys+=1
        result=move(s.board,s.kind,s.position,op)
        if result===nothing
            println("fail ",OPERATIONS[op]);return
        end
        p,test=result
        if op==5 || op==6
            drops!(s,s.position[3]-p[3])
            update!(s,p,1)
            s.fall=0;s.ground=0
        else
            update!(s,p,op>=7 ? 2 : 1,test)
            if s.ground>0 && s.resets<15
                s.ground=0;s.resets+=1
            end
        end
    elseif op==9
        p=landing(s.board,s.kind,s.position)
        rows=s.position[3]-p[3]
        drops!(s,2*rows)
        rows>0 && update!(s,p,1)
        lock!(game)
    elseif op==10
        if grounded(s)
            lock!(game)
        else
            println("fail LOCK")
        end
    else
        if s.used_hold
            println("fail HOLD");return
        end
        s.used_hold=true;s.stats.holds+=1
        previous=s.hold;s.hold=s.kind
        spawn_piece!(game,previous==0 ? next_piece!(game) : previous)
    end
end
function tick!(game::Game)
    s=game.s
    if !grounded(s)
        s.ground=0;s.fall+=1
        interval=s.level>=13 ? 1 : [60,48,37,28,21,16,11,8,6,4,3,2][s.level]
        if s.fall>=interval
            update!(s,(s.position[1],s.position[2],s.position[3]-1),1)
            s.fall=0
        end
    else
        s.ground+=1
        s.ground>=30 && lock!(game)
    end
end
function lock!(game::Game)
    s=game.s
    kind=s.kind;p=s.position
    old_cells=piece_cells(kind,p)
    route,index=routes(s.board,kind,spawn(kind),p)
    shortest_ops=index===nothing ? nothing : shortest(route,index)
    spin=kind==3 && s.last==2 ? t_spin(s.board,p,s.test) : 0
    s.board,n=placed(s.board,kind,p)
    push!(game.history,deepcopy(game.start))
    s.pieces+=1;s.stats.kinds[kind]+=1;s.stats.operations+=s.keys
    clear_name,points,sent=clear_info(spin,n)
    level=s.level;points*=level;back=false
    if n>0
        s.streak+=1
        if n==4 || spin!=0
            s.chain+=1;back=s.chain>=2
        else
            s.chain=0
        end
    else
        s.streak=0
    end
    if back
        points=div(3*points,2);sent+=1
    end
    combo=s.streak-1
    combo_points=combo>=1 ? 50*combo*level : 0
    if combo>=0
        sent+=[0,1,1,2,2,3,3,4,4,4,5][min(combo,10)+1]
    end
    perfect=n>0 && all(==(0),s.board)
    perfect_points=perfect ? (n==4 && back ? 3200 : [800,1200,1800,2000][n])*level : 0
    if perfect
        sent+=10;s.stats.perfect+=1
    end
    gained=points+combo_points+perfect_points
    s.score+=gained;s.lines+=n;s.stats.sent+=sent
    s.stats.combo=max(s.stats.combo,combo);s.stats.chain=max(s.stats.chain,s.chain)
    count_text=shortest_ops===nothing ? "-" : string(length(shortest_ops))
    println("lock $(s.pieces) $(KINDS[kind]) $(STATES[p[1]+1]) $(p[2]) $(p[3]) keys $(s.keys) $count_text drop $(s.drop) lines $n sent $sent +$gained total $(s.score)")
    if shortest_ops !== nothing && s.keys>length(shortest_ops)
        s.stats.faults+=1
        println("finesse ",isempty(shortest_ops) ? "none" : ops_text(shortest_ops))
    end
    if clear_name>0
        s.stats.clears[clear_name]+=1
        line="clear $(CLEAR_NAMES[clear_name]) $points"
        back && (line*=" b2b")
        combo>=1 && (line*=" combo $combo $combo_points")
        perfect && (line*=" perfect $perfect_points")
        println(line)
    end
    next_level=s.initial_level+div(s.lines,10)
    if next_level>level
        s.level=next_level;println("level $(s.level)")
    end
    all(c->c[2]>=21,old_cells) && game_over!(game,"lock out")
    cancelled=min(sent,sum(s.pending))
    remaining=cancelled
    while remaining>0
        used=min(remaining,s.pending[1]);remaining-=used;s.pending[1]-=used
        s.pending[1]==0 && popfirst!(s.pending)
    end
    if cancelled>0
        s.stats.cancelled+=cancelled;println("cancel $cancelled pending $(sum(s.pending))")
    end
    if n==0
        risen=0
        while !isempty(s.pending) && risen<8
            count=min(s.pending[1],8-risen)
            s.random=seed_step(s.random)
            hole=mod(s.random,10)+1
            insert_garbage!(game,count,hole)
            s.stats.received+=count;risen+=count;s.pending[1]-=count
            s.pending[1]==0 && popfirst!(s.pending)
            println("rise $count hole $hole pending $(sum(s.pending))")
        end
    end
    s.used_hold=false
    spawn_piece!(game,next_piece!(game))
    game.start=deepcopy(s)
end
function candidates(s::State,kind::Int,start,prefix::Vector{Int})
    result=Candidate[]
    seen=Set{NTuple{4,Int}}()
    for turns in [Int[],[7],[7,7],[8]]
        p=start
        valid=true
        for op in turns
            next=move(s.board,kind,p,op)
            if next===nothing
                valid=false;break
            end
            p=next[1]
        end
        valid || continue
        function add(q,shifts::Vector{Int})
            landed=landing(s.board,kind,q)
            occupied=sort([(c[2]-1)*10+c[1]-1 for c in piece_cells(kind,landed)])
            key=Tuple(occupied)
            key in seen && return
            push!(seen,key)
            board,n=placed(s.board,kind,landed)
            value=evaluate(board,n)[4]
            push!(result,Candidate(kind,value,vcat(prefix,turns,shifts,[9]),0))
        end
        add(p,Int[])
        for direction in [1,2]
            q=p;shifts=Int[]
            while true
                next=move(s.board,kind,q,direction)
                next===nothing && break
                q=next[1];push!(shifts,direction);add(q,shifts)
            end
        end
    end
    result
end
function ranked(s::State)
    result=candidates(s,s.kind,s.position,Int[])
    held=s.hold==0 ? s.queue[1] : s.hold
    if !s.used_hold && fits(s.board,held,spawn(held))
        append!(result,candidates(s,held,spawn(held),[11]))
    end
    for (i,c) in enumerate(result)
        c.order=i
    end
    sort!(result,by=c->(-c.value,c.order))
end
function spins(s::State)
    if s.kind!=3
        println("spins 0");return
    end
    found=Dict{NTuple{3,Int},Int}()
    for entry in routes(s.board,3,s.position)[1]
        for op in [7,8]
            result=move(s.board,3,entry.position,op)
            result===nothing && continue
            p,test=result
            move(s.board,3,p,5) === nothing || continue
            spin=t_spin(s.board,p,test)
            if spin>0
                found[p]=max(get(found,p,0),spin)
            end
        end
    end
    rows=sort(collect(found),by=x->(x.first[3],x.first[2],x.first[1]))
    for (p,spin) in rows
        _,n=placed(s.board,3,p)
        name=clear_info(spin,n)[1]
        println("spin $(STATES[p[1]+1]) $(p[2]) $(p[3]) $(CLEAR_NAMES[name])")
    end
    println("spins $(length(rows))")
end
function summary(game::Game)
    s=game.s;a=s.stats;c=a.clears
    function ratio(x,y)
        q=y==0 ? 0 : div(100*x,y)
        string(div(q,100),".",lpad(string(mod(q,100)),2,'0'))
    end
    println("summary game $(game.number) score $(s.score) level $(s.level) lines $(s.lines) pieces $(s.pieces)")
    println("clears single $(c[1]) double $(c[2]) triple $(c[3]) tetris $(c[4]) perfect $(a.perfect)")
    println("tspins mini $(c[5]) mini_single $(c[6]) mini_double $(c[7]) zero $(c[8]) single $(c[9]) double $(c[10]) triple $(c[11])")
    println("pieces ",join(["$(KINDS[i]) $(a.kinds[i])" for i in 1:7]," "))
    println("best combo $(a.combo) chain $(a.chain) holds $(a.holds) drops $(a.drops) faults $(a.faults)")
    println("garbage sent $(a.sent) cancelled $(a.cancelled) received $(a.received)")
    println("rates app $(ratio(a.sent,s.pieces)) apl $(ratio(a.sent,s.lines)) kpp $(ratio(a.operations,s.pieces))")
end
function command!(game::Game,command::String,args::Vector{String})
    s=game.s
    if command=="PRINT"
        current=s.ended ? Set{Tuple{Int,Int}}() : Set(piece_cells(s.kind,s.position))
        ghost=s.ended ? Set{Tuple{Int,Int}}() : Set(piece_cells(s.kind,landing(s.board,s.kind,s.position)))
        for r in 22:-1:1
            line=lpad(string(r),2)*" "
            for c in 1:10
                ch=(s.board[r]&(1<<(c-1)))!=0 ? '#' : (c,r) in current ? '@' : (c,r) in ghost ? '+' : '.'
                line*=string(ch)
            end
            println(line)
        end
    elseif command=="NEXT"
        println("hold ",s.hold==0 ? '-' : KINDS[s.hold]," next ",join((KINDS[i] for i in s.queue[1:5])))
    elseif command=="PREVIEW"
        n=parse(Int,args[1]);queue=copy(s.queue);random=s.random
        while length(queue)<n
            random,pieces=bag(random);append!(queue,pieces)
        end
        println("preview ",join((KINDS[i] for i in queue[1:n])))
    elseif command=="STATUS"
        println("score $(s.score) level $(s.level) lines $(s.lines) pieces $(s.pieces)")
        piece=s.ended ? "-" : "$(KINDS[s.kind]) $(STATES[s.position[1]+1]) $(s.position[2]) $(s.position[3])"
        println("piece $piece streak $(s.streak) chain $(s.chain) pending $(sum(s.pending))")
    elseif command=="ANALYZE"
        heights,holes,bump,value=evaluate(s.board,0)
        println("heights ",join(heights," "))
        println("holes $holes bumpiness $bump value $value")
    elseif command=="ROW"
        row=parse(Int,args[1]);pattern=args[2]
        if any(c->c[2]==row && pattern[c[1]]=='#',piece_cells(s.kind,s.position))
            println("ERROR overlap");return
        end
        mask=0
        for i in 1:10
            pattern[i]=='#' && (mask |= 1<<(i-1))
        end
        s.board[row]=mask;println("OK")
    elseif command=="GARBAGE"
        n=parse(Int,args[1]);hole=parse(Int,args[2]);insert_garbage!(game,n,hole)
        for j in 0:n
            p=(s.position[1],s.position[2],s.position[3]+j)
            if fits(s.board,s.kind,p)
                s.position=p;println("OK");return
            end
        end
        game_over!(game,"top out")
    elseif command=="ATTACK"
        push!(s.pending,parse(Int,args[1]));println("pending $(sum(s.pending))")
    elseif command=="TICK"
        for _ in 1:parse(Int,args[1]);tick!(game);end
    elseif command=="UNDO"
        if isempty(game.history)
            println("ERROR nothing to undo")
        else
            game.s=pop!(game.history)
            game.start=deepcopy(game.s)
            println("undo $(game.s.pieces) $(KINDS[game.s.kind])")
        end
    elseif command=="SAVE"
        game.saves[args[1]]=(deepcopy(s),deepcopy(game.history),deepcopy(game.start))
        println("OK")
    elseif command=="LOAD"
        if !haskey(game.saves,args[1])
            println("ERROR unknown save")
        else
            game.s,game.history,game.start=deepcopy(game.saves[args[1]])
            println("load $(game.s.pieces) $(KINDS[game.s.kind])")
        end
    elseif command=="SPINS"
        spins(s)
    elseif command=="HINT"
        list=ranked(s);n=min(parse(Int,args[1]),length(list))
        for i in 1:n
            c=list[i]
            println("hint $i $(KINDS[c.kind]) $(ops_text(c.operations)) value $(c.value)")
        end
    elseif command=="AUTO"
        for _ in 1:parse(Int,args[1])
            c=first(ranked(s))
            println("auto $(KINDS[c.kind]) $(ops_text(c.operations))")
            for op in c.operations
                operation!(game,op)
            end
        end
    end
end
function valid_number(text::String,min_value::Int,max_value::Int)
    occursin(r"^(0|[1-9][0-9]*)$",text) || return false
    n=tryparse(Int,text)
    n!==nothing && min_value<=n<=max_value
end
function valid_args(command::String,args::Vector{String})
    if command=="NEW"
        return length(args)==2 && valid_number(args[1],1,2147483646) && valid_number(args[2],1,15)
    elseif command=="ROW"
        return length(args)==2 && valid_number(args[1],1,22) && occursin(r"^[#.]{10}$",args[2]) && occursin('.',args[2])
    elseif command=="GARBAGE"
        return length(args)==2 && valid_number(args[1],1,10) && valid_number(args[2],1,10)
    elseif command=="SAVE" || command=="LOAD"
        return length(args)==1 && occursin(r"^[a-z]{1,8}$",args[1])
    end
    limits=Dict("PREVIEW"=>14,"ATTACK"=>20,"TICK"=>1000,"HINT"=>10,"AUTO"=>50)
    if haskey(limits,command)
        return length(args)==1 && valid_number(args[1],1,limits[command])
    end
    isempty(args)
end
function main()
    n=parse(Int,readline(stdin))
    game=nothing
    serial=0
    for _ in 1:n
        words=split(readline(stdin),' ')
        command=String(words[1])
        args=String.(words[2:end])
        try
            if command in COMMANDS
                if !valid_args(command,args)
                    println("ERROR bad arguments")
                elseif command=="NEW"
                    if game !== nothing && !game.s.ended
                        println("game stopped");summary(game)
                    end
                    serial+=1
                    println("game $serial seed $(parse(Int,args[1])) level $(parse(Int,args[2]))")
                    game=new_game(serial,parse(Int,args[1]),parse(Int,args[2]))
                elseif game===nothing
                    println("ERROR no game")
                elseif game.s.ended && !(command in AFTER_END)
                    println("ERROR game over")
                else
                    command!(game,command,args)
                end
            else
                invalid=findfirst(w->!(w in OPERATIONS),words)
                if invalid !== nothing
                    println("ERROR unknown $(words[invalid])")
                elseif game===nothing
                    println("ERROR no game")
                elseif game.s.ended
                    println("ERROR game over")
                else
                    for word in words
                        operation!(game,findfirst(==(word),OPERATIONS))
                    end
                end
            end
        catch e
            e isa GameOver || rethrow(e)
        end
    end
    if game !== nothing && !game.s.ended
        println("game stopped");summary(game)
    end
end
main()
