read_lines =: 3 : '<;._2 (1!:1 <y)'
split =: 4 : '<;._1 x,y'
num =: 3 : 'x: 0".y'
intdiv =: 4 : '<.(x: x)%x: y'
read_world =: 3 : 0
    lines =. read_lines y
    Rows =: num 1{::' 'split 0{::lines
    Cols =: num 1{::' 'split 1{::lines
    Kinds =: ;(2+i.Rows){lines
    Wind =: num&> <"0 ]1{::' 'split (2+Rows){::lines
    Rewards =: num&> }.' 'split (3+Rows){::lines
    States =: I.Kinds e.'.S~'
    Terminals =: I.Kinds e.'GP'
    StateIndex =: (i.#States)States}(#Kinds)$_1
    TerminalIndex =: (i.#Terminals)Terminals}(#Kinds)$_1
    Start =: Kinds i.'S'
    StartState =: Start{StateIndex
    #States
)
is_terminal =: 3 : '0<:y{TerminalIndex'
ending_code =: 3 : '''GP''i.y{Kinds'
move =: 4 : 0
    offsets =. (-Cols),1,Cols,_1
    target =. x+y{offsets
    if. '#'=target{Kinds do.
        target =. x
    end.
    if. is_terminal target do.
        target return.
    end.
    for_tick. i.(Cols|x){Wind do.
        above =. target-Cols
        if. '#'=above{Kinds do.
            break.
        end.
        target =. above
        if. is_terminal target do.
            break.
        end.
    end.
    target
)
e_moves =: 0&{::
e_transitions =: 1&{::
e_reward =: 2&{::
e_denominator =: 3&{::
e_floor =: 4&{::
e_ice =: 5&{::
new_environment =: 3 : 0
    'reward denominator floor_slip ice_slip' =. y
    moves =. ((#States),4)$0
    transitions =. ((#States),4)$a:
    for_state. i.#States do.
        cell =. state{States
        p =. floor_slip
        if. '~'=cell{Kinds do.
            p =. ice_slip
        end.
        for_action. i.4 do.
            target =. cell move action
            moves =. target (<state,action)}moves
            directions =. 4|action+0 1 3
            weights =. (denominator-2*p),p,p
            outcomes =. 0 2$0
            for_index. i.3 do.
                weight =. index{weights
                if. weight>0 do.
                    outcomes =. outcomes,((cell move index{directions),weight)
                end.
            end.
            transitions =. (<outcomes)(<state,action)}transitions
        end.
    end.
    (<moves),(<transitions),(<reward),(<denominator),(<floor_slip),<ice_slip
)
arrival_reward =: 4 : 0
    index =. y{TerminalIndex
    if. index<0 do.
        e_reward x
    else.
        index{Rewards
    end.
)
rng_seed =: 3 : 'Rng =: y'
rng_draw =: 3 : 'Rng =: 2147483647|48271x*Rng'
environment_step =: 4 : 0
    'state action' =. y
    draw =. (e_denominator x)|rng_draw 0
    p =. e_floor x
    if. '~'=(state{States){Kinds do.
        p =. e_ice x
    end.
    direction =. action
    if. draw>:(e_denominator x)-2*p do.
        direction =. 4|action+1
        if. draw>:(e_denominator x)-p do.
            direction =. 4|action+3
        end.
    end.
    target =. (<state,direction){e_moves x
    target,x arrival_reward target
)
