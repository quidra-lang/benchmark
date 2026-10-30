domain_size =: 3 : '*/#&>DomainValues'
point_attributes =: 3 : 0
    point =. y
    values =. (#DomainNames)$a:
    for_i. |.i.#DomainNames do.
        candidates =. i{::DomainValues
        index =. (#candidates)|point
        point =. point intdiv #candidates
        values =. (index{candidates)i}values
    end.
    (<DomainNames),<values
)
day_notation =: 3 : 0
    days =. /:~ ~.y
    first =. {.days
    last =. first
    runs =. 0$a:
    for_day. }.days do.
        if. day~:last+1 do.
            runs =. runs,<(integer first),'-',integer last
            first =. day
        end.
        last =. day
    end.
    runs =. runs,<(integer first),'-',integer last
    ','join runs
)
find_blocker =: 4 : 0
    for_earlier. (x{Parents){::Children do.
        if. earlier=x do.
            break.
        end.
        if. 2~:earlier{y do.
            earlier return.
        end.
    end.
    _1
)
conflict_winner =: 3 : 0
    'policy earlier later' =. y
    algorithm =. policy{::Behaviors
    if. algorithm-:'first-applicable' do.
        earlier return.
    end.
    effect =. 'PERMIT'
    if. (<algorithm)e.'deny-overrides';'permit-unless-deny' do.
        effect =. 'DENY'
    end.
    if. effect-:earlier{::Behaviors do.
        earlier
    else.
        later
    end.
)
