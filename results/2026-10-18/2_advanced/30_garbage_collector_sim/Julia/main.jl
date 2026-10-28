include("heap.jl")
include("mutator.jl")
include("mark_sweep.jl")
include("copying.jl")
include("generational.jl")

const SUMMARY_HEADER = "collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,total_work,p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation"
function reachable_numbers(roots,objects)
    reached = Set{Int}()
    stack = filter(!=(0),roots)
    while !isempty(stack)
        id = pop!(stack)
        id in reached && continue
        push!(reached,id)
        append!(stack,filter(!=(0),objects[id].fields))
    end
    reached
end
function state_error(command,roots,objects,labels)
    name,depth = command.name,length(roots)
    name in ("ALLOC","PUSH","LOAD") && depth == 64 && return "stack"
    name in ("LOAD","SET","OVERWRITE") && command.slot >= depth && return "stack"
    name in ("PUSH","SET","OVERWRITE") && command.source >= depth && return "stack"
    name == "POP" && command.count > depth && return "stack"
    if name in ("LOAD","SET")
        target = roots[command.slot+1]
        target == 0 && return "null"
        command.field >= length(objects[target].fields) && return "field"
    end
    name == "CHECKPOINT" && command.label in labels && return "duplicate"
    nothing
end
source_value(roots,source) = source == -1 ? 0 : roots[source+1]
function plain_command!(command,roots,objects)
    name = command.name
    if name == "PUSH"
        push!(roots,source_value(roots,command.source))
    elseif name == "LOAD"
        push!(roots,objects[roots[command.slot+1]].fields[command.field+1])
    elseif name == "POP"
        resize!(roots,length(roots)-command.count)
    elseif name == "SET"
        objects[roots[command.slot+1]].fields[command.field+1] = source_value(roots,command.source)
    elseif name == "OVERWRITE"
        roots[command.slot+1] = source_value(roots,command.source)
    end
end
function analyze_script(parsed)
    commands,errors,checkpoints = NamedTuple[],Tuple{Int,String}[],NamedTuple[]
    counts = Dict(name=>0 for name in COMMAND_NAMES)
    roots,objects = Int[],HeapObject[]
    births,deaths,lifetimes = Int[],Int[],Int[]
    clock,phase_start,peak_line = 0,0,0
    labels,alive = Set{String}(),Set{Int}()
    live,peak = ObjectPair(),ObjectPair()
    for (line,(command,reason)) in enumerate(parsed)
        isnothing(reason) && (reason=state_error(command,roots,objects,labels))
        if !isnothing(reason)
            push!(errors,(line,reason))
            continue
        end
        push!(commands,command)
        counts[command.name] += 1
        if command.name == "ALLOC"
            obj = HeapObject(length(objects)+1,command.pointers,command.data)
            push!(objects,obj)
            push!(births,clock)
            push!(deaths,0)
            push!(lifetimes,-1)
            clock += obj.size
            push!(roots,obj.number)
        else
            plain_command!(command,roots,objects)
        end
        reachable = reachable_numbers(roots,objects)
        for id in setdiff(alive,reachable)
            deaths[id] = command.line
            lifetimes[id] = clock-births[id]-objects[id].size
        end
        alive = reachable
        live = pair_of(objects[collect(alive)])
        if peak_line == 0 || live.words > peak.words
            peak,peak_line = live,command.line
        end
        if command.name == "CHECKPOINT"
            push!(labels,command.label)
            phase_objects = objects[(phase_start+1):end]
            survivors = filter(obj->obj.number in reachable,phase_objects)
            push!(
                checkpoints,
                (
                    label=command.label,
                    line=command.line,
                    stack=length(roots),
                    live=live,
                    allocated=pair_of(objects),
                    phase=pair_of(phase_objects),
                    survivors=pair_of(survivors),
                    reachable=copy(reachable)
                )
            )
            phase_start = length(objects)
        end
    end
    (
        line_count=length(parsed),
        commands=commands,
        errors=errors,
        counts=counts,
        roots=roots,
        objects=objects,
        deaths=deaths,
        lifetimes=lifetimes,
        live=live,
        peak=peak,
        peak_line=peak_line,
        checkpoints=checkpoints,
        alive=alive
    )
