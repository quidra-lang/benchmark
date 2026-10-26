const WEIGHTS=[
    100,
    -20,
    10,
    5,
    5,
    10,
    -20,
    100,
    -20,
    -50,
    -2,
    -2,
    -2,
    -2,
    -50,
    -20,
    10,
    -2,
    -1,
    -1,
    -1,
    -1,
    -2,
    10,
    5,
    -2,
    -1,
    -1,
    -1,
    -1,
    -2,
    5,
    5,
    -2,
    -1,
    -1,
    -1,
    -1,
    -2,
    5,
    10,
    -2,
    -1,
    -1,
    -1,
    -1,
    -2,
    10,
    -20,
    -50,
    -2,
    -2,
    -2,
    -2,
    -50,
    -20,
    100,
    -20,
    10,
    5,
    5,
    10,
    -20,
    100,
]
const TRANSFORMS=["rot90", "rot180", "rot270", "mirror", "flip", "diag", "anti"]
const ZERO=split("NEW DUMP SHOW SCORE LEGAL HISTORY SHEET STATS EVAL STABLE SOLVE")
const NUMERIC=split("UNDO REDO HINT PV AI ANALYZE RANDOM PERFT DIVIDE")
const ACTIVE=split("FLIPS MOVE PLAY HINT PV AI SOLVE AUTOPLAY RANDOM MC DIVIDE")
const COMMANDS=vcat(ZERO, NUMERIC, split("LOAD TRANSFORM AUTOPLAY MC FLIPS MOVE PLAY RECORD"))
other(s) = s=='B' ? 'W' : 'B'
square_name(p) = string(Char(Int('a')+mod(p, 8)), div(p, 8)+1)
square_index(s) = 8*(Int(s[2])-Int('1'))+Int(s[1])-Int('a')
inside(r, c) = 0<=r<8&&0<=c<8
function initial()
    b=fill('.', 64)
    b[28]=b[37]='W'
    b[29]=b[36]='B'
    String(b)
end
function flips(b, s, p)
    b[p+1]!='.'&&return Int[]
    row, col=divrem(p, 8)
    out=Int[]
    for dr in -1:1, dc in -1:1
        dr==0&&dc==0&&continue
        r=row+dr
        c=col+dc
        line=Int[]
        while inside(r, c)&&b[8*r+c+1]==other(s)
            push!(line, 8*r+c)
            r+=dr
            c+=dc
        end
        !isempty(line)&&inside(r, c)&&b[8*r+c+1]==s&&append!(out, line)
    end
    sort!(out)
end
legal(b, s) = [p for p in 0:63 if b[p+1]=='.'&&!isempty(flips(b, s, p))]
function place(b, s, p)
    a=collect(b)
    for q in flips(b, s, p)
        a[q+1]=s
    end
    a[p+1]=s
    String(a)
end
terminal(b) = isempty(legal(b, 'B'))&&isempty(legal(b, 'W'))
function game_over(b)
    x=count(==('B'), b)
    y=count(==('W'), b)
    "game over B $x W $y "*(x>y ? "winner B" : x<y ? "winner W" : "draw")
end
function evaluate(b, s)
    w=sum(b[i]==s ? WEIGHTS[i] : b[i]==other(s) ? -WEIGHTS[i] : 0 for i in 1:64)
    own=length(legal(b, s))
    enemy=length(legal(b, other(s)))
    (w+10*(own-enemy), w, own, enemy)
end
const SEARCH_CACHE=Dict{Tuple{String,Char,Int},Int}();
const PERFT_CACHE=Dict{Tuple{String,Char,Int},Int}()
function search(b, s, d)
    key=(b, s, d)
    haskey(SEARCH_CACHE, key)&&return SEARCH_CACHE[key]
    ms=legal(b, s)
    o=other(s)
    v=if isempty(ms)&&isempty(legal(b, o))
        (d<0 ? 1 : 1000)*(count(==(s), b)-count(==(o), b))
    elseif d==0
        evaluate(b, s)[1]
    elseif isempty(ms)
        -search(b, o, d<0 ? -1 : d-1)
    else
        maximum(-search(place(b, s, p), o, d<0 ? -1 : d-1) for p in ms)
    end
    length(SEARCH_CACHE)>300000&&empty!(SEARCH_CACHE)
    SEARCH_CACHE[key]=v
    v
