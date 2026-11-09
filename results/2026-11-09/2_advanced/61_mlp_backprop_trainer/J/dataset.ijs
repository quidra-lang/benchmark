split_words =: 3 : '<;._1 '' '',y'
read_images =: 3 : 0
    images =. 0$a:
    for_line. }. <;._2 (1!:1 <'input/',y) do.
        fields =. <;._1 ',',>line
        id =. 0{::fields
        label =. parse_number 1{::fields
        pixels =. 2{::fields
        vector =. 0.0+pixels='1'
        images =. images,<(<id),(<label),(<pixels),<vector
    end.
    images
)
rng_shuffle =: 4 : 0
    state =. x
    order =. y
    for_i. |.1+i.(#order)-1 do.
        state =. 2147483647|48271x*state
        j =. (i+1)|state
        first =. i{order
        second =. j{order
        order =. second i}order
        order =. first j}order
    end.
    (<state),<order
)
read_dataset =: 3 : 0
    NetworkNames =: NetworkLayers =: 0$a:
    index =. _1
    for_line. <;._2 (1!:1 <'input/network.txt') do.
        text =. >line
        if. 0=#text do. continue. end.
        fields =. split_words text
        key =. 0{::fields
        select. key
        case. 'IMAGE' do. 'ImageWidth ImageHeight' =: parse_number&>}.fields
        case. 'NETWORK' do.
            index =. index+1
            NetworkNames =: NetworkNames,<1{::fields
            NetworkLayers =: NetworkLayers,<0$a:
        case. 'HIDDEN';'OUTPUT' do.
            units =. parse_number 1{::fields
            activation =. 2{::fields
            layer =. (<units),(<activation),<key
            layers =. (index{::NetworkLayers),<layer
            NetworkLayers =: (<layers)index}NetworkLayers
            if. key-:'OUTPUT' do. ClassCount =: units end.
        end.
    end.
    InitialTheta =: (#NetworkNames)$<i.0
    for_line. <;._2 (1!:1 <'input/weights.txt') do.
        text =. >line
        if. 0=#text do. continue. end.
        fields =. split_words text
        key =. 0{::fields
        if. key-:'NETWORK' do. index =. NetworkNames i.<1{::fields
        elseif. (<key)e.(<,'W'),<,'B' do.
            theta =. (index{::InitialTheta),0.0+parse_number&>}.fields
            InitialTheta =: (<theta)index}InitialTheta
        end.
    end.
    RunDefinitions =: 0$a:
    for_line. <;._2 (1!:1 <'input/params.txt') do.
        fields =. split_words >line
        select. 0{::fields
        case. 'SEED' do. Seed =: parse_number 1{::fields
        case. 'BATCH_SIZE' do. BatchSize =: parse_number 1{::fields
        case. 'MAX_EPOCHS' do. MaxEpochs =: parse_number 1{::fields
        case. 'PATIENCE' do. Patience =: parse_number 1{::fields
        case. 'LR_STEP' do.
            RateStep =: parse_number 1{::fields
            RateGamma =: 0.0+parse_number 2{::fields
        case. 'GRADIENT_CHECK_STRIDE' do. GradientStride =: parse_number 1{::fields
        case. 'CALIBRATION_BINS' do. CalibrationBins =: parse_number 1{::fields
        case. 'PRUNE' do. PruneFractions =: parse_number&>}.fields
        case. 'NOISE' do. NoiseFractions =: parse_number&>}.fields
        case. 'RUN' do.
            name =. 1{::fields
            network =. NetworkNames i.<2{::fields
            optimizer =. 3{::fields
            rate =. 0.0+parse_number 4{::fields
            decay =. 0.0+parse_number 5{::fields
            extra =. 0.0+parse_number&>6}.fields
            RunDefinitions =: RunDefinitions,<(<name),(<network),(<optimizer),(<rate),(<decay),<extra
        end.
    end.
    AllTrainImages =: read_images 'train.csv'
    TestImages =: read_images 'test.csv'
    i.0 0
)