end
function script_lines(script)
    lines = ["script lines $(script.line_count) valid $(length(script.commands)) errors $(length(script.errors))"]
    append!(lines,["error line $line $reason" for (line,reason) in script.errors])
    push!(lines,"commands "*join(("$name $(script.counts[name])" for name in COMMAND_NAMES),' '))
    sizes = [obj.size for obj in script.objects]
    push!(
        lines,
        "allocated objects $(length(sizes)) words $(sum(sizes)) sizes $(class_table(sizes))",
        "peak_live objects $(script.peak.count) words $(script.peak.words) line $(script.peak_line)",
        "end_live objects $(script.live.count) words $(script.live.words) stack $(length(script.roots))"
    )
    counts = zeros(Int,6)
    for lifetime in script.lifetimes
        index = lifetime == -1 ? 6 : findfirst(limit->lifetime <= limit,(63,255,1023,4095,typemax(Int)))
        counts[index] += 1
    end
    labels = ("0-63","64-255","256-1023","1024-4095","4096+","live")
    push!(lines,"lifetimes "*join(("$label $(counts[i])" for (i,label) in enumerate(labels)),' '))
    for c in script.checkpoints
        push!(
            lines,
            "checkpoint $(c.label) line $(c.line) stack $(c.stack) live $(c.live) allocated $(c.allocated) phase $(c.phase) survivors $(c.survivors) survival $(pct(c.survivors.words,c.phase.words))"
        )
    end
    lines
end
function leak_report(title,garbage,deaths,placed)
    members = Set(obj.number for obj in garbage)
    neighbors = Dict(id=>Int[] for id in members)
    for obj in garbage,id in obj.fields
        if id in members
            push!(neighbors[obj.number],id)
            push!(neighbors[id],obj.number)
        end
    end
    groups = Vector{Int}[]
    grouped = Set{Int}()
    for id in sort(collect(members))
        id in grouped && continue
        stack,group = [id],Int[]
        push!(grouped,id)
        while !isempty(stack)
            current = pop!(stack)
            push!(group,current)
            for other in neighbors[current]
                if !(other in grouped)
                    push!(grouped,other)
                    push!(stack,other)
                end
            end
        end
        push!(groups,sort(group))
    end
    function on_cycle(id)
        visited = Set{Int}()
        stack = [child for child in placed[id].fields if child in members]
        while !isempty(stack)
            current = pop!(stack)
            current == id && return true
            current in visited && continue
            push!(visited,current)
            append!(stack,[child for child in placed[current].fields if child in members])
        end
        false
    end
    lines = ["$title groups $(length(groups)) objects $(length(garbage)) words $(pair_of(garbage).words)"]
    for (number,group) in enumerate(groups)
        cycles = on_cycle.(group)
        ids = join((string(id)*(cycle ? "*" : "") for (id,cycle) in zip(group,cycles)),' ')
        push!(
            lines,
            "group $number objects $(length(group)) words $(pair_of(placed[group]).words) cycle $(count(cycles)) died $(maximum(deaths[group])) ids $ids"
        )
    end
    lines
end
function retain!(state,id)
    id == 0 && return
    state.placed[id].count += 1
    state.increments += 1
end
function release!(state,id)
    id == 0 && return
    state.decrements += 1
    state.placed[id].count -= 1
    state.placed[id].count != 0 && return
    pending = [id]
    while !isempty(pending)
        object = state.placed[pop!(pending)]
        filter!(obj->obj.number != object.number,state.objects)
        push!(state.released,object)
        for child in object.fields
            child == 0 && continue
            state.decrements += 1
            state.placed[child].count -= 1
            state.placed[child].count == 0 && push!(pending,child)
        end
    end
end
function collect_backup!(state,roots,line,request)
    record = CollectionRecord(length(state.records)+1,line,request,"backup",free_list(state))
    mark!(record,roots,state.objects,state.placed)
    garbage = filter(obj->!obj.marked,state.objects)
    push!(state.reports,leak_report("backup $(record.number) line $line",garbage,state.deaths,state.placed))
    sweep!(state,record)
    for obj in garbage,id in obj.fields
        if id != 0 && state.placed[id].marked
            state.placed[id].count -= 1
            state.decrements += 1
        end
    end
    finish_record!(state,record)
