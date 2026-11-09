include("instance.jl")
include("minstd.jl")
include("dispatch_rules.jl")
include("genetic.jl")
include("gantt.jl")

const RULES = ("SPT","LPT","MWKR","FIFO")
percentage(a,b) = (t=(2000a+b)÷(2b); "$(t÷10).$(t%10)%")
job_letter(j) = Char(Int('A')+j-1)
parameter(params,key) = parse(Int,only(params[key]))
probability(params,key) = parse.(Int,split(only(params[key]),'/'))
makespan(starts,durations) = maximum(starts .+ durations)
function jackson_bound(instance,machine)
    tasks = instance.operations[machine.operations]
    remaining = [op.duration for op in tasks]
    time,bound = 0,0
    while any(>(0),remaining)
        pending = findall(>(0),remaining)
        all(tasks[i].head > time for i in pending) && (time=minimum(tasks[i].head for i in pending))
        released = [i for i in pending if tasks[i].head <= time]
        selected = released[argmin([(-tasks[i].tail,tasks[i].job) for i in released])]
        later = [op.head for op in tasks if op.head > time]
        step = isempty(later) ? remaining[selected] : min(remaining[selected],minimum(later)-time)
        time += step
        remaining[selected] -= step
        remaining[selected] == 0 && (bound=max(bound,time+tasks[selected].tail))
    end
    bound
end
function order_starts(instance,order,durations=instance.durations)
    starts = fill(-1,length(durations))
    completions = zeros(Int,length(durations))
    positions = ones(Int,instance.machine_count)
    placed = 0
    while placed < length(durations)
        for (m,sequence) in enumerate(order)
            while positions[m] <= length(sequence)
                position = positions[m]
                id = sequence[position]
                previous = instance.operations[id].job_prev
                previous != 0 && starts[previous] == -1 && break
                ready = previous == 0 ? 0 : completions[previous]
                free = position == 1 ? 0 : completions[sequence[position-1]]
                starts[id] = max(ready,free)
                completions[id] = starts[id]+durations[id]
                positions[m] += 1
                placed += 1
            end
        end
    end
    starts
end
function schedule(instance,starts)
    completions = starts .+ instance.durations
    by_start = sortperm(eachindex(starts),by=i->(starts[i],i))
    order = [Int[] for _ in 1:instance.machine_count]
    for id in by_start
        push!(order[instance.operations[id].machine],id)
    end
    previous,following = zeros(Int,length(starts)),zeros(Int,length(starts))
    for sequence in order, i in 2:length(sequence)
        previous[sequence[i]] = sequence[i-1]
        following[sequence[i-1]] = sequence[i]
    end
    (
        instance=instance,
        starts=starts,
        completions=completions,
        makespan=maximum(completions),
        by_start=by_start,
        order=order,
        machine_prev=previous,
        machine_next=following
    )
end
schedule_of_order(instance,order) = schedule(instance,order_starts(instance,order))
function critical_path(s)
    current = findfirst(==(s.makespan),s.completions)
    path = [current]
    while s.starts[current] != 0
        previous = s.machine_prev[current]
        current = previous != 0 && s.completions[previous] == s.starts[current] ? previous : s.instance.operations[current].job_prev
        push!(path,current)
    end
    reverse!(path)
end
function path_blocks(s,path=critical_path(s))
    blocks = Vector{Int}[]
    for id in path
        if !isempty(blocks) && s.instance.operations[blocks[end][end]].machine == s.instance.operations[id].machine
            push!(blocks[end],id)
        else
            push!(blocks,[id])
        end
    end
    blocks
end
moves(s) = [(block[i-1],block[i]) for block in path_blocks(s) for i in 2:length(block)]
function path_count(s)
    ways = zeros(Int,length(s.starts))
    for id in s.by_start
        if s.starts[id] == 0
            ways[id] = 1
        else
            for source in (s.instance.operations[id].job_prev,s.machine_prev[id])
                source != 0 && s.completions[source] == s.starts[id] && (ways[id]+=ways[source])
            end
        end
    end
    sum(ways[s.completions .== s.makespan])
