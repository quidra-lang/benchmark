const SEQUENCE_MODULUS = 4294967296
const MARKS = ("retransmission", "out_of_order", "lost_segment", "duplicate_ack")
const Endpoint = Tuple{Int,Int}

Base.@kwdef mutable struct PreviousAck
    ack::Int
    window::Int
    number::Int
    count::Int = 0
end
Base.@kwdef mutable struct FlowSide
    name::String
    isn::Union{Nothing,Int} = nothing
    mss::Union{Nothing,Int} = nothing
    wscale::Union{Nothing,Int} = nothing
    base::Union{Nothing,Int} = nothing
    expected::Union{Nothing,Int} = nothing
    advanced_at::Union{Nothing,Int} = nothing
    intervals::Set{Tuple{Int,Int}} = Set{Tuple{Int,Int}}()
    previous_ack::Union{Nothing,PreviousAck} = nothing
    packets::Int = 0
    payload::Int = 0
    marks::Dict{String,Int} = Dict(mark=>0 for mark in MARKS)
end
Base.@kwdef mutable struct Stream
    number::Int
    client::Endpoint
    server::Endpoint
    state::String
    history::Vector{Tuple{String,Int}}
    start_time::Int
    end_time::Int
    packets::Int = 0
    bytes::Int = 0
    syn::Union{Nothing,Int} = nothing
    syn_ack::Union{Nothing,Int} = nothing
    handshake_ack::Union{Nothing,Int} = nothing
    events::Vector{Tuple{Int,String,String,Int,Int}} = Tuple{Int,String,String,Int,Int}[]
    closer::String = ""
    final_ack::Union{Nothing,Int} = nothing
    client_side::FlowSide = FlowSide(name="client")
    server_side::FlowSide = FlowSide(name="server")
end
Base.@kwdef mutable struct StreamTracker
    streams::Vector{Stream} = Stream[]
    latest::Dict{Tuple{Endpoint,Endpoint},Stream} = Dict{Tuple{Endpoint,Endpoint},Stream}()
    duplicate_acks::Dict{Int,Tuple{Int,Int}} = Dict{Int,Tuple{Int,Int}}()
end
endpoint_pair(first,second) = first <= second ? (first,second) : (second,first)
function make_segment(packet)
    value(name) = packet_value(packet,name)
    (
        packet=packet,
        number=packet.number,
        time=packet.time,
        source=(value("ip.src"),value("tcp.srcport")),
        destination=(value("ip.dst"),value("tcp.dstport")),
        seq=value("tcp.seq_raw"),
        ack=value("tcp.ack_raw"),
        fin=value("tcp.flags.fin"),
        syn=value("tcp.flags.syn"),
        rst=value("tcp.flags.rst"),
        has_ack=value("tcp.flags.ack"),
        window=value("tcp.window"),
        length=value("tcp.len")
    )
end
syn_only(segment) = segment.syn == 1 && segment.has_ack == 0
syn_ack(segment) = segment.syn == 1 && segment.has_ack == 1
function change_state!(stream,state,number)
    stream.state = state
    push!(stream.history,(state,number))
end
function record_syn!(stream,side,segment)
    side.isn = segment.seq
    side.mss = packet_value(segment.packet,"tcp.options.mss")
    side.wscale = packet_value(segment.packet,"tcp.options.wscale")
    if side.name == "client"
        stream.syn = segment.number
    else
        stream.syn_ack = segment.number
    end
end
function open_stream!(tracker,segment)
    if syn_ack(segment)
        client,server,state = segment.destination,segment.source,"SYN_RECEIVED"
    else
        client,server = segment.source,segment.destination
        state = syn_only(segment) ? "SYN_SENT" : "ESTABLISHED"
    end
    stream = Stream(
        number=length(tracker.streams),
        client=client,
        server=server,
        state=state,
        history=[(state,segment.number)],
        start_time=segment.time,
        end_time=segment.time
    )
    if syn_ack(segment)
        record_syn!(stream,stream.server_side,segment)
    elseif syn_only(segment)
        record_syn!(stream,stream.client_side,segment)
    end
    push!(tracker.streams,stream)
    stream