end
mutable struct Run
    entry::NamedTuple
    config::NamedTuple
    script::NamedTuple
    collector::Collector
    roots::Vector{Int}
    cascades::Vector{NamedTuple}
    timeline::Vector{Tuple{Bool,Int}}
    observations::Vector{Vector{String}}
    peak_used::Int
    failed_line::Int
    failed_size::Int
end
Run(entry,config,script) = Run(
    entry,
    config,
    script,
    Collector(entry,config.heap_size,script.deaths),
    Int[],
    NamedTuple[],
    Tuple{Bool,Int}[],
    Vector{String}[],
    0,
    0,
    0
)
function add_time!(run,mutator,units)
    units == 0 && return
    if !isempty(run.timeline) && run.timeline[end][1] == mutator
        run.timeline[end] = (mutator,run.timeline[end][2]+units)
    else
        push!(run.timeline,(mutator,units))
    end
end
function allocate!(run,obj,line)
    state = run.collector
    accepted = state.kind in ("MARK_SWEEP","REFCOUNT") ? allocate_sweep!(state,obj,run.roots,line) : state.kind == "MARK_COMPACT" ? allocate_compact!(
        state,
        obj,
        run.roots,
        line
    ) : state.kind == "COPYING" ? allocate_copying!(
        state,
        obj,
        run.roots,
        line
    ) : allocate_generational!(
        state,
        obj,
        run.roots,
        line
    )
    accepted || return false
    push!(state.placed,obj)
    state.kind == "REFCOUNT" && retain!(state,obj.number)
    push!(run.roots,obj.number)
    run.peak_used = max(run.peak_used,pair_of(state.objects).words)
    true
end
function observe(run,checkpoint)
    state,reachable = run.collector,checkpoint.reachable
    objects = state.objects
    live = filter(obj->obj.number in reachable,objects)
    garbage = filter(obj->!(obj.number in reachable),objects)
    blocks = free_list(state)
    lines = [
        "heap objects $(pair_of(objects)) reachable $(pair_of(live)) garbage $(pair_of(garbage))",
        "free total $(total_free(blocks)) largest $(largest_free(blocks)) blocks $(length(blocks)) sizes $(class_table([n for (_,n) in blocks])) fragmentation $(fragmentation(blocks))"
    ]
    pointers,forward,backward,distance = 0,0,0,0
    for obj in live,id in obj.fields
        id == 0 && continue
        child = state.placed[id]
        pointers += 1
        forward += child.address > obj.address
        backward += child.address < obj.address
        distance += abs(child.address-obj.address)
    end
    mean = pointers == 0 ? "-" : dec2(distance,pointers)
    push!(lines,"locality pointers $pointers forward $forward backward $backward mean_distance $mean")
    if state.kind == "GENERATIONAL"
        young = filter(obj->is_young(state,obj),objects)
        old = filter(obj->!is_young(state,obj),objects)
        ages = [count(obj->min(obj.age,3) == a,young) for a in 0:3]
        push!(
            lines,
            "generations young $(pair_of(young)) old $(pair_of(old)) remembered $(length(state.remembered)) ages 0:$(ages[1]) 1:$(ages[2]) 2:$(ages[3]) 3+:$(ages[4])"
        )
    end
    if checkpoint.label in run.config.maps
        text = heap_map(state.size,objects,reachable,inactive_range(state))
        width = run.config.width
        for start in 0:width:(state.size-1)
            push!(lines,"$(lpad(string(start),4,'0')) $(text[(start+1):(start+width)])")
        end
    end
    lines
end
function execute!(run,command)
    state,roots = run.collector,run.roots
    refcount = state.kind == "REFCOUNT"
    value = command.source == -1 ? 0 : source_value(roots,command.source)
    if command.name in ("PUSH","LOAD")
        id = command.name == "PUSH" ? value : state.placed[roots[command.slot+1]].fields[command.field+1]
        refcount && retain!(state,id)
        push!(roots,id)
    elseif command.name == "POP"
        for _ in 1:command.count
            id = pop!(roots)
            refcount && release!(state,id)
        end
    elseif command.name == "SET"
        target = state.placed[roots[command.slot+1]]
        state.kind == "GENERATIONAL" && write_barrier!(state,target,value)
        refcount && retain!(state,value)
        previous = target.fields[command.field+1]
        target.fields[command.field+1] = value
        refcount && release!(state,previous)
    elseif command.name == "OVERWRITE"
        refcount && retain!(state,value)
        previous = roots[command.slot+1]
        roots[command.slot+1] = value
        refcount && release!(state,previous)
    elseif command.name == "CHECKPOINT"
        checkpoint = run.script.checkpoints[length(run.observations)+1]
        push!(run.observations,observe(run,checkpoint))
    end