end
function left_shift(s,id)
    op = s.instance.operations[id]
    sequence = s.order[op.machine]
    position = findfirst(==(id),sequence)
    ready = op.job_prev == 0 ? 0 : s.completions[op.job_prev]
    for insertion in 1:(position-1)
        begin_time = insertion == 1 ? 0 : s.completions[sequence[insertion-1]]
        start = max(begin_time,ready)
        start+op.duration <= s.starts[sequence[insertion]] && return (start,insertion)
    end
    nothing
end
function slacks(s)
    latest,slack,free = zeros(Int,length(s.starts)),zeros(Int,length(s.starts)),zeros(Int,length(s.starts))
    for id in reverse(s.by_start)
        successors = filter(!=(0),[s.instance.operations[id].job_next,s.machine_next[id]])
        latest[id] = (isempty(successors) ? s.makespan : minimum(latest[successors]))-s.instance.durations[id]
        slack[id] = latest[id]-s.starts[id]
        free[id] = (isempty(successors) ? s.makespan : minimum(s.starts[successors]))-s.completions[id]
    end
    slack,free
end
path_counts(s,path=critical_path(s)) = [count(
    id->s.instance.operations[id].machine == m,
    path
) for m in 1:s.instance.machine_count]
bottleneck(s,path=critical_path(s)) = argmax(path_counts(s,path))
chromosome(s) = [s.instance.operations[id].job for id in s.by_start]
flow_time(s) = sum(s.completions[j.operations[end]] for j in s.instance.jobs)
total_idle(s) = s.instance.machine_count*s.makespan-sum(s.instance.durations)
utilization(s,machine) = percentage(machine.load,s.makespan)
letters(s,m) = join(job_letter(s.instance.operations[id].job) for id in s.order[m])
function apply_move(instance,order,move)
    result = copy.(order)
    a,b = move
    sequence = result[instance.operations[a].machine]
    position = findfirst(==(a),sequence)
    sequence[position],sequence[position+1] = b,a
    result
end
function machine_distances(first,second)
    distances = Int[]
    for (a,b) in zip(first.order,second.order)
        rank = Dict(id=>i for (i,id) in enumerate(b))
        push!(distances,sum((rank[a[i]] > rank[a[j]] for i in eachindex(a) for j in (i+1):length(a));init=0))
    end
    distances
end
function tabu_search(instance,start_order,iterations,tenure)
    current = copy.(start_order)
    best_order = copy.(current)
    start_value = makespan(order_starts(instance,current),instance.durations)
    best,found = start_value,0
    records = NamedTuple[]
    expiry = Dict{Tuple{Int,Int},Int}()
    reason = "limit"
    for iteration in 1:iterations
        neighborhood = moves(schedule_of_order(instance,current))
        if isempty(neighborhood)
            reason = "no_moves"
            break
        end
        values = [makespan(
            order_starts(instance,apply_move(instance,current,move)),
            instance.durations
        ) for move in neighborhood]
        tabu = [get(expiry,move,0) >= iteration for move in neighborhood]
        selectable = [i for i in eachindex(values) if !tabu[i] || values[i] < best]
        if isempty(selectable)
            reason = "all_tabu"
            break
        end
        chosen = selectable[argmin([(values[i],i) for i in selectable])]
        a,b = neighborhood[chosen]
        current = apply_move(instance,current,(a,b))
        expiry[(b,a)] = iteration+tenure
        if values[chosen] < best
            best_order,best,found = copy.(current),values[chosen],iteration
        end
        push!(
            records,
            (
                iteration=iteration,
                move_count=length(neighborhood),
                tabu_count=count(tabu),
                move=(a,b),
                aspiration=tabu[chosen],
                value=values[chosen],
                best=best
            )
        )
    end
    (
        start_value=start_value,
        best_order=best_order,
        best_value=best,
        found=found,
        records=records,
        reason=reason,
        iterations=iterations,
        tenure=tenure
    )