end
ranked(b, s, d) = sort(
    [(-search(place(b, s, p), other(s), d<0 ? -1 : d-1), p) for p in legal(b, s)];
    by = x->(-x[1], x[2]),
)
function variation(b, s, d)
    steps=String[]
    while d!=0&&!terminal(b)
        ms=ranked(b, s, d)
        if isempty(ms)
            push!(steps, "pass")
        else
            p=ms[1][2]
            push!(steps, square_name(p))
            b=place(b, s, p)
        end
        s=other(s)
        d>0&&(d-=1)
    end
    steps, b
end
function perft(b, s, d)
    d==0&&return 1
    key=(b, s, d)
    haskey(PERFT_CACHE, key)&&return PERFT_CACHE[key]
    ms=legal(b, s)
    o=other(s)
    n=isempty(ms) ? (isempty(legal(b, o)) ? 1 : perft(b, o, d-1)) :
      sum(perft(place(b, s, p), o, d-1) for p in ms)
    length(PERFT_CACHE)>200000&&empty!(PERFT_CACHE)
    PERFT_CACHE[key]=n
    n
end
function stable(b)
    stable=falses(64)
    axes=[(0, 1), (1, 0), (1, 1), (1, -1)]
    while true
        found=Int[]
        for p in 0:63
            (b[p+1]=='.'||stable[p+1])&&continue
            row, col=divrem(p, 8)
            ok=true
            for (dr, dc) in axes
                full=true
                anchor=false
                for sign in [-1, 1]
                    r=row+dr*sign
                    c=col+dc*sign
                    (!inside(r, c)||(stable[8*r+c+1]&&b[8*r+c+1]==b[p+1]))&&(anchor=true)
                    while inside(r, c)
                        b[8*r+c+1]=='.'&&(full=false)
                        r+=dr*sign
                        c+=dc*sign
                    end
                end
                if !full&&!anchor
                    ok=false
                    break
                end
            end
            ok&&push!(found, p)
        end
        isempty(found)&&break
        for p in found
            stable[p+1]=true
        end
    end
    [count(i->stable[i]&&b[i]==s, 1:64) for s in ['B', 'W']]
end
function transform(p, op)
    r, c=divrem(p, 8)
    op=="rot90"&&return 8*c+7-r
    op=="rot180"&&return 63-p
    op=="rot270"&&return 8*(7-c)+r
    op=="mirror"&&return 8*r+7-c
    op=="flip"&&return 8*(7-r)+c
    op=="diag"&&return 8*c+r
    8*(7-c)+7-r
end
function transform_board(b, op)
    a=fill('.', 64)
    for p in 0:63
        a[transform(p, op)+1]=b[p+1]
    end
    String(a)
end
mutable struct Minstd
    value::Int
end
draw!(rng) = (rng.value=mod(48271*rng.value, 2147483647))
function random_game(b, s, rng)
    while true
        ms=legal(b, s)
        if !isempty(ms)
            b=place(b, s, ms[mod(draw!(rng), length(ms))+1])
        elseif isempty(legal(b, other(s)))
            return b
        end
        s=other(s)
    end
end
average(f, n) =
    let v=div(100*f, n)
        string(div(v, 100), ".", lpad(string(mod(v, 100)), 2, '0'))
    end
struct Position
    board::String
    side::Char
    over::Bool
end
struct Move
    side::Char
    square::Int
    count::Int
    passed::Bool
    before::Position
    after::Position
end
mutable struct Othello
    board::String
    side::Char
    over::Bool
    history::Vector{Move}
    redo::Vector{Move}
end
Othello() = Othello(initial(), 'B', false, Move[], Move[])
emit(xs...) = println(join(xs, " "))
snapshot(e) = Position(e.board, e.side, e.over)
function restore!(e, p)
    e.board=p.board
    e.side=p.side
    e.over=p.over
