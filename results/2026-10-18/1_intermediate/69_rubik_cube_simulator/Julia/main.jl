const FACES="URFDLB"
const COLORS="WRGYOB"
const SOLVED=collect(join(repeat(string(c),9) for c in COLORS))
const Move=Tuple{Char,Int}
const LETTERS="UDFBLRMESudfblrxyz"
const AXIS=Dict(c=>i for (i,group) in enumerate(("RLMrlx","UDEudy","FBSfbz")) for c in group)
const OPPOSITE=Dict(a=>b for pair in ("RL","UD","FB","rl","ud","fb") for (a,b) in ((pair[1],pair[2]),(pair[2],pair[1])))
const FRAMES=(((0,1,0),(1,0,0),(0,0,1)),((1,0,0),(0,0,-1),(0,-1,0)),((0,0,1),(1,0,0),(0,-1,0)),((0,-1,0),(1,0,0),(0,0,-1)),((-1,0,0),(0,0,1),(0,-1,0)),((0,0,-1),(-1,0,0),(0,-1,0)))
const TURNS=Dict('R'=>(1,1,[1]),'L'=>(1,3,[-1]),'M'=>(1,3,[0]),'r'=>(1,1,[0,1]),'l'=>(1,3,[-1,0]),'x'=>(1,1,[-1,0,1]),'U'=>(2,1,[1]),'D'=>(2,3,[-1]),'E'=>(2,3,[0]),'u'=>(2,1,[0,1]),'d'=>(2,3,[-1,0]),'y'=>(2,1,[-1,0,1]),'F'=>(3,1,[1]),'B'=>(3,3,[-1]),'S'=>(3,1,[0]),'f'=>(3,1,[0,1]),'b'=>(3,3,[-1,0]),'z'=>(3,1,[-1,0,1]))
struct CommandError <: Exception
    message::String
end
fail(s)=throw(CommandError(s))
require(b,s="bad arguments")=b ? nothing : fail(s)
part(s,a,b=length(s))=a>b ? "" : String(s[a:b])
inverse(moves)=Move[(c,4-a) for (c,a) in reverse(moves)]
movetext(move)=string(move[1])*(move[2]==1 ? "" : move[2]==2 ? "2" : "'")
movestext(moves)=join(movetext.(moves)," ")
sequence(moves)=string(length(moves))*(isempty(moves) ? "" : " "*movestext(moves))
plainmoves(s)=Move[(word[1],length(word)==1 ? 1 : word[2]=='2' ? 2 : 3) for word in split(s)]
function quarter(v,axis)
    a=mod1(axis+1,3); b=mod1(axis+2,3)
    ntuple(i->i==a ? v[b] : i==b ? -v[a] : v[i],3)
end
function tables()
    places=[(ntuple(i->normal[i]+c*column[i]+r*row[i],3),normal) for (normal,column,row) in FRAMES for r in -1:1 for c in -1:1]
    numbers=Dict(place=>i for (i,place) in enumerate(places)); result=Dict{Move,Vector{Int}}()
    for (letter,(axis,turns,layers)) in TURNS
        perm=collect(1:54)
        for (i,(position,normal)) in enumerate(places)
            if position[axis] in layers
                for _ in 1:turns; position=quarter(position,axis); normal=quarter(normal,axis); end
                perm[numbers[(position,normal)]]=i
            end
        end
        power=collect(1:54)
        for a in 1:3; power=power[perm]; result[(letter,a)]=power; end
    end
    result
end
const TABLES=tables()
function applymoves(state,moves)
    for move in moves; state=state[TABLES[move]]; end
    state
end
effect(moves)=applymoves(collect(1:54),moves)
const BYEFFECT=Dict(Tuple(table)=>move for (move,table) in TABLES)
const ROTATIONS=[plainmoves(a*" "*b) for a in ("","x","x2","x'","z","z'") for b in ("","y","y2","y'")]
const ROTATIONEFFECT=Dict(Tuple(effect(r))=>r for r in ROTATIONS)
const REPLACEMENTS=Dict(k=>plainmoves(v) for (k,v) in ('M'=>"R L' x'",'E'=>"U D' y'",'S'=>"F' B z",'r'=>"L x",'l'=>"R x'",'u'=>"D y",'d'=>"U y'",'f'=>"B z",'b'=>"F z'"))
struct PieceKind
    names::Vector{String}
    stickers::Vector{Vector{Int}}
    colors::Vector{Vector{Char}}
