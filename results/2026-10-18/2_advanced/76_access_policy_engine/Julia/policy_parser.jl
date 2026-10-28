Base.@kwdef mutable struct PolicyElement
    index::Int
    kind::String
    identifier::String
    behavior::String
    parent::Int
    targets::Vector{Any} = Any[]
    children::Vector{Int} = Int[]
    condition::Union{Nothing,PolicyExpression} = nothing
    obligations::Vector{NamedTuple} = NamedTuple[]
    advice::Vector{NamedTuple} = NamedTuple[]
end
function parse_target(text)
    [[begin
        reference,op,literal = split(clause,' ';limit=3)
        mandatory = endswith(reference,"!")
        (
            reference=String(mandatory ? reference[1:end-1] : reference),
            mandatory=mandatory,
            operation=String(op),
            literal=parse_expression(literal)
        )
    end for clause in split(alternative," & ")] for alternative in split(text," | ")]
end
function read_policies()
    elements,stack = PolicyElement[],Int[]
    for raw in readlines("input/policies.txt")
        line = lstrip(raw,' ')
        (isempty(line) || startswith(line,"#")) && continue
        parts = split(line,' ';limit=2)
        keyword = parts[1]
        rest = length(parts)==2 ? parts[2] : ""
        if keyword in ("POLICYSET","POLICY","RULE")
            identifier,behavior = split(rest)
            parent = isempty(stack) ? 0 : stack[end]
            element = PolicyElement(
                index=length(elements)+1,
                kind=lowercase(keyword),
                identifier=String(identifier),
                behavior=String(behavior),
                parent=parent
            )
            parent!=0 && push!(elements[parent].children,element.index)
            push!(elements,element)
            push!(stack,element.index)
        elseif keyword=="END"
            pop!(stack)
        elseif keyword=="TARGET"
            push!(elements[stack[end]].targets,parse_target(rest))
        elseif keyword=="CONDITION"
            elements[stack[end]].condition = parse_expression(rest)
        else
            fields = split(rest,' ';limit=3)
            arguments = Pair{String,PolicyExpression}[]
            if length(fields)==3
                for item in split(fields[3],';')
                    name,expression = split(strip(item),'=';limit=2)
                    push!(arguments,String(name)=>parse_expression(expression))
                end
            end
            destination = keyword=="OBLIGATION" ? elements[stack[end]].obligations : elements[stack[end]].advice
            push!(destination,(effect=String(fields[1]),identifier=String(fields[2]),arguments=arguments))
        end
    end
    elements
end