end
function activate(instance,order)
    current = copy.(order)
    shifts = NamedTuple[]
    while true
        s = schedule_of_order(instance,current)
        found = false
        for id in s.by_start
            shift = left_shift(s,id)
            isnothing(shift) && continue
            start,insertion = shift
            sequence = current[instance.operations[id].machine]
            deleteat!(sequence,findfirst(==(id),sequence))
            insert!(sequence,insertion,id)
            push!(shifts,(ident=id,old_start=s.starts[id],new_start=start))
            found = true
            break
        end
        !found && return (current,shifts)
    end
end
function genetic_algorithm(instance,params,seeds)
    rng = Minstd(parameter(params,"seed"))
    population = copy.(seeds)
    p,g,e,k = (parameter(params,key) for key in ("population","generations","elitism","tournament"))
    checkpoints = parse.(Int,params["checkpoints"])
    while length(population) < p
        push!(population,shuffle_genes!(rng,[job.number for job in instance.jobs for _ in job.operations]))
    end
    records,progress = Tuple{Int,Int,Int}[],NamedTuple[]
    crossovers,swaps,inserts = 0,0,0
    previous_best = typemax(Int)
    values = Int[]
    for generation in 0:g
        values = [makespan(decode(instance,c),instance.durations) for c in population]
        ranking = sortperm(eachindex(values),by=i->(values[i],i))
        best = ranking[1]
        values[best] < previous_best && push!(records,(generation,values[best],best))
        previous_best = values[best]
        if generation in checkpoints
            total = sum(values)
            divisor = gcd(total,p)
            push!(
                progress,
                (
                    generation=generation,
                    best=minimum(values),
                    mean="$(total÷divisor)/$(p÷divisor)",
                    worst=maximum(values),
                    distinct=length(Set(Tuple(c) for c in population))
                )
            )
        end
        generation == g && break
        offspring = [copy(population[i]) for i in ranking[1:e]]
        for _ in 1:((p-e)÷2)
            first = population[tournament!(rng,values,k)]
            second = population[tournament!(rng,values,k)]
            if chance!(rng,probability(params,"crossover"))
                crossovers += 1
                children = crossover!(rng,first,second,[job.number for job in instance.jobs])
            else
                children = (copy(first),copy(second))
            end
            for child in children
                if chance!(rng,probability(params,"swap_mutation"))
                    swaps += 1
                    swap_mutation!(rng,child)
                end
                if chance!(rng,probability(params,"insert_mutation"))
                    inserts += 1
                    insert_mutation!(rng,child)
                end
                push!(offspring,child)
            end
        end
        population = offspring
    end
    ranking = sortperm(eachindex(values),by=i->(values[i],i))
    seen,top = Set{Tuple}(),Int[]
    for i in ranking
        key = Tuple(population[i])
        if !(key in seen)
            push!(seen,key)
            push!(top,i)
            length(top) == 5 && break
        end
    end
    (
        population=population,
        values=values,
        records=records,
        progress=progress,
        crossovers=crossovers,
        swaps=swaps,
        inserts=inserts,
        best_index=ranking[1],
        top=top
    )
end
function solve(instance,params)
    iterations,tenure = parameter(params,"tabu_iterations"),parameter(params,"tabu_tenure")
    jacksons = [jackson_bound(instance,m) for m in instance.machines]
    job_bound = argmax([j.work for j in instance.jobs])
    machine_bound = argmax([m.bound for m in instance.machines])
    jackson_index = argmax(jacksons)
    lower_bound = max(
        instance.jobs[job_bound].work,
        instance.machines[machine_bound].bound,
        jacksons[jackson_index]
    )
    baselines = NamedTuple[]
    for rule in RULES
        starts,decisions,ties = giffler_thompson(instance,rule)
        s = schedule(instance,starts)
        push!(
            baselines,
            (
                rule=rule,
                schedule=s,
                decisions=decisions,
                ties=ties,
                path=critical_path(s),
                search=tabu_search(instance,s.order,iterations,tenure)
            )
        )
    end
    ga = genetic_algorithm(instance,params,[chromosome(b.schedule) for b in baselines])
    genes = ga.population[ga.best_index]
    ga_schedule = schedule(instance,decode(instance,genes))
    positions = zeros(Int,length(instance.operations))
    for (position,id) in enumerate(gene_operations(instance,genes))
        positions[id] = position
    end
    starts,active_decisions,_ = giffler_thompson(instance,"GENES",positions)
    activated,shifts = activate(instance,ga_schedule.order)
    search = tabu_search(instance,activated,iterations,tenure)
    (
        instance=instance,
        params=params,
        jacksons=jacksons,
        job_bound=job_bound,
        machine_bound=machine_bound,
        jackson_index=jackson_index,
        lower_bound=lower_bound,
        baselines=baselines,
        genetic=ga,
        ga_schedule=ga_schedule,
        active_makespan=makespan(starts,instance.durations),
        active_decisions=active_decisions,
        activated_value=search.start_value,
        shifts=shifts,
        search=search,
        final=schedule_of_order(instance,search.best_order)
    )