end
function piecekind(names,layout)
    stickers=[[9*(findfirst(==(label[1]),FACES)-1)+parse(Int,part(label,2)) for label in split(row)] for row in layout]
    colors=[[COLORS[findfirst(==(c),FACES)] for c in name] for name in names]
    PieceKind(names,stickers,colors)
end
const CORNERS=piecekind(String.(split("URF UFL ULB UBR DFR DLF DBL DRB")),["U9 R1 F3","U7 F1 L3","U1 L1 B3","U3 B1 R3","D3 F9 R7","D1 L9 F7","D7 B9 L7","D9 R9 B7"])
const EDGES=piecekind(String.(split("UR UF UL UB DR DF DL DB FR FL BL BR")),["U6 R2","U8 F2","U4 L2","U2 B2","D6 R8","D2 F8","D4 L8","D8 B8","F6 R4","F4 L6","B6 L4","B4 R6"])
const CENTERS=piecekind(string.(collect(FACES)),[string(c)*"5" for c in FACES])
function contents(kind,state)
    result=Tuple{Int,Int}[]
    for stickers in kind.stickers
        colors=state[stickers]; found=(0,0)
        for (p,target) in enumerate(kind.colors), t in 0:length(colors)-1
            if [colors[mod1(i+t,length(colors))] for i in eachindex(colors)]==target; found=(p,t); break; end
        end
        push!(result,found)
    end
    result
end
function cycles(kind,state)
    pieces=contents(kind,state); locations=zeros(Int,length(pieces)); turns=zeros(Int,length(pieces)); seen=falses(length(pieces)); result=String[]
    for (position,(piece,t)) in enumerate(pieces); locations[piece]=position; turns[piece]=t; end
    for start in eachindex(pieces)
        seen[start] && continue
        cycle=Int[]; p=start
        while !seen[p]; seen[p]=true; push!(cycle,p); p=locations[p]; end
        remainder=mod(sum(turns[cycle]),length(kind.stickers[1])); mark=("","+","-")[remainder+1]
        if length(cycle)>=2 || !isempty(mark); push!(result,"("*join(kind.names[cycle]," ")*")"*mark); end
    end
    isempty(result) ? "none" : join(result," ")
end
solved(state)=all(i->all(==(state[i+4]),state[i:i+8]),1:9:54)
function normalization(state)
    for rotation in ROTATIONS
        moved=applymoves(state,rotation)
        all(i->moved[9*(i-1)+5]==COLORS[i],1:6) && return rotation
    end
    nothing
end
normalized(state)=applymoves(state,normalization(state))
parity(pieces)=mod(sum(pieces[i][1]>pieces[j][1] for i in eachindex(pieces) for j in i+1:length(pieces);init=0),2)
function invalid(s)
    length(s)==54 || return "length $(length(s))"
    for (i,c) in enumerate(s); c in COLORS || return "char $i"; end
    for c in COLORS; n=count(==(c),s); n==9 || return "count $c $n"; end
    state=collect(s); rotation=normalization(state); rotation===nothing && return "centers"
    c=contents(CORNERS,state); e=contents(EDGES,state)
    for (kind,pieces,label) in ((CORNERS,c,"corner"),(EDGES,e,"edge"))
        missing=findfirst(x->x[1]==0,pieces); missing!==nothing && return "$label $(kind.names[missing])"
    end
    for (kind,pieces) in ((CORNERS,c),(EDGES,e)), (i,name) in enumerate(kind.names)
        any(x->x[1]==i,pieces) || return "missing $name"
    end
    normal=applymoves(state,rotation); c=contents(CORNERS,normal); e=contents(EDGES,normal)
    mod(sum(last,c),3)==0 || return "twist"
    mod(sum(last,e),2)==0 || return "flip"
    parity(c)==parity(e) || return "parity"
    nothing
end
function simplify(moves)
    while true
        result=Move[]; at=1
        while at<=length(moves)
            axis=AXIS[moves[at][1]]; letters=Char[]; totals=Dict{Char,Int}()
            while at<=length(moves) && AXIS[moves[at][1]]==axis
                c,a=moves[at]; !haskey(totals,c) && push!(letters,c); totals[c]=mod(get(totals,c,0)+a,4); at+=1
            end
            append!(result,[(c,totals[c]) for c in letters if totals[c]!=0])
        end
        result==moves && return result
        moves=result
    end
