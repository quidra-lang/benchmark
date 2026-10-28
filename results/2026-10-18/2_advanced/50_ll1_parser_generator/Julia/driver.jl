mutable struct ParseNode
    symbol::String
    mark::String
    children::Vector{ParseNode}
end
ParseNode(symbol) = ParseNode(symbol,"",ParseNode[])
function parse_tokens(tokens,g,sets,table)
    input = vcat(tokens,[(END_MARKER,length(tokens)+1)])
    root = ParseNode(g.start)
    stack = Tuple{String,Union{Nothing,ParseNode}}[(END_MARKER,nothing),(g.start,root)]
    cursor,step = 1,0
    left_parse,traces,events = Int[],NamedTuple[],NamedTuple[]
    counts = Dict(name=>0 for name in ("predict","match","skip","pop","missing","max_stack"))
    while true
        step += 1
        top,node = stack[end]
        current,position = input[cursor]
        counts["max_stack"] = max(counts["max_stack"],length(stack))
        before_stack,before_input = [item[1] for item in stack],[item[1] for item in input[cursor:end]]
        terminate,event = false,""
        if top==END_MARKER && current==END_MARKER
            action = "accept"
            terminate = true
        elseif top==END_MARKER
            action,event = "error: skip $current","skip"
            cursor += 1
        elseif !is_nonterminal(top)
            if top==current
                action = "match $current"
                pop!(stack)
                cursor += 1
                counts["match"] += 1
            else
                action,event = "error: missing $top","missing"
                node.mark = "missing"
                pop!(stack)
            end
        elseif haskey(table.choices,(top,current))
            number = table.choices[(top,current)]
            p = table.productions[number]
            action = "predict $number: $(p.notation)"
            push!(left_parse,number)
            pop!(stack)
            if isempty(p.rhs)
                push!(node.children,ParseNode("%empty"))
            else
                children = ParseNode.(p.rhs)
                append!(node.children,children)
                for child in reverse(children)
                    push!(stack,(child.symbol,child))
                end
            end
            counts["predict"] += 1
        elseif current==END_MARKER || current in sets.follow[top]
            action,event = "error: pop $top","pop"
            node.mark = "error"
            pop!(stack)
        else
            action,event = "error: skip $current","skip"
            cursor += 1
        end
        push!(traces,(step=step,stack=before_stack,input=before_input,action=action))
        if !isempty(event)
            counts[event] += 1
            push!(events,(step=step,kind=event,symbol=top,token=current,position=position))
        end
        terminate && break
    end
    (root=root,trace=traces,left_parse=left_parse,events=events,counts=counts)
end
