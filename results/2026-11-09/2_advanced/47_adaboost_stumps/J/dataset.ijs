read_lines =: 3 : '<;._2 (1!:1 <y)'
words =: 3 : '<;._1 '' '',y'
integer_value =: 3 : '0". ''_''(I.y=''-'')}y'
decimal =: 3 : '0.0+integer_value y'
read_table =: 3 : 0
    'path multiclass' =. y
    lines =. read_lines path
    header =. <;._1 ',',0{::lines
    count =. (#header)-(2+multiclass)
    names =. count{.}.header
    train_ids =. test_ids =. 0$a:
    train_x =. test_x =. (0,count)$0.0
    train_y =. test_y =. i.0
    for_line. }.lines do.
        fields =. <;._1 ',',>line
        values =. decimal&>count{.}.fields
        label =. integer_value (count+1){::fields
        testing =. 0
        if. multiclass do.
            testing =. 'test'-:(count+2){::fields
        end.
        if. testing do.
            test_ids =. test_ids,0{fields
            test_x =. test_x,values
            test_y =. test_y,label
        else.
            train_ids =. train_ids,0{fields
            train_x =. train_x,values
            train_y =. train_y,label
        end.
    end.
    (<names),(<train_ids),(<train_x),(<train_y),(<test_ids),(<test_x),<test_y
)
read_inputs =: 3 : 0
    training =. read_table (<'input/train.csv'),<0
    testing =. read_table (<'input/test.csv'),<0
    multi =. read_table (<'input/multiclass.csv'),<1
    Features =: 0{::training
    TrainIDs =: 1{::training
    TrainX =: 2{::training
    TrainY =: 3{::training
    TestIDs =: 1{::testing
    TestX =: 2{::testing
    TestY =: 3{::testing
    MultiFeatures =: 0{::multi
    MultiTrainIDs =: 1{::multi
    MultiTrainX =: 2{::multi
    MultiTrainY =: 3{::multi
    MultiTestIDs =: 4{::multi
    MultiTestX =: 5{::multi
    MultiTestY =: 6{::multi
    settings =. words&.>read_lines 'input/params.txt'
    Rounds =: integer_value 1{::0{::settings
    Variants =: }.1{::settings
    Bins =: integer_value 1{::2{::settings
    Smoothing =: decimal 1{::3{::settings
    Convergence =: decimal 1{::4{::settings
    Clip =: decimal 1{::5{::settings
    Folds =: integer_value 1{::6{::settings
    Margins =: decimal&>}.7{::settings
    Classes =: integer_value 1{::8{::settings
    SammeRounds =: integer_value 1{::9{::settings
    PermutationRepeats =: integer_value 1{::10{::settings
    PermutationSeed =: integer_value 2{::10{::settings
    NoiseSeed =: integer_value 1{::11{::settings
    Noise =: integer_value&>2}.11{::settings
    Sizes =: integer_value&>}.12{::settings
    Shrinkages =: decimal&>}.13{::settings
    BootstrapCount =: integer_value 1{::14{::settings
    BootstrapSeed =: integer_value 2{::14{::settings
    i.0 0
)
