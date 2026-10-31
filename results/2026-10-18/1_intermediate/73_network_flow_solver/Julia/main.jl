struct CommandError <: Exception
    message::String
end
fail(s) = throw(CommandError(s))
check(b, s) = b ? nothing : fail(s)
yesno(b) = b ? "yes" : "no"
mutable struct FlowEdge
    u::Int
    v::Int
    capacity::Int
    cost::Int
    lower::Int
    flow::Int
end
FlowEdge(u, v, c, w = 0) = FlowEdge(u, v, c, w, 0, 0)
clone_edges(es) = [FlowEdge(e.u, e.v, e.capacity, e.cost) for e in es]
arcstart(es, a) = a>0 ? es[a].u : es[-a].v
arcend(es, a) = a>0 ? es[a].v : es[-a].u
residual(es, a) = a>0 ? es[a].capacity-es[a].flow : es[-a].flow
arccost(es, a) = a>0 ? es[a].cost : -es[-a].cost
struct FlowGraph
    n::Int
    edges::Vector{FlowEdge}
    globalarcs::Vector{Int}
    arcs::Vector{Vector{Int}}
end
function FlowGraph(n, es)
    all=[collect(1:length(es)); -collect(1:length(es))]
    FlowGraph(n, es, all, [[a for a in all if arcstart(es, a)==v] for v in 1:n])
end
struct Push
    amount::Int
    path::Vector{Int}
    marker::Int
    cost::Int
end
function pushpath!(g, path, amount)
    for a in path
        g.edges[abs(a)].flow+=sign(a)*amount
    end
end
bottleneck(g, path) = minimum(residual(g.edges, a) for a in path)
function bfs(g, s, threshold = 1)
    levels=fill(-1, g.n)
    parents=zeros(Int, g.n)
    levels[s]=0
    queue=[s]
    at=1
    while at<=length(queue)
        u=queue[at]
        at+=1
        for a in g.arcs[u]
            v=arcend(g.edges, a)
            if residual(g.edges, a)>=threshold && levels[v]<0
                levels[v]=levels[u]+1
                parents[v]=a
                push!(queue, v)
            end
        end
    end
    levels, parents
end
function tracepath(g, parents, s, t)
    path=Int[]
    v=t
    while v!=s
        a=parents[v]
        push!(path, a)
        v=arcstart(g.edges, a)
    end
    reverse!(path)
end
function augment!(g, s, t, threshold = 1)
    levels, parents=bfs(g, s, threshold)
    levels[t]<0 && return nothing
    path=tracepath(g, parents, s, t)
    amount=bottleneck(g, path)
    pushpath!(g, path, amount)
    Push(amount, path, threshold, 0)
end
function edmonds_karp!(g, s, t)
    pushes=Push[]
    while true
        item=augment!(g, s, t)
        item===nothing && return pushes
        push!(pushes, item)
    end
end
function dinic!(g, s, t)
    pushes=Push[]
    phases=0
    while true
        levels, _=bfs(g, s)
        levels[t]<0 && return phases, pushes
        phases+=1
        pointers=ones(Int, g.n)
        path=Int[]
        u=s
        while true
            if u==t
                amount=bottleneck(g, path)
                pushpath!(g, path, amount)
                push!(pushes, Push(amount, path, phases, 0))
                path=Int[]
                u=s
            elseif pointers[u]>length(g.arcs[u])
                u==s && break
                a=pop!(path)
                u=arcstart(g.edges, a)
                pointers[u]+=1
            else
                a=g.arcs[u][pointers[u]]
                v=arcend(g.edges, a)
                if residual(g.edges, a)>0 && levels[v]==levels[u]+1
                    push!(path, a)
                    u=v
                else
                    pointers[u]+=1
                end
            end
        end
    end
end
function scaling!(g, s, t)
    largest=maximum((e.capacity for e in g.edges); init = 0)
    threshold=1
    while threshold*2<=largest
        threshold*=2
    end
    pushes=Push[]
    while threshold>=1
        while true
            item=augment!(g, s, t, threshold)
            item===nothing && break
            push!(pushes, item)
        end
        threshold=div(threshold, 2)
    end
    pushes