end
function baseline_lines(solver)
    instance,lb = solver.instance,solver.lower_bound
    lines = ["INSTANCE jobs $(length(instance.jobs)) machines $(instance.machine_count) operations $(length(instance.operations)) work $(sum(instance.durations)) errors $(length(instance.errors))"]
    append!(lines,["ERROR $error" for error in instance.errors])
    for job in instance.jobs
        route = join(("M$(instance.operations[id].machine)" for id in job.operations),' ')
        push!(lines,"JOB J$(job.number) operations $(length(job.operations)) work $(job.work) route $route")
    end
    for (m,jackson) in zip(instance.machines,solver.jacksons)
        push!(
            lines,
            "MACHINE M$(m.number) operations $(length(m.operations)) load $(m.load) head $(m.head) tail $(m.tail) bound $(m.bound) jackson $jackson"
        )
    end
    job,machine = instance.jobs[solver.job_bound],instance.machines[solver.machine_bound]
    push!(
        lines,
        "BOUND job $(job.work) J$(job.number)",
        "BOUND machine $(machine.bound) M$(machine.number)",
        "BOUND jackson $(solver.jacksons[solver.jackson_index]) M$(solver.jackson_index)",
        "BOUND lower $lb"
    )
    for b in solver.baselines
        s,search = b.schedule,b.search
        push!(
            lines,
            "RULE $(b.rule) makespan $(s.makespan) gap $(percentage(s.makespan-lb,lb)) flow $(flow_time(s)) idle $(total_idle(s)) decisions $(b.decisions) ties $(b.ties)",
            "PATH $(b.rule) operations $(length(b.path)) blocks $(length(path_blocks(s,b.path))) critical_paths $(path_count(s)) bottleneck M$(bottleneck(s,b.path))",
            "TABU $(b.rule) makespan $(s.makespan) -> $(search.best_value) found $(search.found) iterations $(length(search.records)) stop $(search.reason)"
        )
    end
    best = solver.baselines[argmin([b.schedule.makespan for b in solver.baselines])]
    push!(lines,"BEST $(best.rule) makespan $(best.schedule.makespan)")
    for m in instance.machines
        push!(
            lines,
            "UTILIZATION M$(m.number) "*join(
                ("$(b.rule) $(utilization(b.schedule,m))" for b in solver.baselines),
                ' '
            )
        )
    end
    lines
end
progress_lines(solver) = vcat(
    ["generation,best,mean,worst,distinct"],
    ["$(p.generation),$(p.best),$(p.mean),$(p.worst),$(p.distinct)" for p in solver.genetic.progress]
)
function gantt_lines(solver,path)
    instance,s = solver.instance,solver.final
    scale,columns = chart_scale(s.makespan,parameter(solver.params,"gantt_width"))
    machine_intervals = [Tuple{Int,Int,Char}[] for _ in instance.machines]
    for op in instance.operations
        letter = job_letter(op.job)
        mark = op.id in path ? lowercase(letter) : letter
        push!(machine_intervals[op.machine],(s.starts[op.id],s.completions[op.id],mark))
    end
    lines = ["GANTT scale $scale columns $columns",time_row(scale,columns),rule_row(columns)]
    for m in instance.machines
        push!(lines,chart_row("M$(m.number)",machine_intervals[m.number],scale,columns))
    end
    push!(lines,busy_row(machine_intervals,scale,columns))
    for job in instance.jobs
        intervals = [(
            s.starts[id],
            s.completions[id],
            Char(Int('0')+instance.operations[id].machine%10)
        ) for id in job.operations]
        push!(lines,chart_row("J$(job.number)",intervals,scale,columns))
    end
    lines
