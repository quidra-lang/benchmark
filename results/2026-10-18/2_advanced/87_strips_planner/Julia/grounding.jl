struct GroundAction
    number::Int
    source::Any
    arguments::Vector{String}
    cost::Int
    pre::Set{Int}
    neg::Set{Int}
    add::Set{Int}
    delete::Set{Int}
end
function subtype(parents,actual,expected)
    while actual !== nothing
        actual == expected && return true
        actual = parents[actual]
    end
    false
end
function predicate_classes(domain)
    fluent = Set(atom[1] for action in domain.actions for (_,atom) in action.effects)
    fluent,setdiff(Set(domain.predicate_order),fluent)
end
substitute(atom,assignment) = (atom[1],Tuple(assignment[term] for term in atom[2]))
function ground(domain,problem)
    objects_by_type = Dict(kind => [name for name in problem.object_order if subtype(domain.parents,problem.objects[name],kind)] for kind in domain.type_order)
    initial_atoms = Set(problem.initial)
    candidates,statistics = Any[],Dict{String,Vector{Int}}()
    for schema in domain.actions
        choices = [objects_by_type[kind] for (_,kind) in schema.parameters]
        statistics[schema.name] = [prod(length.(choices);init=1),0,0]
        function assign(arguments,index)
            if index <= length(choices)
                for name in choices[index]
                    assign([arguments;name],index+1)
                end
                return
            end
            binding = Dict(name => argument for ((name,_),argument) in zip(schema.parameters,arguments))
            positive,negative = Set{PlanningAtom}(),Set{PlanningAtom}()
            for (sign,atom) in schema.condition
                bound = substitute(atom,binding)
                if bound[1] == "="
                    truth = bound[2][1] == bound[2][2]
                elseif bound[1] in domain.static
                    truth = bound in initial_atoms
                else
                    push!(sign ? positive : negative,bound)
                    continue
                end
                truth == sign || return
            end
            adds = Set{PlanningAtom}(substitute(atom,binding) for (sign,atom) in schema.effects if sign)
            deletes = setdiff(Set{PlanningAtom}(substitute(atom,binding) for (sign,atom) in schema.effects if !sign),adds)
            push!(candidates,(source=schema,arguments=copy(arguments),cost=schema.cost,pre=positive,neg=negative,add=adds,delete=deletes))
            statistics[schema.name][2] += 1
        end
        assign(String[],1)
    end
    reachable = Set{PlanningAtom}(atom for atom in problem.initial if atom[1] in domain.fluent)
    accepted = Set{Int}()
    while true
        changed = false
        for (i,candidate) in enumerate(candidates)
            if !(i in accepted) && issubset(candidate.pre,reachable)
                push!(accepted,i)
                union!(reachable,candidate.add)
                statistics[candidate.source.name][3] += 1
                changed = true
            end
        end
        changed || break
    end
    predicate_order = Dict(name => i for (i,name) in enumerate(domain.predicate_order))
    object_order = Dict(name => i for (i,name) in enumerate(problem.object_order))
    facts = sort(collect(reachable);by=atom -> (predicate_order[atom[1]],Tuple(object_order[n] for n in atom[2])))
    fact_numbers = Dict(atom => i-1 for (i,atom) in enumerate(facts))
    actions = GroundAction[]
    for (i,candidate) in enumerate(candidates)
        i in accepted || continue
        mapped = [Set{Int}(fact_numbers[a] for a in values if haskey(fact_numbers,a))
            for values in (candidate.pre,candidate.neg,candidate.add,candidate.delete)]
        push!(actions,GroundAction(length(actions),candidate.source,candidate.arguments,candidate.cost,mapped...))
    end
    initial = Set{Int}(fact_numbers[a] for a in problem.initial if a[1] in domain.fluent)
    goal,unreachable = Set{Int}(),PlanningAtom[]
    for atom in problem.goals
        if haskey(fact_numbers,atom)
            push!(goal,fact_numbers[atom])
        elseif !(atom[1] in domain.static) || !(atom in initial_atoms)
            push!(unreachable,atom)
        end
    end
    action_numbers = Dict((a.source.name,Tuple(a.arguments)) => a.number for a in actions)
    (name=problem.name,source=problem,objects_by_type=objects_by_type,statistics=statistics,
        candidate_count=length(candidates),facts=facts,actions=actions,initial=initial,goal=goal,
        unreachable=unreachable,static_count=count(a -> a[1] in domain.static,problem.initial),action_numbers=action_numbers)
end