end
function negativecycle(n, es)
    d=zeros(Int, n)
    for pass in 1:n
        changed=false
        for e in es
            if d[e.u]+e.cost<d[e.v]
                d[e.v]=d[e.u]+e.cost
                changed=true
            end
        end
        !changed && return false
        pass==n && return true
    end
    false
end
function cheapestpath(g, s, t)
    usable=[a for a in g.globalarcs if residual(g.edges, a)>0]
    d=Union{Nothing,Int}[nothing for _ in 1:g.n]
    parents=zeros(Int, g.n)
    d[s]=0
    while true
        changed=false
        for a in usable
            u=arcstart(g.edges, a)
            v=arcend(g.edges, a)
            d[u]===nothing && continue
            candidate=d[u]+arccost(g.edges, a)
            if d[v]===nothing || candidate<d[v]
                d[v]=candidate
                parents[v]=a
                changed=true
            end
        end
        !changed && break
    end
    d[t]===nothing ? nothing : (d[t], tracepath(g, parents, s, t))
end
function mincost!(g, s, t, target = nothing)
    flow=0
    cost=0
    pushes=Push[]
    while target===nothing || flow<target
        result=cheapestpath(g, s, t)
        result===nothing && break
        unit, path=result
        amount=bottleneck(g, path)
        target!==nothing && (amount=min(amount, target-flow))
        pushpath!(g, path, amount)
        flow+=amount
        cost+=amount*unit
        push!(pushes, Push(amount, path, 0, unit))
    end
    flow, cost, pushes
end
outflow(es, v) = sum((e.flow for e in es if e.u==v); init = 0)
inflow(es, v) = sum((e.flow for e in es if e.v==v); init = 0)
flowvalue(es, s) = outflow(es, s)-inflow(es, s)
totalcost(es) = sum((e.flow*e.cost for e in es); init = 0)
function maximum_amount(n, es, s, t)
    g=FlowGraph(n, es)
    edmonds_karp!(g, s, t)
    flowvalue(es, s)
end
struct FlowPiece
    cycle::Bool
    origin::Int
    edges::Vector{Int}
    amount::Int
end
function decompose(n, es)
    remaining=[e.flow for e in es]
    balance=[flowvalue(es, v) for v in 1:n]
    pieces=FlowPiece[]
    while any(>(0), remaining)
        origin=findfirst(>(0), balance)
        origin===nothing && (origin=es[findfirst(>(0), remaining)].u)
        walk=[origin]
        used=Int[]
        while true
            u=last(walk)
            i=findfirst(j->es[j].u==u && remaining[j]>0, eachindex(es))
            v=es[i].v
            push!(used, i)
            repeated=findfirst(==(v), walk)
            if repeated!==nothing
                selected=used[repeated:end]
                amount=minimum(remaining[selected])
                remaining[selected].-=amount
                push!(pieces, FlowPiece(true, v, selected, amount))
                break
            end
            push!(walk, v)
            if balance[v]<0
                amount=min(minimum(remaining[used]), balance[origin], -balance[v])
                remaining[used].-=amount
                balance[origin]-=amount
                balance[v]+=amount
                push!(pieces, FlowPiece(false, origin, used, amount))
                break
            end
        end
    end
    pieces
end
function notation(names, es, origin, path)
    words=[names[origin]]
    for a in path
        push!(words, (a>0 ? "+" : "-")*string(abs(a)), names[arcend(es, a)])
    end
    join(words, ' ')
end
mutable struct Network
    names::Vector{String}
    demands::Vector{Int}
    edges::Vector{FlowEdge}
    owner::Symbol
    source::Int
    sink::Int
end
Network() = Network(String[], Int[], FlowEdge[], :none, 0, 0)
function nodeindex(n, name)
    at=findfirst(==(name), n.names)
    check(at!==nothing, "UNKNOWN NODE $name")
    at
