const PlanningAtom = Tuple{String,Tuple{Vararg{String}}}
mutable struct PlanningDomain
    name::String
    parents::Dict{String,Union{Nothing,String}}
    type_order::Vector{String}
    predicates::Dict{String,Vector{String}}
    predicate_order::Vector{String}
    actions::Vector{Any}
    by_name::Dict{String,Any}
    fluent::Set{String}
    static::Set{String}
    diagnostics::Vector{String}
end
mutable struct ProblemSource
    name::String
    objects::Dict{String,String}
    object_order::Vector{String}
    initial::Vector{PlanningAtom}
    goals::Vector{PlanningAtom}
    diagnostics::Vector{String}
end
function expressions(text)
    cleaned = join([split(row,';';keepempty=true)[1] for row in split(text,'\n')],"\n")
    tokens = [String(m.match) for m in eachmatch(r"\(|\)|[^ ()\n]+",cleaned)]
    position = 1
    function read_expression()
        token = tokens[position]
        position += 1
        token != "(" && return token
        items = Any[]
        while tokens[position] != ")"
            push!(items,read_expression())
        end
        position += 1
        items
    end
    roots = Any[]
    while position <= length(tokens)
        push!(roots,read_expression())
    end
    roots
end
function typed_list(words)
    result,pending = Pair{String,String}[],String[]
    position = 1
    while position <= length(words)
        if words[position] == "-"
            append!(result,[name => String(words[position+1]) for name in pending])
            empty!(pending)
            position += 2
        else
            push!(pending,String(words[position]))
            position += 1
        end
    end
    append!(result,[name => "object" for name in pending])
    result
end
parse_atom(expression) = (String(expression[1]),Tuple(String.(expression[2:end])))
function conjuncts(expression;empty=true)
    conjunction = expression[1] == "and" && all(x -> x isa Vector,expression[2:end])
    conjunction && (empty || length(expression) > 1) ? expression[2:end] : [expression]
end
function parse_literal(expression)
    negative = expression[1] == "not" && length(expression) == 2 && expression[2] isa Vector
    negative ? (false,parse_atom(expression[2])) : (true,parse_atom(expression))
end
function read_domain(text)
    expression = expressions(text)[1]
    domain = PlanningDomain(expression[2][2],Dict("object" => nothing),["object"],
        Dict{String,Vector{String}}(),String[],Any[],Dict{String,Any}(),Set{String}(),Set{String}(),String[])
    for section in expression[3:end]
        if section[1] == ":types"
            for name in section[2:end]
                if name != "-" && !haskey(domain.parents,name)
                    domain.parents[name] = "object"
                    push!(domain.type_order,name)
                end
            end
            for (name,parent) in typed_list(section[2:end])
                domain.parents[name] = parent
            end
        elseif section[1] == ":predicates"
            for declaration in section[2:end]
                name = String(declaration[1])
                domain.predicates[name] = [kind for (_,kind) in typed_list(declaration[2:end])]
                push!(domain.predicate_order,name)
            end
        elseif section[1] == ":action"
            fields = Dict(section[i] => section[i+1] for i in 3:2:length(section))
            condition = haskey(fields,":precondition") ? parse_literal.(conjuncts(fields[":precondition"])) : Any[]
            effects,cost = Any[],1
            for item in conjuncts(fields[":effect"];empty=false)
                if item[1] == "increase" && length(item) == 3 && item[2] == ["total-cost"]
                    cost = parse(Int,item[3])
                else
                    push!(effects,parse_literal(item))
                end
            end
            push!(domain.actions,(name=String(section[2]),parameters=typed_list(fields[":parameters"]),
                condition=condition,effects=effects,cost=cost))
        end
    end
    domain
end
function read_problems(text)
    problems = ProblemSource[]
    for expression in expressions(text)
        sections = Dict(section[1] => section[2:end] for section in expression[3:end])
        objects = typed_list(sections[":objects"])
        push!(problems,ProblemSource(expression[2][2],Dict(objects),first.(objects),
            parse_atom.(sections[":init"]),parse_atom.(conjuncts(sections[":goal"][1];empty=false)),String[]))
    end
    problems
end
