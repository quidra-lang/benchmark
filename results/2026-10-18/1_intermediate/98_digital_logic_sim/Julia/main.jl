const TYPES=["AND", "OR", "NAND", "NOR", "XOR", "XNOR", "NOT", "BUF", "MUX2", "DFF"]
const COUNTS=Dict(
    (p[1]=>parse(Int, p[2])) for p in split.(
        split(
            "BUILD:1 RESET:0 SET:3 APPLY:2 PULSE:3 CLOCK:4 RUN:1 WATCH:1 UNWATCH:1 SHOW:0 CHECK:2 PROBE:1 WAVE:2 HISTORY:1 ACTIVITY:1 STATUS:0 MODULES:0 NETLIST:1 HIERARCHY:1 STATS:1 TRUTHTABLE:1 EQUIV:2 FAULTS:1 CRITICAL:1 PERIOD:1",
        ),
        ':',
    )
)
const SIM=Set(
    split(
        "RESET SET APPLY PULSE CLOCK RUN WATCH UNWATCH SHOW CHECK PROBE WAVE HISTORY ACTIVITY STATUS",
    ),
)
struct InputError <: Exception
    reason::String
end
fail(s) = throw(InputError(s))
nameok(s) = occursin(r"^[a-z][a-z0-9_]{0,15}$", s)
numberok(s) = occursin(r"^(0|[1-9][0-9]{0,8})$", s)
function number(s, positive = false)
    (numberok(s)&&(!positive||s!="0"))||fail("bad number $s")
    parse(Int, s)
end
function parsevalue(s)
    s in ("0", "1", "X")||fail("bad value $s")
    s[1]
end
rowbits(r, n) = join(string((r>>(n-i))&1) for i in 1:n)
function logic(kind, a)
    y=if kind in ("AND", "NAND")
        '0' in a ? '0' : 'X' in a ? 'X' : '1'
    elseif kind in ("OR", "NOR")
        '1' in a ? '1' : 'X' in a ? 'X' : '0'
    elseif kind in ("XOR", "XNOR")
        'X' in a ? 'X' : isodd(count(==('1'), a)) ? '1' : '0'
    elseif kind=="MUX2"
        a[1]=='X' ? (a[2]==a[3] ? a[2] : 'X') : a[a[1]=='0' ? 2 : 3]
    else
        a[1]
    end
    kind in ("NAND", "NOR", "XNOR", "NOT") ? (y=='0' ? '1' : y=='1' ? '0' : 'X') : y
end
abstract type Item end
struct Gate <: Item
    name::String
    kind::String
    inputs::Vector{String}
    output::String
    delay::Int
end
struct LogicModule
    name::String
    inputs::Vector{String}
    outputs::Vector{String}
    body::Vector{Item}
end
struct Instance <: Item
    name::String
    child::LogicModule
    connections::Vector{Pair{String,String}}
end
struct Circuit
    name::String
    inputs::Vector{String}
    outputs::Vector{String}
    gates::Vector{Gate}
    signals::Vector{String}
    driver::Dict{String,Int}
    readers::Dict{String,Vector{Int}}
    flops::Vector{Int}
    order::Vector{Int}
    loop::Bool
end
function circuit(m)
    gates=Gate[]
    function expand(m, prefix, ports)
        actual(s) = get(ports, s, prefix*s)
        for x in m.body
            if x isa Gate
                push!(
                    gates,
                    Gate(prefix*x.name, x.kind, actual.(x.inputs), actual(x.output), x.delay),
                )
            else
                mapping=Dict(p=>actual(s) for (p, s) in x.connections)
                expand(x.child, prefix*x.name*".", mapping)
            end
        end
    end
    expand(m, "", Dict{String,String}())
    signals=vcat(m.inputs, [g.output for g in gates])
    driver=Dict(g.output=>i for (i, g) in enumerate(gates))
    readers=Dict(s=>Int[] for s in signals)
    flops=findall(g->g.kind=="DFF", gates)
    for (i, g) in enumerate(gates), s in unique(g.inputs)
        push!(readers[s], i)
    end
    waiting=zeros(Int, length(gates))
    ready=Int[]
    needed=0
    for (i, g) in enumerate(gates)
        g.kind=="DFF"&&continue
        needed+=1
        waiting[i]=count(s->haskey(driver, s)&&gates[driver[s]].kind!="DFF", unique(g.inputs))
        waiting[i]==0&&push!(ready, i)
    end
    order=Int[]
    while !isempty(ready)
        i=pop!(ready)
        push!(order, i)
        for r in readers[gates[i].output]
            gates[r].kind=="DFF"&&continue
            waiting[r]-=1
            waiting[r]==0&&push!(ready, r)
        end
    end
    Circuit(
        m.name,
        m.inputs,
        m.outputs,
        gates,
        signals,
        driver,
        readers,
        flops,
        order,
        length(order)!=needed,
    )
