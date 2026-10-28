include("cnf_io.jl")
include("encoders.jl")
include("preprocess.jl")
include("dpll.jl")
include("report.jl")

const COMMANDS = ("SOLVE","ENUM","CORE","QUEENS","PIGEON","COLOR","CHROMATIC")
const ARGUMENT_TYPES = Dict(
    "SOLVE"=>("file",),
    "ENUM"=>("file","limit"),
    "CORE"=>("file",),
    "QUEENS"=>("small","limit"),
    "PIGEON"=>("small","small","limit"),
    "COLOR"=>("graph","color","limit"),
    "CHROMATIC"=>("graph","color")
)
record(;items...) = Dict{Symbol,Any}(items)
function load_graphs()
    graphs = Dict{String,Dict{Symbol,Any}}()
    current = nothing
    for (number,line) in enumerate(readlines(joinpath("input","graphs.txt")))
        if isnothing(current)
            (isempty(line) || startswith(line,"#")) && continue
            _,name,count = split(line)
            current = record(
                name=String(name),
                vertices=parse(Int,count),
                edges=Tuple{Int,Int}[],
                invalid=nothing
            )
            continue
        elseif line == "END"
            sort!(current[:edges])
            graphs[current[:name]] = current
            current = nothing
            continue
        end
        !isnothing(current[:invalid]) && continue
        tokens = split(line,' ';keepempty=true)
        reason = nothing
        if length(tokens) != 2 || !all(valid_number,tokens)
            reason = "bad edge line"
        else
            a,b = parse.(Int,tokens)
            if !(1 <= a <= current[:vertices] && 1 <= b <= current[:vertices])
                reason = "vertex out of range"
            elseif a == b
                reason = "self loop"
            elseif minmax(a,b) in current[:edges]
                reason = "duplicate edge"
            else
                push!(current[:edges],minmax(a,b))
            end
        end
        !isnothing(reason) && (current[:invalid]="$reason at line $number")
    end
    graphs
end
function load_jobs()
    jobs = Dict{Symbol,Any}[]
    for line in readlines(joinpath("input","jobs.txt"))
        (isempty(line) || startswith(line,"#")) && continue
        tokens = String.(split(line,' '))
        push!(jobs,record(number=length(jobs)+1,text=line,command=tokens[1],args=tokens[2:end]))
    end
    jobs
end
function validate_job(job,graphs)
    command = job[:command]
    !haskey(ARGUMENT_TYPES,command) && return "unknown command $command"
    types = ARGUMENT_TYPES[command]
    length(job[:args]) != length(types) && return "wrong argument count"
    for (argument,kind) in zip(job[:args],types)
        if kind == "file"
            occursin(r"^[a-z0-9_]{1,20}\.cnf$",argument) || return "bad file name $argument"
        elseif kind == "graph"
            !haskey(graphs,argument) && return "unknown graph $argument"
            !isnothing(graphs[argument][:invalid]) && return "invalid graph $argument: $(graphs[argument][:invalid])"
        else
            !valid_number(argument) && return "bad number $argument"
            maximum_value = kind == "small" ? 8 : kind == "color" ? 6 : 200
            !(1 <= parse(Int,argument) <= maximum_value) && return "out of range $argument"
        end
    end
    nothing
end
function greedy_coloring(graph)
    n = graph[:vertices]
    degree = zeros(Int,n)
    neighbors = [Int[] for _ in 1:n]
    for (a,b) in graph[:edges]
        degree[a] += 1
        degree[b] += 1
        push!(neighbors[a],b)
        push!(neighbors[b],a)
    end
    order = sort(collect(1:n),by=v->(-degree[v],v))
    colors = zeros(Int,n)
    for vertex in order
        used = Set(colors[n] for n in neighbors[vertex] if colors[n] != 0)
        candidate = 1
        while candidate in used
            candidate += 1
        end
        colors[vertex] = candidate
    end
    colors
end
solved_statistics() = Dict("decisions"=>0,"propagations"=>0,"conflicts"=>0,"max_depth"=>0)
function accumulate_stats!(destination,source)
    for key in ("decisions","propagations","conflicts")
        destination[key] += source[key]
    end
    destination["max_depth"] = max(destination["max_depth"],source["max_depth"])
