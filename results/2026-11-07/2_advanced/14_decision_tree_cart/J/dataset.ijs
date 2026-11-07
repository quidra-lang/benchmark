read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
read_rows =: 3 : 0
    rows =. 0$0
    for_line. }.read_lines y do.
        fields =. ',' split >line
        index =. #RowIds
        rows =. rows,index
        RowIds =: RowIds,0{fields
        values =. 0$0
        for_attribute. i.AttributeCount do.
            text =. (attribute+1){::fields
            if. text-:'?' do. value =. _1
            elseif. attribute{IntegerAttributes do. value =. num text
            else. value =. (attribute{::ValueNames)i.<text end.
            values =. values,value
        end.
        Data =: Data,values
        Labels =: Labels,ClassNames i.{:fields
    end.
    rows
)
load_dataset =: 3 : 0
    AttributeNames =: ValueNames =: 0$a:
    IntegerAttributes =: 0$0
    schema =. read_lines 'schema.txt'
    for_line. }:schema do.
        fields =. ' ' split >line
        AttributeNames =: AttributeNames,1{fields
        IntegerAttributes =: IntegerAttributes,('INT'-:2{::fields)
        ValueNames =: ValueNames,<3}.fields
    end.
    fields =. ' ' split >{:schema
    Target =: 1{::fields
    ClassNames =: 2}.fields
    AttributeCount =: #AttributeNames
    ClassCount =: #ClassNames
    RowIds =: 0$a:
    Data =: (0,AttributeCount)$0
    Labels =: 0$0
    Train =: read_rows 'train.csv'
    Validation =: read_rows 'validation.csv'
    Test =: read_rows 'test.csv'
    settings =. 0$a:
    for_line. read_lines 'params.txt' do. settings =. settings,<num&>}. ' ' split >line end.
    MaxDepth =: {.0{::settings
    MinSamplesSplit =: {.1{::settings
    MinSamplesLeaf =: {.2{::settings
    MaxSurrogates =: {.3{::settings
    Folds =: {.4{::settings
    Curve =: 5{::settings
    BagTrees =: {.6{::settings
    BagSeed =: {.7{::settings
    PermutationRepeats =: {.8{::settings
    PermutationSeed =: {.9{::settings
    i.0
)
