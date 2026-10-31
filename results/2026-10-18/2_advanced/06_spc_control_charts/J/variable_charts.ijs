real_sum =: 3 : 0
    total =. 0.0
    for_value. y do. total =. total+value end.
    total
)
subgroup_statistics =: 3 : 0
    groups =. 0$a:
    for_index. i.(#y) div Size do.
        values =. Size{.(index*Size)}.y
        total =. +/values
        squares =. +/values*values
        mean =. (real total)%real Size
        range =. (>./values)-<./values
        numerator =. (Size*squares)-total*total
        denominator =. Size*Size-1
        sd =. %:(real numerator)%real denominator
        group =. 'number values total squares mean range sd' record (<index+1),(<values),(<total),(<squares),(<mean),(<range),<sd
        groups =. groups,<group
    end.
    groups
)
new_limits =: 3 : '''lcl cl ucl'' record <"0 y'
outside =: 4 : '(y>!.0 ''ucl'' get_key x)+.y<!.0 ''lcl'' get_key x'
moving_ranges =: 3 : '|(}.y)-}:y'
subgroup_totals =: 4 : 0
    values =. 0$0
    for_box. y do. values =. values,x get_key >box end.
    values
)
xbar_r_limits =: 3 : 0
    mean =. (real +/'total' subgroup_totals y)%real (#y)*Size
    rbar =. (real +/'range' subgroup_totals y)%real #y
    width =. ('a2' get_key Constants)*rbar
    (<new_limits (mean-width),mean,mean+width),<new_limits (('d3' get_key Constants)*rbar),rbar,('d4' get_key Constants)*rbar
)
xbar_s_limits =: 3 : 0
    mean =. (real +/'total' subgroup_totals y)%real (#y)*Size
    sbar =. (real_sum 'sd' subgroup_totals y)%real #y
    width =. ('a3' get_key Constants)*sbar
    (<new_limits (mean-width),mean,mean+width),<new_limits (('b3' get_key Constants)*sbar),sbar,('b4' get_key Constants)*sbar
)
i_mr_limits =: 3 : 0
    ranges =. moving_ranges y
    mean =. (real +/y)%real #y
    rbar =. (real +/ranges)%real #ranges
    width =. (3.0*rbar)%'d2' get_key PairConstants
    (<new_limits (mean-width),mean,mean+width),<new_limits (('d3' get_key PairConstants)*rbar),rbar,('d4' get_key PairConstants)*rbar
)
