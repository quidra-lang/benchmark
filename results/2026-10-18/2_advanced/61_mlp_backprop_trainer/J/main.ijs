ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'evaluation.ijs'
load SourceDirectory,'dataset.ijs'
load SourceDirectory,'layers.ijs'
load SourceDirectory,'network.ijs'
load SourceDirectory,'optimizers.ijs'

norm =: 3 : 0
    total =. 0.0
    for_value. y do. total =. total+value*value end.
    %:total
)
correct_outcome =: 3 : '(1{::y)=2{::y'
write_lines =: 4 : 0
    text =. ''
    for_line. y do. text =. text,(>line),LF end.
    text 1!:2 <'output/',x
    i.0 0
)
gradient_checks =: 3 : 0
    lines =. 0$a:
    'state order' =. Seed rng_shuffle i.#TrainImages
    images =. (BatchSize<.#TrainImages){.order
    batch =. images{TrainImages
    batchids =. 0$a:
    for_image. batch do. batchids =. batchids,<0{::>image end.
    for_index. i.#NetworkNames do.
        if. #lines do. lines =. lines,<'' end.
        layout =. index{::NetLayouts
        theta =. index{::InitialTheta
        analytic =. 0{::network_mean_gradient (<layout),(<theta),<batch
        checked =. i.0
        passed =. 1
        for_parameter. GradientStride*i.>.((#theta)%GradientStride) do.
            original =. parameter{theta
            h =. 0.00001
            higher_theta =. (original+h)parameter}theta
            lower_theta =. (original-h)parameter}theta
            higher =. 1{::network_evaluate (<layout),(<higher_theta),<batch
            lower =. 1{::network_evaluate (<layout),(<lower_theta),<batch
            derivative =. (higher-lower)%(2*h)
            error =. (|(parameter{analytic)-derivative)%(1>.(|parameter{analytic)+|derivative)
            if. error>:0.000001 do. passed =. 0 end.
            checked =. checked,parameter
        end.
        lines =. lines,<emit 'network';index{::NetworkNames
        lines =. lines,<emit 'parameters';#theta
        lines =. lines,<emit 'batch';' 'join batchids
        layers =. 0{::layout
        for_layernumber. i.#layers do.
            layer =. layernumber{::layers
            weightstart =. 4{::layer
            biasstart =. 5{::layer
            outputs =. 1{::layer
            weights =. +/checked e.weightstart+i.biasstart-weightstart
            biases =. +/checked e.biasstart+i.outputs
            lines =. lines,<emit 'layer';(layernumber+1);'weights';weights;'biases';biases
        end.
        lines =. lines,<emit 'checked';#checked
        lines =. lines,<emit 'result';passed{::'FAIL';'PASS'
    end.
    lines
)
train_run =: 3 : 0
    definition =. y
    index =. 1{::definition
    layout =. index{::NetLayouts
    initial =. index{::InitialTheta
    theta =. initial
    state =. optimizer_initial #theta
    generator =. Seed
    order =. i.#TrainImages
    epochs =. 0$a:
    correctness =. (0,#TrainImages)$0
    updates =. wait =. bestepoch =. bestcorrect =. 0
    bestloss =. _
    besttheta =. theta
    stop =. 'max_epochs'
    for_epoch. 1+i.MaxEpochs do.
        rate =. definition optimizer_rate epoch
        'generator order' =. generator rng_shuffle order
        norms =. 0.0
        batches =. 0
        for_start. BatchSize*i.>.((#order)%BatchSize) do.
            indices =. (BatchSize<.(#order)-start){.start}.order
            images =. indices{TrainImages
            gradient =. 0{::network_mean_gradient (<layout),(<theta),<images
            weightindices =. I.1{::layout
            gradient =. ((weightindices{gradient)+(4{::definition)*weightindices{theta)weightindices}gradient
            norms =. norms+norm gradient
            batches =. batches+1
            'theta state' =. optimizer_update (<theta),(<gradient),(<state),(<definition),<rate
            updates =. updates+1
        end.
        training =. network_evaluate (<layout),(<theta),<TrainImages
        validation =. network_evaluate (<layout),(<theta),<ValidationImages
        statuses =. i.0
        for_outcome. 0{::training do. statuses =. statuses,correct_outcome >outcome end.
        correctness =. correctness,statuses
        trainloss =. 1{::training
        traincorrect =. 2{::training
        valloss =. 1{::validation
        valcorrect =. 2{::validation
        improved =. (epoch=1)+.valloss<bestloss
        if. improved do.
            bestepoch =. epoch
            bestloss =. valloss
            bestcorrect =. valcorrect
            besttheta =. theta
            wait =. 0
        else. wait =. wait+1 end.
        record =. (<epoch),(<rate),(<norms%batches),(<trainloss),(<traincorrect),(<valloss),(<valcorrect),<improved
        epochs =. epochs,<record
        if. wait>:Patience do.
            stop =. 'early'
            break.
        end.
    end.
    (<definition),(<layout),(<initial),(<besttheta),(<epochs),(<correctness),(<updates),(<bestepoch),(<bestloss),(<bestcorrect),<stop
)
prepare_evaluation =: 3 : 0
    'definition layout initial theta epochs correctness updates bestepoch bestloss bestcorrect stop' =. y
    evaluation =. network_evaluate (<layout),(<theta),<TestImages
    outcomes =. 0{::evaluation
    confusion =. ClassCount confusion_matrix outcomes
    top2 =. correctcount =. wrongcount =. 0
    correctsum =. wrongsum =. 0.0
    misclassified =. i.0
    for_index. i.#outcomes do.
        outcome =. index{::outcomes
        top2 =. top2+(1{::outcome)e.best_two 4{::outcome
        if. correct_outcome outcome do.
            correctcount =. correctcount+1
            correctsum =. correctsum+3{::outcome
        else.
            wrongcount =. wrongcount+1
            wrongsum =. wrongsum+3{::outcome
            misclassified =. misclassified,index
        end.
    end.
    confidencecorrect =. confidencewrong =. i.0
    if. correctcount do. confidencecorrect =. correctsum%correctcount end.
    if. wrongcount do. confidencewrong =. wrongsum%wrongcount end.
    forgettingevents =. forgettingrows =. never =. 0
    for_i. i.#TrainImages do.
        statuses =. i{"1 correctness
        events =. +/(}:statuses)*.-.}.statuses
        forgettingevents =. forgettingevents+events
        forgettingrows =. forgettingrows+events>0
        never =. never+-.+./statuses
    end.
    norms =. changes =. i.0
    layers =. 0{::layout
    for_layer. layers do.
        layer =. >layer
        indices =. (4{::layer)+i.(5{::layer)-4{::layer
        norms =. norms,norm indices{theta
        changes =. changes,norm indices{theta-initial
    end.
    calibration =. CalibrationBins 3$0.0
    for_outcome. outcomes do.
        outcome =. >outcome
        confidence =. 3{::outcome
        bucket =. (CalibrationBins-1)<.<.confidence*CalibrationBins
        calibration =. (1+(<bucket,0){calibration)(<bucket,0)}calibration
        calibration =. ((correct_outcome outcome)+(<bucket,1){calibration)(<bucket,1)}calibration
        calibration =. (confidence+(<bucket,2){calibration)(<bucket,2)}calibration
    end.
    ece =. 0.0
    for_row. calibration do.
        'number correct total' =. row
        if. number>0 do. ece =. ece+(number%#TestImages)*|(correct%number)-total%number end.
    end.
    hiddeninfo =. 0$a:
    for_l. i.(#layers)-1 do.
        layer =. l{::layers
        units =. 1{::layer
        means =. (ClassCount,units)$0.0
        counts =. ClassCount$0
        zeros =. units$0
        for_outcome. outcomes do.
            outcome =. >outcome
            class =. 1{::outcome
            activation =. l{::6{::outcome
            counts =. (1+class{counts)class}counts
            means =. ((class{means)+activation)class}means
            zeros =. zeros+activation=0
        end.
        available =. I.counts>0
        meanrows =. 0$a:
        for_class. i.ClassCount do.
            values =. i.0
            if. class{counts do. values =. (class{means)%class{counts end.
            meanrows =. meanrows,<values
        end.
        preferred =. i.0
        for_unit. i.units do.
            values =. unit{"1 available{means
            values =. values%available{counts
            preferred =. preferred,({.\:values){available
        end.
        hiddeninfo =. hiddeninfo,<(<meanrows),(<preferred),<zeros
    end.
    weightindices =. I.1{::layout
    orderedweights =. (/:|weightindices{theta){weightindices
    pruning =. 0 4$0.0
    for_percent. PruneFractions do.
        removed =. <.(percent*#weightindices)%100
        pruned =. 0.0(removed{.orderedweights)}theta
        result =. network_evaluate (<layout),(<pruned),<TestImages
        pruning =. pruning,percent,removed,(2{::result),1{::result
    end.
    noise =. 0 3$0
    for_percent. NoiseFractions do.
        generator =. Seed
        altered =. 0$a:
        flipped =. 0
        for_image. TestImages do.
            image =. >image
            vector =. 3{::image
            for_pixel. i.#vector do.
                generator =. 2147483647|48271x*generator
                if. (100|generator)<percent do.
                    vector =. (1.0-pixel{vector)pixel}vector
                    flipped =. flipped+1
                end.
            end.
            altered =. altered,<(<vector)3}image
        end.
        result =. network_evaluate (<layout),(<theta),<altered
        noise =. noise,percent,flipped,2{::result
    end.
    forgetting =. forgettingevents,forgettingrows,never
    diagnostics =. (<confusion),(<top2),(<confidencecorrect),(<confidencewrong),(<forgetting),(<norms),(<changes),(<calibration),(<ece),(<hiddeninfo),(<pruning),(<noise),<misclassified
    y,(<evaluation),<diagnostics
)
data_summary =: 3 : 0
    lines =. <'data'
    size =. ImageWidth*ImageHeight
    lines =. lines,<emit 'train';(#TrainImages);'validation';(#ValidationImages);'test';(#TestImages);'pixels';size
    maps =. 0$a:
    for_class. i.ClassCount do.
        traincount =. valcount =. testcount =. ink =. 0
        counts =. size$0
        for_image. TrainImages do.
            image =. >image
            if. class=1{::image do.
                traincount =. traincount+1
                black =. (2{::image)='1'
                counts =. counts+black
                ink =. ink++/black
            end.
        end.
        for_image. ValidationImages do. valcount =. valcount+class=1{::>image end.
        for_image. TestImages do. testcount =. testcount+class=1{::>image end.
        lines =. lines,<emit 'class';class;'train';traincount;'validation';valcount;'test';testcount;'ink';ink ratio traincount
        levels =. size$0
        if. traincount do. levels =. 9<.<.(10x*counts)%traincount end.
        maps =. maps,<levels
    end.
    lines =. lines,<emit 'mean_images';' 'join integer&.>i.ClassCount
    lines,level_maps maps
)
run_report =: 3 : 0
    'definition layout initial theta epochs correctness updates bestepoch bestloss bestcorrect stop evaluation diagnostics' =. y
    'confusion top2 confidencecorrect confidencewrong forgetting norms changes calibration ece hiddeninfo pruning noise misclassified' =. diagnostics
    name =. 0{::definition
    netname =. (1{::definition){::NetworkNames
    optimizer =. 2{::definition
    testcount =. #TestImages
    valcount =. #ValidationImages
    lines =. <emit 'run';name;'network';netname;'optimizer';optimizer
    lines =. lines,<emit 'epochs';(#epochs);'best_epoch';bestepoch;'stop';stop;'updates';updates
    lines =. lines,<emit 'best_val_loss';(six bestloss);'best_val_acc';(bestcorrect ratio valcount);'correct';(integer bestcorrect),'/',integer valcount
    lines =. lines,<emit 'test_loss';(six 1{::evaluation);'test_acc';((2{::evaluation)ratio testcount);'correct';(integer 2{::evaluation),'/',integer testcount
    lines =. lines,<emit 'top2_acc';(top2 ratio testcount);'correct';(integer top2),'/',integer testcount
    correcttext =. wrongtext =. '-'
    if. #,confidencecorrect do. correcttext =. fixed confidencecorrect end.
    if. #,confidencewrong do. wrongtext =. fixed confidencewrong end.
    lines =. lines,<emit 'confidence correct';correcttext;'wrong';wrongtext
    lines =. lines,<emit 'forgetting events';(0{forgetting);'rows';(1{forgetting);'never_learned';2{forgetting
    lines =. lines,<emit 'weight_norms';4 formatted norms
    lines =. lines,<emit 'weight_changes';4 formatted changes
    lines =. lines,<'curve'
    maximum =. 0.0
    for_epoch. epochs do. maximum =. maximum>.(3{::>epoch)>.5{::>epoch end.
    for_item. epochs do.
        record =. >item
        number =. 0{::record
        ct =. <.0.5+(39*3{::record)%maximum
        cv =. <.0.5+(39*5{::record)%maximum
        cells =. 40$' '
        cells =. 't'ct}cells
        if. ct=cv do. cells =. '*'cv}cells else. cells =. 'v'cv}cells end.
        text =. ((-2){.'  ',integer number),' |',cells,'|'
        if. number=bestepoch do. text =. text,' best' end.
        lines =. lines,<text
    end.
    lines =. lines,<'confusion'
    for_class. i.ClassCount do.
        lines =. lines,<(integer class),': ',' 'join integer&.>class{confusion
    end.
    for_class. i.ClassCount do.
        'support predicted precision recall f1' =. confusion class_measures class
        lines =. lines,<emit 'class';class;'support';support;'predicted';predicted;'precision';precision;'recall';recall;'f1';f1
    end.
    lines =. lines,<'calibration'
    for_bin. i.CalibrationBins do.
        'number correct total' =. bin{calibration
        confidence =. '-'
        if. number>0 do. confidence =. fixed total%number end.
        lines =. lines,<emit 'bin';(bin+1);(2 format_real bin%CalibrationBins);(2 format_real (bin+1)%CalibrationBins);'count';number;'accuracy';(correct ratio number);'confidence';confidence
    end.
    lines =. lines,<emit 'ece';fixed ece
    layers =. 0{::layout
    for_l. i.#hiddeninfo do.
        layer =. l{::layers
        'means preferred zeros' =. l{::hiddeninfo
        lines =. lines,<emit 'hidden';(l+1);(2{::layer);'units';1{::layer
        for_class. i.ClassCount do.
            values =. class{::means
            text =. '-'
            if. #values do. text =. 4 formatted values end.
            lines =. lines,<emit 'class';class;'mean';text
        end.
        lines =. lines,<emit 'preferred';' 'join integer&.>preferred
        if. (2{::layer)-:'RELU' do. lines =. lines,<emit 'zero_counts';' 'join integer&.>zeros end.
    end.
    lines =. lines,<'pruning'
    for_item. pruning do.
        'percent removed correct loss' =. item
        lines =. lines,<emit 'prune';percent;'removed';removed;'correct';correct;'test_acc';(correct ratio testcount);'test_loss';six loss
    end.
    lines =. lines,<'noise'
    for_item. noise do.
        'percent flipped correct' =. item
        lines =. lines,<emit 'noise';percent;'correct';correct;'test_acc';correct ratio testcount
    end.
    ids =. 0$a:
    for_index. misclassified do. ids =. ids,<0{::index{::TestImages end.
    text =. emit 'misclassified';#ids
    if. #ids do. text =. text,' ',' 'join ids end.
    lines,<text
)
run_predictions =: 3 : 0
    values =. i.0
    for_outcome. 0{::11{::y do. values =. values,2{::>outcome end.
    values
)
run_correctness =: 3 : 0
    values =. i.0
    for_outcome. 0{::11{::y do. values =. values,correct_outcome >outcome end.
    values
)
comparison_report =: 3 : 0
    runs =. y
    keys =. 0 3$0.0
    for_index. i.#runs do.
        run =. index{::runs
        keys =. keys,(-2{::11{::run),(8{::run),index
    end.
    rank =. /:keys
    top =. ({.rank){::runs
    'definition layout initial theta epochs correctness updates bestepoch bestloss bestcorrect stop evaluation diagnostics' =. top
    topname =. 0{::definition
    outcomes =. 0{::evaluation
    testcount =. #TestImages
    predictions =. (0,testcount)$0
    statuses =. (0,testcount)$0
    soft =. i.0
    for_index. i.#runs do.
        run =. index{::runs
        predictions =. predictions,run_predictions run
        statuses =. statuses,run_correctness run
        layers =. 0{::1{::run
        lastlayer =. >{:layers
        if. (2{::lastlayer)-:'SOFTMAX' do. soft =. soft,index end.
    end.
    majority =. softpredictions =. i.0
    for_image. i.testcount do.
        votes =. ClassCount$0
        for_value. image{"1 predictions do. votes =. (1+value{votes)value}votes end.
        maximum =. >./votes
        for_index. rank do.
            predicted =. (<index,image){predictions
            if. maximum=predicted{votes do.
                majority =. majority,predicted
                break.
            end.
        end.
        if. #soft do.
            scores =. ClassCount$0.0
            for_index. soft do. scores =. scores+4{::image{::0{::11{::index{::runs end.
            softpredictions =. softpredictions,{.best_two scores%#soft
        end.
    end.
    lines =. <'comparison'
    for_number. i.#rank do.
        run =. (number{rank){::runs
        definition =. 0{::run
        evaluation =. 11{::run
        correct =. 2{::evaluation
        lines =. lines,<emit 'rank';(number+1);(0{::definition);'correct';correct;'test_acc';(correct ratio testcount);'best_val_loss';(six 8{::run);'test_loss';(six 1{::evaluation);'best_epoch';(7{::run);'epochs';(#4{::run);'updates';6{::run
    end.
    lines =. lines,<'agreement'
    for_i. i.#runs do.
        agreements =. i.0
        for_j. i.#runs do. agreements =. agreements,+/(i{predictions)=j{predictions end.
        name =. 0{::0{::i{::runs
        lines =. lines,<emit name;' 'join integer&.>agreements
    end.
    lines =. lines,<emit 'mcnemar';topname
    topcorrect =. ({.rank){statuses
    for_index. }.rank do.
        othercorrect =. index{statuses
        b =. +/topcorrect*.-.othercorrect
        c =. +/(-.topcorrect)*.othercorrect
        difference =. 0>.(|b-c)-1
        numerator =. difference*difference
        denominator =. b+c
        chi =. '0.0000'
        if. denominator do. chi =. numerator ratio denominator end.
        significant =. ((numerator*1000)>3841*denominator){::'no';'yes'
        name =. 0{::0{::index{::runs
        lines =. lines,<emit 'vs';name;'b';b;'c';c;'chi2';chi;'significant';significant
    end.
    labels =. i.0
    for_image. TestImages do. labels =. labels,1{::>image end.
    chosen =. majority=labels
    fixedcount =. +/chosen*.-.topcorrect
    broken =. +/(-.chosen)*.topcorrect
    correct =. +/chosen
    lines =. lines,<emit 'ensemble correct';((integer correct),'/',integer testcount);'test_acc';(correct ratio testcount);'fixed';fixedcount;'broken';broken
    if. #soft do.
        correct =. +/softpredictions=labels
        lines =. lines,<emit 'soft_ensemble runs';(#soft);'correct';((integer correct),'/',integer testcount);'test_acc';correct ratio testcount
    else. lines =. lines,<'soft_ensemble none' end.
    noise =. 11{::12{::0{::runs
    for_row. noise do. lines =. lines,<emit 'noise';(0{row);'flipped';1{row end.
    totalconfusion =. (ClassCount,ClassCount)$0
    for_run. runs do. totalconfusion =. totalconfusion+0{::12{::>run end.
    pairs =. 0 3$0
    for_actual. i.ClassCount do.
        for_predicted. i.ClassCount do.
            value =. (<actual,predicted){totalconfusion
            if. (actual~:predicted)*.value>0 do. pairs =. pairs,(-value),actual,predicted end.
        end.
    end.
    lines =. lines,<'confused_pairs'
    for_row. (5<.#pairs){.(/:pairs){pairs do.
        'negativecount actual predicted' =. row
        lines =. lines,<emit actual;'as';predicted;'count';-negativecount
    end.
    maps =. 0$a:
    layout =. 1{::top
    theta =. 3{::top
    size =. ImageWidth*ImageHeight
    for_class. i.ClassCount do.
        values =. size$0.0
        number =. 0
        for_image. TestImages do.
            image =. >image
            if. class=1{::image do.
                number =. number+1
                inputs =. 2{::network_gradient (<layout),(<theta),(<image),<1
                values =. values+|inputs
            end.
        end.
        if. number do. values =. values%number end.
        maximum =. >./values
        levels =. size$0
        if. maximum>0 do. levels =. 9<.<.(10*values)%maximum end.
        maps =. maps,<levels
    end.
    lines =. lines,<''
    lines =. lines,<emit 'saliency';topname
    lines =. lines,<emit 'classes';' 'join integer&.>i.ClassCount
    lines =. lines,level_maps maps
    lines =. lines,<''
    lines =. lines,<emit 'hardest_training_examples';topname
    training =. 0{::network_evaluate (<layout),(<theta),<TrainImages
    losses =. i.0
    for_outcome. training do. losses =. losses,5{::>outcome end.
    order =. \:losses
    for_index. (5<.#order){.order do.
        outcome =. index{::training
        lines =. lines,<emit (0{::outcome);'label';(1{::outcome);'predicted';(2{::outcome);'loss';six 5{::outcome
    end.
    lines =. lines,<''
    lines =. lines,<emit 'misclassified_examples';topname
    outcomes =. 0{::11{::top
    for_index. I.-.topcorrect do.
        image =. index{::TestImages
        outcome =. index{::outcomes
        nearest =. 0
        distance =. _
        pixels =. 2{::image
        for_candidate. i.#AllTrainImages do.
            candidatepixels =. 2{::candidate{::AllTrainImages
            d =. +/pixels~:candidatepixels
            if. d<distance do. distance =. d [ nearest =. candidate end.
        end.
        label =. 1{::image
        true_score =. label{4{::outcome
        values =. index{"1 predictions
        lines =. lines,<emit (0{::image);'label';label;'predicted';(2{::outcome);'confidence';(fixed 3{::outcome);'true_score';(fixed true_score);'runs';(' 'join integer&.>values);'ensemble';index{majority
        neighbor =. nearest{::AllTrainImages
        lines =. lines,<emit 'nearest';(0{::neighbor);'label';(1{::neighbor);'distance';distance
        lines =. lines,image_lines pixels
    end.
    lines
)
output_runs =: 3 : 0
    runs =. y
    loglines =. <'run,epoch,lr,grad_norm,train_loss,train_acc,val_loss,val_acc,improved'
    weightlines =. 0$a:
    predictionlines =. <'run,id,label,predicted,confidence'
    for_run. runs do.
        'definition layout initial theta epochs correctness updates bestepoch bestloss bestcorrect stop evaluation diagnostics' =. >run
        name =. 0{::definition
        netname =. (1{::definition){::NetworkNames
        for_record. epochs do.
            'epoch rate gradient trainloss traincorrect valloss valcorrect improved' =. >record
            fields =. (<name),(<integer epoch),(<six rate),(<fixed gradient),(<six trainloss),(<traincorrect ratio #TrainImages),(<six valloss),(<valcorrect ratio #ValidationImages),<integer improved
            loglines =. loglines,<','join fields
        end.
        if. #weightlines do. weightlines =. weightlines,<'' end.
        weightlines =. weightlines,<emit 'RUN';name;'NETWORK';netname;'EPOCH';bestepoch
        layers =. 0{::layout
        for_l. i.#layers do.
            layer =. l{::layers
            inputs =. 0{::layer
            outputs =. 1{::layer
            start =. 4{::layer
            biasstart =. 5{::layer
            weightlines =. weightlines,<emit 'LAYER';(l+1);outputs;inputs
            for_unit. i.outputs do.
                values =. ((start+unit*inputs)+i.inputs){theta
                weightlines =. weightlines,<emit 'W';4 formatted values
            end.
            weightlines =. weightlines,<emit 'B';4 formatted (biasstart+i.outputs){theta
        end.
        for_outcome. 0{::evaluation do.
            outcome =. >outcome
            fields =. (<name),(<0{::outcome),(<integer 1{::outcome),(<integer 2{::outcome),<fixed 3{::outcome
            predictionlines =. predictionlines,<','join fields
        end.
    end.
    'training_log.csv'write_lines loglines
    'final_weights.txt'write_lines weightlines
    'predictions.csv'write_lines predictionlines
    i.0 0
)
main =: 3 : 0
    read_dataset ''
    split =. (#AllTrainImages)-<.(#AllTrainImages)%5
    TrainImages =: split{.AllTrainImages
    ValidationImages =: split}.AllTrainImages
    NetLayouts =: 0$a:
    for_layers. NetworkLayers do. NetLayouts =: NetLayouts,<network_layout >layers end.
    checks =. gradient_checks ''
    runs =. 0$a:
    for_definition. RunDefinitions do. runs =. runs,<prepare_evaluation train_run >definition end.
    lines =. data_summary ''
    lines =. lines,<''
    for_run. runs do.
        lines =. lines,run_report >run
        lines =. lines,<''
    end.
    lines =. lines,comparison_report runs
    'gradient_check.txt'write_lines checks
    output_runs runs
    'evaluation.txt'write_lines lines
    i.0 0
)
main ''