end
function sequence_mark(side,start,size,time)
    (isnothing(side.expected) || start == side.expected) && return nothing
    start > side.expected && return "lost_segment"
    (start,size) in side.intervals && return "retransmission"
    time-side.advanced_at < 3000 ? "out_of_order" : "retransmission"
end
function analyze_segment!(tracker,stream,side,segment,start)
    size = segment.length+segment.syn+segment.fin
    mark = nothing
    if size >= 1
        mark = sequence_mark(side,start,size,segment.time)
        push!(side.intervals,(start,size))
        if isnothing(side.expected) || start+size > side.expected
            side.expected,side.advanced_at = start+size,segment.time
        end
    elseif segment.has_ack == 1 && segment.rst == 0
        previous = side.previous_ack
        if !isnothing(previous) && segment.ack == previous.ack && segment.window == previous.window
            mark = "duplicate_ack"
            previous.count += 1
            tracker.duplicate_acks[segment.number] = (previous.number,previous.count)
        end
    end
    if segment.has_ack == 1 && mark != "duplicate_ack"
        side.previous_ack = PreviousAck(ack=segment.ack,window=segment.window,number=segment.number)
    end
    if !isnothing(mark)
        set_field!(segment.packet,"tcp.analysis."*mark,true)
        side.marks[mark] += 1
        push!(stream.events,(segment.number,side.name,mark,start,size))
    end
end
function transition!(stream,side,segment)
    state,number = stream.state,segment.number
    if segment.rst == 1
        !(state in ("CLOSED","RESET")) && change_state!(stream,"RESET",number)
    elseif state == "SYN_SENT" && syn_ack(segment) && side.name == "server" && segment.ack == mod(
        stream.client_side.isn+1,
        SEQUENCE_MODULUS
    )
        change_state!(stream,"SYN_RECEIVED",number)
        record_syn!(stream,stream.server_side,segment)
    elseif state == "SYN_RECEIVED" && side.name == "client" && segment.has_ack == 1 && segment.syn == 0 && segment.ack == mod(
        stream.server_side.isn+1,
        SEQUENCE_MODULUS
    )
        change_state!(stream,"ESTABLISHED",number)
        stream.handshake_ack = number
    elseif state == "ESTABLISHED" && segment.fin == 1
        change_state!(stream,"FIN_WAIT",number)
        stream.closer = side.name
    elseif state == "FIN_WAIT" && segment.fin == 1 && side.name != stream.closer
        change_state!(stream,"CLOSING",number)
        stream.final_ack = mod(segment.seq+segment.length+1,SEQUENCE_MODULUS)
    elseif state == "CLOSING" && side.name == stream.closer && segment.has_ack == 1 && segment.ack == stream.final_ack
        change_state!(stream,"CLOSED",number)
    end
end
function track!(tracker,packet)
    segment = make_segment(packet)
    key = endpoint_pair(segment.source,segment.destination)
    stream = get(tracker.latest,key,nothing)
    if isnothing(stream) || (stream.state in ("CLOSED","RESET") && syn_only(segment))
        stream = open_stream!(tracker,segment)
        tracker.latest[key] = stream
    end
    set_field!(packet,"tcp.stream",stream.number)
    side,other = segment.source == stream.client ? (stream.client_side,stream.server_side) : (
        stream.server_side,
        stream.client_side
    )
    isnothing(side.base) && (side.base=segment.seq)
    segment.has_ack == 1 && isnothing(other.base) && (other.base=segment.ack)
    relative_seq = mod(segment.seq-side.base,SEQUENCE_MODULUS)
    set_field!(packet,"tcp.seq",relative_seq)
    segment.has_ack == 1 && set_field!(packet,"tcp.ack",mod(segment.ack-other.base,SEQUENCE_MODULUS))
    analyze_segment!(tracker,stream,side,segment,relative_seq)
    scaled = !isnothing(stream.client_side.wscale) && !isnothing(stream.server_side.wscale)
    window = scaled && segment.syn == 0 ? segment.window*(1 << side.wscale) : segment.window
    set_field!(packet,"tcp.window.calc",window)
    transition!(stream,side,segment)
    side.packets += 1
    side.payload += segment.length
    stream.packets += 1
    stream.bytes += packet.length
    stream.end_time = segment.time