end
function unrotate(moves)
    expanded=Move[]
    for (c,a) in moves
        append!(expanded,haskey(REPLACEMENTS,c) ? [(d,mod(b*a,4)) for (d,b) in REPLACEMENTS[c]] : [(c,a)])
    end
    held=Move[]; result=Move[]
    for move in expanded
        if move[1] in "xyz"; held=ROTATIONEFFECT[Tuple(effect([held;[move]]))]
        else; push!(result,BYEFFECT[Tuple(effect([held;[move];inverse(held)]))]); end
    end
    [result;held]
end
function permutationorder(table)
    seen=falses(54); result=1
    for start in 1:54
        n=0; p=start
        while !seen[p]; seen[p]=true; n+=1; p=table[p]; end
        n>0 && (result=lcm(result,n))
    end
    result
end
function scramble(n,seed)
    result=Move[]
    for _ in 1:n
        faces=[c for c in FACES if isempty(result) || c!=last(result)[1]]
        if length(result)>=2 && AXIS[result[end][1]]==AXIS[result[end-1][1]]; filter!(c->AXIS[c]!=AXIS[result[end][1]],faces); end
        seed=mod(48271*seed,2147483647); c=faces[mod(seed,length(faces))+1]
        seed=mod(48271*seed,2147483647); push!(result,(c,(1,3,2)[mod(seed,3)+1]))
    end
    result
end
function searchdepth(state,depth,previous=' ')
    depth==0 && return solved(state) ? Move[] : nothing
    for c in FACES, a in 1:3
        (c==previous || (previous=='D' && c=='U') || (previous=='L' && c=='R') || (previous=='B' && c=='F')) && continue
        found=searchdepth(state[TABLES[(c,a)]],depth-1,c)
        found!==nothing && return [[(c,a)];found]
    end
    nothing
end
mutable struct Parser
    line::String
    at::Int
    macros::Dict{String,Vector{Move}}
end
current(p)=p.at<=length(p.line) ? p.line[p.at] : '\0'
function accept!(p,c)
    current(p)==c || return false
    p.at+=1; true
end
syntax(p)=fail("syntax at $(min(p.at,length(p.line)+1))")
skip!(p)=begin while current(p)==' '; p.at+=1; end; end
function power!(p,moves)
    n=1
    if '1'<=current(p)<='9'
        n=Int(current(p)-'0'); p.at+=1
        if '0'<=current(p)<='9'; n=10n+Int(current(p)-'0'); p.at+=1; end
    end
    result=repeat(moves,n)
    accept!(p,'\'') ? inverse(result) : result
end
function readsequence!(p)
    result=Move[]
    while true
        skip!(p); c=current(p)
        if c in LETTERS
            p.at+=1; a=accept!(p,'2') ? 2 : accept!(p,'\'') ? 3 : 1; push!(result,(c,a))
        elseif c=='('
            p.at+=1; moves=readsequence!(p); skip!(p); accept!(p,')') || syntax(p); append!(result,power!(p,moves))
        elseif c=='['
            p.at+=1; first=readsequence!(p); skip!(p); separator=current(p); separator in (',',':') || syntax(p)
            p.at+=1; second=readsequence!(p); skip!(p); accept!(p,']') || syntax(p)
            append!(result,power!(p,[first;second;inverse(first);separator==',' ? inverse(second) : Move[]]))
        elseif c=='{'
            p.at+=1; start=p.at
            while 'a'<=current(p)<='z'; p.at+=1; end
            name=part(p.line,start,p.at-1); !isempty(name) && current(p)=='}' || syntax(p)
            haskey(p.macros,name) || fail("undefined $name"); p.at+=1; append!(result,power!(p,p.macros[name]))
        else; return result; end
    end
end
function parse_sequence(line,start,macros)
    p=Parser(line,start,macros); result=readsequence!(p); skip!(p); current(p)=='\0' || syntax(p)
    require(length(result)<=500,"too long"); result
end
mutable struct Simulator
    state::Vector{Char}
    history::Vector{Move}
    redo::Vector{Move}
    macros::Dict{String,Vector{Move}}
    saves::Dict{String,Tuple{Vector{Char},Vector{Move}}}
