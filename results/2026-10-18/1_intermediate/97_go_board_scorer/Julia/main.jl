using Printf
const COLUMNS="ABCDEFGHJKLMNOPQRST"
const HANDICAP=Dict(9=>split("C3 G7 C7 G3 C5 G5 E3 E7 E5"),13=>split("D4 K10 D10 K4 D7 K7 G4 G10 G7"),19=>split("D4 Q16 D16 Q4 D10 Q10 K4 K16 K10"))
const ARITY=Dict("BOARD"=>2,"KOMI"=>1,"SUPERKO"=>1,"HANDICAP"=>1,"PLAY"=>2,"PASS"=>1,"REPLAY"=>1,"UNDO"=>0,"SHOW"=>0,"MAP"=>0,"STATUS"=>0,"CAPTURES"=>0,"HISTORY"=>0,"MOVES"=>0,"GROUP"=>1,"GROUPS"=>0,"ATARI"=>0,"LEGAL"=>1,"EYES"=>1,"SAFE"=>1,"LADDER"=>1,"DEAD"=>1,"REGIONS"=>0,"SCORE"=>1)
other(c)=c=='B' ? 'W' : 'B'
half(x)=(x<0 ? "-" : "")*string(abs(x)÷2)*(isodd(abs(x)) ? ".5" : ".0")
function komi(s)
    !occursin(r"^-?(0|[1-9][0-9]*)(?:\.[05])?$",s) && return nothing
    parts=split(startswith(s,"-") ? s[2:end] : s,".");whole=tryparse(Int,parts[1])
    (whole===nothing || whole>100) && return nothing
    x=2*whole+(length(parts)==2 && parts[2]=="5" ? 1 : 0)
    startswith(s,"-") && x==0 && return nothing
    startswith(s,"-") ? -x : x
end
function adjacent(p,n,diagonal=false)
    r,c=divrem(p-1,n);steps=diagonal ? ((-1,-1),(-1,1),(1,-1),(1,1)) : ((-1,0),(1,0),(0,-1),(0,1))
    [(r+dr)*n+c+dc+1 for (dr,dc) in steps if 0<=r+dr<n && 0<=c+dc<n]
end
function flood(b,n,p,allowed)
    seen=Set([p]);todo=[p]
    while !isempty(todo)
        for q in adjacent(pop!(todo),n)
            if !(q in seen) && b[q] in allowed;push!(seen,q);push!(todo,q);end
        end
    end
    seen
end
struct Group
    color::Char
    first::Int
    stones::Set{Int}
    liberties::Set{Int}
end
function group(b,n,p)
    s=flood(b,n,p,(b[p],));l=Set(t for q in s for t in adjacent(q,n) if b[t]=='.')
    Group(b[p],minimum(s),s,l)
end
function groups(b,n,color='.')
    seen=Set{Int}();out=Group[]
    for p in eachindex(b)
        if b[p]!='.' && !(p in seen) && (color=='.' || color==b[p])
            g=group(b,n,p);union!(seen,g.stones);push!(out,g)
        end
    end
    out
end
function placement(b,n,c,p)
    b[p]!='.' && return (b,0,"occupied")
    next=copy(b);next[p]=c;captured=0;seen=Set{Int}()
    for q in adjacent(p,n)
        if next[q]==other(c) && !(q in seen)
            g=group(next,n,q);union!(seen,g.stones)
            if isempty(g.liberties)
                for t in g.stones;next[t]='.';end
                captured+=length(g.stones)
            end
        end
    end
    (next,captured,isempty(group(next,n,p).liberties) ? "suicide" : "")
end
function regions(b,n)
    seen=Set{Int}();out=Tuple{Int,Set{Int},String}[]
    for p in eachindex(b)
        if b[p]=='.' && !(p in seen)
            points=flood(b,n,p,('.',));union!(seen,points)
            border=Set(b[t] for q in points for t in adjacent(q,n) if b[t]!='.')
            push!(out,(p,points,length(border)==1 ? string(first(border)) : "neutral"))
        end
    end
    out
end
function safe_groups(b,n,c)
    own=groups(b,n,c);areas=Tuple{Set{Int},Set{Int}}[];seen=Set{Int}()
    for p in eachindex(b)
        if b[p]!=c && !(p in seen)
            area=flood(b,n,p,('.',other(c)));union!(seen,area);empty=Set(q for q in area if b[q]=='.')
            touch=Set(i for i in eachindex(own) if any(q->any(t->t in own[i].stones,adjacent(q,n)),area))
            vital=Set(i for i in eachindex(own) if issubset(empty,own[i].liberties))
            push!(areas,(touch,vital))
        end
    end
    s=Set(eachindex(own));t=Set(eachindex(areas))
    while true
        count=length(s)+length(t)
        filter!(i->sum(i in areas[j][2] for j in t;init=0)>=2,s)
        filter!(j->issubset(areas[j][1],s),t)
        count==length(s)+length(t) && break
    end
    own[sort!(collect(s))]
