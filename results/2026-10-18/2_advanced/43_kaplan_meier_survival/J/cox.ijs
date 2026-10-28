c_loglik =: 0&{::
c_score =: 1&{::
c_information =: 2&{::
c_predictors =: 3&{::
c_event_sums =: 4&{::
m_beta =: 0&{::
m_null =: 1&{::
m_final =: 2&{::
m_iterations =: 3&{::
cox_evaluate =: 3 : 0
    'subjects vectors beta' =. y
    size =. #beta
    predictors =. (#subjects)$0.0
    risks =. (#subjects)$0.0
    for_index. i.#subjects do.
        value =. 0.0
        for_c. i.size do.
            value =. value+(c{beta)*(<index,c){vectors
        end.
        predictors =. value index}predictors
        risks =. (^value)index}risks
    end.
    order =. /:(-2{"1 subjects),.0{"1 subjects
    s0 =. 0.0
    s1 =. size$0.0
    s2 =. (size,size)$0.0
    likelihood =. 0.0
    score =. size$0.0
    information =. (size,size)$0.0
    event_sums =. 0$a:
    position =. 0
    while. position<#order do.
        moment =. (<(position{order),2){subjects
        events =. i.0
        while. position<#order do.
            index =. position{order
            if. moment~:(<index,2){subjects do.
                break.
            end.
            risk =. index{risks
            vector =. index{vectors
            s0 =. s0+risk
            for_c. i.size do.
                s1 =. ((c{s1)+risk*c{vector)c}s1
                for_d. i.size do.
                    value =. ((<c,d){s2)+(risk*c{vector)*d{vector
                    s2 =. value (<c,d)}s2
                end.
            end.
            if. 1=(<index,3){subjects do.
                events =. events,index
            end.
            position =. position+1
        end.
        count =. #events
        if. count=0 do.
            continue.
        end.
        likelihood =. likelihood+(ordered_sum events{predictors)-count*^.s0
        for_c. i.size do.
            sum_x =. +/c{"1 events{vectors
            score =. ((c{score)+(sum_x-(count*c{s1)%s0))c}score
            for_d. i.size do.
                increment =. count*((((<c,d){s2)%s0)-((c{s1)%s0)*(d{s1)%s0)
                information =. (((<c,d){information)+increment)(<c,d)}information
            end.
        end.
        event_sums =. event_sums,<(<moment),(<count),(<s0),<s1
    end.
    (<likelihood),(<score),(<information),(<predictors),<event_sums
)
cox_fit =: 3 : 0
    'subjects vectors' =. y
    beta =. (1{$vectors)$0.0
    null =. cox_evaluate (<subjects),(<vectors),<beta
    current =. null
    iterations =. 0$a:
    for_iteration. 1+i.25 do.
        change =. solve (<c_information current),<c_score current
        beta =. beta+change
        iterations =. iterations,<(<iteration),(<c_loglik current),<beta
        current =. cox_evaluate (<subjects),(<vectors),<beta
    end.
    (<beta),(<null),(<current),<iterations
)