end
function simulate!(run)
    state = run.collector
    for command in run.script.commands
        previous = length(state.records)
        units = 1
        if command.name == "ALLOC"
            obj = HeapObject(length(state.placed)+1,command.pointers,command.data)
            units = obj.size
            placed = allocate!(run,obj,command.line)
        else
            execute!(run,command)
            placed = true
        end
        for record in state.records[(previous+1):end]
            add_time!(run,false,record.work)
        end
        if !placed
            run.failed_line,run.failed_size = command.line,units
            return
        end
        add_time!(run,true,units)
        if !isempty(state.released)
            freed = pair_of(state.released)
            work = sum(1+length(obj.fields) for obj in state.released)
            push!(run.cascades,(line=command.line,freed=freed,work=work))
            empty!(state.released)
            add_time!(run,false,work)
        end
    end
    if state.kind == "REFCOUNT"
        garbage = filter(obj->!(obj.number in run.script.alive),state.objects)
        push!(state.reports,leak_report("end",garbage,state.deaths,state.placed))
    end
end
function pauses(run)
    vcat(
        [(line=r.line,work=r.work,freed_words=r.freed.words,collection=true) for r in run.collector.records],
        [(line=c.line,work=c.work,freed_words=c.freed.words,collection=false) for c in run.cascades]
    )
end
function pause_stats(pauses)
    works = sort([p.work for p in pauses])
    n = length(works)
    percentile(x) = n == 0 ? "-" : string(works[(x*n+99)÷100])
    (
        count=n,
        collections=count(p->p.collection,pauses),
        work=sum(works;init=0),
        freed_words=sum((p.freed_words for p in pauses);init=0),
        maximum=maximum(works;init=0),
        p50=percentile(50),
        p90=percentile(90)
    )
end
function timeline_stats(run)
    starts,prefix = Int[],Int[]
    total,mutator = 0,0
    for (flag,units) in run.timeline
        push!(starts,total)
        push!(prefix,mutator)
        total += units
        flag && (mutator+=units)
    end
    function until(position)
        index = searchsortedlast(starts,position)
        prefix[index]+(run.timeline[index][1] ? position-starts[index] : 0)
    end
    function mmu(width)
        width > total && return "-"
        lowest = width
        for (i,(_,units)) in enumerate(run.timeline),begin_time in (starts[i],starts[i]+units-width)
            if 0 <= begin_time <= total-width
                lowest = min(lowest,until(begin_time+width)-until(begin_time))
            end
        end
        pct(lowest,width)
    end
    pct(mutator,total),["$width:$(mmu(width))" for width in run.config.windows]
