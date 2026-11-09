lp_name(word) = occursin(r"^[a-z][a-z0-9_]*$",word) && !(word in ("bounds","integer","binary","free","inf"))
struct LPConstraint
    line::Int
    name::String
    terms::Vector{Tuple{String,Fraction}}
    comparison::String
    rhs::Fraction
end
struct LPBound
    line::Int
    name::String
    kind::String
    lower::Union{Nothing,Fraction}
    upper::Union{Nothing,Fraction}
end
mutable struct ParsedLP
    name::String
    error::Union{Nothing,Tuple{Int,String}}
    direction::String
    objective::Vector{Tuple{String,Fraction}}
    constraints::Vector{LPConstraint}
    bounds::Vector{LPBound}
    integers::Vector{Tuple{Int,Vector{String}}}
    binaries::Vector{Tuple{Int,Vector{String}}}
end
function parse_expression(words)
    terms = Tuple{String,Fraction}[]
    index,sign = 1,1
    if !isempty(words) && words[1] == "-"
        index,sign = 2,-1
    end
    while index <= length(words)
        coefficient = read_number(words[index])
        if coefficient !== nothing
            index < length(words) && lp_name(words[index+1]) || return nothing
            name = words[index+1]
            index += 2
        elseif lp_name(words[index])
            coefficient,name = Fraction(1),words[index]
            index += 1
        else
            return nothing
        end
        push!(terms,(name,sign*coefficient))
        index > length(words) && return terms
        words[index] in ("+","-") || return nothing
        sign = words[index] == "+" ? 1 : -1
        index += 1
    end
    nothing
end
function named_expression(words)
    length(words) >= 2 && endswith(words[1],":") || return nothing
    name = words[1][1:end-1]
    terms = parse_expression(words[2:end])
    lp_name(name) && terms !== nothing ? (name,terms) : nothing
end
function parse_constraint(words,line)
    length(words) >= 4 && words[end-1] in ("<=",">=","=") || return nothing
    rhs = read_number(words[end];signed=true)
    named = named_expression(words[1:end-2])
    rhs === nothing || named === nothing ? nothing : LPConstraint(line,named[1],named[2],words[end-1],rhs)
end
function parse_bound(words,line)
    if length(words) == 2 && lp_name(words[1]) && words[2] == "free"
        return LPBound(line,words[1],"both",nothing,nothing)
    elseif length(words) == 3 && lp_name(words[1])
        name,operator,word = words
        value = read_number(word;signed=true)
        operator == ">=" && (value !== nothing || word == "-inf") && return LPBound(line,name,"lower",value,nothing)
        operator == "<=" && (value !== nothing || word == "inf") && return LPBound(line,name,"upper",nothing,value)
        operator == "=" && value !== nothing && return LPBound(line,name,"both",value,value)
    elseif length(words) == 5 && words[2] == words[4] == "<=" && lp_name(words[3])
        lower,upper = read_number(words[1];signed=true),read_number(words[5];signed=true)
        if (lower !== nothing || words[1] == "-inf") && (upper !== nothing || words[5] == "inf")
            return LPBound(line,words[3],"both",lower,upper)
        end
    end
    nothing
end
function parse_block(name,body,end_line)
    parsed = ParsedLP(name,nothing,"",Tuple{String,Fraction}[],LPConstraint[],LPBound[],Tuple{Int,Vector{String}}[],Tuple{Int,Vector{String}}[])
    state = "A"
    for (line,text) in body
        words = String.(split(text,' '))
        accepted = false
        if state == "A" && text in ("maximize","minimize")
            parsed.direction = text
            state,accepted = "B",true
        elseif state == "B"
            named = named_expression(words)
            if named !== nothing
                parsed.objective = named[2]
                state,accepted = "C",true
            end
        elseif state == "C" && text == "subject to"
            state,accepted = "D",true
        elseif state in ("D","E")
            if state == "E" && text in ("bounds","integer","binary")
                state,accepted = Dict("bounds"=>"F","integer"=>"G","binary"=>"H")[text],true
            else
                item = parse_constraint(words,line)
                if item !== nothing
                    push!(parsed.constraints,item)
                    state,accepted = "E",true
                end
            end
        elseif state == "F"
            if text in ("integer","binary")
                state,accepted = text == "integer" ? "G" : "H",true
            else
                item = parse_bound(words,line)
                if item !== nothing
                    push!(parsed.bounds,item)
                    accepted = true
                end
            end
        elseif state in ("G","H")
            if state == "G" && text == "binary"
                state,accepted = "H",true
            elseif all(lp_name,words)
                push!(state == "G" ? parsed.integers : parsed.binaries,(line,words))
                accepted = true
            end
        end
        if !accepted
            parsed.error = (line,"syntax error")
            return parsed
        end
    end
    state in ("A","B","C","D") && (parsed.error = (end_line,"syntax error"))
    parsed
end
function read_models()
    models = ParsedLP[]
    name = nothing
    body = Tuple{Int,String}[]
    for (line,text) in enumerate(readlines("input/models.lp"))
        (isempty(text) || startswith(text,"#")) && continue
        if name === nothing
            name = split(text,' ')[2]
            empty!(body)
        elseif text == "end"
            push!(models,parse_block(name,body,line))
            name = nothing
        else
            push!(body,(line,text))
        end
    end
    models
end
function read_settings()
    lines = readlines("input/params.txt")
    level,limit = parse(Int,split(lines[1])[2]),parse(Int,split(lines[2])[2])
    logs,limits = Dict{String,Int}(),Dict{String,Int}()
    for text in lines[3:end]
        isempty(text) && continue
        kind,name,value = split(text)
        (kind == "log" ? logs : limits)[name] = parse(Int,value)
    end
    (;level,limit,logs,limits)
end
