const ALGORITHMS = ["FCFS", "SJF", "SRTF", "RR", "PRIORITY", "HRRN", "EDF", "LOTTERY", "MLFQ"]
const KEYS = ["cs", "q", "k", "s", "seed"]

struct CommandError <: Exception
    reason::String
end
fail(s) = throw(CommandError(s))
emit(xs...) = println(join(xs, " "))
ratio(u, v) = let x = 100u÷v
    string(x÷100, ".", lpad(x%100, 2, '0'))
end

mutable struct CPUProcess
    id::String
    arrival::Int
    priority::Int
    deadline::Int
    bursts::Vector{Int}
end

mutable struct ProcessState
    state::String
    burst::Int
    left::Int
    effective::Int
    wait::Int
    level::Int
    used::Int
    enqueued::Int
    start::Int
    finish::Int
    slices::Int
end

mutable struct BurstRecord
    ready::Int
    start::Int
    finish::Int
    slices::Int
end

struct CPUSnapshot
    states::Vector{ProcessState}
    queues::Vector{Vector{Int}}
    cpu::Int
    mode::Int
end

struct ScheduleResult
    p::Vector{CPUProcess}
    states::Vector{ProcessState}
    bursts::Vector{Vector{BurstRecord}}
    labels::Vector{String}
    events::Vector{String}
    shots::Vector{CPUSnapshot}
    finish::Int
    switches::Int
    busy::Int
    switching::Int
    idle::Int
    qmax::Int
    qsum::Int
    met::Int
    missed::Int
    totals::Vector{Int}
end
allowed(a, k) = k == "cs" || (k == "q" && a in ("RR", "LOTTERY")) || (k == "seed" && a == "LOTTERY") || (k == "k" && a == "PRIORITY") || (k == "s" && a == "MLFQ")
valid(k, v) = k == "cs" ? 0 <= v <= 5 : k == "q" ? 1 <= v <= 20 : k == "k" ? 1 <= v <= 50 : k == "s" ? 0 <= v <= 500 : k == "seed" && 1 <= v <= 2147483646
notation(a, p, full = false) = join(["$k=$(p[k])" for k in KEYS if full || allowed(a, k)], " ")