end
function schedule_lines(solver)
    instance,s,ga = solver.instance,solver.final,solver.genetic
    ops,lb = instance.operations,solver.lower_bound
    lines = ["GA best $(solver.ga_schedule.makespan) generation $(ga.records[end][1]) crossovers $(ga.crossovers) swaps $(ga.swaps) inserts $(ga.inserts)"]
    for (generation,value,individual) in ga.records
        push!(lines,"RECORD generation $generation makespan $value individual $individual")
    end
    for (rank,index) in enumerate(ga.top)
        other = schedule(instance,decode(instance,ga.population[index]))
        push!(
            lines,
            "TOP $rank individual $index makespan $(ga.values[index]) distance $(sum(machine_distances(other,solver.ga_schedule)))"
        )
    end
    push!(
        lines,
        "GA_CHROMOSOME "*join(ga.population[ga.best_index],' '),
        "ACTIVE_DECODE makespan $(solver.active_makespan) decisions $(solver.active_decisions)"
    )
    for (number,shift) in enumerate(solver.shifts)
        op = ops[shift.ident]
        push!(lines,"SHIFT $number $(op.code) M$(op.machine) start $(shift.old_start) -> $(shift.new_start)")
    end
    push!(
        lines,
        "ACTIVATED makespan $(solver.ga_schedule.makespan) -> $(solver.activated_value) shifts $(length(solver.shifts))",
        "SCHEDULE makespan $(s.makespan) lower_bound $lb gap $(percentage(s.makespan-lb,lb)) improvement $(solver.ga_schedule.makespan-s.makespan) shiftable $(count(id->!isnothing(left_shift(s,id)),eachindex(ops)))",
        "CHROMOSOME "*join(chromosome(s),' '),
        "LEGEND "*join(("$(job_letter(j.number))=J$(j.number)" for j in instance.jobs),' ')
    )
    append!(lines,gantt_lines(solver,critical_path(s)))
    for m in instance.machines
        push!(
            lines,
            "ORDER M$(m.number) FINAL $(letters(s,m.number)) "*join(
                ("$(b.rule) $(letters(b.schedule,m.number))" for b in solver.baselines),
                ' '
            )
        )
    end
    for m in instance.machines
        sequence = s.order[m.number]
        gaps = [s.starts[sequence[i]]-s.completions[sequence[i-1]] for i in 2:length(sequence) if s.starts[sequence[i]] > s.completions[sequence[i-1]]]
        text = join(("J$(ops[id].job):$(s.starts[id])-$(s.completions[id])" for id in sequence),' ')
        push!(
            lines,
            "MACHINE M$(m.number) load $(m.load) idle $(s.makespan-m.load) utilization $(utilization(s,m)) gaps $(length(gaps)) longest_gap $(maximum(gaps;init=0)) sequence $text"
        )
        intervals = vcat(
            [(0,s.starts[sequence[1]])],
            [(s.completions[sequence[i-1]],s.starts[sequence[i]]) for i in 2:length(sequence)],
            [(s.completions[sequence[end]],s.makespan)]
        )
        filter!(pair->pair[2] > pair[1],intervals)
        idle = isempty(intervals) ? "none" : join(("$a-$b" for (a,b) in intervals),' ')
        push!(lines,"IDLE M$(m.number) $idle")
    end
    waiting_total = 0
    for job in instance.jobs
        completion = s.completions[job.operations[end]]
        waiting = completion-job.work
        waiting_total += waiting
        push!(
            lines,
            "JOB J$(job.number) operations $(length(job.operations)) work $(job.work) start $(s.starts[job.operations[1]]) completion $completion waiting $waiting"
        )
    end
    push!(lines,"TOTAL flow $(flow_time(s)) waiting $waiting_total idle $(total_idle(s))")
    others = vcat([b.schedule for b in solver.baselines],[solver.ga_schedule])
    labels = (RULES...,"GA")
    distances = [machine_distances(s,other) for other in others]
    pairs_total = 0
    for m in instance.machines
        q = length(m.operations)
        pairs = q*(q-1)÷2
        pairs_total += pairs
        push!(
            lines,
            "DISTANCE M$(m.number) pairs $pairs "*join(
                ("$(labels[i]) $(distances[i][m.number])" for i in eachindex(labels)),
                ' '
            )
        )
    end
    push!(
        lines,
        "DISTANCE total pairs $pairs_total "*join(
            ("$(labels[i]) $(sum(distances[i]))" for i in eachindex(labels)),
            ' '
        )
    )
    lines