end
status(e) = e.over ? game_over(e.board) : string(e.side, " to move")
function reset!(e)
    restore!(e, Position(initial(), 'B', false))
    empty!(e.history)
    empty!(e.redo)
end
function adjust!(e, quiet = false)
    !isempty(legal(e.board, e.side))&&return false
    if !isempty(legal(e.board, other(e.side)))
        !quiet&&emit(e.side, "passes")
        e.side=other(e.side)
        return true
    end
    e.over=true
    !quiet&&emit(game_over(e.board))
    false
end
function move!(e, p, quiet = false, value = nothing)
    before=snapshot(e)
    s=e.side
    k=length(flips(e.board, s, p))
    e.board=place(e.board, s, p)
    if !quiet
        value===nothing ? emit(s, square_name(p), "flips", k) :
        emit(s, square_name(p), "flips", k, "value", value)
    end
    e.side=other(s)
    passed=adjust!(e, quiet)
    push!(e.history, Move(s, p, k, passed, before, snapshot(e)))
    empty!(e.redo)
    passed
end
reason(e, p) =
    e.over ? "game over" :
    e.board[p+1]!='.' ? "occupied" : isempty(flips(e.board, e.side, p)) ? "no flips" : ""
function record!(e, text)
    temp=Othello()
    ps=[square_index(text[i:(i+1)]) for i in 1:2:length(text)]
    passes=0
    for (i, p) in enumerate(ps)
        why=reason(temp, p)
        if !isempty(why)
            emit("ILLEGAL move", i, square_name(p), why)
            return
        end
        passes+=move!(temp, p, true)
    end
    restore!(e, snapshot(temp))
    e.history=temp.history
    empty!(e.redo)
    op=get(Dict("f5"=>"", "e6"=>"diag", "d3"=>"anti", "c4"=>"rot180"), square_name(ps[1]), "")
    emit("record", length(ps), "moves", passes, "passes")
    emit("normal", join(square_name(isempty(op) ? p : transform(p, op)) for p in ps))
    emit(status(e))
end
function sheet(e)
    fields=string.(collect(isempty(e.history) ? e.board : e.history[1].before.board))
    for (i, r) in enumerate(e.history)
        fields[r.square+1]=string(i)
    end
    emit(" "*join(lpad(string(c), 3) for c in 'a':'h'))
    for r in 0:7
        emit(string(r+1)*join(lpad(x, 3) for x in fields[(8*r+1):(8*r+8)]))
    end
end
function stats(e)
    rows=e.history
    n=length(rows)
    total=sum(r.count for r in rows; init = 0)
    n==0 ? emit("moves 0") :
    emit("moves", n, "flips", total, "avg", average(total, n), "passes", count(r->r.passed, rows))
    for s in ['B', 'W']
        rs=filter(r->r.side==s, rows)
        if isempty(rs)
            emit(s, "moves 0")
            continue
        end
        total=sum(r.count for r in rs)
        max=maximum(r.count for r in rs)
        first=rs[findfirst(r->r.count==max, rs)]
        emit(
            s,
            "moves",
            length(rs),
            "flips",
            total,
            "avg",
            average(total, length(rs)),
            "max",
            max,
            square_name(first.square),
            "corners",
            count(r->r.square in [0, 7, 56, 63], rs),
        )
    end
end
function autoplay!(e, black, white, seed = 0)
    rng=Minstd(seed)
    ps=String[]
    passes=0
    while !e.over
        ms=legal(e.board, e.side)
        p=seed!=0 ? ms[mod(draw!(rng), length(ms))+1] :
          ranked(e.board, e.side, e.side=='B' ? black : white)[1][2]
        push!(ps, square_name(p))
        passes+=move!(e, p, true)
    end
    emit(seed!=0 ? "random" : "autoplay", length(ps), "moves", passes, "passes")
    emit("moves", join(ps))
    emit(game_over(e.board))
