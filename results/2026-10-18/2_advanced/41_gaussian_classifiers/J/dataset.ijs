read_lines =: 3 : '<;._2 (1!:1 <y)'
words =: 3 : '<;._1 '' '',y'
csv_words =: 3 : '<;._1 '','',y'
integer =: 3 : 'x:0".y'
decimal =: 3 : 0
    if. '-'={.y do.
        -0".}.y
    else.
        0".y
    end.
)
row_id =: 0&{::
row_values =: 1&{::
row_label =: 2&{::
row_class =: 3&{::
p_prior =: 0&{::
p_epsilon =: 1&{::
p_smoothing =: 2&{::
p_gamma =: 3&{::
p_gammas =: 4&{::
p_folds =: 5&{::
p_calibration =: 6&{::
p_reject =: 7&{::
p_curve =: 8&{::
p_theta =: 9&{::
p_bootstrap =: 10&{::
p_seed =: 11&{::
p_map =: 12&{::
p_plot =: 13&{::
p_subsets =: 14&{::
p_pairs =: 15&{::
read_table =: 3 : 0
    lines =. read_lines y
    features =. }.}:csv_words 0{::lines
    rows =. 0$a:
    for_box. }.lines do.
        fields =. csv_words >box
        row =. (<integer 0{::fields),(<decimal&>}.}:fields),(<_1{::fields),<_1
        rows =. rows,<row
    end.
    (<features),<rows
)
read_parameters =: 3 : 0
    features =. y
    params =. 16$a:
    subsets =. 0$a:
    pairs =. 0 2$0
    for_box. read_lines 'input/params.txt' do.
        tokens =. words >box
        keyword =. 0{::tokens
        args =. }.tokens
        select. keyword
        case. 'PRIOR' do.
            params =. (0{args)0}params
        case. 'VAR_SMOOTHING' do.
            params =. (<decimal 0{::args)1}params
        case. 'SMOOTHING_GRID' do.
            params =. (<decimal&>args)2}params
        case. 'QDA_GAMMA' do.
            params =. (<decimal 0{::args)3}params
        case. 'GAMMA_GRID' do.
            params =. (<decimal&>args)4}params
        case. 'CV_FOLDS' do.
            params =. (<integer 0{::args)5}params
        case. 'CALIBRATION_EDGES' do.
            params =. (<decimal&>args)6}params
        case. 'REJECT_THRESHOLDS' do.
            params =. (<decimal&>args)7}params
        case. 'CURVE' do.
            params =. (<integer&>args)8}params
        case. 'OUTLIER_THRESHOLD' do.
            params =. (<decimal 0{::args)9}params
        case. 'BOOTSTRAP' do.
            params =. (<integer 0{::args)10}params
            params =. (<integer 1{::args)11}params
        case. 'MAP_SIZE' do.
            params =. (<integer&>args)12}params
        case. 'PLOT_SIZE' do.
            params =. (<integer&>args)13}params
        case. 'SUBSET' do.
            subsets =. subsets,<(<0{::args),<features i.}.args
        case. 'PAIR' do.
            pairs =. pairs,features i.args
        end.
    end.
    params =. (<subsets)14}params
    (<pairs)15}params
)
read_inputs =: 3 : 0
    'features training' =. read_table 'input/train.csv'
    'test_features testing' =. read_table 'input/test.csv'
    classes =. /:~~.row_label&.>training
    train =. 0$a:
    test_rows =. 0$a:
    for_box. training do.
        row =. >box
        row =. (<classes i.<row_label row)3}row
        train =. train,<row
    end.
    for_box. testing do.
        row =. >box
        row =. (<classes i.<row_label row)3}row
        test_rows =. test_rows,<row
    end.
    costs =. ((#classes),#classes)$0.0
    lines =. read_lines 'input/costs.csv'
    columns =. }.csv_words 0{::lines
    order =. columns i.classes
    for_box. }.lines do.
        fields =. csv_words >box
        actual =. classes i.0{fields
        values =. decimal&>}.fields
        costs =. (order{values)actual}costs
    end.
    params =. read_parameters features
    (<features),(<classes),(<train),(<test_rows),(<costs),<params
)
