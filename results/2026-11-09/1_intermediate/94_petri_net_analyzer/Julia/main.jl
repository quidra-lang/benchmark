yes(b) = b ? "yes" : "no"
mark(m) = "(" * join((v < 0 ? "w" : string(v) for v in m), ",") * ")"
listed(a) = isempty(a) ? "none" : join(a, " ")
function number(s, lo, hi)
    occursin(r"^(0|[1-9][0-9]{0,9})$", s) || return -1
    v = parse(Int64, s)
    lo <= v <= hi ? v : -1
end
function visit(adj, start)
    seen = falses(length(adj))
    q = [start]
    seen[start] = true
    cursor = 1
    while cursor <= length(q)
        for v in adj[q[cursor]]
            if !seen[v]
                seen[v] = true
                push!(q, v)
            end
        end
        cursor += 1
    end
    seen
end
function lexless(a, b)
    for i in eachindex(a)
        a[i] != b[i] && return a[i] < b[i]
    end
    false
end
function flows(a)
    n = length(a)
    m = length(a[1])
    rows = [vcat(a[i], [Int64(i == j) for j in 1:n]) for i in 1:n]
    for j in 1:m
        allrows = [r for r in rows if r[j] == 0]
        for r in rows, s in rows
            r[j] > 0 && s[j] < 0 || continue
            v = -s[j] .* r .+ r[j] .* s
            d = foldl(gcd, v; init = 0)
            push!(allrows, div.(v, d))
        end
        unique_rows = collect(values(Dict(Tuple(r) => r for r in allrows)))
        support = [sum(1 << (i-1) for i in 1:n if r[m+i] > 0; init = 0) for r in unique_rows]
        rows = [
            r for (i, r) in enumerate(unique_rows) if
            !any(s != support[i] && s & support[i] == s for s in support)
        ]
    end
    sort!([r[(m+1):end] for r in rows]; lt = (a, b)->lexless(b, a))
end
mutable struct Graph
    states::Vector{Vector{Int64}}
    parent::Vector{Int}
    via::Vector{Int}
    edges::Vector{Vector{Tuple{Int,Int}}}
    found::Int
    aborted::Bool
end
mutable struct Net
    name::String
    p::Vector{String}
    t::Vector{String}
    initial::Vector{Int64}
    cap::Vector{Int64}
    priority::Vector{Int64}
    pre::Matrix{Int64}
    post::Matrix{Int64}
    inh::Matrix{Int64}
    arcs::Int
    inhibitors::Int
    current::Vector{Int64}
    history::Vector{Vector{Int64}}
end
Net(name) = Net(
    name,
    [],
    [],
    [],
    [],
    [],
    zeros(Int64, 16, 16),
    zeros(Int64, 16, 16),
    zeros(Int64, 16, 16),
    0,
    0,
    [],
    [],
)
place(n, s) = something(findfirst(==(s), n.p), 0)
transition(n, s) = something(findfirst(==(s), n.t), 0)
function define!(n, w)
    cmd = w[1]
    count = length(w)-1
    cmd in ("place", "transition", "arc", "inhibit") || error("unknown definition $cmd")
    (cmd == "place" ? count in (2, 3) : cmd == "transition" ? count in (1, 2) : count == 3) ||
        error("wrong number of arguments")
    a = w[2]
    if cmd in ("place", "transition")
        (place(n, a) > 0 || transition(n, a) > 0) && error("duplicate name $a")
        if cmd == "place"
            count == 3 &&
                parse(Int, w[3]) > parse(Int, w[4]) &&
                error("tokens exceed capacity of $a")
            push!(n.p, a)
            push!(n.initial, parse(Int64, w[3]))
            push!(n.cap, count == 3 ? parse(Int64, w[4]) : 0)
        else
            push!(n.t, a)
            push!(n.priority, count == 2 ? parse(Int64, w[3]) : 0)
        end
    elseif cmd == "arc"
        b = w[3]
        for x in (a, b)
            place(n, x) == 0 && transition(n, x) == 0 && error("unknown node $x")
        end
        pa = place(n, a)
        pb = place(n, b)
        (pa > 0) == (pb > 0) && error("arc must connect a place and a transition")
        p = pa > 0 ? pa : pb
        t = transition(n, pa > 0 ? b : a)
        mat = pa > 0 ? n.pre : n.post
        mat[p, t] > 0 && error("duplicate arc $a $b")
        mat[p, t] = parse(Int64, w[4])
        n.arcs += 1
    else
        p = place(n, a)
        t = transition(n, w[3])
        p == 0 && error("unknown place $a")
        t == 0 && error("unknown transition $(w[3])")
        n.inh[p, t] > 0 && error("duplicate inhibitor $a $(w[3])")
        n.inh[p, t] = parse(Int64, w[4])
        n.inhibitors += 1
    end