end
function monte_carlo(e, k, seed)
    rng=Minstd(seed)
    best=-1
    bp=-1
    for p in legal(e.board, e.side)
        w=d=l=0
        start=place(e.board, e.side, p)
        for _ in 1:k
            b=random_game(start, other(e.side), rng)
            diff=count(==(e.side), b)-count(==(other(e.side)), b)
            if diff>0
                w+=1
            elseif diff<0
                l+=1
            else
                d+=1
            end
        end
        emit(square_name(p), w, d, l)
        if 2*w+d>best
            best=2*w+d
            bp=p
        end
    end
    emit("best", square_name(bp), best)
end
function execute!(e, text)
    a=String.(split(text))
    cmd=popfirst!(a)
    error=""
    if !(cmd in COMMANDS)
        error="unknown command"
    elseif cmd=="LOAD"
        !(length(a)==2&&occursin(r"^[.BW]{64}$", a[1])&&a[2] in ["B", "W"])&&(error="bad board")
    elseif cmd in ["MOVE", "FLIPS"]
        error=length(a)!=1 ? "bad arguments" : occursin(r"^[a-h][1-8]$", a[1]) ? "" : "bad square"
    elseif cmd in ["PLAY", "RECORD"]
        error=length(a)!=1 ? "bad arguments" :
              length(a[1])<=120&&occursin(r"^([a-h][1-8])+$", a[1]) ? "" : "bad record"
    elseif cmd in ZERO
        !isempty(a)&&(error="bad arguments")
    elseif cmd=="TRANSFORM"
        !(length(a)==1&&a[1] in TRANSFORMS)&&(error="bad arguments")
    else
        expected=cmd in ["AUTOPLAY", "MC"] ? 2 : 1
        valid=length(a)==expected&&all(s->occursin(r"^[0-9]+$", s), a)
        if valid
            n=parse.(Int, a)
            valid=if cmd=="AUTOPLAY"
                all(x->1<=x<=4, n)
            elseif cmd in ["HINT", "PV", "AI", "ANALYZE"]
                1<=n[1]<=4
            elseif cmd in ["PERFT", "DIVIDE"]
                1<=n[1]<=8
            elseif cmd=="MC"
                1<=n[1]<=100&&1<=n[2]<=2147483646
            elseif cmd=="RANDOM"
                1<=n[1]<=2147483646
            else
                n[1]>=1
            end
        end
        !valid&&(error="bad arguments")
    end
    if !isempty(error)
        emit("ERROR", error)
        return
    end
    if e.over&&cmd in ACTIVE
        emit("ERROR game over")
        return
    end
    n=!isempty(a)&&occursin(r"^[0-9]+$", a[1]) ? parse(Int, a[1]) : 0
    if cmd=="NEW"
        reset!(e)
        emit("OK")
    elseif cmd=="LOAD"
        restore!(e, Position(a[1], a[2][1], false))
        empty!(e.history)
        empty!(e.redo)
        emit("OK")
        adjust!(e)
    elseif cmd=="DUMP"
        emit("board", e.board, e.side)
    elseif cmd=="SHOW"
        emit("  a b c d e f g h")
        ms=e.over ? Int[] : legal(e.board, e.side)
        for r in 0:7
            emit(r+1, [8*r+c in ms ? '*' : e.board[8*r+c+1] for c in 0:7]...)
        end
        emit(status(e))
    elseif cmd=="SCORE"
        emit(
            "score B",
            count(==('B'), e.board),
            "W",
            count(==('W'), e.board),
            "empty",
            count(==('.'), e.board),
        )
    elseif cmd=="LEGAL"
        ms=e.over ? Int[] : legal(e.board, e.side)
        emit("legal", length(ms), square_name.(ms)...)
    elseif cmd in ["MOVE", "FLIPS"]
        p=square_index(a[1])
        why=reason(e, p)
        if !isempty(why)
            emit("ILLEGAL", why)
        elseif cmd=="MOVE"
            move!(e, p)
        else
            f=flips(e.board, e.side, p)
            emit("flips", a[1], length(f), square_name.(f)...)
        end
    elseif cmd=="PLAY"
        for (i, j) in enumerate(1:2:length(a[1]))
            p=square_index(a[1][j:(j+1)])
            why=reason(e, p)
            if !isempty(why)
                emit("ILLEGAL move", i, square_name(p), why)
                break
            end
            move!(e, p)
        end
    elseif cmd=="RECORD"
        record!(e, a[1])
    elseif cmd=="UNDO"
        if n>length(e.history)
            emit("ERROR cannot undo")
        else
            start=length(e.history)-n+1
            removed=e.history[start:end]
            restore!(e, removed[1].before)
            resize!(e.history, start-1)
            e.redo=vcat(removed, e.redo)
            emit(status(e))
        end
    elseif cmd=="REDO"
        if n>length(e.redo)
            emit("ERROR cannot redo")
        else
            added=e.redo[1:n]
            e.redo=e.redo[(n+1):end]
            append!(e.history, added)
            restore!(e, added[end].after)
            emit(status(e))
        end
    elseif cmd=="HISTORY"
        emit("history", length(e.history))
        for (i, r) in enumerate(e.history)
            r.passed ? emit(i, r.side, square_name(r.square), r.count, "pass") :
            emit(i, r.side, square_name(r.square), r.count)
        end
    elseif cmd=="SHEET"
        sheet(e)
    elseif cmd=="STATS"
        stats(e)
    elseif cmd=="TRANSFORM"
        op=a[1]
        e.board=transform_board(e.board, op)
        tr(r) = Move(
            r.side,
            transform(r.square, op),
            r.count,
            r.passed,
            Position(transform_board(r.before.board, op), r.before.side, r.before.over),
            Position(transform_board(r.after.board, op), r.after.side, r.after.over),
        )
        e.history=tr.(e.history)
        e.redo=tr.(e.redo)
        emit("OK")
    elseif cmd=="EVAL"
        v, w, x, y=evaluate(e.board, e.side)
        emit("eval", v, "weights", w, "mobility", x, y)
    elseif cmd=="STABLE"
        b, w=stable(e.board)
        emit("stable B", b, "W", w)
    elseif cmd=="HINT"
        for (v, p) in ranked(e.board, e.side, n)
            emit(square_name(p), v)
        end
    elseif cmd=="PV"
        steps, _=variation(e.board, e.side, n)
        emit("pv", search(e.board, e.side, n), steps...)
    elseif cmd=="AI"
        v, p=ranked(e.board, e.side, n)[1]
        move!(e, p, false, v)
    elseif cmd=="ANALYZE"
        loss=Dict('B'=>0, 'W'=>0)
        for (i, r) in enumerate(e.history)
            rows=ranked(r.before.board, r.side, n)
            best, bp=rows[1]
            v=rows[findfirst(x->x[2]==r.square, rows)][1]
            loss[r.side]+=best-v
            emit(i, r.side, square_name(r.square), v, "best", square_name(bp), best)
        end
        emit("loss B", loss['B'], "W", loss['W'])
    elseif cmd=="SOLVE"
        if count(==('.'), e.board)>=9
            emit("ERROR too many empties")
        else
            for (v, p) in ranked(e.board, e.side, -1)
                emit(square_name(p), v)
            end
            steps, b=variation(e.board, e.side, -1)
            emit("line", steps...)
            emit("final B", count(==('B'), b), "W", count(==('W'), b))
        end
    elseif cmd=="AUTOPLAY"
        autoplay!(e, n, parse(Int, a[2]))
    elseif cmd=="RANDOM"
        autoplay!(e, 0, 0, n)
    elseif cmd=="MC"
        monte_carlo(e, n, parse(Int, a[2]))
    elseif cmd=="PERFT"
        emit("perft", n, perft(e.board, e.side, n))
    elseif cmd=="DIVIDE"
        total=0
        for p in legal(e.board, e.side)
            v=perft(place(e.board, e.side, p), other(e.side), n-1)
            emit(square_name(p), v)
            total+=v
        end
        emit("total", total)
    end
end
function main()
    e=Othello()
    for _ in 1:parse(Int, readline())
        execute!(e, readline())
    end
end
main()