end
Base.@kwdef mutable struct Conversation
    kind::String
    endpoint_a::Endpoint
    endpoint_b::Endpoint
    first_number::Int
    first_time::Int
    last_time::Int
    packets_a_to_b::Int = 0
    bytes_a_to_b::Int = 0
    packets_b_to_a::Int = 0
    bytes_b_to_a::Int = 0
end
flow_packets(c) = c.packets_a_to_b+c.packets_b_to_a
flow_bytes(c) = c.bytes_a_to_b+c.bytes_b_to_a
function conversation_views(packet)
    source_ip,destination_ip = packet_value(packet,"ip.src"),packet_value(packet,"ip.dst")
    views = NamedTuple[(
        kind="ipv4",
        key=endpoint_pair(source_ip,destination_ip),
        source=(source_ip,-1),
        destination=(destination_ip,-1)
    )]
    if field_exists(packet,"tcp.stream")
        source,destination = (source_ip,packet_value(packet,"tcp.srcport")),(
            destination_ip,
            packet_value(packet,"tcp.dstport")
        )
        push!(views,(kind="tcp",key=packet_value(packet,"tcp.stream"),source=source,destination=destination))
    end
    if field_exists(packet,"udp.srcport")
        source,destination = (source_ip,packet_value(packet,"udp.srcport")),(
            destination_ip,
            packet_value(packet,"udp.dstport")
        )
        push!(views,(kind="udp",key=endpoint_pair(source,destination),source=source,destination=destination))
    end
    views
end
function build_conversations(packets)
    table = Dict{Any,Conversation}()
    conversations = Conversation[]
    for packet in packets
        field_exists(packet,"ip.src") || continue
        for view in conversation_views(packet)
            key = (view.kind,view.key)
            if !haskey(table,key)
                conversation = Conversation(
                    kind=view.kind,
                    endpoint_a=view.source,
                    endpoint_b=view.destination,
                    first_number=packet.number,
                    first_time=packet.time,
                    last_time=packet.time
                )
                table[key] = conversation
                push!(conversations,conversation)
            end
            conversation = table[key]
            if view.source == conversation.endpoint_a
                conversation.packets_a_to_b += 1
                conversation.bytes_a_to_b += packet.length
            else
                conversation.packets_b_to_a += 1
                conversation.bytes_b_to_a += packet.length
            end
            conversation.last_time = packet.time
        end
    end
    kinds = ("ipv4","tcp","udp")
    sort!(conversations,by=c->(-flow_bytes(c),-flow_packets(c),findfirst(==(c.kind),kinds),c.first_number))
end
Base.@kwdef mutable struct NetworkEndpoint
    address::Int
    tx_packets::Int = 0
    tx_bytes::Int = 0
    rx_packets::Int = 0
    rx_bytes::Int = 0
end
endpoint_packets(e) = e.tx_packets+e.rx_packets
endpoint_bytes(e) = e.tx_bytes+e.rx_bytes
function build_endpoints(packets)
    table = Dict{Int,NetworkEndpoint}()
    for packet in packets
        field_exists(packet,"ip.src") || continue
        source,destination = packet_value(packet,"ip.src"),packet_value(packet,"ip.dst")
        sender = get!(()->NetworkEndpoint(address=source),table,source)
        sender.tx_packets += 1
        sender.tx_bytes += packet.length
        receiver = get!(()->NetworkEndpoint(address=destination),table,destination)
        receiver.rx_packets += 1
        receiver.rx_bytes += packet.length
    end
    sort(collect(values(table)),by=e->(-endpoint_bytes(e),-endpoint_packets(e),e.address))
end
