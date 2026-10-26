ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
ModelNames =: 'multinomial';'bernoulli';'complement';'rocchio';'vote'
div =: 4 : '_1 x:<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
number =: 3 : 0
    prefix =. ''
    if. y<0 do. prefix =. '-'
        y =. -y end.
    text =. ''
    while. y>0 do. text =. ((10|y){Digits),text
        y =. y div 10 end.
    if. #text do. prefix,text else. '0' end.
)
lower =: 3 : 0
    codes =. a.i.y
    a.{~codes+32*(codes>:65)*.codes<:90
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
        value =. index{::y
        if. 2~:3!:0 value do. value =. number value end.
        text =. text,value
    end.
    text
)
format =: 4 : 0
    parts =. '|' split x
    text =. 0{::parts
    for_index. i.#y do.
        value =. index{::y
        if. 2~:3!:0 value do. value =. number value end.
        text =. text,value,(index+1){::parts
    end.
    text
)
ascii_order =: 3 : '/: > (a.&i.)&.> y'
ascii_sorted =: 3 : '(ascii_order y){y'
sequential_sum =: 3 : 0
    total =. 0.0
    for_value. y do. total =. total+value end.
    total
)
hundredths =: 3 : 0
    'whole fraction' =. '.' split y
    (100*num whole)+num fraction
)
hundredths_text =: 3 : 0
    tail =. number 100|y
    (number y div 100),'.',((2-#tail)$'0'),tail
)
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
load SourceDirectory,'tokenizer.ijs'
load SourceDirectory,'vocabulary.ijs'
load SourceDirectory,'naive_bayes.ijs'
load SourceDirectory,'rocchio.ijs'
load SourceDirectory,'evaluation.ijs'
setting =: 3 : '(SettingNames i.<y){::SettingValues'
integer_setting =: 3 : 'num 0{::setting y'
read_settings =: 3 : 0
    SettingNames =: SettingValues =: 0$a:
    for_line. read_lines 'params.txt' do.
        fields =. ' ' split >line
        SettingNames =: SettingNames,{.fields
        SettingValues =: SettingValues,<}.fields
    end.
    Alphas =: hundredths&>setting 'ALPHAS'
    MinimumDf =: integer_setting 'MIN_DF'
    FeatureCount =: integer_setting 'FEATURES'
    UseBigrams =: 'yes'-:0{::setting 'BIGRAMS'
    TopCount =: integer_setting 'TOP'
    CurveSizes =: num&>setting 'CURVE'
    StudySizes =: num&>setting 'SIZES'
    Thresholds =: hundredths&>setting 'THRESHOLDS'
    Lengths =: num&>setting 'LENGTHS'
    EmIterations =: integer_setting 'EM_ITERATIONS'
    EmWeight =: hundredths 0{::setting 'EM_WEIGHT'
    'Resamples BootstrapSeed' =: num&>setting 'BOOTSTRAP'
    i.0
)
read_documents =: 3 : 0
    Stopwords =: read_lines 'stopwords.txt'
    rows =. 0$a:
    Classes =: 0$a:
    for_line. read_lines 'train.txt' do.
        fields =. TAB split >line
        rows =. rows,<fields
        Classes =: Classes,0{fields
    end.
    Classes =: ascii_sorted ~.Classes
    ClassCount =: #Classes
    TrainingDocuments =: TestDocuments =: UnlabelledDocuments =: 0$a:
    TrainingLabels =: TestLabels =: 0$0
    for_index. i.#rows do.
        'name text' =. index{::rows
        label =. Classes i.<name
        TrainingLabels =: TrainingLabels,label
        TrainingDocuments =: TrainingDocuments,<(<number index+1),(<label),<tokenize_text text
    end.
    for_line. read_lines 'test.txt' do.
        'id name text' =. TAB split >line
        label =. _1
        if. -.name-:'?' do. label =. Classes i.<name end.
        TestLabels =: TestLabels,label
        TestDocuments =: TestDocuments,<(<id),(<label),<tokenize_text text
    end.
    for_line. read_lines 'unlabelled.txt' do.
        UnlabelledDocuments =: UnlabelledDocuments,<(<number 1+#UnlabelledDocuments),(<_1),<tokenize_text >line
    end.
    Labelled =: I.TestLabels>:0
    Truths =: Labelled{TestLabels
    i.0
)
make_training =: 4 : 0
    'bigrams size' =. x
    sequences =. 0$a:
    labels =. 0$0
    for_document. y do.
        document =. >document
        sequences =. sequences,<bigrams token_terms 2{::document
        labels =. labels,1{::document
    end.
    vocabulary =. size build_vocabulary (<sequences),<labels
    encoded =. 0$a:
    for_sequence. sequences do. encoded =. encoded,<vocabulary encode_terms >sequence end.
    counts =. (#3{::vocabulary)training_counts (<encoded),<labels
    rocchio =. (4{::vocabulary)train_rocchio (<encoded),<labels
    (<bigrams),(<vocabulary),(<counts),(<rocchio),<0$a:
)
train_selected =: 3 : 0
    models =. 0$a:
    for_model. i.3 do. models =. models,<model train_nb (2{y),<model{SelectedAlphas end.
    (<models)4}y
)
encode_document =: 4 : 0
    (1{::x)encode_terms (0{::x)token_terms 2{::y
)
classify =: 4 : 0
    'training sequence' =. y
    if. x=3 do. (3{::training)predict_rocchio sequence
    else. (x{::4{::training)predict_nb sequence end.
)
cross_validation_run =: 3 : 0
    evaluation =. TrainingLabels evaluate y
    folds =. 5$0
    for_index. I.TrainingLabels=y do.
        fold =. 5|index
        folds =. (1+fold{folds)fold}folds
    end.
    (<y),(<evaluation),<folds
)
cross_validate =: 3 : 0
    count =. #TrainingDocuments
    predicted =. 0$a:
    for_model. i.4 do.
        rows =. #Alphas
        if. model=3 do. rows =. 1 end.
        predicted =. predicted,<(rows,count)$0
    end.
    Folds =: 0 4$0
    for_fold. i.5 do.
        held =. I.fold=5|i.count
        members =. TrainingDocuments#~fold~:5|i.count
        training =. (UseBigrams,FeatureCount)make_training members
        vocabulary =. 1{::training
        Folds =: Folds,(#members),(#held),(1{::vocabulary),#3{::vocabulary
        sequences =. 0$a:
        for_index. held do. sequences =. sequences,<training encode_document index{::TrainingDocuments end.
        for_model. i.3 do.
            matrix =. model{::predicted
            for_alpha. i.#Alphas do.
                nb =. model train_nb (2{training),<alpha{Alphas
                for_index. i.#held do.
                    posterior =. nb predict_nb index{::sequences
                    matrix =. (0{::posterior)(<alpha,index{held)}matrix
                end.
            end.
            predicted =. (<matrix)model}predicted
        end.
        matrix =. 3{::predicted
        for_index. i.#held do.
            prediction =. (3{::training)predict_rocchio index{::sequences
            matrix =. (0{::prediction)(<0,index{held)}matrix
        end.
        predicted =. (<matrix)3}predicted
    end.
    CrossRuns =: 0$a:
    for_model. i.4 do.
        runs =. 0$a:
        for_labels. model{::predicted do. runs =. runs,<cross_validation_run labels end.
        CrossRuns =: CrossRuns,<runs
    end.
    SelectedAlphas =: 3$0
    SelectedRuns =: 4$0
    for_model. i.3 do.
        runs =. model{::CrossRuns
        best =. 0
        for_index. 1+i.(#runs)-1 do.
            candidate =. decimal_value 4{::1{::index{::runs
            prior =. decimal_value 4{::1{::best{::runs
            if. candidate>prior do. best =. index end.
        end.
        SelectedRuns =: best model}SelectedRuns
        SelectedAlphas =: (best{Alphas)model}SelectedAlphas
    end.
    i.0
)
chosen_run =: 3 : '(y{SelectedRuns){::y{::CrossRuns'
alpha_text =: 3 : 0
    if. y<3 do. hundredths_text y{SelectedAlphas else. '-' end.
)
majority_vote =: 3 : 0
    votes =. ClassCount$0
    for_label. y do. votes =. (1+label{votes)label}votes end.
    winner =. {.y
    for_label. y do. if. (label{votes)>winner{votes do. winner =. label end. end.
    (<winner),(<(winner{votes)%4),(<0$0),(<0$0.0),(<0$0.0),(<0.0),(<0.0),<0
)
train_final =: 3 : 0
    FinalTraining =: train_selected (UseBigrams,FeatureCount)make_training TrainingDocuments
    TestSequences =: 0$a:
    for_document. TestDocuments do. TestSequences =: TestSequences,<FinalTraining encode_document >document end.
    Predictions =: 0$a:
    for_model. i.4 do.
        values =. 0$a:
        for_sequence. TestSequences do. values =. values,<model classify (<FinalTraining),sequence end.
        Predictions =: Predictions,<values
    end.
    votes =. 0$a:
    for_index. i.#TestDocuments do.
        labels =. 0$0
        for_model. i.4 do. labels =. labels,0{::index{::model{::Predictions end.
        votes =. votes,<majority_vote labels
    end.
    Predictions =: Predictions,<votes
    Correct =: (5,#Labelled)$0
    for_model. i.5 do.
        for_position. i.#Labelled do.
            index =. position{Labelled
            label =. 0{::index{::model{::Predictions
            Correct =: (label=position{Truths)(<model,position)}Correct
        end.
    end.
    i.0
)
test_evaluations =: 3 : 0
    sequences =. 0$a:
    for_index. Labelled do. sequences =. sequences,<y encode_document index{::TestDocuments end.
    evaluations =. 0$a:
    for_model. i.4 do.
        labels =. 0$0
        for_sequence. sequences do.
            prediction =. model classify (<y),sequence
            labels =. labels,0{::prediction
        end.
        evaluations =. evaluations,<Truths evaluate labels
    end.
    evaluations
)
evaluation_fields =: 3 : '(2{y),(<real_text 3{::y),<real_text 4{::y'
vocabulary_lines =: 3 : 0
    'terms candidates ranking vocabulary frequencies' =. 1{::FinalTraining
    lines =. <'documents | terms | candidates | vocabulary |' format (<#TrainingDocuments),(<terms),(<candidates),<#vocabulary
    for_index. i.#ranking do.
        'term frequency score class' =. index{::ranking
        lines =. lines,<'| | | | |' format (<index+1),(<term),(<frequency),(<real_text score),class{Classes
    end.
    lines
)
cv_lines =: 3 : 0
    lines =. <'model,alpha,correct,accuracy,macro_f1,selected'
    for_model. i.4 do.
        runs =. model{::CrossRuns
        for_index. i.#runs do.
            alpha =. '-'
            if. model<3 do. alpha =. hundredths_text index{Alphas end.
            selected =. 'no'
            if. index=model{SelectedRuns do. selected =. 'yes' end.
            fields =. (model{ModelNames),(<alpha),(evaluation_fields 1{::index{::runs),<selected
            lines =. lines,<',' join fields
        end.
    end.
    lines
)
prediction_lines =: 3 : 0
    lines =. <'id,model,label,score'
    for_index. i.#TestDocuments do.
        id =. 0{index{::TestDocuments
        for_model. i.5 do.
            prediction =. index{::model{::Predictions
            fields =. id,(model{ModelNames),((0{::prediction){Classes),<real_text 1{::prediction
            lines =. lines,<',' join fields
        end.
    end.
    lines
)
curve_lines =: 3 : 0
    lines =. <'size,vocabulary,model,correct,accuracy,macro_f1'
    for_size. CurveSizes do.
        training =. train_selected (UseBigrams,FeatureCount)make_training size{.TrainingDocuments
        vocabulary =. #3{::1{::training
        evaluations =. test_evaluations training
        for_model. i.4 do.
            fields =. (<size),(<vocabulary),(model{ModelNames),evaluation_fields model{::evaluations
            lines =. lines,<',' join fields
        end.
    end.
    lines
)
feature_lines =: 3 : 0
    lines =. <'terms,features,vocabulary,model,correct,accuracy,macro_f1'
    for_bigrams. 0 1 do.
        kind =. 'unigrams'
        if. bigrams do. kind =. 'bigrams' end.
        for_size. StudySizes do.
            training =. train_selected (bigrams,size)make_training TrainingDocuments
            vocabulary =. #3{::1{::training
            evaluations =. test_evaluations training
            for_model. i.4 do.
                fields =. (<kind),(<size),(<vocabulary),(model{ModelNames),evaluation_fields model{::evaluations
                lines =. lines,<',' join fields
            end.
        end.
    end.
    lines
)
class_counts_text =: 3 : 0
    parts =. 0$a:
    for_label. i.ClassCount do. parts =. parts,(label{Classes),<label{y end.
    ' ' join parts
)
data_part =: 3 : 0
    vocabulary =. 1{::FinalTraining
    terms =. 3{::vocabulary
    lines =. <'documents train | test | labelled | unlabelled | classes |' format (<#TrainingDocuments),(<#TestDocuments),(<#Labelled),(<#UnlabelledDocuments),<ClassCount
    for_label. i.ClassCount do.
        lines =. lines,<'class | train | test |' format (label{Classes),(<+/TrainingLabels=label),<+/Truths=label
    end.
    raw =. stopped =. short =. kept =. bigrams =. 0
    distinct =. 0$a:
    for_document. TrainingDocuments do.
        tokens =. 2{::>document
        raw =. raw+0{::tokens
        stopped =. stopped+1{::tokens
        short =. short+2{::tokens
        kept =. kept+#3{::tokens
        if. UseBigrams do. bigrams =. bigrams+#4{::tokens end.
        distinct =. ~.distinct,UseBigrams token_terms tokens
    end.
    distinctbigrams =. 0
    for_term. distinct do. distinctbigrams =. distinctbigrams+'_'e.>term end.
    lines =. lines,<'train_tokens raw | stopwords | short | unigrams | bigrams |' format (<raw),(<stopped),(<short),(<kept),<bigrams
    lines =. lines,<'train_terms unigrams | bigrams | candidates | vocabulary |' format (<(#distinct)-distinctbigrams),(<distinctbigrams),(1{vocabulary),<#terms
    total =. encoded =. 0
    oov =. 0$a:
    for_index. i.#TestDocuments do.
        tokens =. 2{::index{::TestDocuments
        total =. total+#UseBigrams token_terms tokens
        encoded =. encoded+#index{::TestSequences
        words =. 3{::tokens
        oov =. oov,words#~-.words e.terms
    end.
    lines =. lines,<'test_terms total | in_vocabulary |' format (<total),<encoded
    words =. ascii_sorted ~.oov
    counts =. 0$0
    for_word. words do. counts =. counts,+/word=oov end.
    order =. (TopCount<.#words){./:(-counts),.i.#words
    parts =. <'test_oov'
    for_index. order do. parts =. parts,(index{words),<index{counts end.
    lines,<' ' join parts
)
folds_part =: 3 : 0
    lines =. <'folds 5'
    for_index. i.5 do.
        'train validate candidates size' =. index{Folds
        lines =. lines,<'fold | train | validate | candidates | vocabulary |' format (<index+1),(<train),(<validate),(<candidates),<size
    end.
    lines
)
selection_part =: 3 : 0
    lines =. <'selection'
    for_model. i.4 do.
        'predictions evaluation folds' =. chosen_run model
        line =. '| alpha | correct | macro_f1 | folds |' format (model{ModelNames),(<alpha_text model),(<proportion_text (2{::evaluation),1{::evaluation),(<real_text 4{::evaluation),< ' ' join <"0 folds
        lines =. lines,<line
    end.
    lines
)
cross_part =: 3 : 0
    lines =. <'cross_validation | alpha |' format (y{ModelNames),<alpha_text y
    lines,evaluation_lines 1{::chosen_run y
)
test_part =: 3 : 0
    values =. y{::Predictions
    labels =. 0$0
    top2 =. 0
    for_position. i.#Labelled do.
        prediction =. (position{Labelled){::values
        labels =. labels,0{::prediction
        if. y<4 do. top2 =. top2+(position{Truths)e.2{.2{::prediction end.
    end.
    evaluation =. Truths evaluate labels
    lines =. <'test | alpha |' format (y{ModelNames),<alpha_text y
    lines =. lines,<'labelled | correct |' format (<#Labelled),<proportion_text (2{::evaluation),#Labelled
    if. y<4 do. lines =. lines,<'top2 ',proportion_text top2,#Labelled end.
    lines,evaluation_lines evaluation
)
probability_part =: 3 : 0
    limits =. Thresholds%100
    rows =. hits =. (1+#limits)$0
    sums =. (1+#limits)$0.0
    accepted =. acceptedhits =. (#limits)$0
    loss =. brier =. 0.0
    for_position. i.#Labelled do.
        index =. position{Labelled
        prediction =. index{::y{::Predictions
        'label score ranking scores probabilities normalizer margin runner' =. prediction
        truth =. position{Truths
        right =. (<y,position){Correct
        loss =. loss+((^.normalizer)-((truth{scores)-label{scores))
        squares =. 0.0
        for_class. i.ClassCount do.
            difference =. (class{probabilities)-class=truth
            squares =. squares+difference*difference
        end.
        brier =. brier+squares
        bucket =. +/score>:limits
        rows =. (1+bucket{rows)bucket}rows
        hits =. (right+bucket{hits)bucket}hits
        sums =. (score+bucket{sums)bucket}sums
        for_threshold. I.score>:limits do.
            accepted =. (1+threshold{accepted)threshold}accepted
            acceptedhits =. (right+threshold{acceptedhits)threshold}acceptedhits
        end.
    end.
    lines =. <'probability | alpha |' format (y{ModelNames),<alpha_text y
    lines =. lines,<'log_loss | brier |' format (<real_text loss%#Labelled),<real_text brier%#Labelled
    bounds =. 0,Thresholds
    for_bucket. i.#bounds do.
        count =. bucket{rows
        line =. 'bin | rows |' format (<hundredths_text bucket{bounds),<count
        if. count>0 do. line =. line,' correct ',(proportion_text (bucket{hits),count),' mean ',real_text (bucket{sums)%count end.
        lines =. lines,<line
    end.
    for_index. i.#limits do.
        precise =. '-'
        if. (index{accepted)>0 do. precise =. proportion_text (index{acceptedhits),index{accepted end.
        lines =. lines,<'threshold | covered | correct |' format (<hundredths_text index{Thresholds),(<proportion_text (index{accepted),#Labelled),<precise
    end.
    lines
)
lengths_part =: 3 : 0
    rows =. (1+#Lengths)$0
    hits =. (5,1+#Lengths)$0
    for_position. i.#Labelled do.
        length =. #(position{Labelled){::TestSequences
        bucket =. +/length>:Lengths
        rows =. (1+bucket{rows)bucket}rows
        for_model. i.5 do. hits =. (((<model,bucket){hits)+(<model,position){Correct)(<model,bucket)}hits end.
    end.
    lines =. <'lengths'
    bounds =. 0,Lengths
    for_bucket. i.#bounds do.
        count =. bucket{rows
        line =. 'length | rows |' format (<bucket{bounds),<count
        if. count>0 do.
            for_model. i.5 do. line =. line,' ',(model{::ModelNames),' ',proportion_text ((<model,bucket){hits),count end.
        end.
        lines =. lines,<line
    end.
    lines
)
ModelPairs =: 6 2$0 1 0 2 0 3 1 2 1 3 2 3
comparison_part =: 3 : 0
    lines =. <'comparison'
    for_pair. ModelPairs do.
        'first second' =. pair
        agree =. 0
        for_index. i.#TestDocuments do.
            agree =. agree+(0{::index{::first{::Predictions)=0{::index{::second{::Predictions
        end.
        one =. first{Correct
        other =. second{Correct
        b =. +/one*.-.other
        c =. +/other*.-.one
        if. b+c do. statistic =. fraction_text (*:0>.(|b-c)-1),b+c
        else. statistic =. fraction_text 0 1 end.
        lines =. lines,<'| | agree | b | c | statistic |' format (first{ModelNames),(second{ModelNames),(<proportion_text agree,#TestDocuments),(<b),(<c),<statistic
    end.
    errors =. 5$0
    for_position. i.#Labelled do.
        wrong =. +/-.position{"1 4{.Correct
        errors =. (1+wrong{errors)wrong}errors
    end.
    parts =. <'errors'
    for_wrong. i.5 do. parts =. parts,(<wrong),<wrong{errors end.
    lines,<' ' join parts
)
bootstrap_part =: 3 : 0
    count =. #Labelled
    state =. BootstrapSeed
    totals =. (5,Resamples)$0
    for_sample. i.Resamples do.
        chosen =. 0$0
        for_pick. i.count do.
            state =. 2147483647|48271*state
            chosen =. chosen,count|state
        end.
        for_model. i.5 do. totals =. (+/chosen{model{Correct)(<model,sample)}totals end.
    end.
    rank =. Resamples div 40
    lines =. <'bootstrap resamples | seed |' format (<Resamples),<BootstrapSeed
    for_model. i.5 do.
        ordered =. /:~model{totals
        average =. (+/ordered)%(Resamples*count)
        low =. rank{ordered
        high =. ((#ordered)-(1+rank)){ordered
        lines =. lines,<'| mean | low | high |' format (model{ModelNames),(<real_text average),(<proportion_text low,count),<proportion_text high,count
    end.
    for_pair. ModelPairs do.
        'first second' =. pair
        one =. first{totals
        other =. second{totals
        lines =. lines,<'pair | | wins | ties | losses |' format (first{ModelNames),(second{ModelNames),(<+/one>other),(<+/one=other),<+/one<other
    end.
    lines
)
hard_part =: 3 : 0
    hard =. 0$0
    counts =. ClassCount$0
    for_index. i.#TrainingDocuments do.
        predicted =. 0$0
        for_model. i.4 do. predicted =. predicted,index{0{::chosen_run model end.
        truth =. index{TrainingLabels
        if. *./predicted~:truth do. hard =. hard,index
            counts =. (1+truth{counts)truth}counts end.
    end.
    lines =. <'hard_documents | |' format (<#hard),<class_counts_text counts
    for_index. (TopCount<.#hard){.hard do.
        labels =. 0$a:
        for_model. i.4 do. label =. index{0{::chosen_run model
            labels =. labels,label{Classes end.
        lines =. lines,<'| true | predicted |' format (<index+1),((index{TrainingLabels){Classes),< ' ' join labels
    end.
    lines
)
uncertain_part =: 3 : 0
    values =. 0{::Predictions
    margins =. 0$0.0
    for_prediction. values do. margins =. margins,6{::>prediction end.
    order =. (TopCount<.#values){./:(decimal_value margins),.i.#values
    lines =. <'uncertain multinomial ',number #order
    for_index. order do.
        prediction =. index{::values
        document =. index{::TestDocuments
        truth =. '?'
        if. (index{TestLabels)>:0 do. truth =. (index{TestLabels){::Classes end.
        lines =. lines,<'| predicted | runner_up | margin | posterior | true |' format (0{document),((0{::prediction){Classes),((7{::prediction){Classes),(<real_text 6{::prediction),(<real_text 1{::prediction),<truth
    end.
    lines
)
ratio_order =: 3 : 0
    order =. 0$0
    for_index. i.#y do.
        row =. index{y
        position =. #order
        for_prior. i.#order do.
            other =. (prior{order){y
            left =. (0{row)*1{other
            right =. (0{other)*1{row
            if. (left>right)+.(left=right)*.((2{row)<2{other) do. position =. prior break. end.
        end.
        order =. (position{.order),index,position}.order
    end.
    order
)
misclassified_part =: 3 : 0
    wrong =. Labelled#~-.0{Correct
    lines =. <'misclassified multinomial ',number #wrong
    alpha =. 0{SelectedAlphas
    occurrences =. 2{::2{::FinalTraining
    weights =. 3{::0{::4{::FinalTraining
    terms =. 3{::1{::FinalTraining
    for_index. wrong do.
        prediction =. index{::0{::Predictions
        document =. index{::TestDocuments
        predicted =. 0{::prediction
        truth =. index{TestLabels
        lines =. lines,<'| true | predicted | posterior |' format (0{document),(truth{Classes),(predicted{Classes),<real_text 1{::prediction
        sequence =. index{::TestSequences
        entries =. 0 3$0
        for_term. ~.sequence do.
            numerator =. alpha+100*(<predicted,term){occurrences
            denominator =. alpha+100*(<truth,term){occurrences
            entries =. entries,numerator,denominator,term
        end.
        order =. (3<.#entries){.ratio_order entries
        for_position. order do.
            term =. (<position,2){entries
            value =. ((<predicted,term){weights)-(<truth,term){weights
            lines =. lines,<'  | count | evidence |' format (term{terms),(<+/sequence=term),<real_text value
        end.
    end.
    lines
)
maximization =: 4 : 0
    counts =. 2{::FinalTraining
    occurrences =. 0.0+2{::counts
    documents =. 0.0+1{::counts
    weight =. EmWeight%100
    for_index. i.#y do.
        posterior =. index{::x
        sequence =. index{::y
        probabilities =. 4{::posterior
        first =. ~.sequence
        for_label. i.ClassCount do.
            share =. weight*label{probabilities
            documents =. (share+label{documents)label}documents
            for_term. first do.
                frequency =. +/sequence=term
                occurrences =. (((<label,term){occurrences)+share*frequency)(<label,term)}occurrences
            end.
        end.
    end.
    alpha =. 0{SelectedAlphas
    size =. #3{::1{::FinalTraining
    weights =. (ClassCount,size)$0.0
    for_label. i.ClassCount do.
        total =. sequential_sum label{occurrences
        for_term. i.size do.
            value =. smoothed_log ((<label,term){occurrences),total,alpha,size
            weights =. value (<label,term)}weights
        end.
    end.
    scale =. (#TrainingDocuments)+(EmWeight*#UnlabelledDocuments)%100
    priors =. ^.documents%scale
    (<0),(<priors),(<ClassCount$0.0),<weights
)
semi_supervised_part =: 3 : 0
    sequences =. 0$a:
    for_document. UnlabelledDocuments do. sequences =. sequences,<FinalTraining encode_document >document end.
    model =. 0{::4{::FinalTraining
    lines =. <'semi_supervised multinomial alpha | weight | unlabelled |' format (<alpha_text 0),(<hundredths_text EmWeight),<#UnlabelledDocuments
    previous =. 0$0
    for_iteration. i.EmIterations+1 do.
        posteriors =. 0$a:
        assignments =. predicted =. 0$0
        assigned =. ClassCount$0
        for_sequence. sequences do.
            posterior =. model predict_nb >sequence
            posteriors =. posteriors,<posterior
            label =. 0{::posterior
            assignments =. assignments,label
            assigned =. (1+label{assigned)label}assigned
        end.
        for_index. Labelled do.
            posterior =. model predict_nb index{::TestSequences
            predicted =. predicted,0{::posterior
        end.
        evaluation =. Truths evaluate predicted
        changed =. '-'
        if. iteration>0 do. changed =. number +/previous~:assignments end.
        lines =. lines,<'iteration | correct | macro_f1 | changed | assigned |' format (<iteration),(<proportion_text (2{::evaluation),#Labelled),(<real_text 4{::evaluation),(<changed),<class_counts_text assigned
        if. iteration<EmIterations do. model =. posteriors maximization sequences end.
        previous =. assignments
    end.
    lines
)
join_parts =: 3 : 0
    lines =. 0$a:
    for_part. y do.
        if. #lines do. lines =. lines,<'' end.
        lines =. lines,>part
    end.
    lines
)
metrics_lines =: 3 : 0
    parts =. (<data_part ''),(<folds_part ''),<selection_part ''
    for_model. i.4 do. parts =. parts,<cross_part model end.
    for_model. i.5 do. parts =. parts,<test_part model end.
    for_model. i.3 do. parts =. parts,<probability_part model end.
    parts =. parts,(<lengths_part ''),(<comparison_part ''),(<bootstrap_part ''),(<hard_part ''),(<uncertain_part ''),(<misclassified_part ''),<semi_supervised_part ''
    join_parts parts
)
top_feature_lines =: 3 : 0
    counts =. 2{::FinalTraining
    terms =. 3{::1{::FinalTraining
    size =. #terms
    parts =. 0$a:
    for_model. i.2 do.
        alpha =. model{SelectedAlphas
        if. model=0 do. table =. 2{::counts
            totals =. 4{::counts
            overall =. 6{::counts
            outcomes =. size
        else. table =. 3{::counts
            totals =. 1{::counts
            overall =. 0{::counts
            outcomes =. 2 end.
        termtotals =. +/table
        heading =. 'model | alpha | vocabulary | top |' format (model{ModelNames),(<alpha_text model),(<size),<TopCount
        parts =. parts,<<heading
        for_label. i.ClassCount do.
            total =. label{totals
            other =. overall-total
            lines =. <'class | total | other |' format (label{Classes),(<total),<other
            entries =. 0 3$0
            for_term. i.size do.
                count =. (<label,term){table
                othercount =. (term{termtotals)-count
                entries =. entries,(alpha+100*count),(alpha+100*othercount),term
            end.
            order =. (TopCount<.size){.ratio_order entries
            for_rank. i.#order do.
                term =. (<(rank{order),2){entries
                count =. (<label,term){table
                othercount =. (term{termtotals)-count
                value =. (smoothed_log count,total,alpha,outcomes)-smoothed_log othercount,other,alpha,outcomes
                lines =. lines,<'| | | | |' format (<rank+1),(term{terms),(<count),(<othercount),<real_text value
            end.
            parts =. parts,<lines
        end.
    end.
    join_parts parts
)
write_lines =: 4 : 0
    ((LF join y),LF)1!:2 <'output/',x
    i.0
)
main =: 3 : 0
    read_settings ''
    read_documents ''
    cross_validate ''
    train_final ''
    1!:5 ::0: <'output'
    'vocabulary.txt' write_lines vocabulary_lines ''
    'cv_results.csv' write_lines cv_lines ''
    'predictions.csv' write_lines prediction_lines ''
    'learning_curve.csv' write_lines curve_lines ''
    'feature_study.csv' write_lines feature_lines ''
    'metrics.txt' write_lines metrics_lines ''
    'top_features.txt' write_lines top_feature_lines ''
    i.0
)
main ''