end
function reason(n, m, t)
    for p in eachindex(n.p)
        m[p] >= 0 && m[p] < n.pre[p, t] && return "insufficient tokens in $(n.p[p])"
    end
    for p in eachindex(n.p)
        n.inh[p, t] > 0 && (m[p] < 0 || m[p] >= n.inh[p, t]) && return "inhibited by $(n.p[p])"
    end
    for p in eachindex(n.p)
        n.cap[p] > 0 &&
            (m[p] < 0 || m[p]-n.pre[p, t]+n.post[p, t] > n.cap[p]) &&
            return "capacity of $(n.p[p]) exceeded"
    end
    ""
end
enabled(n, m) = [t for t in eachindex(n.t) if isempty(reason(n, m, t))]
fire(n, m, t) = [m[p] < 0 ? -1 : m[p]-n.pre[p, t]+n.post[p, t] for p in eachindex(n.p)]
names(n, ts) = [n.t[t] for t in ts]
function commit!(n, t)
    push!(n.history, n.current)
    n.current = fire(n, n.current, t)
end
function graph(n, start, limit, target = nothing)
    g = Graph([copy(start)], [0], [0], [Tuple{Int,Int}[]], 0, false)
    index = Dict{Tuple,Int}(Tuple(start)=>1)
    matches(m) =
        target !== nothing && all(
            m[p] >= target[p][1] && (target[p][2] < 0 || m[p] == target[p][2]) for p in eachindex(m)
        )
    if matches(start)
        g.found = 1
        return g
    end
    q = 1
    while q <= length(g.states)
        for t in enabled(n, g.states[q])
            m = fire(n, g.states[q], t)
            k = get(index, Tuple(m), 0)
            if k == 0
                if length(g.states) == limit
                    g.aborted = true
                    return g
                end
                k = length(g.states)+1
                index[Tuple(m)] = k
                push!(g.states, m)
                push!(g.parent, q)
                push!(g.via, t)
                push!(g.edges, Tuple{Int,Int}[])
                if matches(m)
                    g.found = k
                    return g
                end
            end
            push!(g.edges[q], (t, k))
        end
        q += 1
    end
    g
end
function path(g, k)
    result = Int[]
    while g.parent[k] > 0
        push!(result, g.via[k])
        k = g.parent[k]
    end
    reverse(result)
end
function reach(n, limit, display)
    g = graph(n, n.current, limit)
    if g.aborted
        println("reachability graph limit $limit exceeded")
        return
    end
    N = length(g.states)
    if display
        for i in 1:N
            a = ["$(n.t[t])->M$(k-1)" for (t, k) in g.edges[i]]
            println("M$(i-1) $(mark(g.states[i])): ", isempty(a) ? "dead" : join(a, " "))
        end
        return
    end
    adj = [[k for (_, k) in e] for e in g.edges]
    closure = [visit(adj, i) for i in 1:N]
    comp = zeros(Int, N)
    count = 0
    for i in 1:N
        comp[i] > 0 && continue
        count += 1
        for j in i:N
            closure[i][j] && closure[j][i] && (comp[j] = count)
        end
    end
    terminal = trues(count)
    home = trues(N)
    dead = Int[]
    maximum = zeros(Int64, length(n.p))
    edges = 0
    persistent = true
    for i in 1:N
        isempty(g.edges[i]) && push!(dead, i)
        edges += length(g.edges[i])
        maximum = max.(maximum, g.states[i])
        home .&= closure[i]
        for (t, k) in g.edges[i]
            comp[i] != comp[k] && (terminal[comp[i]] = false)
            for (u, _) in g.edges[i]
                t != u && !isempty(reason(n, g.states[k], u)) && (persistent = false)
            end
        end
    end
    println(
        "reachable markings: $N\nedges: $edges\ncomponents: $count (terminal $(sum(terminal)))\ndead markings: $(length(dead))",
    )
    for i in dead
        a = names(n, path(g, i))
        println("  M$(i-1) $(mark(g.states[i])) path ", isempty(a) ? "empty" : join(a, " "))
    end
    bound = Base.maximum(maximum)
    println(
        "max tokens: $(mark(maximum))\nbound: $bound\nsafe: $(yes(bound<=1))\nhome markings: $(sum(home))\nreversible: $(yes(home[1]))\npersistent: $(yes(persistent))",
    )
    levels = String[]
    for t in eachindex(n.t)
        present = falses(count)
        used = cycle = false
        for i in 1:N, (u, k) in g.edges[i]
            u == t || continue
            used = true
            present[comp[i]] = true
            comp[i] == comp[k] && (cycle = true)
        end
        level =
            all(!terminal[c] || present[c] for c in 1:count) ? "L4" :
            cycle ? "L3" : used ? "L1" : "L0"
        push!(levels, n.t[t]*"="*level)
    end
    println("liveness: ", join(levels, " "))
