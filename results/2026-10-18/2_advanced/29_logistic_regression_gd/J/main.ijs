split =: 4 : '<;._1 x,y'
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do.
            result =. result,x
        end.
        result =. result,i{::y
    end.
    result
)
num =: 3 : 'x: 0".y'
decimal =: 3 : '0".''_''(I.y=''-'')}y'
intdiv =: 4 : '<.(x: x)%x: y'
load 'logistic.ijs'
load 'dataset.ijs'
load 'optimizers.ijs'
load 'softmax.ijs'
load 'metrics.ijs'
text =: 3 : 0
    if. 2=3!:0 y do.
        y return.
    end.
    result =. ":y
    '-'(I.result='_')}result
)
line =: 3 : ''' ''join text&.>y'
integers =: 3 : ''' ''join text&.><"0 y'
reals =: 4 : 0
    result =. 0$a:
    for_value. y do.
        result =. result,<x fixed value
    end.
    ' 'join result
)
vector_length =: 3 : '%:ordered_sum *:y'
predict =: 4 : 'y>:x'
count_equal =: 4 : '+/x=y'
model_probabilities =: 4 : 0
    result =. i.0
    for_vector. y do.
        result =. result,probability x score vector
    end.
    result
)
inverse =: 3 : 0
    size =. #y
    lower =. cholesky y
    result =. (size,size)$0.0
    for_k. i.size do.
        unit =. 1 k}size$0.0
        column =. lower solve unit
        for_j. i.size do.
            result =. (j{column)(<j,k)}result
        end.
    end.
    result
)
original_units =: 3 : 0
    'means deviations' =. Statistics
    scaled =. (}.y)%deviations
    shift =. ordered_sum scaled*means
    (({.y)-shift),scaled
)
data_vector =: 3 : 'Statistics standardize Tuples expanded_values y'
e_probabilities =: 0&{::
e_predictions =: 1&{::
e_loss =: 2&{::
e_correct =: 3&{::
e_auc =: 4&{::
evaluate =: 3 : 0
    'weights vectors targets' =. y
    probabilities =. weights model_probabilities vectors
    predictions =. Threshold predict probabilities
    value =. average_loss y
    correct =. predictions count_equal targets
    area =. probabilities auc targets
    (<probabilities),(<predictions),(<value),(<correct),<area
)
m_name =: 0&{::
m_checkpoints =: 1&{::
m_weights =: 2&{::
m_train =: 3&{::
m_test =: 4&{::
m_roc =: 5&{::
binary_model =: 3 : 0
    'name checkpoints' =. y
    weights =. final_weights checkpoints
    fitting =. evaluate (<weights),(<TrainVectors),<TrainTargets
    checking =. evaluate (<weights),(<TestVectors),<TestTargets
    points =. (e_probabilities checking)roc_points TestTargets
    (<name),(<checkpoints),(<weights),(<fitting),(<checking),<points
)
i_matrix =: 0&{::
i_probabilities =: 1&{::
i_leverages =: 2&{::
i_residuals =: 3&{::
i_distances =: 4&{::
i_edf =: 5&{::
i_deviance =: 6&{::
i_aic =: 7&{::
i_bic =: 8&{::
influence =: 3 : 0
    'weights vectors targets lambda' =. y
    matrix =. inverse hessian (<weights),(<vectors),<lambda
    probabilities =. leverages =. residuals =. distances =. i.0
    size =. #weights
    for_i. i.#vectors do.
        vector =. i{vectors
        pi =. probability weights score vector
        variance =. pi*1-pi
        quadratic =. 0.0
        for_j. i.size do.
            for_k. i.size do.
                quadratic =. quadratic+((j{vector)*((<j,k){matrix))*k{vector
            end.
        end.
        leverage =. (variance*quadratic)%#vectors
        pearson =. ((i{targets)-pi)%%:variance
        probabilities =. probabilities,pi
        leverages =. leverages,leverage
        residuals =. residuals,pearson%%:1-leverage
        distances =. distances,((pearson*pearson)*leverage)%(size*(*:1-leverage))
    end.
    edf =. ordered_sum leverages
    deviance =. (2.0*#vectors)*average_loss 3{.y
    aic =. deviance+2.0*edf
    bic =. deviance+(^.#vectors)*edf
    (<matrix),(<probabilities),(<leverages),(<residuals),(<distances),(<edf),(<deviance),(<aic),<bic
)
cv_lambda =: 0&{::
cv_folds =: 1&{::
cv_loss =: 2&{::
cv_probabilities =: 3&{::
cv_errors =: 4&{::
cross_validate =: 4 : 0
    lambda =. x
    count =. y
    losses =. probabilities =. N$0.0
    fold_losses =. i.0
    errors =. 0
    for_fold. i.5 do.
        fitting =. I.fold~:5|i.N
        checking =. I.fold=5|i.N
        statistics =. count compute_statistics fitting{TrainExpanded
        vectors =. statistics standardize"1 fitting{TrainExpanded
        targets =. fitting{TrainTargets
        weights =. final_weights newton_method (<vectors),(<targets),<lambda
        fold_total =. 0.0
        for_i. checking do.
            u =. weights score statistics standardize i{TrainExpanded
            value =. (i{TrainTargets)loss u
            pi =. probability u
            losses =. value i}losses
            probabilities =. pi i}probabilities
            fold_total =. fold_total+value
            errors =. errors+(pi>:Threshold)~:i{TrainTargets
        end.
        fold_losses =. fold_losses,fold_total%#checking
    end.
    value =. (ordered_sum losses)%N
    (<lambda),(<fold_losses),(<value),(<probabilities),<errors
)
term_lines =: 3 : 0
    weights =. y
    original =. original_units weights
    lines =. ,<'term intercept standardized ',(4 fixed {.weights),' original ',4 fixed {.original
    for_j. i.FeatureCount do.
        lines =. lines,<'term ',(j{::FeatureNames),' standardized ',(4 fixed (j+1){weights),' original ',4 fixed (j+1){original
    end.
    lines
)
features_part =: 3 : 0
    correlation =. (FeatureCount,FeatureCount)$0.0
    for_j. i.FeatureCount do.
        for_k. i.FeatureCount do.
            total =. ordered_sum ((j+1){"1 TrainVectors)*(k+1){"1 TrainVectors
            correlation =. (total%N-1)(<j,k)}correlation
        end.
    end.
    inflation =. inverse correlation
    'means deviations' =. Statistics
    lines =. (<line 'features';D;'degree';Degree;'expanded';FeatureCount),<'standardization'
    for_j. i.FeatureCount do.
        lines =. lines,<line (j{::FeatureNames);'mean';(6 fixed j{means);'sd';(6 fixed j{deviations);'vif';4 fixed (<j,j){inflation
    end.
    lines =. lines,<'correlation'
    for_row. correlation do.
        lines =. lines,<4 reals row
    end.
    lines
)
weight_parts =: 3 : 0
    parts =. ,<features_part 0
    newton_weights =. m_weights Newton
    for_model. Models do.
        model =. >model
        weights =. m_weights model
        lines =. ,<line 'model';(m_name model);'lambda';4 fixed SelectedLambda
        lines =. lines,term_lines weights
        lines =. lines,<'norm ',4 fixed vector_length }.weights
        if. -. 'newton'-:m_name model do.
            lines =. lines,<'distance_to_newton ',6 fixed vector_length weights-newton_weights
        end.
        parts =. parts,<lines
    end.
    lines =. ,<'coefficients newton lambda ',4 fixed SelectedLambda
    names =. (<'intercept'),FeatureNames
    matrix =. i_matrix Influence
    for_j. i.#names do.
        weight =. j{newton_weights
        se =. %:((<j,j){matrix)%N
        lines =. lines,<line (j{::names);'weight';(4 fixed weight);'se';(4 fixed se);'z';(4 fixed weight%se);'lower';(4 fixed weight-1.96*se);'upper';(4 fixed weight+1.96*se);'odds_ratio';4 fixed ^weight
    end.
    parts =. parts,<lines
    lines =. ,<'model softmax lambda ',4 fixed SoftmaxLambda
    for_k. i.Classes do.
        lines =. lines,(<'class ',":k),term_lines k{SoftWeights
    end.
    parts,<lines
)
loss_trace =: 3 : 0
    lines =. ,<'optimizer,iteration,loss,gradient_norm,test_loss'
    for_model. Models do.
        model =. >model
        for_checkpoint. m_checkpoints model do.
            checkpoint =. >checkpoint
            weights =. cp_weights checkpoint
            args =. (<weights),(<TrainVectors),(<TrainTargets),<SelectedLambda
            value =. objective args
            slope =. vector_length gradient args
            test_loss =. average_loss (<weights),(<TestVectors),<TestTargets
            fields =. (m_name model);(cp_iteration checkpoint);(6 fixed value);(6 fixed slope);6 fixed test_loss
            lines =. lines,<','join text&.>fields
        end.
    end.
    for_checkpoint. SoftCheckpoints do.
        checkpoint =. >checkpoint
        weights =. cp_weights checkpoint
        args =. (<weights),(<TrainVectors),(<TrainLabels),<SoftmaxLambda
        value =. sm_objective args
        slope =. vector_length ,sm_gradient args
        test_loss =. sm_average_loss (<weights),(<TestVectors),<TestLabels
        fields =. 'softmax';(cp_iteration checkpoint);(6 fixed value);(6 fixed slope);6 fixed test_loss
        lines =. lines,<','join text&.>fields
    end.
    lines
)
prediction_lines =: 3 : 0
    lines =. ,<'id,model,probability,predicted,actual'
    for_model. Models do.
        model =. >model
        checking =. m_test model
        for_i. i.M do.
            fields =. (i{::TestIds);(m_name model);(6 fixed i{e_probabilities checking);(i{e_predictions checking);i{TestTargets
            lines =. lines,<','join text&.>fields
        end.
    end.
    for_i. i.M do.
        predicted =. i{SoftPredictions
        fields =. (i{::TestIds);'softmax';(6 fixed (<i,predicted){SoftProbabilities);predicted;i{TestLabels
        lines =. lines,<','join text&.>fields
    end.
    lines
)
roc_lines =: 3 : 0
    positives =. +/TestTargets
    negatives =. M-positives
    lines =. ,<'model,threshold,tpr,fpr,precision'
    for_model. Models do.
        model =. >model
        lines =. lines,<(m_name model),',inf,0.0000,0.0000,-'
        for_point. m_roc model do.
            point =. >point
            tp =. rp_tp point
            fp =. rp_fp point
            fields =. (m_name model);(6 fixed rp_threshold point);(tp ratio positives);(fp ratio negatives);tp ratio tp+fp
            lines =. lines,<','join fields
        end.
    end.
    lines
)
data_part =: 3 : 0
    train_counts =. +/"1 (i.Classes)=/TrainLabels
    test_counts =. +/"1 (i.Classes)=/TestLabels
    (<line 'data';'train';N;'test';M;'base_features';D;'degree';Degree;'features';FeatureCount),(<line 'binary';'positive_class';Positive;'train';((": +/TrainTargets),'/',":N);'test';(": +/TestTargets),'/',":M),<line 'classes';Classes;'train';(integers train_counts);'test';integers test_counts
)
cross_validation_part =: 3 : 0
    lines =. ,<'cross_validation folds 5 newton_iterations 10'
    for_result. Validations do.
        result =. >result
        errors =. (":cv_errors result),'/',":N
        lines =. lines,<line 'lambda';(4 fixed cv_lambda result);'fold_loss';(6 reals cv_folds result);'cv_loss';(6 fixed cv_loss result);'errors';errors
    end.
    lines =. lines,<line 'selected';'lambda';(4 fixed SelectedLambda);'cv_loss';(6 fixed cv_loss BestValidation);'se';(6 fixed SelectionSE);'lambda_1se';4 fixed OneSE
    probabilities =. cv_probabilities BestValidation
    'tp fp tn fn' =. (Threshold predict probabilities)confusion TrainTargets
    lines,<line 'out_of_fold';'tp';tp;'fp';fp;'tn';tn;'fn';fn;'accuracy';((tp+tn)ratio N);'auc';fraction probabilities auc TrainTargets
)
lambda_path =: 3 : 0
    lines =. ,<'lambda_path'
    for_lambda. Lambdas do.
        weights =. final_weights newton_method (<TrainVectors),(<TrainTargets),<lambda
        fitting =. evaluate (<weights),(<TrainVectors),<TrainTargets
        checking =. evaluate (<weights),(<TestVectors),<TestTargets
        value =. objective (<weights),(<TrainVectors),(<TrainTargets),<lambda
        lines =. lines,<line 'lambda';(4 fixed lambda);'objective';(6 fixed value);'train_loss';(6 fixed e_loss fitting);'test_loss';(6 fixed e_loss checking);'train_accuracy';((e_correct fitting)ratio N);'test_accuracy';((e_correct checking)ratio M);'norm';4 fixed vector_length }.weights
    end.
    lines
)
degree_part =: 3 : 0
    lines =. ,<'degrees lambda ',4 fixed SelectedLambda
    for_degree. 1+i.Degree do.
        count =. +/degree>:#&>Tuples
        train_vectors =. (i.count+1){"1 TrainVectors
        test_vectors =. (i.count+1){"1 TestVectors
        weights =. final_weights newton_method (<train_vectors),(<TrainTargets),<SelectedLambda
        validation =. SelectedLambda cross_validate count
        fitting =. evaluate (<weights),(<train_vectors),<TrainTargets
        checking =. evaluate (<weights),(<test_vectors),<TestTargets
        measures =. influence (<weights),(<train_vectors),(<TrainTargets),<SelectedLambda
        lines =. lines,<line 'degree';degree;'features';count;'cv_loss';(6 fixed cv_loss validation);'train_loss';(6 fixed e_loss fitting);'test_loss';(6 fixed e_loss checking);'test_accuracy';((e_correct checking)ratio M);'auc';(fraction e_auc checking);'edf';(4 fixed i_edf measures);'aic';(4 fixed i_aic measures);'bic';4 fixed i_bic measures
    end.
    lines
)
learning_curve =: 3 : 0
    lines =. ,<'learning_curve lambda ',4 fixed SelectedLambda
    for_step. 1+i.4 do.
        size =. (step*N)intdiv 4
        rows =. size{.TrainExpanded
        statistics =. FeatureCount compute_statistics rows
        train_vectors =. statistics standardize"1 rows
        test_vectors =. statistics standardize"1 TestExpanded
        targets =. size{.TrainTargets
        weights =. final_weights newton_method (<train_vectors),(<targets),<SelectedLambda
        fitting =. evaluate (<weights),(<train_vectors),<targets
        checking =. evaluate (<weights),(<test_vectors),<TestTargets
        lines =. lines,<line 'size';size;'train_loss';(6 fixed e_loss fitting);'test_loss';(6 fixed e_loss checking);'test_accuracy';((e_correct checking)ratio M);'auc';fraction e_auc checking
    end.
    lines
)
bin_index =: 3 : '9<.<.10*y'
fill_bins =: 4 : 0
    bins =. 10$<0;0.0;0
    for_i. i.#x do.
        index =. bin_index i{x
        'count total hits' =. index{::bins
        bins =. (<(<count+1),(<total+i{x),<hits+i{y)index}bins
    end.
    bins
)
bin_lines =: 3 : 0
    'bins mean_label rate_label' =. y
    lines =. 0$a:
    for_index. i.10 do.
        'count total hits' =. index{::bins
        mean =. '-'
        if. count do.
            mean =. 4 fixed total%count
        end.
        range =. (1 fixed index%10.0),'-',1 fixed (index+1)%10.0
        lines =. lines,<line 'bin';range;'count';count;mean_label;mean;rate_label;hits ratio count
    end.
    lines
)
calibration_error =: 4 : 0
    value =. 0.0
    for_group. x do.
        'count total hits' =. >group
        if. count do.
            value =. value+|total-hits
        end.
    end.
    value%y
)
point_cost =: 4 : '(CostFP*rp_fp x)+CostFN*y-rp_tp x'
binary_part =: 3 : 0
    model =. y
    checking =. m_test model
    probabilities =. e_probabilities checking
    positives =. +/TestTargets
    negatives =. M-positives
    'tp fp tn fn' =. (e_predictions checking)confusion TestTargets
    brier =. (ordered_sum *:probabilities-TestTargets)%M
    points =. m_roc model
    youden =. best_f1 =. cheapest =. 0{::points
    ap =. 0.0
    previous =. 0
    for_point. points do.
        point =. >point
        left =. (negatives*rp_tp point)-positives*rp_fp point
        right =. (negatives*rp_tp youden)-positives*rp_fp youden
        if. left>right do.
            youden =. point
        end.
        left =. (rp_tp point)*(positives+(rp_tp best_f1)+rp_fp best_f1)
        right =. (rp_tp best_f1)*(positives+(rp_tp point)+rp_fp point)
        if. left>right do.
            best_f1 =. point
        end.
        if. (point point_cost positives)<cheapest point_cost positives do.
            cheapest =. point
        end.
        ap =. ap+(((rp_tp point)-previous)*rp_tp point)%((rp_tp point)+rp_fp point)
        previous =. rp_tp point
    end.
    lines =. ,<line 'model';(m_name model);'lambda';4 fixed SelectedLambda
    correct =. e_correct m_train model
    lines =. lines,<line 'train';'correct';((":correct),'/',":N);'accuracy';correct ratio N
    lines =. lines,<line 'test';'tp';tp;'fp';fp;'tn';tn;'fn';fn
    lines =. lines,<line 'test';'accuracy';((tp+tn)ratio M);'precision';(tp ratio tp+fp);'recall';(tp ratio tp+fn);'specificity';(tn ratio tn+fp);'f1';(2*tp)ratio (2*tp)+fp+fn
    lines =. lines,<line 'log_loss';(6 fixed e_loss checking);'brier';6 fixed brier
    lines =. lines,<line 'auc';(fraction e_auc checking);'average_precision';4 fixed ap%positives
    yp =. rp_tp youden
    yf =. rp_fp youden
    lines =. lines,<line 'youden';'threshold';(6 fixed rp_threshold youden);'tpr';(yp ratio positives);'fpr';(yf ratio negatives);'j';((yp*negatives)-yf*positives)ratio positives*negatives
    bp =. rp_tp best_f1
    bf =. rp_fp best_f1
    lines =. lines,<line 'best_f1';'threshold';(6 fixed rp_threshold best_f1);'precision';(bp ratio bp+bf);'recall';(bp ratio positives);'f1';(2*bp)ratio positives+bp+bf
    lines =. lines,<line 'min_cost';'threshold';(6 fixed rp_threshold cheapest);'cost';(cheapest point_cost positives);'fp';(rp_fp cheapest);'fn';positives-rp_tp cheapest
    bins =. probabilities fill_bins TestTargets
    lines =. lines,(<'calibration'),bin_lines (<bins),(<'mean_probability'),<'positive_rate'
    mce =. statistic =. 0.0
    groups =. 0
    for_group. bins do.
        'count total hits' =. >group
        if. count=0 do.
            continue.
        end.
        groups =. groups+1
        mce =. mce>.|(total%count)-hits%count
        statistic =. statistic+(*:hits-total)%(total*1-total%count)
    end.
    lines =. lines,<line 'ece';(4 fixed bins calibration_error M);'mce';(4 fixed mce);'hosmer_lemeshow';(4 fixed statistic);'groups';groups
    lines =. lines,<'gains'
    order =. \:probabilities
    for_decile. 1+i.10 do.
        rows =. (decile*M)intdiv 10
        hits =. +/(rows{.order){TestTargets
        lines =. lines,<line 'decile';decile;'rows';rows;'positives';hits;'gain';(hits ratio positives);'lift';(hits*M)ratio rows*positives
    end.
    lines
)
comparison_part =: 3 : 0
    lines =. 0$a:
    for_pair. 3 2$0 1 0 2 1 2 do.
        'a b' =. pair
        first =. a{::Models
        second =. b{::Models
        p =. e_predictions m_test first
        q =. e_predictions m_test second
        same =. +/p=q
        only_first =. +/(p=TestTargets)*.q~:TestTargets
        only_second =. +/(q=TestTargets)*.p~:TestTargets
        gap =. (|only_first-only_second)-1
        lines =. lines,<line 'agreement';(m_name first);(m_name second);'same';((":same),'/',":M);'only_first';only_first;'only_second';only_second;'mcnemar';(gap*gap)ratio only_first+only_second
    end.
    lines
)
slope =: 3 : 0
    'original values base' =. y
    total =. 0.0
    for_j. i.FeatureCount do.
        indices =. j{::Tuples
        occurrences =. +/base=indices
        if. occurrences=0 do.
            continue.
        end.
        removed =. 0
        product =. 1.0
        for_index. indices do.
            if. (index=base)*.-.removed do.
                removed =. 1
            else.
                product =. product*index{values
            end.
        end.
        total =. total+((j+1){original)*(occurrences*product)
    end.
    total
)
bootstrap_line =: 3 : 0
    state =. BootstrapSeed
    samples =. 0 2$0
    values =. i.0
    scores =. e_probabilities m_test Newton
    for_sample. i.BootstrapCount do.
        picks =. i.0
        for_j. i.M do.
            state =. rng_draw state
            picks =. picks,M|state
        end.
        area =. (picks{scores)auc picks{TestTargets
        samples =. samples,area
        values =. values,({.area)%{:area
    end.
    mean =. (ordered_sum values)%BootstrapCount
    deviation =. %:(ordered_sum *:values-mean)%BootstrapCount-1
    order =. /:values
    tail =. BootstrapCount intdiv 40
    lower =. (tail{order){samples
    upper =. (((BootstrapCount-tail)-1){order){samples
    line 'bootstrap';'resamples';BootstrapCount;'seed';BootstrapSeed;'auc_mean';(4 fixed mean);'auc_sd';(4 fixed deviation);'lower';(fraction lower);'upper';fraction upper
)
diagnostics_part =: 3 : 0
    weights =. m_weights Newton
    fitting =. m_train Newton
    checking =. m_test Newton
    base_rate =. (+/TrainTargets)%N
    null_loss =. -((base_rate*^.base_rate)+(1-base_rate)*^.1-base_rate)
    lines =. ,<'diagnostics newton lambda ',4 fixed SelectedLambda
    lines =. lines,<line 'fit';'null_loss';(6 fixed null_loss);'train_loss';(6 fixed e_loss fitting);'mcfadden_r2';(4 fixed 1-(e_loss fitting)%null_loss);'deviance';(4 fixed i_deviance Influence);'edf';(4 fixed i_edf Influence);'aic';(4 fixed i_aic Influence);'bic';4 fixed i_bic Influence
    probabilities =. i_probabilities Influence
    order =. /:probabilities
    statistic =. 0.0
    groups =. 0$a:
    for_group. 1+i.10 do.
        first =. ((group-1)*N)intdiv 10
        last =. (group*N)intdiv 10
        members =. (last-first){.first}.order
        observed =. +/members{TrainTargets
        expected =. ordered_sum members{probabilities
        statistic =. statistic+(*:observed-expected)%(expected*1-expected%#members)
        groups =. groups,<line 'group';group;'rows';(#members);'observed';observed;'expected';4 fixed expected
    end.
    lines =. lines,(<line 'hosmer_lemeshow_train';'groups';10;'statistic';4 fixed statistic),groups,<'newton_iterations'
    checkpoints =. m_checkpoints Newton
    for_iteration. 1+i.10 do.
        previous_weights =. cp_weights (iteration-1){::checkpoints
        args =. (<previous_weights),(<TrainVectors),(<TrainTargets),<SelectedLambda
        'direction step' =. newton_direction args
        decrease =. (ordered_sum direction*step)%2.0
        lines =. lines,<line 'iteration';iteration;'objective';(6 fixed objective args);'gradient_norm';(6 fixed vector_length direction);'step_norm';(6 fixed vector_length step);'predicted_decrease';6 fixed decrease
    end.
    original =. original_units weights
    centre =. probability weights score data_vector MeanValues
    for_base. i.D do.
        value =. 0.0
        for_i. i.N do.
            pi =. i{probabilities
            slope_value =. slope (<original),(<i{TrainValues),<base
            value =. value+((pi*1-pi)*slope_value)
        end.
        at_mean =. (centre*1-centre)*slope (<original),(<MeanValues),<base
        lines =. lines,<line 'marginal';(base{::Names);'average';(4 fixed value%N);'at_mean';4 fixed at_mean
    end.
    test_scores =. e_probabilities checking
    for_cut. 1+i.9 do.
        'tp fp tn fn' =. ((cut%10.0)predict test_scores)confusion TestTargets
        lines =. lines,<line ('cut 0.',":cut);'positive';(tp+fp);'tp';tp;'fp';fp;'precision';(tp ratio tp+fp);'recall';(tp ratio tp+fn);'accuracy';(tp+tn)ratio M
    end.
    wrong =. I.(e_predictions checking)~:TestTargets
    distances =. |Threshold-test_scores
    wrong =. (\:wrong{distances){wrong
    for_i. (5<.#wrong){.wrong do.
        lines =. lines,<line 'error';(i{::TestIds);'actual';(i{TestTargets);'probability';6 fixed i{test_scores
    end.
    lines =. lines,<bootstrap_line 0
    large =. +/2<|i_residuals Influence
    lines =. lines,<line 'influence';'effective_parameters';(4 fixed i_edf Influence);'large_residuals';large
    order =. \:i_distances Influence
    for_i. (5<.N){.order do.
        lines =. lines,<line 'cook';(i{::TrainIds);'actual';(i{TrainTargets);'probability';(4 fixed i{i_probabilities Influence);'leverage';(4 fixed i{i_leverages Influence);'residual';(4 fixed i{i_residuals Influence);'distance';4 fixed i{i_distances Influence
    end.
    lines
)
softmax_correct =: 3 : 0
    predictions =. i.0
    for_vector. y do.
        predictions =. predictions,sm_class SoftWeights sm_probabilities vector
    end.
    predictions count_equal TestLabels
)
importance_part =: 3 : 0
    weights =. m_weights Newton
    checking =. m_test Newton
    base_loss =. e_loss checking
    base_area =. e_auc checking
    base_correct =. SoftPredictions count_equal TestLabels
    lines =. (<line 'importance';'repeats';PermutationCount;'seed';PermutationSeed),<line 'baseline';'log_loss';(6 fixed base_loss);'auc';(fraction base_area);'softmax_accuracy';base_correct ratio M
    state =. PermutationSeed
    for_base. i.D do.
        losses =. i.0
        auc_total =. correct_total =. 0
        for_replicate. i.PermutationCount do.
            'order state' =. shuffle (<i.M),<state
            vectors =. (0,FeatureCount+1)$0.0
            for_i. i.M do.
                values =. i{TestValues
                values =. ((<(i{order),base){TestValues)base}values
                vectors =. vectors,data_vector values
            end.
            losses =. losses,average_loss (<weights),(<vectors),<TestTargets
            area =. (weights model_probabilities vectors)auc TestTargets
            auc_total =. auc_total+{.area
            correct_total =. correct_total+softmax_correct vectors
        end.
        increase =. ((ordered_sum losses)%PermutationCount)-base_loss
        area =. auc_total,PermutationCount*{:base_area
        lines =. lines,<line 'feature';(base{::Names);'log_loss_increase';(6 fixed increase);'auc';(fraction area);'softmax_accuracy';correct_total ratio PermutationCount*M
    end.
    lines
)
profile_part =: 3 : 0
    weights =. m_weights Newton
    lines =. ,<'profiles'
    for_base. i.D do.
        low =. <./base{"1 TrainValues
        high =. >./base{"1 TrainValues
        for_step. i.5 do.
            value =. low+((high-low)*step)%4.0
            values =. value base}MeanValues
            vector =. data_vector values
            pi =. probability weights score vector
            probabilities =. SoftWeights sm_probabilities vector
            lines =. lines,<line 'profile';(base{::Names);'value';(4 fixed value);'newton';(4 fixed pi);'softmax';4 reals probabilities
        end.
    end.
    lines
)
softmax_part =: 3 : 0
    table =. (Classes,Classes)$0
    for_i. i.M do.
        actual =. i{TestLabels
        predicted =. i{SoftPredictions
        table =. (>:(<actual,predicted){table)(<actual,predicted)}table
    end.
    rows =. +/"1 table
    columns =. +/table
    lines =. (<line 'softmax';'classes';Classes;'lambda';(4 fixed SoftmaxLambda);'iterations';SoftmaxIterations),<'confusion'
    for_row. table do.
        lines =. lines,<integers row
    end.
    diagonal =. chance =. 0
    for_k. i.Classes do.
        scores =. k{"1 SoftProbabilities
        targets =. k=TestLabels
        hits =. (<k,k){table
        lines =. lines,<line 'class';k;'precision';(hits ratio k{columns);'recall';(hits ratio k{rows);'f1';((2*hits)ratio (k{columns)+k{rows);'auc';fraction scores auc targets
        diagonal =. diagonal+hits
        chance =. chance+(k{rows)*k{columns
    end.
    lines =. lines,<line 'accuracy';(diagonal ratio M);'kappa';((M*diagonal)-chance)ratio (M*M)-chance
    value =. sm_average_loss (<SoftWeights),(<TestVectors),<TestLabels
    squares =. confidences =. hits =. i.0
    for_i. i.M do.
        probabilities =. i{SoftProbabilities
        targets =. (i{TestLabels)=i.Classes
        squares =. squares,ordered_sum *:probabilities-targets
        confidences =. confidences,(i{SoftPredictions){probabilities
        hits =. hits,(i{SoftPredictions)=i{TestLabels
    end.
    brier =. (ordered_sum squares)%M
    lines =. lines,<line 'log_loss';(6 fixed value);'brier';6 fixed brier
    binary_scores =. Positive{"1 SoftProbabilities
    binary_loss =. 0.0
    for_i. i.M do.
        q =. i{binary_scores
        if. 0=i{TestTargets do.
            q =. 1-q
        end.
        binary_loss =. binary_loss-^.q
    end.
    predictions =. Threshold predict binary_scores
    correct =. predictions count_equal TestTargets
    agreement =. predictions count_equal e_predictions m_test Newton
    lines =. lines,<line 'binary_view';'positive_class';Positive;'auc';(fraction binary_scores auc TestTargets);'log_loss';(6 fixed binary_loss%M);'accuracy';(correct ratio M);'agreement_with_newton';(":agreement),'/',":M
    bins =. confidences fill_bins hits
    lines =. lines,(<'confidence'),bin_lines (<bins),(<'mean_confidence'),<'accuracy'
    lines,<line 'ece';4 fixed bins calibration_error M
)
one_vs_rest =: 3 : 0
    lines =. ,<'one_vs_rest lambda ',(4 fixed SoftmaxLambda),' newton_iterations 10'
    probabilities =. (0,M)$0.0
    for_k. i.Classes do.
        targets =. k=TrainLabels
        test_targets =. k=TestLabels
        weights =. final_weights newton_method (<TrainVectors),(<targets),<SoftmaxLambda
        checking =. evaluate (<weights),(<TestVectors),<test_targets
        value =. objective (<weights),(<TrainVectors),(<targets),<SoftmaxLambda
        probabilities =. probabilities,e_probabilities checking
        lines =. lines,<line 'class';k;'objective';(6 fixed value);'auc';fraction e_auc checking
    end.
    predictions =. sm_class"1 |:probabilities
    correct =. predictions count_equal TestLabels
    agreement =. predictions count_equal SoftPredictions
    lines,<line 'accuracy';(correct ratio M);'agreement_with_softmax';(":agreement),'/',":M
)
map_part =: 3 : 0
    low_x =. <./0{"1 TrainValues
    high_x =. >./0{"1 TrainValues
    low_y =. <./1{"1 TrainValues
    high_y =. >./1{"1 TrainValues
    cells =. Classes$0
    class_rows =. probability_rows =. 0$a:
    weights =. m_weights Newton
    for_r. i.MapHeight do.
        class_row =. probability_row =. ''
        for_c. i.MapWidth do.
            horizontal =. low_x+((c+0.5)*(high_x-low_x))%MapWidth
            vertical =. high_y-((r+0.5)*(high_y-low_y))%MapHeight
            values =. (horizontal,vertical)0 1}MeanValues
            vector =. data_vector values
            predicted =. sm_class SoftWeights sm_probabilities vector
            cells =. (>:(predicted{cells))predicted}cells
            class_row =. class_row,":predicted
            probability_row =. probability_row,":bin_index probability weights score vector
        end.
        class_rows =. class_rows,<class_row
        probability_rows =. probability_rows,<probability_row
    end.
    (<line 'map';(0{::Names);(1{::Names);'width';MapWidth;'height';MapHeight),(<'softmax_classes'),class_rows,(<'cells ',integers cells),(<'newton_probability'),probability_rows
)
evaluation_parts =: 3 : 0
    parts =. (<data_part 0),(<cross_validation_part 0),(<lambda_path 0),(<degree_part 0),<learning_curve 0
    for_model. Models do.
        parts =. parts,<binary_part >model
    end.
    parts,(<comparison_part 0),(<diagnostics_part 0),(<importance_part 0),(<profile_part 0),(<softmax_part 0),(<one_vs_rest 0),<map_part 0
)
write_lines =: 4 : 0
    output =. ''
    for_value. y do.
        output =. output,(>value),LF
    end.
    output 1!:2 <'output/',x
)
write_parts =: 4 : 0
    lines =. 0$a:
    for_part. y do.
        if. #lines do.
            lines =. lines,<''
        end.
        lines =. lines,>part
    end.
    x write_lines lines
)
run =: 3 : 0
    'Names TrainIds TrainValues TrainLabels' =: read_examples 'input/train.csv'
    'test_names TestIds TestValues TestLabels' =: read_examples 'input/test.csv'
    read_settings 'input/params.txt'
    N =: #TrainIds
    M =: #TestIds
    D =: #Names
    Classes =: 1+>./TrainLabels
    Tuples =: D expansion_tuples Degree
    FeatureNames =: Names expanded_names Tuples
    FeatureCount =: #Tuples
    TrainExpanded =: Tuples expanded_values"1 TrainValues
    TestExpanded =: Tuples expanded_values"1 TestValues
    Statistics =: FeatureCount compute_statistics TrainExpanded
    TrainVectors =: Statistics standardize"1 TrainExpanded
    TestVectors =: Statistics standardize"1 TestExpanded
    TrainTargets =: Positive=TrainLabels
    TestTargets =: Positive=TestLabels
    MeanValues =: D{.0{::Statistics
    Validations =: 0$a:
    for_lambda. Lambdas do.
        Validations =: Validations,<lambda cross_validate FeatureCount
    end.
    BestValidation =: 0{::Validations
    for_result. Validations do.
        result =. >result
        if. (cv_loss result)<:cv_loss BestValidation do.
            BestValidation =: result
        end.
    end.
    SelectedLambda =: cv_lambda BestValidation
    mean =. (ordered_sum cv_folds BestValidation)%5.0
    spread =. ordered_sum *:(cv_folds BestValidation)-mean
    SelectionSE =: (%:spread%4.0)%%:5.0
    OneSE =: SelectedLambda
    for_result. Validations do.
        result =. >result
        if. (cv_loss result)<:(cv_loss BestValidation)+SelectionSE do.
            OneSE =: cv_lambda result
        end.
    end.
    gd =. gradient_descent (<TrainVectors),(<TrainTargets),(<SelectedLambda),(<GDRate),<GDIterations
    sgd =. stochastic_gradient_descent (<TrainVectors),(<TrainTargets),(<SelectedLambda),(<SGDRate),(<BatchSize),(<Epochs),<SGDSeed
    newton =. newton_method (<TrainVectors),(<TrainTargets),<SelectedLambda
    Models =: (<binary_model (<'gd'),<gd),(<binary_model (<'sgd'),<sgd),<binary_model (<'newton'),<newton
    Newton =: 2{::Models
    SoftCheckpoints =: sm_train (<TrainVectors),(<TrainLabels),(<Classes),(<SoftmaxLambda),(<SoftmaxRate),<SoftmaxIterations
    SoftWeights =: final_weights SoftCheckpoints
    SoftProbabilities =: (0,Classes)$0.0
    for_vector. TestVectors do.
        SoftProbabilities =: SoftProbabilities,SoftWeights sm_probabilities vector
    end.
    SoftPredictions =: sm_class"1 SoftProbabilities
    Influence =: influence (<m_weights Newton),(<TrainVectors),(<TrainTargets),<SelectedLambda
    try. 1!:5 <'output' catch. end.
    'weights.txt'write_parts weight_parts 0
    'loss_trace.csv'write_lines loss_trace 0
    'predictions.csv'write_lines prediction_lines 0
    'evaluation.txt'write_parts evaluation_parts 0
    'roc.csv'write_lines roc_lines 0
    i.0
)
run 0
