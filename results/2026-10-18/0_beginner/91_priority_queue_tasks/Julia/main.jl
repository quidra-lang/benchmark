function heap_push!(heap,task)
    push!(heap,task)
    child = length(heap)
    while child > 1
        parent = div(child,2)
        !isless(heap[child],heap[parent]) && break
        heap[child],heap[parent] = heap[parent],heap[child]
        child = parent
    end
end
function heap_pop!(heap)
    task = heap[1]
    last = pop!(heap)
    if !isempty(heap)
        heap[1] = last
        parent = 1
        while 2*parent <= length(heap)
            child = 2*parent
            if child < length(heap) && isless(heap[child+1],heap[child])
                child += 1
            end
            !isless(heap[child],heap[parent]) && break
            heap[child],heap[parent] = heap[parent],heap[child]
            parent = child
        end
    end
    return task
end
function main()
    operations = ["add email 3","add backup 5","add deploy 1","run","add report 3","add test 2","add lint 3","run","run","add cleanup 5","add review 2","run","add build 1","add docs 4","run","run"]
    heap = Tuple{Int,Int,String}[]
    for (sequence,operation) in enumerate(operations)
        parts = split(operation)
        if parts[1] == "add"
            heap_push!(heap,(parse(Int,parts[3]),sequence,String(parts[2])))
        else
            priority,_,name = heap_pop!(heap)
            println("run: ",name," (priority ",priority,")")
        end
    end
    remaining = String[]
    while !isempty(heap)
        push!(remaining,heap_pop!(heap)[3])
    end
    println("remaining: ",join(remaining," "))
end
main()
