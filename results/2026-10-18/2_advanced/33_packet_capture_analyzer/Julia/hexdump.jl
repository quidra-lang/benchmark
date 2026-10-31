mutable struct Packet
    number::Int
    time::Int
    length::Int
    data::Vector{UInt8}
    error::Union{Nothing,String}
    layers::Vector{String}
    fields::Dict{String,Vector{Any}}
    remaining::Vector{UInt8}
end
Packet(n,t,length) = Packet(n,t,length,UInt8[],nothing,String[],Dict{String,Vector{Any}}(),UInt8[])
field_values(packet,name) = get(packet.fields,name,Any[])
packet_value(packet,name) = (values=field_values(packet,name); isempty(values) ? nothing : values[1])
field_exists(packet,name) = haskey(packet.fields,name)
set_field!(object,name,value) = (object.fields[name]=Any[value])
add_field!(object,name,value) = push!(get!(()->Any[],object.fields,name),value)
function read_capture(path)
    packets = Packet[]
    lines_by_packet = Vector{Tuple{Int,String}}[]
    for (number,line) in enumerate(readlines(path))
        if startswith(line,"PACKET ")
            fields = split(line)
            push!(packets,Packet(parse.(Int,fields[2:4])...))
            push!(lines_by_packet,Tuple{Int,String}[])
        elseif !isempty(line)
            push!(lines_by_packet[end],(number,line))
        end
    end
    for (packet,lines) in zip(packets,lines_by_packet)
        data = UInt8[]
        for (number,line) in lines
            if !occursin(r"^[0-9a-f]{4}  [0-9a-f]{2}(?: [0-9a-f]{2}){0,15}$",line)
                packet.error = "dump: bad line $number"
                break
            elseif parse(Int,line[1:4],base=16) != length(data)
                packet.error = "dump: offset mismatch at line $number"
                break
            end
            append!(data,[parse(UInt8,byte,base=16) for byte in split(line[7:end])])
        end
        if isnothing(packet.error)
            if length(data) != packet.length
                packet.error = "dump: length mismatch (header $(packet.length), data $(length(data)))"
            else
                packet.data = data
            end
        end
    end
    packets
end
function hex_dump_lines(data)
    lines = String[]
    for offset in 0:16:(length(data)-1)
        piece = data[(offset+1):min(offset+16,length(data))]
        hex = join((string(byte,base=16,pad=2) for byte in piece),' ')
        text = String([32 <= byte <= 126 ? Char(byte) : '.' for byte in piece])
        push!(lines,"$(string(offset,base=16,pad=4))  $(rpad(hex,47))  |$text|")
    end
    lines
end
