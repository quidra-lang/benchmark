function mark!(record,roots,objects,placed)
    for obj in objects
        obj.marked = false
    end
    record.work += length(roots)
    stack = Int[]
    function push_mark!(id)
        placed[id].marked = true
        push!(stack,id)
        record.stack = max(record.stack,length(stack))
    end
    for root in roots
        (root == 0 || placed[root].marked) && continue
        push_mark!(root)
        while !isempty(stack)
            obj = placed[pop!(stack)]
            add_object!(record.live,obj)
            record.work += 1+length(obj.fields)
            for id in obj.fields
                id != 0 && !placed[id].marked && push_mark!(id)
            end
        end
    end
end
function sweep!(state,record)
    record.work += length(state.objects)
    for obj in state.objects
        !obj.marked && add_object!(record.freed,obj)
    end
    filter!(obj->obj.marked,state.objects)
end
function collect_sweep!(state,roots,line,request)
    record = CollectionRecord(length(state.records)+1,line,request,"sweep",free_list(state))
    mark!(record,roots,state.objects,state.placed)
    sweep!(state,record)
    finish_record!(state,record)
end
function allocate_sweep!(state,obj,roots,line)
    address = first_fit(free_list(state),obj.size)
    if isnothing(address)
        state.kind == "REFCOUNT" ? collect_backup!(state,roots,line,obj.size) : collect_sweep!(
            state,
            roots,
            line,
            obj.size
        )
        address = first_fit(free_list(state),obj.size)
        isnothing(address) && return false
    end
    obj.address = address
    push!(state.objects,obj)
    true
end
function allocate_compact!(state,obj,roots,line)
    if state.top+obj.size > state.size
        record = CollectionRecord(length(state.records)+1,line,obj.size,"compact",free_list(state))
        mark!(record,roots,state.objects,state.placed)
        record.work += length(state.objects)+length(roots)
        destination = 0
        survivors = HeapObject[]
        for object in by_address(state.objects)
            if !object.marked
                add_object!(record.freed,object)
                continue
            end
            record.work += length(object.fields)
            if object.address != destination
                add_object!(record.moved,object)
                record.work += object.size
                object.address = destination
                object.moves += 1
            end
            destination += object.size
            push!(survivors,object)
        end
        state.objects,state.top = survivors,destination
        finish_record!(state,record)
    end
    state.top+obj.size > state.size && return false
    obj.address = state.top
    state.top += obj.size
    push!(state.objects,obj)
    true
end