end
function solve_formula(variables,clauses,limit)
    preparation = preprocess(variables,clauses,limit == 1)
    models = BitVector[]
    stats = solved_statistics()
    rounds = 0
    trace = String[]
    blocking = Vector{Int}[]
    stop = "preprocess"
    if isnothing(preparation.empty_clause)
        stop = "limit"
        while length(models) < limit
            rounds += 1
            model,events,counters = run_round(variables,vcat(preparation.clauses,blocking))
            rounds == 1 && (trace=events)
            accumulate_stats!(stats,counters)
            if isnothing(model)
                stop = "all"
                break
            end
            for (variable,value) in preparation.fixed
                model[variable] = value
            end
            push!(models,model)
            push!(blocking,[model[v] ? -v : v for v in preparation.active])
        end
    end
    record(
        variables=variables,
        clauses=clauses,
        models=models,
        status=isempty(models) ? "UNSAT" : "SAT",
        rounds=rounds,
        stop=stop,
        trace=trace,
        stats=stats,
        preparation=preparation,
        removed=preparation.counts["removed"]
    )
end
true_literal(model,literal) = literal > 0 ? model[abs(literal)] : !model[abs(literal)]
satisfies(model,clauses) = all(any(true_literal(model,literal) for literal in clause) for clause in clauses)
function analyze_models(solution)
    models,clauses = solution[:models],solution[:clauses]
    isempty(models) && return nothing
    failure = nothing
    for (i,model) in enumerate(models)
        for (j,clause) in enumerate(clauses)
            if !any(true_literal(model,literal) for literal in clause)
                failure = (i,j)
                break
            end
        end
        !isnothing(failure) && break
    end
    first_model = models[1]
    distribution = [sum(true_literal(first_model,literal) for literal in clause;init=0) for clause in clauses]
    safe = Int[]
    for variable in eachindex(first_model)
        inverted = copy(first_model)
        inverted[variable] = !inverted[variable]
        satisfies(inverted,clauses) && push!(safe,variable)
    end
    diversity = [count(models[i] .!= models[j]) for i in eachindex(models) for j in i+1:length(models)]
    backbone = [first_model[v] ? v : -v for v in eachindex(first_model) if all(model[v] == first_model[v] for model in models)]
    (failure=failure,true_distribution=distribution,safe=safe,diversity=diversity,backbone=backbone)
end
function unsat_core(variables,clauses)
    remaining = Set(eachindex(clauses))
    decisions,conflicts = 0,0
    for removed in eachindex(clauses)
        candidates = [clause for (
            number,
            clause
        ) in enumerate(clauses) if number in remaining && number != removed]
        test = solve_formula(variables,candidates,1)
        decisions += test[:stats]["decisions"]
        conflicts += test[:stats]["conflicts"]
        test[:status] == "UNSAT" && delete!(remaining,removed)
    end
    (clauses=sort(collect(remaining)),decisions=decisions,conflicts=conflicts)
end
function execute_chromatic!(job,graphs)
    graph = graphs[job[:args][1]]
    attempts = Dict{Symbol,Any}[]
    stats = solved_statistics()
    rounds,removed = 0,0
    for colors in 1:parse(Int,job[:args][2])
        count,clauses = coloring(graph,colors)
        solution = solve_formula(count,clauses,1)
        solution[:colors] = colors
        push!(attempts,solution)
        accumulate_stats!(stats,solution[:stats])
        rounds += solution[:rounds]
        removed += solution[:removed]
        solution[:status] == "SAT" && break
    end
    solution = last(attempts)
    merge!(
        job,
        record(
            attempts=attempts,
            chromatic=solution[:status] == "SAT" ? solution[:colors] : nothing,
            solution=solution,
            aggregate_stats=stats,
            aggregate_rounds=rounds,
            aggregate_removed=removed,
            colors=solution[:colors],
            graph=graph
        )
    )
end
function execute_standard!(job,graphs)
    command,args = job[:command],job[:args]
    if command in ("SOLVE","ENUM","CORE")
        variables,clauses = read_dimacs(args[1])
        limit = command == "ENUM" ? parse(Int,args[2]) : 1
    elseif command == "QUEENS"
        variables,clauses = queens(parse(Int,args[1]))
        limit = parse(Int,args[2])
    elseif command == "PIGEON"
        variables,clauses = pigeon(parse(Int,args[1]),parse(Int,args[2]))
        limit = parse(Int,args[3])
    else
        job[:graph],job[:colors] = graphs[args[1]],parse(Int,args[2])
        variables,clauses = coloring(job[:graph],job[:colors])
        limit = parse(Int,args[3])
    end
    solution = solve_formula(variables,clauses,limit)
    merge!(
        job,
        record(
            solution=solution,
            aggregate_stats=solution[:stats],
            aggregate_rounds=solution[:rounds],
            aggregate_removed=solution[:removed]
        )
    )
    command == "CORE" && solution[:status] == "UNSAT" && (job[:core]=unsat_core(variables,clauses))