end
function edgeindex(n, text)
    at=parse(Int, text)
    check(1<=at<=length(n.edges), "UNKNOWN EDGE $text")
    at
end
function endpoints(n, args)
    s=nodeindex(n, args[1])
    t=nodeindex(n, args[2])
    check(s!=t, "SAME NODE")
    s, t
end
function startflow!(n, s, t)
    if n.owner != :flow || n.source!=s || n.sink!=t
        for e in n.edges
            e.flow=0
        end
    end
    n.owner=:flow
    n.source=s
    n.sink=t
    flowvalue(n.edges, s)
end
function flowlist(n)
    for (i, e) in enumerate(n.edges)
        println("FLOW $i $(n.names[e.u]) $(n.names[e.v]) $(e.flow)/$(e.capacity)")
    end
end
function matchreport(args)
    left=String.(split(args[1], ','))
    right=String.(split(args[2], ','))
    seen=Set{String}()
    for name in [left; right]
        check(!(name in seen), "DUPLICATE VERTEX $name")
        push!(seen, name)
    end
    links=Tuple{Int,Int}[]
    for text in (args[3]=="-" ? String[] : split(args[3], ','))
        a, b=split(text, '-')
        u=findfirst(==(a), left)
        v=findfirst(==(b), right)
        check(u!==nothing, "UNKNOWN VERTEX $a")
        check(v!==nothing, "UNKNOWN VERTEX $b")
        check(!((u, v) in links), "DUPLICATE PAIR $a-$b")
        push!(links, (u, v))
    end
    lp=zeros(Int, length(left))
    rp=zeros(Int, length(right))
    examined=falses(length(right))
    function try_left(u)
        for (a, b) in links
            a==u && !examined[b] || continue
            examined[b]=true
            if rp[b]==0 || try_left(rp[b])
                rp[b]=u
                lp[u]=b
                return true
            end
        end
        false
    end
    for u in eachindex(left)
        fill!(examined, false)
        try_left(u)
    end
    lin=lp .== 0
    rin=falses(length(right))
    while true
        changed=false
        for (a, b) in links
            if lin[a] && !rin[b] && lp[a]!=b
                rin[b]=true
                changed=true
            end
        end
        for b in eachindex(right)
            if rin[b] && rp[b]!=0 && !lin[rp[b]]
                lin[rp[b]]=true
                changed=true
            end
        end
        !changed && break
    end
    freeleft=left[lp .== 0]
    freeright=right[rp .== 0]
    cover=[left[.!lin]; right[rin]]
    println("MATCH size=$(count(!=(0),lp)) left=$(length(left)) right=$(length(right))")
    for a in eachindex(left)
        lp[a]!=0 && println("PAIR $(left[a]) $(right[lp[a]])")
    end
    println(
        "FREE ",
        isempty(freeleft) ? "-" : join(freeleft, ','),
        " ",
        isempty(freeright) ? "-" : join(freeright, ','),
    )
    println("COVER size=$(length(cover))", isempty(cover) ? "" : " "*join(cover, ' '))
    !isempty(freeleft) &&
        println("HALL ", join(left[lin], ','), " ", any(rin) ? join(right[rin], ',') : "-")
end
function assignmentreport(args)
    mode=args[1]
    n=parse(Int, args[2])
    check(1<=n<=8, "BAD SIZE")
    values=args[3:end]
    check(length(values)==n*n, "BAD LENGTH")
    chosen=Int[]
    best=nothing
    ways=0
    bestchosen=Int[]
    function search(total)
        row=length(chosen)+1
        if row>n
            if best===nothing || (mode=="MAX" ? total>best : total<best)
                best=total
                ways=1
                bestchosen=copy(chosen)
            elseif total==best
                ways+=1
            end
            return
        end
        for col in 1:n
            col in chosen && continue
            text=values[(row-1)*n+col]
            text=="x" && continue
            push!(chosen, col)
            search(total+parse(Int, text))
            pop!(chosen)
        end
    end
    search(0)
    if best===nothing
        println("ASSIGN $mode n=$n infeasible")
        return
    end
    println("ASSIGN $mode n=$n total=$best optimal=$ways")
    for (row, col) in enumerate(bestchosen)
        println("MATE $row $col $(values[(row-1)*n+col])")
    end
