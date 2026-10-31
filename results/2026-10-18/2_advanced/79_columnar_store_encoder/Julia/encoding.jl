const ENCODING_METHODS = ("PLAIN", "DICTIONARY", "RLE", "DELTA_BINARY_PACKED", "DELTA_LENGTH_BYTE_ARRAY")
const ENCODING_CANDIDATES = Dict(
    "INT" => (0, 1, 3),
    "DATE" => (0, 1, 3),
    "STRING" => (0, 1, 4),
    "BOOL" => (0, 2)
)

function delta_encode(values)
    output = vcat(
        uleb_bytes(128),
        uleb_bytes(4),
        uleb_bytes(length(values)),
        zigzag_bytes(isempty(values) ? 0 : values[1])
    )
    deltas = [values[index] - values[index - 1] for index in 2:length(values)]
    for start in 1:128:length(deltas)
        block = deltas[start:min(start + 127, end)]
        low = minimum(block)
        append!(output, zigzag_bytes(low))
        miniblocks = [index > length(block) ? Int[] : [value - low for value in block[index:min(
            index + 31,
            end
        )]] for index in 1:32:128]
        widths = [bit_width(maximum(miniblock; init=0)) for miniblock in miniblocks]
        append!(output, widths)
        for (miniblock, width) in zip(miniblocks, widths)
            !isempty(miniblock) && append!(
                output,
                pack_values(vcat(miniblock, zeros(Int, 32 - length(miniblock))), width)
            )
        end
    end
    return output
end

function delta_decode!(reader)
    block_size, miniblock_count, count = read_uleb!(reader), read_uleb!(reader), read_uleb!(reader)
    first_value = read_zigzag!(reader)
    values = count == 0 ? Int[] : [first_value]
    miniblock_size = block_size ÷ miniblock_count
    while length(values) < count
        low = read_zigzag!(reader)
        widths = [read_byte!(reader) for _ in 1:miniblock_count]
        for width in widths
            length(values) == count && break
            differences = unpack_values!(reader, width, miniblock_size)
            for difference in differences[1:min(miniblock_size, count - length(values))]
                push!(values, values[end] + low + difference)
            end
        end
    end
    return values
end

function encode_values(kind, method, values, dictionary=Any[])
    if method == 0
        output = Int[]
        if kind in ("INT", "DATE")
            for value in values
                append!(output, integer_bytes(value))
            end
        elseif kind == "STRING"
            for value in values
                append!(output, integer_bytes(length(value)))
                append!(output, ascii_bytes(value))
            end
        else
            output = pack_values(vcat(Int.(values), zeros(Int, mod(-length(values), 8))), 1)
        end
        return output
    elseif method == 1
        ranks = Dict(value => index - 1 for (index, value) in enumerate(dictionary))
        width = bit_width(length(dictionary) - 1)
        return vcat(width, hybrid_encode([ranks[value] for value in values], width))
    elseif method == 2
        encoded = hybrid_encode(Int.(values), 1)
        return vcat(integer_bytes(length(encoded)), encoded)
    elseif method == 3
        return delta_encode(values)
    end
    output = delta_encode(length.(values))
    for value in values
        append!(output, ascii_bytes(value))
    end
    return output
end

function decode_values!(reader, kind, method, count, dictionary=Any[])
    if method == 0
        kind in ("INT", "DATE") && return Any[read_integer!(reader; signed=true) for _ in 1:count]
        kind == "STRING" && return Any[ascii_text(read_bytes!(
            reader,
            read_integer!(reader)
        )) for _ in 1:count]
        values = unpack_values!(reader, 1, cld(count, 8) * 8)
        return Any[value == 1 for value in values[1:count]]
    elseif method == 1
        width = read_byte!(reader)
        return Any[dictionary[index + 1] for index in hybrid_decode!(reader, width, count)]
    elseif method == 2
        encoded = ByteReader(read_bytes!(reader, read_integer!(reader)))
        return Any[value == 1 for value in hybrid_decode!(encoded, 1, count)]
    elseif method == 3
        return Any[delta_decode!(reader)...]
    end
    lengths = delta_decode!(reader)
    return Any[ascii_text(read_bytes!(reader, length)) for length in lengths]
end

function encode_statistics(kind, bounds)
    bounds === nothing && return [0]
    output = [1]
    for value in bounds
        if kind in ("INT", "DATE")
            append!(output, zigzag_bytes(value))
        elseif kind == "STRING"
            append!(output, uleb_bytes(length(value)))
            append!(output, ascii_bytes(value))
        else
            push!(output, Int(value))
        end
    end
    return output
end

function decode_statistics!(reader, kind)
    read_byte!(reader) == 0 && return nothing
    values = Any[]
    for _ in 1:2
        if kind in ("INT", "DATE")
            push!(values, read_zigzag!(reader))
        elseif kind == "STRING"
            push!(values, ascii_text(read_bytes!(reader, read_uleb!(reader))))
        else
            push!(values, read_byte!(reader) == 1)
        end
    end
    return values
end
