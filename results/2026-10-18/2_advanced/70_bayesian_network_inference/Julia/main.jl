include("network_io.jl")
include("learning.jl")
include("factors.jl")
include("elimination.jl")
include("sampling.jl")
using Printf

words(parts...) = join(string.(parts)," ")
function format_real(value)
    text = @sprintf("%.4f",value)
    text=="-0.0000" ? "0.0000" : text
end
yes(value) = value ? "yes" : "no"
function write_blocks(path,blocks)
    text = join([join(block,"\n") for block in blocks],"\n\n")
    write(path,text*(isempty(text) ? "" : "\n"))
end
function closure(initial,links)
    reached,pending = Set(initial),collect(initial)
    while !isempty(pending)
        for neighbor in links[pop!(pending)]
            if !(neighbor in reached)
                push!(reached,neighbor)
                push!(pending,neighbor)
            end
        end
    end
    sort!(collect(reached))
end
function network_analysis(input)
    names,states,parents = input.names,input.states,input.parents
    sizes,variables = length.(states),collect(eachindex(names))
    children = [[c for c in variables if v in parents[c]] for v in variables]
    topological,selected = Int[],Set{Int}()
    while length(selected)<length(variables)
        v = minimum(v for v in variables if !(v in selected) && all(p->p in selected,parents[v]))
        push!(topological,v)
        push!(selected,v)
    end
    depths = zeros(Int,length(variables))
    for v in topological
        depths[v] = maximum((depths[p]+1 for p in parents[v]);init=0)
    end
    ancestors = [closure(parents[v],parents) for v in variables]
    descendants = [closure(children[v],children) for v in variables]
    spouses,blankets = Vector{Int}[],Vector{Int}[]
    for v in variables
        immediate = union(parents[v],children[v])
        other_parents = unique([p for c in children[v] for p in parents[c]])
        spouse = sort!(setdiff(other_parents,[v;immediate]))
        push!(spouses,spouse)
        push!(blankets,sort!(union(immediate,spouse)))
    end
    counts = [count_samples(v,parents[v],input.samples,sizes) for v in variables]
    learned = [learn_cpt(c,input.params.alpha) for c in counts]
    cpts = [input.params.sources[v]=="GIVEN" ? input.expert[v] : learned[v] for v in variables]
    likelihoods = [log_likelihood(counts[v],cpts[v]) for v in variables]
    parameters = parameter_count.(counts)
    factors = [cpt_factor(v,parents[v],cpts[v],sizes) for v in variables]
    (;input...,sizes,variables,children,topological,depths,ancestors,descendants,spouses,blankets,
        counts,learned,cpts,likelihoods,parameters,factors,random=Minstd(input.params.seed),
        family_scores=Dict{Tuple{Int,Tuple},Float64}())
end
sequence(a,variables) = isempty(variables) ? "-" : join(a.names[variables]," ")
function assignment_text(a,assignment,variables)
    isempty(variables) ? "-" : join(["$(a.names[v])=$(a.states[v][assignment[v]])" for v in variables]," ")
end
function parse_evidence(a,fields)
    evidence = Pair{Int,Int}[]
    for field in fields
        variable,state = split(field,'=')
        v = findfirst(==(variable),a.names)
        push!(evidence,v=>findfirst(==(state),a.states[v]))
    end
    evidence
end
function query_parts(a,fields)
    separator = findfirst(==("|"),fields)
    if isnothing(separator)
        return [findfirst(==(name),a.names) for name in fields],Pair{Int,Int}[]
    end
    [findfirst(==(name),a.names) for name in fields[1:separator-1]],parse_evidence(a,fields[separator+1:end])
end
function plans(a,initial,eliminate)
    Dict(method=>make_plan(initial,eliminate,method,a.params.order,a.sizes) for method in ("MINFILL","GIVEN"))