end
function execute!(n, line)
    words=String.(split(line, ' '))
    command=words[1]
    args=words[2:end]
    if command=="NODE"
        seen=Set(n.names)
        for name in args
            check(!(name in seen), "DUPLICATE NODE $name")
            push!(seen, name)
        end
        check(length(n.names)+length(args)<=20, "TOO MANY NODES")
        append!(n.names, args)
        append!(n.demands, zeros(Int, length(args)))
        println("NODE added=$(length(args)) total=$(length(n.names))")
    elseif command=="EDGE"
        s=nodeindex(n, args[1])
        t=nodeindex(n, args[2])
        check(s!=t, "SELF LOOP")
        check(length(n.edges)<60, "TOO MANY EDGES")
        e=FlowEdge(s, t, parse(Int, args[3]), length(args)==4 ? parse(Int, args[4]) : 0)
        push!(n.edges, e)
        println("EDGE $(length(n.edges)) $(args[1]) $(args[2]) cap=$(e.capacity) cost=$(e.cost)")
    elseif command in ("LOWER", "CAP", "COST")
        at=edgeindex(n, args[1])
        e=n.edges[at]
        value=parse(Int, args[2])
        if command=="LOWER"
            check(value<=e.capacity, "BAD BOUND")
            e.lower=value
            println("LOWER $at low=$(e.lower) cap=$(e.capacity)")
        elseif command=="CAP"
            check(value>=e.lower, "BAD BOUND")
            check(value>=e.flow, "BELOW FLOW")
            e.capacity=value
            println("CAP $at low=$(e.lower) cap=$(e.capacity)")
        else
            e.cost=value
            println("COST $at cost=$(e.cost)")
        end
    elseif command=="DEMAND"
        at=nodeindex(n, args[1])
        n.demands[at]=parse(Int, args[2])
        println("DEMAND $(args[1]) $(args[2]) total=$(sum(n.demands))")
    elseif command=="RESET"
        println("RESET edges=$(count(e->e.flow!=0,n.edges))")
        for e in n.edges
            e.flow=0
        end
        n.owner=:none
    elseif command=="CLEAR"
        println("CLEAR nodes=$(length(n.names)) edges=$(length(n.edges))")
        empty!(n.names)
        empty!(n.demands)
        empty!(n.edges)
        n.owner=:none
        n.source=0
        n.sink=0
    elseif command=="SHOW"
        println("NETWORK nodes=$(length(n.names)) edges=$(length(n.edges))")
        println(
            n.owner == :none ? "STATE none" :
            n.owner == :circulation ? "STATE circulation cost=$(totalcost(n.edges))" :
            "STATE flow $(n.names[n.source]) $(n.names[n.sink]) value=$(flowvalue(n.edges,n.source)) cost=$(totalcost(n.edges))",
        )
        for (v, name) in enumerate(n.names)
            println(
                "NODE $name demand=$(n.demands[v]) out=$(outflow(n.edges,v)) in=$(inflow(n.edges,v))",
            )
        end
        for (i, e) in enumerate(n.edges)
            println(
                "EDGE $i $(n.names[e.u]) $(n.names[e.v]) cap=$(e.capacity) cost=$(e.cost) low=$(e.lower) flow=$(e.flow)",
            )
        end
    elseif command in ("AUGMENT", "MAXFLOW", "DINIC", "SCALING", "MINCUT")
        s, t=endpoints(n, args)
        start=startflow!(n, s, t)
        g=FlowGraph(length(n.names), n.edges)
        heading="$command $(args[1]) $(args[2])"
        if command=="AUGMENT"
            item=augment!(g, s, t)
            println(
                "$heading value=$(flowvalue(n.edges,s))",
                item===nothing ? " none" :
                " amount=$(item.amount) "*notation(n.names, n.edges, s, item.path),
            )
            return
        end
        phases=0
        if command=="DINIC"
            phases, pushes=dinic!(g, s, t)
        elseif command=="SCALING"
            pushes=scaling!(g, s, t)
        else
            pushes=edmonds_karp!(g, s, t)
        end
        if command=="MINCUT"
            levels, _=bfs(g, s)
            cut=[i for (i, e) in enumerate(n.edges) if levels[e.u]>=0 && levels[e.v]<0]
            println("$heading value=$(flowvalue(n.edges,s)) edges=$(length(cut))")
            println("SOURCE ", join(n.names[levels .>= 0], ' '))
            println("SINK ", join(n.names[levels .< 0], ' '))
            for i in cut
                e=n.edges[i]
                println("CUT $i $(n.names[e.u]) $(n.names[e.v]) $(e.capacity)")
            end
        else
            println(
                "$heading value=$(flowvalue(n.edges,s)) start=$start",
                command=="DINIC" ? " phases=$phases" : "",
                " paths=$(length(pushes))",
            )
            for (i, item) in enumerate(pushes)
                detail=command=="DINIC" ? " phase=$(item.marker)" :
                       command=="SCALING" ? " delta=$(item.marker)" : ""
                println(
                    "AUG $i$detail amount=$(item.amount) ",
                    notation(n.names, n.edges, s, item.path),
                )
            end
            flowlist(n)
        end
    elseif command=="SENSITIVITY"
        s, t=endpoints(n, args)
        value=maximum_amount(length(n.names), clone_edges(n.edges), s, t)
        effective=Tuple{Int,Bool,Bool}[]
        for (i, e) in enumerate(n.edges)
            work=clone_edges(n.edges)
            work[i].capacity+=1
            up=maximum_amount(length(n.names), work, s, t)>value
            down=false
            if e.capacity>0
                work=clone_edges(n.edges)
                work[i].capacity-=1
                down=maximum_amount(length(n.names), work, s, t)<value
            end
            (up || down) && push!(effective, (i, up, down))
        end
        println(
            "SENSITIVITY $(args[1]) $(args[2]) value=$value up=$(count(x->x[2],effective)) down=$(count(x->x[3],effective))",
        )
        for (i, up, down) in effective
            e=n.edges[i]
            println(
                "CRITICAL $i $(n.names[e.u]) $(n.names[e.v]) up=$(yesno(up)) down=$(yesno(down))",
            )
        end
    elseif command=="MINCOST"
        s, t=endpoints(n, args)
        check(
            !negativecycle(length(n.names), [e for e in n.edges if e.capacity>0]),
            "NEGATIVE CYCLE",
        )
        target=args[3]=="MAX" ? nothing : parse(Int, args[3])
        g=FlowGraph(length(n.names), clone_edges(n.edges))
        flow, cost, pushes=mincost!(g, s, t, target)
        heading="MINCOST $(args[1]) $(args[2]) k=$(args[3])"
        if target!==nothing && flow<target
            println("$heading infeasible max=$flow")
            return
        end
        for (original, worked) in zip(n.edges, g.edges)
            original.flow=worked.flow
        end
        n.owner=:flow
        n.source=s
        n.sink=t
        println("$heading flow=$flow cost=$cost")
        for (i, item) in enumerate(pushes)
            println(
                "AUG $i amount=$(item.amount) cost=$(item.cost) ",
                notation(n.names, n.edges, s, item.path),
            )
        end
        flowlist(n)
    elseif command=="DISJOINT"
        s, t=endpoints(n, args)
        nodecount=length(n.names)
        exits=collect(1:nodecount)
        total=nodecount
        if args[3]=="VERTEX"
            total=2nodecount
            for v in 1:nodecount
                v!=s && v!=t && (exits[v]=nodecount+v)
            end
        end
        es=[FlowEdge(exits[e.u], e.v, min(1, e.capacity)) for e in n.edges]
        if args[3]=="VERTEX"
            for v in 1:nodecount
                v!=s && v!=t && push!(es, FlowEdge(v, exits[v], 1))
            end
        end
        edmonds_karp!(FlowGraph(total, es), s, t)
        pieces=[p for p in decompose(total, es) if !p.cycle]
        println("DISJOINT $(args[1]) $(args[2]) $(args[3]) count=$(length(pieces))")
        for (i, piece) in enumerate(pieces)
            selected=[j for j in piece.edges if j<=length(n.edges)]
            println("PATH $i ", notation(n.names, n.edges, piece.origin, selected))
        end
    elseif command=="DECOMPOSE"
        pieces=decompose(length(n.names), n.edges)
        cycles=count(p->p.cycle, pieces)
        println("DECOMPOSE paths=$(length(pieces)-cycles) cycles=$cycles")
        p=0
        c=0
        for piece in pieces
            if piece.cycle
                c+=1
                title="CYCLE $c"
            else
                p+=1
                title="PATH $p"
            end
            println(
                "$title amount=$(piece.amount) ",
                notation(n.names, n.edges, piece.origin, piece.edges),
            )
        end
    elseif command=="VERIFY"
        violations=[
            "LOW $i flow=$(e.flow) low=$(e.lower)" for
            (i, e) in enumerate(n.edges) if e.flow<e.lower
        ]
        for (v, name) in enumerate(n.names)
            n.owner == :flow && v in (n.source, n.sink) && continue
            need=n.owner == :flow ? 0 : n.demands[v]
            net=inflow(n.edges, v)-outflow(n.edges, v)
            net!=need && push!(violations, "BALANCE $name net=$net need=$need")
        end
        if isempty(violations)
            println("VERIFY ok")
        else
            println("VERIFY violations=$(length(violations))")
            foreach(println, violations)
        end
    elseif command=="CIRCULATION"
        mode=args[1]
        nodecount=length(n.names)
        mode=="MINCOST" && check(
            !negativecycle(nodecount, [e for e in n.edges if e.capacity>e.lower]),
            "NEGATIVE CYCLE",
        )
        imbalance=sum(n.demands)
        if imbalance!=0
            println("CIRCULATION infeasible unbalanced=$imbalance")
            return
        end
        required=copy(n.demands)
        es=[FlowEdge(e.u, e.v, e.capacity-e.lower, e.cost) for e in n.edges]
        for e in n.edges
            required[e.v]-=e.lower
            required[e.u]+=e.lower
        end
        for v in 1:nodecount
            required[v]<0 && push!(es, FlowEdge(nodecount+1, v, -required[v]))
        end
        sinkedges=Int[]
        for v in 1:nodecount
            if required[v]>0
                push!(es, FlowEdge(v, nodecount+2, required[v]))
                push!(sinkedges, length(es))
            end
        end
        g=FlowGraph(nodecount+2, es)
        mode=="ANY" ? edmonds_karp!(g, nodecount+1, nodecount+2) :
        mincost!(g, nodecount+1, nodecount+2)
        total=sum((es[i].capacity for i in sinkedges); init = 0)
        achieved=sum((es[i].flow for i in sinkedges); init = 0)
        if achieved<total
            println("CIRCULATION infeasible required=$total achieved=$achieved")
            levels, _=bfs(g, nodecount+1)
            println("CUT ", join([n.names[v] for v in 1:nodecount if levels[v]>=0], ' '))
            return
        end
        for (i, e) in enumerate(n.edges)
            e.flow=e.lower+es[i].flow
        end
        n.owner=:circulation
        println("CIRCULATION feasible required=$total cost=$(totalcost(n.edges))")
        flowlist(n)
    elseif command=="MATCH"
        matchreport(args)
    elseif command=="ASSIGN"
        assignmentreport(args)
    end
end
function main()
    network=Network()
    count=parse(Int, readline())
    for _ in 1:count
        line=readline()
        try
            execute!(network, line)
        catch e
            e isa CommandError || rethrow()
            println("ERROR $(e.message)")
        end
    end
end
main()
