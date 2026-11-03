mutable struct Header
    fields::Vector{Tuple{String,String}}
    invalid_lines::Vector{Int}
end
Header() = Header(Tuple{String,String}[], Int[])
function field_value(header::Header, name::String)
    name = lowercase(name)
    for (field, value) in header.fields
        field == name && return value
    end
    nothing
end
field_count(header::Header, name::String) = count(field -> field[1] == lowercase(name), header.fields)
struct Token
    kind::String
    text::String
    spaced::Bool
end
split_words(text::AbstractString) = String.(split(text, [' ', '\t']; keepempty=false))
collapse_whitespace(text::AbstractString) = join(split_words(text), ' ')
strip_whitespace(text::AbstractString) = String(strip(char -> char in (' ', '\t'), text))
strip_trailing(text::AbstractString) = String(rstrip(char -> char in (' ', '\t'), text))
function parse_fields(lines::Vector{Tuple{Int,String}})
    header = Header()
    in_field = false
    for (number, text) in lines
        if startswith(text, ' ') || startswith(text, '\t')
            if in_field
                name, value = header.fields[end]
                header.fields[end] = (name, value * text)
            else
                push!(header.invalid_lines, number)
            end
            continue
        end
        in_field = false
        position = findfirst(==(':'), text)
        if !isnothing(position)
            name = text[1:(position - 1)]
            if !isempty(name) && all(byte -> 33 <= byte <= 126, codeunits(name))
                push!(header.fields, (lowercase(name), text[(position + 1):end]))
                in_field = true
            end
        end
        in_field || push!(header.invalid_lines, number)
    end
    header.fields = [(name, strip_whitespace(value)) for (name, value) in header.fields]
    header
end
function remove_comments(text::AbstractString)
    result = UInt8[]
    depth = 0
    escaped = false
    for byte in codeunits(text)
        if depth == 0
            if byte == 40
                depth = 1
                push!(result, 32)
            else
                push!(result, byte)
            end
        elseif escaped
            escaped = false
        elseif byte == 92
            escaped = true
        elseif byte == 40
            depth += 1
        elseif byte == 41
            depth -= 1
        end
    end
    depth == 0 ? String(result) : nothing
end
function word_byte(byte::UInt8, address::Bool)
    if address
        return 65 <= byte <= 90 || 97 <= byte <= 122 || 48 <= byte <= 57 || byte in codeunits("!#\$%&'*+-/=?^_`{|}~")
    end
    33 <= byte <= 126 && byte ∉ codeunits("()<>@,;:\\\"/[]?=")
end
function tokenize(text::AbstractString, address::Bool)
    data = codeunits(text)
    specials = codeunits(address ? "<>:;@,." : "/;=")
    tokens = Token[]
    position = 1
    spaced = false
    while position <= length(data)
        byte = data[position]
        if byte == 32 || byte == 9
            spaced = true
            position += 1
            continue
        end
        if byte == 40
            depth = 1
            position += 1
            while position <= length(data) && depth > 0
                if data[position] == 92
                    position += 2
                    continue
                elseif data[position] == 40
                    depth += 1
                elseif data[position] == 41
                    depth -= 1
                end
                position += 1
            end
            depth == 0 || return nothing
            spaced = true
            continue
        end
        if byte == 34
            position += 1
            value = UInt8[]
            while position <= length(data) && data[position] != 34
                data[position] == 92 && (position += 1)
                position <= length(data) || return nothing
                push!(value, data[position])
                position += 1
            end
            position <= length(data) || return nothing
            position += 1
            push!(tokens, Token("quoted", String(value), spaced))
        elseif byte in specials
            token_text = string(Char(byte))
            push!(tokens, Token(token_text, token_text, spaced))
            position += 1
        elseif word_byte(byte, address)
            start = position
            while position <= length(data) && word_byte(data[position], address)
                position += 1
            end
            push!(tokens, Token("word", String(data[start:(position - 1)]), spaced))
        else
            return nothing
        end
        spaced = false
    end
    tokens
end
function decode_word(word::AbstractString)
    if length(word) < 4 || !startswith(word, "=?") || !endswith(word, "?=")
        return (String(word), false, false)
    end
    pieces = split(word[3:(end - 2)], '?'; keepempty=true)
    if length(pieces) != 3 || any(isempty, pieces)
        return (String(word), false, false)
    end
    function decode()
        lowercase(pieces[1]) == "us-ascii" || return nothing
        if pieces[2] in ("B", "b")
            data = strict_base64(pieces[3])
        elseif pieces[2] in ("Q", "q")
            bytes = codeunits(pieces[3])
            data = UInt8[]
            position = 1
            while position <= length(bytes)
                if bytes[position] == 95
                    push!(data, 32)
                    position += 1
                elseif bytes[position] == 61
                    value = hex_byte(bytes, position + 1)
                    isnothing(value) && return nothing
                    push!(data, value)
                    position += 3
                else
                    push!(data, bytes[position])
                    position += 1
                end
            end
        else
            return nothing
        end
        isnothing(data) && return nothing
        all(byte -> 32 <= byte <= 126, data) ? String(data) : nothing
    end
    decoded = decode()
    isnothing(decoded) ? (String(word), false, true) : (decoded, true, false)
end
function decode_unstructured(value::AbstractString)
    result = ""
    previous = false
    error = false
    for (index, word) in enumerate(split_words(value))
        text, decoded, failed = decode_word(word)
        index > 1 && !(decoded && previous) && (result *= " ")
        result *= text
        previous = decoded
        error |= failed
    end
    (collapse_whitespace(result), error)
end
struct Parameters
    main_type::String
    subtype::String
    values::Dict{String,String}
end
function parse_parameters(value::String, with_subtype::Bool)
    tokens = tokenize(value, false)
    (isnothing(tokens) || isempty(tokens) || tokens[1].kind != "word") && return nothing
    subtype = ""
    position = 2
    if with_subtype
        (length(tokens) < 3 || tokens[2].kind != "/" || tokens[3].kind != "word") && return nothing
        subtype = lowercase(tokens[3].text)
        position = 4
    end
    parameters = Dict{String,String}()
    while position <= length(tokens)
        if position + 3 > length(tokens) || tokens[position].kind != ";" || tokens[position + 1].kind != "word" || tokens[position + 2].kind != "=" || tokens[position + 3].kind ∉ ("word", "quoted")
            return nothing
        end
        name = lowercase(tokens[position + 1].text)
        haskey(parameters, name) || (parameters[name] = tokens[position + 3].text)
        position += 4
    end
    Parameters(lowercase(tokens[1].text), subtype, parameters)
end
