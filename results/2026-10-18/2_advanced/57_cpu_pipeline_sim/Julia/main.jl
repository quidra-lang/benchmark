include("trace_io.jl")
include("hazards.jl")
include("pipeline.jl")
include("predictors.jl")
include("report.jl")
const CLASSES = ("ALU","MUL","LOAD","STORE","BRANCH","JUMP","NOP")
const CONTROLS = ("BRANCH","JUMP")
const OPERANDS = Dict(
    "ALU"=>(1,1,2),
    "MUL"=>(1,1,1),
    "LOAD"=>(1,1,0),
    "STORE"=>(0,1,1),
    "BRANCH"=>(0,1,2),
    "JUMP"=>(2,2,0),
    "NOP"=>(0,0,0)
)
const MISS_KINDS = ("direction","btb_miss","wrong_target")
function check_record(line,static)
    tokens = String.(split(line,' ';keepempty=true))
    (length(tokens)!=8 || any(isempty,tokens)) && return nothing,"fields"
    pc_text,kind,rd_text,rs1_text,rs2_text,outcome,target_text,address_text = tokens
    pc = parse_hex(pc_text)
    (isnothing(pc) || pc%4!=0) && return nothing,"pc"
    kind in CLASSES || return nothing,"class"
    texts = (rd_text,rs1_text,rs2_text)
    registers = parse_register.(texts)
    any(text!="-" && value==-1 for (text,value) in zip(texts,registers)) && return nothing,"register"
    for (text,usage) in zip(texts,OPERANDS[kind])
        ((usage==1 && text=="-") || (usage==0 && text!="-")) && return nothing,"operands"
    end
    allowed = kind=="BRANCH" ? ("T","N") : kind=="JUMP" ? ("T",) : ("-",)
    outcome in allowed || return nothing,"taken"
    target = parse_hex(target_text)
    if kind in CONTROLS
        (isnothing(target) || target%4!=0 || target==pc+4) && return nothing,"target"
    else
        target_text=="-" || return nothing,"target"
    end
    address = parse_hex(address_text)
    if kind in ("LOAD","STORE")
        (isnothing(address) || address%4!=0) && return nothing,"address"
    else
        address_text=="-" || return nothing,"address"
    end
    rd,rs1,rs2 = registers
    instruction = (
        pc=pc,
        kind=kind,
        rd=rd,
        rs1=rs1,
        rs2=rs2,
        outcome=outcome,
        target=target,
        address=address,
        next_pc=outcome=="T" ? target : pc+4
    )
    if haskey(static,pc)
        previous = static[pc]
        (kind,rd,rs1,rs2)==(previous.kind,previous.rd,previous.rs1,previous.rs2) || return nothing,"conflict"
        fixed_target = kind=="BRANCH" || (kind=="JUMP" && rs1==-1)
        fixed_target && target!=previous.target && return nothing,"conflict"
    end
    instruction,nothing
end
function validate_trace(lines)
    instructions,rejected,gaps = NamedTuple[],Tuple{Int,String}[],NTuple{3,Int}[]
    static = Dict{Int,NamedTuple}()
    for (line_number,line) in enumerate(lines)
        instruction,error = check_record(line,static)
        if !isnothing(error)
            push!(rejected,(line_number,error))
            continue
        end
        instruction = (;instruction...,line=line_number,number=length(instructions)+1)
        if !isempty(instructions) && instruction.pc!=instructions[end].next_pc
            push!(gaps,(line_number,instructions[end].next_pc,instruction.pc))
        end
        push!(instructions,instruction)
        get!(static,instruction.pc,instruction)
    end
    (lines=length(lines),instructions=instructions,rejected=rejected,gaps=gaps,static=static)
