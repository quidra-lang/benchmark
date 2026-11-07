include("report.jl")
include("eventlog.jl")
include("dfg.jl")
include("alpha_miner.jl")
include("heuristic_miner.jl")
include("conformance.jl")

words(parts...) = join(string.(parts)," ")
mean_fraction(values) = sum(values)//length(values)
function prepare_study()
    rows,raw_params = read_inputs()
    params = Dict{String,Any}()
    for (name,value) in raw_params
        params[name] = occursin('/',value) ? (v=parse.(Int,split(value,'/'));v[1]//v[2]) : parse(Int,value)
    end
    events,errors,adopted = NamedTuple[],String[],Set{Tuple{String,String,String}}()
    for row in rows
        t = timestamp_minutes(row.timestamp)
        if isnothing(t)
            push!(errors,"line $(row.line): bad timestamp $(row.timestamp)")
        elseif (row.case_id,row.activity,row.timestamp) in adopted
            push!(errors,"line $(row.line): duplicate event $(row.case_id) $(row.activity) $(row.timestamp)")
        else
            push!(adopted,(row.case_id,row.activity,row.timestamp))
            push!(events,(;row...,time=t))
        end
    end
    cases = group_cases(events)
    log = [(case.trace,1) for case in cases]
    (
        rows=rows,
        params=params,
        events=events,
        errors=errors,
        cases=cases,
        activities=sort!(unique([e.activity for e in events])),
        resources=sort!(unique([e.resource for e in events])),
        log=log,
        counts=directly_follows(log),
        reference=read_model()
    )
end
function build_variants(s)
    grouped = Dict{Tuple,Vector{NamedTuple}}()
    for case in s.cases
        push!(get!(grouped,case.trace,NamedTuple[]),case)
    end
    traces = sort!(collect(keys(grouped));by=trace->(-length(grouped[trace]),trace))
    variants,variant_by_case,filtered_log = NamedTuple[],Dict{String,Int}(),Tuple{Tuple,Int}[]
    for (number,trace) in enumerate(traces)
        cases = grouped[trace]
        keep = all(
            i->count_at(s.counts,trace[i],trace[i+1])>=s.params["filter_min_follows"],
            1:length(trace)-1
        )
        push!(variants,(number=number,trace=trace,cases=cases,keep=keep))
        for case in cases
            variant_by_case[case.identifier] = number
        end
        keep && push!(filtered_log,(trace,length(cases)))
    end
    (
        ;s...,
        variants=variants,
        variant_by_case=variant_by_case,
        filtered_log=filtered_log,
        kept_cases=sum(entry[2] for entry in filtered_log),
        kept_events=sum(length(entry[1])*entry[2] for entry in filtered_log)
    )
end
function discover(log,activities,relation)
    candidates,pending,causal = Set{Tuple}(),Tuple[],0
    for a in activities,b in activities
        relation(a,b)=="->" || continue
        causal += 1
        if relation(a,a)=="#" && relation(b,b)=="#"
            pair = ((a,),(b,))
            push!(candidates,pair)
            push!(pending,pair)
        end
    end
    cursor = 1
    while cursor<=length(pending)
        pair = pending[cursor]
        cursor += 1
        for a in activities,side in 1:2
            extended = extend_pair(pair,a,side,relation)
            if !isnothing(extended) && !(extended in candidates)
                push!(candidates,extended)
                push!(pending,extended)
            end
        end
    end
    maximal = [pair for pair in candidates if !any(!isnothing(extend_pair(
        pair,
        a,
        side,
        relation
    )) for a in activities for side in 1:2)]
    sort!(maximal;by=pair_order)
    starts,ends = sort!(unique([trace[1] for (trace,_) in log])),sort!(unique([trace[end] for (
        trace,
        _
    ) in log]))
    places = ["start";["p$i" for i in eachindex(maximal)];"end"]
    arcs = [("start",a) for a in starts]
    append!(arcs,[(a,"end") for a in ends])
    for (i,(first,second)) in enumerate(maximal)
        append!(arcs,[(a,"p$i") for a in first])
        append!(arcs,[("p$i",a) for a in second])
    end
    (
        net=PetriNet(places,activities,arcs,"start","end"),
        pairs=maximal,
        candidates=length(candidates),
        causal=causal,
        starts=starts,
        ends=ends,
        activities=activities
    )
end
pair_line(d) = words("PAIRS causal",d.causal,"candidates",d.candidates,"maximal",length(d.pairs))
function net_lines(d)
    net = d.net
    lines = [words("PLACE start -",name_list(d.starts))]
    for (i,(first,second)) in enumerate(d.pairs)
        push!(lines,words("PLACE p$i",name_list(first),name_list(second)))
    end
    push!(lines,words("PLACE end",name_list(d.ends),"-"))
    for t in net.transitions
        push!(
            lines,
            words(
                "TRANSITION",
                t,
                "in",
                name_list(net.places[net.inputs[t]]),
                "out",
                name_list(net.places[net.outputs[t]])
            )
        )
    end
    push!(
        lines,
        words("NET places",length(net.places),"transitions",length(net.transitions),"arcs",length(net.arcs))
    )
    lines
end
function mine_workflows(s)
    counts = directly_follows(s.filtered_log)
    activities = sort!(unique([a for (trace,_) in s.filtered_log for a in trace]))
    loops = filter(a->count_at(counts,a,a)>=1,activities)
    basic(a,b) = basic_relation(counts,a,b)
    alpha = discover(s.filtered_log,activities,basic)
    lines = [
        words("LOG variants",length(s.filtered_log),"cases",s.kept_cases,"activities",name_list(activities)),
        "LOOPS "*name_list(loops),
        "MINER alpha"
    ]
    append!(lines,footprint(activities,basic))
    push!(lines,pair_line(alpha))
    append!(lines,net_lines(alpha))
    reduced = [(Tuple(a for a in trace if !(a in loops)),weight) for (trace,weight) in s.filtered_log]
    retained = setdiff(activities,loops)
    reduced_counts,triangles = directly_follows(reduced),triangle_counts(reduced)
    relation(a,b) = plus_relation(reduced_counts,triangles,a,b)
    plus = discover(reduced,retained,relation)
    push!(lines,"MINER alpha_plus")
    for (a,b) in sort!(collect(keys(triangles)))
        push!(lines,words("TRIANGLE",a,b,"count",triangles[(a,b)]))
    end
    append!(lines,footprint(retained,relation))
    push!(lines,pair_line(plus))
    arcs = copy(plus.net.arcs)
    for a in loops
        before = Tuple(filter(b->count_at(counts,b,a)>=1,retained))
        after = Tuple(filter(b->count_at(counts,a,b)>=1,retained))
        number = findfirst(==((before,after)),plus.pairs)
        place = isnothing(number) ? "-" : "p$number"
        if !isnothing(number)
            push!(arcs,(place,a))
            push!(arcs,(a,place))
        end
        push!(lines,words("LOOP",a,"before",name_list(before),"after",name_list(after),"place",place))
    end
    plus = (;plus...,net=PetriNet(plus.net.places,activities,arcs,"start","end"))
    append!(lines,net_lines(plus))
    lines,(("reference",s.reference),("alpha",alpha.net),("alpha_plus",plus.net))
end
function heuristic_report(s)
    counts,triangles,minimum_count = s.counts,triangle_counts(s.log),s.params["positive_observations"]
    loops1,loops2,lines = Set{String}(),Set{Tuple{String,String}}(),String[]
    for a in s.activities
        n = count_at(counts,a,a)
        n==0 && continue
        measure = loop_measure(n)
        accepted = n>=minimum_count && measure>=s.params["loop1_threshold"]
        accepted && push!(loops1,a)
        push!(lines,words("L1",a,"count",n,"measure",fraction(measure),accepted ? "ACCEPT" : "REJECT"))
    end
    for i in 1:length(s.activities)-1,j in i+1:length(s.activities)
        a,b = s.activities[i],s.activities[j]
        n = count_at(triangles,a,b)+count_at(triangles,b,a)
        (a in loops1 || b in loops1 || n==0) && continue
        measure = loop_measure(n)
        accepted = n>=minimum_count && measure>=s.params["loop2_threshold"]
        accepted && push!(loops2,(a,b))
        push!(lines,words("L2",a,b,"count",n,"measure",fraction(measure),accepted ? "ACCEPT" : "REJECT"))
    end
    measures = Dict(pair=>dependency(counts,pair...) for pair in keys(counts) if pair[1]!=pair[2])
    best_out,best_in = Dict{String,Rational{Int}}(),Dict{String,Rational{Int}}()
    for ((a,b),measure) in measures
        best_out[a] = haskey(best_out,a) ? max(best_out[a],measure) : measure
        best_in[b] = haskey(best_in,b) ? max(best_in[b],measure) : measure
    end
    edges = Set((a,a) for a in loops1)
    relative = s.params["relative_to_best"]
    for (a,b) in sort!(collect(keys(measures)))
        measure = measures[(a,b)]
        if minmax(a,b) in loops2
            verdict = "LOOP2"
        elseif count_at(counts,a,b)<minimum_count
            verdict = "REJECT_COUNT"
        elseif measure<s.params["dependency_threshold"]
            verdict = "REJECT_MEASURE"
        elseif best_out[a]-measure>relative && best_in[b]-measure>relative
            verdict = "REJECT_BEST"
        else
            verdict = "ACCEPT"
        end
        verdict in ("LOOP2","ACCEPT") && push!(edges,(a,b))
        push!(
            lines,
            words(
                "DEP",
                a,
                b,
                "count",
                count_at(counts,a,b),
                "reverse",
                count_at(counts,b,a),
                "measure",
                fraction(measure),
                verdict
            )
        )
    end
    inputs = Dict(a=>sort!([x for (x,y) in edges if y==a]) for a in s.activities)
    outputs = Dict(a=>sort!([y for (x,y) in edges if x==a]) for a in s.activities)
    for a in s.activities
        push!(lines,words("NODE",a,"in",name_list(inputs[a]),"out",name_list(outputs[a])))
    end
    for a in s.activities,(kind,neighbors) in (
        ("SPLIT",filter(!=(a),outputs[a])),
        ("JOIN",filter(!=(a),inputs[a]))
    )
        for i in 1:length(neighbors)-1,j in i+1:length(neighbors)
            b,c = neighbors[i],neighbors[j]
            measure = kind=="SPLIT" ? split_measure(counts,a,b,c) : join_measure(counts,a,b,c)
            push!(
                lines,
                words(
                    kind,
                    a,
                    b,
                    c,
                    "measure",
                    fraction(measure),
                    measure>=s.params["and_threshold"] ? "AND" : "XOR"
                )
            )
        end
    end
    push!(
        lines,
        words(
            "GRAPH activities",
            length(s.activities),
            "edges",
            length(edges),
            "loops1",
            length(loops1),
            "loops2",
            length(loops2)
        )
    )
    lines
end
function explore(net)
    markings,pending,edges = Set([net.initial_marking]),[net.initial_marking],Tuple[]
    reverse,enabled_at,ever = Dict{Tuple,Set{Tuple}}(),Dict{Tuple,Vector{String}}(),Set{String}()
    unsafe,deadlocks,cursor = 0,0,1
    while cursor<=length(pending)
        marking = pending[cursor]
        cursor += 1
        transitions = enabled_transitions(net,marking)
        enabled_at[marking] = transitions
        union!(ever,transitions)
        isempty(transitions) && marking!=net.final_marking && (deadlocks+=1)
        for t in transitions
            after = fire(net,marking,t)
            if any(>(1),after)
                unsafe += 1
                continue
            end
            push!(edges,(marking,t,after))
            push!(get!(reverse,after,Set{Tuple}()),marking)
            if !(after in markings)
                push!(markings,after)
                push!(pending,after)
            end
        end
    end
    reachable = Set{Tuple}()
    pending = Tuple[]
    if net.final_marking in markings
        push!(reachable,net.final_marking)
        push!(pending,net.final_marking)
    end
    cursor = 1
    while cursor<=length(pending)
        marking = pending[cursor]
        cursor += 1
        for before in get(reverse,marking,Set{Tuple}())
            if !(before in reachable)
                push!(reachable,before)
                push!(pending,before)
            end
        end
    end
    dead,stuck = setdiff(net.transitions,collect(ever)),length(markings)-length(reachable)
    follows = Dict{Tuple{String,String},Int}()
    for (_,t,after) in edges,u in enabled_at[after]
        follows[(t,u)] = 1
    end
    (
        markings=length(markings),
        edges=length(edges),
        unsafe=unsafe,
        deadlocks=deadlocks,
        stuck=stuck,
        final=net.final_marking in markings,
        dead=dead,
        sound=unsafe==0 && stuck==0 && isempty(dead),
        follows=follows
    )
end
function build_prefixes(cases)
    prefixes = Dict{Tuple,NamedTuple}()
    for case in cases,n in 0:length(case.trace)
        prefix = case.trace[1:n]
        entry = get(prefixes,prefix,(weight=0,followers=Set{String}()))
        n<length(case.trace) && push!(entry.followers,case.trace[n+1])
        prefixes[prefix] = (weight=entry.weight+1,followers=entry.followers)
    end
    prefixes
end
function precision_report(name,net,prefixes)
    fitting,allowed,escaping,weights = 0,0,0,Dict{String,Int}()
    for (prefix,entry) in prefixes
        marking = net.initial_marking
        fits = true
        for t in prefix
            if !haskey(net.inputs,t) || !enabled(net,marking,t)
                fits = false
                break
            end
            marking = fire(net,marking,t)
        end
        fits || continue
        fitting += 1
        transitions = enabled_transitions(net,marking)
        escapes = setdiff(transitions,collect(entry.followers))
        allowed += entry.weight*length(transitions)
        escaping += entry.weight*length(escapes)
        for t in escapes
            weights[t] = get(weights,t,0)+entry.weight
        end
    end
    lines = [words(
        "PRECISION",
        name,
        "prefixes",
        fitting,
        "allowed",
        allowed,
        "escaping",
        escaping,
        "precision",
        fraction(allowed==0 ? 1//1 : (allowed-escaping)//allowed)
    )]
    for t in sort!(collect(keys(weights));by=t->(-weights[t],t))
        push!(lines,words("ESCAPE",name,t,"weight",weights[t]))
    end
    lines
end
function replay_case(net,case)
    r = ReplayTotals(length(net.places))
    tokens = [Int[] for _ in net.places]
    push!(tokens[net.initial],case.events[1].time)
    r.produced = 1
    for event in case.events
        t = event.activity
        if !haskey(net.inputs,t)
            r.skipped += 1
            continue
        end
        for p in net.inputs[t]
            r.consumed += 1
            if !isempty(tokens[p])
                push!(r.waiting[p],event.time-popfirst!(tokens[p]))
                r.routes[p][t] = get(r.routes[p],t,0)+1
            else
                r.missing += 1
                r.place_missing[p] += 1
            end
        end
        for p in net.outputs[t]
            push!(tokens[p],event.time)
            r.produced += 1
        end
    end
    r.consumed += 1
    if !isempty(tokens[net.final])
        popfirst!(tokens[net.final])
    else
        r.missing += 1
        r.place_missing[net.final] += 1
    end
    for p in eachindex(tokens)
        r.place_remaining[p] = length(tokens[p])
        r.remaining += length(tokens[p])
        r.deviating[p] = Int(r.place_missing[p]>0 || !isempty(tokens[p]))
    end
    r
end
function aggregate_replays(net,cases)
    total,results,fitting = ReplayTotals(length(net.places)),Dict{String,ReplayTotals}(),0
    for case in cases
        r = replay_case(net,case)
        results[case.identifier] = r
        fitting += r.missing==0 && r.remaining==0
        for field in (:missing,:remaining,:consumed,:produced,:skipped)
            setproperty!(total,field,getproperty(total,field)+getproperty(r,field))
        end
        for p in eachindex(net.places)
            total.place_missing[p] += r.place_missing[p]
            total.place_remaining[p] += r.place_remaining[p]
            total.deviating[p] += r.deviating[p]
            append!(total.waiting[p],r.waiting[p])
            for (t,n) in r.routes[p]
                total.routes[p][t] = get(total.routes[p],t,0)+n
            end
        end
    end
    total,results,fitting
end
function conformance_report(s,nets)
    lines = [words(
        "MODEL places",
        length(s.reference.places),
        "transitions",
        length(s.reference.transitions),
        "arcs",
        length(s.reference.arcs)
    )]
    explorations = Dict{String,NamedTuple}()
    for (name,net) in nets
        r = explore(net)
        explorations[name] = r
        push!(
            lines,
            words(
                "REACHABILITY",
                name,
                "markings",
                r.markings,
                "edges",
                r.edges,
                "unsafe",
                r.unsafe,
                "deadlocks",
                r.deadlocks,
                "stuck",
                r.stuck,
                "final",
                r.final ? "yes" : "no",
                "dead",
                name_list(r.dead),
                "sound",
                r.sound ? "yes" : "no"
            )
        )
    end
    for (name,net) in nets
        activities = sort!(union(s.activities,net.transitions))
        follows,differences = explorations[name].follows,Tuple{String,String,String,String}[]
        for a in activities,b in activities
            log,model = basic_relation(s.counts,a,b),basic_relation(follows,a,b)
            log!=model && push!(differences,(a,b,log,model))
        end
        cells = length(activities)*length(activities)
        push!(
            lines,
            words(
                "FOOTPRINT",
                name,
                "activities",
                length(activities),
                "cells",
                cells,
                "differing",
                length(differences),
                "fitness",
                fraction((cells-length(differences))//cells)
            )
        )
        if name=="reference"
            for (a,b,log,model) in differences
                a<=b && push!(lines,words("DIFF",a,b,"log",log,"model",model))
            end
        end
    end
    prefixes = build_prefixes(s.cases)
    for (name,net) in nets
        append!(lines,precision_report(name,net,prefixes))
    end
    reference_replays = Dict{String,ReplayTotals}()
    for (name,net) in nets
        total,results,fitting = aggregate_replays(net,s.cases)
        name=="reference" && (reference_replays=results)
        push!(
            lines,
            words(
                "REPLAY",
                name,
                "cases",
                length(s.cases),
                "fitting",
                fitting,
                "skipped",
                total.skipped,
                "missing",
                total.missing,
                "remaining",
                total.remaining,
                "consumed",
                total.consumed,
                "produced",
                total.produced,
                "fitness",
                fraction(fitness(total))
            )
        )
        for (p,place) in enumerate(net.places)
            waiting = total.waiting[p]
            mean,largest = isempty(waiting) ? ("-","-") : (
                fraction(mean_fraction(waiting)),
                string(maximum(waiting))
            )
            push!(
                lines,
                words(
                    "PLACE",
                    name,
                    place,
                    "missing",
                    total.place_missing[p],
                    "remaining",
                    total.place_remaining[p],
                    "deviating",
                    total.deviating[p],
                    "tokens",
                    length(waiting),
                    "mean",
                    mean,
                    "max",
                    largest
                )
            )
        end
        for (p,place) in enumerate(net.places)
            length(net.routes[p])<2 && continue
            consumptions = join(("$t=$(get(total.routes[p],t,0))" for t in net.routes[p]),",")
            push!(lines,words("ROUTE",name,place,consumptions))
        end
    end
    lines,reference_replays
end
function log_summary(s)
    lines = ["ERROR "*error for error in s.errors]
    earliest,latest = argmin(e->e.time,s.events),argmax(e->e.time,s.events)
    push!(
        lines,
        words(
            "LOG rows",
            length(s.rows),
            "adopted",
            length(s.events),
            "rejected",
            length(s.errors),
            "cases",
            length(s.cases),
            "activities",
            length(s.activities),
            "resources",
            length(s.resources),
            "first",
            earliest.timestamp,
            "last",
            latest.timestamp
        )
    )
    for a in s.activities
        events = filter(e->e.activity==a,s.events)
        waits = [case.events[i].time-case.events[i-1].time for case in s.cases for i in 2:length(case.events) if case.events[i].activity==a]
        push!(
            lines,
            words(
                "ACTIVITY",
                a,
                "events",
                length(events),
                "cases",
                count(c->a in c.trace,s.cases),
                "start",
                count(c->c.trace[1]==a,s.cases),
                "end",
                count(c->c.trace[end]==a,s.cases),
                "rework",
                count(c->count(==(a),c.trace)>=2,s.cases),
                "wait",
                isempty(waits) ? "-" : fraction(mean_fraction(waits)),
                "resources",
                length(unique([e.resource for e in events])),
                "model",
                haskey(s.reference.inputs,a) ? "yes" : "no"
            )
        )
    end
    lengths,durations = [length(c.events) for c in s.cases],[c.duration for c in s.cases]
    for (label,values) in (("LENGTH",lengths),("DURATION",durations))
        push!(
            lines,
            words(
                label,
                "min",
                minimum(values),
                "max",
                maximum(values),
                "mean",
                fraction(mean_fraction(values)),
                "median",
                fraction(integer_median(values))
            )
        )
    end
    days = durations.÷1440
    for day in 0:maximum(days)
        n = count(==(day),days)
        push!(lines,words("DAYS",day,"cases",n,"share",percentage(n,length(s.cases))))
    end
    late = count(>(s.params["sla_minutes"]),durations)
    push!(
        lines,
        words("SLA limit",s.params["sla_minutes"],"late",late,"share",percentage(late,length(s.cases)))
    )
    for (i,name) in enumerate(("Mon","Tue","Wed","Thu","Fri","Sat","Sun"))
        weekday(t) = (t÷1440+3)%7
        push!(
            lines,
            words(
                "WEEKDAY",
                name,
                "events",
                count(e->weekday(e.time)==i-1,s.events),
                "starts",
                count(c->weekday(c.events[1].time)==i-1,s.cases),
                "ends",
                count(c->weekday(c.events[end].time)==i-1,s.cases)
            )
        )
    end
    lines
end
function variant_report(s,replays)
    lines = String[]
    for v in s.variants
        durations = [c.duration for c in v.cases]
        push!(
            lines,
            words(
                "VARIANT",
                v.number,
                "count",
                length(v.cases),
                "share",
                percentage(length(v.cases),length(s.cases)),
                "length",
                length(v.trace),
                "first",
                v.cases[1].identifier,
                "duration",
                fraction(mean_fraction(durations)),
                "late",
                count(>(s.params["sla_minutes"]),durations),
                "fitness",
                fraction(fitness(replays[v.cases[1].identifier])),
                v.keep ? "KEEP" : "DROP",
                name_list(v.trace)
            )
        )
    end
    push!(
        lines,
        words(
            "FILTER min_follows",
            s.params["filter_min_follows"],
            "variants",
            length(s.filtered_log),
            "of",
            length(s.variants),
            "cases",
            s.kept_cases,
            "of",
            length(s.cases),
            "events",
            s.kept_events,
            "of",
            length(s.events)
        )
    )
    lines
end
function dfg_report(s)
    starts = Dict(a=>count(c->c.trace[1]==a,s.cases) for a in s.activities)
    ends = Dict(a=>[c.duration for c in s.cases if c.trace[end]==a] for a in s.activities)
    lines = [words("START",a,"count",starts[a]) for a in sort!(filter(
        a->starts[a]>0,
        s.activities
    );by=a->(-starts[a],a))]
    for a in sort!(filter(a->!isempty(ends[a]),s.activities);by=a->(-length(ends[a]),a))
        push!(lines,words("END",a,"count",length(ends[a]),"duration",fraction(mean_fraction(ends[a]))))
    end
    for (a,b) in sort!(collect(keys(s.counts));by=pair->(-s.counts[pair],pair))
        waiting = [case.events[i+1].time-case.events[i].time for case in s.cases for i in 1:length(case.events)-1 if case.trace[i]==a && case.trace[i+1]==b]
        cases = count(c->any(i->c.trace[i]==a && c.trace[i+1]==b,1:length(c.trace)-1),s.cases)
        push!(
            lines,
            words(
                "EDGE",
                a,
                b,
                "count",
                s.counts[(a,b)],
                "cases",
                cases,
                "mean",
                fraction(mean_fraction(waiting)),
                "min",
                minimum(waiting),
                "max",
                maximum(waiting)
            )
        )
    end
    append!(lines,footprint(s.activities,(a,b)->basic_relation(s.counts,a,b)))
    lines
end
function resource_report(s)
    handovers,handover_cases,subcontract,together = [Dict{Tuple{String,String},Int}() for _ in 1:4]
    for case in s.cases
        workers = [e.resource for e in case.events]
        present = sort!(unique(workers))
        pairs = [(workers[i],workers[i+1]) for i in 1:length(workers)-1]
        for pair in pairs
            handovers[pair] = get(handovers,pair,0)+1
        end
        for pair in unique(pairs)
            handover_cases[pair] = get(handover_cases,pair,0)+1
        end
        for i in 1:length(workers)-2
            a,b,c = workers[i:i+2]
            a==c && a!=b && (subcontract[(a,b)]=get(subcontract,(a,b),0)+1)
        end
        for i in 1:length(present)-1,j in i+1:length(present)
            pair = (present[i],present[j])
            together[pair] = get(together,pair,0)+1
        end
    end
    lines = String[]
    for (number,resource) in enumerate(s.resources)
        events = filter(e->e.resource==resource,s.events)
        work = join(
            ("$a=$(count(e->e.activity==a,events))" for a in sort!(unique([e.activity for e in events]))),
            ","
        )
        cases = count(c->any(e->e.resource==resource,c.events),s.cases)
        push!(lines,words("RESOURCE",number,resource,"events",length(events),"cases",cases,"work",work))
    end
    for (a,b) in sort!(collect(keys(handovers));by=p->(-handovers[p],p))
        a==b && continue
        push!(lines,words("HANDOVER",a,b,"count",handovers[(a,b)],"cases",handover_cases[(a,b)]))
    end
    append!(lines,table_lines([[get(handovers,(a,b),0) for b in s.resources] for a in s.resources],5))
    for (a,b) in sort!(collect(keys(subcontract));by=p->(-subcontract[p],p))
        push!(lines,words("SUBCONTRACT",a,b,"count",subcontract[(a,b)]))
    end
    for (a,b) in sort!(collect(keys(together));by=p->(-together[p],p))
        push!(lines,words("TOGETHER",a,b,"cases",together[(a,b)]))
    end
    total = sum(values(handovers))
    own = sum((n for ((a,b),n) in handovers if a==b);init=0)
    push!(lines,words("TOTAL handovers",total,"self",own,"other",total-own))
    lines
end
function main()
    s = build_variants(prepare_study())
    workflows,nets = mine_workflows(s)
    conformance,replays = conformance_report(s,nets)
    csv = ["case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness"]
    for case in s.cases
        r = replays[case.identifier]
        push!(
            csv,
            join(
                (
                    case.identifier,
                    s.variant_by_case[case.identifier],
                    length(case.events),
                    r.skipped,
                    r.missing,
                    r.remaining,
                    r.consumed,
                    r.produced,
                    fraction(fitness(r))
                ),
                ","
            )
        )
    end
    write_outputs([
        "log_summary.txt"=>log_summary(s),
        "variants.txt"=>variant_report(s,replays),
        "dfg.txt"=>dfg_report(s),
        "alpha_net.txt"=>workflows,
        "heuristic_net.txt"=>heuristic_report(s),
        "conformance.csv"=>csv,
        "conformance.txt"=>conformance,
        "resources.txt"=>resource_report(s)
    ])
end
main()