function simulate(p, a, param)
    n = length(p)
    states = [ProcessState("FUTURE", 1, x.bursts[1], x.priority, 0, 0, 0, 0, -1, -1, 0) for x in p]
    bursts = [[BurstRecord(0, -1, 0, 0) for _ in 1:cld(length(x.bursts), 2)] for x in p]
    queues = [Int[], Int[], Int[]]
    cpu = previous = 0
    mode = sw = run = switches = busy = switching = idle = qmax = qsum = 0
    x = param["seed"]
    labels = String[]
    events = String[]
    shots = CPUSnapshot[]
    t = 0
    deadline(i) = p[i].deadline == 0 ? typemax(Int) : p[i].arrival+p[i].deadline
    while true
        log(s) = push!(events, "$t $s")
        function enqueue(i)
            z = states[i]
            z.state = "READY"
            z.enqueued = t
            push!(queues[a == "MLFQ" ? z.level+1 : 1], i)
        end
        function start(i)
            cpu = i
            mode = 2
            run = 0
            z = states[i]
            z.state = "RUN"
            z.start<0 && (z.start = t)
            b = bursts[i][cld(z.burst, 2)]
            b.start<0 && (b.start = t)
        end
        if a == "PRIORITY"
            for i in queues[1]
                z = states[i]
                z.wait += 1
                if z.wait == param["k"]
                    z.wait = 0
                    if z.effective>0
                        z.effective -= 1
                        log("AGE $(p[i].id) $(z.effective)")
                    end
                end
            end
        end
        for i in eachindex(p)
            z = states[i]
            if z.state == "IO" && z.left == 0
                z.burst += 1
                z.left = p[i].bursts[z.burst]
                bursts[i][cld(z.burst, 2)].ready = t
                enqueue(i)
                log("IODONE $(p[i].id)")
            end
        end
        for i in eachindex(p)
            if states[i].state == "FUTURE" && p[i].arrival == t
                bursts[i][1].ready = t
                enqueue(i)
                log("ARRIVE $(p[i].id)")
            end
        end
        if mode == 1 && sw == 0
            start(cpu)
            log("START $(p[cpu].id)")
        elseif mode == 2
            i = cpu
            z = states[i]
            if z.left == 0 && z.burst == length(p[i].bursts)
                z.state = "DONE"
                z.finish = t
                log("DONE $(p[i].id)")
                mode = 0
                cpu = 0
            else
                demoted = false
                if a == "MLFQ" && z.level<2 && z.used == (4, 8)[z.level+1]
                    z.level += 1
                    z.used = 0
                    demoted = true
                    log("DEMOTE $(p[i].id) $(z.level)")
                end
                preempt = any((a == "SRTF" && states[j].left<z.left) || (a == "PRIORITY" && states[j].effective<z.effective) || (a == "EDF" && deadline(j)<deadline(i)) || (a == "MLFQ" && l-1<z.level) for (l, q) in enumerate(queues) for j in q)
                if z.left == 0
                    z.burst += 1
                    z.left = p[i].bursts[z.burst]
                    z.state = "IO"
                    log("IO $(p[i].id) $(z.left)")
                    mode = 0
                    cpu = 0
                elseif demoted
                    enqueue(i)
                    mode = 0
                    cpu = 0
                elseif a in ("RR", "LOTTERY") && run == param["q"]
                    enqueue(i)
                    log("EXPIRE $(p[i].id)")
                    mode = 0
                    cpu = 0
                elseif preempt
                    enqueue(i)
                    log("PREEMPT $(p[i].id)")
                    mode = 0
                    cpu = 0
                end
            end
        end
        if all(z->z.state == "DONE", states)
            push!(shots, CPUSnapshot(deepcopy(states), [Int[], Int[], Int[]], 0, 0))
            break
        end
        if a == "MLFQ" && param["s"]>0 && t>0 && t%param["s"] == 0
            append!(queues[1], queues[2])
            append!(queues[1], queues[3])
            empty!(queues[2])
            empty!(queues[3])
            for z in states
                z.level = 0
                z.used = 0
            end
            log("BOOST")
        end
        if mode == 0
            l = findfirst(q->!isempty(q), queues)
            if !isnothing(l)
                q = queues[l]
                selected = 1
                if a == "LOTTERY"
                    total = sum(10-p[i].priority for i in q)
                    x = 48271x%2147483647
                    draw = x%total
                    count = 0
                    for (j, i) in enumerate(q)
                        count += 10-p[i].priority
                        if count>draw
                            selected = j
                            break
                        end
                    end
                else
                    for j in 2:length(q)
                        i = q[j]
                        b = q[selected]
                        u = states[i]
                        v = states[b]
                        better = a in ("SJF", "SRTF") ? u.left<v.left : a == "PRIORITY" ? u.effective<v.effective : a == "EDF" ? deadline(i)<deadline(b) : a == "HRRN" ? (t-u.enqueued+u.left)*v.left>(t-v.enqueued+v.left)*u.left : false
                        better && (selected = j)
                    end
                end
                i = q[selected]
                deleteat!(q, selected)
                z = states[i]
                z.effective = p[i].priority
                z.wait = 0
                z.slices += 1
                bursts[i][cld(z.burst, 2)].slices += 1
                change = i != previous
                change && (switches += 1)
                if change && param["cs"]>0
                    cpu = i
                    mode = 1
                    sw = param["cs"]
                    z.state = "SWITCH"
                    log("SWITCH $(p[i].id)")
                else
                    start(i)
                    log("DISPATCH $(p[i].id)")
                end
            end
        end
        push!(shots, CPUSnapshot(deepcopy(states), deepcopy(queues), cpu, mode))
        qlen = sum(length, queues)
        qmax = max(qmax, qlen)
        qsum += qlen
        label = "IDLE"
        if mode == 2
            z = states[cpu]
            z.left -= 1
            z.used += 1
            run += 1
            previous = cpu
            label = p[cpu].id
            busy += 1
            z.left == 0 && (bursts[cpu][cld(z.burst, 2)].finish = t+1)
        elseif mode == 1
            sw -= 1
            label = "CS"
            switching += 1
        else
            idle += 1
        end
        push!(labels, label)
        for z in states
            z.state == "IO" && (z.left -= 1)
        end
        t += 1
    end
    totals = zeros(Int, 3)
    met = missed = 0
    for i in eachindex(p)
        z = states[i]
        u = p[i]
        turn = z.finish-u.arrival
        totals.+= [turn, turn-sum(u.bursts), z.start-u.arrival]
        if u.deadline>0
            z.finish <= u.arrival+u.deadline ? (met += 1) : (missed += 1)
        end
    end
    ScheduleResult(p, states, bursts, labels, events, shots, t, switches, busy, switching, idle, qmax, qsum, met, missed, totals)