end
function cover(n, limit)
    states = [copy(n.current)]
    parent = [0]
    via = [0]
    old = [false]
    dead = [false]
    q = 1
    rank(v) = v < 0 ? typemax(Int64) : v
    while q <= length(states)
        if !old[q]
            es = enabled(n, states[q])
            dead[q] = isempty(es)
            ancestors = Int[]
            a = q
            while a > 0
                push!(ancestors, a)
                a = parent[a]
            end
            for t in es
                m = fire(n, states[q], t)
                for a in reverse(ancestors)
                    if all(rank(m[p]) >= rank(states[a][p]) for p in eachindex(m)) &&
                       any(rank(m[p]) > rank(states[a][p]) for p in eachindex(m))
                        for p in eachindex(m)
                            n.cap[p] == 0 && rank(m[p]) > rank(states[a][p]) && (m[p] = -1)
                        end
                    end
                end
                if length(states) == limit
                    println("coverability tree limit $limit exceeded")
                    return
                end
                push!(old, m in states)
                push!(states, m)
                push!(parent, q)
                push!(via, t)
                push!(dead, false)
            end
        end
        q += 1
    end
    println("coverability tree nodes: $(length(states))")
    maximum = zeros(Int64, length(n.p))
    for i in eachindex(states)
        prefix = i == 1 ? "root" : "<- $(parent[i]-1) $(n.t[via[i]])"
        println("  $(i-1) $(mark(states[i])) $prefix", old[i] ? " old" : "", dead[i] ? " dead" : "")
        for p in eachindex(n.p)
            rank(states[i][p]) > rank(maximum[p]) && (maximum[p] = states[i][p])
        end
    end
    println(
        "bounds: $(mark(maximum))\nunbounded: ",
        listed([n.p[p] for p in eachindex(n.p) if maximum[p] < 0]),
    )
end
function sets(n, trap)
    found = Int[]
    for mask in 1:((1<<length(n.p))-1)
        valid = true
        for t in eachindex(n.t)
            input = any(mask & (1<<(p-1)) != 0 && n.post[p, t] > 0 for p in eachindex(n.p))
            output = any(mask & (1<<(p-1)) != 0 && n.pre[p, t] > 0 for p in eachindex(n.p))
            if trap ? output && !input : input && !output
                valid = false
                break
            end
        end
        valid && push!(found, mask)
    end
    result = [m for m in found if !any(s != m && s & m == s for s in found)]
    bits(m) = [p for p in eachindex(n.p) if m & (1<<(p-1)) != 0]
    sort!(
        result;
        lt = (a, b)->count_ones(a) != count_ones(b) ? count_ones(a)<count_ones(b) :
                     lexless(bits(a), bits(b)),
    )
end
settext(n, mask) = "{"*join([n.p[p] for p in eachindex(n.p) if mask & (1<<(p-1)) != 0], ",")*"}"
function realize(n, counts)
    used = zeros(Int64, length(n.t))
    stack = [n.current]
    choices = [1]
    result = Int[]
    seen = Set{Tuple}()
    total = sum(counts)
    while !isempty(stack)
        d = length(result)+1
        length(result) == total && return result
        chosen = 0
        for t in choices[d]:length(n.t)
            choices[d] = t+1
            (used[t] >= counts[t] || !isempty(reason(n, stack[d], t))) && continue
            used[t] += 1
            key = Tuple(used)
            used[t] -= 1
            key in seen && continue
            push!(seen, key)
            chosen = t
            break
        end
        if chosen > 0
            used[chosen] += 1
            push!(result, chosen)
            push!(stack, fire(n, stack[d], chosen))
            push!(choices, 1)
        else
            pop!(stack)
            pop!(choices)
            !isempty(result) && (used[pop!(result)] -= 1)
        end
    end
    nothing
