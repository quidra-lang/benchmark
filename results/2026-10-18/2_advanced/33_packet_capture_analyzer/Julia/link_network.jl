struct Malformed <: Exception
    reason::String
end
Base.showerror(io::IO,error::Malformed) = print(io,error.reason)
mutable struct Layer
    fields::Dict{String,Vector{Any}}
    next_layer::Union{Nothing,String}
    payload::Vector{UInt8}
    remaining::Vector{UInt8}
end
Layer() = Layer(Dict{String,Vector{Any}}(),nothing,UInt8[],UInt8[])
function read_integer(data,index,count)
    value = 0
    for i in (index+1):(index+count)
        value = value*256+Int(data[i])
    end
    value
end
integer_bytes(value,count) = [UInt8((value >> (8*i)) & 255) for i in (count-1):-1:0]
function checksum_status(data)
    total = 0
    for i in 1:2:length(data)
        total += Int(data[i])*256+(i < length(data) ? Int(data[i+1]) : 0)
    end
    while total > 65535
        total = total%65536+total÷65536
    end
    total == 65535 ? "good" : "bad"
end
mac_notation(value) = join((string(byte,base=16,pad=2) for byte in integer_bytes(value,6)),':')
ipv4_notation(value) = join(Int.(integer_bytes(value,4)),'.')
function forward!(layer,name,payload)
    layer.next_layer,layer.payload = name,payload
end
function dissect_ethernet(frame)
    length(frame) < 14 && throw(Malformed("eth: truncated"))
    layer = Layer()
    type = read_integer(frame,12,2)
    set_field!(layer,"eth.dst",read_integer(frame,0,6))
    set_field!(layer,"eth.src",read_integer(frame,6,6))
    set_field!(layer,"eth.type",type)
    payload = frame[15:end]
    if type in (2054,2048)
        forward!(layer,type == 2054 ? "arp" : "ip",payload)
    else
        layer.remaining = payload
    end
    layer
end
function dissect_arp(message)
    length(message) < 28 && throw(Malformed("arp: truncated"))
    if read_integer(message,0,2) != 1 || read_integer(
        message,
        2,
        2
    ) != 2048 || message[5] != 6 || message[6] != 4
        throw(Malformed("arp: unsupported format"))
    end
    layer = Layer()
    for (name,start,count) in (
        ("arp.opcode",6,2),
        ("arp.src.hw",8,6),
        ("arp.src.ip",14,4),
        ("arp.dst.hw",18,6),
        ("arp.dst.ip",24,4)
    )
        set_field!(layer,name,read_integer(message,start,count))
    end
    layer
end
function dissect_ipv4(datagram)
    available = length(datagram)
    available < 20 && throw(Malformed("ip: truncated header"))
    version = Int(datagram[1])÷16
    version != 4 && throw(Malformed("ip: bad version $version"))
    header = Int(datagram[1])%16*4
    header < 20 && throw(Malformed("ip: bad header length $header"))
    available < header && throw(Malformed("ip: truncated header"))
    total = read_integer(datagram,2,2)
    total < header && throw(Malformed("ip: bad total length $total"))
    total > available && throw(Malformed("ip: truncated (total length $total, available $available)"))
    flags = read_integer(datagram,6,2)
    more,offset = flags÷8192%2,flags%8192*8
    protocol = Int(datagram[10])
    layer = Layer()
    entries = (
        ("ip.hdr_len",header),
        ("ip.tos",Int(datagram[2])),
        ("ip.len",total),
        ("ip.id",read_integer(datagram,4,2)),
        ("ip.flags.df",flags÷16384%2),
        ("ip.flags.mf",more),
        ("ip.frag_offset",offset),
        ("ip.ttl",Int(datagram[9])),
        ("ip.proto",protocol),
        ("ip.checksum",read_integer(datagram,10,2)),
        ("ip.checksum.status",checksum_status(datagram[1:header])),
        ("ip.src",read_integer(datagram,12,4)),
        ("ip.dst",read_integer(datagram,16,4))
    )
    for (name,value) in entries
        set_field!(layer,name,value)
    end
    payload = datagram[(header+1):total]
    if more == 1 || offset != 0
        set_field!(layer,"ip.fragment",true)
        layer.remaining = payload
    elseif protocol in (1,17,6)
        forward!(layer,protocol == 1 ? "icmp" : protocol == 17 ? "udp" : "tcp",payload)
    else
        layer.remaining = payload
    end
    layer
end
