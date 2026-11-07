mutable struct Process
    maximum::Vector{Int}
    allocation::Vector{Int}
    created::Int
end
struct Waiting
    id::Int
    value::Vector{Int}
    since::Int
end
struct Event
    time::Int
    kind::String
    id::Int
    value::Vector{Int}
    wait::Int
end
mutable struct State
    total::Vector{Int}
    available::Vector{Int}
    processes::Dict{Int,Process}
    queue::Vector{Waiting}
    history::Vector{Event}
end
mutable struct Manager
    state::State
    mode::String
    policy::String
    trace::Bool
    automatic::Bool
    time::Int
    snapshots::Dict{String,State}
end
vecform(v) = "(" * join(v, ",") * ")"
pname(id) = "P$id"
plist(ids) = join(pname.(ids), " ")
ids(s) = sort(collect(keys(s.processes)))
need(p) = p.maximum - p.allocation
blocked(s, id) = any(q -> q.id == id, s.queue)
function request(s, id)
    for q in s.queue
        q.id == id && return q.value
    end
    zeros(Int, length(s.total))
end
function check(s, detect=false, trace=false)
    work = copy(s.available)
    remaining = Int[]
    idle = Int[]
    sequence = Int[]
    for id in ids(s)
        if detect && all(iszero, s.processes[id].allocation)
            push!(idle, id)
        else
            push!(remaining, id)
        end
    end
    tag = detect ? "[detect]" : "[safety]"
    if trace
        suffix = isempty(idle) ? "" : " idle " * plist(idle)
        println(tag, " start work=", vecform(work), suffix)
    end
    while true
        at = findfirst(remaining) do id
            v = detect ? request(s, id) : need(s.processes[id])
            all(v .<= work)
        end
        isnothing(at) && break
        id = remaining[at]
        work += s.processes[id].allocation
        deleteat!(remaining, at)
        push!(sequence, id)
        trace && println(tag, " ", pname(id), " can finish, work=", vecform(work))
    end
    if trace && !isempty(remaining)
        println(tag, " stuck work=", vecform(work), " remaining ", plist(remaining))
    end
    isempty(remaining), sequence, remaining
end
function decision(m, id, v; reject=true, trace=m.trace)
    s = m.state
    p = s.processes[id]
    if reject
        blocked(s, id) && return ("rejected", "process $(pname(id)) is blocked", Int[])
        all(iszero, v) && return ("rejected", "zero vector", Int[])
        any(v .> need(p)) && return ("rejected", "request exceeds need", Int[])
        if m.mode == "ORDER"
            last = findlast(>(0), p.allocation)
            if !isnothing(last) && any(>(0), v[1:last])
                return "rejected", "resource order violation", Int[]
            end
        end
    end
    any(v .> s.available) && return ("blocked", "insufficient resources", Int[])
    if m.mode == "AVOID"
        olda, oldp = s.available, p.allocation
        s.available = olda - v
        p.allocation = oldp + v
        ok, seq, _ = check(s, false, trace)
        s.available, p.allocation = olda, oldp
        !ok && return ("blocked", "unsafe state", Int[])
        return "granted", "", seq
    end
    "granted", "", Int[]
end
function record!(m, kind, id, v, wait=0)
    push!(m.state.history, Event(m.time, kind, id, copy(v), wait))
end
function grant!(s, id, v)
    s.available -= v
    s.processes[id].allocation += v
end
function remove_wait!(s, id)
    filter!(q -> q.id != id, s.queue)
end
function retry!(m)
    for q in copy(m.state.queue)
        result, _, _ = decision(m, q.id, q.value; reject=false)
        if result == "granted"
            grant!(m.state, q.id, q.value)
            remove_wait!(m.state, q.id)
            println("unblocked ", pname(q.id), " ", vecform(q.value))
            record!(m, "unblocked", q.id, q.value, m.time - q.since)
        end
    end
end
function terminate!(m, id, kind; retry=true)
    s = m.state
    v = copy(s.processes[id].allocation)
    s.available += v
    delete!(s.processes, id)
    remove_wait!(s, id)
    println(kind, " ", pname(id), " released ", vecform(v))
    record!(m, kind, id, v)
    retry && retry!(m)
end
function victims(s)
    _, _, dead = check(s, true)
    choices = Vector{Int}[]
    for mask in 1:(2^length(dead)-1)
        push!(choices, [dead[i] for i in eachindex(dead) if mask & (1 << (i-1)) != 0])
    end
    sort!(choices; by=v -> (length(v), sum(sum(s.processes[id].allocation) for id in v), v))
    for choice in choices
        trial = deepcopy(s)
        for id in choice
            trial.available += trial.processes[id].allocation
            delete!(trial.processes, id)
        end
        ok, _, _ = check(trial, true)
        ok && return choice
    end
    Int[]
