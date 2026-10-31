include("rbac.jl")
include("expressions.jl")
include("policy_parser.jl")
include("combining.jl")
include("analysis.jl")

const DEFINITE_DECISIONS = ("PERMIT","DENY")
struct PolicyError
    reason::String
end
words(parts...) = join(string.(parts)," ")
bump!(counts,key,amount=1) = (counts[key]=get(counts,key,0)+amount)
function input_value(text)
    text in ("true","false") && return text=="true"
    startswith(text,"[") && return text=="[]" ? String[] : String.(split(text[2:end-1],','))
    occursin(r"^-?[0-9]+$",text) && return parse(Int,text)
    String(text)
end
function read_attribute_fields(fields)
    result = Dict{String,Any}()
    for field in fields
        name,value = split(field,'=';limit=2)
        result[name] = input_value(value)
    end
    result
end
function value_notation(value)
    value isa Bool && return value ? "true" : "false"
    value isa Int && return string(value)
    value isa String && return "\""*value*"\""
    "["*join(value_notation.(value),',')*"]"
end
function read_attributes()
    subjects,resources = Dict{String,Dict{String,Any}}(),Dict{String,NamedTuple}()
    domains,reference = Tuple{String,Vector{Any}}[],Dict{String,Any}()
    for line in readlines("input/attributes.txt")
        f = split(line)
        if f[1]=="SUBJECT"
            subjects[f[2]] = read_attribute_fields(f[3:end])
        elseif f[1]=="RESOURCE"
            resources[f[2]] = (type=String(f[3]),attributes=read_attribute_fields(f[4:end]))
        elseif f[1]=="DOMAIN"
            push!(domains,(String(f[2]),Any[input_value(v) for v in f[3:end]]))
        else
            reference = read_attribute_fields(f[2:end])
        end
    end
    subjects,resources,domains,reference
end
function read_requests()
    [begin
        f = String.(split(line))
        explain = f[end]=="EXPLAIN"
        explain && pop!(f)
        (
            identifier=f[1],
            user=f[2],
            roles=f[3],
            action=f[4],
            resource=f[5],
            environment=read_attribute_fields(f[6:end]),
            explain=explain
        )
    end for line in readlines("input/requests.txt")]
end
function first_error(values)
    index = findfirst(v->v isa PolicyError,values)
    isnothing(index) ? nothing : values[index]
end
function boolean_result(values,veto,name)
    checked = [v isa Bool || v isa PolicyError ? v : PolicyError("type $name") for v in values]
    any(v->v===veto,checked) && return veto
    error = first_error(checked)
    isnothing(error) ? !veto : error
end
function apply_operation(name,operands)
    error = first_error(operands)
    !isnothing(error) && return error
    if name in ("+","-","*","<","<=",">",">=")
        if all(v->typeof(v)==Int,operands)
            length(operands)==1 && return -operands[1]
            left,right = operands
            name=="+" && return left+right
            name=="-" && return left-right
            name=="*" && return left*right
            name=="<" && return left<right
            name=="<=" && return left<=right
            name==">" && return left>right
            return left>=right
        end
    elseif name in ("==","!=")
        left,right = operands
        if typeof(left)==typeof(right) && (left isa Int || left isa Bool || left isa String)
            return name=="==" ? left==right : left!=right
        end
    elseif name=="in"
        operands[1] isa String && operands[2] isa Vector{String} && return operands[1] in operands[2]
    elseif name=="not"
        operands[1] isa Bool && return !operands[1]
    elseif name in ("starts_with","^=")
        all(v->v isa String,operands) && return startswith(operands[1],operands[2])
    elseif name=="size"
        operands[1] isa Vector{String} && return length(operands[1])
    end
    PolicyError("type $name")
