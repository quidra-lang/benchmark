split_words =: 3 : '<;._1 '' '',y'
split_csv =: 3 : '<;._1 '','',y'
read_csv =: 3 : 0
    ids =. 0$a:
    points =. 0 2$0.0
    labels =. i.0
    roles =. 0$a:
    for_line. }. <;._2 (1!:1 <'input/',y) do.
        fields =. split_csv >line
        ids =. ids,<0{::fields
        points =. points,0.0+parse_number&>1 2{fields
        labels =. labels,parse_number 3{::fields
        if. 5=#fields do. roles =. roles,<4{::fields
        else. roles =. roles,<'' end.
    end.
    (<ids),(<points),(<labels),<roles
)
data_subset =: 4 : 0
    (<x{0{::y),(<x{1{::y),(<x{2{::y),<x{3{::y
)
read_dataset =: 3 : 0
    TrainData =: read_csv 'train.csv'
    TestData =: read_csv 'test.csv'
    allmulti =. read_csv 'multiclass.csv'
    roles =. 3{::allmulti
    MultiTrain =: (I.roles=<'train')data_subset allmulti
    MultiTest =: (I.roles=<'test')data_subset allmulti
    KernelDefs =: 0$a:
    for_line. <;._2 (1!:1 <'input/params.txt') do.
        fields =. split_words >line
        select. 0{::fields
        case. 'C_GRID' do. CGrid =: 0.0+parse_number&>}.fields
        case. 'KERNEL' do.
            name =. 1{::fields
            kind =. 2{::fields
            degree =. 0
            gamma =. coef0 =. 0.0
            if. kind-:'poly' do.
                degree =. parse_number 3{::fields
                gamma =. 0.0+parse_number 4{::fields
                coef0 =. 0.0+parse_number 5{::fields
            elseif. kind-:'rbf' do. gamma =. 0.0+parse_number 3{::fields end.
            KernelDefs =: KernelDefs,<(<name),(<kind),(<degree),(<gamma),<coef0
        case. 'TOLERANCE' do. Tolerance =: 0.0+parse_number 1{::fields
        case. 'EPS' do. Epsilon =: 0.0+parse_number 1{::fields
        case. 'MAX_PASSES' do. MaxPasses =: parse_number 1{::fields
        case. 'FOLDS' do. FoldCount =: parse_number 1{::fields
        case. 'LEARNING_CURVE' do. CurveFractions =: parse_number&>}.fields
        case. 'NEWTON_ITERATIONS' do. NewtonIterations =: parse_number 1{::fields
        case. 'MULTICLASS' do.
            MultiKernelName =: 1{::fields
            MultiCoefficient =: 0.0+parse_number 2{::fields
        case. 'PEGASOS' do.
            PegasosLambda =: 0.0+parse_number 1{::fields
            PegasosIterations =: parse_number 2{::fields
            PegasosSeed =: parse_number 3{::fields
        case. 'PLOT_X' do. PlotX =: 0.0+parse_number&>}.fields
        case. 'PLOT_Y' do. PlotY =: 0.0+parse_number&>}.fields
        case. 'PLOT_SIZE' do. PlotSize =: parse_number&>}.fields
        end.
    end.
    i.0 0
)
