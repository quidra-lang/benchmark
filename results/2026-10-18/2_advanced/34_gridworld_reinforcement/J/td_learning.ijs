next_maximum =: >./
choose_action =: 4 : 0
    if. (1000|rng_draw 0)<x do.
        4|rng_draw 0
    else.
        first_max y
    end.
)
next_expected =: 4 : '((x*+/y)+4*(1000-x)*>./y)intdiv 4000'
td_target =: 3 : 0
    'reward terminal future gamma' =. y
    result =. 10000*reward
    if. -.terminal do.
        result =. result+(gamma*future)intdiv 100
    end.
    result
)
td_update =: 4 : 0
    'state action backup alpha' =. y
    old =. (<state,action){x
    value =. old+(alpha*backup-old)intdiv 100
    value (<state,action)}x
)
new_dyna_model =: 3 : '(<((y,4)$_1)),<0 4$0x'
record_model =: 4 : 0
    'positions outcomes' =. x
    'state action reward target' =. y
    index =. (<state,action){positions
    if. index<0 do.
        positions =. (#outcomes)(<state,action)}positions
        outcomes =. outcomes,y
    else.
        outcomes =. y index}outcomes
    end.
    (<positions),<outcomes
)
planning_updates =: 4 : 0
    'values gamma alpha steps' =. y
    outcomes =. 1{::x
    for_tick. i.steps do.
        index =. (#outcomes)|rng_draw 0
        'state action reward target' =. index{outcomes
        future =. 0
        if. target>:0 do.
            future =. next_maximum target{values
        end.
        backup =. td_target reward,(target<0),future,gamma
        values =. values td_update state,action,backup,alpha
    end.
    values
)