end
function expression(tree,attributes,current=nothing)
    name,args = tree.operation,tree.arguments
    name=="literal" && return args[1]
    name=="attribute" && return get(attributes,args[1],PolicyError("missing $(args[1])"))
    name=="it" && return current
    name=="present" && return haskey(attributes,args[1].arguments[1])
    if name in ("any_of","all_of")
        bag = expression(args[1],attributes,current)
        bag isa PolicyError && return bag
        !(bag isa Vector{String}) && return PolicyError("type $name")
        predicates = Any[expression(args[2],attributes,item) for item in bag]
        return boolean_result(predicates,name=="any_of",name)
    end
    operands = Any[expression(arg,attributes,current) for arg in args]
    name in ("and","or") ? boolean_result(operands,name=="or",name) : apply_operation(name,operands)
end
function target_group(results,conjunction)
    if conjunction
        any(r->r[1]=="NO_MATCH",results) && return ("NO_MATCH","")
        all(r->r[1]=="MATCH",results) && return ("MATCH","")
    else
        any(r->r[1]=="MATCH",results) && return ("MATCH","")
    end
    for result in results
        result[1]=="INDETERMINATE" && return result
    end
    ("NO_MATCH","")
end
function match_clause(clause,attributes)
    if !haskey(attributes,clause.reference)
        return clause.mandatory ? ("INDETERMINATE","missing $(clause.reference)") : ("NO_MATCH","")
    end
    source = attributes[clause.reference]
    items = source isa Vector{String} ? source : [source]
    comparison = expression(clause.literal,attributes)
    results = [apply_operation(clause.operation,Any[item,comparison]) for item in items]
    any(v->v===true,results) && return ("MATCH","")
    error = first_error(results)
    isnothing(error) ? ("NO_MATCH","") : ("INDETERMINATE",error.reason)
end
function evaluate_target(element,attributes)
    lines = [target_group(
        [target_group([match_clause(c,attributes) for c in alternative],true) for alternative in line],
        false
    ) for line in element.targets]
    target_group(lines,true)
end
Base.@kwdef mutable struct PolicyEvaluation
    element::Int
    target::Tuple{String,String}
    decision::String = NOT_APPLICABLE
    reason::String = ""
    decisive::Int = 0
    condition::Union{Nothing,Bool,PolicyError} = nothing
    children::Vector{Any} = Any[]
    obligations::Vector{Tuple{String,String}} = Tuple{String,String}[]
    advice::Vector{Tuple{String,String}} = Tuple{String,String}[]
end
function attachments!(result,supporters,elements,attributes)
    for supporter in supporters
        append!(result.obligations,supporter.obligations)
        append!(result.advice,supporter.advice)
    end
    effect,element = result.decision,elements[result.element]
    for (obligatory,definitions) in ((true,element.obligations),(false,element.advice))
        for definition in definitions
            definition.effect==effect || continue
            evaluated = [name=>expression(tree,attributes) for (name,tree) in definition.arguments]
            error = first_error(last.(evaluated))
            if !isnothing(error)
                if obligatory
                    result.decision = effect=="DENY" ? INDETERMINATE_D : INDETERMINATE_P
                    result.reason = "obligation $(definition.identifier): $(error.reason)"
                    result.decisive = 0
                    empty!(result.obligations)
                    empty!(result.advice)
                    return
                end
                continue
            end
            item = definition.identifier*join([" $name=$(value_notation(value))" for (
                name,
                value
            ) in evaluated])
            push!(obligatory ? result.obligations : result.advice,(definition.identifier,item))
        end
    end
end
function evaluate_rule(elements,index,attributes,coverage=nothing,obligations=true)
    element = elements[index]
    result = PolicyEvaluation(element=index,target=evaluate_target(element,attributes))
    target,reason = result.target
    indeterminate = element.behavior=="DENY" ? INDETERMINATE_D : INDETERMINATE_P
    if target=="INDETERMINATE"
        result.decision,result.reason = indeterminate,reason
    elseif target=="MATCH"
        condition = isnothing(element.condition) ? true : expression(element.condition,attributes)
        !(condition isa Bool || condition isa PolicyError) && (condition=PolicyError("type condition"))
        result.condition = condition
        if condition isa PolicyError
            result.decision,result.reason = indeterminate,condition.reason
        elseif condition
            result.decision,result.decisive = element.behavior,index
            obligations && attachments!(result,PolicyEvaluation[],elements,attributes)
        end
    end
    if !isnothing(coverage)
        coverage[index] = result.decision=="PERMIT" ? 'P' : result.decision=="DENY" ? 'D' : result.decision==NOT_APPLICABLE ? '-' : 'I'
    end
    result
