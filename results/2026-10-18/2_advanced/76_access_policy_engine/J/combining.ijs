child_state =: 4 : '(<x),<y'
combine_children =: 4 : 0
    context =. x
    element =. y
    algorithm =. element{::Behaviors
    children =. element{::Children
    states =. (#children)$<0 child_state 0$a:
    if. algorithm-:'only-one-applicable' do.
        matched =. _1
        matched_position =. _1
        for_i. i.#children do.
            child =. i{children
            target =. (0{::context)evaluate_target child
            states =. (<1 child_state target)i}states
            'status reason' =. target
            if. status=2 do.
                (<5),(<reason),<states return.
            end.
            if. status=0 do.
                if. matched~:_1 do.
                    reason =. 'multiple applicable ',(matched{::ElementIds),' ',child{::ElementIds
                    (<5),(<reason),<states return.
                end.
                matched =. child
                matched_position =. i
            end.
        end.
        if. matched=_1 do.
            (<2),(<''),<states return.
        end.
        result =. context evaluate_element matched
        states =. (<2 child_state result)matched_position}states
        (2 3{result),<states return.
    end.
    decisions =. i.0
    first_error =. ''
    for_i. i.#children do.
        result =. context evaluate_element i{children
        states =. (<2 child_state result)i}states
        decision =. 2{::result
        reason =. 3{::result
        decisions =. ~.decisions,decision
        if. (decision>:3)*.0=#first_error do.
            first_error =. reason
        end.
        if. (algorithm-:'first-applicable')*.decision~:2 do.
            (<decision),(<reason),<states return.
        end.
        if. ((<algorithm)e.'deny-overrides';'permit-unless-deny')*.decision=1 do.
            (<1),(<''),<states return.
        end.
        if. ((<algorithm)e.'permit-overrides';'deny-unless-permit')*.decision=0 do.
            (<0),(<''),<states return.
        end.
    end.
    if. algorithm-:'deny-unless-permit' do.
        decision =. 1
    elseif. algorithm-:'permit-unless-deny' do.
        decision =. 0
    elseif. algorithm-:'first-applicable' do.
        decision =. 2
    elseif. algorithm-:'deny-overrides' do.
        if. (5 e.decisions)+.((3 e.decisions)*.((4 e.decisions)+.0 e.decisions)) do.
            decision =. 5
        elseif. 3 e.decisions do.
            decision =. 3
        elseif. 0 e.decisions do.
            decision =. 0
        elseif. 4 e.decisions do.
            decision =. 4
        else.
            decision =. 2
        end.
    else.
        if. (5 e.decisions)+.((4 e.decisions)*.((3 e.decisions)+.1 e.decisions)) do.
            decision =. 5
        elseif. 4 e.decisions do.
            decision =. 4
        elseif. 1 e.decisions do.
            decision =. 1
        elseif. 3 e.decisions do.
            decision =. 3
        else.
            decision =. 2
        end.
    end.
    reason =. ''
    if. decision>:3 do.
        reason =. first_error
    end.
    (<decision),(<reason),<states
)