end
function execute_jobs!(jobs,graphs)
    for job in jobs
        error = validate_job(job,graphs)
        if !isnothing(error)
            job[:error] = error
            continue
        end
        try
            job[:command] == "CHROMATIC" ? execute_chromatic!(job,graphs) : execute_standard!(job,graphs)
        catch error
            error isa InputError || rethrow()
            job[:error] = error.reason
            continue
        end
        job[:analysis] = analyze_models(job[:solution])
    end
end
function graph_summary(graph)
    degree = zeros(Int,graph[:vertices])
    for (a,b) in graph[:edges]
        degree[a] += 1
        degree[b] += 1
    end
    named(
        vertices=graph[:vertices],
        edges=length(graph[:edges]),
        max_degree=maximum(degree),
        greedy=maximum(greedy_coloring(graph))
    )
end
function preprocessing_report(preparation)
    counts,records = preparation.counts,preparation.records
    lines = [
        "preprocess "*named(
            pure=preparation.pure ? "on" : "off",
            tautologies=counts["tautologies"],
            duplicate_literals=counts["duplicate_literals"],
            unit_fixed=counts["unit_fixed"],
            unit_removed=counts["unit_removed"],
            subsumed=counts["subsumed"],
            pure_fixed=counts["pure_fixed"],
            pure_removed=counts["pure_removed"],
            removed=counts["removed"]
        ),
        "removed_clauses "*named(
            tautology=number_list(records["tautology"]),
            unit=number_list(records["unit"]),
            subsumed=number_list(records["subsumed"]),
            pure=number_list(records["pure"])
        )
    ]
    if !isnothing(preparation.empty_clause)
        push!(lines,"simplified empty_clause=$(preparation.empty_clause)")
    else
        lengths = length.(preparation.clauses)
        push!(
            lines,
            "simplified "*named(
                clauses=length(lengths),
                literals=sum(lengths),
                lengths=frequency(lengths),
                fixed=length(preparation.fixed),
                active=length(preparation.active)
            )
        )
        fixed = [preparation.fixed[v] ? v : -v for v in sort(collect(keys(preparation.fixed)))]
        push!(lines,"fixed literals="*number_list(fixed))
    end
    lines
end
search_report(stats) = "search "*named(
    decisions=stats["decisions"],
    propagations=stats["propagations"],
    conflicts=stats["conflicts"],
    max_depth=stats["max_depth"]
)
function verification_report(solution,analysis)
    isnothing(analysis) && return String[]
    !isnothing(analysis.failure) && return ["verify failed model=$(analysis.failure[1]) clause=$(analysis.failure[2])"]
    ["verify ok "*named(
        models=length(solution[:models]),
        clauses=length(solution[:clauses]),
        true_literals=frequency(analysis.true_distribution)
    )]
end
function analysis_report(solution,analysis)
    isnothing(analysis) && return String[]
    lines = ["flips "*named(safe=length(analysis.safe),variables=number_list(analysis.safe))]
    distances = analysis.diversity
    !isempty(distances) && push!(
        lines,
        "diversity "*named(
            pairs=length(distances),
            min_distance=minimum(distances),
            max_distance=maximum(distances)
        )
    )
    solution[:stop] == "all" && push!(
        lines,
        "backbone "*named(size=length(analysis.backbone),literals=number_list(analysis.backbone))
    )
    lines
end
function trace_report(events)
    isempty(events) && return "trace -"
    shown = events[1:min(12,length(events))]
    "trace "*join(shown,' ')*(length(events) > 12 ? " +$(length(events)-12)" : "")
