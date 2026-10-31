load 'dataset.ijs'
load 'linalg.ijs'
load 'gaussian_models.ijs'
load 'evaluation.ijs'
load 'plot.ijs'
ModelNames =: ;:'NB LDA QDA'
integers =: 3 : ''' ''join text&.>y'
feature_names =: 3 : ''' ''join y{Features'
default_spec =: 3 : 0
    (<y),(<AllFeatures),(<Training),(<p_prior Params),(<p_epsilon Params),<p_gamma Params
)
fit =: 3 : 'train_model (3{.y),(<ClassCount),3}.y'
fit_features =: 4 : 0
    spec =. (<y)1}default_spec x
    fit spec
)
row_predictions =: 4 : 0
    result =. i.0
    for_box. y do.
        result =. result,x predict row_values >box
    end.
    result
)
correct_count =: 4 : '+/x=y'
cv_predictions =: 0&{::
cv_folds =: 1&{::
cv_correct =: 2&{::
cv_with =: 3 : 0
    key =. y
    'name sequence epsilon gamma' =. key
    for_box. CVCache do.
        record =. >box
        if. key-:4{.record do.
            4}.record return.
        end.
    end.
    predicted =. N$0
    fold_correct =. i.0
    for_fold. i.p_folds Params do.
        retained =. Training#~Folds~:fold
        fitted =. fit (<name),(<sequence),(<retained),(<p_prior Params),(<epsilon),<gamma
        correct =. 0
        for_index. I.Folds=fold do.
            row =. index{::Training
            value =. fitted predict row_values row
            predicted =. value index}predicted
            correct =. correct+value=row_class row
        end.
        fold_correct =. fold_correct,correct
    end.
    result =. (<predicted),(<fold_correct),<+/fold_correct
    CVCache =: CVCache,<key,result
    result
)
cross_validate =: 4 : 'cv_with (<x),(<y),(<p_epsilon Params),<p_gamma Params'
confusion_lines =: 3 : 0
    result =. 0$a:
    for_category. i.ClassCount do.
        result =. result,<'confusion ',(category{::Classes),' ',integers category{y
    end.
    result
)
comparisons =: 3 : 0
    'title names predicted actual' =. y
    result =. <title
    for_first. i.(#names)-1 do.
        for_second. (first+1)+i.(#names)-(first+1) do.
            'b01 b10 chi significant' =. mcnemar (<actual),(<first{::predicted),<second{::predicted
            b01 =. <.b01
            b10 =. <.b10
            significance =. (<.significant){::'no';'yes'
            result =. result,<(first{::names),' ',(second{::names),' b01 ',(text b01),' b10 ',(text b10),' chi2 ',(real_text chi),' significant ',significance
        end.
    end.
    result
)
model_sections =: 3 : 0
    'nb lda qda' =. MainModels
    stats =. g_statistics nb
    means =. s_means stats
    counts =. s_counts stats
    sections =. 0$a:
    lines =. (<'features ',' 'join Features),(<'classes ',' 'join Classes),<'prior_mode ',p_prior Params
    for_category. i.ClassCount do.
        lines =. lines,<'class ',(category{::Classes),' letter ',(category{UpperLetters),' count ',(text category{counts),' prior ',(real_text category{g_priors nb),' mean ',reals category{means
    end.
    sections =. sections,<lines
    lines =. (<'model NB'),<'smoothing epsilon ',(real_text g_epsilon nb),' max_variance ',(real_text g_max_variance nb),' added ',real_text g_added nb
    for_category. i.ClassCount do.
        covariance =. category{g_covariances nb
        diagonal =. 0$0.0
        for_feature. i.D do.
            diagonal =. diagonal,(<feature,feature){covariance
        end.
        lines =. lines,<'class ',(category{::Classes),' variance ',(reals diagonal),' log_det ',real_text category{g_log_determinants nb
    end.
    sections =. sections,<lines
    factor =. 0{g_factors lda
    lines =. (<'model LDA'),<'log_det ',real_text 0{g_log_determinants lda
    for_row. 0{g_covariances lda do.
        lines =. lines,<'  ',reals row
    end.
    for_category. i.ClassCount do.
        mean =. category{g_means lda
        coefficients =. factor backward factor forward mean
        intercept =. (^.category{g_priors lda)-(mean dot coefficients)%2.0
        lines =. lines,<'class ',(category{::Classes),' intercept ',(real_text intercept),' coef ',reals coefficients
    end.
    sections =. sections,<lines
    lines =. <'model QDA gamma ',real_text g_gamma qda
    for_category. i.ClassCount do.
        covariance =. category{g_covariances qda
        'values vectors sweeps' =. jacobi covariance
        values =. \:~values
        condition =. ({.values)%{:values
        lines =. lines,<'class ',(category{::Classes),' log_det ',(real_text category{g_log_determinants qda),' eigenvalues ',(reals values),' condition ',real_text condition
        for_row. covariance do.
            lines =. lines,<'  ',reals row
        end.
    end.
    sections =. sections,<lines
    lines =. <'separation'
    for_first. i.ClassCount-1 do.
        for_second. (first+1)+i.ClassCount-(first+1) do.
            delta =. (first{means)-second{means
            mahalanobis =. %:factor quadratic delta
            average =. ((first{g_covariances qda)+second{g_covariances qda)%2.0
            average_factor =. cholesky average
            determinants =. g_log_determinants qda
            quadratic_term =. (average_factor quadratic delta)%8.0
            average_determinant =. ((first{determinants)+second{determinants)%2.0
            determinant_term =. ((log_determinant average_factor)-average_determinant)%2.0
            bhattacharyya =. quadratic_term+determinant_term
            lines =. lines,<(first{::Classes),' ',(second{::Classes),' mahalanobis ',(real_text mahalanobis),' bhattacharyya ',real_text bhattacharyya
        end.
    end.
    sections =. sections,<lines
    outliers =. 0 2$0.0
    for_index. i.N do.
        row =. index{::Training
        distance =. (row_class row){qda model_distances row_values row
        if. distance>p_theta Params do.
            outliers =. outliers,distance,index
        end.
    end.
    order =. /:(-0{"1 outliers),.1{"1 outliers
    lines =. <'outliers threshold ',real_text p_theta Params
    for_record. order{outliers do.
        'distance index' =. record
        row =. (<.index){::Training
        lines =. lines,<(text row_id row),' ',(row_label row),' q ',real_text distance
    end.
    lines =. lines,<'count ',text #outliers
    sections,<lines
)
prediction_lines =: 3 : 0
    lines =. <'id,model,actual,predicted,decision,',','join Classes
    for_index. i.M do.
        row =. index{::Testing
        for_model. i.3 do.
            result =. index{::model{::Results
            fields =. (<text row_id row),(model{ModelNames),(<row_label row),((pred_class result){Classes),((pred_decision result){Classes),real_text&.>pred_posterior result
            lines =. lines,<','join fields
        end.
    end.
    lines
)
model_evaluation =: 3 : 0
    model =. y
    inferred =. model{::Results
    metrics =. measures (<TestActual),(<model{::MainPredictions),<ClassCount
    lines =. (<'model ',model{::ModelNames),confusion_lines m_matrix metrics
    lines =. lines,(<'accuracy ',fraction_text m_accuracy metrics),(<'balanced_accuracy ',fraction_text m_balanced metrics),<'kappa ',fraction_text m_kappa metrics
    for_category. i.ClassCount do.
        lines =. lines,<'class ',(category{::Classes),' support ',(text category{m_support metrics),' recall ',(fraction_text category{::m_recall metrics),' precision ',(fraction_text category{::m_precision metrics),' f1 ',fraction_text category{::m_f1 metrics
    end.
    loss =. 0.0
    errors =. 0$a:
    for_index. i.M do.
        row =. index{::Testing
        result =. index{::inferred
        loss =. loss+(row_class row){pred_log_posterior result
        if. (pred_class result)~:row_class row do.
            errors =. errors,<'error ',(text row_id row),' actual ',(row_label row),' predicted ',((pred_class result){::Classes),' confidence ',real_text pred_confidence result
        end.
    end.
    lines =. lines,(<'macro_f1 ',real_text m_macro metrics),(<'log_loss ',real_text (-loss)%M),(<'errors ',text #errors),errors
    edges =. 0.0,(p_calibration Params),1.0
    calibration_error =. 0.0
    for_bin. i.(#edges)-1 do.
        low =. bin{edges
        high =. (bin+1){edges
        count =. 0
        confidence =. 0.0
        correct =. 0
        for_index. i.M do.
            result =. index{::inferred
            value =. pred_confidence result
            if. (value>:low)*.((value<high)+.((bin=(#edges)-2)*.value=high)) do.
                count =. count+1
                confidence =. confidence+value
                correct =. correct+(pred_class result)=index{TestActual
            end.
        end.
        average =. '-'
        if. count do.
            average =. real_text confidence%count
        end.
        lines =. lines,<'bin ',(real_text low),' ',(real_text high),' count ',(text count),' confidence ',average,' accuracy ',correct ratio_text count
        calibration_error =. calibration_error+|correct-confidence
    end.
    lines =. lines,<'ece ',real_text calibration_error%M
    for_threshold. p_reject Params do.
        count =. 0
        correct =. 0
        for_index. i.M do.
            result =. index{::inferred
            if. (pred_confidence result)>:threshold do.
                count =. count+1
                correct =. correct+(pred_class result)=index{TestActual
            end.
        end.
        lines =. lines,<'reject ',(real_text threshold),' accepted ',(text count),' coverage ',(count ratio_text M),' accuracy ',correct ratio_text count
    end.
    lines
)
bootstrap_lines =: 3 : 0
    count =. p_bootstrap Params
    state =. p_seed Params
    resamples =. 0 3$0
    for_round. i.count do.
        correct =. 3$0
        for_sample. i.M do.
            state =. random_draw state
            index =. M|state
            for_model. i.3 do.
                if. (index{model{::MainPredictions)=index{TestActual do.
                    correct =. (1+model{correct)model}correct
                end.
            end.
        end.
        resamples =. resamples,correct
    end.
    lines =. <'bootstrap resamples ',(text count),' seed ',text p_seed Params
    offset =. <.(x:count)%40x
    for_model. i.3 do.
        counts =. model{"1 resamples
        ordered =. /:~counts
        mean =. ((0.0++/counts)%count)%M
        lines =. lines,<(model{::ModelNames),' mean ',(real_text mean),' interval ',((offset{ordered)ratio_text M),' ',(((count-offset)-1){ordered)ratio_text M
    end.
    for_first. i.2 do.
        for_second. (first+1)+i.3-(first+1) do.
            a =. first{"1 resamples
            b =. second{"1 resamples
            wins =. +/a>b
            ties =. +/a=b
            lines =. lines,<(first{::ModelNames),' ',(second{::ModelNames),' wins ',(text wins),' ties ',(text ties),' losses ',text (count-wins)-ties
        end.
    end.
    lines
)
subset_lines =: 3 : 0
    lines =. (<'cross_validation folds ',text p_folds Params),<'fold_sizes ',integers FoldSizes
    best_subset =. _1
    best_model =. _1
    best_correct =. _1
    best_size =. D+1
    subsets =. p_subsets Params
    for_subset_index. i.#subsets do.
        'name sequence' =. subset_index{::subsets
        lines =. lines,<'subset ',name,' features ',feature_names sequence
        for_model. i.3 do.
            result =. (model{::ModelNames)cross_validate sequence
            correct =. cv_correct result
            lines =. lines,<'  ',(model{::ModelNames),' fold_correct ',(integers cv_folds result),' correct ',(text correct),' accuracy ',correct ratio_text N
            if. (correct>best_correct)+.((correct=best_correct)*.(#sequence)<best_size) do.
                best_subset =. subset_index
                best_model =. model
                best_correct =. correct
                best_size =. #sequence
            end.
        end.
    end.
    'name sequence' =. best_subset{::subsets
    lines =. lines,<'best subset ',name,' model ',(best_model{::ModelNames),' correct ',(text best_correct),' accuracy ',best_correct ratio_text N
    fitted =. (best_model{::ModelNames)fit_features sequence
    correct =. TestActual correct_count fitted row_predictions Testing
    lines,<'refit_test correct ',(text correct),' accuracy ',correct ratio_text M
)
forward_sections =: 3 : 0
    sections =. 0$a:
    for_name_box. ModelNames do.
        name =. >name_box
        lines =. <'forward_selection model ',name
        selected =. i.0
        best_step =. 0
        best_correct =. _1
        for_step. 1+i.D do.
            added =. _1
            step_correct =. _1
            for_feature. AllFeatures-.selected do.
                result =. name cross_validate selected,feature
                if. (cv_correct result)>step_correct do.
                    added =. feature
                    step_correct =. cv_correct result
                end.
            end.
            selected =. selected,added
            lines =. lines,<'step ',(text step),' add ',(added{::Features),' correct ',(text step_correct),' accuracy ',step_correct ratio_text N
            if. step_correct>best_correct do.
                best_step =. step
                best_correct =. step_correct
            end.
        end.
        lines =. lines,<'best_step ',(text best_step),' features ',feature_names best_step{.selected
        sections =. sections,<lines
    end.
    sections
)
tuning_lines =: 3 : 0
    'name values title' =. y
    lines =. <title
    best_value =. 0.0
    best_correct =. _1
    for_value. values do.
        epsilon =. p_epsilon Params
        gamma =. p_gamma Params
        if. name-:'NB' do.
            epsilon =. value
        else.
            gamma =. value
        end.
        result =. cv_with (<name),(<AllFeatures),(<epsilon),<gamma
        correct =. cv_correct result
        lines =. lines,<'value ',(real_text value),' correct ',(text correct),' accuracy ',correct ratio_text N
        if. correct>:best_correct do.
            best_value =. value
            best_correct =. correct
        end.
    end.
    spec =. default_spec name
    if. name-:'NB' do.
        spec =. (<best_value)4}spec
    else.
        spec =. (<best_value)5}spec
    end.
    fitted =. fit spec
    correct =. TestActual correct_count fitted row_predictions Testing
    lines,<'best ',(real_text best_value),' test correct ',(text correct),' accuracy ',correct ratio_text M
)
evaluation_sections =: 3 : 0
    sections =. <,<'test rows ',text M
    for_index. i.3 do.
        sections =. sections,<model_evaluation index
    end.
    ensemble =. i.0
    for_index. i.M do.
        posterior =. ClassCount$0.0
        for_category. i.ClassCount do.
            total =. 0.0
            for_model. i.3 do.
                result =. index{::model{::Results
                total =. total+category{pred_posterior result
            end.
            posterior =. (total%3.0)category}posterior
        end.
        ensemble =. ensemble,argmax posterior
    end.
    metrics =. measures (<TestActual),(<ensemble),<ClassCount
    lines =. (<'ensemble soft_vote'),<'accuracy ',(fraction_text m_accuracy metrics),' balanced_accuracy ',(fraction_text m_balanced metrics),' kappa ',fraction_text m_kappa metrics
    sections =. sections,<lines
    sections =. sections,<comparisons (<'mcnemar test'),(<ModelNames,<'ENSEMBLE'),(<MainPredictions,<ensemble),<TestActual
    lines =. <'costs'
    for_model. i.3 do.
        inferred =. model{::Results
        argmax_total =. 0.0
        decision_total =. 0.0
        changed =. 0
        correct =. 0
        for_index. i.M do.
            result =. index{::inferred
            actual =. index{TestActual
            predicted =. pred_class result
            decided =. pred_decision result
            argmax_total =. argmax_total+(<actual,predicted){Costs
            decision_total =. decision_total+(<actual,decided){Costs
            changed =. changed+predicted~:decided
            correct =. correct+actual=decided
        end.
        lines =. lines,<(model{::ModelNames),' argmax_total ',(real_text argmax_total),' decision_total ',(real_text decision_total),' changed ',(text changed),' decision_accuracy ',correct ratio_text M
    end.
    sections =. sections,<lines
    qda =. 2{::MainModels
    novel =. 0 3$0.0
    for_index. i.M do.
        distances =. qda model_distances row_values index{::Testing
        nearest =. argmin distances
        distance =. nearest{distances
        if. distance>p_theta Params do.
            novel =. novel,distance,index,nearest
        end.
    end.
    order =. /:(-0{"1 novel),.1{"1 novel
    lines =. <'novelty threshold ',real_text p_theta Params
    for_record. order{novel do.
        'distance index nearest' =. record
        row =. (<.index){::Testing
        lines =. lines,<(text row_id row),' nearest ',((<.nearest){::Classes),' q ',real_text distance
    end.
    sections =. sections,<lines,<'count ',text #novel
    sections =. sections,<bootstrap_lines 0
    alternative =. 'empirical'
    if. 'empirical'-:p_prior Params do.
        alternative =. 'uniform'
    end.
    lines =. <'prior_sensitivity alternative ',alternative
    for_model. i.3 do.
        spec =. (<alternative)3}default_spec model{::ModelNames
        fitted =. fit spec
        predicted =. fitted row_predictions Testing
        metrics =. measures (<TestActual),(<predicted),<ClassCount
        changed =. +/predicted~:model{::MainPredictions
        lines =. lines,<(model{::ModelNames),' accuracy ',(fraction_text m_accuracy metrics),' balanced_accuracy ',(fraction_text m_balanced metrics),' changed ',text changed
    end.
    sections =. sections,<lines
    lines =. <'learning_curve'
    for_size. p_curve Params do.
        retained =. 0$a:
        taken =. ClassCount$0
        for_box. Training do.
            row =. >box
            category =. row_class row
            if. (category{taken)<size do.
                retained =. retained,<row
                taken =. (1+category{taken)category}taken
            end.
        end.
        fields =. <'size ',(text size),' rows ',text #retained
        for_box. ModelNames do.
            name =. >box
            spec =. (<retained)2}default_spec name
            fitted =. fit spec
            correct =. TestActual correct_count fitted row_predictions Testing
            fields =. fields,<name,' ',correct ratio_text M
        end.
        lines =. lines,<' 'join fields
    end.
    sections =. sections,<lines
    sections =. sections,<subset_lines 0
    cv_predicted =. 0$a:
    for_box. ModelNames do.
        result =. (>box)cross_validate AllFeatures
        cv_predicted =. cv_predicted,<cv_predictions result
    end.
    sections =. sections,<comparisons (<'mcnemar cross_validation'),(<ModelNames),(<cv_predicted),<TrainActual
    for_model. i.3 do.
        metrics =. measures (<TrainActual),(<model{::cv_predicted),<ClassCount
        lines =. (<'cv_confusion model ',model{::ModelNames),confusion_lines m_matrix metrics
        lines =. lines,<'balanced_accuracy ',(fraction_text m_balanced metrics),' kappa ',fraction_text m_kappa metrics
        sections =. sections,<lines
    end.
    lines =. <'leave_one_out'
    for_box. ModelNames do.
        name =. >box
        correct =. 0
        for_excluded. i.N do.
            retained =. Training#~excluded~:i.N
            spec =. (<retained)2}default_spec name
            fitted =. fit spec
            row =. excluded{::Training
            correct =. correct+(fitted predict row_values row)=row_class row
        end.
        lines =. lines,<name,' correct ',(text correct),' accuracy ',correct ratio_text N
    end.
    sections =. sections,(<lines),forward_sections 0
    sections =. sections,<tuning_lines (<'NB'),(<p_smoothing Params),<'nb_smoothing_path'
    sections,<tuning_lines (<'QDA'),(<p_gammas Params),<'qda_gamma_path'
)
point_grid =: 3 : 0
    'points actual limits size' =. y
    'xmin xmax ymin ymax' =. limits
    'width height' =. size
    grid =. (height,width)$' '
    for_index. i.#points do.
        point =. index{points
        column =. cell (0{point),xmin,xmax,width
        row =. (height-1)-cell (1{point),ymin,ymax,height
        letter =. (index{actual){LowerLetters
        previous =. (<row,column){grid
        if. -.previous e.' ',letter do.
            letter =. '*'
        end.
        grid =. letter (<row,column)}grid
    end.
    grid
)
limits_of =: 3 : '(<./0{"1 y),(>./0{"1 y),(<./1{"1 y),>./1{"1 y'
boundary_sections =: 3 : 0
    'width height' =. p_map Params
    sections =. 0$a:
    for_pair. p_pairs Params do.
        'fx fy' =. pair
        points =. 0 2$0.0
        for_box. Training do.
            points =. points,pair{row_values >box
        end.
        limits =. limits_of points
        'xmin xmax ymin ymax' =. limits
        dx =. (xmax-xmin)%(width-1)
        dy =. (ymax-ymin)%(height-1)
        lines =. (<'pair ',(fx{::Features),' ',fy{::Features),<'x ',(fx{::Features),' ',(real_text xmin),' ',(real_text xmax),' y ',(fy{::Features),' ',(real_text ymin),' ',(real_text ymax),' grid ',(text width),'x',text height
        grids =. 0$a:
        for_name_box. ModelNames do.
            name =. >name_box
            fitted =. name fit_features pair
            correct =. TrainActual correct_count fitted row_predictions Training
            cv =. name cross_validate pair
            lines =. lines,<'model ',name,' train_accuracy ',(correct ratio_text N),' cv_accuracy ',(cv_correct cv)ratio_text N
            grid =. (height,width)$' '
            inferred =. 0$a:
            counts =. ClassCount$0
            for_row. i.height do.
                for_column. i.width do.
                    point =. (xmin+column*dx),ymax-row*dy
                    result =. fitted infer_vector (<point),<0 0$0.0
                    inferred =. inferred,<result
                    category =. pred_class result
                    grid =. (category{UpperLetters)(<row,column)}grid
                    counts =. (1+category{counts)category}counts
                end.
            end.
            grids =. grids,<inferred
            lines =. lines,frame grid
            fields =. <'cells'
            for_category. i.ClassCount do.
                fields =. fields,<(category{UpperLetters),' ',text category{counts
            end.
            lines =. lines,<' 'join fields
        end.
        agreement =. (height,width)$' '
        uncertainty =. agreement
        disagreements =. 0
        levels =. ' .:-=+*#%@'
        for_row. i.height do.
            for_column. i.width do.
                index =. (row*width)+column
                predicted =. i.0
                for_model. i.3 do.
                    result =. index{::model{::grids
                    predicted =. predicted,pred_class result
                end.
                distinct =. #~.predicted
                character =. '.'
                if. distinct>1 do.
                    character =. {.text distinct
                    disagreements =. disagreements+1
                end.
                agreement =. character (<row,column)}agreement
                result =. index{::2{::grids
                value =. (1.0-pred_confidence result)%(1.0-1.0%ClassCount)
                level =. 9<.<.10*value
                uncertainty =. (level{levels)(<row,column)}uncertainty
            end.
        end.
        lines =. lines,(<'agreement'),frame agreement
        lines =. lines,(<'disagreement_cells ',text disagreements),(<'uncertainty QDA'),frame uncertainty
        grid =. point_grid (<points),(<TrainActual),(<limits),<p_map Params
        lines =. lines,(<'points'),frame grid
        sections =. sections,<lines
    end.
    sections
)
project_points =: 3 : 0
    'points directions center' =. y
    result =. 0 2$0.0
    for_point. points do.
        projected =. 0$0.0
        for_direction. directions do.
            total =. 0.0
            for_feature. i.D do.
                total =. total+(feature{direction)*((feature{point)-feature{center)
            end.
            projected =. projected,total
        end.
        result =. result,projected
    end.
    result
)
nearest_correct =: 3 : 0
    'points actual centroids dimensions' =. y
    correct =. 0
    for_index. i.#points do.
        point =. index{points
        distances =. 0$0.0
        for_centroid. centroids do.
            delta =. (0{point)-0{centroid
            distance =. delta*delta
            if. dimensions=2 do.
                delta =. (1{point)-1{centroid
                distance =. distance+delta*delta
            end.
            distances =. distances,distance
        end.
        correct =. correct+(argmin distances)=index{actual
    end.
    correct
)
projection_sections =: 3 : 0
    nb =. 0{::MainModels
    lda =. 1{::MainModels
    stats =. g_statistics nb
    center =. s_center stats
    means =. s_means stats
    counts =. s_counts stats
    scatter =. s_scatter stats
    within =. zeros D
    between =. zeros D
    for_first. i.D do.
        for_second. i.D do.
            sw =. 0.0
            sb =. 0.0
            for_category. i.ClassCount do.
                sw =. sw+(<category,first,second){scatter
                a =. ((<category,first){means)-first{center
                b =. ((<category,second){means)-second{center
                sb =. sb+((category{counts)*a)*b
            end.
            within =. sw (<first,second)}within
            between =. sb (<first,second)}between
        end.
    end.
    f_values =. 0$0.0
    for_feature. i.D do.
        between_term =. ((<feature,feature){between)%(ClassCount-1)
        within_term =. ((<feature,feature){within)%(N-ClassCount)
        value =. between_term%within_term
        f_values =. f_values,value
    end.
    feature_order =. /:(-f_values),.i.D
    univariate =. <'univariate'
    for_rank. i.D do.
        feature =. rank{feature_order
        univariate =. univariate,<'rank ',(text rank+1),' ',(feature{::Features),' f ',(real_text feature{f_values),' between ',(real_text (<feature,feature){between),' within ',real_text (<feature,feature){within
    end.
    factor =. cholesky within
    transformed =. zeros D
    for_column. i.D do.
        values =. factor forward column{"1 between
        for_row. i.D do.
            transformed =. (row{values)(<row,column)}transformed
        end.
    end.
    whitened =. zeros D
    for_column. i.D do.
        values =. factor forward column{transformed
        for_row. i.D do.
            whitened =. (row{values)(<row,column)}whitened
        end.
    end.
    symmetric =. (whitened+|:whitened)%2.0
    'eigenvalues eigenvectors sweeps' =. jacobi symmetric
    eigen_order =. /:(-eigenvalues),.i.D
    total =. ordered_sum eigenvalues
    directions =. (0,D)$0.0
    for_dimension. i.2 do.
        vector =. (dimension{eigen_order){"1 eigenvectors
        vector =. factor backward vector
        norm =. %:vector dot vector
        vector =. vector%norm
        pivot =. argmax |vector
        if. 0>pivot{vector do.
            vector =. -vector
        end.
        directions =. directions,vector
    end.
    training_vectors =. >row_values&.>Training
    testing_vectors =. >row_values&.>Testing
    train_points =. project_points (<training_vectors),(<directions),<center
    test_points =. project_points (<testing_vectors),(<directions),<center
    centroids =. project_points (<means),(<directions),<center
    fisher =. (<'fisher features ',' 'join Features),(<'center ',reals center),(<'sweeps ',text sweeps),(<'eigenvalues ',reals eigen_order{eigenvalues),<'ratios ',reals (eigen_order{eigenvalues)%total
    pooled =. 0{g_covariances lda
    for_dimension. i.2 do.
        direction =. dimension{directions
        standardized =. 0$0.0
        for_feature. i.D do.
            standardized =. standardized,(feature{direction)*%:(<feature,feature){pooled
        end.
        fisher =. fisher,(<'direction ',(text dimension+1),' ',reals direction),<'standardized ',(text dimension+1),' ',reals standardized
    end.
    for_category. i.ClassCount do.
        spread =. 0$0.0
        for_dimension. i.2 do.
            subtotal =. 0.0
            for_index. I.TrainActual=category do.
                delta =. ((<index,dimension){train_points)-(<category,dimension){centroids
                subtotal =. subtotal+delta*delta
            end.
            spread =. spread,%:subtotal%category{counts
        end.
        fisher =. fisher,<'centroid ',(category{::Classes),' ',(reals category{centroids),' spread ',reals spread
    end.
    for_dimensions. 1 2 do.
        training_correct =. nearest_correct (<train_points),(<TrainActual),(<centroids),<dimensions
        testing_correct =. nearest_correct (<test_points),(<TestActual),(<centroids),<dimensions
        fisher =. fisher,<'nearest_centroid dims ',(text dimensions),' train ',(training_correct ratio_text N),' test ',testing_correct ratio_text M
    end.
    limits =. limits_of train_points
    'xmin xmax ymin ymax' =. limits
    'width height' =. p_plot Params
    grid =. point_grid (<train_points),(<TrainActual),(<limits),<p_plot Params
    for_category. i.ClassCount do.
        point =. category{centroids
        column =. cell (0{point),xmin,xmax,width
        row =. (height-1)-cell (1{point),ymin,ymax,height
        grid =. (category{UpperLetters)(<row,column)}grid
    end.
    scatter_plot =. (<'plot x ',(real_text xmin),' ',(real_text xmax),' y ',(real_text ymin),' ',(real_text ymax),' size ',(text width),'x',text height),frame grid
    (<univariate),(<fisher),<scatter_plot
)
run =: 3 : 0
    'Features Classes Training Testing Costs Params' =: read_inputs 0
    N =: #Training
    M =: #Testing
    D =: #Features
    ClassCount =: #Classes
    AllFeatures =: i.D
    TrainActual =: row_class&>Training
    TestActual =: row_class&>Testing
    LowerLetters =: ;{.&.>Classes
    UpperLetters =: ('abcdefghijklmnopqrstuvwxyz'i.LowerLetters){'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    Folds =: (p_folds Params)|row_id&>Training
    FoldSizes =: +/Folds=/i.p_folds Params
    CVCache =: 0$a:
    MainModels =: 0$a:
    Results =: 0$a:
    MainPredictions =: 0$a:
    for_box. ModelNames do.
        fitted =. fit default_spec >box
        MainModels =: MainModels,<fitted
        inferred =. 0$a:
        predicted =. i.0
        for_row_box. Testing do.
            result =. fitted infer (<row_values >row_box),<Costs
            inferred =. inferred,<result
            predicted =. predicted,pred_class result
        end.
        Results =: Results,<inferred
        MainPredictions =: MainPredictions,<predicted
    end.
    try.
        1!:5 <'output'
    catch.
    end.
    'models.txt'save_lines join_sections model_sections 0
    'predictions.csv'save_lines prediction_lines 0
    'evaluation.txt'save_lines join_sections evaluation_sections 0
    'boundaries.txt'save_lines join_sections boundary_sections 0
    'projection.txt'save_lines join_sections projection_sections 0
    0
)
run 0