end
function evaluate_element(elements,index,attributes,coverage=nothing)
    element = elements[index]
    element.kind=="rule" && return evaluate_rule(elements,index,attributes,coverage)
    result = PolicyEvaluation(element=index,target=evaluate_target(element,attributes))
    target,reason = result.target
    target=="NO_MATCH" && return result
    combined = combine_children(element.behavior,element.children,i->evaluate_element(elements,i,attributes,coverage),
        i->evaluate_target(elements[i],attributes),i->elements[i].identifier)
    result.decision,result.reason,result.children = combined.decision,combined.reason,combined.states
    if target=="INDETERMINATE"
        if result.decision in DEFINITE_DECISIONS
            result.decision = result.decision=="DENY" ? INDETERMINATE_D : INDETERMINATE_P
        end
        startswith(result.decision,"INDETERMINATE") && (result.reason=reason)
    end
    if result.decision in DEFINITE_DECISIONS
        supporters = [state.result for state in result.children if !isnothing(state) && state.kind=="evaluated" && state.result.decision==result.decision]
        result.decisive = isempty(supporters) ? index : supporters[1].decisive
        attachments!(result,supporters,elements,attributes)
    end
    result
end
decision_notation(decision,reason) = startswith(decision,"INDETERMINATE") ? "$decision ($reason)" : decision
function final_notation(result,elements)
    text = decision_notation(result.decision,result.reason)
    result.decision in DEFINITE_DECISIONS ? text*" by "*elements[result.decisive].identifier : text
end
function tree_lines(result,elements,depth=0)
    element,target = elements[result.element],result.target[1]
    prefix = repeat(" ",2+2depth)
    line = prefix*words(element.kind,element.identifier,element.behavior,"target",target)
    if element.kind=="rule" && target=="MATCH"
        condition = result.condition isa PolicyError ? "INDETERMINATE" : result.condition ? "TRUE" : "FALSE"
        line *= " condition $condition"
    end
    lines = [line*" -> "*decision_notation(result.decision,result.reason)]
    if element.kind!="rule" && target!="NO_MATCH"
        for (child,state) in zip(element.children,result.children)
            e = elements[child]
            if !isnothing(state) && state.kind=="evaluated"
                append!(lines,tree_lines(state.result,elements,depth+1))
            elseif isnothing(state)
                push!(lines,prefix*"  "*words(e.kind,e.identifier,"skipped"))
            else
                checked,reason = state.target
                line = prefix*"  "*words(e.kind,e.identifier,e.behavior,"target",checked)
                push!(lines,line*(checked=="INDETERMINATE" ? " ($reason)" : ""))
            end
        end
    end
    lines
end
function join_blocks(blocks)
    lines = String[]
    for block in blocks
        !isempty(lines) && push!(lines,"")
        append!(lines,block)
    end
    lines
end
function new_engine()
    rbac,elements = read_rbac(),read_policies()
    rules = [e.index for e in elements if e.kind=="rule"]
    subjects,resources,domains,reference = read_attributes()
    requests = read_requests()
    (;rbac,elements,rules,subjects,resources,domains,reference,requests,coverage=Dict(i=>Char[] for i in rules),
        grant_counts=Dict{Tuple{String,String,String},Int}(),decisions=Dict{String,Int}(),decisive=Dict{Int,Int}(),
        obligations=Dict{String,Int}(),advice=Dict{String,Int}(),refused=Ref(0))