end
counter_value(statistics,key) = get(statistics,key,0)
function predict_trace(instructions,definition,config)
    btb,ras = BTB(config["btb"]),RAS(config["ras"])
    direction = DirectionPredictor(definition.scheme,definition.parameters)
    details = Vector{Any}(undef,length(instructions))
    fill!(details,nothing)
    flags = falses(length(instructions))
    statistics = Dict{String,Int}()
    increase(key,value=1) = (statistics[key]=get(statistics,key,0)+value)
    for (i,instruction) in enumerate(instructions)
        kind = instruction.kind
        kind in CONTROLS || continue
        pc,target,taken = instruction.pc,instruction.target,instruction.outcome=="T"
        candidate = lookup(btb,pc)
        increase("lookups")
        increase("hits",!isnothing(candidate))
        is_return = kind=="JUMP" && instruction.rd==-1 && instruction.rs1==31
        is_call = kind=="JUMP" && instruction.rd==31
        increase("calls",is_call)
        increase("returns",is_return)
        if is_return
            address = ras_pop!(ras)
            if !isnothing(address)
                candidate = address
                increase("ras_predictions")
                increase("ras_correct",address==target)
            end
        end
        is_call && ras_push!(ras,pc+4)
        predicted_taken = kind=="BRANCH" ? direction_prediction(direction,pc,target) : true
        predicted = definition.scheme=="PERFECT" ? instruction.next_pc : kind=="JUMP" ? (isnothing(candidate) ? pc+4 : candidate) : (predicted_taken && !isnothing(candidate) ? candidate : pc+4)
        missed = predicted!=instruction.next_pc
        miss_kind = nothing
        if missed
            miss_kind = kind=="BRANCH" && predicted_taken!=taken ? "direction" : isnothing(candidate) ? "btb_miss" : "wrong_target"
            increase(miss_kind)
        end
        flags[i] = missed
        details[i] = (predicted=predicted,kind=miss_kind,missed=missed)
        increase("control")
        increase("mispredictions",missed)
        increase(kind)
        increase(kind*"_misses",missed)
        kind=="BRANCH" && direction_update!(direction,pc,taken)
        taken && btb_insert!(btb,pc,target)
    end
    (definition=definition,details=details,flags=flags,statistics=statistics,bits=storage_bits(direction))
end
function stall_totals(records)
    cycles,events = zeros(Int,4),zeros(Int,4)
    for record in records
        cycles[record.cause] += record.cycles
        events[record.cause] += 1
    end
    cycles,events
end
function all_combinations(instructions,sources,predictions,config)
    combinations,primary = NamedTuple[],nothing
    for variant in config["variants"],predictor in config["predictors"]
        result = simulate(instructions,sources,variant,predictions[predictor.name].flags)
        cycles,events = stall_totals(result.records)
        push!(combinations,(variant=variant.name,predictor=predictor.name,cycles=result.cycles,stalls=cycles))
        if (variant.name,predictor.name)==config["primary"]
            primary = (;result...,variant=variant,predictor=predictor.name,stalls=cycles,stall_events=events)
        end
    end
    sort!(combinations;by=pair->(pair.cycles,pair.variant,pair.predictor))
    combinations,primary
end
function build_rows(instructions,primary,prediction)
    annotations = fill("",length(instructions))
    for record in primary.records
        record.waiting!=0 && (annotations[record.waiting]*=" $(CAUSES[record.cause]) $(record.cycles)")
    end
    rows = NamedTuple[]
    for (i,instruction) in enumerate(instructions)
        f,d,x,m,w = primary.timings[i,:]
        annotation = annotations[i]
        prediction.flags[i] && (annotation*=" mispredict $(prediction.details[i].kind)")
        characters = [(f,f,'F'),(f+1,d-1,'*'),(d,d,'D'),(d+1,x-1,'*'),(x,m-1,'X'),(m,m,'M'),(w,w,'W')]
        stages = [(1,f,d-1),(2,d,x-1),(3,x,m-1),(4,m,m),(5,w,w)]
        push!(
            rows,
            (
                number=i,
                pc=instruction.pc,
                kind=instruction.kind,
                annotation=annotation,
                characters=characters,
                stages=stages
            )
        )
        prediction.flags[i] || continue
        resolved = id_resolved(instruction,primary.variant)
        cancel = x+!resolved
        characters = [(d,d,'F'),(d+1,x-1,'*'),(cancel,cancel,'x')]
        stages = [(1,d,x-1)]
        if !resolved
            push!(characters,(x,x,'D'))
            push!(stages,(2,x,x))
        end
        pc = prediction.details[i].predicted
        push!(rows,(number=0,pc=pc,kind="FLUSH",annotation="",characters=characters,stages=stages))
        if !resolved
            push!(
                rows,
                (
                    number=0,
                    pc=pc+4,
                    kind="FLUSH",
                    annotation="",
                    characters=[(x,x,'F'),(x+1,x+1,'x')],
                    stages=[(1,x,x)]
                )
            )
        end
    end
    rows
end
function occupancy(rows)
    counts = zeros(Int,5,2)
    for row in rows,(stage,first,last) in row.stages
        counts[stage,row.number==0 ? 2 : 1] += last-first+1
    end
    counts
