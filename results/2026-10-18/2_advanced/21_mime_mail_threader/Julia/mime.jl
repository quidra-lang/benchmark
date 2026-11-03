function strict_base64(text::AbstractString)
    data = codeunits(text)
    length(data) % 4 == 0 || return nothing
    last = length(data)
    while last > 0 && data[last] == 61
        last -= 1
    end
    length(data) - last >= 3 && return nothing
    buffer = 0
    bits = 0
    result = UInt8[]
    for byte in data[1:last]
        value = if 65 <= byte <= 90
            Int(byte) - 65
        elseif 97 <= byte <= 122
            Int(byte) - 97 + 26
        elseif 48 <= byte <= 57
            Int(byte) - 48 + 52
        elseif byte == 43
            62
        elseif byte == 47
            63
        else
            return nothing
        end
        buffer = buffer << 6 | value
        bits += 6
        if bits >= 8
            bits -= 8
            push!(result, UInt8(buffer >> bits))
            buffer &= (1 << bits) - 1
        end
    end
    result
end
function hex_digit(byte::UInt8)
    48 <= byte <= 57 && return Int(byte) - 48
    65 <= byte <= 70 && return Int(byte) - 65 + 10
    97 <= byte <= 102 && return Int(byte) - 97 + 10
    nothing
end
function hex_byte(data::AbstractVector{UInt8}, position::Int)
    position + 1 <= length(data) || return nothing
    first = hex_digit(data[position])
    second = hex_digit(data[position + 1])
    isnothing(first) || isnothing(second) ? nothing : UInt8(first * 16 + second)
end
function decode_base64_body(text::String)
    compact = filter(char -> char ∉ (' ', '\t', '\n'), text)
    data = strict_base64(compact)
    isnothing(data) && return nothing
    result = UInt8[]
    position = 1
    while position <= length(data)
        if data[position] == 13 && position < length(data) && data[position + 1] == 10
            push!(result, 10)
            position += 2
        else
            push!(result, data[position])
            position += 1
        end
    end
    all(byte -> byte in (9, 10) || 32 <= byte <= 126, result) || return nothing
    String(result)
end
function decode_quoted_printable(text::String)
    lines = split(text, '\n'; keepempty=true)
    result = UInt8[]
    error = false
    for (index, line) in enumerate(lines)
        data = collect(codeunits(rstrip(char -> char in (' ', '\t'), line)))
        soft = !isempty(data) && data[end] == 61
        soft && pop!(data)
        position = 1
        while position <= length(data)
            if data[position] == 61
                value = hex_byte(data, position + 1)
                if !isnothing(value) && (value == 9 || 32 <= value <= 126)
                    push!(result, value)
                    position += 3
                    continue
                end
                error = true
            end
            push!(result, data[position])
            position += 1
        end
        !soft && index < length(lines) && push!(result, 10)
    end
    (String(result), error)
end