end
function ladder(b,n,p)
    defender=b[p];attacker=other(defender);memo=Dict{Tuple{String,Int,Bool},Tuple{Bool,Int}}()
    function read(current,depth,defending)
        depth>=40 && return (defending,0)
        key=(join(current),depth,defending);haskey(memo,key) && return memo[key]
        g=group(current,n,p);candidates=copy(g.liberties);seen=Set{Int}()
        if defending
            for q in g.stones,t in adjacent(q,n)
                if current[t]==attacker && !(t in seen)
                    enemy=group(current,n,t);union!(seen,enemy.stones)
                    length(enemy.liberties)==1 && union!(candidates,enemy.liberties)
                end
            end
        end
        for q in sort!(collect(candidates))
            next,_,reason=placement(current,n,defending ? defender : attacker,q);!isempty(reason) && continue
            if defending
                m=length(group(next,n,p).liberties);success=m>=3 || (m==2 && !read(next,depth+1,false)[1])
            else success=!read(next,depth+1,true)[1] end
            if success;memo[key]=(true,q);return memo[key];end
        end
        memo[key]=(false,0)
    end
    count=length(group(b,n,p).liberties);count>=3 && return ("safe",0)
    success,move=read(b,0,count==1)
    ((count==1 ? success : !success) ? "escapes" : "captured",move)
end
struct Snapshot
    board::Vector{Char};turn::Char;black::Int;white::Int;passes::Int;over::Bool
end
struct Move
    color::Char;point::Int;captured::Int;before::Snapshot
end
mutable struct Game
    n::Int;komi::Int;board::Vector{Char};turn::Char;captures::Dict{Char,Int};passes::Int;over::Bool
    handicap::Vector{Int};history::Vector{Move};positions::Vector{Vector{Char}};superko::Bool;dead::Set{Int}
end
Game()=Game(19,13,fill('.',361),'B',Dict('B'=>0,'W'=>0),0,false,Int[],Move[],[fill('.',361)],false,Set{Int}())
emit(a...)=println(join(a," "))
function reset!(g,n,k)
    g.n=n;g.komi=k;g.board=fill('.',n*n);g.turn='B';g.captures=Dict('B'=>0,'W'=>0);g.passes=0;g.over=false
    empty!(g.handicap);empty!(g.history);g.positions=[g.board];empty!(g.dead)
end
function point(g,s)
    !occursin(r"^[A-HJ-T](?:[1-9]|1[0-9])$",s) && return 0
    c=findfirst(==(s[1]),COLUMNS);r=parse(Int,s[2:end]);c<=g.n && r<=g.n ? (r-1)*g.n+c : 0
end
name(g,p)=string(COLUMNS[(p-1)%g.n+1],(p-1)÷g.n+1)
sgf(g,p)=string(Char(97+(p-1)%g.n),Char(97+g.n-1-(p-1)÷g.n))
function check(g,c,p)
    b,captured,reason=placement(g.board,g.n,c,p)
    isempty(reason) && length(g.positions)>=2 && b==g.positions[end-1] && (reason="ko")
    isempty(reason) && g.superko && b in g.positions && (reason="superko")
    (b,captured,reason)
end
function move!(g,c,p,checked=nothing)
    before=Snapshot(g.board,g.turn,g.captures['B'],g.captures['W'],g.passes,g.over);captured=0
    if p==0;g.passes+=1;g.passes==2 && (g.over=true)
    else
        g.board,captured,_=checked===nothing ? check(g,c,p) : checked
        g.captures[c]+=captured;g.passes=0
    end
    g.turn=other(c);push!(g.history,Move(c,p,captured,before));push!(g.positions,g.board);empty!(g.dead);captured
end
clean(g)=[p in g.dead ? '.' : c for (p,c) in enumerate(g.board)]
function show_board(g,map=false)
    b=map ? clean(g) : g.board;chars=copy(b)
    stars=Set(point(g,s) for (i,s) in enumerate(HANDICAP[g.n]) if g.n==19 || i<=4 || i==9)
    if map
        for (_,points,owner) in regions(b,g.n),p in points;chars[p]=owner=="B" ? 'x' : owner=="W" ? 'o' : '.';end
    end
    for p in eachindex(b)
        if b[p]!='.'
            c=b[p]=='B' ? 'X' : 'O';chars[p]=!map && p in g.dead ? lowercase(c) : c
        elseif !map;chars[p]=p in stars ? '+' : '.' end
    end
    header="   "*join(collect(COLUMNS[1:g.n])," ");emit(header)
    for r in g.n:-1:1;emit(@sprintf("%2d",r),join(chars[(r-1)*g.n+1:r*g.n]," "),r);end
    emit(header)
