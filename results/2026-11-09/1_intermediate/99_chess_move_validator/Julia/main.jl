const FILES="abcdefgh"
const RANKS="12345678"
const INITIAL="rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
const ROOK=[(0, 1), (0, -1), (-1, 0), (1, 0)]
const BISHOP=[(1, 1), (-1, 1), (1, -1), (-1, -1)]
const KING=vcat(ROOK, BISHOP)
const KNIGHT=[(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
struct Rule
    king::Int
    rook::Int
    target::Int
    rooktarget::Int
    path::Vector{Int}
end
const RULES=Dict(
    'K'=>Rule(4, 7, 6, 5, [5, 6]),
    'Q'=>Rule(4, 0, 2, 3, [1, 2, 3]),
    'k'=>Rule(60, 63, 62, 61, [61, 62]),
    'q'=>Rule(60, 56, 58, 59, [57, 58, 59]),
)
struct Move
    source::Int
    target::Int
    promotion::Char
end
Move(s, t) = Move(s, t, '\0')
struct Record
    san::String
    uci::String
    captured::Char
end
struct InputError <: Exception
    reason::String
end
fail(s) = throw(InputError(s))
color(p) = isuppercase(p) ? 'w' : 'b'
opposite(c) = c=='w' ? 'b' : 'w'
colored(p, c) = c=='w' ? p : lowercase(p)
pawnstep(c) = c=='w' ? 8 : -8
square(s) = occursin(r"^[a-h][1-8]$", s) ? Int(s[1]-'a')+8*Int(s[2]-'1') : -1
sqname(s) = string(FILES[s%8+1], RANKS[s÷8+1])
function number(s, lo, hi)
    occursin(r"^(0|[1-9][0-9]{0,8})$", s)||return -1
    n=parse(Int, s)
    lo<=n<=hi ? n : -1
end
function shift(s, dx, dy)
    x, y=s%8+dx, s÷8+dy
    0<=x<8&&0<=y<8 ? 8*y+x : -1
end
function targets(b, s)
    piece=b[s+1]
    kind=uppercase(piece)
    a=Int[]
    if kind in "PNK"
        dirs=kind=='P' ? [(-1, color(piece)=='w' ? 1 : -1), (1, color(piece)=='w' ? 1 : -1)] :
             kind=='N' ? KNIGHT : KING
        for (dx, dy) in dirs
            t=shift(s, dx, dy)
            t>=0&&push!(a, t)
        end
    else
        dirs=kind=='Q' ? KING : kind=='R' ? ROOK : BISHOP
        for (dx, dy) in dirs
            t=shift(s, dx, dy)
            while t>=0
                push!(a, t)
                b[t+1]!='.'&&break
                t=shift(t, dx, dy)
            end
        end
    end
    a
end
attackers(b, t, c) = [s for s in 0:63 if b[s+1]!='.'&&color(b[s+1])==c&&t in targets(b, s)]
mutable struct Position
    board::Vector{Char}
    side::Char
    rights::String
    ep::Int
    half::Int
    full::Int
    cached::Union{Nothing,Vector{Move}}
end
Position(b, s, r, e, h, f) = Position(b, s, r, e, h, f, nothing)
incheck(p::Position, c = p.side) =
    !isempty(attackers(p.board, findfirst(==(colored('K', c)), p.board)-1, opposite(c)))
iscastle(p, m) = uppercase(p.board[m.source+1])=='K'&&abs(m.target-m.source)==2
isenpassant(p, m) =
    uppercase(p.board[m.source+1])=='P'&&m.source%8!=m.target%8&&p.board[m.target+1]=='.'
iscapture(p, m) = p.board[m.target+1]!='.'||isenpassant(p, m)
captured(p, m) =
    p.board[m.target+1]!='.' ? lowercase(p.board[m.target+1]) : isenpassant(p, m) ? 'p' : '-'
function play(p::Position, m::Move)
    b=copy(p.board)
    piece=b[m.source+1]
    kind=uppercase(piece)
    isenpassant(p, m)&&(b[m.target-pawnstep(p.side)+1]='.')
    if iscastle(p, m)
        r=RULES[colored(m.target>m.source ? 'K' : 'Q', p.side)]
        b[r.rooktarget+1]=b[r.rook+1]
        b[r.rook+1]='.'
    end
    b[m.target+1]=m.promotion=='\0' ? piece : colored(m.promotion, p.side)
    b[m.source+1]='.'
    rights=join(
        r for r in p.rights if
        (kind!='K'||color(r)!=p.side)&&RULES[r].rook!=m.source&&RULES[r].rook!=m.target
    )
    Position(
        b,
        opposite(p.side),
        rights,
        kind=='P'&&abs(m.target-m.source)==16 ? (m.source+m.target)÷2 : -1,
        kind=='P'||iscapture(p, m) ? 0 : p.half+1,
        p.full+(p.side=='b'),
    )
end
function pseudo(p::Position)
    result=Move[]
    for s in 0:63
        piece=p.board[s+1]
        (piece=='.'||color(piece)!=p.side)&&continue
        pawn=uppercase(piece)=='P'
        a=Int[]
        if pawn
            d=pawnstep(p.side)
            if p.board[s+d+1]=='.'
                push!(a, s+d)
                s÷8==(p.side=='w' ? 1 : 6)&&p.board[s+2*d+1]=='.'&&push!(a, s+2*d)
            end
            append!(
                a,
                [
                    t for t in targets(p.board, s) if
                    (p.board[t+1]!='.'&&color(p.board[t+1])!=p.side)||t==p.ep
                ],
            )
        else
            append!(
                a,
                [t for t in targets(p.board, s) if p.board[t+1]=='.'||color(p.board[t+1])!=p.side],
            )
        end
        for t in a
            if pawn&&t÷8==(p.side=='w' ? 7 : 0)
                for promotion in "QRBN"
                    push!(result, Move(s, t, promotion))
                end
            else
                push!(result, Move(s, t))
            end
        end
    end
    result
end
function castlingmove(p, k)
    r=RULES[colored(k ? 'K' : 'Q', p.side)]
    Move(r.king, r.target)
end
function castlingproblem(p, k)
    right=colored(k ? 'K' : 'Q', p.side)
    r=RULES[right]
    right in p.rights||return "no castling right"
    any(p.board[s+1]!='.' for s in r.path)&&return "path blocked"
    incheck(p)&&return "in check"
    !isempty(attackers(p.board, r.rooktarget, opposite(p.side)))&&return "through check"
    incheck(play(p, castlingmove(p, k)), p.side)&&return "into check"
    ""
end
function legal(p::Position)
    p.cached!==nothing&&return p.cached
    a=[m for m in pseudo(p) if !incheck(play(p, m), p.side)]
    for k in (true, false)
        isempty(castlingproblem(p, k))&&push!(a, castlingmove(p, k))
    end
    p.cached=a
    a
end
function checkmark(p, m)
    q=play(p, m)
    incheck(q) ? (isempty(legal(q)) ? "#" : "+") : ""
end
function disambiguation(p, m)
    a=[
        x for x in legal(p) if
        !iscastle(p, x)&&x.target==m.target&&x.source!=m.source&&p.board[x.source+1]==p.board[m.source+1]
    ]
    isempty(a)&&return ""
    all(x.source%8!=m.source%8 for x in a)&&return string(FILES[m.source%8+1])
    all(x.source÷8!=m.source÷8 for x in a)&&return string(RANKS[m.source÷8+1])
    sqname(m.source)
end
function san(p, m)
    kind=uppercase(p.board[m.source+1])
    text=if iscastle(p, m)
        m.target>m.source ? "O-O" : "O-O-O"
    elseif kind=='P'
        (iscapture(p, m) ? string(FILES[m.source%8+1], "x") : "")*sqname(m.target)*(
            m.promotion=='\0' ? "" : "="*string(m.promotion)
        )
    else
        string(kind)*disambiguation(p, m)*(iscapture(p, m) ? "x" : "")*sqname(m.target)
    end
    text*checkmark(p, m)
end
key(p) =
    join(p.board)*" "*string(p.side)*" "*p.rights*" "*string(
        p.ep>=0&&any(isenpassant(p, m) for m in legal(p)) ? p.ep : -1,
    )
state(p) =
    incheck(p) ? (isempty(legal(p)) ? "checkmate" : "check") :
    (isempty(legal(p)) ? "stalemate" : "normal")
function insufficient(p)
    a=[s for s in 0:63 if p.board[s+1]!='.'&&uppercase(p.board[s+1])!='K']
    any(uppercase(p.board[s+1]) in "PRQ" for s in a)&&return false
    length(a)<=1||(
        all(uppercase(p.board[s+1])=='B' for s in a)&&length(unique([(s%8+s÷8)%2 for s in a]))==1
    )
end
function pins(p)
    k=findfirst(==(colored('K', p.side)), p.board)-1
    a=Tuple{Int,Int}[]
    for (dx, dy) in KING
        first=-1
        t=shift(k, dx, dy)
        while t>=0
            piece=p.board[t+1]
            if piece!='.'
                if first<0
                    color(piece)!=p.side&&break
                    first=t
                else
                    color(piece)!=p.side&&(
                        uppercase(piece)=='Q'||uppercase(piece)==(dx==0||dy==0 ? 'R' : 'B')
                    )&&push!(a, (first, t))
                    break
                end
            end
            t=shift(t, dx, dy)
        end
    end
    sort(a)
end
function fen(p)
    rows=String[]
    for r in 7:-1:0
        row=IOBuffer()
        empty=0
        for f in 0:7
            piece=p.board[8*r+f+1]
            if piece=='.'
                empty+=1
            else
                empty>0&&print(row, empty)
                empty=0
                print(row, piece)
            end
        end
        empty>0&&print(row, empty)
        push!(rows, String(take!(row)))
    end
    join(
        (
            join(rows, "/"),
            p.side,
            isempty(p.rights) ? "-" : p.rights,
            p.ep<0 ? "-" : sqname(p.ep),
            p.half,
            p.full,
        ),
        " ",
    )
end
function parsefen(a)
    length(a)==6||fail("fields")
    rows=split(a[1], '/'; keepempty = true)
    length(rows)==8||fail("placement")
    b=fill('.', 64)
    for (i, row) in enumerate(rows)
        f=0
        digit=false
        for c in row
            if c in '1':'8'
                digit&&fail("placement")
                f+=Int(c-'0')
                digit=true
            else
                (c in "KQRBNPkqrbnp"&&f<8)||fail("placement")
                b[(8-i)*8+f+1]=c
                f+=1
                digit=false
            end
        end
        f==8||fail("placement")
    end
    (count(==('K'), b)==1&&count(==('k'), b)==1)||fail("kings")
    any(c in "Pp" for c in vcat(b[1:8], b[57:64]))&&fail("pawns")
    a[2] in ("w", "b")||fail("side")
    side=a[2][1]
    (a[3]=="-"||(!isempty(a[3])&&occursin(r"^K?Q?k?q?$", a[3])))||fail("castling")
    rights=a[3]=="-" ? "" : String(a[3])
    for r in rights
        rule=RULES[r]
        (b[rule.king+1]==colored('K', color(r))&&b[rule.rook+1]==colored('R', color(r)))||fail(
            "castling",
        )
    end
    ep=-1
    if a[4]!="-"
        ep=square(a[4])
        d=pawnstep(side)
        (
            ep>=0&&ep÷8==(side=='w' ? 5 : 2)&&b[ep+1]=='.'&&b[ep+d+1]=='.'&&b[ep-d+1]==colored(
                'P',
                opposite(side),
            )
        )||fail("en passant")
    end
    half=number(a[5], 0, 999)
    full=number(a[6], 1, 999)
    (half>=0&&full>=0&&(ep<0||half==0))||fail("clocks")
    p=Position(b, side, rights, ep, half, full)
    incheck(p, opposite(side))&&fail("check")
    p
end
function readsan(p, text)
    mark=last(text) in "+#" ? string(last(text)) : ""
    body=isempty(mark) ? String(text) : chop(text)
    castling=body in ("O-O", "O-O-O")
    promotion='\0'
    target=-1
    capture=false
    kind='P'
    file=""
    rank=""
    if !castling
        if length(body)>=2&&body[end-1]=='='
            promotion=body[end]
            promotion in "QRBN"||fail("syntax")
            body=chop(body; tail = 2)
        end
        length(body)>=2||fail("syntax")
        target=square(body[(end-1):end])
        target>=0||fail("syntax")
        body=chop(body; tail = 2)
        capture=endswith(body, "x")
        capture&&(body=chop(body))
        if !isempty(body)&&body[1] in "KQRBN"
            kind=body[1]
            h=match(r"^([a-h]?)([1-8]?)$", body[2:end])
            (h!==nothing&&promotion=='\0')||fail("syntax")
            file=String(h[1])
            rank=String(h[2])
        else
            occursin(capture ? r"^[a-h]$" : r"^$", body)||fail("syntax")
            file=body
        end
    end
    moves=legal(p)
    isempty(moves)&&fail("game over")
    if castling
        k=body=="O-O"
        problem=castlingproblem(p, k)
        isempty(problem)||fail(problem)
        m=castlingmove(p, k)
    else
        matches(m) =
            uppercase(p.board[m.source+1])==kind&&m.target==target&&!iscastle(p, m)&&(
                isempty(file)||FILES[m.source%8+1]==file[1]
            )&&(isempty(rank)||RANKS[m.source÷8+1]==rank[1])&&(
                kind!='P'||(m.source%8!=m.target%8)==capture
            )
        a=filter(matches, moves)
        isempty(a)&&fail(any(matches, pseudo(p)) ? "leaves king in check" : "no such move")
        length(unique(m.source for m in a))>1&&fail("ambiguous")
        m=a[1]
        iscapture(p, m)==capture||fail("capture mark")
        m.promotion!='\0'&&promotion=='\0'&&fail("missing promotion")
        promotion!='\0'&&m.promotion=='\0'&&fail("invalid promotion")
        kind!='P'&&file*rank!=disambiguation(p, m)&&fail("disambiguation")
        m=Move(m.source, m.target, promotion)
    end
    checkmark(p, m)==mark||fail("check mark")
    m
end
function readuci(p, text)
    occursin(r"^[a-h][1-8][a-h][1-8][qrbn]?$", text)||fail("syntax")
    s=square(text[1:2])
    t=square(text[3:4])
    promotion=length(text)==5 ? uppercase(text[5]) : '\0'
    moves=legal(p)
    isempty(moves)&&fail("game over")
    (p.board[s+1]!='.'&&color(p.board[s+1])==p.side)||fail("no piece")
    a=[m for m in moves if m.source==s&&m.target==t]
    isempty(a)&&fail(
        any(m.source==s&&m.target==t for m in pseudo(p)) ? "leaves king in check" : "no such move",
    )
    m=a[1]
    m.promotion!='\0'&&promotion=='\0'&&fail("missing promotion")
    promotion!='\0'&&m.promotion=='\0'&&fail("invalid promotion")
    Move(s, t, promotion)
end
function perft(p, d, stats = nothing)
    d==0&&return 1
    total=0
    for m in legal(p)
        q=play(p, m)
        total+=perft(q, d-1, stats)
        if d==1&&stats!==nothing
            stats[1]+=1
            stats[2]+=iscapture(p, m)
            stats[3]+=isenpassant(p, m)
            stats[4]+=iscastle(p, m)
            stats[5]+=m.promotion!='\0'
            if incheck(q)
                stats[6]+=1
                stats[7]+=isempty(legal(q))
            end
        end
    end
    total
end
mutable struct Game
    positions::Vector{Position}
    records::Vector{Record}
    loaded::Bool
end
Game(start = parsefen(split(INITIAL)), loaded = false) = Game([start], Record[], loaded)
current(g) = g.positions[end]
function play!(g, m)
    p=current(g)
    push!(
        g.records,
        Record(
            san(p, m),
            sqname(m.source)*sqname(m.target)*(
                m.promotion=='\0' ? "" : string(lowercase(m.promotion))
            ),
            captured(p, m),
        ),
    )
    push!(g.positions, play(p, m))
end
repetition(g) = count(p->key(p)==key(current(g)), g.positions)
function draws(g)
    a=String[]
    current(g).half>=100&&push!(a, "fifty")
    repetition(g)>=3&&push!(a, "threefold")
    insufficient(current(g))&&push!(a, "insufficient")
    a
end
function result(g)
    s=state(current(g))
    s=="checkmate" ? (current(g).side=='b' ? "1-0" : "0-1") :
    s=="stalemate"||!isempty(draws(g)) ? "1/2-1/2" : "*"
end
function execute(g, line)
    w=split(line)
    cmd=w[1]
    a=w[2:end]
    if !(
        cmd in split(
            "NEW LOAD FEN BOARD MOVE UCI LEGAL STATUS UNDO PERFT DIVIDE ATTACKS PINS HISTORY PGN",
        )
    )
        println("ERROR unknown command")
        return g
    end
    bad=cmd in split("NEW FEN BOARD STATUS PINS HISTORY PGN")&&!isempty(a)
    cmd in ("MOVE", "UCI")&&(bad=isempty(a))
    cmd=="LEGAL"&&(bad=length(a)>1||(length(a)==1&&square(a[1])<0))
    cmd=="ATTACKS"&&(bad=length(a)!=1||(length(a)==1&&square(a[1])<0))
    n=-1
    if cmd in ("UNDO", "PERFT", "DIVIDE")
        n=length(a)==1 ? number(a[1], 1, cmd=="UNDO" ? 9999 : 3) : -1
        bad=n<0
    end
    if bad
        println("ERROR bad arguments")
        return g
    end
    p=current(g)
    if cmd=="NEW"
        g=Game()
        println("OK")
    elseif cmd=="LOAD"
        try
            q=parsefen(a)
            g=Game(q, true)
            println("OK")
        catch e
            e isa InputError||rethrow()
            println("ERROR bad fen ($(e.reason))")
        end
    elseif cmd=="FEN"
        println(fen(p))
    elseif cmd=="BOARD"
        for r in 7:-1:0
            println(join(vcat(string(r+1), string.(p.board[(8*r+1):(8*r+8)])), " "))
        end
        println("  a b c d e f g h")
    elseif cmd in ("MOVE", "UCI")
        played=String[]
        failure=""
        for (i, text) in enumerate(a)
            try
                m=cmd=="MOVE" ? readsan(current(g), text) : readuci(current(g), text)
                play!(g, m)
                push!(played, g.records[end].san)
            catch e
                e isa InputError||rethrow()
                failure="ILLEGAL move $i: $text ($(e.reason))"
                break
            end
        end
        cmd=="UCI"&&!isempty(played)&&println("san ", join(played, " "))
        if !isempty(failure)
            println(failure)
        elseif cmd=="MOVE"
            println("OK")
        end
    elseif cmd=="LEGAL"
        list=sort([san(p, m) for m in legal(p) if isempty(a)||m.source==square(a[1])])
        println(join(vcat(["legal", string(length(list))], list), " "))
    elseif cmd=="STATUS"
        println(
            join(
                vcat(
                    [
                        "status",
                        p.side=='w' ? "white" : "black",
                        state(p),
                        "rep",
                        string(repetition(g)),
                    ],
                    draws(g),
                ),
                " ",
            ),
        )
    elseif cmd=="UNDO"
        if n>length(g.records)
            println("ERROR cannot undo")
        else
            resize!(g.records, length(g.records)-n)
            resize!(g.positions, length(g.positions)-n)
            println("OK")
        end
    elseif cmd=="PERFT"
        stats=zeros(Int, 7)
        perft(p, n, stats)
        row=["perft", string(n)]
        for (i, f) in
            enumerate(("nodes", "captures", "ep", "castles", "promotions", "checks", "mates"))
            append!(row, [f, string(stats[i])])
        end
        println(join(row, " "))
    elseif cmd=="DIVIDE"
        rows=sort([(san(p, m), perft(play(p, m), n-1)) for m in legal(p)]; by = first)
        for (s, v) in rows
            println(s, " ", v)
        end
        println("total ", sum((last(r) for r in rows); init = 0))
    elseif cmd=="ATTACKS"
        row=["attacks", String(a[1])]
        for c in ('w', 'b')
            found=attackers(p.board, square(a[1]), c)
            append!(row, [c=='w' ? "white" : "black", string(length(found))])
            append!(row, sqname.(found))
        end
        println(join(row, " "))
    elseif cmd=="PINS"
        found=pins(p)
        println(
            join(
                vcat(
                    ["pins", string(length(found))],
                    [sqname(s)*"-"*sqname(t) for (s, t) in found],
                ),
                " ",
            ),
        )
    elseif cmd=="HISTORY"
        println("history ", length(g.records))
        for (i, r) in enumerate(g.records)
            println(i, " ", r.uci, " ", r.san, " ", r.captured)
        end
    elseif cmd=="PGN"
        r=result(g)
        println("[Result \"$r\"]")
        if g.loaded
            println("[SetUp \"1\"]")
            println("[FEN \"$(fen(g.positions[1]))\"]")
        end
        row=String[]
        for (i, record) in enumerate(g.records)
            q=g.positions[i]
            if q.side=='w'
                push!(row, "$(q.full).")
            elseif i==1
                push!(row, "$(q.full)...")
            end
            push!(row, record.san)
        end
        push!(row, r)
        println(join(row, " "))
    end
    g
end
function main()
    lines=readlines()
    g=Game()
    for i in 1:parse(Int, lines[1])
        g=execute(g, lines[i+1])
    end
end
main()