end
function combinational(c)
    isempty(c.flops)||fail("$(c.name) is not combinational")
    c.loop&&fail("$(c.name) has a combinational loop")
    length(c.inputs)<=8||fail("too many inputs $(length(c.inputs))")
end
function evaluate(c, b, stuck = "", v = 'X')
    values=Dict(s=>(s==stuck ? v : b[i]) for (i, s) in enumerate(c.inputs))
    for i in c.order
        g=c.gates[i]
        values[g.output]=g.output==stuck ? v : logic(g.kind, [values[s] for s in g.inputs])
    end
    join(values[s] for s in c.outputs)
end
function arrivals(c, period)
    late=Dict{String,Int}()
    early=Dict{String,Int}()
    prev=Dict{String,String}()
    if period
        for i in c.flops
            g=c.gates[i]
            late[g.output]=early[g.output]=g.delay
        end
    else
        for s in c.inputs
            late[s]=early[s]=0
        end
    end
    for i in c.order
        g=c.gates[i]
        a=[s for s in g.inputs if haskey(late, s)]
        isempty(a)&&continue
        best=a[1]
        for s in a
            late[s]>late[best]&&(best=s)
        end
        late[g.output]=late[best]+g.delay
        early[g.output]=minimum(early[s] for s in a)+g.delay
        prev[g.output]=best
    end
    late, early, prev
end
struct Event
    time::Int
    sequence::Int
    signal::String
    value::Char
end
before(a, b) = a.time<b.time||(a.time==b.time&&a.sequence<b.sequence)
mutable struct Simulation
    c::Circuit
    watch::Vector{String}
    values::Dict{String,Char}
    history::Dict{String,Vector{Tuple{Int,Char}}}
    queue::Vector{Event}
    time::Int
    sequence::Int
    processed::Int
    halted::Bool
end
function Simulation(c)
    Simulation(
        c,
        String[],
        Dict(s=>'X' for s in c.signals),
        Dict(s=>Tuple{Int,Char}[] for s in c.signals),
        Event[],
        0,
        0,
        0,
        false,
    )
end
function reset!(s)
    s.values=Dict(x=>'X' for x in s.c.signals)
    s.history=Dict(x=>Tuple{Int,Char}[] for x in s.c.signals)
    empty!(s.queue)
    s.time=0
    s.sequence=0
    s.processed=0
    s.halted=false
end
function schedule!(s, t, x, v)
    e=Event(t, s.sequence, x, v)
    s.sequence+=1
    push!(s.queue, e)
    i=length(s.queue)
    while i>1
        p=i÷2
        before(e, s.queue[p])||break
        s.queue[i]=s.queue[p]
        i=p
    end
    s.queue[i]=e
end
function popevent!(s)
    result=s.queue[1]
    last=pop!(s.queue)
    if !isempty(s.queue)
        i=1
        while 2*i<=length(s.queue)
            j=2*i
            j+1<=length(s.queue)&&before(s.queue[j+1], s.queue[j])&&(j+=1)
            before(s.queue[j], last)||break
            s.queue[i]=s.queue[j]
            i=j
        end
        s.queue[i]=last
    end
    result
