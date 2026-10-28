mutable struct ByteReader
    data::Vector{Int}
    position::Int
end

ByteReader(data) = ByteReader(data, 0)

function read_bytes!(reader, count)
    start = reader.position + 1
    reader.position += count
    return reader.data[start:reader.position]
end

function read_byte!(reader)
    reader.position += 1
    return reader.data[reader.position]
end

function read_uleb!(reader)
    value, shift = 0, 0
    while true
        byte = read_byte!(reader)
        value |= (byte & 127) << shift
        byte < 128 && return value
        shift += 7
    end
end

function read_zigzag!(reader)
    value = read_uleb!(reader)
    return iseven(value) ? value ÷ 2 : -(value + 1) ÷ 2
end

function read_integer!(reader; signed=false)
    value = sum(byte << (8 * (index - 1)) for (index, byte) in enumerate(read_bytes!(reader, 4)))
    return signed && value >= 2147483648 ? value - 4294967296 : value
end

function uleb_bytes(value)
    output = Int[]
    while value >= 128
        push!(output, value % 128 + 128)
        value ÷= 128
    end
    push!(output, value)
    return output
end

zigzag_bytes(value) = uleb_bytes(value >= 0 ? 2 * value : -2 * value - 1)
integer_bytes(value) = [mod(value >> (8 * index), 256) for index in 0:3]
bit_width(value) = value == 0 ? 0 : ndigits(value; base=2)
hex_bytes(data) = join(string(value; base=16, pad=2) for value in data)
hex_checksum(value) = string(value; base=16, pad=8)
ascii_bytes(text) = Int.(collect(codeunits(text)))
ascii_text(bytes) = String(UInt8.(bytes))

function pack_values(values, width)
    output = zeros(Int, length(values) * width ÷ 8)
    for (index, value) in enumerate(values), bit in 0:width - 1
        serial = (index - 1) * width + bit
        output[serial ÷ 8 + 1] |= ((value >> bit) & 1) << (serial % 8)
    end
    return output
end

function unpack_values!(reader, width, count)
    bytes = read_bytes!(reader, count * width ÷ 8)
    values = zeros(Int, count)
    for index in 0:count - 1, bit in 0:width - 1
        serial = index * width + bit
        values[index + 1] |= ((bytes[serial ÷ 8 + 1] >> (serial % 8)) & 1) << bit
    end
    return values
end

function adler32(data)
    first_sum, second_sum = 1, 0
    for byte in data
        first_sum = (first_sum + byte) % 65521
        second_sum = (second_sum + first_sum) % 65521
    end
    return second_sum * 65536 + first_sum
end

function hybrid_encode(values, width)
    count = length(values)
    runs = ones(Int, count)
    for index in count - 1:-1:1
        values[index] == values[index + 1] && (runs[index] += runs[index + 1])
    end
    output = Int[]
    index = 1
    while index <= count
        if runs[index] >= 8
            append!(output, uleb_bytes(2 * runs[index]))
            append!(output, [mod(values[index] >> (8 * byte), 256) for byte in 0:cld(width, 8) - 1])
            index += runs[index]
        else
            stop, groups = index, 0
            while true
                stop += 8
                groups += 1
                (stop > count || groups == 63 || runs[stop] >= 8) && break
            end
            append!(output, uleb_bytes(2 * groups + 1))
            block = vcat(values[index:min(stop - 1, count)], zeros(Int, max(0, stop - count - 1)))
            append!(output, pack_values(block, width))
            index = stop
        end
    end
    return output
end

function hybrid_decode!(reader, width, count)
    values = Int[]
    while length(values) < count
        header = read_uleb!(reader)
        if iseven(header)
            bytes = read_bytes!(reader, cld(width, 8))
            value = sum((byte << (8 * (index - 1)) for (index, byte) in enumerate(bytes)); init=0)
            append!(values, fill(value, header ÷ 2))
        else
            append!(values, unpack_values!(reader, width, (header - 1) ÷ 2 * 8))
        end
    end
    return values[1:count]
end