end
function standard_result(job)
    solution = job[:solution]
    lines = [heading(job)]
    job[:command] == "COLOR" && push!(lines,"graph "*graph_summary(job[:graph]))
    lengths = length.(solution[:clauses])
    push!(
        lines,
        "formula "*named(
            variables=solution[:variables],
            clauses=length(lengths),
            literals=sum(lengths),
            lengths=frequency(lengths)
        )
    )
    append!(lines,preprocessing_report(solution[:preparation]))
    push!(
        lines,
        "result $(solution[:status]) "*named(
            models=length(solution[:models]),
            rounds=solution[:rounds],
            stop=solution[:stop]
        )
    )
    push!(lines,search_report(solution[:stats]))
    solution[:rounds] > 0 && push!(lines,trace_report(solution[:trace]))
    append!(lines,verification_report(solution,job[:analysis]))
    append!(lines,analysis_report(solution,job[:analysis]))
    if haskey(job,:core)
        core = job[:core]
        push!(
            lines,
            "core "*named(
                size=length(core.clauses),
                decisions=core.decisions,
                conflicts=core.conflicts,
                clauses=number_list(core.clauses)
            )
        )
    end
    lines
end
function chromatic_result(job)
    lines = [heading(job),"graph "*graph_summary(job[:graph])]
    for attempt in job[:attempts]
        stats = attempt[:stats]
        push!(
            lines,
            "attempt "*named(
                k=attempt[:colors],
                clauses=length(attempt[:clauses]),
                removed=attempt[:removed],
                result=attempt[:status],
                stop=attempt[:stop],
                decisions=stats["decisions"],
                propagations=stats["propagations"],
                conflicts=stats["conflicts"],
                max_depth=stats["max_depth"]
            )
        )
    end
    chromatic = isnothing(job[:chromatic]) ? "-" : string(job[:chromatic])
    push!(lines,"result $(job[:solution][:status]) chromatic=$chromatic attempts=$(length(job[:attempts]))")
    push!(lines,search_report(job[:aggregate_stats]))
    if job[:solution][:status] == "SAT"
        append!(lines,verification_report(job[:solution],job[:analysis]))
        safe = job[:analysis].safe
        push!(lines,"flips "*named(safe=length(safe),variables=number_list(safe)))
    end
    lines
end
valid_jobs(jobs) = filter(job->!haskey(job,:error),jobs)
function results_summary(jobs)
    valid = valid_jobs(jobs)
    sat = count(job->job[:solution][:status] == "SAT",valid)
    lines = ["SUMMARY "*named(
        jobs=length(jobs),
        sat=sat,
        unsat=length(valid)-sat,
        error=length(jobs)-length(valid)
    )]
    totals = [
        sum(length(job[:solution][:models]) for job in valid;init=0),
        sum(job[:aggregate_rounds] for job in valid;init=0)
    ]
    push!(
        lines,
        "totals "*named(
            models=totals[1],
            rounds=totals[2],
            decisions=sum(job[:aggregate_stats]["decisions"] for job in valid;init=0),
            propagations=sum(job[:aggregate_stats]["propagations"] for job in valid;init=0),
            conflicts=sum(job[:aggregate_stats]["conflicts"] for job in valid;init=0),
            removed_clauses=sum(job[:aggregate_removed] for job in valid;init=0)
        )
    )
    for command in COMMANDS
        members = filter(job->job[:command] == command,valid)
        isempty(members) && continue
        sat = count(job->job[:solution][:status] == "SAT",members)
        push!(
            lines,
            "command $command "*named(
                jobs=length(members),
                sat=sat,
                unsat=length(members)-sat,
                decisions=sum(job[:aggregate_stats]["decisions"] for job in members),
                propagations=sum(job[:aggregate_stats]["propagations"] for job in members),
                conflicts=sum(job[:aggregate_stats]["conflicts"] for job in members)
            )
        )
    end
    for (label,key) in (("hardest","conflicts"),("deepest","max_depth"),("busiest","propagations"))
        isempty(valid) && break
        job = first(sort(valid,by=job->(-job[:aggregate_stats][key],job[:number])))
        push!(lines,"$label job=$(job[:number]) $key=$(job[:aggregate_stats][key])")
    end
    lines
end
function classes_for_models(columns,canonicalize)
    table = Dict{Tuple,Dict{Symbol,Any}}()
    classes = Dict{Symbol,Any}[]
    assignments = Any[]
    for (index,value) in enumerate(columns)
        canonical,orbit = canonicalize(value)
        if !haskey(table,canonical)
            group = record(number=length(classes)+1,first=index,found=0,canonical=canonical,orbit=orbit)
            table[canonical] = group
            push!(classes,group)
        end
        group = table[canonical]
        group[:found] += 1
        push!(assignments,(value,group[:number],index == group[:first]))
    end
    assignments,classes