end
Simulator()=Simulator(copy(SOLVED),Move[],Move[],Dict{String,Vector{Move}}(),Dict{String,Tuple{Vector{Char},Vector{Move}}}())
function record!(s,moves)
    s.state=applymoves(s.state,moves); append!(s.history,moves); empty!(s.redo)
end
function execute!(s,line)
    splitat=findfirst(' ',line); cmd=splitat===nothing ? line : part(line,1,splitat-1); argument=splitat===nothing ? "" : part(line,splitat+1)
    noargs=("RESET","SHOW","STATE","ISSOLVED","HISTORY","SOLUTION","ANALYZE","STAGE","MACROS")
    wordcounts=Dict("CHECK"=>1,"LOAD"=>1,"UNDO"=>1,"REDO"=>1,"SEARCH"=>1,"WHERE"=>1,"SAVE"=>1,"RESTORE"=>1,"SCRAMBLE"=>2)
    seqcmds=("APPLY","INVERT","SIMPLIFY","METRICS","ORDER","CYCLES","UNROTATE","UNTIL")
    words=String[]; head=""; moves=Move[]
    if cmd in noargs; require(splitat===nothing)
    elseif haskey(wordcounts,cmd)
        words=splitat===nothing ? String[] : String.(split(argument,' ';keepempty=true)); require(length(words)==wordcounts[cmd])
        if cmd in ("UNDO","REDO","SEARCH","SCRAMBLE"); require(all(w->occursin(r"^(?:0|[1-9][0-9]{0,9})$",w),words))
        elseif cmd in ("SAVE","RESTORE"); require(occursin(r"^[a-z]{1,8}$",words[1])); end
    elseif cmd in seqcmds; moves=parse_sequence(line,length(cmd)+2,s.macros)
    elseif cmd in ("DEFINE","MIRROR","ROTATE")
        require(splitat!==nothing); at=findfirst(' ',argument); head=at===nothing ? argument : part(argument,1,at-1)
        require(cmd=="DEFINE" ? occursin(r"^[a-z]{1,8}$",head) : cmd=="MIRROR" ? head in ("LR","UD","FB") : occursin(r"^[xyz][2']?$",head))
        moves=parse_sequence(line,length(cmd)+length(head)+3,s.macros)
    else; fail("unknown command $cmd"); end
    if cmd=="RESET"; s.state=copy(SOLVED); empty!(s.history); empty!(s.redo); println("reset")
    elseif cmd=="SHOW"
        row(face,r)=s.state[9*(findfirst(==(face),FACES)-1)+3r+1:9*(findfirst(==(face),FACES)-1)+3r+3]
        for r in 0:2; println("      ",join(row('U',r),' ')); end
        for r in 0:2; println(join([row('L',r);row('F',r);row('R',r);row('B',r)],' ')); end
        for r in 0:2; println("      ",join(row('D',r),' ')); end
    elseif cmd=="STATE"; println("state ",join(s.state))
    elseif cmd=="ISSOLVED"; println(solved(s.state) ? "solved" : "unsolved $(count(i->s.state[i]!=s.state[9*fld(i-1,9)+5],1:54))")
    elseif cmd=="HISTORY"; println("history ",sequence(s.history))
    elseif cmd=="SOLUTION"; println("solution ",sequence(simplify(inverse(s.history))))
    elseif cmd=="MACROS"
        println("macros $(length(s.macros))"); for name in sort!(collect(keys(s.macros))); println("macro $name $(sequence(s.macros[name]))"); end
    elseif cmd=="ANALYZE"
        rotation=normalization(s.state); normal=applymoves(s.state,rotation); println("rotation ",isempty(rotation) ? "none" : movestext(rotation))
        println("corners ",cycles(CORNERS,normal)); println("edges ",cycles(EDGES,normal))
    elseif cmd=="STAGE"
        normal=normalized(s.state); corners=contents(CORNERS,normal); edges=contents(EDGES,normal)
        cross=count(i->edges[i]==(i,0),5:8); slots=count(i->corners[i+4]==(i+4,0) && edges[i+8]==(i+8,0),1:4); top=count(==('W'),normal[1:9])
        stage=solved(normal) ? "solved" : cross==4 && slots==4 && top==9 ? "oll" : cross==4 && slots==4 ? "f2l" : cross==4 ? "cross" : "none"
        println("stage $stage cross $cross slots $slots top $top")
    elseif cmd in ("CHECK","LOAD")
        reason=invalid(words[1])
        if cmd=="CHECK"; println(reason===nothing ? "valid" : "invalid $reason")
        else; reason===nothing || fail("invalid $reason"); s.state=collect(words[1]); empty!(s.history); empty!(s.redo); println("loaded"); end
    elseif cmd in ("UNDO","REDO")
        n=parse(Int,words[1]); require(n>=1,"bad value"); source=cmd=="UNDO" ? s.history : s.redo; target=cmd=="UNDO" ? s.redo : s.history
        require(!isempty(source),cmd=="UNDO" ? "nothing to undo" : "nothing to redo"); n=min(n,length(source))
        for _ in 1:n; move=pop!(source); s.state=applymoves(s.state,cmd=="UNDO" ? inverse([move]) : [move]); push!(target,move); end
        println(cmd=="UNDO" ? "undone $n" : "redone $n")
    elseif cmd=="SEARCH"
        n=parse(Int,words[1]); require(n<=4,"bad value"); found=nothing
        for depth in 0:n; found=searchdepth(s.state,depth); found!==nothing && break; end
        println(found===nothing ? "not found" : "found $(sequence(found))")
    elseif cmd=="WHERE"
        name=words[1]; kind=name in CORNERS.names ? CORNERS : name in EDGES.names ? EDGES : nothing; kind===nothing && fail("unknown piece $name")
        piece=findfirst(==(name),kind.names); pieces=contents(kind,normalized(s.state)); position=findfirst(x->x[1]==piece,pieces)
        println("$name at $(kind.names[position]) $(kind===CORNERS ? "twist" : "flip") $(pieces[position][2])")
    elseif cmd=="SAVE"; name=words[1]; s.saves[name]=(copy(s.state),copy(s.history)); println("saved $name")
    elseif cmd=="RESTORE"
        name=words[1]; require(haskey(s.saves,name),"no save $name"); state,history=s.saves[name]; s.state=copy(state); s.history=copy(history); empty!(s.redo); println("restored $name")
    elseif cmd=="SCRAMBLE"
        n,seed=parse.(Int,words); require(1<=n<=50 && 1<=seed<=2147483646,"bad value"); moves=scramble(n,seed); record!(s,moves); println("scramble ",movestext(moves))
    elseif cmd=="APPLY"; record!(s,moves); println("applied $(length(moves))")
    elseif cmd=="INVERT"; println("inverse ",sequence(inverse(moves)))
    elseif cmd=="SIMPLIFY"; println("simplified ",sequence(simplify(moves)))
    elseif cmd=="METRICS"
        htm=0; qtm=0; stm=0
        for (c,a) in moves; c in "xyz" && continue; w=c in "MES" ? 2 : 1; htm+=w; qtm+=w*(a==2 ? 2 : 1); stm+=1; end
        println("metrics htm $htm qtm $qtm stm $stm etm $(length(moves))")
    elseif cmd=="ORDER"; println("order ",permutationorder(effect(moves)))
    elseif cmd=="CYCLES"
        state=applymoves(SOLVED,moves); println("corners ",cycles(CORNERS,state)); println("edges ",cycles(EDGES,state)); println("centers ",cycles(CENTERS,state))
    elseif cmd=="UNROTATE"; println("unrotated ",sequence(unrotate(moves)))
    elseif cmd=="UNTIL"
        table=effect(moves); state=s.state; found=0
        for i in 1:permutationorder(table); state=state[table]; if solved(state); found=i; break; end; end
        println(found==0 ? "until never" : "until $found")
    elseif cmd=="DEFINE"; s.macros[head]=copy(moves); println("defined $head $(length(moves))")
    elseif cmd=="MIRROR"
        axis=head=="LR" ? 1 : head=="UD" ? 2 : 3
        result=Move[AXIS[c]!=axis ? (c,4-a) : haskey(OPPOSITE,c) ? (OPPOSITE[c],4-a) : (c,a) for (c,a) in moves]
        println("mirror ",sequence(result))
    elseif cmd=="ROTATE"
        rotation=plainmoves(head); result=Move[BYEFFECT[Tuple(effect([rotation;[move];inverse(rotation)]))] for move in moves]
        println("rotated ",sequence(result))
    end
end
function main()
    s=Simulator(); n=parse(Int,readline())
    for _ in 1:n
        line=readline()
        try; execute!(s,line)
        catch e; e isa CommandError || rethrow(); println("error: $(e.message)"); end
    end
end
main()