end
function check_request(a,request)
    !haskey(a.subjects,request.user) && return "unknown user $(request.user)"
    !haskey(a.resources,request.resource) && return "unknown resource $(request.resource)"
    day = get(request.environment,"day",nothing)
    (typeof(day)!=Int || !(1<=day<=365)) && return "bad day"
    nothing
end
function activate(a,user,specification,day)
    authorized = authorized_roles(a.rbac,user,day)
    candidates = specification=="-" ? String[] : specification=="*" ? sort!(collect(authorized)) : String.(split(
        specification,
        ','
    ))
    active,seen,activations = String[],Set{String}(),Tuple{String,String}[]
    for candidate in candidates
        reason = ""
        if !(candidate in a.rbac.roles)
            reason = "unknown"
        elseif candidate in seen
            reason = "duplicate"
        elseif !(candidate in authorized)
            reason = "unauthorized"
        else
            closure = role_closure(a.rbac,[active;candidate])
            for constraint in a.rbac.dsd
                if length(intersect(constraint.roles,closure))>=constraint.cardinality
                    reason = "dsd $(constraint.name)"
                    break
                end
            end
        end
        push!(seen,candidate)
        isempty(reason) && push!(active,candidate)
        push!(activations,(candidate,reason))
    end
    activations,sort!(collect(role_closure(a.rbac,active)))
end
function prepare(a,request)
    activations,roles = activate(a,request.user,request.roles,request.environment["day"])
    resource = a.resources[request.resource]
    granted = findfirst(role->(request.action,resource.type) in a.rbac.permissions[role],roles)
    grant = isnothing(granted) ? "" : roles[granted]
    attributes = Dict{String,Any}("subject."*name=>value for (name,value) in a.subjects[request.user])
    attributes["subject.id"],attributes["subject.role"],attributes["subject.rbac"] = request.user,roles,!isempty(grant)
    for (name,value) in resource.attributes
        attributes["resource."*name] = value
    end
    attributes["resource.id"],attributes["resource.type"],attributes["action.id"] = request.resource,resource.type,request.action
    for (name,value) in request.environment
        attributes["environment."*name] = value
    end
    (;activations,roles,grant,attributes)
end
function request_trace(a,request,prepared,result)
    lines = [
        "request $(request.identifier)",
        "  "*words(
            "user",
            request.user,
            "resource",
            request.resource,
            "type",
            a.resources[request.resource].type,
            "action",
            request.action,
            "day",
            request.environment["day"]
        )
    ]
    for (role,reason) in prepared.activations
        push!(lines,"  activate $role"*(isempty(reason) ? " ok" : " refused $reason"))
    end
    push!(lines,"  roles "*(isempty(prepared.roles) ? "-" : join(prepared.roles,',')))
    push!(lines,"  rbac "*(isempty(prepared.grant) ? "no" : "yes $(prepared.grant)"))
    append!(lines,tree_lines(result,a.elements))
    push!(lines,"  decision "*final_notation(result,a.elements))
    lines
end
function process_requests(a)
    lines,explanations = String[],Vector{String}[]
    for request in a.requests
        coverage = Dict(i=>'.' for i in a.rules)
        error = check_request(a,request)
        if !isnothing(error)
            push!(lines,"$(request.identifier) ERROR $error")
            bump!(a.decisions,"ERROR")
            request.explain && push!(explanations,["request $(request.identifier)","  error $error"])
        else
            prepared = prepare(a,request)
            result = evaluate_element(a.elements,1,prepared.attributes,coverage)
            push!(lines,request.identifier*" "*final_notation(result,a.elements))
            for (role,reason) in prepared.activations
                if !isempty(reason)
                    push!(lines,"  refused $role $reason")
                    a.refused[] += 1
                end
            end
            for (kind,items,counts) in (
                ("obligation",result.obligations,a.obligations),
                ("advice",result.advice,a.advice)
            )
                for (id,item) in items
                    push!(lines,"  $kind $item")
                    bump!(counts,id)
                end
            end
            !isempty(prepared.grant) && bump!(
                a.grant_counts,
                (prepared.grant,request.action,a.resources[request.resource].type)
            )
            category = startswith(result.decision,"INDETERMINATE") ? "INDETERMINATE" : result.decision
            bump!(a.decisions,category)
            result.decision in DEFINITE_DECISIONS && bump!(a.decisive,result.decisive)
            request.explain && push!(explanations,request_trace(a,request,prepared,result))
        end
        for rule in a.rules
            push!(a.coverage[rule],coverage[rule])
        end
    end
    lines,join_blocks(explanations)