end
function invariants(n, transpose)
    a =
        transpose ? [[n.post[p, t]-n.pre[p, t] for p in eachindex(n.p)] for t in eachindex(n.t)] :
        [[n.post[p, t]-n.pre[p, t] for t in eachindex(n.t)] for p in eachindex(n.p)]
    f = flows(a)
    ns = transpose ? n.t : n.p
    covered = falses(length(ns))
    bounds = fill(Int64(-1), length(ns))
    println(transpose ? "T" : "P", "-semiflows: ", length(f))
    for c in f
        terms = join([(c[i] == 1 ? "" : "$(c[i])*")*ns[i] for i in eachindex(c) if c[i] > 0], " + ")
        covered .|= c .> 0
        if transpose
            sequence = realize(n, c)
            println(
                "  $terms: ",
                sequence === nothing ? "not realizable" :
                "realizable "*join(names(n, sequence), " "),
            )
        else
            value = sum(c .* n.current)
            println("  $terms = $value")
            for p in eachindex(c)
                c[p] > 0 && (
                    bounds[p] =
                        bounds[p] < 0 ? div(value, c[p]) : min(bounds[p], div(value, c[p]))
                )
            end
        end
    end
    !transpose && println("bounds: (", join([b < 0 ? "-" : string(b) for b in bounds], ","), ")")
    println(transpose ? "consistent: " : "conservative: ", yes(all(covered)))
end
function classify(n)
    P = length(n.p)
    T = length(n.t)
    inputs = [[p for p in 1:P if n.pre[p, t] > 0] for t in 1:T]
    outputs = [[t for t in 1:T if n.pre[p, t] > 0] for p in 1:P]
    ordinary = all(n.pre[p, t] <= 1 && n.post[p, t] <= 1 for p in 1:P, t in 1:T)
    pure = all(n.pre[p, t] == 0 || n.post[p, t] == 0 for p in 1:P, t in 1:T)
    sm = ordinary && all(length(inputs[t]) == 1 && count(>(0), n.post[1:P, t]) == 1 for t in 1:T)
    mg = ordinary && all(length(outputs[p]) == 1 && count(>(0), n.post[p, 1:T]) == 1 for p in 1:P)
    fc =
        ordinary &&
        all(length(outputs[p]) == 1 || length(inputs[t]) == 1 for p in 1:P for t in outputs[p])
    efc = ordinary && all(isempty(intersect(a, b)) || a == b for a in outputs, b in outputs)
    for (label, v) in [
        ("ordinary", ordinary),
        ("pure", pure),
        ("state machine", sm),
        ("marked graph", mg),
        ("free choice", fc),
        ("extended free choice", efc),
    ]
        println(label, ": ", yes(v))
    end
    verdict = !fc ? "not applicable" : P > 12 ? "too many places" : "holds"
    if fc && P <= 12
        traps = sets(n, true)
        for s in sets(n, false)
            if !any(
                q & s == q && any(n.current[p] > 0 && q & (1<<(p-1)) != 0 for p in 1:P) for
                q in traps
            )
                verdict = "fails at "*settext(n, s)
                break
            end
        end
    end
    println("commoner: ", verdict)
end
function workflow(n, limit)
    P = length(n.p)
    T = length(n.t)
    sources = [p for p in 1:P if all(n.post[p, t] == 0 for t in 1:T)]
    sinks = [p for p in 1:P if all(n.pre[p, t] == 0 for t in 1:T)]
    if length(sources) != 1
        println("workflow: no ($(length(sources)) source places)")
        return
    end
    if length(sinks) != 1
        println("workflow: no ($(length(sinks)) sink places)")
        return
    end
    i = sources[1]
    o = sinks[1]
    ns = vcat(n.p, n.t)
    adj = [Int[] for _ in ns]
    rev = [Int[] for _ in ns]
    for p in 1:P, t in 1:T
        if n.pre[p, t] > 0
            push!(adj[p], P+t)
            push!(rev[P+t], p)
        end
        if n.post[p, t] > 0
            push!(adj[P+t], p)
            push!(rev[p], P+t)
        end
    end
    f = visit(adj, i)
    b = visit(rev, o)
    for v in eachindex(ns)
        if !f[v] || !b[v]
            println("workflow: no ($(ns[v]) is not on a path from $(n.p[i]) to $(n.p[o]))")
            return
        end
    end
    println("workflow: source $(n.p[i]) sink $(n.p[o])")
    start = zeros(Int64, P)
    goal = zeros(Int64, P)
    start[i] = goal[o] = 1
    g = graph(n, start, limit)
    if g.aborted
        println("reachability graph limit $limit exceeded")
        return
    end
    finish = findfirst(==(goal), g.states)
    rev = [Int[] for _ in g.states]
    used = falses(T)
    for u in eachindex(g.states), (t, v) in g.edges[u]
        push!(rev[v], u)
        used[t] = true
    end
    option = finish !== nothing && all(visit(rev, finish))
    proper = all(m[o] < 1 || m == goal for m in g.states)
    live = all(used)
    println(
        "option to complete: $(yes(option))\nproper completion: $(yes(proper))\nno dead transitions: $(yes(live))\nsound: $(yes(option&&proper&&live))",
    )