end
function sum_result(a,initial,plan,query)
    factor,_ = execute_plan(initial,plan,a.sizes)
    probability = ordered_total(factor.entries)
    distribution = Factor(factor.variables,factor.entries./probability)
    marginals = Dict(v=>zeros(a.sizes[v]) for v in query)
    for (assignment,p) in zip(assignments(distribution.variables,a.sizes),distribution.entries)
        for v in query
            marginals[v][assignment[v]] += p
        end
    end
    (distribution=distribution,probability=probability,marginals=marginals)
end
function posterior(a,query,evidence)
    relevant = closure(union(query,first.(evidence)),a.parents)
    eliminate = setdiff(relevant,union(query,first.(evidence)))
    initial = [reduce_factor(a.factors[v],Dict(evidence),a.sizes) for v in relevant]
    options = plans(a,initial,eliminate)
    result = sum_result(a,initial,options[a.params.method],query)
    (;result...,relevant,eliminate,initial,plans=options)
end
function joint_probability(a,assignment,variables)
    probability = 1.0
    for v in variables
        probability *= a.cpts[v][parent_row(a.parents[v],assignment,a.sizes),assignment[v]]
    end
    probability
end
function query_enumeration(a,result,query,evidence)
    free = setdiff(result.relevant,first.(evidence))
    n = entry_count(free,a.sizes)
    n>a.params.limit && return (n,"skipped")
    query = sort(query)
    entries = zeros(entry_count(query,a.sizes))
    for assignment in assignments(free,a.sizes)
        for (v,s) in evidence
            assignment[v] = s
        end
        entries[parent_row(query,assignment,a.sizes)] += joint_probability(a,assignment,result.relevant)
    end
    probability = ordered_total(entries)
    agreement = abs(log(probability)-log(result.probability))<=1e-9 && all(abs.(entries./probability.-result.distribution.entries).<=1e-9)
    n,agreement ? "agree" : "disagree"
end
function elimination_lines(a,result,agreement,enumeration)
    lines = ["relevant "*sequence(a,result.relevant),"pruned "*sequence(a,setdiff(a.variables,result.relevant)),
        "eliminate "*sequence(a,result.eliminate)]
    for method in ("MINFILL","GIVEN")
        plan = result.plans[method]
        push!(lines,"order "*lowercase(method))
        for step in plan.steps
            push!(
                lines,
                words(
                    "step",
                    a.names[step.variable],
                    "fill",
                    step.fill,
                    "scope",
                    sequence(a,step.scope),
                    "entries",
                    step.size
                )
            )
        end
        push!(lines,words("cost max",plan.maximum,"total",plan.total))
    end
    append!(
        lines,
        [
            "used "*lowercase(a.params.method),
            "orders_agree "*yes(agreement),
            words("enumeration",enumeration...)
        ]
    )
    lines
end
function marginal_lines(a,prefix,query,marginals)
    [words(
        prefix,
        a.names[v],
        join([words(state,format_real(p)) for (state,p) in zip(a.states[v],marginals[v])]," ")
    ) for v in query]
end
function answer_query(a,query,evidence)
    result = posterior(a,query,evidence)
    lines = ["log_evidence "*format_real(log(result.probability))]
    if !isempty(evidence)
        conflict = ordered_total(log(posterior(
            a,
            Int[],
            [item]
        ).probability) for item in evidence)-log(result.probability)
        push!(lines,"conflict "*format_real(conflict))
    end
    if length(query)>=2
        for (assignment,p) in zip(
            assignments(result.distribution.variables,a.sizes),
            result.distribution.entries
        )
            push!(
                lines,
                words("joint",assignment_text(a,assignment,result.distribution.variables),format_real(p))
            )
        end
    end
    append!(lines,marginal_lines(a,"marginal",query,result.marginals))
    for (v,s) in evidence
        without = posterior(a,query,filter(p->first(p)!=v,evidence)).marginals
        shift = maximum(abs(left-right) for q in query for (left,right) in zip(
            result.marginals[q],
            without[q]
        ))
        push!(lines,words("drop","$(a.names[v])=$(a.states[v][s])","shift",format_real(shift)))
    end
    first_result = sum_result(a,result.initial,result.plans["MINFILL"],query)
    second_result = sum_result(a,result.initial,result.plans["GIVEN"],query)
    agreement = abs(log(first_result.probability)-log(second_result.probability))<=1e-9 &&
        all(abs.(first_result.distribution.entries.-second_result.distribution.entries).<=1e-9)
    lines,elimination_lines(a,result,agreement,query_enumeration(a,result,query,evidence))
