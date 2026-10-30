include("pddl_parser.jl")
include("grounding.jl")
include("heuristics.jl")
include("search.jl")
include("graphplan.jl")
notation(atom) = "(" * join([atom[1];collect(atom[2])]," ") * ")"
action_text(action) = notation((action.source.name,action.arguments))
number_list(values) = isempty(values) ? "-" : join(sort(collect(values)),",")
headed(heading,items) = heading * " " * (isempty(items) ? "-" : join(items," "))
value_text(value) = value == INFINITY ? "inf" : string(value)
heuristic_text(values) = join([name * "=" * value_text(value) for (name,value) in zip(HEURISTIC_NAMES,values)]," ")
function read_settings(text)
    settings = Dict{String,Any}("runs" => Tuple{String,String}[])
    for row in split(text,'\n')
        (isempty(row) || startswith(row,"#")) && continue
        fields = String.(split(row))
        if fields[1] == "run"
            push!(settings["runs"],(fields[2],fields[3]))
        elseif fields[1] == "repair"
            settings["repair"] = (fields[2],fields[3])
        else
            settings[fields[1]] = parse(Int,fields[2])
        end
    end
    settings
end
function read_candidates(text)
    candidates = Any[]
    current = nothing
    for row in split(text,'\n')
        (isempty(row) || startswith(row,"#")) && continue
        if startswith(row,"plan ")
            fields = String.(split(row))
            current = (number=length(candidates)+1,problem=fields[2],label=fields[3],steps=Any[])
        elseif row == "end"
            push!(candidates,current)
        else
            fields = String.(split(row[2:end-1]))
            push!(current.steps,(fields[1],fields[2:end]))
        end
    end
    candidates
end
function argument_error(domain,arguments,expected,table,noun)
    length(arguments) == length(expected) || return "expected $(length(expected)) arguments, got $(length(arguments))"
    for (i,(argument,kind)) in enumerate(zip(arguments,expected))
        haskey(table,argument) || return "unknown $noun $argument"
        subtype(domain.parents,table[argument],kind) || return "argument $i ($argument) is not of type $kind"
    end
    ""
end
function validate_domain!(domain)
    kept,diagnostics = Any[],String[]
    for action in domain.actions
        error = ""
        for (_,kind) in action.parameters
            if !haskey(domain.parents,kind)
                error = "unknown type " * kind
                break
            end
        end
        if isempty(error)
            parameters = Dict(action.parameters)
            for (_,atom) in [action.condition;action.effects]
                if atom[1] != "=" && !haskey(domain.predicates,atom[1])
                    error = "unknown predicate " * atom[1]
                else
                    expected = atom[1] == "=" ? ["object","object"] : domain.predicates[atom[1]]
                    error = argument_error(domain,atom[2],expected,parameters,"variable")
                end
                if !isempty(error)
                    error = notation(atom) * ": " * error
                    break
                end
            end
        end
        isempty(error) ? push!(kept,action) : push!(diagnostics,"error: action $(action.name): $error")
    end
    domain.actions = kept
    domain.by_name = Dict(a.name => a for a in kept)
    used = Set(atom[1] for a in kept for (_,atom) in [a.condition;a.effects])
    for predicate in domain.predicate_order
        predicate in used || push!(diagnostics,"warning: predicate $predicate is not used by any action")
    end
    domain.fluent,domain.static = predicate_classes(domain)
    domain.diagnostics = diagnostics
end
function validate_problem!(domain,problem)
    for side in ("init","goal")
        original = side == "init" ? problem.initial : problem.goals
        kept,seen = PlanningAtom[],Set{PlanningAtom}()
        for atom in original
            error = haskey(domain.predicates,atom[1]) ?
                argument_error(domain,atom[2],domain.predicates[atom[1]],problem.objects,"object") :
                "unknown predicate " * atom[1]
            isempty(error) && atom in seen && (error = "duplicate")
            if isempty(error)
                push!(kept,atom)
                push!(seen,atom)
            else
                push!(problem.diagnostics,"warning: $side $(notation(atom)): $error")
            end
        end
        side == "init" ? (problem.initial = kept) : (problem.goals = kept)
    end