end
describe(s, a) = ["$x=$(s.values[x])" for x in a]
function run!(s, ending)
    total=0
    glitches=0
    while !isempty(s.queue)&&s.queue[1].time<ending
        t=s.queue[1].time
        original=Dict{String,Char}()
        count=0
        while !isempty(s.queue)&&s.queue[1].time==t
            if count==1000
                println("halted: oscillation at time $t")
                empty!(s.queue)
                s.time=t
                s.halted=true
                return
            end
            e=popevent!(s)
            count+=1
            s.processed+=1
            old=s.values[e.signal]
            old==e.value&&continue
            get!(original, e.signal, old)
            s.values[e.signal]=e.value
            for i in s.c.readers[e.signal]
                g=s.c.gates[i]
                if g.kind!="DFF"
                    schedule!(
                        s,
                        t+g.delay,
                        g.output,
                        logic(g.kind, [s.values[x] for x in g.inputs]),
                    )
                elseif e.signal==g.inputs[1]&&old=='0'&&e.value=='1'
                    schedule!(s, t+g.delay, g.output, s.values[g.inputs[2]])
                end
            end
        end
        total+=count
        for (x, v) in original
            if s.values[x]==v
                glitches+=1
            else
                push!(s.history[x], (t, s.values[x]))
            end
        end
        for x in s.watch
            haskey(original, x)&&s.values[x]!=original[x]&&println("$t $x $(s.values[x])")
        end
    end
    s.time=ending
    println("run $ending events $total glitches $glitches pending $(length(s.queue))")
end
mutable struct Simulator
    modules::Dict{String,LogicModule}
    order::Vector{LogicModule}
    simulation::Union{Nothing,Simulation}
end
Simulator() = Simulator(Dict{String,LogicModule}(), LogicModule[], nothing)
lookup(s, name) = haskey(s.modules, name) ? s.modules[name] : fail("unknown module $name")
requiresignal(s, x) = haskey(s.simulation.values, x) ? nothing : fail("unknown signal $x")
requireinput(s, x) = x in s.simulation.c.inputs ? nothing : fail("not an input $x")
function parsetime(s, w)
    t=number(w)
    t>=s.simulation.time||fail("time $t is in the past")
    t
end
function define!(s, header, lines)
    line=header
    try
        w=String.(split(lines[1], ' '))
        (length(w)>=5&&w[3]=="IN"&&count(==("OUT"), w[4:end])==1&&w[end]!="OUT")||fail(
            "bad module header",
        )
        name=w[2]
        occursin(r"^[A-Z][A-Z0-9_]{0,15}$", name)||fail("bad module name $name")
        haskey(s.modules, name)&&fail("duplicate module $name")
        splitat=findfirst(==("OUT"), w[4:end])+3
        ins=w[4:(splitat-1)]
        outs=w[(splitat+1):end]
        seen=Set{String}()
        for p in vcat(ins, outs)
            nameok(p)||fail("bad name $p")
            p in seen&&fail("duplicate port $p")
            push!(seen, p)
        end
        driven=Set(ins)
        used=Set{String}()
        body=Item[]
        reads=Tuple{Int,String}[]
        gates=0
        for i in 2:length(lines)
            line=header+i-1
            a=String.(split(lines[i], ' '))
            kind=a[1]
            if kind in TYPES
                (length(a)>=5&&a[end-2]=="->"&&count(==("->"), a)==1)||fail("bad gate syntax")
                n=a[2]
                nameok(n)||fail("bad name $n")
                inputs=a[3:(end-3)]
                output, delay=a[end-1], a[end]
                lo=kind in ("NOT", "BUF") ? 1 : kind=="MUX2" ? 3 : 2
                hi=findfirst(==(kind), TYPES)<=6 ? 8 : lo
                lo<=length(inputs)<=hi||fail("bad input count $(length(inputs)) for $kind")
                for x in vcat(inputs, [output])
                    nameok(x)||fail("bad name $x")
                end
                (numberok(delay)&&parse(Int, delay)<=1000)||fail("bad delay $delay")
                n in used&&fail("duplicate name $n")
                output in driven&&fail("multiple drivers for $output")
                push!(used, n)
                push!(driven, output)
                push!(body, Gate(n, kind, inputs, output, parse(Int, delay)))
                gates+=1
                append!(reads, [(line, x) for x in inputs])
            elseif kind=="INST"
                length(a)>=3||fail("bad instance syntax")
                n=a[2]
                nameok(n)||fail("bad name $n")
                m=lookup(s, a[3])
                connections=Pair{String,String}[]
                ports=Set{String}()
                for word in a[4:end]
                    p=split(word, '='; keepempty = true)
                    (length(p)==2&&!isempty(p[1])&&!isempty(p[2]))||fail("bad connection $word")
                    port, x=String.(p)
                    (port in m.inputs||port in m.outputs)||fail("unknown port $port")
                    port in ports&&fail("duplicate connection $port")
                    nameok(x)||fail("bad name $x")
                    push!(ports, port)
                    push!(connections, port=>x)
                end
                for p in m.inputs
                    p in ports||fail("unconnected input $p")
                end
                n in used&&fail("duplicate name $n")
                for (p, x) in connections
                    if p in m.outputs
                        x in driven&&fail("multiple drivers for $x")
                        push!(driven, x)
                    end
                end
                push!(used, n)
                push!(body, Instance(n, m, connections))
                append!(reads, [(line, x) for (p, x) in connections if p in m.inputs])
            else
                fail("unknown statement $kind")
            end
        end
        append!(reads, [(header, x) for x in outs])
        for (n, x) in reads
            if !(x in driven)
                line=n
                fail("undriven signal $x")
            end
        end
        m=LogicModule(name, ins, outs, body)
        s.modules[name]=m
        push!(s.order, m)
        println(
            "defined $name inputs $(length(ins)) outputs $(length(outs)) gates $gates instances $(length(body)-gates)",
        )
    catch e
        e isa InputError||rethrow()
        println("error: line $line: $(e.reason)")
    end
