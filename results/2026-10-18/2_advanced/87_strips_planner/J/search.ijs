action_applicable =: 4 : '(*/(3{::x)<:y)*.-.+./(4{::x)*.y'
apply_action =: 4 : '(y*.-.6{::x)+.5{::x'
goal_state =: 3 : '*/HGoal<:y'
search_result =: 3 : 0
    'status expanded generated plan' =. y
    (<status),(<expanded),(<generated),<plan
)
reconstruct_plan =: 4 : 0
    node =. y
    plan =. i.0
    while. _1~:3{node{x do.
        plan =. plan,4{node{x
        node =. 3{node{x
    end.
    |.plan
)
search_priority =: 4 : 0
    'algorithm heuristic weight' =. x
    'cost depth' =. y
    select. algorithm
    case. 'bfs' do. depth
    case. 'ucs' do. cost
    case. 'gbfs' do. heuristic
    case. 'astar' do. cost+heuristic
    case. 'wastar' do. cost+weight*heuristic
    end.
)
key_less =: 4 : 0
    differences =. I.x~:y
    if. #differences do.
        position =. {.differences
        (position{x)<position{y
    else.
        0
    end.
)
heap_push =: 4 : 0
    heap =. x,y
    position =. (#heap)-1
    while. position>0 do.
        parent =. (position-1)intdiv 2
        if. -.y key_less parent{heap do.
            break.
        end.
        heap =. (parent{heap)position}heap
        position =. parent
    end.
    y position}heap
)
heap_pop =: 3 : 0
    entry =. 0{y
    last =. _1{y
    heap =. }:y
    if. #heap do.
        position =. 0
        while. (1+2*position)<#heap do.
            child =. 1+2*position
            if. (child+1)<#heap do.
                if. ((child+1){heap)key_less child{heap do.
                    child =. child+1
                end.
            end.
            if. -. (child{heap)key_less last do.
                break.
            end.
            heap =. (child{heap)position}heap
            position =. child
        end.
        heap =. last position}heap
    end.
    (<entry),<heap
)
best_first =: 3 : 0
    'start algorithm heuristic budget weight' =. y
    initial_h =. heuristic heuristic_value start
    if. initial_h=_1 do.
        (<'dead end'),(<0),(<0),<i.0 return.
    end.
    states =. ,<start
    best =. ,0
    nodes =. ,:0 0 0 _1 _1
    f =. ((<algorithm),(<initial_h),<weight)search_priority 0 0
    heap =. ,:f,initial_h,0,0
    serial =. 1
    expanded =. 0
    generated =. 0
    reopen =. (<algorithm)e.;:'ucs astar wastar'
    status =. 'exhausted'
    plan =. i.0
    while. #heap do.
        'entry heap' =. heap_pop heap
        node_number =. 3{entry
        'state_index cost depth parent incoming' =. node_number{nodes
        state =. state_index{::states
        if. reopen*.cost>state_index{best do.
            continue.
        end.
        if. goal_state state do.
            status =. 'solved'
            plan =. nodes reconstruct_plan node_number
            break.
        end.
        if. expanded=budget do.
            status =. 'budget'
            break.
        end.
        expanded =. expanded+1
        for_number. i.#HActions do.
            action =. number{::HActions
            if. -.action action_applicable state do.
                continue.
            end.
            successor =. action apply_action state
            generated =. generated+1
            next_cost =. cost+2{::action
            index =. states i.<successor
            if. index<#states do.
                if. (-.reopen)+.(index{best)<:next_cost do.
                    continue.
                end.
                best =. next_cost index}best
            else.
                states =. states,<successor
                best =. best,next_cost
            end.
            value =. heuristic heuristic_value successor
            if. value=_1 do.
                continue.
            end.
            child =. #nodes
            nodes =. nodes,index,next_cost,(depth+1),node_number,number
            f =. ((<algorithm),(<value),<weight)search_priority next_cost,depth+1
            heap =. heap heap_push f,value,serial,child
            serial =. serial+1
        end.
    end.
    (<status),(<expanded),(<generated),<plan
)
hill_climbing =: 3 : 0
    'current heuristic budget' =. y
    current_h =. heuristic heuristic_value current
    expanded =. 0
    generated =. 0
    plan =. i.0
    if. current_h=_1 do.
        (<'dead end'),(<0),(<0),<i.0 return.
    end.
    while. -.goal_state current do.
        queue =. ,<(<current),<i.0
        front =. 0
        visited =. ,<current
        improved =. 0
        while. (front<#queue)*.-.improved do.
            'state prefix' =. front{::queue
            front =. front+1
            if. expanded=budget do.
                (<'budget'),(<expanded),(<generated),<i.0 return.
            end.
            expanded =. expanded+1
            for_number. helpful_actions state do.
                action =. number{::HActions
                successor =. action apply_action state
                generated =. generated+1
                if. (<successor)e.visited do.
                    continue.
                end.
                visited =. visited,<successor
                value =. heuristic heuristic_value successor
                if. value=_1 do.
                    continue.
                end.
                path =. prefix,number
                if. value<current_h do.
                    plan =. plan,path
                    current =. successor
                    current_h =. value
                    improved =. 1
                    break.
                end.
                queue =. queue,<( <successor),<path
            end.
        end.
        if. -.improved do.
            (<'stuck'),(<expanded),(<generated),<i.0 return.
        end.
    end.
    (<'solved'),(<expanded),(<generated),<plan
)
search_run =: 3 : 0
    'start algorithm heuristic budget weight' =. y
    if. algorithm-:'ehc' do.
        hill_climbing(<start),(<heuristic),<budget
    else.
        best_first y
    end.
)