end
metrics(r, i) = let p = r.p[i], z = r.states[i]
    t = z.finish-p.arrival
    [t, t-sum(p.bursts), z.start-p.arrival]
end
summaryline(r) = let n = length(r.p)
    "turnaround=$(ratio(r.totals[1],n)) waiting=$(ratio(r.totals[2],n)) response=$(ratio(r.totals[3],n)) util=$(ratio(r.busy*100,r.finish)) end=$(r.finish) switches=$(r.switches)"
end

function listline(p)
    b = join([string(isodd(i) ? "C" : "I", v) for (i, v) in enumerate(p.bursts)], ",")
    d = p.deadline == 0 ? "none" : string(p.deadline)
    "$(p.id) arrival=$(p.arrival) priority=$(p.priority) deadline=$d bursts=$b"
end

function command!(registry, w)
    c = w[1]
    n(i) = parse(Int, w[i])
    p = length(w)>1 ? get(registry, w[2], nothing) : nothing
    if c == "PROC"
        !isnothing(p) && fail("duplicate process $(w[2])")
        length(registry) == 10 && fail("too many processes")
        n(3)>200 && fail("invalid arrival $(w[2])")
        n(4)>9 && fail("invalid priority $(w[2])")
        b = [parse(Int, s[2:end]) for s in w[5:end]]
        (iseven(length(b)) || any(!(1 <= v <= 30) || w[i+4][1] != (isodd(i) ? 'C' : 'I') for (i, v) in enumerate(b))) && fail("invalid bursts $(w[2])")
        p = CPUProcess(w[2], n(3), n(4), 0, b)
        registry[p.id] = p
        emit(c, p.id, "cpu=$(sum(b[1:2:end])) io=$(sum(b[2:2:end]))")
        return
    elseif c == "GEN"
        generated_count = n(3)
        ids = [w[2]*string(i) for i in 1:generated_count]
        for id in ids
            haskey(registry, id) && fail("duplicate process $id")
        end
        length(registry)+generated_count>10 && fail("too many processes")
        emit(c, "count=$generated_count")
        x = n(4)
        next() = (x = 48271x%2147483647)
        for id in ids
            arrival = next()%21
            priority = next()%10
            m = 1+next()%3
            b = Int[]
            for j in 1:m
                j>1 && push!(b, 1+next()%8)
                push!(b, 1+next()%9)
            end
            p = CPUProcess(id, arrival, priority, 0, b)
            registry[id] = p
            emit(listline(p))
        end
        return
    elseif c in ("SETPRIO", "DEADLINE", "DROP")
        isnothing(p) && fail("unknown process $(w[2])")
        if c == "DROP"
            delete!(registry, p.id)
            emit(c, p.id)
        elseif c == "SETPRIO"
            n(3)>9 && fail("invalid priority $(p.id)")
            p.priority = n(3)
            emit(c, p.id, "priority=$(p.priority)")
        else
            n(3)>1000 && fail("invalid deadline $(p.id)")
            p.deadline = n(3)
            emit(c, p.id, p.deadline == 0 ? "none" : p.deadline)
        end
        return
    elseif c == "CLEAR"
        emit(c, "count=$(length(registry))")
        empty!(registry)
        return
    elseif c == "LIST"
        emit(c, "count=$(length(registry))")
        for id in sort(collect(keys(registry)))
            emit(listline(registry[id]))
        end
        return
    end
    a = ""
    metric = ""
    start = 3
    multi = c in ("COMPARE", "RANK", "DIFF")
    if c == "COMPARE"
        start = 2
    elseif c == "RANK"
        metric = w[2]
        metric in ("turnaround", "waiting", "response", "end", "switches", "missed") || fail("unknown metric $metric")
    else
        a = w[2]
        a in ALGORITHMS || fail("unknown algorithm $a")
        if c == "DIFF"
            w[3] in ALGORITHMS || fail("unknown algorithm $(w[3])")
            start = 4
        end
    end
    c in ("SNAPSHOT", "WINDOW") && (start = 4)
    c == "WINDOW" && !(1 <= n(3) <= 1000) && fail("invalid window")
    seen = Set{String}()
    if c == "SWEEP"
        start = 6
        k = w[3]
        k in KEYS || fail("unknown key $k")
        allowed(a, k) || fail("key $k not allowed for $a")
        (n(4)>n(5) || !valid(k, n(4)) || !valid(k, n(5)) || n(5)-n(4)>20) && fail("invalid range")
        push!(seen, k)
    end
    param = Dict("cs"=>0, "q"=>4, "k"=>5, "s"=>0, "seed"=>1)
    for word in w[start:end]
        kv = split(word, '=')
        k = String(kv[1])
        v = parse(Int, kv[2])
        k in KEYS || fail("unknown key $k")
        !multi && !allowed(a, k) && fail("key $k not allowed for $a")
        k in seen && fail("duplicate key $k")
        valid(k, v) || fail("invalid $k")
        push!(seen, k)
        param[k] = v
    end
    isempty(registry) && fail("no processes")
    ps = [registry[id] for id in sort(collect(keys(registry)))]
    N = length(ps)
    if c == "SWEEP"
        emit(c, a, w[3], n(4), n(5))
        best = typemax(Int)
        bestv = 0
        for v in n(4):n(5)
            param[w[3]] = v
            r = simulate(ps, a, param)
            emit(notation(a, param), summaryline(r))
            if r.totals[2]<best
                best = r.totals[2]
                bestv = v
            end
        end
        emit("BEST", "$(w[3])=$bestv")
        return
    end
    if multi
        if c == "DIFF"
            r = simulate(ps, a, param)
            s = simulate(ps, w[3], param)
            emit(c, a, w[3], notation("", param, true))
            wins = loss = ties = 0
            for i in eachindex(ps)
                u = metrics(r, i)
                v = metrics(s, i)
                emit(ps[i].id, "turnaround=$(u[1])/$(v[1]) waiting=$(u[2])/$(v[2]) response=$(u[3])/$(v[3])")
                u[1]<v[1] ? (wins += 1) : u[1]>v[1] ? (loss += 1) : (ties += 1)
            end
            emit("WINS", "$a=$wins $(w[3])=$loss ties=$ties")
            return
        end
        results = [simulate(ps, a, param) for a in ALGORITHMS]
        if c == "COMPARE"
            emit(c, notation("", param, true))
            row(v) = println(rpad(v[1], 8)*join([" "*lpad(x, 8) for x in v[2:end]], ""))
            row(["ALGO", "TURN", "WAIT", "RESP", "UTIL", "END", "SWITCH", "MISS"])
            for (i, r) in enumerate(results)
                row([ALGORITHMS[i], ratio(r.totals[1], N), ratio(r.totals[2], N), ratio(r.totals[3], N), ratio(r.busy*100, r.finish), string(r.finish), string(r.switches), string(r.missed)])
            end
            emit("BEST", ("$k=$(ALGORITHMS[argmin([r.totals[j] for r in results])])" for (j, k) in enumerate(("turnaround", "waiting", "response")))...)
        else
            emit(c, metric, notation("", param, true))
            j = findfirst(==(metric), ["turnaround", "waiting", "response"])
            values = [!isnothing(j) ? r.totals[j] : metric == "end" ? r.finish : metric == "switches" ? r.switches : r.missed for r in results]
            for i in sortperm(values)
                rank = count(<(values[i]), values)+1
                emit(rank, ALGORITHMS[i], isnothing(j) ? string(values[i]) : ratio(values[i], N))
            end
        end
        return
    end
    r = simulate(ps, a, param)
    note = notation(a, param)
    T = r.finish
    if c == "TRACE"
        emit(c, a, note)
        foreach(emit, r.events)
        emit("END", T)
    elseif c == "TIMELINE"
        T>100 && fail("too long $T")
        emit(c, a, note, "end=$T")
        chars = Dict("READY"=>'.', "RUN"=>'#', "SWITCH"=>'s', "IO"=>'i', "FUTURE"=>'-', "DONE"=>'-')
        for i in eachindex(ps)
            emit(rpad(ps[i].id, 8), join([chars[r.shots[t].states[i].state] for t in 1:T]))
        end
    elseif c == "SNAPSHOT"
        t = n(3)
        s = r.shots[min(t, T)+1]
        emit(c, a, note, "t=$t")
        s.mode == 0 ? emit("CPU IDLE") : emit("CPU", s.mode == 1 ? "SWITCH" : "RUN", ps[s.cpu].id)
        for l in 1:(a == "MLFQ" ? 3 : 1)
            ids = [ps[i].id for i in s.queues[l]]
            emit(a == "MLFQ" ? "QUEUE$(l-1)" : "QUEUE", isempty(ids) ? "none" : join(ids, " "))
        end
        for (i, p) in enumerate(ps)
            z = s.states[i]
            if z.state == "FUTURE"
                emit(p.id, "FUTURE at=$(p.arrival)")
            elseif z.state == "DONE"
                emit(p.id, "DONE at=$(z.finish)")
            else
                line = "$(p.id) $(z.state) burst=$(z.burst) left=$(z.left)"
                a == "PRIORITY" && (line*= " prio=$(z.effective)")
                a == "MLFQ" && (line*= " level=$(z.level) used=$(z.used)")
                emit(line)
            end
        end
    elseif c == "BURSTS"
        emit(c, a, note)
        for (i, p) in enumerate(ps), (j, b) in enumerate(r.bursts[i])
            len = p.bursts[2j-1]
            emit(p.id, "#$j len=$len ready=$(b.ready) start=$(b.start) end=$(b.finish) wait=$(b.finish-b.ready-len) slices=$(b.slices)")
        end
    elseif c == "WINDOW"
        width = n(3)
        emit(c, a, note, "width=$width")
        for lo in 0:width:T-1
            hi = min(lo+width, T)
            shots = r.shots[lo+1:hi]
            labels = [ps[s.cpu].id for s in shots if s.mode == 2]
            cs = count(s->s.mode == 1, shots)
            idle = count(s->s.mode == 0, shots)
            busy = hi-lo-cs-idle
            counts = [count(==(p.id), labels) for p in ps]
            top = maximum(counts) == 0 ? "none" : ps[argmax(counts)].id
            emit("$lo-$hi busy=$busy switch=$cs idle=$idle util=$(ratio(busy*100,hi-lo)) top=$top")
        end
    elseif c == "STATS"
        emit(c, a, note)
        for (j, k) in enumerate(("turnaround", "waiting", "response"))
            values = [metrics(r, i)[j] for i in eachindex(ps)]
            lo = argmin(values)
            hi = argmax(values)
            v = sort(values)
            med = isodd(N) ? 2v[cld(N, 2)] : v[N÷2]+v[N÷2+1]
            emit("$k min=$(values[lo]) ($(ps[lo].id)) max=$(values[hi]) ($(ps[hi].id)) median=$(med÷2).$(med%2*5) total=$(r.totals[j])")
        end
    elseif c == "RUN"
        emit(c, a, note)
        segments = String[]
        lo = 0
        while lo<T
            hi = lo+1
            while hi<T && r.labels[hi+1] == r.labels[lo+1]
                hi += 1
            end
            push!(segments, "[$lo-$hi $(r.labels[lo+1])]")
            lo = hi
        end
        for i in 1:8:length(segments)
            emit("GANTT", join(segments[i:min(i+7, length(segments))], ""))
        end
        for (i, p) in enumerate(ps)
            z = r.states[i]
            m = metrics(r, i)
            line = "$(p.id) arrival=$(p.arrival) done=$(z.finish) turnaround=$(m[1]) waiting=$(m[2]) response=$(m[3]) slices=$(z.slices)"
            if p.deadline>0
                d = p.arrival+p.deadline
                line*= " deadline=$d late=$(max(0,z.finish-d))"
            end
            emit(line)
        end
        emit("AVERAGE turnaround=$(ratio(r.totals[1],N)) waiting=$(ratio(r.totals[2],N)) response=$(ratio(r.totals[3],N))")
        emit("CPU end=$T busy=$(r.busy) switch=$(r.switching) idle=$(r.idle) switches=$(r.switches) util=$(ratio(r.busy*100,T))")
        emit("QUEUE max=$(r.qmax) avg=$(ratio(r.qsum,T))")
        counts = Dict(k=>count(s->split(s)[2] == k, r.events) for k in ("PREEMPT", "EXPIRE", "DEMOTE", "BOOST", "AGE"))
        emit("EVENTS preempt=$(counts["PREEMPT"]) expire=$(counts["EXPIRE"]) demote=$(counts["DEMOTE"]) boost=$(counts["BOOST"]) age=$(counts["AGE"])")
        emit("DEADLINE met=$(r.met) missed=$(r.missed)")
    end
end

function main()
    registry = Dict{String, CPUProcess}()
    for _ in 1:parse(Int, readline())
        w = String.(split(readline()))
        try
            command!(registry, w)
        catch err
            err isa CommandError || rethrow()
            emit("ERROR", err.reason)
        end
    end
end
main()