end
function mpe_enumeration(a,eliminate,evidence,assignment,maximum_probability)
    n = entry_count(eliminate,a.sizes)
    n>a.params.limit && return (n,"skipped")
    best,best_assignment = -1.0,Int[]
    for candidate in assignments(eliminate,a.sizes)
        for (v,s) in evidence
            candidate[v] = s
        end
        probability = joint_probability(a,candidate,a.variables)
        if probability>best
            best,best_assignment = probability,candidate
        end
    end
    agree = best_assignment==assignment && abs(log(best)-log(maximum_probability))<=1e-9
    n,agree ? "agree" : "disagree"
end
function answer_mpe(a,evidence)
    initial = [reduce_factor(f,Dict(evidence),a.sizes) for f in a.factors]
    eliminate = setdiff(a.variables,first.(evidence))
    options,outcomes = plans(a,initial,eliminate),Dict{String,NamedTuple}()
    for method in ("MINFILL","GIVEN")
        factor,products = execute_plan(initial,options[method],a.sizes,true)
        assignment = traceback(products,a.sizes)
        for (v,s) in evidence
            assignment[v] = s
        end
        outcomes[method] = (probability=factor.entries[1],assignment=assignment)
    end
    outcome = outcomes[a.params.method]
    best,assignment = outcome.probability,outcome.assignment
    probability = isempty(evidence) ? 1.0 : posterior(a,Int[],evidence).probability
    lines = ["assignment "*assignment_text(a,assignment,a.variables),"log_joint "*format_real(log(best)),
        "log_evidence "*format_real(log(probability)),"posterior "*format_real(best/probability)]
    for v in eliminate
        plan = make_plan(initial,filter(!=(v),eliminate),a.params.method,a.params.order,a.sizes)
        factor,_ = execute_plan(initial,plan,a.sizes,true)
        alternative = argmax(s->factor.entries[s],filter(!=(assignment[v]),collect(1:a.sizes[v])))
        push!(
            lines,
            words(
                "margin",
                a.names[v],
                a.states[v][alternative],
                format_real(log(best)-log(factor.entries[alternative]))
            )
        )
    end
    left,right = outcomes["MINFILL"],outcomes["GIVEN"]
    agree = left.assignment==right.assignment && abs(log(left.probability)-log(right.probability))<=1e-9
    result = (relevant=a.variables,eliminate=eliminate,plans=options)
    lines,elimination_lines(a,result,agree,mpe_enumeration(a,eliminate,evidence,assignment,best))
end
function answer_sample(a,number,query,evidence,counts)
    exact = posterior(a,query,evidence).marginals
    lines,rows = marginal_lines(a,"exact",query,exact),String[]
    weight,squared_weight = 0.0,0.0
    weights = Dict(v=>zeros(a.sizes[v]) for v in query)
    for index in 1:counts[end]
        sample,current = weighted_sample(a.topological,a.parents,a.cpts,a.sizes,Dict(evidence),a.random)
        weight += current
        squared_weight += current*current
        for v in query
            weights[v][sample[v]] += current
        end
        index in counts || continue
        maximum_error = 0.0
        for v in query,s in 1:a.sizes[v]
            estimate,p = weights[v][s]/weight,exact[v][s]
            error = abs(estimate-p)
            maximum_error = max(maximum_error,error)
            push!(
                rows,
                join(
                    [
                        string(number),
                        string(index),
                        a.names[v],
                        a.states[v][s],
                        format_real(estimate),
                        format_real(p),
                        format_real(error)
                    ],
                    ','
                )
            )
        end
        push!(
            lines,
            words(
                "after",
                index,
                "weight",
                format_real(weight),
                "ess",
                format_real(weight*weight/squared_weight),
                "max_error",
                format_real(maximum_error)
            )
        )
    end
    lines,rows