end
validation_result(status,messages,correct) = (status=status,messages=messages,correct=correct)
function validate_steps(domain,problem,steps)
    world,cost = Set(problem.initial),0
    for (i,(name,arguments)) in enumerate(steps)
        heading = "step $i $(notation((name,arguments))): "
        haskey(domain.by_name,name) || return validation_result("invalid",[heading * "unknown action " * name],i-1)
        schema = domain.by_name[name]
        error = argument_error(domain,arguments,last.(schema.parameters),problem.objects,"object")
        isempty(error) || return validation_result("invalid",[heading * error],i-1)
        binding = Dict(variable => argument for ((variable,_),argument) in zip(schema.parameters,arguments))
        for (sign,atom) in schema.condition
            bound = substitute(atom,binding)
            truth = bound[1] == "=" ? bound[2][1] == bound[2][2] : bound in world
            if truth != sign
                literal = sign ? notation(bound) : "(not " * notation(bound) * ")"
                return validation_result("invalid",[heading * "precondition " * literal * " is false"],i-1)
            end
        end
        deletes = Set(substitute(atom,binding) for (sign,atom) in schema.effects if !sign)
        adds = Set(substitute(atom,binding) for (sign,atom) in schema.effects if sign)
        setdiff!(world,deletes)
        union!(world,adds)
        cost += schema.cost
    end
    missing = ["unsatisfied goal " * notation(atom) for atom in problem.goals if !(atom in world)]
    isempty(missing) ? validation_result("valid",["length=$(length(steps)) cost=$cost"],length(steps)) :
        validation_result("goal not reached",missing,length(steps))
end
verdict(checked) = checked.status * (checked.status == "valid" ? " " : ": ") * checked.messages[1]
plan_steps(problem,plan) = [(problem.actions[n+1].source.name,problem.actions[n+1].arguments) for n in plan]
plan_cost(problem,plan) = sum((problem.actions[n+1].cost for n in plan);init=0)
function interferes(a,b)
    !isdisjoint(a.delete,union(b.pre,b.add)) || !isdisjoint(b.delete,union(a.pre,a.add)) ||
        !isdisjoint(a.add,b.neg) || !isdisjoint(b.add,a.neg)
end
function parallelize(problem,plan)
    assigned,layers = Int[],Vector{Int}[]
    for (j,n) in enumerate(plan)
        action,layer = problem.actions[n+1],1
        for i in 1:j-1
            previous = problem.actions[plan[i]+1]
            if !isdisjoint(previous.add,action.pre) || !isdisjoint(previous.delete,action.neg) || interferes(previous,action)
                layer = max(layer,assigned[i]+1)
            end
        end
        push!(assigned,layer)
        while length(layers) < layer
            push!(layers,Int[])
        end
        push!(layers[layer],n)
    end
    layers
end
function validate_parallel(problem,layers)
    state = problem.initial
    for (k,layer) in enumerate(layers)
        actions = [problem.actions[n+1] for n in layer]
        if any(!applicable(a,state) for a in actions) ||
            any(interferes(actions[i],actions[j]) for i in eachindex(actions) for j in (i+1):length(actions))
            return "invalid at layer $k"
        end
        deletes = Set{Int}(p for a in actions for p in a.delete)
        adds = Set{Int}(p for a in actions for p in a.add)
        state = union(setdiff(state,deletes),adds)
    end
    issubset(problem.goal,state) ? "valid" : "goal not reached"
end
function improve(problem,plan)
    sequence,position = copy(plan),1
    while position <= length(sequence)
        state = problem.initial
        for n in sequence[1:position-1]
            state = apply_action(problem.actions[n+1],state)
        end
        applied = Int[]
        for n in sequence[position+1:end]
            action = problem.actions[n+1]
            if applicable(action,state)
                state = apply_action(action,state)
                push!(applied,n)
            end
        end
        if issubset(problem.goal,state)
            sequence = [sequence[1:position-1];applied]
        else
            position += 1
        end
    end
    sequence
end
function transform_negatives(problem)
    negative = sort(collect(Set(p for a in problem.actions for p in a.neg)))
    complements = Dict(p => length(problem.facts)+i-1 for (i,p) in enumerate(negative))
    actions = GraphElement[]
    for a in problem.actions
        pre = union(a.pre,Set{Int}(complements[p] for p in a.neg))
        add = union(a.add,Set{Int}(complements[p] for p in a.delete if haskey(complements,p)))
        deletes = union(a.delete,Set{Int}(complements[p] for p in a.add if haskey(complements,p)))
        push!(actions,GraphElement(a.number,pre,add,deletes))
    end
    initial = union(problem.initial,Set{Int}(complements[p] for p in negative if !(p in problem.initial)))
    actions,initial,length(negative)
