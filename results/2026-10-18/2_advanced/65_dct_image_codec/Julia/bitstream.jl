struct CodecDecodeError <: Exception
    kind::String
end
Base.@kwdef mutable struct BitWriter
    data::Vector{Int} = Int[]
    buffer::Int = 0
    pending::Int = 0
    padding_bits::Int = 0
    stuffed_bytes::Int = 0
end
function write_bits!(writer,value,width)
    for shift in width-1:-1:0
        writer.buffer = 2*writer.buffer+((value>>shift)&1)
        writer.pending += 1
        if writer.pending==8
            push!(writer.data,writer.buffer)
            if writer.buffer==255
                push!(writer.data,0)
                writer.stuffed_bytes += 1
            end
            writer.buffer,writer.pending = 0,0
        end
    end
end
function pad_bits!(writer)
    if writer.pending!=0
        width = 8-writer.pending
        writer.padding_bits += width
        write_bits!(writer,(1<<width)-1,width)
    end
end
function restart!(writer,number)
    pad_bits!(writer)
    append!(writer.data,[255,208+number%8])
end
mutable struct BitReader
    data::Vector{Int}
    position::Int
    buffer::Int
    remaining::Int
end
BitReader(data,position) = BitReader(data,position,0,0)
function read_bit!(reader)
    if reader.remaining==0
        value = reader.data[reader.position+1]
        if value==255
            reader.data[reader.position+2]!=0 && throw(CodecDecodeError("marker"))
            reader.position += 2
        else
            reader.position += 1
        end
        reader.buffer,reader.remaining = value,8
    end
    reader.remaining -= 1
    (reader.buffer>>reader.remaining)&1
end
function read_bits!(reader,width)
    value = 0
    for _ in 1:width
        value = 2value+read_bit!(reader)
    end
    value
end
discard_bits!(reader) = ((reader.buffer,reader.remaining)=(0,0))
function find_resync(data,position)
    for offset in position:length(data)-2
        if data[offset+1]==255 && (208<=data[offset+2]<=215 || data[offset+2]==217)
            return offset
        end
    end
    error("missing resynchronization marker")
end
