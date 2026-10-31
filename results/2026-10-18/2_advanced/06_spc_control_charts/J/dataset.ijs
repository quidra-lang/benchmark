ConstantTable =: 9 8$1.880 2.659 0 3.267 0 3.267 1.128 0.7979 1.023 1.954 0 2.568 0 2.574 1.693 0.8862 0.729 1.628 0 2.266 0 2.282 2.059 0.9213 0.577 1.427 0 2.089 0 2.114 2.326 0.9400 0.483 1.287 0.030 1.970 0 2.004 2.534 0.9515 0.419 1.182 0.118 1.882 0.076 1.924 2.704 0.9594 0.373 1.099 0.185 1.815 0.136 1.864 2.847 0.9650 0.337 1.032 0.239 1.761 0.184 1.816 2.970 0.9693 0.308 0.975 0.284 1.716 0.223 1.777 3.078 0.9727
control_constants =: 3 : '''a2 a3 b3 b4 d3 d4 d2 c4'' record <"0 (y-2){ConstantTable'
read_numeric_rows =: 3 : 0
    rows =. 0$a:
    for_box. }.read_lines y do. rows =. rows,<num&>',' split >box end.
    rows
)
read_dataset =: 3 : 0
    Settings =: Rules =: empty_table ''
    realnames =. ' ' split 'cusum_k cusum_h ewma_lambda ewma_l ci_z'
    for_box. read_lines 'spec.txt' do.
        words =. ' ' split >box
        name =. 0{::words
        if. name-:'rules' do. Rules =: ((1{words),<num&>2}.words) put_key Rules
        else.
            text =. 1{::words
            if. name-:'characteristic' do. value =. text
            elseif. (<name)e.realnames do. value =. real 0".text
            else. value =. num text end.
            Settings =: ((<name),<value) put_key Settings
        end.
    end.
    Size =: 'subgroup_size' get_key Settings
    Phase1 =: 'phase1_subgroups' get_key Settings
    Constants =: control_constants Size
    PairConstants =: control_constants 2
    Values =: 0$0
    for_box. read_numeric_rows 'measurements.csv' do. Values =: Values,2{>box end.
    Lots =: 0$a:
    for_box. read_numeric_rows 'attributes.csv' do.
        Lots =: Lots,<'number inspected defectives defects' record <"0 >box
    end.
    i.0
)