end
function graph(m, resource)
    s = m.state
    order = ids(s)
    edges = Dict(id => Tuple{Int,Int}[] for id in order)
    if resource
        if any(!=(1), s.total)
            println("error: not single-instance")
            return
        end
        for j in eachindex(s.total), id in order
            s.processes[id].allocation[j] > 0 && println("assign ", Char('A'+j-1), " -> ", pname(id))
        end
        for id in order
            r = request(s, id)
            for j in eachindex(r)
                r[j] == 0 && continue
                println("request ", pname(id), " -> ", Char('A'+j-1))
                for to in order
                    s.processes[to].allocation[j] > 0 && push!(edges[id], (to, j))
                end
            end
        end
        for id in order
            r = request(s, id)
            for j in eachindex(r)
                if need(s.processes[id])[j] > 0 && r[j] == 0
                    println("claim ", pname(id), " -> ", Char('A'+j-1))
                end
            end
        end
    else
        count = 0
        for id in order, to in order
            id == to && continue
            labels = [string(Char('A'+j-1)) for j in eachindex(s.total)
                      if request(s, id)[j] > s.available[j] && s.processes[to].allocation[j] > 0]
            if !isempty(labels)
                println(pname(id), " -> ", pname(to), " on ", join(labels, ","))
                push!(edges[id], (to, 0))
                count += 1
            end
        end
        count == 0 && println("no wait edges")
    end
    cycles = Vector{Int}[]
    for start in order
        function visit(at, path, seen)
            for (to, type) in edges[at]
                next = resource ? [path; type; to] : [path; to]
                if to == start
                    (resource || length(seen) >= 2) && push!(cycles, next)
                elseif to > start && !(to in seen)
                    visit(to, next, union(seen, Set([to])))
                end
            end
        end
        visit(start, [start], Set([start]))
    end
    sort!(cycles)
    for cycle in cycles
        parts = [resource && iseven(i) ? string(Char('A'+x-1)) : pname(x)
                 for (i, x) in enumerate(cycle)]
        println("cycle: ", join(parts, " -> "))
    end
    isempty(cycles) && println("no cycles")
end
function table(s)
    widths = length.(string.(s.total))
    names = join([lpad(string(Char('A'+i-1)), widths[i]) for i in eachindex(widths)], " ")
    cw = max.([10, 3, 4, 7], length(names))
    form(v) = join([lpad(string(v[i]), widths[i]) for i in eachindex(v)], " ")
    function row(heading, cols)
        line = rpad(heading, 9)
        for i in 1:4
            line *= "  " * rpad(i <= length(cols) ? cols[i] : "", cw[i])
        end
        println(rstrip(line))
    end
    row("Process", ["Allocation", "Max", "Need", "Request"])
    row("", fill(names, 4))
    for id in ids(s)
        p = s.processes[id]
        row(pname(id), form.([p.allocation, p.maximum, need(p), request(s, id)]))
    end
    row("Available", [form(s.available)])
    row("Total", [form(s.total)])
    if isempty(s.queue)
        println("blocked queue: empty")
    else
        println("blocked queue: ", join(["$(pname(q.id)) $(vecform(q.value)) since t=$(q.since)" for q in s.queue], ", "))
    end