end
function domain_report(domain)
    lines = ["== domain $(domain.name) ==";domain.diagnostics]
    for kind in domain.type_order
        chain,current = String[],kind
        while current !== nothing
            push!(chain,current)
            current = domain.parents[current]
        end
        push!(lines,"type " * join(chain," < "))
    end
    for name in domain.predicate_order
        push!(lines,"predicate $name/$(length(domain.predicates[name])) " * (name in domain.fluent ? "fluent" : "static"))
    end
    for a in domain.actions
        adds = count(literal -> literal[1],a.effects)
        push!(lines,"action $(a.name)/$(length(a.parameters)) cost=$(a.cost) pre=$(length(a.condition)) add=$adds del=$(length(a.effects)-adds)")
    end
    lines
end
function grounding_report(domain,p)
    lines = ["";"== problem $(p.name) ==";p.source.diagnostics]
    push!(lines,"objects: $(length(p.source.objects))")
    append!(lines,[headed("  $kind:",p.objects_by_type[kind]) for kind in domain.type_order])
    push!(lines,"static facts: $(p.static_count)")
    for a in domain.actions
        assignments,candidates,reachable = p.statistics[a.name]
        push!(lines,"schema $(a.name): assignments=$assignments candidates=$candidates reachable=$reachable")
    end
    push!(lines,"candidates: $(p.candidate_count) reachable: $(length(p.actions))")
    push!(lines,"facts: $(length(p.facts)) init: $(length(p.initial)) goals: $(length(p.goal))")
    append!(lines,["unreachable goal: " * notation(a) for a in p.unreachable])
    counts = ["$name=$(count(a -> a[1] == name,p.facts))" for name in domain.predicate_order if name in domain.fluent]
    push!(lines,headed("facts by predicate:",counts))
    push!(lines,"facts:")
    append!(lines,["  $(i-1) $(notation(a))" for (i,a) in enumerate(p.facts)])
    push!(lines,"actions:")
    for a in p.actions
        push!(lines,"  $(a.number) $(action_text(a)) cost=$(a.cost) pre=$(number_list(a.pre)) neg=$(number_list(a.neg)) add=$(number_list(a.add)) del=$(number_list(a.delete))")
    end
    lines
end
function initial_report(p,engine)
    values = heuristic_values(engine,p.initial)
    selected = landmarks(engine,p.initial)
    selected === nothing && (selected = Set{Int}())
    relaxed = relaxed_plan(engine,p.initial)
    relaxed === nothing && (relaxed = Int[])
    lines = ["initial h: " * heuristic_text(values),"landmarks: $(length(selected))"]
    append!(lines,["  " * notation(p.facts[n+1]) for n in sort(collect(selected))])
    push!(lines,"relaxed plan: length=$(length(relaxed)) cost=$(value_text(values[4]))")
    append!(lines,["  " * action_text(p.actions[n+1]) for n in relaxed])
    push!(lines,headed("helpful:",[action_text(p.actions[n+1]) for n in helpful(engine,p.initial)]))
    lines,selected
end
function plan_report(domain,p,tag,plan,landmark_set,earlier)
    first_tag = get!(earlier,Tuple(plan),tag)
    suffix = first_tag == tag ? "" : " (same as $first_tag)"
    lines = ["plan: length=$(length(plan)) cost=$(plan_cost(p,plan))" * suffix]
    append!(lines,["  $i $(action_text(p.actions[n+1]))" for (i,n) in enumerate(plan)])
    counts = ["$(a.name)=$(count(n -> p.actions[n+1].source.name == a.name,plan))" for a in domain.actions
        if any(p.actions[n+1].source.name == a.name for n in plan)]
    push!(lines,headed("schemas:",counts))
    layers = parallelize(p,plan)
    push!(lines,"parallel: layers=$(length(layers))")
    append!(lines,[headed("  $i:",[action_text(p.actions[n+1]) for n in layer]) for (i,layer) in enumerate(layers)])
    improved = improve(p,plan)
    removed = length(plan)-length(improved)
    push!(lines,"improved: length=$(length(improved)) cost=$(plan_cost(p,improved)) removed=$removed")
    removed > 0 && append!(lines,["  $i $(action_text(p.actions[n+1]))" for (i,n) in enumerate(improved)])
    state,reached = p.initial,Set{Int}()
    for n in plan
        state = apply_action(p.actions[n+1],state)
        union!(reached,intersect(state,landmark_set))
    end
    push!(lines,"landmarks reached: $(length(reached))/$(length(landmark_set))")
    append!(lines,["  missed " * notation(p.facts[n+1]) for n in sort(collect(setdiff(landmark_set,reached)))])
    checked = validate_steps(domain,p.source,plan_steps(p,plan))
    checked_improved = validate_steps(domain,p.source,plan_steps(p,improved))
    validations = ["$tag: " * verdict(checked),"  parallel: " * validate_parallel(p,layers),"  improved: " * verdict(checked_improved)]
    lines,validations,checked.status == "valid"
