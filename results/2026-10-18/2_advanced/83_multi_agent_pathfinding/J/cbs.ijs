path_position =: 4 : '(x<.(#y)-1){y'
plan_conflicts =: 3 : 0
    horizon =. >./(#&>y)-1
    conflicts =. 0 6$0
    for_time. 1+i.horizon do.
        for_first. i.NumberAgents do.
            path_a =. first{::y
            current_a =. time path_position path_a
            past_a =. (time-1)path_position path_a
            for_second. (first+1)+i.NumberAgents-(first+1) do.
                path_b =. second{::y
                current_b =. time path_position path_b
                if. current_a=current_b do.
                    conflicts =. conflicts,0,time,first,second,current_a,current_a
                elseif. (current_a=(time-1)path_position path_b)*.current_b=past_a do.
                    conflicts =. conflicts,1,time,first,second,past_a,current_a
                end.
            end.
        end.
    end.
    conflicts
)
split_constraints =: 3 : 0
    'kind time first second source destination' =. y
    if. kind=0 do.
        (first,0,destination,destination,time),:second,0,destination,destination,time
    else.
        (first,1,source,destination,time),:second,1,destination,source,time
    end.
)
plan_cost =: 4 : 0
    lengths =. (#&>y)-1
    if. x=0 do.
        +/lengths
    else.
        >./lengths
    end.
)
new_node =: 4 : 0
    'number depth parent' =. x
    'paths restrictions cost_function' =. y
    conflicts =. plan_conflicts paths
    cost =. cost_function plan_cost paths
    (<paths),(<restrictions),(<number),(<depth),(<parent),(<conflicts),<cost
)
node_key =: 3 : '(6{::y),(#5{::y),(2{::y),2{::y'