end
function pipeline_lines(rows,primary,config)
    first,last = config["window"]
    width = last-first+1
    lines = [
        "pipeline variant=$(primary.variant.name) predictor=$(primary.predictor) cycles $first-$last",
        cycle_heading(first,last)
    ]
    contents = fill(".",width,5)
    visible,stalled,flushed = 0,0,0
    for row in rows
        characters = fill('.',width)
        for (beginning,ending,symbol) in row.characters,cycle in max(first,beginning):min(last,ending)
            characters[cycle-first+1] = symbol
        end
        if any(!=('.'),characters)
            visible += 1
            stalled += count(==('*'),characters)
            flushed += count(==('x'),characters)
            push!(lines,diagram_row(row.number,row.pc,row.kind,join(characters),row.annotation))
        end
        for (stage,beginning,ending) in row.stages,cycle in max(first,beginning):min(last,ending)
            contents[cycle-first+1,stage] = row.number==0 ? "w" : string(row.number)
        end
    end
    completed = count(w->first<=w<=last,primary.timings[:,5])
    append!(
        lines,
        [
            "rows $visible completed $completed stall_cells $stalled flushed $flushed",
            "",
            "stages",
            "cycle IF ID EX MEM WB"
        ]
    )
    append!(lines,["$cycle "*join(contents[cycle-first+1,:]," ") for cycle in first:last])
    lines
end
function stall_aggregates(instructions,records)
    classes = Dict(kind=>0 for kind in CLASSES)
    by_pc = Dict{Int,Vector{Int}}()
    pairs = Dict{NTuple{3,Int},Vector{Int}}()
    for record in records
        instruction = instructions[record.responsible]
        classes[instruction.kind] += record.cycles
        get!(by_pc,instruction.pc,zeros(Int,4))[record.cause] += record.cycles
        if record.cause>=3
            key = (instructions[record.producer].pc,instructions[record.waiting].pc,record.cause)
            group = get!(pairs,key,zeros(Int,2))
            group[1] += record.cycles
            group[2] += 1
        end
    end
    classes,by_pc,pairs
end
function dataflow_height(instructions,sources,latency)
    finish = zeros(Int,length(instructions))
    for (i,instruction) in enumerate(instructions)
        start = maximum((finish[source.producer] for source in sources[i] if source.producer!=0);init=0)
        cost = instruction.kind=="LOAD" ? 2 : instruction.kind=="MUL" ? latency : 1
        finish[i] = start+cost
    end
    maximum(finish)
end
function whatif_runs(instructions,sources,primary,flags)
    variant = primary.variant
    changes = [("perfect_prediction",variant,falses(length(instructions))),("single_cycle_mul",(;variant...,latency=1),flags),
        (
            variant.forwarding ? "forwarding_off" : "forwarding_on",
            (;variant...,forwarding=!variant.forwarding),
            flags
        ),
        (
            variant.stage=="EX" ? "branch_stage_ID" : "branch_stage_EX",
            (;variant...,stage=variant.stage=="EX" ? "ID" : "EX"),
            flags
        )]
    [(name,simulate(instructions,sources,modified,misses).cycles) for (name,modified,misses) in changes]
end
function input_part(trace)
    lines = ["input lines $(trace.lines) accepted $(length(trace.instructions)) rejected $(length(trace.rejected)) gaps $(length(trace.gaps))"]
    append!(lines,["reject line $line $reason" for (line,reason) in trace.rejected])
    append!(
        lines,
        ["gap line $line expected $(hexadecimal(expected)) found $(hexadecimal(found))" for (
            line,
            expected,
            found
        ) in trace.gaps]
    )
    lines
end
function trace_part(trace,sources)
    instructions = trace.instructions
    counts = Dict(kind=>count(i->i.kind==kind,instructions) for kind in CLASSES)
    branches = [i for i in instructions if i.kind=="BRANCH"]
    jumps = [i for i in instructions if i.kind=="JUMP"]
    addresses = Set(i.address for i in instructions if i.kind in ("LOAD","STORE"))
    distances,source_count = zeros(Int,5),0
    for (i,operands) in enumerate(sources)
        source_count += length(operands)
        for source in operands
            source.producer!=0 && (distances[min(5,i-source.producer)]+=1)
        end
    end
    static = collect(values(trace.static))
    ["trace","instructions $(length(instructions))","static_instructions $(length(static))","mix "*join(("$kind $(counts[kind])" for kind in CLASSES)," "),
        "branches $(length(branches)) taken $(count(i->i.outcome=="T",branches)) backward $(count(i->i.target<i.pc,branches))",
        "jumps $(length(jumps)) indirect $(count(i->i.rs1!=-1,jumps)) link $(count(i->i.rd!=-1,jumps))",
        "static_control branches $(count(i->i.kind=="BRANCH",static)) jumps $(count(i->i.kind=="JUMP",static))",
        "memory loads $(counts["LOAD"]) stores $(counts["STORE"]) distinct_addresses $(length(addresses))",
        "operands $source_count with_producer $(sum(distances)) distance "*join(
            ("$label $value" for (label,value) in zip(("1","2","3","4","5+"),distances)),
            " "
        )]
