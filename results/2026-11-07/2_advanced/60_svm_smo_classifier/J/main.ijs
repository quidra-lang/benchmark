ScriptPath =: >{:4!:3''
DirectoryLength =: 1+>./ _1,I.ScriptPath e.'/\'
SourceDirectory =: DirectoryLength{.ScriptPath
load SourceDirectory,'evaluation.ijs'
load SourceDirectory,'dataset.ijs'
load SourceDirectory,'kernels.ijs'
load SourceDirectory,'smo.ijs'
load SourceDirectory,'multiclass.ijs'

support_counts =: 3 : 0
    alpha =. 5{::y
    coefficient =. 4{::y
    total =. +/alpha>0
    bound =. +/(alpha>0)*.alpha=coefficient
    total,bound,total-bound
)
support_text =: 3 : 0
    'total bound free' =. support_counts y
    emit 'support_vectors';total;'bound';bound;'free';free
)
run_info =: 3 : 0
    counters =. 7{::y
    converged =. (9{::y){::'no';'yes'
    emit 'passes';(+/2{.counters);'steps';(3{counters);'converged';converged
)
model_objectives =: 4 : 0
    labels =. 1{::x
    matrix =. 3{::x
    alpha =. y
    quadratic =. 0.0
    total =. 0.0
    for_i. i.#alpha do.
        value =. 0.0
        for_j. I.alpha>0 do. value =. value+((j{alpha)*j{labels)*(<i,j){matrix end.
        quadratic =. quadratic+((i{alpha)*i{labels)*value
        total =. total+i{alpha
    end.
    quadratic,total-quadratic%2
)
cross_validate =: 3 : 0
    TrainIds =: 0{::TrainData
    TrainX =: 1{::TrainData
    TrainY =: 2{::TrainData
    TestIds =: 0{::TestData
    TestX =: 1{::TestData
    TestY =: 2{::TestData
    partitions =. (#TrainY)make_folds FoldCount
    Matrices =: Combinations =: Best =: 0$a:
    keys =. 0 3$0.0
    for_k. i.#KernelDefs do.
        kernel =. k{::KernelDefs
        matrix =. kernel kernel_matrix TrainX
        Matrices =: Matrices,<matrix
        best =. a:
        for_coefficient. CGrid do.
            values =. (#TrainY)$0.0
            foldrecords =. 0$a:
            correct =. support =. passes =. steps =. 0
            for_partition. partitions do.
                'train_indices test_indices' =. >partition
                points =. train_indices{TrainX
                labels =. train_indices{TrainY
                submatrix =. train_indices kernel_submatrix matrix
                model =. smo_train (<points),(<labels),(<kernel),(<submatrix),<coefficient
                predicted =. model smo_decisions test_indices{TrainX
                values =. predicted test_indices}values
                foldcorrect =. (test_indices{TrainY)correct_count predicted
                foldsupport =. {.support_counts model
                counters =. 7{::model
                foldrecords =. foldrecords,<(<#train_indices),(<#test_indices),(<foldcorrect),(<foldsupport),<model
                correct =. correct+foldcorrect
                support =. support+foldsupport
                passes =. passes++/2{.counters
                steps =. steps+3{counters
            end.
            result =. (<k),(<coefficient),(<values),(<foldrecords),(<correct),(<support),(<passes),<steps
            Combinations =: Combinations,<result
            keys =. keys,(-correct),coefficient,k
            if. best-:a: do. best =. result
            elseif. correct>4{::best do. best =. result end.
        end.
        Best =: Best,<best
    end.
    Ranking =: (/:keys){Combinations
    Selected =: 0{::Ranking
    i.0 0
)
cv_lines =: 3 : 0
    lines =. <emit 'cross_validation folds';FoldCount;'examples';#TrainY
    for_result. Best do.
        result =. >result
        kernel =. (0{::result){::KernelDefs
        fraction =. (integer 4{::result),'/',integer #TrainY
        lines =. lines,<emit 'best';(0{::kernel);'C';(fixed 1{::result);'correct';fraction;'accuracy';((4{::result)ratio #TrainY)
    end.
    kernel =. (0{::Selected){::KernelDefs
    lines =. lines,<emit 'selected';(0{::kernel);'C';fixed 1{::Selected
    lines =. lines,<'ranking'
    for_rank. i.#Ranking do.
        result =. rank{::Ranking
        kernel =. (0{::result){::KernelDefs
        fraction =. (integer 4{::result),'/',integer #TrainY
        lines =. lines,<emit (rank+1);(0{::kernel);'C';(fixed 1{::result);'correct';fraction
    end.
    kernel =. (0{::Selected){::KernelDefs
    lines =. lines,<emit 'cv_detail';(0{::kernel);'C';fixed 1{::Selected
    folds =. 3{::Selected
    for_i. i.#folds do.
        'train testing correct support model' =. i{::folds
        lines =. lines,<emit 'fold';(i+1);'train';train;'test';testing;'correct';correct;'support_vectors';support;run_info model
    end.
    lines
)
final_evaluation =: 3 : 0
    model =. y
    kernel =. 2{::model
    coefficient =. 4{::model
    alpha =. 5{::model
    matrix =. 3{::model
    counters =. 7{::model
    trainvalues =. smo_training_values model
    testvalues =. model smo_decisions TestX
    'quadratic dual' =. model model_objectives alpha
    sy =. sg =. 0.0
    maximum =. __
    minimum =. _
    for_i. i.#TrainY do.
        maximum =. maximum>.(<i,i){matrix
        for_j. i.#TrainY do.
            value =. (<i,j){matrix
            sy =. sy+((i{TrainY)*j{TrainY)*value
            sg =. sg+value*value
            minimum =. minimum<.value
        end.
    end.
    alignment =. sy%((#TrainY)*%:sg)
    equality =. w1 =. w2 =. 0.0
    classes =. 2 2$0
    for_i. i.#TrainY do.
        label =. i{TrainY
        a =. i{alpha
        equality =. equality+a*label
        if. (1{::kernel)-:'linear' do.
            w1 =. w1+(a*label)*(<i,0){TrainX
            w2 =. w2+(a*label)*(<i,1){TrainX
        end.
        if. a>0 do.
            class =. label=_1
            category =. a~:coefficient
            index =. <class,category
            classes =. (1+index{classes)index}classes
        end.
    end.
    norm =. %:quadratic
    radius =. maximum-minimum
    hinge_total =. largest =. 0.0
    violations =. estimated =. 0
    for_i. i.#TrainY do.
        label =. i{TrainY
        a =. i{alpha
        value =. i{trainvalues
        hinge =. 0.0>.1-label*value
        hinge_total =. hinge_total+hinge
        residual =. (label*value)-1
        if. a=0 do. violation =. 0.0>.-residual
        elseif. a=coefficient do. violation =. 0.0>.residual
        else. violation =. |residual end.
        violations =. violations+violation>Tolerance
        largest =. largest>.violation
        estimated =. estimated+(((2*a)*radius)+hinge)>:1
    end.
    primal =. (quadratic%2)+coefficient*hinge_total
    traincorrect =. TrainY correct_count trainvalues
    'tp fp tn fn' =. TestY binary_counts testvalues
    inside =. +/1>|testvalues
    positives =. I.TestY=1
    negatives =. I.TestY=_1
    positive_mean =. (sum_ordered positives{testvalues)%#positives
    negative_mean =. (sum_ordered negatives{testvalues)%#negatives
    lines =. <emit 'model';0{::kernel
    lines =. lines,<emit 'kernel';kernel_description kernel
    lines =. lines,<emit 'C';fixed coefficient
    lines =. lines,<emit 'alignment';six alignment
    converged =. (9{::model){::'no';'yes'
    lines =. lines,<emit 'passes';(+/2{.counters);'full';(0{counters);'nonbound';(1{counters);'converged';converged
    lines =. lines,<emit 'examined';(2{counters);'steps';3{counters
    lines =. lines,<emit 'choice heuristic';(4{counters);'nonbound_loop';(5{counters);'full_loop';6{counters
    lines =. lines,<emit 'clipping none';(7{counters);'lower';(8{counters);'upper';9{counters
    lines =. lines,<support_text model
    lines =. lines,<emit 'b';six 6{::model
    lines =. lines,<emit 'equality';six equality
    if. (1{::kernel)-:'linear' do. lines =. lines,<emit 'w';(six w1);six w2 end.
    lines =. lines,<emit 'sv_by_class positive bound';((<0,0){classes);'free';((<0,1){classes);'negative bound';((<1,0){classes);'free';(<1,1){classes
    lines =. lines,<emit 'norm';(six norm);'margin';six 2%norm
    lines =. lines,<emit 'dual_objective';six dual
    lines =. lines,<emit 'primal_objective';six primal
    lines =. lines,<emit 'duality_gap';six primal-dual
    lines =. lines,<emit 'kkt_violations';violations;'max';six largest
    lines =. lines,<emit 'xi_alpha radius';(six radius);'errors';((integer estimated),'/',integer #TrainY);'accuracy';((#TrainY)-estimated)ratio #TrainY
    lines =. lines,<emit 'train correct';((integer traincorrect),'/',integer #TrainY);'accuracy';traincorrect ratio #TrainY
    lines =. lines,<emit 'test correct';((integer tp+tn),'/',integer #TestY);'accuracy';((tp+tn)ratio #TestY);'tp';tp;'fp';fp;'tn';tn;'fn';fn
    lines =. lines,<emit 'test precision';(tp ratio tp+fp);'recall';(tp ratio tp+fn);'f1';((2*tp)ratio (2*tp)+fp+fn);'auc';fixed TestY auc testvalues
    lines =. lines,<emit 'test inside_margin';inside
    lines =. lines,<emit 'test mean_decision positive';(fixed positive_mean);'negative';fixed negative_mean
    for_i. I.alpha>0 do.
        state =. ((i{alpha)=coefficient){::'free';'bound'
        lines =. lines,<emit 'sv';(i{::TrainIds);'y';(i{TrainY);'alpha';(six i{alpha);'f';(fixed i{trainvalues);state
    end.
    (<model),(<trainvalues),(<testvalues),(<w1,w2),<lines
)
training_log =: 3 : 0
    model =. y
    kernel =. 2{::model
    records =. 8{::model
    lines =. <emit 'training_log';0{::kernel
    index =. 0
    while. index<#records do.
        'full examined changed snapshot' =. index{::records
        if. full do.
            dual =. 1{model model_objectives snapshot
            lines =. lines,<emit 'pass';(index+1);'full examined';examined;'changed';changed;'dual_objective';six dual
            index =. index+1
        else.
            first =. index
            examined =. changed =. 0
            while. index<#records do.
                record =. index{::records
                if. 0{::record do. break. end.
                examined =. examined+1{::record
                changed =. changed+2{::record
                index =. index+1
            end.
            span =. (integer first+1),'-',integer index
            lines =. lines,<emit 'passes';span;'nonbound examined';examined;'changed';changed
        end.
    end.
    lines
)
c_path =: 3 : 0
    kernel_index =. 0{::Selected
    kernel =. kernel_index{::KernelDefs
    matrix =. kernel_index{::Matrices
    lines =. <emit 'c_path';0{::kernel
    for_coefficient. CGrid do.
        model =. smo_train (<TrainX),(<TrainY),(<kernel),(<matrix),<coefficient
        dual =. 1{model model_objectives 5{::model
        traincorrect =. TrainY correct_count smo_training_values model
        testcorrect =. TestY correct_count model smo_decisions TestX
        lines =. lines,<emit 'C';(fixed coefficient);(support_text model);'dual_objective';(six dual);'train';((integer traincorrect),'/',integer #TrainY);'test';((integer testcorrect),'/',integer #TestY);run_info model
    end.
    lines
)
learning_curve =: 3 : 0
    kernel_index =. 0{::Selected
    coefficient =. 1{::Selected
    kernel =. kernel_index{::KernelDefs
    matrix =. kernel_index{::Matrices
    lines =. <emit 'learning_curve';(0{::kernel);'C';fixed coefficient
    for_percentage. CurveFractions do.
        size =. <.((#TrainY)*percentage)%100
        indices =. i.size
        points =. indices{TrainX
        labels =. indices{TrainY
        submatrix =. indices kernel_submatrix matrix
        model =. smo_train (<points),(<labels),(<kernel),(<submatrix),<coefficient
        traincorrect =. labels correct_count smo_training_values model
        testcorrect =. TestY correct_count model smo_decisions TestX
        lines =. lines,<emit 'size';size;'support_vectors';({.support_counts model);'train';((integer traincorrect),'/',integer size);'test';((integer testcorrect),'/',integer #TestY);run_info model
    end.
    lines
)
probability =: 4 : '1%1+^(((0{x)*y)+1{x)'
calibration_nll =: 3 : 0
    'values targets a b' =. y
    total =. 0.0
    for_i. i.#values do.
        prob =. (a,b)probability i{values
        target =. i{targets
        total =. total+((target*^.prob)+(1-target)*^.1-prob)
    end.
    -total
)
calibrate =: 3 : 0
    testvalues =. y
    positive =. +/TrainY=1
    negative =. (#TrainY)-positive
    targets =. (#TrainY)$1%negative+2
    targets =. ((positive+1)%positive+2)(I.TrainY=1)}targets
    values =. 2{::Selected
    a =. 0.0
    b =. ^.(negative+1)%positive+1
    kernel =. (0{::Selected){::KernelDefs
    lines =. <emit 'calibration';(0{::kernel);'C';(fixed 1{::Selected);'positives';positive;'negatives';negative
    loss =. calibration_nll (<values),(<targets),(<a),<b
    lines =. lines,<emit 'start A';(six a);'B';(six b);'nll';six loss
    for_iteration. 1+i.NewtonIterations do.
        g1 =. g2 =. h11 =. h21 =. h22 =. 0.0
        for_i. i.#values do.
            value =. i{values
            prob =. (a,b)probability value
            target =. i{targets
            g1 =. g1+value*(target-prob)
            g2 =. g2+target-prob
            h11 =. h11+(((value*value)*prob)*(1-prob))
            h21 =. h21+((value*prob)*(1-prob))
            h22 =. h22+prob*(1-prob)
        end.
        determinant =. (h11*h22)-h21*h21
        nexta =. a-((h22*g1)-h21*g2)%determinant
        nextb =. b-((h11*g2)-h21*g1)%determinant
        a =. nexta
        b =. nextb
        loss =. calibration_nll (<values),(<targets),(<a),<b
        lines =. lines,<emit 'iteration';iteration;'A';(six a);'B';(six b);'nll';six loss
    end.
    probabilities =. (a,b)probability testvalues
    logtotal =. briertotal =. 0.0
    bin_counts =. bin_positive =. 5$0
    bin_totals =. 5$0.0
    for_i. i.#TestY do.
        prob =. i{probabilities
        positive_label =. 1=i{TestY
        if. positive_label do. logtotal =. logtotal+^.prob
        else. logtotal =. logtotal+^.1-prob end.
        difference =. prob-positive_label
        briertotal =. briertotal+difference*difference
        bin =. 4<.<.prob*5
        bin_counts =. (1+bin{bin_counts)bin}bin_counts
        bin_totals =. (prob+bin{bin_totals)bin}bin_totals
        bin_positive =. (positive_label+bin{bin_positive)bin}bin_positive
    end.
    lines =. lines,<emit 'test log_loss';(six (-logtotal)%#TestY);'brier';six briertotal%#TestY
    ranges =. '0.0-0.2';'0.2-0.4';'0.4-0.6';'0.6-0.8';'0.8-1.0'
    for_bin. i.5 do.
        mean_probability =. '-'
        if. bin{bin_counts do. mean_probability =. fixed (bin{bin_totals)%bin{bin_counts end.
        lines =. lines,<emit 'bin';(bin{::ranges);'count';(bin{bin_counts);'mean_probability';mean_probability;'positive_rate';(bin{bin_positive)ratio bin{bin_counts
    end.
    closest =. /:|testvalues
    for_i. 5{.closest do.
        lines =. lines,<emit 'closest';(i{::TestIds);'label';(i{TestY);'decision';(fixed i{testvalues);'probability';fixed i{probabilities
    end.
    (<a),(<b),(<probabilities),<lines
)
linear_decisions =: 4 : 0
    values =. i.0
    for_point. y do.
        value =. (((0{x)*0{point)+(1{x)*1{point)+2{x
        values =. values,value
    end.
    values
)
pegasos =: 3 : 0
    comparison =. y
    state =. PegasosSeed
    w1 =. w2 =. w0 =. sum1 =. sum2 =. sum0 =. 0.0
    updates =. 0
    lines =. <emit 'pegasos lambda';(fixed PegasosLambda);'iterations';PegasosIterations;'seed';PegasosSeed
    for_iteration. 1+i.PegasosIterations do.
        state =. 2147483647|48271x*state
        index =. (#TrainY)|state
        label =. index{TrainY
        'x1 x2' =. index{TrainX
        eta =. 1%(PegasosLambda*iteration)
        sigma =. 1-eta*PegasosLambda
        if. (label*(((w1*x1)+w2*x2)+w0))<1 do.
            w1 =. (sigma*w1)+(eta*label)*x1
            w2 =. (sigma*w2)+(eta*label)*x2
            w0 =. (sigma*w0)+eta*label
            updates =. updates+1
        else.
            w1 =. sigma*w1
            w2 =. sigma*w2
            w0 =. sigma*w0
        end.
        sum1 =. sum1+w1
        sum2 =. sum2+w2
        sum0 =. sum0+w0
        if. 0=(<.PegasosIterations%10)|iteration do.
            trainvalues =. (w1,w2,w0)linear_decisions TrainX
            hinge =. 0.0
            for_i. i.#TrainY do. hinge =. hinge+0.0>.1-(i{TrainY)*i{trainvalues end.
            norm2 =. ((w1*w1)+w2*w2)+w0*w0
            objective =. ((PegasosLambda%2)*norm2)+hinge%#TrainY
            correct =. TrainY correct_count trainvalues
            lines =. lines,<emit 'checkpoint';iteration;'objective';(six objective);'train';(integer correct),'/',integer #TrainY
        end.
    end.
    weights =. w1,w2,w0
    averages =. (sum1,sum2,sum0)%PegasosIterations
    trainvalues =. weights linear_decisions TrainX
    testvalues =. weights linear_decisions TestX
    averagevalues =. averages linear_decisions TestX
    traincorrect =. TrainY correct_count trainvalues
    testcorrect =. TestY correct_count testvalues
    averagecorrect =. TestY correct_count averagevalues
    'v1 v2' =. 3{::comparison
    cosine =. ((w1*v1)+w2*v2)%((%:(w1*w1)+w2*w2)*%:(v1*v1)+v2*v2)
    agreement =. +/(sgn testvalues)=sgn 2{::comparison
    model =. 0{::comparison
    kernel =. 2{::model
    lines =. lines,<emit 'updates';updates
    lines =. lines,<emit 'w';(six w1);(six w2);'bias';six w0
    lines =. lines,<emit 'train correct';((integer traincorrect),'/',integer #TrainY);'accuracy';traincorrect ratio #TrainY
    lines =. lines,<emit 'test correct';((integer testcorrect),'/',integer #TestY);'accuracy';testcorrect ratio #TestY
    lines =. lines,<emit 'average w';(six 0{averages);(six 1{averages);'bias';(six 2{averages);'test correct';(integer averagecorrect),'/',integer #TestY
    lines =. lines,<emit 'compare';(0{::kernel);'cosine';(six cosine);'test_agreement';(integer agreement),'/',integer #TestY
    (<testvalues),<lines
)
mcnemar_lines =: 3 : 0
    values =. 0$a:
    names =. 0$a:
    for_final. Finals do.
        final =. >final
        kernel =. 2{::0{::final
        names =. names,<0{::kernel
        values =. values,<2{::final
    end.
    names =. names,<'pegasos'
    values =. values,<y
    lines =. <'mcnemar'
    for_i. i.#names do.
        for_j. (i+1)+i.(#names)-(i+1) do.
            first =. TestY=sgn i{::values
            second =. TestY=sgn j{::values
            n1 =. +/first*.-.second
            n2 =. +/second*.-.first
            chi =. '-'
            if. n1+n2 do.
                difference =. (|n1-n2)-1
                chi =. fixed (difference*difference)%(n1+n2)
            end.
            lines =. lines,<emit (i{::names);(j{::names);'only_first';n1;'only_second';n2;'chi2';chi
        end.
    end.
    lines
)
multiclass_results =: 4 : 0
    results =. 0$a:
    for_point. 1{::y do. results =. results,<x multiclass_classify point end.
    results
)
multiclass_summary =: 3 : 0
    'role data results' =. y
    labels =. 2{::data
    rest =. pairs =. agreement =. ties =. 0
    for_i. i.#labels do.
        result =. i{::results
        rest =. rest+(i{labels)=3{::result
        pairs =. pairs+(i{labels)=4{::result
        agreement =. agreement+(3{::result)=4{::result
        ties =. ties+5{::result
    end.
    size =. #labels
    emit role;'ovr';((integer rest),'/',integer size);(rest ratio size);'ovo';((integer pairs),'/',integer size);(pairs ratio size);'agreement';((integer agreement),'/',integer size);'vote_ties';ties
)
multiclass_report =: 3 : 0
    models =. y
    trainresults =. models multiclass_results MultiTrain
    testresults =. models multiclass_results MultiTest
    kernel =. 0{::models
    coefficient =. 1{::models
    trainlabels =. 2{::MultiTrain
    testlabels =. 2{::MultiTest
    traincount =. #trainlabels
    testcount =. #testlabels
    lines =. <emit 'multiclass kernel';(0{::kernel);'C';(fixed coefficient);'classes 3 train';traincount;'test';testcount
    lines =. lines,<'ovr'
    for_i. i.3 do.
        model =. i{::2{::models
        correct =. 0
        for_j. i.testcount do.
            target =. _1+2*(j{testlabels)=i+1
            correct =. correct+target=sgn i{0{::j{::testresults
        end.
        positives =. +/1=1{::model
        lines =. lines,<emit 'model';((integer i+1),'-rest');'examples';traincount;'positives';positives;(support_text model);'b';(six 6{::model);(run_info model);'test';(integer correct),'/',integer testcount
    end.
    lines =. lines,<'ovo'
    for_i. i.3 do.
        'first second' =. i{::ClassPairs
        model =. i{::3{::models
        indices =. I.testlabels e.first,second
        correct =. 0
        for_j. indices do.
            target =. _1+2*(j{testlabels)=first
            correct =. correct+target=sgn i{1{::j{::testresults
        end.
        positives =. +/1=1{::model
        tag =. (integer first),'-',integer second
        lines =. lines,<emit 'model';tag;'examples';(#1{::model);'positives';positives;(support_text model);'b';(six 6{::model);(run_info model);'test';(integer correct),'/',integer #indices
    end.
    lines =. lines,<'predictions'
    for_i. i.testcount do.
        result =. i{::testresults
        restvalues =. ' 'join fixed&.>0{::result
        pairvalues =. ' 'join fixed&.>1{::result
        votes =. ' 'join integer&.>2{::result
        lines =. lines,<emit (i{::0{::MultiTest);'class';(i{testlabels);'ovr';restvalues;'pred';(3{::result);'ovo';pairvalues;'votes';votes;'pred';4{::result
    end.
    lines =. lines,<multiclass_summary (<'train'),(<MultiTrain),<trainresults
    lines =. lines,<multiclass_summary (<'test'),(<MultiTest),<testresults
    restpredictions =. pairpredictions =. i.0
    for_result. testresults do.
        result =. >result
        restpredictions =. restpredictions,3{::result
        pairpredictions =. pairpredictions,4{::result
    end.
    lines =. lines,<'confusion ovr'
    lines =. lines,confusion_lines testlabels confusion_matrix restpredictions
    lines =. lines,<'confusion ovo'
    lines =. lines,confusion_lines testlabels confusion_matrix pairpredictions
    lines
)
framed =: 3 : 0
    'width height' =. PlotSize
    border =. '+',(width$'-'),'+'
    lines =. <border
    for_row. (height,width)$y do. lines =. lines,<'|',row,'|' end.
    lines,<border
)
plot_cell =: 3 : 0
    'width height' =. PlotSize
    'xmin xmax' =. PlotX
    'ymin ymax' =. PlotY
    dx =. (xmax-xmin)%width
    dy =. (ymax-ymin)%height
    column =. <.((0{y)-xmin)%dx
    row =. <.(ymax-1{y)%dy
    if. (column<0)+.(column>:width)+.(row<0)+.row>:height do. _1
    else. (row*width)+column end.
)
decision_plots =: 3 : 0
    'a b multi' =. y
    'width height' =. PlotSize
    'xmin xmax' =. PlotX
    'ymin ymax' =. PlotY
    dx =. (xmax-xmin)%width
    dy =. (ymax-ymin)%height
    totalcells =. width*height
    model =. 0{::(0{::Selected){::Finals
    kernel =. 2{::model
    alpha =. 5{::model
    binary =. totalcells$' '
    probabilitycells =. totalcells$'0'
    multicells =. totalcells$' '
    signs =. ((#Finals),totalcells)$0
    levels =. 10$0
    for_row. i.height do.
        for_column. i.width do.
            point =. (xmin+(column+0.5)*dx),ymax-(row+0.5)*dy
            position =. (row*width)+column
            values =. i.0
            for_i. i.#Finals do.
                value =. (0{::i{::Finals)smo_decision point
                values =. values,value
                signs =. (sgn value)(<i,position)}signs
            end.
            value =. (0{::Selected){values
            if. value>:1 do. character =. '+'
            elseif. value>0 do. character =. '.'
            elseif. value>_1 do. character =. '-'
            else. character =. ' ' end.
            binary =. character position}binary
            level =. 9<.<.10*(a,b)probability value
            probabilitycells =. (level{'0123456789')position}probabilitycells
            levels =. (1+level{levels)level}levels
            result =. multi multiclass_classify point
            if. (3{::result)~:4{::result do. character =. '?'
            else. character =. ((3{::result)-1){' .:' end.
            multicells =. character position}multicells
        end.
    end.
    assignments =. totalcells$_1
    binaryoutside =. 0
    for_i. i.#TrainY do.
        position =. plot_cell i{TrainX
        if. position<0 do. binaryoutside =. binaryoutside+1 else.
            assigned =. position{assignments
            if. assigned<0 do. assignments =. i position}assignments
            elseif. ((i{alpha)>0)*.(assigned{alpha)<:0 do. assignments =. i position}assignments end.
        end.
    end.
    for_position. I.assignments>:0 do.
        index =. position{assignments
        support =. (index{alpha)>0
        if. (index{TrainY)=1 do. character =. support{'xX'
        else. character =. support{'oO' end.
        binary =. character position}binary
    end.
    binarypoints =. +/assignments>:0
    multiassignments =. totalcells$_1
    multioutside =. 0
    multipoints =. 1{::MultiTrain
    multilabels =. 2{::MultiTrain
    for_i. i.#multilabels do.
        position =. plot_cell i{multipoints
        if. position<0 do. multioutside =. multioutside+1
        elseif. (position{multiassignments)<0 do. multiassignments =. i position}multiassignments end.
    end.
    for_position. I.multiassignments>:0 do.
        index =. position{multiassignments
        character =. (index{multilabels){'0123'
        multicells =. character position}multicells
    end.
    multipointcount =. +/multiassignments>:0
    lines =. <emit 'binary';(0{::kernel);'C';fixed 4{::model
    lines =. lines,<emit 'x';(fixed xmin);(fixed xmax);'y';(fixed ymin);(fixed ymax);'grid';(integer width),'x',integer height
    lines =. lines,framed binary
    lines =. lines,<emit 'cells outer_positive';(+/binary='+');'inner_positive';(+/binary='.');'inner_negative';(+/binary='-');'outer_negative';(+/binary=' ');'points';binarypoints;'outside';binaryoutside
    lines =. lines,<''
    lines =. lines,<emit 'probability';(0{::kernel);'A';(six a);'B';six b
    lines =. lines,framed probabilitycells
    lines =. lines,<emit 'levels';' 'join integer&.>levels
    lines =. lines,<''
    lines =. lines,<'grid_agreement'
    for_i. i.#Finals do.
        for_j. (i+1)+i.(#Finals)-(i+1) do.
            first =. i{signs
            second =. j{signs
            firstkernel =. 2{::0{::i{::Finals
            secondkernel =. 2{::0{::j{::Finals
            agreement =. +/first=second
            lines =. lines,<emit (0{::firstkernel);(0{::secondkernel);((integer agreement),'/',integer totalcells);'positive';(+/first=1);+/second=1
        end.
    end.
    lines =. lines,<''
    multikernel =. 0{::multi
    lines =. lines,<emit 'multiclass';(0{::multikernel);'C';fixed 1{::multi
    lines =. lines,framed multicells
    lines =. lines,<emit 'cells class1';(+/multicells=' ');'class2';(+/multicells='.');'class3';(+/multicells=':');'disagree';(+/multicells='?');'points';multipointcount;'outside';multioutside
    lines
)
cv_grid =: 3 : 0
    header =. 'kernel';'C'
    for_i. 1+i.FoldCount do. header =. header,<'fold',integer i end.
    header =. header,;:'correct accuracy support_vectors passes steps'
    lines =. <','join header
    for_result. Combinations do.
        result =. >result
        kernel =. (0{::result){::KernelDefs
        fields =. (<0{::kernel),<fixed 1{::result
        for_fold. 3{::result do. fields =. fields,<integer 2{::>fold end.
        fields =. fields,(<integer 4{::result),(<(4{::result)ratio #TrainY),(<integer 5{::result),(<integer 6{::result),<integer 7{::result
        lines =. lines,<','join fields
    end.
    lines
)
prediction_lines =: 3 : 0
    'pegasosvalues probabilities' =. y
    header =. 'id';'label'
    for_kernel. KernelDefs do. header =. header,<0{::>kernel end.
    header =. header,;:'pegasos predicted probability'
    lines =. <','join header
    selectedvalues =. 2{::(0{::Selected){::Finals
    for_i. i.#TestY do.
        fields =. (<i{::TestIds),<integer i{TestY
        for_final. Finals do. fields =. fields,<fixed i{2{::>final end.
        fields =. fields,(<fixed i{pegasosvalues),(<integer sgn i{selectedvalues),<fixed i{probabilities
        lines =. lines,<','join fields
    end.
    lines
)
main =: 3 : 0
    read_dataset ''
    cross_validate ''
    Finals =: 0$a:
    for_k. i.#Best do.
        result =. k{::Best
        kernel =. k{::KernelDefs
        coefficient =. 1{::result
        matrix =. k{::Matrices
        model =. smo_train (<TrainX),(<TrainY),(<kernel),(<matrix),<coefficient
        Finals =: Finals,<final_evaluation model
    end.
    selectedfinal =. (0{::Selected){::Finals
    sections =. <cv_lines ''
    for_final. Finals do. sections =. sections,<4{::>final end.
    sections =. sections,<training_log 0{::selectedfinal
    sections =. sections,<c_path ''
    sections =. sections,<learning_curve ''
    'a b probabilities calibrationlines' =. calibrate 2{::selectedfinal
    sections =. sections,<calibrationlines
    comparison =. a:
    for_final. Finals do.
        final =. >final
        kernel =. 2{::0{::final
        if. (1{::kernel)-:'linear' do.
            comparison =. final
            break.
        end.
    end.
    'pegasosvalues pegasoslines' =. pegasos comparison
    sections =. sections,<pegasoslines
    sections =. sections,<mcnemar_lines pegasosvalues
    multikernel =. a:
    for_kernel. KernelDefs do.
        kernel =. >kernel
        if. (0{::kernel)-:MultiKernelName do.
            multikernel =. kernel
            break.
        end.
    end.
    multi =. ((<multikernel),<MultiCoefficient)multiclass_train MultiTrain
    modellines =. 0$a:
    for_section. sections do.
        if. #modellines do. modellines =. modellines,<'' end.
        modellines =. modellines,>section
    end.
    'model.txt'write_lines modellines
    'cv_grid.csv'write_lines cv_grid ''
    'predictions.csv'write_lines prediction_lines (<pegasosvalues),<probabilities
    'multiclass.txt'write_lines multiclass_report multi
    'decision_plot.txt'write_lines decision_plots (<a),(<b),<multi
    i.0 0
)
main ''
