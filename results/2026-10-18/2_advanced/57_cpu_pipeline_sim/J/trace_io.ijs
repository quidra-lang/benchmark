floor_div =: 4 : '<.(x:x)%x:y'
split_words =: 3 : '<;._1 '' '',y'
parse_hex =: 3 : 0
    if. (8~:#y)+.-.*./y e.'0123456789abcdef' do.
        _1 return.
    end.
    16x#.'0123456789abcdef'i.y
)
parse_register =: 3 : 0
    if. (2>#y)+.(3<#y) do.
        _1 return.
    end.
    if. 'r'~:{.y do.
        _1 return.
    end.
    digits =. }.y
    if. (-.*./digits e.'0123456789')+.((1<#digits)*.'0'={.digits) do.
        _1 return.
    end.
    result =. 10#.'0123456789'i.digits
    if. result>31 do. _1 else. result end.
)
read_inputs =: 3 : 0
    trace =. <;._2 (1!:1 <'input/trace.txt')
    rows =. <;._2 (1!:1 <'input/config.txt')
    predictors =. variants =. 0$a:
    btb =. ras =. top =. interval =. 0
    primary =. 0$a:
    window =. i.0
    for_row. rows do.
        fields =. split_words >row
        select. 0{::fields
        case. 'BTB' do. btb =. ".1{::fields
        case. 'RAS' do. ras =. ".1{::fields
        case. 'TOP' do. top =. ".1{::fields
        case. 'INTERVAL' do. interval =. ".1{::fields
        case. 'PRIMARY' do. primary =. }.fields
        case. 'WINDOW' do. window =. ".&>}.fields
        case. 'PREDICTOR' do.
            definition =. (1{fields),(2{fields),<".&>3}.fields
            predictors =. predictors,<definition
        case. 'VARIANT' do.
            definition =. (1{fields),(<('ON'-:2{::fields)),(3{fields),<".4{::fields
            variants =. variants,<definition
        end.
    end.
    config =. (<btb),(<ras),(<predictors),(<variants),(<primary),(<window),(<top),<interval
    (<trace),<config
)
