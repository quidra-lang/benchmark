const NICK_SPECIAL = "[]\\`_^{}|"
function irc_fold(value)
    join([isuppercase(c) ? lowercase(c) : c=='[' ? '{' : c==']' ? '}' : c=='\\' ? '|' : c=='^' ? '~' : c for c in value])
end
is_digits(value) = !isempty(value) && all(c->'0'<=c<='9',value)
is_letter(c) = 'A'<=c<='Z' || 'a'<=c<='z'
valid_nickname(value) = !isempty(value) && (is_letter(value[1]) || value[1] in NICK_SPECIAL) && all(
    c->is_letter(c) || c in NICK_SPECIAL || '0'<=c<='9' || c=='-',
    value[2:end]
)
valid_channel(value,maximum) = 2<=length(value)<=maximum && startswith(value,"#") && !occursin(':',value)
function parse_message(raw)
    n,position = length(raw),1
    if startswith(raw,":")
        first_space = findfirst(==(' '),raw)
        isnothing(first_space) && return "",String[]
        position = first_space
    end
    while position<=n && raw[position]==' '
        position += 1
    end
    start = position
    while position<=n && raw[position]!=' '
        position += 1
    end
    command = uppercase(raw[start:position-1])
    parameters = String[]
    while position<=n
        while position<=n && raw[position]==' '
            position += 1
        end
        position>n && break
        if raw[position]==':'
            push!(parameters,raw[position+1:end])
            break
        elseif length(parameters)==14
            push!(parameters,raw[position:end])
            break
        end
        start = position
        while position<=n && raw[position]!=' '
            position += 1
        end
        push!(parameters,raw[start:position-1])
    end
    command,parameters
end
