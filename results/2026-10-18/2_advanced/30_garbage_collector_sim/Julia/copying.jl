function allocate_copying!(state,obj,roots,line)
    half = state.size÷2
    if state.top+obj.size > state.base+half
        record = CollectionRecord(length(state.records)+1,line,obj.size,"copy",free_list(state))
        state.base = half-state.base
        state.top = state.base
        copied = Set{Int}()
        queue = HeapObject[]
        function copy_object!(id)
            (id == 0 || id in copied) && return
            push!(copied,id)
            object = state.placed[id]
            object.address = state.top
            state.top += object.size
            object.moves += 1
            add_object!(record.live,object)
            add_object!(record.moved,object)
            push!(queue,object)
        end
        record.work += length(roots)
        foreach(copy_object!,roots)
        index = 1
        while index <= length(queue)
            object = queue[index]
            index += 1
            record.work += object.size+length(object.fields)
            foreach(copy_object!,object.fields)
        end
        for object in state.objects
            !(object.number in copied) && add_object!(record.freed,object)
        end
        state.objects = queue
        finish_record!(state,record)
    end
    state.top+obj.size > state.base+half && return false
    obj.address = state.top
    state.top += obj.size
    push!(state.objects,obj)
    true
end