end
function prediction_accuracy(prediction,kind="control")
    statistics = prediction.statistics
    total = counter_value(statistics,kind)
    misses = counter_value(statistics,kind=="control" ? "mispredictions" : kind*"_misses")
    percentage(total-misses,total)
end
function prediction_part(predictions,config)
    lines = ["prediction"]
    for definition in config["predictors"]
        prediction = predictions[definition.name]
        s = prediction.statistics
        push!(
            lines,
            "$(definition.name) $(definition.scheme) bits $(prediction.bits) control $(counter_value(s,"control")) mispredicted $(counter_value(s,"mispredictions")) accuracy $(prediction_accuracy(prediction)) branches $(prediction_accuracy(prediction,"BRANCH")) jumps $(prediction_accuracy(prediction,"JUMP")) "*join(
                ("$kind $(counter_value(s,kind))" for kind in MISS_KINDS),
                " "
            )
        )
    end
    s = predictions[config["predictors"][1].name].statistics
    push!(lines,"btb entries $(config["btb"]) lookups $(counter_value(s,"lookups")) hits $(counter_value(s,"hits")) misses $(counter_value(s,"lookups")-counter_value(s,"hits"))",
        "ras depth $(config["ras"]) calls $(counter_value(s,"calls")) returns $(counter_value(s,"returns")) predicted $(counter_value(s,"ras_predictions")) correct $(counter_value(s,"ras_correct"))")
    lines
end
cause_values(values) = join(("$cause $value" for (cause,value) in zip(CAUSES,values))," ")
function timing_part(primary,n,height,refetch)
    variant,c,stalls = primary.variant,primary.cycles,primary.stalls
    total = sum(stalls)
    lengths = zeros(Int,5)
    for value in primary.delays
        value>0 && (lengths[min(5,value)]+=1)
    end
    cpi_causes = join(("$cause $(decimal(value,n))" for (cause,value) in zip(CAUSES,stalls))," ")
    ["timing variant=$(variant.name) predictor=$(primary.predictor)","forwarding $(variant.forwarding ? "on" : "off") branch_stage $(variant.stage) mul_latency $(variant.latency)",
        "cycles $c","cpi $(reduced_fraction(c,n)) $(decimal(c,n))","ipc $(decimal(n,c))","stall_cycles total $total $(cause_values(stalls))",
        "stall_events $(cause_values(primary.stall_events))","flushed $refetch","cycle_check $n + 4 + $total = $(n+4+total)",
        "cpi_stack base 1.0000 fill $(decimal(4,n)) $cpi_causes","stall_lengths "*join(
            ("$label $value" for (label,value) in zip(("1","2","3","4","5+"),lengths)),
            " "
        ),
        "dataflow height $height ilp $(decimal(n,height))"]
