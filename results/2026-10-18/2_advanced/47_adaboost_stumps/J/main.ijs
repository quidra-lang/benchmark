load 'dataset.ijs'
load 'stumps.ijs'
load 'adaboost.ijs'
load 'variants.ijs'
load 'evaluation.ijs'
integer =: 3 : 0
    result =. ":<.y
    '-'(I.result='_')}result
)
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
integers =: 3 : ''' ''join integer&.>y'
reals =: 3 : ''' ''join real_text&.>y'
random_draw =: 3 : 0
    RandomState =: 2147483647x|48271x*RandomState
    RandomState
)
train_variant =: 3 : 0
    'variant rows labels' =. y
    select. variant
    case. 'discrete' do.
        train_discrete (<rows),(<labels),(<Rounds),(<1.0),<i.0
    case. 'real' do.
        train_real (<rows),(<labels),(<Rounds),(<Bins),(<Smoothing),<Convergence
    case. 'gentle' do.
        train_gentle (<rows),(<labels),<Rounds
    case. 'logit' do.
        train_logit (<rows),(<labels),(<Rounds),<Clip
    end.
)
magnitude =: 3 : '>./|stump_values round_stump y'
row_score =: 4 : 0
    result =. 0.0
    for_record. x do.
        result =. result+(round_stump >record)stump_output y
    end.
    result
)
score_rows =: 4 : 0
    result =. i.0
    for_row. y do.
        result =. result,x row_score row
    end.
    result
)
error_count =: 4 : '+/x~:prediction y'
calc_loss =: 3 : 0
    'labels values logit' =. y
    total =. 0.0
    for_i. i.#labels do.
        if. logit do.
            total =. total+^.1.0+^(_2.0*i{labels)*i{values
        else.
            total =. total+^(-i{labels)*i{values
        end.
    end.
    total%#labels
)
first_rounds =: 4 : '(x<.#y){.y'
cross_validation =: 3 : 0
    folds =. 0$a:
    errors =. Rounds$0
    for_f. i.Folds do.
        validation =. I.f=Folds|i.#TrainX
        train_count =. (#TrainX)-#validation
        weights =. (#TrainX)$1.0%train_count
        weights =. 0.0 validation}weights
        model =. train_discrete (<TrainX),(<TrainY),(<Rounds),(<1.0),<weights
        rounds =. model_rounds model
        fold_errors =. i.0
        for_t. 1+i.Rounds do.
            selected =. t first_rounds rounds
            values =. selected score_rows validation{TrainX
            fold_errors =. fold_errors,(validation{TrainY)error_count values
        end.
        errors =. errors+fold_errors
        folds =. folds,<(<model),(<train_count),(<validation),<fold_errors
    end.
    selected =. 1+{.I.errors=<./errors
    out_of_fold =. (#TrainX)$0.0
    for_fold. folds do.
        'model train_count validation unused' =. >fold
        rounds =. selected first_rounds model_rounds model
        for_i. validation do.
            out_of_fold =. (rounds row_score i{TrainX)i}out_of_fold
        end.
    end.
    (<folds),(<errors),(<selected),<out_of_fold
)
calc_curve =: 3 : 0
    'rounds training train_labels testing test_labels logit' =. y
    train_scores =. (#training)$0.0
    test_scores =. (#testing)$0.0
    scale =. 0.0
    result =. 0 5$0.0
    for_box. rounds do.
        record =. >box
        stump =. round_stump record
        train_scores =. train_scores+stump stump_outputs training
        test_scores =. test_scores+stump stump_outputs testing
        scale =. scale+magnitude record
        train_error =. train_labels error_count train_scores
        test_error =. test_labels error_count test_scores
        train_loss =. calc_loss (<train_labels),(<train_scores),<logit
        test_loss =. calc_loss (<test_labels),(<test_scores),<logit
        minimum =. (<./train_labels*train_scores)%scale
        result =. result,train_error,test_error,train_loss,test_loss,minimum
    end.
    result
)
curve_minimum =: 4 : 0
    values =. x{"1 y
    at =. {.I.values=<./values
    (at{values),at+1
)
metrics_line =: 3 : 0
    'kind variant rounds labels values logit' =. y
    predicted =. prediction values
    tp =. +/(labels=1)*.predicted=1
    fp =. +/(labels=_1)*.predicted=1
    tn =. +/(labels=_1)*.predicted=_1
    fn =. +/(labels=1)*.predicted=_1
    auc_values =. auc (<labels),<values
    line =. kind,' ',variant,' rounds ',(integer rounds),' correct ',(integer tp+tn),'/',integer #labels
    line =. line,' accuracy ',((tp+tn)ratio #labels),' tp ',(integer tp),' fp ',(integer fp),' tn ',(integer tn),' fn ',integer fn
    line =. line,' precision ',(tp ratio tp+fp),' recall ',(tp ratio tp+fn),' f1 ',((2*tp)ratio (2*tp)+fp+fn)
    line =. line,' auc ',((0{auc_values)ratio 1{auc_values),' loss ',real_text calc_loss (<labels),(<values),<logit
    line
)
calc_importance =: 3 : 0
    'rounds count samme' =. y
    values =. count$0.0
    counts =. count$0
    for_box. rounds do.
        record =. >box
        j =. stump_feature round_stump record
        value =. magnitude record
        if. samme do.
            value =. round_alpha record
        end.
        values =. ((j{values)+value)j}values
        counts =. (1+j{counts)j}counts
    end.
    (<values),(<counts),(<ordered_sum values),<\:values
)
importance_lines =: 4 : 0
    'values counts total order' =. y
    lines =. <'importance'
    for_rank. i.#order do.
        j =. rank{order
        line =. (integer rank+1),' ',(j{::x),' score ',(real_text j{values),' share ',(real_text (j{values)%total),' rounds ',integer j{counts
        lines =. lines,<line
    end.
    lines
)
permutation_importance =: 3 : 0
    'rounds rows labels' =. y
    base =. (#rows)-labels error_count rounds score_rows rows
    drops =. minimum =. maximum =. i.0
    for_j. i.{:$rows do.
        counts =. i.0
        for_repeat. i.PermutationRepeats do.
            order =. i.#rows
            for_i. |.1+i.(#rows)-1 do.
                other =. <.0.0+(i+1)|random_draw 0
                temporary =. i{order
                order =. (other{order)i}order
                order =. temporary other}order
            end.
            correct =. 0
            for_i. i.#rows do.
                values =. ((<(i{order),j){rows)j}i{rows
                correct =. correct+(i{labels)=prediction rounds row_score values
            end.
            counts =. counts,correct
        end.
        drops =. drops,+/base-counts
        minimum =. minimum,<./counts
        maximum =. maximum,>./counts
    end.
    (<base),(<drops),(<minimum),(<maximum),<\:drops
)
p_name =: 0&{::
p_full =: 1&{::
p_rounds =: 2&{::
p_scale =: 3&{::
p_train =: 4&{::
p_test =: 5&{::
p_train_margins =: 6&{::
p_test_margins =: 7&{::
p_curve =: 8&{::
p_importance =: 9&{::
p_permutation =: 10&{::
make_profile =: 3 : 0
    'variant full selected' =. y
    rounds =. model_rounds full
    if. variant-:'discrete' do.
        rounds =. selected first_rounds rounds
    end.
    train_scores =. rounds score_rows TrainX
    test_scores =. rounds score_rows TestX
    scale =. ordered_sum magnitude&>rounds
    train_margins =. (TrainY*train_scores)%scale
    test_margins =. (TestY*test_scores)%scale
    curve =. calc_curve (<model_rounds full),(<TrainX),(<TrainY),(<TestX),(<TestY),<variant-:'logit'
    importance =. calc_importance (<rounds),(<#Features),<0
    permutation =. permutation_importance (<rounds),(<TestX),<TestY
    (<variant),(<full),(<rounds),(<scale),(<train_scores),(<test_scores),(<train_margins),(<test_margins),(<curve),(<importance),<permutation
)
ensemble_report =: 3 : 0
    'profiles cv' =. y
    'folds errors selected unused' =. cv
    lines =. 0$a:
    for_box. profiles do.
        item =. >box
        variant =. p_name item
        model =. p_full item
        rounds =. model_rounds model
        if. #lines do.
            lines =. lines,<''
        end.
        header =. 'variant ',variant,' rounds ',(integer #rounds),' stop ',model_reason model
        if. variant-:'real' do.
            header =. header,' bins ',(integer Bins),' smoothing ',(real_text Smoothing),' convergence ',6 real_text Convergence
        elseif. variant-:'logit' do.
            header =. header,' clip ',real_text Clip
        end.
        lines =. lines,<header
        if. variant-:'real' do.
            cuts =. model_cuts model
            for_j. i.#Features do.
                lines =. lines,<'cuts ',(j{::Features),' ',reals j{::cuts
            end.
        end.
        for_t. i.#rounds do.
            record =. t{::rounds
            'feature thresholds values' =. round_stump record
            line =. 'round ',(integer t+1),' feature ',feature{::Features
            if. variant-:'real' do.
                line =. line,' z ',(real_text round_z record),' bound ',(real_text round_bound record),' values ',reals values
            else.
                line =. line,' threshold ',real_text 0{thresholds
                if. variant-:'discrete' do.
                    line =. line,' polarity ',(integer round_polarity record),' error ',(real_text round_error record),' alpha ',real_text round_alpha record
                    line =. line,' z ',(real_text round_z record),' bound ',real_text round_bound record
                else.
                    line =. line,' left ',(real_text 0{values),' right ',(real_text 1{values),' error ',real_text round_error record
                    if. variant-:'logit' do.
                        line =. line,' loss ',real_text round_loss record
                    end.
                end.
            end.
            lines =. lines,<line
            if. variant-:'discrete' do.
                weights =. round_weights record
                maximum =. {.\:weights
                ess =. 1.0%ordered_sum weights*weights
                lines =. lines,<'weights ',(integer t+1),' max ',(6 real_text maximum{weights),' id ',(maximum{::TrainIDs),' ess ',real_text ess
            end.
        end.
        if. variant-:'discrete' do.
            lines =. lines,<'cv folds ',(integer Folds),' selected ',(integer selected),' errors ',(integer (selected-1){errors),'/',integer #TrainX
            for_f. i.#folds do.
                'fold_model count validation fold_errors' =. f{::folds
                line =. 'fold ',(integer f+1),' train ',(integer count),' validation ',integer #validation
                line =. line,' rounds ',(integer #model_rounds fold_model),' stop ',model_reason fold_model
                line =. line,' selected ',(integer (selected-1){fold_errors),'/',(integer #validation),' final ',(integer {:fold_errors),'/',integer #validation
                lines =. lines,<line
            end.
            lines =. lines,<'cv_errors ',integers errors
        end.
    end.
    lines
)
predictions_report =: 3 : 0
    lines =. <'id,variant,score,label,',','join Features
    for_i. i.#TestX do.
        for_box. y do.
            item =. >box
            contributions =. (#Features)$0.0
            for_record. p_rounds item do.
                stump =. round_stump >record
                j =. stump_feature stump
                contributions =. ((j{contributions)+stump stump_output i{TestX)j}contributions
            end.
            score =. i{p_test item
            fields =. (i{TestIDs),(<p_name item),(<real_text score),<integer prediction score
            fields =. fields,real_text&.>contributions
            lines =. lines,<','join fields
        end.
    end.
    lines
)
roc_report =: 3 : 0
    lines =. <'variant,threshold,tp,fp'
    for_box. y do.
        item =. >box
        scores =. p_test item
        for_threshold. \:~~.scores do.
            tp =. +/(scores>:threshold)*.TestY=1
            fp =. +/(scores>:threshold)*.TestY=_1
            lines =. lines,<(p_name item),',',(real_text threshold),',',(integer tp),',',integer fp
        end.
    end.
    lines
)
margins_report =: 3 : 0
    lines =. 0$a:
    for_box. y do.
        item =. >box
        if. #lines do.
            lines =. lines,<''
        end.
        training =. p_train_margins item
        testing =. p_test_margins item
        lines =. lines,<'variant ',(p_name item),' rounds ',(integer #p_rounds item),' scale ',real_text p_scale item
        lines =. lines,<'train min ',(real_text <./training),' mean ',real_text (ordered_sum training)%#training
        for_threshold. Margins do.
            count =. threshold count_margin training
            lines =. lines,<'train le ',(real_text threshold),' ',(integer count),'/',(integer #training),' ',count ratio #training
        end.
        histogram =. 20$0
        for_value. training do.
            bin =. 19<.<.(value+1.0)*10.0
            histogram =. (1+bin{histogram)bin}histogram
        end.
        lines =. lines,<'histogram ',integers histogram
        order =. /:training
        for_i. 5{.order do.
            lines =. lines,<'hardest ',(i{::TrainIDs),' label ',(integer i{TrainY),' margin ',real_text i{training
        end.
        lines =. lines,<'test min ',(real_text <./testing),' mean ',real_text (ordered_sum testing)%#testing
        for_threshold. Margins do.
            count =. threshold count_margin testing
            lines =. lines,<'test le ',(real_text threshold),' ',(integer count),'/',(integer #testing),' ',count ratio #testing
        end.
        for_threshold. Margins do.
            confident =. I.(|testing)>threshold
            correct =. +/(confident{TestY)=prediction confident{p_test item
            line =. 'test confident ',(real_text threshold),' ',(integer #confident),'/',(integer #testing),' correct ',(integer correct),'/',(integer #confident),' ',correct ratio #confident
            lines =. lines,<line
        end.
        lines =. lines,Features importance_lines p_importance item
        'base drops minimum maximum order' =. p_permutation item
        lines =. lines,<'permutation repeats ',(integer PermutationRepeats),' base ',(integer base),'/',integer #TestX
        for_rank. i.#order do.
            j =. rank{order
            line =. (integer rank+1),' ',(j{::Features),' drop ',((j{drops)ratio PermutationRepeats*#TestX)
            line =. line,' min ',(integer j{minimum),'/',(integer #TestX),' max ',(integer j{maximum),'/',integer #TestX
            lines =. lines,<line
        end.
    end.
    lines
)
shapes_report =: 3 : 0
    lines =. 0$a:
    for_box. y do.
        item =. >box
        if. #lines do.
            lines =. lines,<''
        end.
        lines =. lines,<'variant ',(p_name item),' rounds ',integer #p_rounds item
        for_j. i.#Features do.
            collected =. 0$a:
            cuts =. i.0
            for_record. p_rounds item do.
                stump =. round_stump >record
                if. j=stump_feature stump do.
                    collected =. collected,record
                    cuts =. cuts,stump_thresholds stump
                end.
            end.
            cuts =. /:~~.cuts
            values =. i.0
            for_interval. i.1+#cuts do.
                total =. 0.0
                for_record. collected do.
                    stump =. round_stump >record
                    bin =. 0
                    if. interval do.
                        bin =. +/(stump_thresholds stump)<:(interval-1){cuts
                    end.
                    total =. total+bin{stump_values stump
                end.
                values =. values,total
            end.
            range =. (>./values)-<./values
            lines =. lines,<'feature ',(j{::Features),' rounds ',(integer #collected),' cuts ',(integer #cuts),' range ',real_text range
            for_interval. i.#values do.
                lower =. '-inf'
                upper =. 'inf'
                if. interval do.
                    lower =. real_text (interval-1){cuts
                end.
                if. interval<#cuts do.
                    upper =. real_text interval{cuts
                end.
                lines =. lines,<'interval ',lower,' ',upper,' value ',real_text interval{values
            end.
        end.
    end.
    lines
)
feature_summary =: 4 : 0
    values =. x{"1 y
    (reals (<./values),(>./values),(ordered_sum values)%#values),' ',integer #~.values
)
bootstrap_lines =: 3 : 0
    profiles =. y
    RandomState =: x: BootstrapSeed
    counts =. ((#profiles),BootstrapCount)$0
    for_sample. i.BootstrapCount do.
        selected =. i.0
        for_i. i.#TestX do.
            selected =. selected,<.0.0+(#TestX)|random_draw 0
        end.
        for_v. i.#profiles do.
            item =. v{::profiles
            correct =. +/(selected{TestY)=prediction selected{p_test item
            counts =. correct(<v,sample)}counts
        end.
    end.
    lines =. <'bootstrap samples ',(integer BootstrapCount),' seed ',integer BootstrapSeed
    tail =. <.BootstrapCount intdiv 40
    for_v. i.#profiles do.
        values =. v{counts
        ordered =. /:~values
        line =. (p_name v{::profiles),' mean ',((+/values)ratio BootstrapCount*#TestX)
        low =. tail{ordered
        high =. ((BootstrapCount-tail)-1){ordered
        line =. line,' low ',(low ratio #TestX),' high ',high ratio #TestX
        lines =. lines,<line
    end.
    for_a. i.#profiles do.
        for_b. (a+1)}.i.#profiles do.
            left =. a{counts
            right =. b{counts
            line =. (p_name a{::profiles),' ',(p_name b{::profiles),' first ',(integer +/left>right),' tie ',(integer +/left=right),' second ',integer +/left<right
            lines =. lines,<line
        end.
    end.
    lines
)
calibration_lines =: 3 : 0
    ranges =. '0.0-0.2';'0.2-0.4';'0.4-0.6';'0.6-0.8';'0.8-1.0'
    lines =. 0$a:
    for_box. y do.
        item =. >box
        scores =. p_test item
        counts =. positives =. 5$0
        totals =. 5$0.0
        brier =. 0.0
        for_i. i.#TestX do.
            p =. 1.0%(1.0+^_2.0*i{scores)
            target =. 1=i{TestY
            difference =. p-target
            brier =. brier+difference*difference
            bin =. 4<.<.p*5.0
            counts =. (1+bin{counts)bin}counts
            totals =. ((bin{totals)+p)bin}totals
            positives =. ((bin{positives)+target)bin}positives
        end.
        lines =. lines,<'calibration ',(p_name item),' brier ',real_text brier%#TestX
        for_bin. i.5 do.
            mean =. '-'
            if. bin{counts do.
                mean =. real_text (bin{totals)%bin{counts
            end.
            lines =. lines,<'bin ',(bin{::ranges),' count ',(integer bin{counts),' mean ',mean,' positives ',integer bin{positives
        end.
    end.
    lines
)
summary_report =: 3 : 0
    'profiles cv' =. y
    'folds errors selected oof' =. cv
    lines =. <'data train ',(integer #TrainX),' test ',(integer #TestX),' features ',(integer #Features),' positives ',(integer +/TrainY=1),' ',integer +/TestY=1
    for_j. i.#Features do.
        lines =. lines,<'feature ',(j{::Features),' train ',(j feature_summary TrainX),' test ',j feature_summary TestX
    end.
    lines =. lines,<'cv selected ',(integer selected),' errors ',(integer (selected-1){errors),'/',(integer #TrainX),' rate ',((selected-1){errors)ratio #TrainX
    lines =. lines,<metrics_line (<'oof'),(<'discrete'),(<selected),(<TrainY),(<oof),<0
    committee_train =. (#TrainX)$0.0
    committee_test =. (#TestX)$0.0
    total_rounds =. 0
    for_box. profiles do.
        item =. >box
        name =. p_name item
        count =. #p_rounds item
        lines =. lines,<metrics_line (<'train'),(<name),(<count),(<TrainY),(<p_train item),<name-:'logit'
        lines =. lines,<metrics_line (<'test'),(<name),(<count),(<TestY),(<p_test item),<name-:'logit'
        total_rounds =. total_rounds+count
        committee_train =. committee_train+(p_train item)%p_scale item
        committee_test =. committee_test+(p_test item)%p_scale item
    end.
    lines =. lines,<metrics_line (<'train'),(<'committee'),(<total_rounds),(<TrainY),(<committee_train),<0
    lines =. lines,<metrics_line (<'test'),(<'committee'),(<total_rounds),(<TestY),(<committee_test),<0
    for_box. profiles do.
        item =. >box
        'train_min train_at' =. 0 curve_minimum p_curve item
        'test_min test_at' =. 1 curve_minimum p_curve item
        line =. 'curve ',(p_name item),' rounds ',(integer #model_rounds p_full item),' train_min ',(integer train_min),'/',(integer #TrainX),' at ',integer train_at
        line =. line,' test_min ',(integer test_min),'/',(integer #TestX),' at ',integer test_at
        lines =. lines,<line
    end.
    wrong =. 0$a:
    for_i. i.#TestX do.
        all_wrong =. 1
        for_box. profiles do.
            if. (i{TestY)=prediction i{p_test >box do.
                all_wrong =. 0
            end.
        end.
        if. all_wrong do.
            wrong =. wrong,i{TestIDs
        end.
    end.
    line =. 'all_wrong ',integer #wrong
    if. #wrong do.
        line =. line,' ',' 'join wrong
    end.
    lines =. lines,(<line),<'agreement'
    for_a. i.#profiles do.
        for_b. (a+1)}.i.#profiles do.
            left =. prediction p_test a{::profiles
            right =. prediction p_test b{::profiles
            agree =. +/left=right
            first =. +/(left=TestY)*.right~:TestY
            second =. +/(right=TestY)*.left~:TestY
            difference =. (|first-second)-1
            line =. (p_name a{::profiles),' ',(p_name b{::profiles),' agree ',(integer agree),'/',(integer #TestX),' only_first ',(integer first),' only_second ',integer second
            lines =. lines,<line,' chi2 ',(difference*difference)ratio first+second
        end.
    end.
    lines,(bootstrap_lines profiles),calibration_lines profiles
)
samme_scores =: 4 : 0
    result =. Classes$0.0
    for_box. x do.
        record =. >box
        class =. ((round_stump record)stump_output y)-1
        result =. ((class{result)+round_alpha record)class}result
    end.
    result
)
class_predictions =: 4 : 0
    result =. i.0
    for_row. y do.
        result =. result,1+{.\:x samme_scores row
    end.
    result
)
class_errors =: 4 : '+/x~:y'
multiclass_analysis =: 3 : 0
    model =. train_samme (<MultiTrainX),(<MultiTrainY),(<Classes),<SammeRounds
    rounds =. model_rounds model
    ovr =. 0$a:
    for_c. 1+i.Classes do.
        labels =. _1+2*MultiTrainY=c
        ovr =. ovr,<train_discrete (<MultiTrainX),(<labels),(<SammeRounds),(<1.0),<i.0
    end.
    training =. rounds class_predictions MultiTrainX
    testing =. rounds class_predictions MultiTestX
    ovr_training =. ovr_testing =. i.0
    class_scores =. (0,Classes)$0.0
    for_collection. i.2 do.
        rows =. MultiTrainX
        if. collection do.
            rows =. MultiTestX
        end.
        for_row. rows do.
            binary =. i.0
            for_classifier. ovr do.
                binary =. binary,(model_rounds >classifier)row_score row
            end.
            predicted =. 1+{.\:binary
            if. collection do.
                ovr_testing =. ovr_testing,predicted
                class_scores =. class_scores,rounds samme_scores row
            else.
                ovr_training =. ovr_training,predicted
            end.
        end.
    end.
    curve =. 0 2$0
    for_t. 1+i.#rounds do.
        selected =. t{.rounds
        train_error =. MultiTrainY class_errors selected class_predictions MultiTrainX
        test_error =. MultiTestY class_errors selected class_predictions MultiTestX
        curve =. curve,train_error,test_error
    end.
    (<model),(<ovr),(<training),(<testing),(<ovr_training),(<ovr_testing),(<class_scores),<curve
)
confusion_lines =: 3 : 0
    matrix =. confusion (<MultiTestY),(<y),<Classes
    lines =. <'confusion'
    for_row. matrix do.
        lines =. lines,<integers row
    end.
    for_c. i.Classes do.
        column =. +/c{"1 matrix
        row_total =. +/c{matrix
        diagonal =. (<c,c){matrix
        lines =. lines,<'class ',(integer c+1),' precision ',(diagonal ratio column),' recall ',diagonal ratio row_total
    end.
    lines
)
multiclass_evaluation =: 3 : 0
    'training testing' =. y
    train_error =. MultiTrainY class_errors training
    test_error =. MultiTestY class_errors testing
    lines =. <'train errors ',(integer train_error),'/',(integer #MultiTrainX),' rate ',train_error ratio #MultiTrainX
    lines =. lines,<'test errors ',(integer test_error),'/',(integer #MultiTestX),' rate ',test_error ratio #MultiTestX
    lines,confusion_lines testing
)
samme_report =: 3 : 0
    'model ovr training testing ovr_training ovr_testing class_scores curve' =. y
    rounds =. model_rounds model
    lines =. <'samme classes ',(integer Classes),' train ',(integer #MultiTrainX),' test ',(integer #MultiTestX),' rounds ',(integer #rounds),' stop ',model_reason model
    for_t. i.#rounds do.
        record =. t{::rounds
        'feature thresholds values' =. round_stump record
        line =. 'round ',(integer t+1),' feature ',(feature{::MultiFeatures),' threshold ',real_text 0{thresholds
        line =. line,' left ',(integer 0{values),' right ',(integer 1{values),' error ',(real_text round_error record),' alpha ',real_text round_alpha record
        lines =. lines,<line
    end.
    lines =. lines,multiclass_evaluation (<training),<testing
    lines =. lines,MultiFeatures importance_lines calc_importance (<rounds),(<#MultiFeatures),<1
    lines =. lines,(<''),<'ovr classes ',(integer Classes),' rounds ',integer SammeRounds
    for_c. i.Classes do.
        classifier =. c{::ovr
        selected =. model_rounds classifier
        train_labels =. _1+2*MultiTrainY=c+1
        test_labels =. _1+2*MultiTestY=c+1
        positive =. +/MultiTrainY=c+1
        train_error =. train_labels error_count selected score_rows MultiTrainX
        test_error =. test_labels error_count selected score_rows MultiTestX
        line =. 'class ',(integer c+1),' rounds ',(integer #selected),' stop ',(model_reason classifier),' positives ',integer positive
        lines =. lines,<line,' train_errors ',(integer train_error),'/',(integer #MultiTrainX),' test_errors ',(integer test_error),'/',integer #MultiTestX
    end.
    lines =. lines,multiclass_evaluation (<ovr_training),<ovr_testing
    agree =. +/testing=ovr_testing
    lines =. lines,(<'agreement ',(integer agree),'/',integer #MultiTestX),(<''),<'predictions'
    for_i. i.#MultiTestX do.
        line =. (i{::MultiTestIDs),' class ',(integer i{MultiTestY),' samme ',(integer i{testing),' ovr ',(integer i{ovr_testing),' scores ',reals i{class_scores
        lines =. lines,<line
    end.
    lines
)
error_curve_report =: 3 : 0
    'profiles multi' =. y
    lines =. <'variant,round,train_error,test_error,train_loss,test_loss,min_margin'
    for_box. profiles do.
        item =. >box
        curve =. p_curve item
        for_t. i.#curve do.
            'train_error test_error train_loss test_loss minimum' =. t{curve
            fields =. (<p_name item),(<integer t+1),(<train_error ratio #TrainX),(<test_error ratio #TestX),(<real_text train_loss),(<real_text test_loss),<real_text minimum
            lines =. lines,<','join fields
        end.
    end.
    curve =. 7{::multi
    for_t. i.#curve do.
        'train_error test_error' =. t{curve
        lines =. lines,<'samme,',(integer t+1),',',(train_error ratio #MultiTrainX),',',(test_error ratio #MultiTestX),',-,-,-'
    end.
    lines
)
experiment_fields =: 3 : 0
    'model training train_labels testing test_labels' =. y
    rounds =. model_rounds model
    train_error =. train_labels error_count rounds score_rows training
    test_error =. test_labels error_count rounds score_rows testing
    'rounds ',(integer #rounds),' stop ',(model_reason model),' train_errors ',(integer train_error),'/',(integer #training),' test_errors ',(integer test_error),'/',integer #testing
)
experiments_report =: 3 : 0
    'profiles cv' =. y
    selected =. 2{::cv
    lines =. 0$a:
    for_fraction. Sizes do.
        count =. <.((#TrainX)*fraction)intdiv 100
        rows =. count{.TrainX
        labels =. count{.TrainY
        lines =. lines,<'size ',(integer fraction),' rows ',integer count
        for_variant. Variants do.
            model =. train_variant variant,(<rows),<labels
            lines =. lines,<(>variant),' ',experiment_fields (<model),(<rows),(<labels),(<TestX),<TestY
        end.
    end.
    for_shrinkage. Shrinkages do.
        model =. train_discrete (<TrainX),(<TrainY),(<Rounds),(<shrinkage),<i.0
        curve =. calc_curve (<model_rounds model),(<TrainX),(<TrainY),(<TestX),(<TestY),<0
        'minimum at' =. 1 curve_minimum curve
        fields =. experiment_fields (<model),(<TrainX),(<TrainY),(<TestX),<TestY
        lines =. lines,<'shrinkage ',(real_text shrinkage),' ',fields,' test_min ',(integer minimum),'/',(integer #TestX),' at ',integer at
    end.
    importance_order =. i.0
    for_box. profiles do.
        item =. >box
        if. 'discrete'-:p_name item do.
            importance_order =. 3{::p_importance item
            break.
        end.
    end.
    for_count. 1+i.#Features do.
        features =. /:~count{.importance_order
        rows =. features{"1 TrainX
        testing =. features{"1 TestX
        model =. train_discrete (<rows),(<TrainY),(<selected),(<1.0),<i.0
        rounds =. model_rounds model
        train_error =. TrainY error_count rounds score_rows rows
        test_error =. TestY error_count rounds score_rows testing
        line =. 'top ',(integer count),' features ',(' 'join features{Features),' rounds ',integer #rounds
        lines =. lines,<line,' train_errors ',(integer train_error),'/',(integer #TrainX),' test_errors ',(integer test_error),'/',integer #TestX
    end.
    for_fraction. Noise do.
        count =. <.((#TrainX)*fraction)intdiv 100
        RandomState =: x: NoiseSeed
        order =. i.#TrainX
        for_i. i.count do.
            other =. i+<.0.0+((#TrainX)-i)|random_draw 0
            temporary =. i{order
            order =. (other{order)i}order
            order =. temporary other}order
        end.
        flipped =. (#TrainX)$0
        flipped =. 1 (count{.order)}flipped
        labels =. TrainY*(1-2*flipped)
        lines =. lines,<'noise ',(integer fraction),' flipped ',integer count
        for_variant. Variants do.
            model =. train_variant variant,(<TrainX),<labels
            rounds =. model_rounds model
            curve =. calc_curve (<rounds),(<TrainX),(<labels),(<TestX),(<TestY),<(>variant)-:'logit'
            'minimum at' =. 1 curve_minimum curve
            weights =. round_weights >{:rounds
            weight =. ordered_sum flipped#weights
            fields =. experiment_fields (<model),(<TrainX),(<labels),(<TestX),<TestY
            line =. (>variant),' ',fields,' test_min ',(integer minimum),'/',(integer #TestX),' at ',integer at
            lines =. lines,<line,' flipped_weight ',real_text weight
        end.
    end.
    lines
)
run =: 3 : 0
    read_inputs 0
    CV =: cross_validation 0
    RandomState =: x: PermutationSeed
    Profiles =: 0$a:
    for_variant. Variants do.
        Full =. train_variant variant,(<TrainX),<TrainY
        Profiles =: Profiles,<make_profile variant,(<Full),<2{::CV
    end.
    Multi =: multiclass_analysis 0
    'ensemble.txt' save_lines ensemble_report (<Profiles),<CV
    'error_curve.csv' save_lines error_curve_report (<Profiles),<Multi
    'predictions.csv' save_lines predictions_report Profiles
    'roc.csv' save_lines roc_report Profiles
    'margins.txt' save_lines margins_report Profiles
    'shapes.txt' save_lines shapes_report Profiles
    'samme.txt' save_lines samme_report Multi
    'summary.txt' save_lines summary_report (<Profiles),<CV
    'experiments.txt' save_lines experiments_report (<Profiles),<CV
    i.0 0
)
run 0
