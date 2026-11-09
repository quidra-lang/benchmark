empty_prohibitions =: 3 : '( <0 2$0),(<0 3$0),<0 2$0'
state_allowed =: 4 : 0
    'cell time' =. y
    'states moves permanent' =. x
    if. +./(cell,time)-:"1 states do.
        0 return.
    end.
    -.+./(cell=0{"1 permanent)*.time>:1{"1 permanent
)
action_allowed =: 4 : 0
    'source destination time' =. y
    if. -.x state_allowed destination,time do.
        0 return.
    end.
    if. source=destination do.
        1 return.
    end.
    -.+./(source,destination,time)-:"1 (1{::x)
)
arrival_allowed =: 4 : 0
    states =. 0{::x
    times =. 1{"1 states#~y=0{"1 states
    if. #times do.
        1+>./times
    else.
        0
    end.
)
reserve_path =: 4 : 0
    'path start permanent_goal' =. y
    'states moves permanent' =. x
    for_step. i.#path do.
        cell =. step{path
        time =. start+step
        states =. states,cell,time
        if. step>0 do.
            source =. (step-1){path
            if. source~:cell do.
                moves =. moves,cell,source,time
            end.
        end.
    end.
    if. permanent_goal do.
        permanent =. permanent,({:path),(start+#path)-1
    end.
    (<~.states),(<~.moves),<~.permanent
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
low_search =: 3 : 0
    'agent start t0 restrictions tmax window' =. y
    LLSearches =: LLSearches+1
    beginning =. LLExpansions
    goal =. agent{Goals
    distance =. agent{Distances
    arrival =. restrictions arrival_allowed goal
    parents =. ((tmax+1)*NumberCells)$_2
    initial =. start+NumberCells*t0
    parents =. _1 initial}parents
    heap =. ,:(start{distance),0,0,initial
    insertion =. 0
    while. #heap do.
        'entry heap' =. heap_pop heap
        state =. 3{entry
        cell =. NumberCells|state
        time =. state intdiv NumberCells
        LLExpansions =: LLExpansions+1
        if. (LLLimit~:_1)*.LLExpansions>LLLimit do.
            (<_1),(<i.0),<LLExpansions-beginning return.
        end.
        if. ((cell=goal)*.time>:arrival)+.(window*.time=tmax) do.
            path =. i.0
            current =. state
            while. current~:_1 do.
                path =. path,NumberCells|current
                current =. current{parents
            end.
            (<1),(<|.path),<LLExpansions-beginning return.
        end.
        if. time=tmax do.
            continue.
        end.
        next_time =. time+1
        for_destination. cell{::Destinations do.
            if. _1=destination{distance do.
                continue.
            end.
            next_state =. destination+NumberCells*next_time
            if. _2~:next_state{parents do.
                continue.
            end.
            if. -.restrictions action_allowed cell,destination,next_time do.
                continue.
            end.
            insertion =. insertion+1
            parents =. state next_state}parents
            g =. next_time-t0
            key =. (g+destination{distance),(-g),insertion,next_state
            heap =. heap heap_push key
        end.
    end.
    (<0),(<i.0),<LLExpansions-beginning
)
