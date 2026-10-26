read_rules =: 3 : 0
    rules =. 0$a:
    for_line. read_lines 'segment_rules.txt' do.
        fields =. ' ' split >line
        features =. directions =. 0$0
        thresholds =. 0$0.0
        for_index. 1+3*i.((#fields)-1)div 3 do.
            features =. features,FeatureNames i.index{fields
            directions =. directions,('>'-:(index+1){::fields)
            thresholds =. thresholds,decimal (index+2){::fields
        end.
        rules =. rules,<(0{fields),(<features),(<directions),<thresholds
    end.
    rules
)
rule_number =: 4 : 0
    for_index. i.#x do.
        'name features directions thresholds' =. index{::x
        accepted =. 1
        for_condition. i.#features do.
            value =. (condition{features){y
            if. condition{directions do. holds =. value>condition{thresholds
            else. holds =. value<condition{thresholds end.
            if. -.holds do. accepted =. 0 break. end.
        end.
        if. accepted do. index return. end.
    end.
    _1
)
original_scale =: 4 : 0
    'means deviations' =. x
    values =. means+deviations*y
    for_feature. I.SqrtFeatures do. value =. feature{values
        values =. (value*value) feature}values end.
    values
)
