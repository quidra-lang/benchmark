struct BGPMessage
    serial::Int
    sender::Int
    receiver::Int
    link::Int
    prefix::IPPrefix
    content::Any
    arrival::Int
end
message_key(message) = (message.arrival, message.receiver, message.sender, message.serial)
mutable struct BGPMessageQueue
    heap::Vector{BGPMessage}
    serial::Int
end
BGPMessageQueue() = BGPMessageQueue(BGPMessage[], 0)

function heap_push!(queue, message)
    push!(queue.heap, message)
    index = length(queue.heap)
    while index > 1
        parent = index ÷ 2
        message_key(queue.heap[parent]) <= message_key(queue.heap[index]) && break
        queue.heap[parent], queue.heap[index] = queue.heap[index], queue.heap[parent]
        index = parent
    end
end

function send_message!(queue, time, sender, receiver, link, prefix, content)
    queue.serial += 1
    message = BGPMessage(queue.serial, sender, receiver, link.number, prefix, content, time + link.delay)
    heap_push!(queue, message)
    return message
end

next_message_time(queue) = isempty(queue.heap) ? nothing : queue.heap[1].arrival
ordered_messages(queue) = sort(queue.heap; by=message_key)

function take_message!(queue)
    result = queue.heap[1]
    last_message = pop!(queue.heap)
    if !isempty(queue.heap)
        queue.heap[1] = last_message
        index = 1
        while 2 * index <= length(queue.heap)
            child = 2 * index
            child < length(queue.heap) && message_key(queue.heap[child + 1]) < message_key(queue.heap[child]) && (child += 1)
            message_key(queue.heap[index]) <= message_key(queue.heap[child]) && break
            queue.heap[index], queue.heap[child] = queue.heap[child], queue.heap[index]
            index = child
        end
    end
    return result
end

function remove_link_messages!(queue, link)
    removed = [message for message in ordered_messages(queue) if message.link == link]
    kept = [message for message in queue.heap if message.link != link]
    empty!(queue.heap)
    for message in kept
        heap_push!(queue, message)
    end
    return removed
end

function read_events()
    events = Any[(time=0, text="INITIAL", fields=["INITIAL"], kind="INITIAL")]
    for line in readlines("input/events.txt")
        time, text = split(line, ' '; limit=2)
        fields = String.(split(text, ' '))
        kind = fields[1] in ("LINK", "POLICY") ? join(fields[1:2], "_") : fields[1]
        push!(events, (time=parse(Int, time), text=String(text), fields=fields, kind=kind))
    end
    return events
end

function read_params()
    lines = readlines("input/params.txt")
    defaults = Dict(role => parse(Int, value) for (role, value) in zip(
        ("customer", "peer", "provider"),
        split(lines[1], ' ')[2:end]
    ))
    stepcap = parse(Int, split(lines[2], ' ')[2])
    traces = Tuple{Int,String,Int}[]
    for line in lines[3:end]
        fields = split(line, ' ')
        push!(traces, (parse(Int, fields[2]), String(fields[3]), address_value(fields[3])))
    end
    return defaults, stepcap, traces
end
