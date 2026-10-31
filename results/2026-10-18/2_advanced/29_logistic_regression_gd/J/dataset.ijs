read_examples =: 3 : 0
    lines =. <;._2 (1!:1 <y)
    names =. }.}:','split 0{::lines
    ids =. 0$a:
    values =. (0,#names)$0.0
    labels =. i.0
    for_line. }.lines do.
        fields =. ','split >line
        ids =. ids,{.fields
        values =. values,decimal&>}.}:fields
        labels =. labels,num >{:fields
    end.
    (<names),(<ids),(<values),<labels
)
read_settings =: 3 : 0
    rows =. 0$a:
    for_line. <;._2 (1!:1 <y) do.
        rows =. rows,<' 'split >line
    end.
    Positive =: num 1{::0{::rows
    Degree =: num 1{::1{::rows
    Threshold =: decimal 1{::2{::rows
    Lambdas =: decimal&>}.3{::rows
    GDRate =: decimal 1{::4{::rows
    GDIterations =: num 2{::4{::rows
    SGDRate =: decimal 1{::5{::rows
    'BatchSize Epochs SGDSeed' =: num&>2 3 4{5{::rows
    SoftmaxRate =: decimal 1{::6{::rows
    SoftmaxIterations =: num 2{::6{::rows
    SoftmaxLambda =: decimal 3{::6{::rows
    'BootstrapCount BootstrapSeed' =: num&>}.7{::rows
    'PermutationCount PermutationSeed' =: num&>}.8{::rows
    'MapWidth MapHeight' =: num&>}.9{::rows
    'CostFP CostFN' =: num&>}.10{::rows
    i.0
)
extend_tuples =: 3 : 0
    'width remaining first prefix' =. y
    if. remaining=0 do.
        ,<prefix return.
    end.
    result =. 0$a:
    for_index. first+i.width-first do.
        result =. result,extend_tuples (<width),(<remaining-1),(<index),<prefix,index
    end.
    result
)
expansion_tuples =: 4 : 0
    result =. 0$a:
    for_length. 1+i.y do.
        result =. result,extend_tuples (<x),(<length),(<0),<i.0
    end.
    result
)
expanded_names =: 4 : 0
    result =. 0$a:
    for_indices. y do.
        result =. result,<'*'join (>indices){x
    end.
    result
)
expanded_values =: 4 : 0
    result =. i.0
    for_indices. x do.
        indices =. >indices
        product =. ({.indices){y
        for_index. }.indices do.
            product =. product*index{y
        end.
        result =. result,product
    end.
    result
)
compute_statistics =: 4 : 0
    means =. deviations =. i.0
    for_column. i.x do.
        total =. ordered_sum column{"1 y
        mean =. total%#y
        squares =. ordered_sum *:mean-column{"1 y
        means =. means,mean
        deviations =. deviations,%:squares%<:#y
    end.
    (<means),<deviations
)
standardize =: 4 : 0
    'means deviations' =. x
    1.0,(((#means){.y)-means)%deviations
)
