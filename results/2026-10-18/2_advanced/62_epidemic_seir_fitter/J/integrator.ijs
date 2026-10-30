rk4_step =: 1 : 0
    'state multiplier' =. y
    half =. 0.25%2
    sixth =. 0.25%6
    k1 =. u (<state),<multiplier
    shifted =. state+half*k1
    k2 =. u (<shifted),<multiplier
    shifted =. state+half*k2
    k3 =. u (<shifted),<multiplier
    shifted =. state+0.25*k3
    k4 =. u (<shifted),<multiplier
    combined =. ((k1+2*k2)+2*k3)+k4
    state+sixth*combined
)
simulate =: 1 : 0
    'state multipliers inflows' =. y
    daily =. (0,#state)$0.0
    for_multiplier. multipliers do.
        state =. 0.0 inflows}state
        for_quarter. i.4 do. state =. (u rk4_step) (<state),<multiplier end.
        daily =. daily,state
    end.
    daily
)