end
function hierarchy(m, depth)
    for x in m.body
        if x isa Instance
            println("  "^depth, x.name, " ", x.child.name)
            hierarchy(x.child, depth+1)
        end
    end
end
function execute!(s, line, w)
    try
        cmd=w[1]
        a=w[2:end]
        haskey(COUNTS, cmd)||fail("unknown command $cmd")
        n=COUNTS[cmd]
        (length(a)>=n&&(cmd in ("WATCH", "UNWATCH", "SHOW")||length(a)==n))||fail(
            "wrong argument count",
        )
        cmd in SIM&&s.simulation===nothing&&fail("no circuit")
        sim=s.simulation
        cmd in ("SET", "APPLY", "PULSE", "CLOCK", "RUN")&&sim.halted&&fail("simulation halted")
        if cmd=="MODULES"
            println("modules ", length(s.order))
            for m in s.order
                println(
                    "$(m.name) inputs $(length(m.inputs)) outputs $(length(m.outputs)) gates $(length(circuit(m).gates))",
                )
            end
            return
        end
        if cmd in (
            "BUILD",
            "NETLIST",
            "HIERARCHY",
            "STATS",
            "TRUTHTABLE",
            "EQUIV",
            "FAULTS",
            "CRITICAL",
            "PERIOD",
        )
            m=lookup(s, a[1])
            m2=cmd=="EQUIV" ? lookup(s, a[2]) : nothing
            c=circuit(m)
            if cmd=="BUILD"
                s.simulation=Simulation(c)
                println("built $(c.name) signals $(length(c.signals)) gates $(length(c.gates))")
            elseif cmd=="NETLIST"
                println("netlist $(c.name) gates $(length(c.gates)) signals $(length(c.signals))")
                for g in c.gates
                    println("$(g.name) $(g.kind) $(join(g.inputs," ")) -> $(g.output) $(g.delay)")
                end
            elseif cmd=="HIERARCHY"
                println(c.name)
                hierarchy(m, 1)
            elseif cmd=="STATS"
                levels=Dict(x=>0 for x in c.signals)
                depth=0
                for i in c.order
                    g=c.gates[i]
                    levels[g.output]=maximum(levels[x] for x in g.inputs)+1
                    depth=max(depth, levels[g.output])
                end
                println(
                    "stats $(c.name) gates $(length(c.gates)) signals $(length(c.signals)) depth $(c.loop ? "-" : depth)",
                )
                row=["types"]
                for t in TYPES
                    n=count(g->g.kind==t, c.gates)
                    n>0&&append!(row, [t, string(n)])
                end
                println(join(row, " "))
                best=c.signals[1]
                for x in c.signals
                    length(c.readers[x])>length(c.readers[best])&&(best=x)
                end
                println("max fanout $best $(length(c.readers[best]))")
            elseif cmd in ("CRITICAL", "PERIOD")
                period=cmd=="PERIOD"
                period&&isempty(c.flops)&&fail("$(c.name) has no flip-flops")
                c.loop&&fail("$(c.name) has a combinational loop")
                late, early, prev=arrivals(c, period)
                ends=period ? [c.gates[i].inputs[2] for i in c.flops] : c.outputs
                heading=period ? "flip-flops $(length(c.flops)) period" : "critical"
                best=nothing
                for x in ends
                    !period&&println(
                        haskey(late, x) ? "$x min $(early[x]) max $(late[x])" : "$x unreachable",
                    )
                    haskey(late, x)&&(best===nothing||late[x]>late[best])&&(best=x)
                end
                if best===nothing
                    println(heading, " none")
                else
                    path=[best]
                    while haskey(prev, path[end])
                        push!(path, prev[path[end]])
                    end
                    println(heading, " ", late[best], ": ", join(reverse(path), " -> "))
                end
            else
                combinational(c)
                rows=[rowbits(r, length(c.inputs)) for r in 0:((1<<length(c.inputs))-1)]
                expected=[evaluate(c, b) for b in rows]
                if cmd=="TRUTHTABLE"
                    println(join(vcat(c.inputs, ["|"], c.outputs), " "))
                    for r in eachindex(rows)
                        println(
                            join(
                                vcat(
                                    string.(collect(rows[r])),
                                    ["|"],
                                    string.(collect(expected[r])),
                                ),
                                " ",
                            ),
                        )
                    end
                elseif cmd=="EQUIV"
                    d=circuit(m2)
                    combinational(d)
                    (length(c.inputs)==length(d.inputs)&&length(c.outputs)==length(d.outputs))||fail(
                        "port mismatch",
                    )
                    for r in eachindex(rows)
                        v=evaluate(d, rows[r])
                        if v!=expected[r]
                            println("not equivalent at $(rows[r]): $(expected[r]) vs $v")
                            return
                        end
                    end
                    println("equivalent")
                else
                    undetected=String[]
                    tests=Set{Int}()
                    for x in c.signals, v in "01"
                        found=findfirst(r->evaluate(c, rows[r], x, v)!=expected[r], eachindex(rows))
                        found===nothing ? push!(undetected, "$x/$v") : push!(tests, found)
                    end
                    total=2*length(c.signals)
                    println("faults $total detected $(total-length(undetected))")
                    for f in undetected
                        println("undetected $f")
                    end
                    println(join(vcat(["tests"], rows[sort(collect(tests))]), " "))
                end
            end
            return
        end
        if cmd=="RESET"
            reset!(sim)
            println("reset")
        elseif cmd=="SET"
            t=parsetime(s, a[1])
            requireinput(s, a[2])
            v=parsevalue(a[3])
            schedule!(sim, t, a[2], v)
            println("set $(a[2]) $v at $t")
        elseif cmd=="APPLY"
            t=parsetime(s, a[1])
            b=a[2]
            (length(b)==length(sim.c.inputs)&&all(x->x in "01X", b))||fail("bad vector $b")
            for (i, x) in enumerate(sim.c.inputs)
                schedule!(sim, t, x, b[i])
            end
            println("apply $b at $t")
        elseif cmd in ("PULSE", "CLOCK")
            requireinput(s, a[1])
            t=parsetime(s, a[2])
            width=number(a[3], true)
            if cmd=="PULSE"
                schedule!(sim, t, a[1], '1')
                schedule!(sim, t+width, a[1], '0')
                println("pulse $(a[1]) $t $(t+width)")
            else
                eventcount=number(a[4], true)
                for i in 0:(eventcount-1)
                    schedule!(sim, t+i*width, a[1], iseven(i) ? '0' : '1')
                end
                println("clock $(a[1]) events $eventcount last $(t+(eventcount-1)*width)")
            end
        elseif cmd=="RUN"
            t=number(a[1])
            t>sim.time||fail("time $t is not after $(sim.time)")
            run!(sim, t)
        elseif cmd in ("WATCH", "UNWATCH")
            seen=Set{String}()
            for x in a
                requiresignal(s, x)
                watched=x in sim.watch
                (cmd=="WATCH" ? watched||x in seen : !watched||x in seen)&&fail(
                    (cmd=="WATCH" ? "already watched " : "not watched ")*x,
                )
                push!(seen, x)
            end
            if cmd=="WATCH"
                append!(sim.watch, a)
            else
                filter!(x->!(x in seen), sim.watch)
            end
            println("watching ", isempty(sim.watch) ? "nothing" : join(sim.watch, " "))
        elseif cmd=="SHOW"
            for x in a
                requiresignal(s, x)
            end
            println(
                join(
                    isempty(a) ?
                    vcat(describe(sim, sim.c.inputs), ["|"], describe(sim, sim.c.outputs)) :
                    describe(sim, a),
                    " ",
                ),
            )
        elseif cmd=="CHECK"
            requiresignal(s, a[1])
            v=parsevalue(a[2])
            println(
                "check $(a[1])=$v ",
                sim.values[a[1]]==v ? "ok" : "failed ($(sim.values[a[1]]))",
            )
        elseif cmd=="PROBE"
            x=a[1]
            requiresignal(s, x)
            text="input"
            if haskey(sim.c.driver, x)
                g=sim.c.gates[sim.c.driver[x]]
                text="$(g.name) $(g.kind) $(join(describe(sim,g.inputs)," ")) delay $(g.delay)"
            end
            println("$x=$(sim.values[x]) driven by $text")
            readers=sim.c.readers[x]
            println(
                join(
                    vcat(
                        ["fanout", string(length(readers))],
                        [sim.c.gates[i].name for i in readers],
                    ),
                    " ",
                ),
            )
        elseif cmd=="WAVE"
            first, last=number(a[1]), number(a[2])
            first<last<=sim.time||fail("bad range $first $last")
            isempty(sim.watch)&&fail("nothing watched")
            for x in sim.watch
                h=sim.history[x]
                i=1
                v='X'
                wave=IOBuffer()
                for t in first:(last-1)
                    while i<=length(h)&&h[i][1]<=t
                        v=h[i][2]
                        i+=1
                    end
                    print(wave, v)
                end
                println(x, " ", String(take!(wave)))
            end
        elseif cmd=="HISTORY"
            x=a[1]
            requiresignal(s, x)
            h=sim.history[x]
            println(
                join(
                    vcat(["history", x, "changes", string(length(h))], ["$t:$v" for (t, v) in h]),
                    " ",
                ),
            )
        elseif cmd=="ACTIVITY"
            k=number(a[1], true)
            ranked=sort(copy(sim.c.signals); by = x->(-length(sim.history[x]), x))
            for x in ranked[1:min(k, length(ranked))]
                println(x, " ", length(sim.history[x]))
            end
        elseif cmd=="STATUS"
            println(
                "circuit $(sim.c.name) time $(sim.time) pending $(length(sim.queue)) events $(sim.processed) halted $(sim.halted ? "yes" : "no")",
            )
            println(
                "values 0:$(count(==('0'),values(sim.values))) 1:$(count(==('1'),values(sim.values))) X:$(count(==('X'),values(sim.values)))",
            )
        end
    catch e
        e isa InputError||rethrow()
        println("error: line $line: $(e.reason)")
    end
end
function main()
    lines=readlines()
    s=Simulator()
    i=1
    while i<=length(lines)&&lines[i]!="END"
        w=String.(split(lines[i], ' '))
        if w[1]=="MODULE"
            last=i+1
            while lines[last]!="ENDMODULE"
                last+=1
            end
            define!(s, i, lines[i:(last-1)])
            i=last+1
        else
            execute!(s, i, w)
            i+=1
        end
    end
end
main()