end
function collection_lines(run)
    state = run.collector
    lines = ["collector $(run.entry.name) $(run.entry.kind)"]
    for r in state.records
        push!(
            lines,
            "$(r.number) line $(r.line) size $(r.request) kind $(r.kind) live $(r.live) freed $(r.freed) moved $(r.moved) promoted $(r.promoted) stack $(r.stack) work $(r.work) before $(r.before[1]) $(r.before[2]) after $(r.after[1]) $(r.after[2])"
        )
    end
    all_pauses = pauses(run)
    stats = pause_stats(all_pauses)
    push!(
        lines,
        "totals collections $(stats.collections) pauses $(stats.count) work $(stats.work) freed $(stats.freed_words) pause p50 $(stats.p50) p90 $(stats.p90) max $(stats.maximum)"
    )
    utilization,mmu = timeline_stats(run)
    push!(lines,"utilization $utilization mmu "*join(mmu,' '))
    if state.kind == "GENERATIONAL"
        parts = ["generational"]
        for kind in ("minor","major","tenure","full")
            records = filter(r->r.kind == kind,state.records)
            push!(parts,"$kind $(length(records)) $(sum((r.work for r in records);init=0))")
        end
        promoted = ObjectPair(
            sum((r.promoted.count for r in state.records);init=0),
            sum((r.promoted.words for r in state.records);init=0)
        )
        push!(parts,"promoted $promoted","barrier $(state.barriers)","remembered $(state.remembers)")
        push!(lines,join(parts,' '))
    elseif state.kind == "REFCOUNT"
        freed = ObjectPair(
            sum((c.freed.count for c in run.cascades);init=0),
            sum((c.freed.words for c in run.cascades);init=0)
        )
        largest = isempty(run.cascades) ? nothing : run.cascades[argmax([c.work for c in run.cascades])]
        maximum_text = isnothing(largest) ? "max_cascade 0 0 line -" : "max_cascade $(largest.freed.count) $(largest.work) line $(largest.line)"
        push!(
            lines,
            "refcount increments $(state.increments) decrements $(state.decrements) cascades $(length(run.cascades)) freed $freed $maximum_text"
        )
    end
    previous = 0
    for c in run.script.checkpoints
        if run.failed_line != 0 && run.failed_line < c.line
            push!(lines,"phase $(c.label) out_of_memory")
        else
            stats = pause_stats(filter(p->previous < p.line <= c.line,all_pauses))
            push!(
                lines,
                "phase $(c.label) collections $(stats.collections) pauses $(stats.count) work $(stats.work) freed $(stats.freed_words) max_pause $(stats.maximum)"
            )
        end
        previous = c.line
    end
    push!(
        lines,
        run.failed_line == 0 ? "status completed" : "status out_of_memory line $(run.failed_line) size $(run.failed_size)"
    )
    lines
end
function summary_row(run)
    state = run.collector
    stats = pause_stats(pauses(run))
    moves = [obj.moves for obj in state.placed if obj.moves > 0]
    if run.failed_line == 0
        blocks = free_list(state)
        status = "completed"
        ending = (pair_of(state.objects).words,total_free(blocks),largest_free(blocks),fragmentation(blocks))
    else
        status = "out_of_memory"
        ending = ("-","-","-","-")
    end
    fields = (
        run.entry.name,
        run.entry.kind,
        status,
        length(state.records),
        stats.count,
        sum((r.live.count for r in state.records);init=0),
        sum((r.moved.count for r in state.records);init=0),
        length(moves),
        maximum(moves;init=0),
        stats.freed_words,
        stats.work,
        stats.p50,
        stats.p90,
        stats.maximum,
        run.peak_used,
        ending...
    )
    join(fields,',')
end
function join_blocks(blocks)
    lines = String[]
    for block in blocks
        !isempty(lines) && push!(lines,"")
        append!(lines,block)
    end
    lines
end
function main()
    config = read_config("input/config.txt")
    script = analyze_script(read_script("input/mutator.txt"))
    runs = [Run(entry,config,script) for entry in config.collectors]
    foreach(simulate!,runs)
    maps = Vector{String}[]
    for (i,c) in enumerate(script.checkpoints),run in runs
        block = ["checkpoint $(c.label) line $(c.line) collector $(run.entry.name)"]
        append!(block,i <= length(run.observations) ? run.observations[i] : ["out_of_memory"])
        push!(maps,block)
    end
    leaks = Vector{String}[]
    for run in runs
        run.entry.kind == "REFCOUNT" || continue
        lines = ["collector $(run.entry.name)"]
        for report in run.collector.reports
            append!(lines,report)
        end
        run.failed_line != 0 && push!(lines,"status out_of_memory")
        push!(leaks,lines)
    end
    outputs = (
        ("mutator.txt",script_lines(script)),
        ("heap_maps.txt",join_blocks(maps)),
        ("collections.txt",join_blocks(collection_lines.(runs))),
        ("summary.csv",vcat([SUMMARY_HEADER],summary_row.(runs))),
        ("leaks.txt",isempty(leaks) ? ["none"] : join_blocks(leaks))
    )
    mkpath("output")
    for (name,lines) in outputs
        open(joinpath("output",name),"w") do io
            foreach(line->println(io,line),lines)
        end
    end
end
main()
