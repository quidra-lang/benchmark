module ConversationMemory

mutable struct Queue
    capacity::Int
    texts::Vector{String}
    log::Vector{String}
end

Queue(capacity) = Queue(capacity, String[], String[])

function store!(queue, prefix, keyword, text)
    if text in queue.texts
        push!(queue.log, "$prefix SKIP $keyword $text")
        return false
    end
    if length(queue.texts) == queue.capacity
        push!(queue.log, "$prefix DROP $(popfirst!(queue.texts))")
    end
    push!(queue.texts, text)
    push!(queue.log, "$prefix STORE $keyword $text")
    return true
end

function recall!(queue, prefix)
    text = popfirst!(queue.texts)
    push!(queue.log, "$prefix RECALL $text")
    return text
end

function clear!(queue, prefix)
    if !isempty(queue.texts)
        push!(queue.log, "$prefix CLEAR $(length(queue.texts))")
        empty!(queue.texts)
    end
end

end
