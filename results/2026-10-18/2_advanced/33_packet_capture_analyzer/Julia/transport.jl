pseudo_header(source,destination,protocol,length) = vcat(
    integer_bytes(source,4),
    integer_bytes(destination,4),
    UInt8[0,protocol],
    integer_bytes(length,2)
)
function dissect_icmp(message)
    length(message) < 8 && throw(Malformed("icmp: truncated"))
    layer = Layer()
    type = Int(message[1])
    set_field!(layer,"icmp.type",type)
    set_field!(layer,"icmp.code",Int(message[2]))
    set_field!(layer,"icmp.checksum",read_integer(message,2,2))
    set_field!(layer,"icmp.checksum.status",checksum_status(message))
    if type in (0,8)
        set_field!(layer,"icmp.id",read_integer(message,4,2))
        set_field!(layer,"icmp.seq",read_integer(message,6,2))
    end
    layer.remaining = message[9:end]
    layer
end
function dissect_udp(datagram,source,destination)
    length(datagram) < 8 && throw(Malformed("udp: truncated"))
    size = read_integer(datagram,4,2)
    (size < 8 || size > length(datagram)) && throw(Malformed("udp: bad length $size"))
    source_port,destination_port = read_integer(datagram,0,2),read_integer(datagram,2,2)
    checksum = read_integer(datagram,6,2)
    status = checksum == 0 ? "none" : checksum_status(vcat(
        pseudo_header(source,destination,17,size),
        datagram[1:size]
    ))
    layer = Layer()
    for (name,value) in (
        ("udp.srcport",source_port),
        ("udp.dstport",destination_port),
        ("udp.length",size),
        ("udp.checksum",checksum),
        ("udp.checksum.status",status)
    )
        set_field!(layer,name,value)
    end
    payload = datagram[9:size]
    if source_port == 53 || destination_port == 53
        forward!(layer,"dns",payload)
    else
        layer.remaining = payload
    end
    layer
end
function option_text(kind,size,body,layer)
    if kind == 2
        mss = read_integer(body,0,2)
        set_field!(layer,"tcp.options.mss",mss)
        return "MSS $mss"
    elseif kind == 3
        scale = Int(body[1])
        set_field!(layer,"tcp.options.wscale",scale)
        return "WS $scale"
    elseif kind == 4
        return "SACK_PERM"
    elseif kind == 5
        return "SACK"*join((" $(read_integer(body,i,4))-$(read_integer(body,i+4,4))" for i in 0:8:(length(body)-1)))
    elseif kind == 8
        return "TS $(read_integer(body,0,4)) $(read_integer(body,4,4))"
    end
    "kind $kind len $size"
end
function parse_options!(options,layer)
    lengths = Dict(2=>(4,),3=>(3,),4=>(2,),5=>(10,18,26,34),8=>(10,))
    index = 1
    while index <= length(options)
        kind = Int(options[index])
        if kind == 0
            add_field!(layer,"tcp.option","EOL")
            return
        elseif kind == 1
            add_field!(layer,"tcp.option","NOP")
            index += 1
            continue
        end
        size = index < length(options) ? Int(options[index+1]) : 0
        if size < 2 || index+size-1 > length(options) || (haskey(lengths,kind) && !(size in lengths[kind]))
            set_field!(layer,"tcp.options.malformed",true)
            return
        end
        body = options[(index+2):(index+size-1)]
        add_field!(layer,"tcp.option",option_text(kind,size,body,layer))
        index += size
    end
end
function dissect_tcp(segment,source,destination)
    length(segment) < 20 && throw(Malformed("tcp: truncated header"))
    header = Int(segment[13])÷16*4
    header < 20 && throw(Malformed("tcp: bad header length $header"))
    header > length(segment) && throw(Malformed("tcp: truncated header"))
    flags = Int(segment[14])
    layer = Layer()
    for (name,start,count) in (
        ("tcp.srcport",0,2),
        ("tcp.dstport",2,2),
        ("tcp.seq_raw",4,4),
        ("tcp.window",14,2),
        ("tcp.checksum",16,2),
        ("tcp.urgent",18,2)
    )
        set_field!(layer,name,read_integer(segment,start,count))
    end
    set_field!(layer,"tcp.hdr_len",header)
    set_field!(layer,"tcp.flags",flags)
    for (bit,name) in enumerate(("fin","syn","rst","psh","ack","urg"))
        set_field!(layer,"tcp.flags."*name,(flags >> (bit-1)) & 1)
    end
    set_field!(
        layer,
        "tcp.checksum.status",
        checksum_status(vcat(pseudo_header(source,destination,6,length(segment)),segment))
    )
    set_field!(layer,"tcp.len",length(segment)-header)
    flags & 16 != 0 && set_field!(layer,"tcp.ack_raw",read_integer(segment,8,4))
    parse_options!(segment[21:header],layer)
    layer.remaining = segment[(header+1):end]
    layer
end