end
function statistics_lines(trace,sources,predictions,combinations,primary,rows,config)
    instructions,n = trace.instructions,length(trace.instructions)
    height = dataflow_height(instructions,sources,primary.variant.latency)
    class_stalls,by_pc,pairs = stall_aggregates(instructions,primary.records)
    forward = zeros(Int,3)
    for (i,instruction) in enumerate(instructions),source in sources[i]
        p = source.producer
        path = forwarding_path(
            instruction,
            p==0 ? nothing : primary.timings[p,:],
            primary.timings[i,:],
            primary.variant
        )
        forward[path] += 1
    end
    whatif = ["whatif"]
    for (name,c) in whatif_runs(instructions,sources,primary,predictions[primary.predictor].flags)
        push!(whatif,"$name cycles $c saved $(primary.cycles-c) speedup $(decimal(primary.cycles,c))")
    end
    classes = ["classes"]
    for kind in CLASSES
        total = count(i->i.kind==kind,instructions)
        average = total==0 ? "-" : decimal(class_stalls[kind],total)
        push!(classes,"$kind count $total stall_cycles $(class_stalls[kind]) per_instruction $average")
    end
    occupied = occupancy(rows)
    occupancy_lines = ["occupancy cycles $(primary.cycles)"]
    for (i,stage) in enumerate(STAGES)
        correct,wrong = occupied[i,:]
        push!(
            occupancy_lines,
            "$stage correct $correct wrong $wrong idle $(primary.cycles-correct-wrong) busy $(percentage(correct+wrong,primary.cycles))"
        )
    end
    hotspots = ["hotspots"]
    pcs = sort(collect(keys(by_pc));by=pc->(-sum(by_pc[pc]),pc))
    for (rank,pc) in enumerate(pcs[1:min(config["top"],length(pcs))])
        push!(
            hotspots,
            "$rank $(hexadecimal(pc)) $(trace.static[pc].kind) stall_cycles $(sum(by_pc[pc])) $(cause_values(by_pc[pc]))"
        )
    end
    dependency_lines = ["dependencies total $(length(pairs))"]
    ordered = sort(collect(keys(pairs));by=key->(-pairs[key][1],key...))
    for (rank,key) in enumerate(ordered[1:min(config["top"],length(ordered))])
        producer,waiting,cause = key
        cycles,events = pairs[key]
        push!(
            dependency_lines,
            "$rank $(hexadecimal(producer)) $(trace.static[producer].kind) -> $(hexadecimal(waiting)) $(trace.static[waiting].kind) $(CAUSES[cause]) stall_cycles $cycles events $events"
        )
    end
    intervals = ["intervals size $(config["interval"])"]
    for first in 1:config["interval"]:n
        last = min(n,first+config["interval"]-1)
        previous = first==1 ? 0 : primary.timings[first-1,5]
        cycles = primary.timings[last,5]-previous
        push!(intervals,"$first-$last cycles $cycles cpi $(decimal(cycles,last-first+1))")
    end
    table = Dict((pair.variant,pair.predictor)=>pair.cycles for pair in combinations)
    names = [definition.name for definition in config["predictors"]]
    table_lines = ["cycles_table "*join(names," ")]
    for variant in config["variants"]
        push!(table_lines,variant.name*" "*join((string(table[(variant.name,name)]) for name in names)," "))
    end
    forward_line = "forwarding "*join(
        ("$name $value" for (name,value) in zip(("regfile","ex_mem","mem_wb"),forward)),
        " "
    )
    join_parts([input_part(trace),trace_part(trace,sources),prediction_part(predictions,config),timing_part(primary,n,height,count(row->row.number==0,rows)),
        whatif,classes,[forward_line],occupancy_lines,hotspots,dependency_lines,intervals,table_lines])
end
function group_executions(instructions)
    groups = Dict{Int,Vector{Int}}()
    for (i,instruction) in enumerate(instructions)
        push!(get!(groups,instruction.pc,Int[]),i)
    end
    groups
end
function branch_lines(instructions,groups,predictions,config)
    lines = ["predictor,pc,class,executions,taken,mispredictions,accuracy"]
    for definition in config["predictors"],pc in sort(collect(keys(groups)))
        indices = groups[pc]
        kind = instructions[indices[1]].kind
        kind in CONTROLS || continue
        taken = count(i->instructions[i].outcome=="T",indices)
        missed = count(predictions[definition.name].flags[indices])
        push!(
            lines,
            "$(definition.name),$(hexadecimal(pc)),$kind,$(length(indices)),$taken,$missed,$(percentage(length(indices)-missed,length(indices)))"
        )
    end
    lines
end
function comparison_lines(combinations,primary,predictions,n)
    lines = ["rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw"]
    for (rank,pair) in enumerate(combinations)
        prediction = predictions[pair.predictor]
        values = [
            string(rank),
            pair.variant,
            pair.predictor,
            string(pair.cycles),
            decimal(pair.cycles,n),
            decimal(primary.cycles,pair.cycles),
            prediction_accuracy(prediction),
            string(counter_value(prediction.statistics,"mispredictions"))
        ]
        append!(values,string.(pair.stalls))
        push!(lines,join(values,","))
    end
    lines