end
function path_lines(solver)
    instance,s,search = solver.instance,solver.final,solver.search
    ops = instance.operations
    lines = ["SEARCH start $(search.start_value) iterations $(search.iterations) tenure $(search.tenure)"]
    for r in search.records
        a,b = ops[r.move[1]],ops[r.move[2]]
        kind = r.aspiration ? "aspiration" : "free"
        push!(
            lines,
            "ITER $(r.iteration) moves $(r.move_count) tabu $(r.tabu_count) swap M$(a.machine) $(a.code) $(b.code) $kind makespan $(r.value) best $(r.best)"
        )
    end
    push!(
        lines,
        "STOP iterations $(length(search.records)) reason $(search.reason) best $(search.best_value) found $(search.found)"
    )
    path = critical_path(s)
    blocks = path_blocks(s,path)
    push!(
        lines,
        "PATH operations $(length(path)) blocks $(length(blocks)) makespan $(s.makespan) critical_paths $(path_count(s))"
    )
    for (number,id) in enumerate(path)
        op = ops[id]
        link = number == 1 ? "start" : s.machine_prev[id] == path[number-1] ? "machine" : "job"
        push!(lines,"NODE $number $(op.code) M$(op.machine) $(s.starts[id])-$(s.completions[id]) $link")
    end
    for (number,block) in enumerate(blocks)
        codes = join((ops[id].code for id in block),' ')
        push!(
            lines,
            "BLOCK $number M$(ops[block[1]].machine) $(s.starts[block[1]])-$(s.completions[block[end]]) $codes"
        )
    end
    for (number,move) in enumerate(moves(s))
        a,b = ops[move[1]],ops[move[2]]
        value = makespan(order_starts(instance,apply_move(instance,s.order,move)),instance.durations)
        push!(lines,"NEIGHBOUR $number M$(a.machine) $(a.code) $(b.code) makespan $value")
    end
    slack,free = slacks(s)
    push!(lines,"CRITICAL operations $(count(==(0),slack)) total $(length(ops))")
    for (label,values) in (("SLACK",slack),("FREE",free)),job in instance.jobs
        push!(lines,"$label J$(job.number) "*join(values[job.operations],' '))
    end
    counts = path_counts(s,path)
    for m in instance.machines
        durations = [op.duration+(op.machine == m.number ? cld(op.duration,10) : 0) for op in ops]
        sensitivity = makespan(order_starts(instance,s.order,durations),durations)
        critical = count(id->slack[id] == 0,m.operations)
        push!(
            lines,
            "MACHINE M$(m.number) critical $critical path $(counts[m.number]) sensitivity $sensitivity delta $(sensitivity-s.makespan)"
        )
    end
    machine = argmax(counts)
    push!(lines,"BOTTLENECK M$machine path $(counts[machine])")
    lines
end
function main()
    params = Dict{String,Vector{String}}()
    for line in readlines("input/ga_params.txt")
        fields = String.(split(line))
        params[fields[1]] = fields[2:end]
    end
    solver = solve(load_instance("input/instance.txt"),params)
    mkpath("output")
    for (name,lines) in (
        ("baselines.txt",baseline_lines(solver)),
        ("ga_progress.csv",progress_lines(solver)),
        ("best_schedule.txt",schedule_lines(solver)),
        ("critical_path.txt",path_lines(solver))
    )
        open(joinpath("output",name),"w") do io
            foreach(line->println(io,line),lines)
        end
    end
end
main()
