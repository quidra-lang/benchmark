parse_real =: 3 : 0
    if. '-'={.y do. y =. '_',}.y end.
    1.0*0".y
)
read_rows =: 3 : 0
    lines =. read_lines y
    fields =. ',' split 0{::lines
    names =. }. _2}.fields
    count =. #names
    rows =. 0$a:
    for_box. }.lines do.
        fields =. ',' split >box
        values =. parse_real&>count{.}.fields
        label =. (count+1){::fields
        text =. (count+2){::fields
        target =. 0.0
        if. #text do. target =. parse_real text end.
        rows =. rows,<'id values label target has_target' record (0{fields),(<values),(<label),(<target),<0<#text
    end.
    (<names),<rows
)
read_dataset =: 3 : 0
    'FeatureNames Train' =: read_rows 'train.csv'
    Test =: 1{::read_rows 'test.csv'
    Settings =: empty_table ''
    for_box. read_lines 'params.txt' do.
        words =. ' ' split >box
        name =. 0{::words
        value =. }.words
        if. (<name)e.'SCALINGS';'METRICS';'WEIGHTINGS' do. value =. value
        elseif. name-:'BINS' do. value =. parse_real&>value
        else. value =. num&>value end.
        Settings =: ((<name),<value) put_key Settings
    end.
    Features =: i.#FeatureNames
    Labels =: 0$a:
    TrainIDs =: 0$a:
    for_box. Train do.
        Labels =: Labels,<'label' get_key >box
        TrainIDs =: TrainIDs,<'id' get_key >box
    end.
    Labels =: /:~~.Labels
    LabelledIndices =: TargetedIndices =: 0$0
    for_index. i.#Test do.
        row =. index{::Test
        if. #'label' get_key row do. LabelledIndices =: LabelledIndices,index end.
        if. 'has_target' get_key row do. TargetedIndices =: TargetedIndices,index end.
    end.
    Labelled =: LabelledIndices{Test
    Targeted =: TargetedIndices{Test
    FoldCount =: {.'FOLDS' get_key Settings
    TopCount =: {.'TOP' get_key Settings
    i.0
)