end
function profile_lines(instructions,groups,predictions,primary,config)
    branches,loops,indirect,static_lines = ["branches"],["loops"],["indirect"],["instructions"]
    choices = [definition.name for definition in config["predictors"] if definition.scheme!="PERFECT"]
    _,by_pc,_ = stall_aggregates(instructions,primary.records)
    for pc in sort(collect(keys(groups)))
        indices = groups[pc]
        instruction = instructions[indices[1]]
        if instruction.kind=="BRANCH"
            outcomes = [instructions[i].outcome for i in indices]
            transitions = count(pair->pair[1]!=pair[2],zip(outcomes,outcomes[2:end]))
            longest = Dict("T"=>0,"N"=>0)
            previous,run = "",0
            trips,trip = Int[],0
            for outcome in outcomes
                run = outcome==previous ? run+1 : 1
                longest[outcome] = max(longest[outcome],run)
                previous = outcome
                trip += 1
                if outcome=="N"
                    push!(trips,trip)
                    trip = 0
                end
            end
            trip>0 && push!(trips,trip)
            misses = [count(predictions[name].flags[indices]) for name in choices]
            best = argmin(misses)
            direction = instruction.target<pc ? "backward" : "forward"
            push!(
                branches,
                "$(hexadecimal(pc)) $direction executions $(length(indices)) taken $(count(==("T"),outcomes)) transitions $transitions longest_taken $(longest["T"]) longest_not_taken $(longest["N"]) best $(choices[best]) $(misses[best])"
            )
            if direction=="backward"
                push!(
                    loops,
                    "$(hexadecimal(instruction.target))-$(hexadecimal(pc)) body $((pc-instruction.target)÷4+1) entries $(length(trips)) iterations $(length(indices)) avg_trip $(decimal(length(indices),length(trips))) max_trip $(maximum(trips))"
                )
            end
        end
        if instruction.kind=="JUMP" && instruction.rs1!=-1
            targets = Dict{Int,Int}()
            for i in indices
                target = instructions[i].target
                targets[target] = get(targets,target,0)+1
            end
            ordered = sort(collect(keys(targets));by=target->(-targets[target],target))
            values = join(("$(hexadecimal(target)):$(targets[target])" for target in ordered)," ")
            push!(
                indirect,
                "$(hexadecimal(pc)) executions $(length(indices)) distinct $(length(targets)) targets $values"
            )
        end
        operands = join(register_text.((instruction.rd,instruction.rs1,instruction.rs2))," ")
        total = sum(get(by_pc,pc,zeros(Int,4)))
        push!(
            static_lines,
            "$(hexadecimal(pc)) $(instruction.kind) $operands executions $(length(indices)) stall_cycles $total"
        )
    end
    segments = Dict{Int,Vector{Int}}()
    first = 1
    for (last,instruction) in enumerate(instructions)
        if instruction.kind in CONTROLS || last==length(instructions)
            pc = instructions[first].pc
            group = get!(segments,pc,zeros(Int,3))
            group[1] += 1
            group[2] += last-first+1
            group[3] += primary.timings[last,5]-(first==1 ? 0 : primary.timings[first-1,5])
            first = last+1
        end
    end
    segment_lines = ["segments total $(length(segments))"]
    ordered = sort(collect(keys(segments));by=pc->(-segments[pc][3],pc))
    for (rank,pc) in enumerate(ordered[1:min(config["top"],length(ordered))])
        instances,total,cycles = segments[pc]
        push!(
            segment_lines,
            "$rank $(hexadecimal(pc)) instances $instances instructions $total cycles $cycles cpi $(decimal(cycles,total))"
        )
    end
    join_parts([branches,loops,segment_lines,indirect,static_lines])
end
function main()
    lines,config = read_inputs()
    trace = validate_trace(lines)
    instructions = trace.instructions
    sources = dependencies(instructions)
    predictions = Dict(definition.name=>predict_trace(
        instructions,
        definition,
        config
    ) for definition in config["predictors"])
    combinations,primary = all_combinations(instructions,sources,predictions,config)
    rows = build_rows(instructions,primary,predictions[primary.predictor])
    groups = group_executions(instructions)
    write_lines("pipeline.txt",pipeline_lines(rows,primary,config))
    write_lines("stats.txt",statistics_lines(trace,sources,predictions,combinations,primary,rows,config))
    write_lines("branches.csv",branch_lines(instructions,groups,predictions,config))
    write_lines("comparison.csv",comparison_lines(combinations,primary,predictions,length(instructions)))
    write_lines("profile.txt",profile_lines(instructions,groups,predictions,primary,config))
end
main()
