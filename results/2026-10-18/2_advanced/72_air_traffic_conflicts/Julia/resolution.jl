function priority_order(first,second,a,b)
    (first.departure+first.delay,first.callsign)>(
        second.departure+second.delay,
        second.callsign
    ) ? (a,b) : (b,a)
end
function manoeuvres(max_delay)
    result = [("level_up",10),("level_down",-10),("speed_down",0)]
    append!(result,[("delay_$delay",delay) for delay in 60:60:max_delay])
    result
end
function propose(plan,name,amount,types,params)
    changed = (;plan...,history=copy(plan.history))
    if name in ("level_up","level_down")
        changed = (;changed...,offset=changed.offset+amount)
        any(l->l<params.level_min || l>params.level_max,level_list(changed)) && return nothing
    elseif name=="speed_down"
        changed = (;changed...,speed=changed.speed*9÷10)
        changed.speed<types[changed.type].minimum && return nothing
    else
        changed = (;changed...,delay=changed.delay+amount)
    end
    changed
end
