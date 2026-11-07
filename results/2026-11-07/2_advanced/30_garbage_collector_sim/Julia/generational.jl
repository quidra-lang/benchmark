function write_barrier!(state,target,value)
    is_young(state,target) && return
    state.barriers += 1
    if value != 0 && is_young(state,state.placed[value]) && !(target.number in state.remembered)
        push!(state.remembered,target.number)
        state.remembers += 1
    end
end
function collect_generational!(state,kind,roots,line,request)
    record = CollectionRecord(length(state.records)+1,line,request,kind,free_list(state))
    marking = kind in ("major","full")
    tenuring = kind in ("tenure","full")
    if marking
        mark!(record,roots,state.objects,state.placed)
        survivors = HeapObject[]
        for object in state.objects
            if is_young(state,object)
                push!(survivors,object)
            else
                record.work += 1
                if object.marked
                    push!(survivors,object)
                else
                    add_object!(record.freed,object)
                    delete!(state.remembered,object.number)
                end
            end
        end
        state.objects = survivors
    end
    pending = Set(object.number for object in state.objects if is_young(state,object))
    destination = state.young÷2-state.base
    target = destination
    queue = HeapObject[]
    function evacuate!(id)
        (id == 0 || !(id in pending)) && return true
        delete!(pending,id)
        object = state.placed[id]
        object.age += 1
        object.moves += 1
        if tenuring || object.age >= state.promotion_age
            address = first_fit(old_blocks(state),object.size)
            isnothing(address) && return false
            object.address = address
            add_object!(record.promoted,object)
        else
            object.address = target
            target += object.size
        end
        add_object!(record.moved,object)
        !marking && add_object!(record.live,object)
        push!(queue,object)
        true
    end
    record.work += length(roots)
    for root in roots
        evacuate!(root) || return false
    end
    for object in by_address(state.placed[collect(state.remembered)])
        record.work += 1+length(object.fields)
        for id in object.fields
            evacuate!(id) || return false
        end
    end
    index = 1
    while index <= length(queue)
        object = queue[index]
        index += 1
        record.work += object.size+length(object.fields)
        for id in object.fields
            evacuate!(id) || return false
        end
    end
    for object in state.objects
        object.number in pending && add_object!(record.freed,object)
    end
    filter!(object->!(object.number in pending),state.objects)
    state.base,state.top = destination,target
    state.remembered = Set(object.number for object in state.objects if !is_young(state,object) && any(id != 0 && is_young(
        state,
        state.placed[id]
    ) for id in object.fields))
    finish_record!(state,record)
    true
end
function allocate_generational!(state,obj,roots,line)
    fits() = state.top+obj.size <= state.base+state.young÷2
    for step in 0:2
        if fits()
            obj.address = state.top
            state.top += obj.size
            push!(state.objects,obj)
            return true
        end
        step == 2 && break
        kind = largest_free(old_blocks(state)) < state.top-state.base ? (step == 0 ? "major" : "full") : (step == 0 ? "minor" : "tenure")
        collect_generational!(state,kind,roots,line,obj.size) || return false
    end
    false
end