end
const ARITY = Dict(
    "MARKING"=>0,
    "RESET"=>0,
    "SET"=>2,
    "ENABLED"=>0,
    "FIRE"=>-1,
    "UNDO"=>1,
    "SIMULATE"=>3,
    "CONFLICTS"=>0,
    "REACH"=>1,
    "GRAPH"=>1,
    "COVER"=>1,
    "PATH"=>2,
    "INCIDENCE"=>0,
    "PINV"=>0,
    "TINV"=>0,
    "SIPHONS"=>0,
    "TRAPS"=>0,
    "CLASSIFY"=>0,
    "WORKFLOW"=>1,
    "SHOW"=>0,
)
function execute!(n, w)
    cmd = w[1]
    haskey(ARITY, cmd) || error("unknown command $cmd")
    (ARITY[cmd] < 0 ? length(w)>1 : length(w)==ARITY[cmd]+1) || error("wrong number of arguments")
    limit = 0
    if cmd in ("REACH", "GRAPH", "COVER", "PATH", "WORKFLOW")
        limit = number(w[2], 1, 2000)
        limit < 0 && error("invalid limit $(w[2])")
    end
    if cmd in ("MARKING", "RESET")
        if cmd == "RESET"
            n.current = copy(n.initial)
            empty!(n.history)
        end
        println("marking ", mark(n.current))
    elseif cmd == "SET"
        p = place(n, w[2])
        p == 0 && error("unknown place $(w[2])")
        v = number(w[3], 0, 999)
        v < 0 && error("invalid tokens $(w[3])")
        n.cap[p] > 0 && v > n.cap[p] && error("tokens exceed capacity of $(w[2])")
        n.current = copy(n.current)
        n.current[p] = v
        empty!(n.history)
        println("marking ", mark(n.current))
    elseif cmd == "ENABLED"
        println("enabled: ", listed(names(n, enabled(n, n.current))))
    elseif cmd == "FIRE"
        ts = Int[]
        for a in w[2:end]
            t = transition(n, a)
            t == 0 && error("unknown transition $a")
            push!(ts, t)
        end
        for (i, t) in enumerate(ts)
            r = reason(n, n.current, t)
            if !isempty(r)
                println("step $i: $(n.t[t]) not enabled ($r) at $(mark(n.current))")
                return
            end
            commit!(n, t)
        end
        println("fired $(length(ts)) -> $(mark(n.current))")
    elseif cmd == "UNDO"
        k = number(w[2], 1, 1000)
        k < 0 && error("invalid count $(w[2])")
        h = length(n.history)
        k > h && error("cannot undo $k: history size $h")
        n.current = n.history[h-k+1]
        resize!(n.history, h-k)
        println("marking ", mark(n.current))
    elseif cmd == "SIMULATE"
        steps = number(w[2], 1, 1000)
        x = number(w[3], 1, 2147483646)
        steps < 0 && error("invalid steps $(w[2])")
        x < 0 && error("invalid seed $(w[3])")
        w[4] in ("PRIORITY", "RANDOM") || error("invalid mode $(w[4])")
        counts = zeros(Int, length(n.t))
        done = 0
        while done < steps
            es = enabled(n, n.current)
            if isempty(es)
                println("dead (steps=$done)")
                break
            end
            t = es[1]
            if w[4] == "RANDOM"
                x = x*48271%2147483647
                t = es[x%length(es)+1]
            else
                for u in es
                    n.priority[u] > n.priority[t] && (t = u)
                end
            end
            commit!(n, t)
            counts[t] += 1
            done += 1
            println("step $done: $(n.t[t]) -> $(mark(n.current))")
        end
        done == steps && println("completed (steps=$steps)")
        println("counts: ", join(["$(n.t[t])=$(counts[t])" for t in eachindex(n.t)], " "))
    elseif cmd == "CONFLICTS"
        structural = String[]
        effective = String[]
        for u in eachindex(n.t), v in (u+1):length(n.t)
            pair = n.t[u]*"/"*n.t[v]
            any(n.pre[p, u] > 0 && n.pre[p, v] > 0 for p in eachindex(n.p)) &&
                push!(structural, pair)
            isempty(reason(n, n.current, u)) &&
                isempty(reason(n, n.current, v)) &&
                (
                    !isempty(reason(n, fire(n, n.current, u), v)) ||
                    !isempty(reason(n, fire(n, n.current, v), u))
                ) &&
                push!(effective, pair)
        end
        println("structural: ", listed(structural), "\neffective: ", listed(effective))
    elseif cmd in ("REACH", "GRAPH")
        reach(n, limit, cmd=="GRAPH")
    elseif cmd == "COVER"
        cover(n, limit)
    elseif cmd == "PATH"
        entries = split(w[3], ',')
        length(entries) == length(n.p) || error("target needs $(length(n.p)) entries")
        target = Tuple{Int64,Int64}[]
        for s in entries
            if s == "*"
                push!(target, (0, -1))
                continue
            end
            plus = endswith(s, "+")
            v = number(plus ? s[1:(end-1)] : s, 0, 9999999999)
            v < 0 && error("invalid target entry $s")
            push!(target, (v, plus ? -1 : v))
        end
        g = graph(n, n.current, limit, target)
        if g.found > 0
            sequence = names(n, path(g, g.found))
            println(
                "reached $(mark(g.states[g.found])) length=$(length(sequence))",
                isempty(sequence) ? "" : ": "*join(sequence, " "),
            )
        elseif g.aborted
            println("search limit $limit exceeded")
        else
            println("unreachable (markings explored: $(length(g.states)))")
        end
    elseif cmd == "INCIDENCE"
        rows = [vcat([""], n.t)]
        append!(
            rows,
            [
                [n.p[p]; [string(n.post[p, t]-n.pre[p, t]) for t in eachindex(n.t)]] for
                p in eachindex(n.p)
            ],
        )
        width = [maximum(length(r[i]) for r in rows) for i in eachindex(rows[1])]
        for r in rows
            println(
                rstrip(
                    join(
                        [
                            i == 1 ? rpad(r[i], width[i]) : lpad(r[i], width[i]) for
                            i in eachindex(r)
                        ],
                        "  ",
                    ),
                ),
            )
        end
    elseif cmd in ("PINV", "TINV")
        invariants(n, cmd=="TINV")
    elseif cmd in ("SIPHONS", "TRAPS")
        length(n.p) > 12 && error("more than 12 places")
        ss = sets(n, cmd=="TRAPS")
        println("minimal ", cmd=="TRAPS" ? "traps" : "siphons", ": ", length(ss))
        for s in ss
            println(
                "  $(settext(n,s)) tokens=",
                sum(n.current[p] for p in eachindex(n.p) if s & (1<<(p-1)) != 0; init = 0),
            )
        end
    elseif cmd == "CLASSIFY"
        classify(n)
    elseif cmd == "WORKFLOW"
        workflow(n, limit)
    elseif cmd == "SHOW"
        for p in eachindex(n.p)
            println(
                "place $(n.p[p]) tokens=$(n.initial[p]) capacity=",
                n.cap[p] == 0 ? "none" : n.cap[p],
            )
        end
        for t in eachindex(n.t)
            list(mat) = (
                a = ["$(n.p[p]):$(mat[p,t])" for p in eachindex(n.p) if mat[p, t] > 0];
                isempty(a) ? "-" : join(a, ",")
            )
            println(
                "transition $(n.t[t]) priority=$(n.priority[t]) pre=$(list(n.pre)) post=$(list(n.post)) inhibit=$(list(n.inh))",
            )
        end
    end
end
function main()
    blocks = parse(Int, readline())
    for _ in 1:blocks
        n = Net(split(readline())[2])
        while true
            line = readline()
            line == "END NET" && break
            try
                define!(n, split(line))
            catch e
                e isa ErrorException || rethrow()
                println("error: ", e.msg)
            end
        end
        n.current = copy(n.initial)
        println(
            "net $(n.name): places=$(length(n.p)) transitions=$(length(n.t)) arcs=$(n.arcs) inhibitors=$(n.inhibitors)",
        )
        for _ in 1:parse(Int, readline())
            try
                execute!(n, split(readline()))
            catch e
                e isa ErrorException || rethrow()
                println("error: ", e.msg)
            end
        end
    end
end
main()