end
function profile_report(p,engine,tag,plan)
    lines = ["-- profile ($tag) --"]
    state,remaining = p.initial,plan_cost(p,plan)
    overestimates = zeros(Int,length(HEURISTIC_NAMES))
    for k in 0:length(plan)
        values = heuristic_values(engine,state)
        push!(lines,"  $k: h*=$remaining " * heuristic_text(values))
        overestimates .+= values .> remaining
        if k < length(plan)
            a = p.actions[plan[k+1]+1]
            state = apply_action(a,state)
            remaining -= a.cost
        end
    end
    push!(lines,"overestimates: " * join(["$name=$value" for (name,value) in zip(HEURISTIC_NAMES,overestimates)]," "))
    push!(lines,"-- causal links ($tag) --")
    suppliers = Dict{Int,Int}()
    for (k,n) in enumerate(plan)
        a = p.actions[n+1]
        links = [notation(p.facts[f+1]) * "<-" * string(get(suppliers,f,0)) for f in sort(collect(a.pre))]
        push!(lines,headed("  $k $(action_text(a)):",links))
        for f in a.add
            suppliers[f] = k
        end
    end
    push!(lines,headed("  goal:",[notation(p.facts[f+1]) * "<-" * string(get(suppliers,f,0)) for f in sort(collect(p.goal))]))
    lines