end
function answer_predict(a,v)
    k,likelihood = a.sizes[v],0.0
    confusion = zeros(Int,k,k)
    for sample in a.samples
        assignment,probabilities = copy(sample),Float64[]
        for s in 1:k
            assignment[v] = s
            p = a.cpts[v][parent_row(a.parents[v],assignment,a.sizes),s]
            for child in a.children[v]
                p *= a.cpts[child][parent_row(a.parents[child],assignment,a.sizes),assignment[child]]
            end
            push!(probabilities,p)
        end
        probabilities ./= ordered_total(probabilities)
        predicted,actual = argmax(probabilities),sample[v]
        confusion[actual,predicted] += 1
        likelihood += log(probabilities[actual])
    end
    correct,n = sum(confusion[s,s] for s in 1:k),length(a.samples)
    lines = ["blanket "*sequence(a,a.blankets[v]),words("accuracy","$correct/$n",format_real(correct/n)),
        "log_loss "*format_real(-likelihood/n),"predicted "*join(a.states[v]," ")]
    for s in 1:k
        push!(lines,words("actual",a.states[v][s],join(confusion[s,:]," ")))
    end
    lines
end
function reachable(a,x,z)
    ancestors = Set(closure(z,a.parents))
    pending = [(v,true) for v in sort(x)]
    visited = Set(pending)
    head = 1
    while head<=length(pending)
        v,up = pending[head]
        head += 1
        following = Tuple{Int,Bool}[]
        if up && !(v in z)
            append!(following,[(p,true) for p in a.parents[v]])
            append!(following,[(c,false) for c in a.children[v]])
        elseif !up
            !(v in z) && append!(following,[(c,false) for c in a.children[v]])
            v in ancestors && append!(following,[(p,true) for p in a.parents[v]])
        end
        for position in following
            if !(position in visited)
                push!(visited,position)
                push!(pending,position)
            end
        end
    end
    sort!(setdiff(unique(first.(collect(visited))),union(x,z)))
end
function frequency_counts(a,scope)
    counts = Dict{Int,Int}()
    for sample in a.samples
        key = parent_row(scope,sample,a.sizes)
        counts[key] = get(counts,key,0)+1
    end
    counts
end
function mutual_information(a,x,y,z)
    scope = sort!(union(x,y,z))
    xz,yz,z = sort!(union(x,z)),sort!(union(y,z)),sort(z)
    counts,cxz,cyz,cz = frequency_counts(
        a,
        scope
    ),frequency_counts(a,xz),frequency_counts(a,yz),frequency_counts(a,z)
    information,n = 0.0,length(a.samples)
    for key in sort!(collect(keys(counts)))
        assignment = canonical_assignment(key-1,scope,a.sizes)
        observed = counts[key]
        nxz,nyz,nz = cxz[parent_row(xz,assignment,a.sizes)],cyz[parent_row(
            yz,
            assignment,
            a.sizes
        )],cz[parent_row(z,assignment,a.sizes)]
        information += (observed/n)*log(Float64(observed*nz)/Float64(nxz*nyz))
    end
    degrees = (entry_count(x,a.sizes)-1)*(entry_count(y,a.sizes)-1)*entry_count(z,a.sizes)
    information,2n*information,degrees
end
function answer_dsep(a,groups)
    x,y = groups[1:2]
    z = length(groups)==3 ? groups[3] : Int[]
    reached = reachable(a,x,z)
    information,statistic,degrees = mutual_information(a,x,y,z)
    ["result "*(isempty(intersect(reached,y)) ? "separated" : "connected"),"reachable "*sequence(a,reached),
        words("data cmi",format_real(information),"g2",format_real(statistic),"df",degrees)]