end
function permission_report(a)
    blocks = Vector{String}[]
    users = sort!(unique([x.user for x in a.rbac.assignments]))
    for user in users
        assigned,authorized = Dict{String,Set{Int}}(),Dict{String,Set{Int}}()
        for x in a.rbac.assignments
            x.user==user && union!(get!(assigned,x.role,Set{Int}()),x.first:x.last)
        end
        for (role,days) in assigned,inherited in role_closure(a.rbac,[role])
            union!(get!(authorized,inherited,Set{Int}()),days)
        end
        lines = ["user $user"]
        for (kind,sets) in (
            ("assigned",assigned),
            ("authorized",authorized)
        ),role in sort!(collect(keys(sets)))
            push!(lines,"  $kind $role "*day_notation(sets[role]))
        end
        via = Dict{Tuple{String,String},Vector{String}}()
        for role in sort!(collect(keys(authorized))),permission in a.rbac.permissions[role]
            push!(get!(via,permission,String[]),role)
        end
        for (action,resource_type) in sort!(collect(keys(via)))
            roles = via[(action,resource_type)]
            days = Set{Int}()
            for role in roles
                union!(days,authorized[role])
            end
            effective = "-"
            if haskey(a.subjects,user)
                resources = [id for (id,r) in a.resources if r.type==resource_type]
                permitted = 0
                for resource in resources
                    request = (
                        identifier="",
                        user=user,
                        roles="*",
                        action=action,
                        resource=resource,
                        environment=a.reference,
                        explain=false
                    )
                    prepared = prepare(a,request)
                    permitted += evaluate_element(a.elements,1,prepared.attributes).decision=="PERMIT"
                end
                effective = "$permitted/$(length(resources))"
            end
            push!(
                lines,
                "  "*words(
                    "permission",
                    action,
                    resource_type,
                    day_notation(days),
                    "via",
                    join(roles,','),
                    "effective",
                    effective
                )
            )
        end
        push!(blocks,lines)
    end
    join_blocks(blocks)