end
function execute!(m, words)
    cmd = words[1]
    args = words[2:end]
    s = m.state
    hasid = cmd in ["PROCESS", "CLAIM", "REQUEST", "WHATIF", "RELEASE", "FINISH", "ABORT", "CANCEL", "MAXGRANT"]
    hasvector = cmd in ["PROCESS", "CLAIM", "REQUEST", "WHATIF", "RELEASE", "ADD", "REMOVE"]
    id = hasid ? parse(Int, args[1]) : 0
    v = hasvector ? parse.(Int, args[(hasid ? 2 : 1):end]) : Int[]
    err = ""
    if hasvector && length(v) != length(s.total)
        err = "wrong vector length"
    elseif hasid && cmd == "PROCESS" && haskey(s.processes, id)
        err = "duplicate process $(pname(id))"
    elseif hasid && cmd != "PROCESS" && !haskey(s.processes, id)
        err = "unknown process $(pname(id))"
    end
    if !isempty(err)
        println("error: ", err)
        return
    end
    if cmd == "RESOURCES"
        total = parse.(Int, args)
        m.state = State(total, copy(total), Dict{Int,Process}(), Waiting[], Event[])
        println("resources ", vecform(total))
    elseif cmd in ["MODE", "POLICY", "TRACE", "AUTODETECT"]
        if cmd == "MODE"
            m.mode = args[1]
        elseif cmd == "POLICY"
            m.policy = args[1]
        elseif cmd == "TRACE"
            m.trace = args[1] == "ON"
        else
            m.automatic = args[1] == "ON"
        end
        println(lowercase(cmd), " ", args[1])
    elseif cmd == "PROCESS"
        if any(v .> s.total)
            err = "max exceeds total"
        else
            s.processes[id] = Process(v, zeros(Int, length(v)), m.time)
            println("process ", pname(id), " max ", vecform(v))
        end
    elseif cmd == "CLAIM"
        p = s.processes[id]
        if blocked(s, id)
            err = "process $(pname(id)) is blocked"
        elseif any(p.allocation .> v)
            err = "claim below allocation"
        elseif any(v .> s.total)
            err = "max exceeds total"
        else
            old = p.maximum
            p.maximum = v
            if m.mode == "AVOID"
                ok, _, _ = check(s, false, m.trace)
                if !ok
                    p.maximum = old
                    err = "claim makes state unsafe"
                end
            end
            if isempty(err)
                println("claim ", pname(id), " max ", vecform(v))
                retry!(m)
            end
        end
    elseif cmd in ["ADD", "REMOVE"]
        if all(iszero, v)
            err = "zero vector"
        elseif cmd == "ADD"
            s.total += v
            s.available += v
            println("added ", vecform(v), " total ", vecform(s.total))
            retry!(m)
        elseif any(v .> s.available)
            err = "remove exceeds available"
        elseif any(iszero, s.total - v)
            err = "total must stay positive"
        elseif any(p -> any(p.maximum .> s.total - v), values(s.processes))
            err = "max exceeds total"
        else
            old = s.available
            s.available = old - v
            if m.mode == "AVOID"
                ok, _, _ = check(s, false, m.trace)
                !ok && (err = "removal makes state unsafe")
            end
            if isempty(err)
                s.total -= v
                println("removed ", vecform(v), " total ", vecform(s.total))
            else
                s.available = old
            end
        end
    elseif cmd in ["REQUEST", "WHATIF"]
        result, reason, seq = decision(m, id, v)
        if cmd == "WHATIF"
            line = "whatif $(pname(id)) $(vecform(v)): $result"
            if result != "granted"
                line *= " ($reason)"
            elseif m.mode == "AVOID"
                line *= ", safe sequence " * plist(seq)
            end
            println(line)
        elseif result == "rejected"
            err = reason
        else
            if result == "granted"
                grant!(s, id, v)
                println("granted ", pname(id), " ", vecform(v))
            else
                push!(s.queue, Waiting(id, v, m.time))
                println("blocked ", pname(id), " ", vecform(v), ": ", reason)
            end
            record!(m, result, id, v)
            if result == "blocked" && m.automatic
                _, _, dead = check(s, true, m.trace)
                !isempty(dead) && println("deadlock detected: ", plist(dead))
            end
        end
    elseif cmd == "RELEASE"
        p = s.processes[id]
        if blocked(s, id)
            err = "process $(pname(id)) is blocked"
        elseif all(iszero, v)
            err = "zero vector"
        elseif any(v .> p.allocation)
            err = "release exceeds allocation"
        else
            p.allocation -= v
            s.available += v
            println("released ", pname(id), " ", vecform(v))
            record!(m, "released", id, v)
            retry!(m)
        end
    elseif cmd in ["FINISH", "ABORT"]
        if cmd == "FINISH" && blocked(s, id)
            err = "process $(pname(id)) is blocked"
        else
            terminate!(m, id, cmd == "FINISH" ? "finished" : "aborted")
        end
    elseif cmd == "CANCEL"
        if !blocked(s, id)
            err = "process $(pname(id)) is not blocked"
        else
            v = request(s, id)
            remove_wait!(s, id)
            println("cancelled ", pname(id), " ", vecform(v))
            record!(m, "cancelled", id, v)
        end
    elseif cmd == "MAXGRANT"
        if blocked(s, id)
            err = "process $(pname(id)) is blocked"
        else
            result = zeros(Int, length(s.total))
            for j in eachindex(result)
                for x in need(s.processes[id])[j]:-1:1
                    v = zeros(Int, length(result))
                    v[j] = x
                    decision(m, id, v; trace=false)[1] == "granted" || continue
                    result[j] = x
                    break
                end
            end
            println("maxgrant ", pname(id), ": ", vecform(result))
        end
    elseif cmd == "SAFE"
        if isempty(s.processes)
            println("safe: no processes")
        else
            ok, seq, left = check(s, false, m.trace)
            println(ok ? "safe: " * plist(seq) : "unsafe: " * plist(left) * " cannot finish")
        end
    elseif cmd == "SEQUENCES"
        if isempty(s.processes)
            println("safe sequences: no processes")
        else
            count = 0
            samples = String[]
            k = parse(Int, args[1])
            order = ids(s)
            function search(work, path)
                if length(path) == length(order)
                    count += 1
                    length(samples) < k && push!(samples, plist(path))
                    return
                end
                for id in order
                    p = s.processes[id]
                    if !(id in path) && all(need(p) .<= work)
                        search(work + p.allocation, [path; id])
                    end
                end
            end
            search(s.available, Int[])
            println("safe sequences: ", count)
            foreach(println, samples)
        end
    elseif cmd == "DEFICIT"
        result = String[]
        for j in eachindex(s.total)
            limit = sum((need(p)[j] for p in values(s.processes)); init=0)
            value = "-"
            for x in 0:limit
                trial = deepcopy(s)
                trial.available[j] += x
                if check(trial)[1]
                    value = string(x)
                    break
                end
            end
            push!(result, value)
        end
        println("deficit: ", vecform(result))
    elseif cmd == "STATE"
        table(s)
    elseif cmd == "STATS"
        for j in eachindex(s.total)
            total = s.total[j]
            used = total - s.available[j]
            requested = sum((q.value[j] for q in s.queue); init=0)
            pct = used * 1000 ÷ total
            println(Char('A'+j-1), ": allocated $used/$total (", pct ÷ 10, ".", pct % 10, "%), requested ", requested)
        end
        kinds = ["granted", "blocked", "unblocked", "released", "finished", "aborted", "cancelled"]
        counts = Dict(kind => Base.count(e -> e.kind == kind, s.history) for kind in kinds)
        println("events: ", join(["$kind $(counts[kind])" for kind in kinds], ", "))
        n = counts["unblocked"]
        if n == 0
            println("waits: none")
        else
            total = sum(e.wait for e in s.history if e.kind == "unblocked")
            avg = total * 100 ÷ n
            println("waits: $n unblocked, total $total, average ", avg ÷ 100, ".", lpad(string(avg % 100), 2, '0'))
        end
    elseif cmd == "DETECT"
        _, _, dead = check(s, true, m.trace)
        println(isempty(dead) ? "no deadlock" : "deadlocked: " * plist(dead))
    elseif cmd == "VICTIMS"
        choice = victims(s)
        println(isempty(choice) ? "no deadlock" : "victims: " * plist(choice))
    elseif cmd == "RECOVER"
        count = 0
        while true
            _, _, dead = check(s, true, m.trace)
            isempty(dead) && break
            if !isempty(args)
                for id in dead
                    terminate!(m, id, "aborted"; retry=false)
                    count += 1
                end
                retry!(m)
                break
            end
            function priority(id)
                p = s.processes[id]
                m.policy == "ALLOC" && return (sum(p.allocation), -id)
                m.policy == "NEED" && return (-sum(need(p)), -id)
                (-p.created, -id)
            end
            sort!(dead; by=priority)
            terminate!(m, dead[1], "aborted")
            count += 1
        end
        println(count == 0 ? "no deadlock" : "recovered: $count aborted")
    elseif cmd in ["WAITGRAPH", "GRAPH"]
        graph(m, cmd == "GRAPH")
    elseif cmd == "HISTORY"
        found = false
        for e in s.history
            if !isempty(args) && args[1] != e.kind && args[1] != string(e.id)
                continue
            end
            line = "t=$(e.time) $(e.kind) $(pname(e.id)) $(vecform(e.value))"
            e.kind == "unblocked" && (line *= " waited $(e.wait)")
            println(line)
            found = true
        end
        !found && println("no events")
    elseif cmd == "SNAPSHOT"
        m.snapshots[args[1]] = deepcopy(s)
        println("saved ", args[1])
    elseif cmd == "RESTORE"
        if !haskey(m.snapshots, args[1])
            err = "unknown snapshot $(args[1])"
        else
            m.state = deepcopy(m.snapshots[args[1]])
            println("restored ", args[1])
        end
    end
    !isempty(err) && println("error: ", err)
end
function main()
    m = Manager(State(Int[], Int[], Dict{Int,Process}(), Waiting[], Event[]), "AVOID", "ALLOC", false, false, 0, Dict{String,State}())
    n = parse(Int, readline())
    for t in 1:n
        m.time = t
        execute!(m, String.(split(readline())))
    end
end
main()