end
function main()
    domain = read_domain(read("input/domain.txt",String))
    sources = read_problems(read("input/problems.txt",String))
    settings = read_settings(read("input/params.txt",String))
    candidates = read_candidates(read("input/candidates.txt",String))
    validate_domain!(domain)
    pairs = [settings["runs"];[("graphplan","none")]]
    tags = [algorithm == "graphplan" ? "graphplan" : "$algorithm $heuristic" for (algorithm,heuristic) in pairs]
    totals = [zeros(Int,4) for _ in tags]
    grounding_lines,plan_lines,graph_lines,validation_lines = domain_report(domain),String[],String[],String[]
    comparison = ["problem,algorithm,heuristic,length,cost,expanded,generated"]
    problems,evaluators,summaries = Dict{String,Any}(),Dict{String,Any}(),Dict{String,Any}()
    validated_plans,valid_plans = 0,0
    for source in sources
        validate_problem!(domain,source)
        p = ground(domain,source)
        problems[p.name] = p
        append!(grounding_lines,grounding_report(domain,p))
        for lines in (plan_lines,graph_lines,validation_lines)
            push!(lines,"== problem $(p.name) ==")
        end
        unreachable = !isempty(p.unreachable)
        engine = unreachable ? nothing : new_evaluator(p)
        landmark_set = Set{Int}()
        if unreachable
            push!(plan_lines,"initial h: unreachable goal")
        else
            evaluators[p.name] = engine
            lines,landmark_set = initial_report(p,engine)
            append!(plan_lines,lines)
        end
        outcomes,earlier,proof = Any[],Dict{Tuple,String}(),0
        for (i,(algorithm,heuristic)) in enumerate(pairs)
            complements = 0
            if unreachable
                outcome = search_result("unreachable goal")
            elseif algorithm == "graphplan"
                actions,initial,complements = transform_negatives(p)
                outcome = solve_graphplan(actions,initial,p.goal,settings["graphplan"])
            else
                outcome = run_search(p,p.initial,algorithm,heuristic,settings["budget"],settings["weight"],engine)
            end
            push!(outcomes,outcome)
            push!(plan_lines,"-- $(tags[i]) --")
            if unreachable
                push!(plan_lines,"result: FAIL (unreachable goal)")
            else
                status = outcome.status == "solved" ? "solved" : "FAIL ($(outcome.status))"
                push!(plan_lines,"result: $status expanded=$(outcome.expanded) generated=$(outcome.generated)")
                if outcome.status == "solved"
                    lines,validations,valid = plan_report(domain,p,tags[i],outcome.plan,landmark_set,earlier)
                    append!(plan_lines,lines)
                    append!(validation_lines,validations)
                    validated_plans += 1
                    valid_plans += valid
                end
            end
            if proof == 0 && (algorithm,heuristic) in [("ucs","none"),("astar","hmax")] && outcome.status == "solved"
                proof = i
            end
            if algorithm == "graphplan"
                if unreachable
                    push!(graph_lines,"result: FAIL (unreachable goal)")
                else
                    push!(graph_lines,"complementary facts: $complements")
                    append!(graph_lines,outcome.lines)
                    counts = " searched=$(outcome.expanded) memo_hits=$(outcome.memo_hits) tried=$(outcome.generated)"
                    if outcome.status == "solved"
                        push!(graph_lines,"result: solved levels=$(length(outcome.layers)) length=$(length(outcome.plan)) cost=$(plan_cost(p,outcome.plan))" * counts)
                        append!(graph_lines,[headed("layer $k:",[action_text(p.actions[n+1]) for n in layer]) for (k,layer) in enumerate(outcome.layers)])
                    else
                        push!(graph_lines,"result: FAIL ($(outcome.status))" * counts)
                    end
                end
            end
        end
        proof != 0 && append!(plan_lines,profile_report(p,engine,tags[proof],outcomes[proof].plan))
        solved = [o for o in outcomes if o.status == "solved"]
        best = isempty(solved) ? nothing : minimum(plan_cost(p,o.plan) for o in solved)
        optimal = proof != 0 ? string(plan_cost(p,outcomes[proof].plan)) :
            any(o.status in ("unreachable goal","dead end","exhausted","unreachable") for o in outcomes) ? "none" : "unknown"
        summaries[p.name] = (solved=length(solved),best=best,optimal=optimal)
        for (i,(outcome,(algorithm,heuristic))) in enumerate(zip(outcomes,pairs))
            totals[i][3] += outcome.expanded
            totals[i][4] += outcome.generated
            if outcome.status == "solved"
                length_text,cost_text = string(length(outcome.plan)),string(plan_cost(p,outcome.plan))
                totals[i][1] += 1
                totals[i][2] += plan_cost(p,outcome.plan) == best
            else
                length_text,cost_text = "-","-"
            end
            push!(comparison,join([p.name,algorithm,heuristic,length_text,cost_text,outcome.expanded,outcome.generated],","))
        end
        for lines in (plan_lines,graph_lines,validation_lines)
            push!(lines,"")
        end
    end
    push!(plan_lines,"== summary ==")
    for source in sources
        s = summaries[source.name]
        best = s.best === nothing ? "-" : string(s.best)
        push!(plan_lines,"$(source.name): solved=$(s.solved)/$(length(tags)) best=$best optimal=$(s.optimal)")
    end
    for (tag,values) in zip(tags,totals)
        push!(plan_lines,"$tag: solved=$(values[1]) best=$(values[2]) expanded=$(values[3]) generated=$(values[4])")
    end
    push!(validation_lines,"== candidates ==")
    valid_candidates = 0
    for candidate in candidates
        p = problems[candidate.problem]
        checked = validate_steps(domain,p.source,candidate.steps)
        heading = "candidate $(candidate.number) $(candidate.problem) $(candidate.label): "
        map_steps(steps) = [p.action_numbers[(name,Tuple(arguments))] for (name,arguments) in steps]
        if checked.status == "valid"
            valid_candidates += 1
            push!(validation_lines,heading * verdict(checked))
            mapped = map_steps(candidate.steps)
            improved = improve(p,mapped)
            best = summaries[p.name].best
            best_text = best === nothing ? "-" : string(best)
            push!(validation_lines,"  improved: length=$(length(improved)) cost=$(plan_cost(p,improved)) removed=$(length(mapped)-length(improved)) best known=$best_text")
        else
            push!(validation_lines,heading * checked.status)
            append!(validation_lines,["  " * message for message in checked.messages])
            if !isempty(p.unreachable)
                push!(validation_lines,"  repair: FAIL (unreachable goal)")
                continue
            end
            prefix = map_steps(candidate.steps[1:checked.correct])
            state = p.initial
            for n in prefix
                state = apply_action(p.actions[n+1],state)
            end
            algorithm,heuristic = settings["repair"]
            outcome = run_search(p,state,algorithm,heuristic,settings["budget"],settings["weight"],evaluators[p.name])
            if outcome.status != "solved"
                push!(validation_lines,"  repair: FAIL ($(outcome.status))")
            else
                repaired = [prefix;outcome.plan]
                validation = validate_steps(domain,p.source,plan_steps(p,repaired))
                push!(validation_lines,"  repair: kept=$(length(prefix)) added=$(length(outcome.plan)) " * verdict(validation))
                append!(validation_lines,["    $i $(action_text(p.actions[n+1]))" for (i,n) in enumerate(repaired)])
            end
        end
    end
    append!(validation_lines,["","== summary ==","plans: $validated_plans valid: $valid_plans",
        "candidates: $(length(candidates)) valid: $valid_candidates"])
    mkpath("output")
    for (name,lines) in [("grounding.txt",grounding_lines),("plans.txt",plan_lines),("graphplan.txt",graph_lines),
        ("validation.txt",validation_lines),("comparison.csv",comparison)]
        write(joinpath("output",name),join(lines,"\n") * "\n")
    end
end
main()
