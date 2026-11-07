FeatureNames =: 'recency';'frequency';'monetary';'basket';'categories';'tenure'
SqrtFeatures =: 0 1 1 1 0 0
eligible_customers =: 4 : 0
    valid =. 0$a:
    for_box. x do. if. (3{::>box)>0 do. valid =. valid,box end. end.
    grouped =. orders_by_customer valid
    result =. 0$a:
    for_idbox. ascii_sort table_keys grouped do.
        id =. >idbox
        orders =. id get_key grouped
        days =. spends =. 0$0
        categories =. empty_table ''
        for_box. orders do.
            order =. >box
            days =. days,2{::order
            spends =. spends,3{::order
            for_index. 4{::order do.
                row =. index{::ValidRows
                category =. 3{::row
                previous =. 0
                if. category has_key categories do. previous =. category get_key categories end.
                categories =. ((<category),<previous+4{::row) put_key categories
            end.
        end.
        spend =. +/spends
        frequency =. #orders
        positive =. +/0< >1{"1 categories
        monetary =. spend%100
        raw =. (y->./days),frequency,monetary,(monetary%frequency),positive,y-<./days
        result =. result,<(<id),(<orders),(<raw),(<spend),<categories
    end.
    result
)
raw_values =: 3 : 0
    result =. 0 6$0.0
    for_box. y do. result =. result,2{::>box end.
    result
)
transform =: 3 : 0
    values =. y
    for_feature. I.SqrtFeatures do. values =. (%:feature{values) feature}values end.
    values
)
ordered_sum =: 3 : 0
    total =. 0.0
    for_value. y do. total =. total+value end.
    total
)
mean =: 3 : '(ordered_sum y)%#y'
sample_sd =: 3 : 0
    average =. mean y
    differences =. y-average
    %:(ordered_sum differences*differences)%<:#y
)
standardization =: 3 : 0
    means =. deviations =. 0$0.0
    for_feature. i.{:$y do.
        column =. feature{"1 y
        means =. means,mean column
        deviations =. deviations,sample_sd column
    end.
    (<means),<deviations
)
standardize =: 4 : 0
    'means deviations' =. x
    result =. 0$0.0
    for_feature. i.#means do.
        if. 0=feature{deviations do. result =. result,0.0
        else. result =. result,((feature{y)-feature{means)%feature{deviations end.
    end.
    result
)
correlation =: 4 : 0
    'first second' =. x
    (ordered_sum (first{"1 y)*second{"1 y)%<:#y
)