end
function score(g,method)
    b=clean(g);territory=Dict('B'=>0,'W'=>0);totals=Dict{Char,Int}()
    for (_,points,owner) in regions(b,g.n);owner!="neutral" && (territory[owner[1]]+=length(points));end
    for c in ('B','W')
        if method=="AREA"
            stones=count(==(c),b);totals[c]=2*(stones+territory[c])+(c=='W' ? g.komi : 0)
            emit(c,"stones",stones,"territory",territory[c],(c=='W' ? ["komi",half(g.komi)] : String[])...,"total",half(totals[c]))
        else
            prisoners=g.captures[c]+count(p->g.board[p]==other(c),g.dead);totals[c]=2*(territory[c]+prisoners)+(c=='W' ? g.komi : 0)
            emit(c,"territory",territory[c],"prisoners",prisoners,(c=='W' ? ["komi",half(g.komi)] : String[])...,"total",half(totals[c]))
        end
    end
    d=totals['B']-totals['W'];emit("result",d>0 ? "B+"*half(d) : d<0 ? "W+"*half(-d) : "Draw")
end
function execute(g,line)
    words=split(line," ");c=words[1];a=words[2:end]
    !haskey(ARITY,c) && return emit("ERROR unknown command")
    length(a)!=ARITY[c] && return emit("ERROR bad arguments")
    valid=c=="BOARD" ? a[1] in ("9","13","19") && komi(a[2])!==nothing : c=="KOMI" ? komi(a[1])!==nothing : c=="SUPERKO" ? a[1] in ("ON","OFF") : c=="HANDICAP" ? occursin(r"^[2-9]$",a[1]) : c in ("PLAY","PASS","LEGAL","EYES","SAFE") ? a[1] in ("B","W") : c=="SCORE" ? a[1] in ("AREA","TERRITORY") : true
    !valid && return emit("ERROR bad arguments")
    p=0
    if c in ("PLAY","GROUP","LADDER","DEAD");p=point(g,a[c=="PLAY" ? 2 : 1]);p==0 && return emit("ERROR bad point");end
    records=Tuple{Char,Int}[]
    if c=="REPLAY"
        !occursin(r"^(?:;[BW]\[[a-z]{0,2}\])+$",a[1]) && return emit("ERROR bad sequence")
        for m in eachmatch(r";([BW])\[([a-z]*)\]",a[1])
            s=m[2]
            if !isempty(s) && (length(s)!=2 || any(ch->Int(ch)-97>=g.n,s));return emit("ERROR bad sequence");end
            q=isempty(s) ? 0 : (g.n-1-(Int(s[2])-97))*g.n+Int(s[1])-96
            push!(records,(m[1][1],q))
        end
    end
    c in ("PLAY","PASS","REPLAY") && g.over && return emit("ERROR game over")
    if c=="BOARD";reset!(g,parse(Int,a[1]),komi(a[2]));emit("board",g.n,"komi",half(g.komi))
    elseif c=="KOMI";g.komi=komi(a[1]);emit("komi",half(g.komi))
    elseif c=="SUPERKO";g.superko=a[1]=="ON";emit("superko",g.superko ? "on" : "off")
    elseif c=="HANDICAP"
        (!isempty(g.history) || any(!=('.'),g.board)) && return emit("ERROR handicap not allowed")
        k=parse(Int,a[1]);indices=k==5 ? [1,2,3,4,9] : k==7 ? [1,2,3,4,5,6,9] : collect(1:k)
        g.handicap=[point(g,HANDICAP[g.n][i]) for i in indices];g.board=copy(g.board)
        for q in g.handicap;g.board[q]='B';end
        g.turn='W';g.positions=[g.board];empty!(g.dead);emit("handicap",k,[name(g,q) for q in g.handicap]...)
    elseif c=="PLAY"
        color=a[1][1];checked=check(g,color,p);reason=color!=g.turn ? "turn" : checked[3]
        if !isempty(reason);emit("ILLEGAL",color,a[2],reason)
        else captured=move!(g,color,p,checked);emit(color,a[2],(captured>0 ? ["captures",string(captured)] : String[])...) end
    elseif c=="PASS"
        color=a[1][1]
        if color!=g.turn;emit("ILLEGAL",color,"pass turn")
        else move!(g,color,0);emit(color,"pass");g.over && emit("game over") end
    elseif c=="REPLAY"
        count=0;stopped=String[]
        for (color,q) in records
            checked=q==0 ? nothing : check(g,color,q);reason=g.over ? "game over" : color!=g.turn ? "turn" : checked===nothing ? "" : checked[3]
            if !isempty(reason);stopped=["stopped",string(color),q==0 ? "pass" : name(g,q),reason];break;end
            move!(g,color,q,checked);count+=1
        end
        emit("replay",count,"moves",stopped...);g.over && emit("game over")
    elseif c=="UNDO"
        isempty(g.history) && return emit("ERROR nothing to undo")
        m=pop!(g.history);s=m.before;g.board=s.board;g.turn=s.turn;g.captures=Dict('B'=>s.black,'W'=>s.white);g.passes=s.passes;g.over=s.over
        pop!(g.positions);empty!(g.dead);emit("undo",m.color,m.point==0 ? "pass" : name(g,m.point))
    elseif c in ("SHOW","MAP");show_board(g,c=="MAP")
    elseif c=="STATUS"
        emit("size",g.n,"komi",half(g.komi),"handicap",length(g.handicap),"superko",g.superko ? "on" : "off")
        emit("moves",length(g.history),(g.over ? ["game over"] : ["next",string(g.turn),"passes",string(g.passes)])...)
    elseif c=="CAPTURES";emit("captures B",g.captures['B'],"W",g.captures['W'])
    elseif c=="HISTORY"
        emit("history",length(g.history))
        for (i,m) in enumerate(g.history);emit(i,m.color,m.point==0 ? "pass" : name(g,m.point),(m.captured>0 ? ["captures",string(m.captured)] : String[])...);end
    elseif c=="MOVES"
        s="(;GM[1]FF[4]SZ[$(g.n)]KM[$(half(g.komi))]"
        !isempty(g.handicap) && (s*="HA[$(length(g.handicap))]AB"*join(["["*sgf(g,q)*"]" for q in g.handicap]))
        s*=join([";$(m.color)[$(m.point==0 ? "" : sgf(g,m.point))]" for m in g.history]);emit(s*")")
    elseif c in ("GROUP","DEAD","LADDER")
        g.board[p]=='.' && return emit("ERROR no stone")
        gr=group(g.board,g.n,p)
        if c=="GROUP"
            emit("group",gr.color,name(g,gr.first),"size",length(gr.stones),"liberties",length(gr.liberties))
            emit("stones",[name(g,q) for q in sort!(collect(gr.stones))]...);emit("liberties",[name(g,q) for q in sort!(collect(gr.liberties))]...)
        elseif c=="DEAD"
            alive=p in g.dead;alive ? setdiff!(g.dead,gr.stones) : union!(g.dead,gr.stones)
            emit(alive ? "alive" : "dead",gr.color,name(g,gr.first),"size",length(gr.stones))
        else status,q=ladder(g.board,g.n,p);emit("ladder",a[1],status,(q==0 ? String[] : [name(g,q)])...) end
    elseif c=="GROUPS"
        gs=groups(g.board,g.n);emit("groups",length(gs))
        for gr in gs;emit(gr.color,name(g,gr.first),"size",length(gr.stones),"liberties",length(gr.liberties),(gr.first in g.dead ? ["dead"] : String[])...);end
    elseif c=="ATARI"
        gs=filter(gr->length(gr.liberties)==1,groups(g.board,g.n));isempty(gs) && emit("atari none")
        for gr in gs;emit("atari",gr.color,name(g,gr.first),"size",length(gr.stones),"at",name(g,first(gr.liberties)));end
    elseif c=="LEGAL"
        rejected=Tuple{String,String}[];count=0
        for q in eachindex(g.board)
            g.board[q]!='.' && continue
            reason=check(g,a[1][1],q)[3];isempty(reason) ? (count+=1) : push!(rejected,(name(g,q),reason))
        end
        emit("legal",a[1],count);for r in rejected;emit(r...);end
    elseif c=="EYES"
        found=Tuple{String,String}[]
        for q in eachindex(g.board)
            g.board[q]!='.' && continue
            ns=adjacent(q,g.n);!all(t->g.board[t]==a[1][1],ns) && continue
            enemies=Base.count(t->g.board[t]==other(a[1][1]),adjacent(q,g.n,true));push!(found,(name(g,q),enemies<=(length(ns)==4 ? 1 : 0) ? "real" : "false"))
        end
        emit("eyes",a[1],length(found));for r in found;emit(r...);end
    elseif c=="SAFE"
        gs=safe_groups(g.board,g.n,a[1][1]);emit("safe",a[1],length(gs));for gr in gs;emit(name(g,gr.first),"size",length(gr.stones));end
    elseif c=="REGIONS"
        rs=regions(clean(g),g.n);emit("regions",length(rs));for (q,points,owner) in rs;emit(name(g,q),"size",length(points),owner);end
    elseif c=="SCORE";score(g,a[1])
    end
end
function main()
    g=Game()
    for _ in 1:parse(Int,readline());execute(g,readline());end
end
main()