end
function answer_blanket(a,v)
    blanket = a.blankets[v]
    rest = setdiff(a.variables,[v;blanket])
    ["parents "*sequence(a,a.parents[v]),"children "*sequence(a,a.children[v]),"spouses "*sequence(a,a.spouses[v]),
        "blanket "*sequence(a,blanket),"rest "*sequence(a,rest),"rest_separated "*yes(isempty(intersect(
            reachable(a,[v],blanket),
            rest
        )))]
end
function directed_path(a,start,finish,ignored=nothing)
    previous,pending,head = Dict(start=>0),[start],1
    while head<=length(pending)
        v = pending[head]
        head += 1
        for child in a.children[v]
            ((v,child)==ignored || haskey(previous,child)) && continue
            previous[child] = v
            if child==finish
                result,current = Int[],child
                while current!=0
                    push!(result,current)
                    current = previous[current]
                end
                return reverse(result)
            end
            push!(pending,child)
        end
    end
    nothing
end
function cached_score(a,v,parents)
    key = (v,Tuple(sort(collect(parents))))
    get!(a.family_scores,key) do
        family_score(v,parents,a.samples,a.sizes,a.params.alpha)
    end
end
function answer_edge(a,operation,x,y)
    exists = x in a.parents[y]
    operation=="ADD" && exists && return ["result exists"]
    operation!="ADD" && !exists && return ["result missing"]
    path = operation=="ADD" ? directed_path(a,y,x) : operation=="REVERSE" ? directed_path(
        a,
        x,
        y,
        (x,y)
    ) : nothing
    if !isnothing(path)
        cycle = [operation=="ADD" ? x : y;path]
        return ["result cycle "*join(a.names[cycle]," -> ")]
    end
    before_y = cached_score(a,y,a.parents[y])
    parents_y = operation=="ADD" ? union(a.parents[y],[x]) : setdiff(a.parents[y],[x])
    after_y = cached_score(a,y,parents_y)
    change = after_y-before_y
    lines = [
        "result ok",
        words("family",a.names[y],"before",format_real(before_y),"after",format_real(after_y))
    ]
    if operation=="REVERSE"
        before_x,after_x = cached_score(a,x,a.parents[x]),cached_score(a,x,union(a.parents[x],[y]))
        change = (after_y-before_y)+(after_x-before_x)
        push!(lines,words("family",a.names[x],"before",format_real(before_x),"after",format_real(after_x)))
    end
    push!(lines,words("delta",format_real(change),change>0 ? "improves" : "worsens"))
    lines
end
function cpt_blocks(a)
    blocks,n = Vector{String}[],length(a.samples)
    for v in a.variables
        source,parents,cpt,counts = a.params.sources[v],a.parents[v],a.cpts[v],a.counts[v]
        lines = [
            words("variable",a.names[v],"source",source),
            "states "*join(a.states[v]," "),
            "parents "*sequence(a,parents)
        ]
        for (row,assignment) in enumerate(assignments(parents,a.sizes))
            push!(
                lines,
                words(
                    "row",
                    assignment_text(a,assignment,parents),
                    "counts",
                    join(counts[row,:]," "),
                    "probs",
                    join(format_real.(cpt[row,:])," ")
                )
            )
        end
        ll,d = a.likelihoods[v],a.parameters[v]
        push!(lines,words("loglik",format_real(ll),"parameters",d,"bic",format_real(ll-d*log(n)/2)))
        marginal = posterior(a,[v],Pair{Int,Int}[]).marginals[v]
        frequencies = [sum(counts[:,s])/n for s in 1:a.sizes[v]]
        push!(lines,words("marginal model",join(format_real.(marginal)," "),"data",join(format_real.(frequencies)," ")))
        if source=="LEARNED"
            difference = haskey(a.expert,v) ? format_real(maximum(abs.(a.learned[v].-a.expert[v]))) : "-"
            push!(lines,"given_difference "*difference)
        end
        push!(blocks,lines)
    end
    ll,d = ordered_total(a.likelihoods),sum(a.parameters)
    push!(
        blocks,
        [words(
            "network samples",
            n,
            "pseudocount",
            format_real(a.params.alpha),
            "loglik",
            format_real(ll),
            "parameters",
            d,
            "bic",
            format_real(ll-d*log(n)/2)
        )]
    )
    blocks
