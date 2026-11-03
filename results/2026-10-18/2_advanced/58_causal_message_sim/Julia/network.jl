mutable struct MINSTD
    state::Int
    draws::Int
end
function draw!(generator)
    generator.state = (48271generator.state)%2147483647
    generator.draws += 1
    generator.state
end
Base.@kwdef mutable struct NetworkChannel
    source::Int
    destination::Int
    kind::String
    minimum::Int
    maximum::Int
    sequence::Int = 0
    last_arrival::Int = 0
    messages::Int = 0
    markers::Int = 0
    buffered::Int = 0
    max_delay::Int = 0
    entries::Int = 0
    previous_vector::Vector{Int}
end
Base.@kwdef mutable struct Packet
    packet_type::Symbol
    message::Int = 0
    snapshot::Int = 0
    source::Int = 0
    destination::Int = 0
    sequence::Int = 0
    dispatch_time::Int = 0
    arrival_time::Int = 0
    fifo_wait::Bool = false
    causal_wait::Bool = false
    missing::Vector{Int} = Int[]
    recv_event::Int = 0
    delivery_time::Int = 0
end
Base.@kwdef mutable struct Message
    id::Int
    kind::String
    source::Int
    tag::String
    amount::Int
    stamp::Vector{Int}
    copies::Vector{Int} = Int[]
    send_event::Int = 0
    send_time::Int = 0
end
function read_topology()
    rows = String.(readlines(joinpath("input","topology.txt")))
    names = String.(split(rows[1]))[2:end]
    indices = Dict(name=>i for (i,name) in enumerate(names))
    channels = Dict{Tuple{Int,Int},NetworkChannel}()
    for row in rows[2:end]
        words = String.(split(row))
        source,destination = indices[words[2]],indices[words[3]]
        low = parse(Int,words[5])
        high = length(words)==6 ? parse(Int,words[6]) : low
        channels[(source,destination)] = NetworkChannel(
            source=source,
            destination=destination,
            kind=words[4],
            minimum=low,
            maximum=high,
            previous_vector=zeros(Int,length(names))
        )
    end
    names,channels,sort(collect(keys(channels)))
end
function dispatch!(channel,packet,time,generator,vector,enqueue)
    channel.sequence += 1
    packet.sequence = channel.sequence
    packet.source,packet.destination,packet.dispatch_time = channel.source,channel.destination,time
    delay = channel.minimum==channel.maximum ? channel.minimum : channel.minimum+draw!(generator)%(channel.maximum-channel.minimum+1)
    arrival = time+delay
    channel.kind=="FIFO" && (arrival=max(arrival,channel.last_arrival))
    channel.last_arrival = max(channel.last_arrival,arrival)
    packet.arrival_time = arrival
    channel.max_delay = max(channel.max_delay,arrival-time)
    if packet.packet_type==:marker
        channel.markers += 1
    else
        channel.messages += 1
        channel.entries += count(pair->pair[1]!=pair[2],zip(channel.previous_vector,vector))
        channel.previous_vector = copy(vector)
    end
    enqueue(arrival,channel.destination)
end
delay_notation(channel) = channel.minimum==channel.maximum ? string(channel.minimum) : "$(channel.minimum)-$(channel.maximum)"
