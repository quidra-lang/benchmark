HeuristicNames =: ;:'goalcount hmax hadd ff lmcount'
init_heuristics =: 3 : 0
    HProblem =: y
    HActions =: 5{::y
    HGoal =: 7{::y
    HFactCount =: #4{::y
    HAchievers =: HFactCount$<i.0
    for_index. i.#HActions do.
        for_fact. I.5{::index{::HActions do.
            HAchievers =: (<(fact{::HAchievers),index)fact}HAchievers
        end.
    end.
    HStates =: 0$a:
    HCache =: 0 6$<a:
)
heuristic_state =: 3 : 0
    index =. HStates i.<y
    if. index=#HStates do.
        HStates =: HStates,<y
        HCache =: HCache,6$<a:
    end.
    index
)
relaxed_costs =: 4 : 0
    column =. -.x
    index =. heuristic_state y
    cached =. >(<index,column){HCache
    if. -.cached-:a: do.
        cached return.
    end.
    costs =. y-1
    changed =. 1
    while. changed do.
        changed =. 0
        for_action. HActions do.
            action =. >action
            values =. (I.3{::action){costs
            if. _1 e.values do.
                continue.
            end.
            aggregate =. +/values
            if. x do.
                aggregate =. >./0,values
            end.
            value =. (2{::action)+aggregate
            for_fact. I.5{::action do.
                old =. fact{costs
                if. (old=_1)+.value<old do.
                    costs =. value fact}costs
                    changed =. 1
                end.
            end.
        end.
    end.
    HCache =: (<costs)(<index,column)}HCache
    costs
)
relaxed_plan =: 3 : 0
    index =. heuristic_state y
    cached =. >(<index,2){HCache
    if. -.cached-:a: do.
        cached return.
    end.
    costs =. 0 relaxed_costs y
    if. _1 e.(I.HGoal){costs do.
        plan =. ,_1
    else.
        chosen =. (#HActions)$0
        pending =. I.HGoal*.-.y
        front =. 0
        while. front<#pending do.
            fact =. front{pending
            front =. front+1
            winner =. _1
            lowest =. _1
            for_number. fact{::HAchievers do.
                action =. number{::HActions
                values =. (I.3{::action){costs
                if. _1 e.values do.
                    continue.
                end.
                cost =. (2{::action)++/values
                if. (lowest=_1)+.cost<lowest do.
                    winner =. number
                    lowest =. cost
                end.
            end.
            if. -.winner{chosen do.
                chosen =. 1 winner}chosen
                pending =. pending,I.(3{::winner{::HActions)*.-.y
            end.
        end.
        plan =. I.chosen
    end.
    HCache =: (<plan)(<index,2)}HCache
    plan
)
helpful_actions =: 3 : 0
    index =. heuristic_state y
    cached =. >(<index,3){HCache
    if. -.cached-:a: do.
        cached return.
    end.
    plan =. relaxed_plan y
    helpful =. i.0
    if. -.plan-:,_1 do.
        for_number. plan do.
            if. (number{::HActions)action_applicable y do.
                helpful =. helpful,number
            end.
        end.
    end.
    HCache =: (<helpful)(<index,3)}HCache
    helpful
)
planning_levels =: 3 : 0
    index =. heuristic_state y
    cached =. >(<index,4){HCache
    if. -.cached-:a: do.
        cached return.
    end.
    facts =. y-1
    actions =. (#HActions)$_1
    level =. 0
    while. 1 do.
        changed =. 0
        for_number. I.actions=_1 do.
            action =. number{::HActions
            values =. (I.3{::action){facts
            if. _1 e.values do.
                continue.
            end.
            if. +./values>level do.
                continue.
            end.
            actions =. level number}actions
            for_fact. I.5{::action do.
                if. _1=fact{facts do.
                    facts =. (level+1)fact}facts
                    changed =. 1
                end.
            end.
        end.
        if. -.changed do.
            break.
        end.
        level =. level+1
    end.
    result =. (<facts),<actions
    HCache =: (<result)(<index,4)}HCache
    result
)
verified_landmark =: 4 : 0
    reachable =. x
    changed =. 1
    while. changed do.
        changed =. 0
        for_action. HActions do.
            action =. >action
            if. y{5{::action do.
                continue.
            end.
            if. */(3{::action)<:reachable do.
                next =. reachable+.5{::action
                if. -.next-:reachable do.
                    reachable =. next
                    changed =. 1
                end.
            end.
        end.
    end.
    -.*/HGoal<:reachable
)
landmarks =: 3 : 0
    index =. heuristic_state y
    cached =. >(<index,5){HCache
    if. -.cached-:a: do.
        cached return.
    end.
    'fact_levels action_levels' =. planning_levels y
    if. _1 e.(I.HGoal){fact_levels do.
        result =. ,_1
    else.
        selected =. HGoal*.-.y
        pending =. I.selected
        verification =. HFactCount$_1
        front =. 0
        while. front<#pending do.
            fact =. front{pending
            front =. front+1
            achievers =. fact{::HAchievers
            earliest =. achievers#~(achievers{action_levels)=(fact{fact_levels)-1
            candidates =. HFactCount$1
            for_number. earliest do.
                candidates =. candidates*.3{::number{::HActions
            end.
            candidates =. candidates*.-.y+.selected
            for_candidate. I.candidates do.
                valid =. candidate{verification
                if. valid=_1 do.
                    valid =. y verified_landmark candidate
                    verification =. valid candidate}verification
                end.
                if. valid do.
                    selected =. 1 candidate}selected
                    pending =. pending,candidate
                end.
            end.
        end.
        result =. I.selected
    end.
    HCache =: (<result)(<index,5)}HCache
    result
)
heuristic_value =: 4 : 0
    select. x
    case. 'none' do. 0
    case. 'goalcount' do. +/HGoal*.-.y
    case. 'hmax';'hadd' do.
        costs =. (x-:'hmax')relaxed_costs y
        values =. (I.HGoal){costs
        if. _1 e.values do.
            _1
        elseif. x-:'hmax' do.
            >./0,values
        else.
            +/values
        end.
    case. 'ff' do.
        plan =. relaxed_plan y
        if. plan-:,_1 do.
            _1
        else.
            total =. 0
            for_number. plan do.
                total =. total+2{::number{::HActions
            end.
            total
        end.
    case. 'lmcount' do.
        selected =. landmarks y
        if. selected-:,_1 do. _1 else. #selected end.
    end.
)
heuristic_values =: 3 : 0
    values =. i.0
    for_name. HeuristicNames do.
        values =. values,(>name)heuristic_value y
    end.
    values
)
