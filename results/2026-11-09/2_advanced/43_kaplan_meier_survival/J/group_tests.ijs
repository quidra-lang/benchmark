Weights =: ;:'logrank gehan_wilcoxon tarone_ware'
t_groups =: 0&{::
t_events =: 1&{::
t_observed =: 2&{::
t_expected =: 3&{::
t_covariance =: 4&{::
t_statistic =: 5&{::
t_degrees =: 6&{::
t_probability =: 7&{::
empty_totals =: 3 : 0
    size =. #y
    (<y),(<size$0),(<size$0.0),(<size$0.0),<(size,size)$0.0
)
weighted_totals =: 3 : 0
    'subjects groups weight population_size' =. y
    size =. #groups
    deaths_total =. size$0
    observed =. size$0.0
    expected =. size$0.0
    covariance =. (size,size)$0.0
    for_row. risk_sets subjects do.
        if. 0=2{row do.
            continue.
        end.
        moment =. 0{row
        risks =. size$0
        deaths =. size$0
        for_h. i.size do.
            group_mask =. (h{groups)=1{"1 subjects
            risks =. (+/group_mask*.moment<:2{"1 subjects)h}risks
            deaths =. (+/group_mask*.(moment=2{"1 subjects)*.3{"1 subjects)h}deaths
        end.
        n =. +/risks
        d =. +/deaths
        value =. 1.0
        if. weight=1 do.
            value =. n fraction population_size
        elseif. weight=2 do.
            value =. %:n fraction population_size
        end.
        for_h. i.size do.
            deaths_total =. ((h{deaths_total)+h{deaths)h}deaths_total
            observed =. ((h{observed)+value*h{deaths)h}observed
            expected =. ((h{expected)+value*(d*h{risks)fraction n)h}expected
            if. n<2 do.
                continue.
            end.
            factor =. (value*value)*(d*(n-d))fraction ((n-1)*n)*n
            for_other. i.size do.
                multiple =. -(h{risks)*other{risks
                if. h=other do.
                    multiple =. (h{risks)*(n-h{risks)
                end.
                covariance =. (((<h,other){covariance)+factor*multiple)(<h,other)}covariance
            end.
        end.
    end.
    (<groups),(<deaths_total),(<observed),(<expected),<covariance
)
finish_test =: 3 : 0
    degrees =. <:(#t_groups y)
    difference =. degrees{.(t_observed y)-t_expected y
    coefficients =. (degrees,degrees){.t_covariance y
    solution =. solve (<coefficients),<difference
    statistic =. ordered_sum difference*solution
    y,(<statistic),(<degrees),<statistic chi_p degrees
)
weighted_test =: 3 : 'finish_test weighted_totals y'
combine_strata =: 3 : 0
    'strata groups' =. y
    'stored events observed expected covariance' =. empty_totals groups
    for_box. strata do.
        stratum =. >box
        events =. events+t_events stratum
        observed =. observed+t_observed stratum
        expected =. expected+t_expected stratum
        covariance =. covariance+t_covariance stratum
    end.
    finish_test (<groups),(<events),(<observed),(<expected),<covariance
)
