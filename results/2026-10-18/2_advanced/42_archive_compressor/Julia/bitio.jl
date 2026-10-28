struct DecodeError <: Exception
    kind::String
    position::Int
end
mutable struct BitWriter
    bytes::Vector{Int}
    partial::Int
    used::Int
    count::Int
end
BitWriter() = BitWriter(Int[],0,0,0)
function write_bits!(writer,value,width)
    for shift in width-1:-1:0
        writer.partial = 2writer.partial+((value>>shift)&1)
        writer.used += 1
        if writer.used==8
            push!(writer.bytes,writer.partial)
            writer.partial,writer.used = 0,0
        end
    end
    writer.count += width
end
finish(writer) = writer.used==0 ? copy(writer.bytes) : vcat(writer.bytes,writer.partial<<(8-writer.used))
mutable struct BitReader
    bytes::Vector{Int}
    position::Int
    zero_fill::Bool
end
BitReader(bytes;zero_fill=false) = BitReader(bytes,0,zero_fill)
function read_bits!(reader,width,position=0)
    limit = 8length(reader.bytes)
    !reader.zero_fill && reader.position+width>limit && throw(DecodeError("end_of_data",position))
    value = 0
    for _ in 1:width
        value *= 2
        if reader.position<limit
            value += (reader.bytes[reader.position÷8+1]>>(7-reader.position%8))&1
        end
        reader.position += 1
    end
    value
end
function bits(value)
    width = 0
    while value>0
        value >>= 1
        width += 1
    end
    width
end
