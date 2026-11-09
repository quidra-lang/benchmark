discounted_return =: 4 : 0
    result =. 0x
    for_reward. |.y do.
        result =. (10000*reward)+(x*result)intdiv 100
    end.
    result
)
new_mc_totals =: 3 : '(<((y,4)$0x)),<(y,4)$0'
first_visit_update =: 4 : 0
    'values history gamma' =. y
    'sums counts' =. x
    seen =. ($counts)$0
    first =. i.0
    for_visit. history do.
        'state action reward' =. visit
        coordinate =. <state,action
        first =. first,-.coordinate{seen
        seen =. 1 coordinate}seen
    end.
    value =. 0x
    for_index. |.i.#history do.
        'state action reward' =. index{history
        value =. (10000*reward)+(gamma*value)intdiv 100
        if. index{first do.
            coordinate =. <state,action
            sum =. value+coordinate{sums
            count =. 1+coordinate{counts
            sums =. sum coordinate}sums
            counts =. count coordinate}counts
            values =. (sum intdiv count)coordinate}values
        end.
    end.
    (<values),<((<sums),<counts)
)