end
function queens_boards(job)
    n = parse(Int,job[:args][1])
    solution = job[:solution]
    columns = [positions(model,n,n) for model in solution[:models]]
    canonical(cols) = (variants=queens_symmetries(cols); (minimum(variants),length(unique(variants))))
    assignments,classes = classes_for_models(columns,canonical)
    lines = ["QUEENS job=$(job[:number]) n=$n"]
    for (index,(value,group,is_first)) in enumerate(assignments)
        push!(lines,"solution $index columns=$(number_list(value)) class=$group")
        is_first && append!(lines,queens_board(value))
    end
    for group in classes
        push!(
            lines,
            "class $(group[:number]) "*named(
                orbit=group[:orbit],
                found=group[:found],
                first=group[:first],
                canonical=number_list(group[:canonical])
            )
        )
    end
    push!(
        lines,
        "summary "*named(solutions=length(solution[:models]),stop=solution[:stop],classes=length(classes))
    )
    lines
end
function pigeon_boards(job)
    p,h = parse.(Int,job[:args][1:2])
    solution = job[:solution]
    lines = ["PIGEON job=$(job[:number]) pigeons=$p holes=$h"]
    for (index,model) in enumerate(solution[:models])
        places = positions(model,p,h)
        empty = [hole for hole in 1:h if !(hole in places)]
        push!(lines,"assignment $index holes=$(number_list(places)) empty=$(number_list(empty))")
    end
    expected = p > h ? 0 : prod(h:-1:h-p+1)
    push!(
        lines,
        "summary "*named(assignments=length(solution[:models]),stop=solution[:stop],expected=expected)
    )
    lines
end
function coloring_boards(job)
    graph,colors,solution = job[:graph],job[:colors],job[:solution]
    decoded = [positions(model,graph[:vertices],colors) for model in solution[:models]]
    assignments,classes = classes_for_models(decoded,value->(canonical_coloring(value),nothing))
    lines = ["$(job[:command]) job=$(job[:number]) graph=$(graph[:name]) vertices=$(graph[:vertices]) edges=$(length(graph[:edges])) colors=$colors"]
    greedy = greedy_coloring(graph)
    push!(lines,"greedy used=$(maximum(greedy)) colors=$(number_list(greedy))")
    for (index,(value,group,_)) in enumerate(assignments)
        sizes = [count(==(color),value) for color in 1:colors]
        push!(
            lines,
            "coloring $index colors=$(number_list(value)) used=$(length(unique(value))) sizes=$(number_list(sizes)) class=$group"
        )
    end
    for group in classes
        push!(
            lines,
            "class $(group[:number]) found=$(group[:found]) first=$(group[:first]) canonical=$(number_list(group[:canonical]))"
        )
    end
    push!(
        lines,
        "summary "*named(colorings=length(solution[:models]),stop=solution[:stop],classes=length(classes))
    )
    lines
end
function main()
    graphs,jobs = load_graphs(),load_jobs()
    execute_jobs!(jobs,graphs)
    results,models,boards = Vector{String}[],Vector{String}[],Vector{String}[]
    stats = ["job,command,status,variables,clauses,removed_clauses,decisions,propagations,conflicts,max_depth,models,rounds"]
    for job in jobs
        if haskey(job,:error)
            push!(results,[heading(job),"error "*job[:error]])
            continue
        end
        push!(results,job[:command] == "CHROMATIC" ? chromatic_result(job) : standard_result(job))
        solution = job[:solution]
        if !isempty(solution[:models])
            lines = [heading(job)]
            for (number,model) in enumerate(solution[:models])
                push!(lines,"model $number")
                append!(lines,model_lines(model))
            end
            push!(models,lines)
        end
        if job[:command] == "QUEENS"
            push!(boards,queens_boards(job))
        elseif job[:command] == "PIGEON"
            push!(boards,pigeon_boards(job))
        elseif job[:command] in ("COLOR","CHROMATIC")
            push!(boards,coloring_boards(job))
        end
        counters = job[:aggregate_stats]
        row = (
            job[:number],
            job[:command],
            solution[:status],
            solution[:variables],
            length(solution[:clauses]),
            job[:aggregate_removed],
            counters["decisions"],
            counters["propagations"],
            counters["conflicts"],
            counters["max_depth"],
            length(solution[:models]),
            job[:aggregate_rounds]
        )
        push!(stats,join(row,','))
    end
    push!(results,results_summary(jobs))
    save_paragraphs("results.txt",results)
    save_paragraphs("models.txt",models)
    save_paragraphs("boards.txt",boards)
    save_lines("stats.csv",stats)
end
main()
