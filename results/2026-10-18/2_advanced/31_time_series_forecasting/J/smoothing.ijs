recurse =: 3 : 0
    'name values season parameters' =. y
    'alpha beta gamma phi' =. parameters
    seasonal =. (<name)e.'hw_add';'hw_mult'
    level =. {.values
    slope =. 0.0
    components =. i.0
    if. seasonal do.
        level =. (total season{.values)%season
        slope =. (((total season{.season}.values)%season)-level)%season
        if. name-:'hw_add' do.
            components =. (season{.values)-level
        else.
            components =. (season{.values)%level
        end.
    elseif. -.name-:'ses' do.
        slope =. ((season{values)-{.values)%season
    end.
    states =. 0$a:
    errors =. i.0
    for_t. i.#values do.
        observed =. t{values
        states =. states,<(<level),(<slope),<components
        predicted =. level
        next_level =. level
        next_slope =. slope
        if. name-:'ses' do.
            next_level =. (alpha*observed)+(1-alpha)*level
        elseif. seasonal do.
            position =. season|t
            previous =. position{components
            base =. level+slope
            if. name-:'hw_add' do.
                predicted =. base+previous
                next_level =. (alpha*(observed-previous))+(1-alpha)*base
                component =. (gamma*(observed-base))+(1-gamma)*previous
            else.
                predicted =. base*previous
                next_level =. (alpha*(observed%previous))+(1-alpha)*base
                component =. (gamma*(observed%base))+(1-gamma)*previous
            end.
            components =. component position}components
            next_slope =. (beta*(next_level-level))+(1-beta)*slope
        else.
            predicted =. level+phi*slope
            next_level =. (alpha*observed)+(1-alpha)*predicted
            next_slope =. (beta*(next_level-level))+((1-beta)*phi)*slope
        end.
        errors =. errors,observed-predicted
        level =. next_level
        slope =. next_slope
    end.
    states =. states,<(<level),(<slope),<components
    (<errors),<states
)
sm_forecast =: 3 : 0
    'name state parameters origin steps season' =. y
    'level slope components' =. state
    if. name-:'ses' do.
        steps$level return.
    end.
    result =. i.0
    if. (<name)e.'holt';'damped' do.
        phi =. 3{parameters
        power =. phi
        accumulated =. 0.0
        for_step. i.steps do.
            accumulated =. accumulated+power
            result =. result,level+accumulated*slope
            power =. power*phi
        end.
    else.
        for_step. 1+i.steps do.
            component =. (season|origin+step-1){components
            base =. level+step*slope
            if. name-:'hw_add' do.
                value =. base+component
            else.
                value =. base*component
            end.
            result =. result,value
        end.
    end.
    result
)
