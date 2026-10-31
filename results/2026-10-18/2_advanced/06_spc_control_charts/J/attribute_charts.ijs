AttributeCharts =: ' ' split 'p np c u'
center_line =: 4 : 0
    defectives =. defects =. inspected =. 0
    for_box. y do.
        lot =. >box
        defectives =. defectives+'defectives' get_key lot
        defects =. defects+'defects' get_key lot
        inspected =. inspected+'inspected' get_key lot
    end.
    fraction =. (real defectives)%real inspected
    select. x
    case. 'p' do. value =. fraction
    case. 'np' do. value =. (real defectives)%real #y
    case. 'c' do. value =. (real defects)%real #y
    case. 'u' do. value =. (real defects)%real inspected
    end.
    'chart value fraction' record (<x),(<value),<fraction
)
lot_point =: 4 : 0
    chart =. 'chart' get_key x
    cl =. 'value' get_key x
    inspected =. real 'inspected' get_key y
    select. chart
    case. 'p' do.
        value =. (real 'defectives' get_key y)%inspected
        sigma =. %:(cl*(1.0-cl))%inspected
    case. 'np' do.
        value =. 'defectives' get_key y
        sigma =. %:cl*1.0-'fraction' get_key x
    case. 'c' do.
        value =. 'defects' get_key y
        sigma =. %:cl
    case. 'u' do.
        value =. (real 'defects' get_key y)%inspected
        sigma =. %:cl%inspected
    end.
    lcl =. 0.0>.cl-3.0*sigma
    ucl =. cl+3.0*sigma
    z =. (value-cl)%sigma
    if. value>!.0 ucl do. status =. 'high'
    elseif. value<!.0 lcl do. status =. 'low'
    else. status =. 'ok' end.
    'value lcl ucl z status' record (<value),(<lcl),(<ucl),(<z),<status
)
