const QR_ALPHANUMERIC = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ \$%*+-./:"
const QR_ALPHA_VALUES = Dict(character => index - 1 for (index, character) in enumerate(QR_ALPHANUMERIC))

binary_digits(value, width) = string(value; base=2, pad=width)
codeword_bits(words) = join(binary_digits(value, 8) for value in words)
hex_words(words) = join(string(value; base=16, pad=2) for value in words)

function bits_codewords(bits)
    return [parse(Int, bits[index:index + 7]; base=2) for index in 1:8:length(bits)]
end

mutable struct QRBitReader
    bits::String
    position::Int
end

remaining_bits(reader) = length(reader.bits) - reader.position

function read_bits!(reader, width)
    start = reader.position + 1
    reader.position += width
    return parse(Int, reader.bits[start:reader.position]; base=2)
end

mutable struct QRBitWriter
    parts::Vector{String}
end

function write_bits!(writer, value, width)
    push!(writer.parts, binary_digits(value, width))
end

bit_value(writer) = join(writer.parts)