end
function structure_summary(a)
    options = plans(a,a.factors,a.variables)
    widths = Dict(method=>maximum(length(s.scope) for s in plan.steps)-1 for (method,plan) in options)
    graph = interaction_graph(a.factors)
    moral_edges = sum(length,values(graph))÷2
    lines = [words("variables",length(a.variables),"edges",sum(length,a.parents)),"topological_order "*sequence(a,a.topological),
        "roots "*sequence(a,[v for v in a.variables if isempty(a.parents[v])]),
        "leaves "*sequence(a,[v for v in a.variables if isempty(a.children[v])]),
        words("moral_edges",moral_edges,"width minfill",widths["MINFILL"],"given",widths["GIVEN"])]
    for v in a.variables
        push!(lines,words("variable",a.names[v],"states",a.sizes[v],"parents",length(a.parents[v]),"children",length(a.children[v]),
            "depth",a.depths[v],"ancestors",length(a.ancestors[v]),"descendants",length(a.descendants[v]),"blanket",length(a.blankets[v])))
    end
    lines
end
function main()
    input = read_inputs()
    a = network_analysis(input)
    cpts = cpt_blocks(a)
    answers,elimination,structure = Vector{String}[],Vector{String}[],[structure_summary(a)]
    sampling = ["query,samples,variable,state,estimate,exact,abs_error"]
    for (number,line) in enumerate(input.queries)
        fields = split(line)
        kind,fields = fields[1],fields[2:end]
        heading = words("query",number,line)
        if kind=="QUERY"
            query,evidence = query_parts(a,fields)
            answer,steps = answer_query(a,query,evidence)
            push!(answers,[heading;answer])
            push!(elimination,[heading;steps])
        elseif kind=="MPE"
            answer,steps = answer_mpe(a,parse_evidence(a,fields))
            push!(answers,[heading;answer])
            push!(elimination,[heading;steps])
        elseif kind=="SAMPLE"
            separator = findfirst(==("COUNTS"),fields)
            query,evidence = query_parts(a,fields[1:separator-1])
            answer,rows = answer_sample(a,number,query,evidence,parse.(Int,fields[separator+1:end]))
            push!(answers,[heading;answer])
            append!(sampling,rows)
        elseif kind=="PREDICT"
            push!(answers,[heading;answer_predict(a,findfirst(==(fields[1]),a.names))])
        elseif kind=="DSEP"
            groups = [Int[]]
            for field in fields
                field=="|" ? push!(groups,Int[]) : push!(groups[end],findfirst(==(field),a.names))
            end
            push!(structure,[heading;answer_dsep(a,groups)])
        elseif kind=="BLANKET"
            push!(structure,[heading;answer_blanket(a,findfirst(==(fields[1]),a.names))])
        else
            push!(
                structure,
                [heading;answer_edge(
                    a,
                    fields[1],
                    findfirst(==(fields[2]),a.names),
                    findfirst(==(fields[3]),a.names)
                )]
            )
        end
    end
    mkpath("output")
    for (name,blocks) in [
        ("cpts.txt",cpts),
        ("structure.txt",structure),
        ("answers.txt",answers),
        ("elimination.txt",elimination),
        ("sampling.csv",[sampling])
    ]
        write_blocks(joinpath("output",name),blocks)
    end
end
main()
