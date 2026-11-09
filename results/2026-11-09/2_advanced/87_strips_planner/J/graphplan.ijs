mutex_count =: 3 : '(+/,y)intdiv 2'
graph_conflict =: 3 : 0
    'first second mutex' =. y
    'number_a pre_a add_a del_a' =. first
    'number_b pre_b add_b del_b' =. second
    if. (+./del_a*.(pre_b+.add_b))+. +./del_b*.(pre_a+.add_a) do.
        1 return.
    end.
    a =. I.pre_a
    b =. I.pre_b
    +./,b{"1 a{mutex
)
graph_expand =: 3 : 0
    level =. y
    facts =. level{::GPFacts
    mutex =. level{::GPFactMutexes
    elements =. 0$a:
    for_action. GPActions do.
        action =. >action
        pre =. 1{::action
        if. -.*/pre<:facts do.
            continue.
        end.
        indices =. I.pre
        if. +./,indices{"1 indices{mutex do.
            continue.
        end.
        elements =. elements,<action
    end.
    action_count =. #elements
    for_fact. I.facts do.
        one =. GPFactCount$0
        one =. 1 fact}one
        elements =. elements,<( <_1),(<one),(<one),<GPFactCount$0
    end.
    exclusive =. ((#elements),#elements)$0
    for_first. i.#elements do.
        for_second. (first+1)+i.(#elements)-(first+1) do.
            pair =. (first{elements),(second{elements),<mutex
            if. graph_conflict pair do.
                exclusive =. 1(<first,second)}exclusive
                exclusive =. 1(<second,first)}exclusive
            end.
        end.
    end.
    line =. 'action level ',(integer level),': actions=',integer action_count
    GPLines =: GPLines,<line,' noops=',(integer +/facts),' mutexes=',integer mutex_count exclusive
    achievers =. GPFactCount$<i.0
    following =. GPFactCount$0
    numbers =. i.0
    for_index. i.#elements do.
        element =. index{::elements
        numbers =. numbers,0{::element
        for_fact. I.2{::element do.
            following =. 1 fact}following
            achievers =. (<(fact{::achievers),index)fact}achievers
        end.
    end.
    for_fact. I.following do.
        producers =. fact{::achievers
        noops =. producers#~_1=producers{numbers
        actions =. producers#~_1~:producers{numbers
        achievers =. (<noops,actions)fact}achievers
    end.
    following_mutex =. (GPFactCount,GPFactCount)$0
    occurring =. I.following
    for_position. i.#occurring do.
        first =. position{occurring
        a =. first{::achievers
        for_second. (position+1)}.occurring do.
            b =. second{::achievers
            if. */,b{"1 a{exclusive do.
                following_mutex =. 1(<first,second)}following_mutex
                following_mutex =. 1(<second,first)}following_mutex
            end.
        end.
    end.
    GPElemLevels =: GPElemLevels,<elements
    GPMutexLevels =: GPMutexLevels,<exclusive
    GPAchieverLevels =: GPAchieverLevels,<achievers
    GPFacts =: GPFacts,<following
    GPFactMutexes =: GPFactMutexes,<following_mutex
)
graph_extract =: 3 : 0
    'level goals' =. y
    if. level=0 do.
        (<1),<0$a: return.
    end.
    key =. (<level),<goals
    if. (<key)e.GPMemo do.
        GPMemoHits =: GPMemoHits+1
        (<0),<0$a: return.
    end.
    GPSearched =: GPSearched+1
    result =. graph_assign(<level),(<goals),(<0),<i.0
    if. -.0{::result do.
        GPMemo =: GPMemo,<key
    end.
    result
)
graph_assign =: 3 : 0
    'level goals position chosen' =. y
    elements =. (level-1){::GPElemLevels
    covered =. GPFactCount$0
    for_index. chosen do.
        covered =. covered+.2{::index{::elements
    end.
    while. position<#goals do.
        if. -.(position{goals){covered do.
            break.
        end.
        position =. position+1
    end.
    if. position=#goals do.
        previous =. GPFactCount$0
        layer =. i.0
        for_index. chosen do.
            element =. index{::elements
            previous =. previous+.1{::element
            number =. 0{::element
            if. number~:_1 do.
                layer =. layer,number
            end.
        end.
        'success layers' =. graph_extract(<level-1),<I.previous
        if. success do.
            (<1),<layers,</:~layer
        else.
            (<0),<0$a:
        end.
        return.
    end.
    achievers =. (level-1){::GPAchieverLevels
    mutex =. (level-1){::GPMutexLevels
    for_index. (position{goals){::achievers do.
        if. +./chosen{index{mutex do.
            continue.
        end.
        GPTried =: GPTried+1
        result =. graph_assign(<level),(<goals),(<position+1),<chosen,index
        if. 0{::result do.
            result return.
        end.
    end.
    (<0),<0$a:
)
graphplan_run =: 3 : 0
    'actions initial goal limit' =. y
    GPActions =: actions
    GPGoal =: goal
    GPFactCount =: #initial
    GPFacts =: ,<initial
    GPFactMutexes =: ,<(GPFactCount,GPFactCount)$0
    GPElemLevels =: 0$a:
    GPMutexLevels =: 0$a:
    GPAchieverLevels =: 0$a:
    GPMemo =: 0$a:
    GPLines =: 0$a:
    GPSearched =: 0
    GPMemoHits =: 0
    GPTried =: 0
    status =. 'level limit'
    layers =. 0$a:
    for_level. i.limit+1 do.
        facts =. level{::GPFacts
        mutex =. level{::GPFactMutexes
        count =. mutex_count mutex
        line =. 'fact level ',(integer level),': facts=',integer +/facts
        GPLines =: GPLines,<line,' mutexes=',integer count
        indices =. I.goal
        possible =. (*/goal<:facts)*.-.+./,indices{"1 indices{mutex
        if. possible do.
            before_search =. GPSearched
            before_hits =. GPMemoHits
            'success extracted' =. graph_extract(<level),<indices
            outcome =. 'fail'
            if. success do.
                outcome =. 'success'
            end.
            line =. 'extract level ',(integer level),': ',outcome,' searched=',integer GPSearched-before_search
            GPLines =: GPLines,<line,' memo_hits=',integer GPMemoHits-before_hits
            if. success do.
                status =. 'solved'
                layers =. extracted
                break.
            end.
        elseif. level>0 do.
            same_facts =. (+/facts)=+/(level-1){::GPFacts
            same_mutex =. count=mutex_count (level-1){::GPFactMutexes
            if. same_facts*.same_mutex do.
                status =. 'unreachable'
                break.
            end.
        end.
        if. level=limit do.
            break.
        end.
        graph_expand level
    end.
    plan =. ;layers
    result =. (<status),(<GPSearched),(<GPTried),(<plan),(<layers),(<GPLines),<GPMemoHits
    result
)
