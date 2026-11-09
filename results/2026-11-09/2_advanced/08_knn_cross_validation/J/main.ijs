ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
div =: 4 : '_1 x:<.(x:x)%x:y'
real =: 3 : '1.0*y'
num =: 3 : '10#.Digits i.y'
number =: 3 : 0
    if. y<0 do. '-',number -y return. end.
    text =. ''
    while. y>0 do.
        text =. ((10|y){Digits),text
        y =. y div 10
    end.
    if. #text do. text else. '0' end.
)
split =: 4 : 0
    parts =. 0$a:
    while. 1 do.
        position =. y i.x
        parts =. parts,<position{.y
        if. position=#y do. parts return. end.
        y =. (position+1)}.y
    end.
)
join =: 4 : 0
    text =. ''
    for_index. i.#y do.
        if. index do. text =. text,x end.
        text =. text,index{::y
    end.
    text
)
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
empty_table =: 3 : '0 2$a:'
table_keys =: 3 : '0{"1 y'
get_key =: 4 : '((table_keys y)i.<x){::1{"1 y'
put_key =: 4 : 0
    'key value' =. x
    position =. (table_keys y)i.<key
    if. position<#y do. (<value) (<position,1)}y
    else. y,1 2$(<key),<value end.
)
record =: 4 : '('' '' split x),.y'
collect =: 4 : 0
    values =. 0$a:
    for_box. y do. values =. values,<x get_key >box end.
    values
)
load SourceDirectory,'dataset.ijs'
load SourceDirectory,'scaling.ijs'
load SourceDirectory,'neighbors.ijs'
load SourceDirectory,'validation.ijs'
load SourceDirectory,'report.ijs'
build_grid =: 3 : 0
    Grid =: 0$a:
    for_k. 'K_VALUES' get_key Settings do.
        for_metricbox. 'METRICS' get_key Settings do.
            for_weightingbox. 'WEIGHTINGS' get_key Settings do.
                for_scalingbox. 'SCALINGS' get_key Settings do. Grid =: Grid,<model_record (<k),metricbox,weightingbox,scalingbox end.
            end.
        end.
    end.
    i.0
)
correct_count =: 4 : 0
    count =. 0
    for_index. i.#y do. count =. count+('label' get_key index{::x)-:'label' get_key index{::y end.
    count
)
prediction_errors =: 4 : 0
    errors =. 0$0.0
    for_index. i.#y do. errors =. errors,('estimate' get_key index{::x)-'target' get_key index{::y end.
    errors
)
id_order =: 3 : '(/:''id'' collect y){y'
best_classifier =: 3 : 0
    best =. 0{::y
    for_box. }.y do.
        candidate =. >box
        if. ('correct' get_key candidate)>'correct' get_key best do. best =. candidate end.
    end.
    best
)
best_regressor =: 3 : 0
    best =. 0{::y
    for_box. }.y do.
        candidate =. >box
        if. (four_decimal 'rmse' get_key candidate)<!.0 four_decimal 'rmse' get_key best do. best =. candidate end.
    end.
    best
)
cross_validate =: 3 : 0
    'models rows features' =. y
    predictions =. (#models)#<(#rows)#a:
    spaces =. 0$a:
    for_box. models do.
        model =. >box
        spaces =. spaces,<('scaling' get_key model),'/','metric' get_key model
    end.
    spaces =. ~.spaces
    for_foldbox. FoldCount stratified_folds rows do.
        fold =. >foldbox
        training =. (-.(i.#rows)e.fold)#rows
        queries =. fold{rows
        for_spacebox. spaces do.
            'method metric' =. '/' split >spacebox
            orders =. neighbor_orders (<training),(<queries),(<method),(<metric),<features
            for_modelindex. i.#models do.
                model =. modelindex{::models
                if. (-.method-:'scaling' get_key model)+.-.metric-:'metric' get_key model do. continue. end.
                predicted =. modelindex{::predictions
                for_position. i.#fold do.
                    prediction =. prediction_from_order (position{orders),(<'k' get_key model),<'weighting' get_key model
                    predicted =. (<prediction) (position{fold)}predicted
                end.
                predictions =. (<predicted) modelindex}predictions
            end.
        end.
    end.
    results =. 0$a:
    for_modelindex. i.#models do.
        predicted =. modelindex{::predictions
        hits =. 0$0
        for_index. i.#rows do. hits =. hits,('label' get_key index{::predicted)-:'label' get_key index{::rows end.
        result =. 'model predictions hits correct rmse' record (modelindex{models),(<predicted),(<hits),(<+/hits),<rmse predicted prediction_errors rows
        results =. results,<result
    end.
    results
)
label_counts =: 3 : 0
    values =. 0$a:
    for_labelbox. Labels do.
        label =. >labelbox
        count =. 0
        for_box. y do. count =. count+label-:'label' get_key >box end.
        values =. values,<label,' ',number count
    end.
    ' ' join values
)
evaluation_lines =: 4 : 0
    count =. #Labels
    matrix =. (count,count)$0
    for_index. i.#y do.
        first =. Labels i.<'label' get_key index{::y
        second =. Labels i.<'label' get_key index{::x
        matrix =. (1+(<first,second){matrix) (<first,second)}matrix
    end.
    add_line (<'true\predicted'),<' ' join Labels
    for_index. i.count do. add_line (index{Labels),number&.><"0 index{matrix end.
    totals =. 3$0.0
    valued =. 3$0
    for_index. i.count do.
        hits =. (<index,index){matrix
        predicted =. +/index{"1 matrix
        actual =. +/index{matrix
        numerators =. hits,hits,2*hits
        denominators =. predicted,actual,predicted+actual
        for_position. i.3 do.
            denominator =. position{denominators
            if. denominator>0 do.
                totals =. ((position{totals)+(real position{numerators)%real denominator) position}totals
                valued =. (1+position{valued) position}valued
            end.
        end.
        add_line (<'class'),(index{Labels),(<'precision'),(<hits fraction_text predicted),(<'recall'),(<hits fraction_text actual),(<'f1'),(<(2*hits) fraction_text predicted+actual),(<'support'),<actual
    end.
    averages =. 0$a:
    for_index. i.3 do.
        value =. '-'
        if. index{valued do. value =. f4 (index{totals)%real index{valued end.
        averages =. averages,<value
    end.
    add_line (<'macro precision'),(0{averages),(<'recall'),(1{averages),(<'f1'),2{averages
    i.0
)
reliability_lines =: 4 : 0
    bounds =. 'BINS' get_key Settings
    lowers =. 0.0,bounds
    counts =. hits =. (#lowers)$0
    shares =. (#lowers)$0.0
    for_index. i.#y do.
        prediction =. index{::x
        share =. 'share' get_key prediction
        bin =. +/bounds<:!.0 share
        correct =. ('label' get_key prediction)-:'label' get_key index{::y
        counts =. (1+bin{counts) bin}counts
        hits =. (correct+bin{hits) bin}hits
        shares =. (share+bin{shares) bin}shares
    end.
    for_index. i.#lowers do.
        fields =. (<'bin'),(<2 fixed index{lowers),(<'rows'),<index{counts
        if. index{counts do. fields =. fields,(<'correct'),(<(index{hits) ratio_text index{counts),(<'share'),<f4 (index{shares)%real index{counts end.
        add_line fields
    end.
    i.0
)
classifier_summary =: 3 : '(model_text ''model'' get_key y),'' correct '',((''correct'' get_key y) ratio_text #Train),'' rmse '',f4 ''rmse'' get_key y'
regressor_summary =: 3 : '(model_text ''model'' get_key y),'' rmse '',(f4 ''rmse'' get_key y),'' correct '',(''correct'' get_key y) ratio_text #Train'
matching_results =: 3 : 0
    'field value' =. y
    found =. 0$a:
    for_box. Results do.
        result =. >box
        if. value-:field get_key 'model' get_key result do. found =. found,box end.
    end.
    found
)
leave_one_out_parts =: 3 : 0
    model =. 'model' get_key Classifier
    kvalues =. 'K_VALUES' get_key Settings
    byk =. (#kvalues)#<(#Train)#a:
    estimates =. (#Train)$0.0
    for_index. i.#Train do.
        training =. ((i.#Train)~:index)#Train
        queries =. index{Train
        order =. 0{::neighbor_orders (<training),(<queries),(<'scaling' get_key model),(<'metric' get_key model),<Features
        for_position. i.#kvalues do.
            predicted =. position{::byk
            prediction =. prediction_from_order (<order),(<position{kvalues),<'weighting' get_key model
            predicted =. (<prediction) index}predicted
            byk =. (<predicted) position}byk
        end.
        predicted =. predict_rows (<'model' get_key Regressor),(<training),(<queries),<Features
        estimates =. ('estimate' get_key 0{::predicted) index}estimates
    end.
    selected =. (kvalues i.'k' get_key model){::byk
    errors =. 0$0
    for_index. i.#Train do. if. -.('label' get_key index{::selected)-:'label' get_key index{::Train do. errors =. errors,index end. end.
    next_part ''
    add_line (<'leave_one_out classifier'),<model_text model
    add_line (<'errors'),<(#errors) ratio_text #Train
    add_line (<'class_errors'),<label_counts errors{Train
    ids =. 'id' collect errors{Train
    for_index. (/:ids){errors do.
        row =. index{::Train
        prediction =. index{::selected
        add_line (<'id' get_key row),(<'true'),(<'label' get_key row),(<'predicted'),(<'label' get_key prediction),(<'share'),<f4 'share' get_key prediction
    end.
    residuals =. estimates-(>'target' collect Train)
    next_part ''
    add_line (<'leave_one_out regressor'),<model_text 'model' get_key Regressor
    add_line (<'rmse'),(<f4 rmse residuals),(<'mae'),<f4 mae residuals
    add_line (<'largest'),(<TopCount),<'residuals'
    keys =. 0 2$a:
    for_index. i.#Train do. keys =. keys,1 2$(<-four_decimal |index{residuals),index{TrainIDs end.
    ranking =. /:keys
    for_index. (TopCount<.#ranking){.ranking do.
        row =. index{::Train
        add_line (<'id' get_key row),(<'target'),(<f4 'target' get_key row),(<'estimate'),(<f4 index{estimates),(<'residual'),<f4 index{residuals
    end.
    next_part ''
    add_line <'leave_one_out by k metric=',('metric' get_key model),' weighting=',('weighting' get_key model),' scaling=','scaling' get_key model
    for_position. i.#kvalues do.
        predicted =. position{::byk
        add_line (<'k=',number position{kvalues),(<'correct'),(<(predicted correct_count Train) ratio_text #Train),(<'rmse'),<f4 rmse predicted prediction_errors Train
    end.
    i.0
)
nested_part =: 3 : 0
    next_part ''
    add_line (<'nested_cross_validation folds'),<FoldCount
    estimates =. (#Train)$0.0
    total =. 0
    for_foldindex. i.#Folds do.
        fold =. foldindex{::Folds
        inner =. (-.(i.#Train)e.fold)#Train
        queries =. fold{Train
        results =. cross_validate (<Grid),(<inner),<Features
        classifier =. best_classifier results
        regressor =. best_regressor results
        predicted =. predict_rows (<'model' get_key classifier),(<inner),(<queries),<Features
        correct =. predicted correct_count queries
        total =. total+correct
        predicted =. predict_rows (<'model' get_key regressor),(<inner),(<queries),<Features
        estimates =. (>'estimate' collect predicted) fold}estimates
        add_line (<'fold'),(<foldindex+1),(<'classifier'),(<model_text 'model' get_key classifier),(<'inner'),(<f4 (real 'correct' get_key classifier)%real #inner),(<'outer'),<correct ratio_text #fold
        add_line (<'fold'),(<foldindex+1),(<'regressor'),(<model_text 'model' get_key regressor),(<'inner'),(<f4 'rmse' get_key regressor),(<'outer'),<f4 rmse predicted prediction_errors queries
    end.
    add_line (<'nested accuracy'),(<total ratio_text #Train),(<'rmse'),<f4 rmse estimates-(>'target' collect Train)
    i.0
)
feature_selection_part =: 3 : 0
    next_part ''
    model =. 'model' get_key Classifier
    current =. selected =. Features
    selectedcorrect =. 'correct' get_key Classifier
    models =. ,<model
    add_line (<'feature_selection'),<model_text model
    add_line (<'start features'),(<' ' join current{FeatureNames),(<'correct'),<selectedcorrect ratio_text #Train
    step =. 0
    while. (#current)>:3 do.
        step =. step+1
        candidates =. 0$0
        for_feature. current do.
            result =. 0{::cross_validate (<models),(<Train),<current-.feature
            candidates =. candidates,'correct' get_key result
        end.
        position =. candidates i.>./candidates
        removed =. position{current
        correct =. position{candidates
        fields =. 0$a:
        for_index. i.#current do. fields =. fields,<( (index{current){::FeatureNames),' ',number index{candidates end.
        current =. current-.removed
        add_line (<'step'),(<step),(<'remove'),(removed{FeatureNames),(<'correct'),(<correct ratio_text #Train),(<'candidates'),<' ' join fields
        if. correct>:selectedcorrect do. selected =. current
            selectedcorrect =. correct end.
    end.
    predicted =. predict_rows (<model),(<Train),(<Labelled),<selected
    add_line (<'selected features'),(<' ' join selected{FeatureNames),(<'correct'),<selectedcorrect ratio_text #Train
    add_line (<'selected test'),<(predicted correct_count Labelled) ratio_text #Labelled
    i.0
)
metrics_lines =: 3 : 0
    ReportLines =: 0$a:
    add_line (<'data train'),(<#Train),(<'test'),(<#Test),(<'labelled'),(<#Labelled),(<'targets'),(<#Targeted),(<'features'),(<#Features),(<'classes'),<#Labels
    add_line (<'classes'),<label_counts Train
    for_methodbox. 'SCALINGS' get_key Settings do.
        method =. >methodbox
        scaling =. method compute_scaling Train
        centers =. 'centers' get_key scaling
        scales =. 'scales' get_key scaling
        next_part ''
        add_line (<'scaling'),<method
        for_feature. Features do. add_line (feature{FeatureNames),(<'center'),(<6 fixed feature{centers),(<'scale'),<6 fixed feature{scales end.
    end.
    next_part ''
    add_line (<'folds'),<FoldCount
    for_index. i.#Folds do.
        fold =. index{::Folds
        add_line (<'fold'),(<index+1),(<'size'),(<#fold),<label_counts fold{Train
    end.
    next_part ''
    add_line (<'grid'),<#Grid
    add_line (<'best_classifier'),<classifier_summary Classifier
    add_line (<'best_regressor'),<regressor_summary Regressor
    accuracy =. /:-(>'correct' collect Results)
    errorvalues =. 0$0
    for_box. Results do. errorvalues =. errorvalues,four_decimal 'rmse' get_key >box end.
    error =. /:errorvalues
    for_kindbox. 'accuracy';'rmse' do.
        kind =. >kindbox
        next_part ''
        add_line (<'top'),(<TopCount),(<'by'),<kind
        if. kind-:'accuracy' do. ranking =. accuracy else. ranking =. error end.
        ranking =. (TopCount<.#ranking){.ranking
        for_rank. i.#ranking do.
            result =. (rank{ranking){::Results
            if. kind-:'accuracy' do. text =. classifier_summary result else. text =. regressor_summary result end.
            add_line (<rank+1),<text
        end.
    end.
    fields =. 'k';'metric';'weighting';'scaling'
    params =. 'K_VALUES';'METRICS';'WEIGHTINGS';'SCALINGS'
    for_position. i.4 do.
        field =. position{::fields
        values =. (position{::params) get_key Settings
        if. position=0 do. values =. <"0 values end.
        next_part ''
        add_line (<'best per'),<field
        for_valuebox. values do.
            value =. >valuebox
            results =. matching_results (<field),<value
            classifier =. best_classifier results
            regressor =. best_regressor results
            if. position=0 do. value =. number value end.
            add_line (<field,'=',value),(<'classifier'),(<model_text 'model' get_key classifier),(<'accuracy'),(<f4 (real 'correct' get_key classifier)%real #Train),(<'regressor'),(<model_text 'model' get_key regressor),(<'rmse'),<f4 'rmse' get_key regressor
        end.
    end.
    next_part ''
    add_line <'classifier folds'
    hits =. 'hits' get_key Classifier
    for_index. i.#Folds do.
        fold =. index{::Folds
        add_line (<'fold'),(<index+1),(<'correct'),<(+/fold{hits) ratio_text #fold
    end.
    next_part ''
    add_line <'regressor folds'
    for_index. i.#Folds do.
        fold =. index{::Folds
        predicted =. fold{'predictions' get_key Regressor
        add_line (<'fold'),(<index+1),(<'size'),(<#fold),(<'rmse'),<f4 rmse predicted prediction_errors fold{Train
    end.
    next_part ''
    add_line <'cross_validation classes'
    ('predictions' get_key Classifier) evaluation_lines Train
    next_part ''
    add_line <'cross_validation reliability'
    ('predictions' get_key Classifier) reliability_lines Train
    next_part ''
    add_line <'mcnemar'
    for_metricbox. 'METRICS' get_key Settings do.
        comparison =. best_classifier matching_results (<'metric'),metricbox
        otherhits =. 'hits' get_key comparison
        b =. +/hits*.-.otherhits
        c =. +/otherhits*.-.hits
        base =. 0>.((|b-c)-1)
        numerator =. base*base
        denominator =. b+c
        if. denominator>0 do. statistic =. numerator fraction_text denominator else. statistic =. '0/1 0.0000' end.
        significant =. ((1000*numerator)>3841*denominator){::'no';'yes'
        add_line (<model_text 'model' get_key comparison),(<'b'),(<b),(<'c'),(<c),(<'statistic'),(<statistic),(<'significant'),<significant
    end.
    leave_one_out_parts ''
    nested_part ''
    feature_selection_part ''
    labelledpredictions =. LabelledIndices{TestPredictions
    next_part ''
    add_line (<'test classification'),<model_text 'model' get_key Classifier
    add_line (<'labelled'),(<#Labelled),(<'correct'),<(labelledpredictions correct_count Labelled) ratio_text #Labelled
    labelledpredictions evaluation_lines Labelled
    next_part ''
    add_line <'test reliability'
    labelledpredictions reliability_lines Labelled
    next_part ''
    add_line (<'uncertain'),(<TopCount),<'test rows'
    margins =. 0$0.0
    rounded =. 0$0
    for_box. TestPredictions do.
        prediction =. >box
        margin =. ('share' get_key prediction)-'runner_share' get_key prediction
        margins =. margins,margin
        rounded =. rounded,four_decimal margin
    end.
    ranking =. /:rounded
    for_index. (TopCount<.#ranking){.ranking do.
        row =. index{::Test
        prediction =. index{::TestPredictions
        truth =. 'label' get_key row
        if. 0=#truth do. truth =. '-' end.
        add_line (<'id' get_key row),(<'predicted'),(<'label' get_key prediction),(<'share'),(<f4 'share' get_key prediction),(<'runner_up'),(<'runner_up' get_key prediction),(<'share'),(<f4 'runner_share' get_key prediction),(<'margin'),(<f4 index{margins),(<'true'),<truth
    end.
    next_part ''
    add_line (<'test regression'),<model_text 'model' get_key Regressor
    estimates =. TargetedIndices{TestEstimates
    targets =. >'target' collect Targeted
    errors =. estimates-targets
    add_line (<'targets'),(<#Targeted),(<'rmse'),(<f4 rmse errors),(<'mae'),(<f4 mae errors),(<'r2'),<f4 errors r_squared targets
    for_labelbox. Labels do.
        label =. >labelbox
        chosen =. 0$0
        for_index. i.#Targeted do. if. label-:'label' get_key index{::Targeted do. chosen =. chosen,index end. end.
        value =. '-'
        if. #chosen do. value =. f4 rmse chosen{errors end.
        add_line (<'class'),(<label),(<'targets'),(<#chosen),(<'rmse'),<value
    end.
    next_part ''
    add_line <'misclassified test rows'
    count =. 0
    for_index. LabelledIndices do.
        row =. index{::Test
        prediction =. index{::TestPredictions
        if. ('label' get_key prediction)-:'label' get_key row do. continue. end.
        count =. count+1
        add_line (<'id' get_key row),(<'true'),(<'label' get_key row),(<'predicted'),(<'label' get_key prediction),(<'share'),<f4 'share' get_key prediction
        for_box. 'neighbors' get_key prediction do.
            'gap neighbor' =. >box
            add_line (<'  ','id' get_key neighbor),(<'label' get_key neighbor),<f4 gap
        end.
    end.
    add_line (<'count'),<count
    ReportLines
)
classifier_space =: 3 : 0
    model =. 'model' get_key Classifier
    scaling =. ('scaling' get_key model) compute_scaling Train
    references =. 0$a:
    for_box. Train do. references =. references,<transform_values (<scaling),(<'values' get_key >box),<Features end.
    Space =: empty_table ''
    for_box. Train,Test do.
        row =. >box
        vector =. transform_values (<scaling),(<'values' get_key row),<Features
        gaps =. 0$0.0
        for_referencebox. references do. gaps =. gaps,distance (<vector),referencebox,<'metric' get_key model end.
        Space =: ((<'id' get_key row),<gaps) put_key Space
    end.
    i.0
)
space_order =: 4 : 0
    gaps =. ('id' get_key x) get_key Space
    neighbors =. 0$a:
    for_box. y do.
        row =. >box
        index =. TrainIDs i.<'id' get_key row
        neighbors =. neighbors,<(<index{gaps),<row
    end.
    sort_neighbors neighbors
)
space_vote =: 3 : 0
    'query rows k' =. y
    order =. query space_order rows
    nearest =. (k<.#order){.order
    ('weighting' get_key 'model' get_key Classifier) vote nearest
)
nearest_label =: 4 : '''label'' get_key 1{::0{::x space_order y'
wilson_editing =: 3 : 0
    current =. y
    passes =. 0$a:
    while. 1 do.
        removals =. 0$a:
        removed =. 0$a:
        for_box. current do.
            row =. >box
            id =. 'id' get_key row
            others =. current#~-.('id' collect current)e.<id
            prediction =. space_vote (<row),(<others),<{.'EDIT_K' get_key Settings
            if. -.('label' get_key prediction)-:'label' get_key row do.
                removals =. removals,<box,<prediction
                removed =. removed,<id
            end.
        end.
        passes =. passes,<removals
        if. 0=#removals do. break. end.
        current =. current#~-.('id' collect current)e.removed
    end.
    (<current),<passes
)
hart_condensing =: 3 : 0
    store =. 1{.y
    stored =. <'id' get_key 0{::y
    scans =. 0
    while. 1 do.
        scans =. scans+1
        added =. 0
        for_box. y do.
            row =. >box
            id =. 'id' get_key row
            if. (<id)e.stored do. continue. end.
            if. -. (row nearest_label store)-:'label' get_key row do.
                store =. store,box
                stored =. stored,<id
                added =. 1
            end.
        end.
        if. -.added do. break. end.
    end.
    (<id_order store),<scans
)
id_lines =: 3 : 0
    ids =. 'id' collect y
    for_first. 10*i.1+(<:#ids) div 10 do.
        length =. 10<.(#ids)-first
        add_line <' ' join length{.first}.ids
    end.
    i.0
)
prototypes_lines =: 3 : 0
    classifier_space ''
    ordered =. id_order Train
    'edited passes' =. wilson_editing ordered
    'condensed condensedscans' =. hart_condensing ordered
    'editedcondensed editedscans' =. hart_condensing edited
    ReportLines =: 0$a:
    model =. 'model' get_key Classifier
    add_line (<'space'),<model_text model
    next_part ''
    add_line <'editing k=',number {.'EDIT_K' get_key Settings
    for_index. i.#passes do.
        removals =. index{::passes
        add_line (<'pass'),(<index+1),(<'removed'),<#removals
        for_box. removals do.
            'row prediction' =. >box
            add_line (<'  ','id' get_key row),(<'true'),(<'label' get_key row),(<'predicted'),(<'label' get_key prediction),(<'share'),<f4 'share' get_key prediction
        end.
    end.
    add_line (<'edited size'),(<#edited),(<'removed'),<(#Train)-#edited
    next_part ''
    add_line (<'condensing original scans'),(<condensedscans),(<'size'),<#condensed
    add_line (<'condensing edited scans'),(<editedscans),(<'size'),<#editedcondensed
    next_part ''
    names =. 'original';'edited';'condensed';'edited_condensed'
    sets =. (<ordered),(<edited),(<condensed),<editedcondensed
    for_index. i.4 do.
        rows =. index{::sets
        knn =. nearest =. 0
        for_box. Labelled do.
            query =. >box
            truth =. 'label' get_key query
            prediction =. space_vote (<query),(<rows),<'k' get_key model
            knn =. knn+truth-:'label' get_key prediction
            nearest =. nearest+truth-:query nearest_label rows
        end.
        add_line (<'set'),(index{names),(<'size'),(<#rows),(<label_counts rows),(<'knn'),(<knn ratio_text #Labelled),(<'1nn'),<nearest ratio_text #Labelled
    end.
    next_part ''
    add_line <'prototypes condensed'
    id_lines condensed
    next_part ''
    add_line <'prototypes edited_condensed'
    id_lines editedcondensed
    next_part ''
    add_line <'borders'
    total =. 0
    for_labelbox. Labels do.
        label =. >labelbox
        members =. ordered#~('label' collect ordered)e.labelbox
        borders =. 0
        sametotal =. othertotal =. 0.0
        for_box. members do.
            row =. >box
            others =. ordered#~-.('id' collect ordered)e.<'id' get_key row
            order =. row space_order others
            same =. other =. 0.0
            foundsame =. foundother =. 0
            for_neighborbox. order do.
                'gap neighbor' =. >neighborbox
                if. label-:'label' get_key neighbor do.
                    if. -.foundsame do. same =. gap
                        foundsame =. 1 end.
                else.
                    if. -.foundother do. other =. gap
                        foundother =. 1 end.
                end.
                if. foundsame*.foundother do. break. end.
            end.
            if. -.label-:'label' get_key 1{::0{::order do. borders =. borders+1 end.
            sametotal =. sametotal+same
            othertotal =. othertotal+other
        end.
        total =. total+borders
        add_line (<'class'),(<label),(<'size'),(<#members),(<'border'),(<borders),(<'same'),(<f4 sametotal%real #members),(<'other'),<f4 othertotal%real #members
    end.
    add_line (<'border total'),<total ratio_text #Train
    next_part ''
    add_line <'hubs k=',(number 'k' get_key model),' queries ',number #Test
    occurrences =. (#Train)$0
    for_box. TestPredictions do.
        for_neighborbox. 'neighbors' get_key >box do.
            neighbor =. 1{::>neighborbox
            index =. TrainIDs i.<'id' get_key neighbor
            occurrences =. (1+index{occurrences) index}occurrences
        end.
    end.
    keys =. 0 2$a:
    for_index. i.#Train do. keys =. keys,1 2$(<-index{occurrences),index{TrainIDs end.
    ranking =. /:keys
    for_index. (TopCount<.#ranking){.ranking do.
        row =. index{::Train
        add_line (<'id' get_key row),(<'label' get_key row),<index{occurrences
    end.
    add_line (<'anti_hubs'),<+/occurrences=0
    ReportLines
)
learning_curve_lines =: 3 : 0
    lines =. <'n,train_size,correct,accuracy,rmse'
    for_limit. 'CURVE' get_key Settings do.
        counts =. (#Labels)$0
        rows =. 0$a:
        for_box. Train do.
            row =. >box
            index =. Labels i.<'label' get_key row
            if. (index{counts)<limit do.
                counts =. (1+index{counts) index}counts
                rows =. rows,box
            end.
        end.
        predicted =. predict_rows (<'model' get_key Classifier),(<rows),(<Labelled),<Features
        correct =. predicted correct_count Labelled
        estimated =. predict_rows (<'model' get_key Regressor),(<rows),(<Targeted),<Features
        fields =. (<number limit),(<number #rows),(<number correct),(<f4 (real correct)%real #Labelled),<f4 rmse estimated prediction_errors Targeted
        lines =. lines,<',' join fields
    end.
    lines
)
run_experiment =: 3 : 0
    build_grid ''
    Folds =: FoldCount stratified_folds Train
    Results =: cross_validate (<Grid),(<Train),<Features
    Classifier =: best_classifier Results
    Regressor =: best_regressor Results
    TestPredictions =: predict_rows (<'model' get_key Classifier),(<Train),(<Test),<Features
    estimated =. predict_rows (<'model' get_key Regressor),(<Train),(<Test),<Features
    TestEstimates =: >'estimate' collect estimated
    i.0
)
grid_lines =: 3 : 0
    lines =. <'k,metric,weighting,scaling,correct,accuracy,rmse'
    for_box. Results do.
        result =. >box
        model =. 'model' get_key result
        fields =. (<number 'k' get_key model),(<'metric' get_key model),(<'weighting' get_key model),(<'scaling' get_key model),(<number 'correct' get_key result),(<f4 (real 'correct' get_key result)%real #Train),<f4 'rmse' get_key result
        lines =. lines,<',' join fields
    end.
    lines
)
prediction_lines =: 3 : 0
    lines =. <'id,label,vote_share,estimate'
    for_index. i.#Test do.
        row =. index{::Test
        prediction =. index{::TestPredictions
        fields =. (<'id' get_key row),(<'label' get_key prediction),(<f4 'share' get_key prediction),<f4 index{TestEstimates
        lines =. lines,<',' join fields
    end.
    lines
)
main =: 3 : 0
    read_dataset ''
    run_experiment ''
    1!:5 <'output'
    'cv_grid.csv' write_lines grid_lines ''
    'predictions.csv' write_lines prediction_lines ''
    'metrics.txt' write_lines metrics_lines ''
    'learning_curve.csv' write_lines learning_curve_lines ''
    'prototypes.txt' write_lines prototypes_lines ''
    i.0
)
main ''