end
function domain_analysis(a)
    counts,examples = zeros(Int,length(a.elements)),Dict{Int,String}()
    shadowed = Set(i for i in a.rules if a.elements[a.elements[i].parent].behavior=="first-applicable")
    blockers = Dict(i=>Set{Int}() for i in a.rules)
    ancestors = Dict{Int,Vector{Int}}()
    for i in a.rules
        chain,parent = Int[],a.elements[i].parent
        while parent!=0
            push!(chain,parent)
            parent = a.elements[parent].parent
        end
        ancestors[i] = chain
    end
    pairs = Tuple{Int,Int,Int}[]
    for policy in a.elements
        policy.kind=="policy" || continue
        for (position,earlier) in enumerate(policy.children),later in policy.children[position+1:end]
            a.elements[earlier].behavior!=a.elements[later].behavior && push!(
                pairs,
                (policy.index,earlier,later)
            )
        end
    end
    conflict_counts,point_count = zeros(Int,length(pairs)),0
    for attributes in domain_points(a.domains)
        point_count += 1
        targets = Dict(e.index=>evaluate_target(e,attributes)[1] for e in a.elements if e.kind!="rule")
        standalone = Dict(i=>evaluate_rule(a.elements,i,attributes,nothing,false).decision for i in a.rules)
        applying = Set{Int}()
        for i in a.rules
            (standalone[i] in DEFINITE_DECISIONS && all(
                parent->targets[parent]=="MATCH",
                ancestors[i]
            )) || continue
            push!(applying,i)
            counts[i] += 1
            if !haskey(examples,i)
                examples[i] = join(
                    [name*"="*value_notation(attributes[name]) for (
                        name,
                        candidates
                    ) in a.domains if length(candidates)>=2],
                    ' '
                )
            end
            if i in shadowed
                earlier = rule_blocker(a.elements[i],a.elements,standalone)
                earlier==0 ? delete!(shadowed,i) : push!(blockers[i],earlier)
            end
        end
        for (i,(_,earlier,later)) in enumerate(pairs)
            earlier in applying && later in applying && (conflict_counts[i]+=1)
        end
    end
    lines = ["applicability $point_count"]
    for i in a.rules
        push!(lines,"  $(a.elements[i].identifier) $(counts[i]) $(get(examples,i,"-"))")
    end
    dead = [i for i in a.rules if counts[i]==0]
    push!(lines,"dead $(length(dead))")
    append!(lines,["  $(a.elements[i].identifier)" for i in dead])
    setdiff!(shadowed,dead)
    push!(lines,"shadowed $(length(shadowed))")
    for i in a.rules
        if i in shadowed
            ids = [a.elements[j].identifier for j in a.rules if j in blockers[i]]
            push!(lines,"  $(a.elements[i].identifier) by "*join(ids,','))
        end
    end
    push!(lines,"conflicts $(count(>(0),conflict_counts))")
    for (i,(policy,earlier,later)) in enumerate(pairs)
        conflict_counts[i]==0 && continue
        winner = conflict_winner(a.elements[policy],a.elements[earlier],a.elements[later])
        push!(
            lines,
            "  "*words(
                a.elements[policy].identifier,
                a.elements[earlier].identifier,
                a.elements[later].identifier,
                conflict_counts[i],
                a.elements[winner].identifier
            )
        )
    end
    lines
end
function analysis_report(a)
    lines = ["rbac $(length(a.rbac.diagnostics))"]
    for (number,keyword,message) in a.rbac.diagnostics
        push!(lines,"  "*words("line",number,keyword,message))
    end
    push!(lines,"grants $(length(a.rbac.grants))")
    for grant in sort!(collect(a.rbac.grants))
        push!(lines,"  "*words(grant...,get(a.grant_counts,grant,0)))
    end
    append!(lines,domain_analysis(a))
    push!(lines,"coverage $(length(a.requests))")
    uncovered = Int[]
    for i in a.rules
        symbols = a.coverage[i]
        n = count(c->c in "PD",symbols)
        push!(lines,"  "*words(a.elements[i].identifier,join(symbols),n))
        n==0 && push!(uncovered,i)
    end
    push!(lines,"uncovered $(length(uncovered))")
    append!(lines,["  $(a.elements[i].identifier)" for i in uncovered])
    push!(lines,"summary")
    for name in ("PERMIT","DENY",NOT_APPLICABLE,"INDETERMINATE","ERROR")
        push!(lines,"  decision $name $(get(a.decisions,name,0))")
    end
    push!(lines,"  refused $(a.refused[])")
    for e in a.elements
        n = get(a.decisive,e.index,0)
        n>0 && push!(lines,"  decisive $(e.identifier) $n")
    end
    for (kind,counts) in (("obligation",a.obligations),("advice",a.advice)),id in sort!(collect(keys(counts)))
        push!(lines,"  $kind $id $(counts[id])")
    end
    lines
end
function main()
    a = new_engine()
    decisions,traces = process_requests(a)
    outputs = [
        ("decisions.txt",decisions),
        ("traces.txt",traces),
        ("permissions.txt",permission_report(a)),
        ("analysis.txt",analysis_report(a))
    ]
    mkpath("output")
    for (name,lines) in outputs
        write(joinpath("output",name),isempty(lines) ? "" : join(lines,"\n")*"\n")
    end
end
main()
