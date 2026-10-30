load 'model_io.ijs'
load 'inference.ijs'
load 'training.ijs'
load 'evaluation.ijs'
load 'sampler.ijs'
uppercase =: 3 : 0
    codes =. a.i.y
    codes =. codes-32*(codes>:97)*.codes<:122
    codes{a.
)
lowercase_symbol =: 3 : 'a.{~32+a.i.y'
yes_no =: 3 : 'y{::;:''no yes'''
join_blocks =: 3 : 0
    result =. 0$a:
    for_j. i.#y do.
        if. j do.
            result =. result,<''
        end.
        result =. result,j{::y
    end.
    result
)
record_observations =: 3 : 0
    result =. 0$a:
    for_record. y do.
        result =. result,1{>record
    end.
    result
)
record_paths =: 3 : 0
    result =. 0$a:
    for_record. y do.
        result =. result,2{>record
    end.
    result
)
positions =: 3 : 0
    total =. 0
    for_record. y do.
        total =. total+#1{::>record
    end.
    total
)
rejection =: 4 : 0
    'seen observations labels labeled' =. x
    name =. y
    if. (<name)e.seen do.
        (<seen),<'duplicate name' return.
    end.
    seen =. seen,<name
    for_t. i.#observations do.
        character =. t{observations
        if. (-.character e.Symbols)*.character~:Missing do.
            (<seen),<'invalid symbol ',character,' at position ',integer t+1 return.
        end.
    end.
    if. labeled do.
        for_t. i.#labels do.
            character =. t{labels
            if. -.character e.States do.
                (<seen),<'invalid label ',character,' at position ',integer t+1 return.
            end.
        end.
        if. (#observations)~:#labels do.
            (<seen),<'length mismatch ',(integer #observations),' ',integer #labels return.
        end.
    end.
    if. (#observations)<MinimumSequenceLength do.
        (<seen),<'too short ',integer #observations return.
    end.
    missing =. +/observations=Missing
    if. (100*missing)>MaximumMissingPercent*#observations do.
        (<seen),<'too many missing ',integer missing return.
    end.
    (<seen),<''
)
encode_observations =: 3 : 0
    result =. Symbols i.y
    _1 (I.y=Missing)}result
)
validate =: 3 : 0
    Sequences =: 0$a:
    TrainRecords =: 0$a:
    TestRecords =: 0$a:
    Rejections =: 0$a:
    seen =. 0$a:
    for_j. i.#SequenceRows do.
        'name raw' =. j{::SequenceRows
        observations =. uppercase raw
        'seen reason' =. ((<seen),(<observations),(<'') ,<0)rejection name
        if. #reason do.
            Rejections =: Rejections,<'REJECT sequences.txt line ',(integer j+1),' ',name,' ',reason
        else.
            Sequences =: Sequences,<(<name),(<encode_observations observations),<i.0
        end.
    end.
    seen =. 0$a:
    for_j. 2*i.(#LabeledRows)intdiv 2 do.
        'name role raw' =. j{::LabeledRows
        observations =. uppercase raw
        labels =. 0{::(j+1){::LabeledRows
        'seen reason' =. ((<seen),(<observations),(<labels),<1)rejection name
        if. #reason do.
            Rejections =: Rejections,<'REJECT labeled.txt line ',(integer j+1),' ',name,' ',reason
            continue.
        end.
        record =. (<name),(<encode_observations observations),<States i.labels
        if. role-:'TRAIN' do.
            TrainRecords =: TrainRecords,<record
        else.
            TestRecords =: TestRecords,<record
        end.
    end.
    i.0
)
viterbi_paths =: 4 : 0
    paths =. 0$a:
    total =. 0.0
    for_sequence. y do.
        'path logprob' =. x viterbi >sequence
        paths =. paths,<path
        total =. total+logprob
    end.
    (<paths),<total
)
count_records =: 4 : 0
    estimate_by_counting (<Initial),(<record_observations y),(<record_paths y),<x
)
train_unsupervised =: 3 : 0
    Unlabeled =: record_observations Sequences
    heldout =. record_observations TrainRecords,TestRecords
    current =. Initial
    previous_loglik =. current total_loglik Unlabeled
    FirstLoglik =: previous_loglik
    best_heldout =. current total_loglik heldout
    BestIteration =: 0
    Violations =: 0
    BaumTrace =: (<'iteration,loglik,heldout,change,max_change,status'),<'0,',(real_text FirstLoglik),',',(real_text best_heldout),',,,'
    for_iteration. 1+i.Iterations do.
        updated =. baum_welch_step (<current),(<Unlabeled),<Pseudocount
        loglik =. updated total_loglik Unlabeled
        heldout_loglik =. updated total_loglik heldout
        max_change =. 0.0
        for_row. i.#current do.
            max_change =. max_change>.>./,|(row{::updated)-row{::current
        end.
        violation =. loglik<previous_loglik-0.000001*|previous_loglik
        Violations =: Violations+violation
        if. heldout_loglik>best_heldout do.
            best_heldout =. heldout_loglik
            BestIteration =: iteration
        end.
        status =. 'ok'
        if. violation do.
            status =. 'violation'
        end.
        BaumTrace =: BaumTrace,<(integer iteration),',',(real_text loglik),',',(real_text heldout_loglik),',',(real_text loglik-previous_loglik),',',(6 decimal max_change),',',status
        current =. updated
        previous_loglik =. loglik
    end.
    FinalLoglik =: previous_loglik
    Models =: (<Initial),<current
    current =. Initial
    'paths logprob' =. current viterbi_paths Unlabeled
    ViterbiTrace =: (<'iteration,logprob,loglik,changed'),<'0,',(real_text logprob),',',(real_text FirstLoglik),','
    ViterbiIterations =: 0
    Converged =: 0
    for_iteration. 1+i.Iterations do.
        current =. estimate_by_counting (<Initial),(<Unlabeled),(<paths),<Pseudocount
        'next_paths next_logprob' =. current viterbi_paths Unlabeled
        changed =. 0
        for_j. i.#paths do.
            changed =. changed+(#j{::paths)-(j{::paths)correct_count j{::next_paths
        end.
        loglik =. current total_loglik Unlabeled
        ViterbiTrace =: ViterbiTrace,<(integer iteration),',',(real_text next_logprob),',',(real_text loglik),',',integer changed
        paths =. next_paths
        ViterbiIterations =: iteration
        Converged =: changed=0
        if. Converged do.
            break.
        end.
    end.
    Models =: Models,<current
    i.0
)
train_supervised =: 3 : 0
    TrainPositions =: positions TrainRecords
    TestPositions =: positions TestRecords
    Candidates =: 0$a:
    SelectedCandidate =: 0
    for_candidate. Smoothing do.
        candidate =. >candidate
        matrix =. confusion_matrix #States
        fold_results =. 0 3$0
        total_correct =. 0
        for_fold. i.Folds do.
            indices =. i.#TrainRecords
            fitting =. TrainRecords#~fold~:Folds|indices
            validating =. TrainRecords#~fold=Folds|indices
            model =. (".candidate)count_records fitting
            fold_positions =. 0
            fold_correct =. 0
            for_record. validating do.
                record =. >record
                'path logprob' =. model viterbi 1{::record
                fold_positions =. fold_positions+#path
                fold_correct =. fold_correct+(2{::record)correct_count path
                matrix =. matrix accumulate_confusion (2{record),<path
            end.
            total_correct =. total_correct+fold_correct
            fold_results =. fold_results,(#validating),fold_positions,fold_correct
        end.
        Candidates =: Candidates,<(<candidate),(<total_correct),(<fold_results),<matrix
        last =. <:#Candidates
        if. total_correct>1{::SelectedCandidate{::Candidates do.
            SelectedCandidate =: last
        end.
    end.
    selected =. SelectedCandidate{::Candidates
    alpha =. ".0{::selected
    Models =: Models,<alpha count_records TrainRecords
    CvLines =: <'CROSS_VALIDATION folds ',integer Folds
    for_candidate. Candidates do.
        'name correct fold_results matrix' =. >candidate
        CvLines =: CvLines,<'SMOOTHING ',name,' positions ',(integer TrainPositions),' correct ',(integer correct),' accuracy ',correct fraction TrainPositions
    end.
    CvLines =: CvLines,<'SELECTED ',0{::selected
    fold_results =. 2{::selected
    for_fold. i.Folds do.
        'records total correct' =. fold{fold_results
        CvLines =: CvLines,<'FOLD ',(integer fold+1),' records ',(integer records),' positions ',(integer total),' correct ',(integer correct),' accuracy ',correct fraction total
    end.
    CvLines =: CvLines,(States matrix_lines 3{::selected),States metric_lines 3{::selected
    LearningLines =: <'LEARNING_CURVE'
    for_count. 1+i.#TrainRecords do.
        model =. alpha count_records count{.TrainRecords
        correct =. 0
        for_record. TestRecords do.
            record =. >record
            'path logprob' =. model viterbi 1{::record
            correct =. correct+(2{::record)correct_count path
        end.
        LearningLines =: LearningLines,<'RECORDS ',(integer count),' correct ',(integer correct),' accuracy ',correct fraction TestPositions
    end.
    i.0
)
segments =: 3 : 0
    merged =. 0 2$0
    for_run. runs y do.
        if. (0{run)~:SegmentState do.
            continue.
        end.
        last =. <:#merged
        combine =. 0
        if. last>:0 do.
            gap =. ((1{run)-(<last,1){merged)-1
            combine =. gap<:MergeGap
        end.
        if. combine do.
            merged =. (2{run)(<last,1)}merged
        else.
            merged =. merged,1 2{run
        end.
    end.
    merged#~MinimumSegmentLength<:1+(1{"1 merged)-0{"1 merged
)
composition =: 4 : 0
    observed =. 0
    rich =. 0
    first =. 0
    second =. 0
    pairs =. 0
    'start finish' =. y
    for_t. start+i.1+finish-start do.
        symbol =. t{x
        if. symbol~:_1 do.
            observed =. observed+1
            rich =. rich+symbol e.RichSymbols
            first =. first+symbol=0{Motif
            second =. second+symbol=1{Motif
        end.
        if. t<finish do.
            pairs =. pairs+(symbol=0{Motif)*.(1{Motif)=(t+1){x
        end.
    end.
    rich_fraction =. '-'
    pair_ratio =. '-'
    if. observed do.
        rich_fraction =. real_text rich%observed
    end.
    if. first*second do.
        pair_ratio =. real_text (pairs*observed)%(first*second)
    end.
    island =. (first*second)>0
    island =. island*.(100*rich)>:MinimumRichPercent*observed
    island =. island*.(100*pairs*observed)>:MinimumMotifPercent*first*second
    (<rich_fraction),(<pair_ratio),<island
)
evaluate =: 3 : 0
    EvaluationBlocks =: 0$a:
    Scores =: 0 2$0
    Decoded =: 0$a:
    for_model_index. i.#Models do.
        model =. model_index{::Models
        results =. 0$a:
        for_record. TestRecords do.
            results =. results,<model decode 1{::>record
        end.
        totals =. i.0
        for_decoder. i.2 do.
            name =. decoder{::;:'VITERBI POSTERIOR'
            matrix =. confusion_matrix #States
            regions =. 4$0
            boundaries =. 4$0
            calibration =. 10 2$0
            record_lines =. 0$a:
            total_correct =. 0
            for_j. i.#TestRecords do.
                record =. j{::TestRecords
                result =. j{::results
                path =. (2*decoder){::result
                truth =. 2{::record
                correct =. truth correct_count path
                total_correct =. total_correct+correct
                matrix =. matrix accumulate_confusion (<truth),<path
                true_regions =. 0 2$0
                for_run. runs truth do.
                    if. SegmentState=0{run do.
                        true_regions =. true_regions,1 2{run
                    end.
                end.
                regions =. regions+(segments path)region_counts true_regions
                boundaries =. boundaries+boundary_counts (<path),(<truth),<BoundaryTolerance
                if. decoder do.
                    confidence =. 3{::result
                    for_t. i.#path do.
                        bucket =. 9<.<.10.0*t{confidence
                        calibration =. (1+(<bucket,0){calibration)(<bucket,0)}calibration
                        if. (t{path)=t{truth do.
                            calibration =. (1+(<bucket,1){calibration)(<bucket,1)}calibration
                        end.
                    end.
                end.
                record_lines =. record_lines,<'RECORD ',(0{::record),' length ',(integer #path),' correct ',integer correct
            end.
            block =. <'EVALUATION ',(model_index{::ModelNames),' ',name
            block =. block,(States matrix_lines matrix),States metric_lines matrix
            block =. block,<'REGIONS ',(SegmentState{States),' predicted ',(integer 0{regions),' true ',(integer 1{regions),' precision ',((2{regions)fraction 0{regions),' recall ',(3{regions)fraction 1{regions
            block =. block,<'BOUNDARIES predicted ',(integer 0{boundaries),' true ',(integer 1{boundaries),' precision ',((2{boundaries)fraction 0{boundaries),' recall ',(3{boundaries)fraction 1{boundaries
            if. decoder do.
                for_bucket. i.10 do.
                    'total correct' =. bucket{calibration
                    if. total do.
                        range =. '0.',(integer bucket),'-0.',integer bucket+1
                        if. bucket=9 do.
                            range =. '0.9-1.0'
                        end.
                        block =. block,<'CALIBRATION ',range,' positions ',(integer total),' correct ',(integer correct),' accuracy ',correct fraction total
                    end.
                end.
            end.
            EvaluationBlocks =: EvaluationBlocks,<block,record_lines
            totals =. totals,total_correct
        end.
        Scores =: Scores,totals
        results =. 0$a:
        for_record. Sequences do.
            results =. results,<model decode 1{::>record
        end.
        Decoded =: Decoded,<results
    end.
    EvaluationBlocks =: EvaluationBlocks,(<CvLines),<LearningLines
    i.0
)
path_text =: 4 : 'y{x'
annotate =: 3 : 0
    model =. 1{::Models
    emission =. 2{::model
    seed =. PosteriorSeed
    decoding_lines =. 0$a:
    segment_lines =. <'sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island'
    results =. 1{::Decoded
    for_j. i.#Sequences do.
        record =. j{::Sequences
        'name sequence truth' =. record
        'viterbi_path logprob posterior_path_value confidence fb' =. j{::results
        gamma =. 4{::fb
        samples =. 0$a:
        sample_segments =. 0
        for_sample. i.PosteriorSamples do.
            'path seed' =. model posterior_path (0{fb),<seed
            samples =. samples,<path
            sample_segments =. sample_segments+#segments path
        end.
        uncertain =. 0
        confident =. ''
        imputed =. ''
        for_t. i.#sequence do.
            if. (t{confidence)<Confidence do.
                uncertain =. uncertain+1
                confident =. confident,'.'
            else.
                confident =. confident,(t{posterior_path_value){States
            end.
            observation =. t{sequence
            if. observation~:_1 do.
                imputed =. imputed,observation{Symbols
            else.
                probabilities =. i.0
                for_symbol. i.#Symbols do.
                    total =. 0.0
                    for_state. i.#States do.
                        total =. total+((<t,state){gamma)*(<state,symbol){emission
                    end.
                    probabilities =. probabilities,total
                end.
                imputed =. imputed,lowercase_symbol (maximum_index probabilities){Symbols
            end.
        end.
        differences =. (#sequence)-viterbi_path correct_count posterior_path_value
        decoding_lines =. decoding_lines,(<'SEQUENCE ',name,' length ',(integer #sequence),' loglik ',(real_text 5{::fb),' viterbi ',(real_text logprob),' differences ',(integer differences),' uncertain ',(integer uncertain),' expected_segments ',real_text sample_segments%PosteriorSamples),(<'VITERBI ',States path_text viterbi_path),(<'POSTERIOR ',States path_text posterior_path_value),(<'CONFIDENT ',confident),<'IMPUTED ',imputed
        for_decoder. i.2 do.
            decoder_name =. decoder{::;:'viterbi posterior'
            path =. viterbi_path
            if. decoder do.
                path =. posterior_path_value
            end.
            for_segment. segments path do.
                'start finish' =. segment
                length =. 1+finish-start
                total =. 0.0
                for_t. start+i.length do.
                    total =. total+(<t,SegmentState){gamma
                end.
                support =. 0
                for_sample. samples do.
                    count =. +/SegmentState=(start+i.length){>sample
                    support =. support+(2*count)>length
                end.
                'rich ratio island' =. sequence composition segment
                fields =. (<name),(<decoder_name),(<integer start+1),(<integer finish+1),(<integer length),(<real_text total%length),(<integer support),(<rich),(<ratio),<yes_no island
                segment_lines =. segment_lines,<','join fields
            end.
        end.
    end.
    'decodings.txt'write_lines decoding_lines
    'segments.csv'write_lines segment_lines
)
synthetic_output =: 3 : 0
    model =. 1{::Models
    seed =. SampleSeed
    rows =. 0$a:
    total_positions =. 0
    viterbi_total =. 0
    posterior_total =. 0
    for_number. 1+i.SampleCount do.
        'truth sequence seed' =. model synthetic_sequence SampleLength,seed
        'path logprob posterior_path_value confidence fb' =. model decode sequence
        vc =. truth correct_count path
        pc =. truth correct_count posterior_path_value
        total_positions =. total_positions+#truth
        viterbi_total =. viterbi_total+vc
        posterior_total =. posterior_total+pc
        rows =. rows,(<'SAMPLE ',(integer number),' loglik ',(real_text 5{::fb),' viterbi ',(real_text logprob),' viterbi_correct ',(integer vc),' posterior_correct ',integer pc),(<'STATES ',States path_text truth),(<'SYMBOLS ',Symbols path_text sequence),(<'VITERBI ',States path_text path),<'POSTERIOR ',States path_text posterior_path_value
    end.
    rows =. rows,<'TOTAL positions ',(integer total_positions),' viterbi_accuracy ',(viterbi_total fraction total_positions),' posterior_accuracy ',posterior_total fraction total_positions
    'samples.txt'write_lines rows
)
path_statistics =: 3 : 0
    counts =. (#States)$0
    run_counts =. counts
    total =. 0
    for_path. y do.
        path =. >path
        total =. total+#path
        for_run. runs path do.
            state =. 0{run
            counts =. ((state{counts)+1+(2{run)-1{run)state}counts
            run_counts =. (1+state{run_counts)state}run_counts
        end.
    end.
    (<counts),(<run_counts),<total
)
mean_text =: 4 : 0
    if. y=0 do.
        '-'
    else.
        real_text x%y
    end.
)
input_report =: 3 : 0
    labeled =. TrainRecords,TestRecords
    total_positions =. positions Sequences
    missing =. 0
    labeled_missing =. 0
    symbols =. (#Symbols)$0
    for_record. Sequences do.
        for_symbol. 1{::>record do.
            if. symbol=_1 do.
                missing =. missing+1
            else.
                symbols =. (1+symbol{symbols)symbol}symbols
            end.
        end.
    end.
    for_record. labeled do.
        labeled_missing =. labeled_missing++/_1=1{::>record
    end.
    rows =. (<'INPUT'),(<'SEQUENCES accepted ',(integer #Sequences),' rejected ',(integer (#SequenceRows)-#Sequences),' positions ',(integer total_positions),' missing ',integer missing),<'LABELED train ',(integer #TrainRecords),' test ',(integer #TestRecords),' rejected ',(integer ((#LabeledRows)intdiv 2)-#labeled),' positions ',(integer positions labeled),' missing ',integer labeled_missing
    rows =. rows,Rejections
    line =. 'COMPOSITION'
    for_symbol. i.#Symbols do.
        line =. line,' ',(symbol{Symbols),' ',real_text (symbol{symbols)%(total_positions-missing)
    end.
    rows =. rows,<line
    for_role. i.2 do.
        records =. TrainRecords
        if. role do.
            records =. TestRecords
        end.
        name =. role{::;:'TRAIN TEST'
        'counts run_counts total' =. path_statistics record_paths records
        for_state. i.#States do.
            rows =. rows,<'TRUTH ',name,' ',(state{States),' occupancy ',(real_text (state{counts)%total),' mean_run ',(state{counts)mean_text state{run_counts
        end.
    end.
    rows
)
training_report =: 3 : 0
    selected =. SelectedCandidate{::Candidates
    rows =. (<'TRAINING BAUM_WELCH iterations ',(integer Iterations),' initial_loglik ',(real_text FirstLoglik),' final_loglik ',(real_text FinalLoglik),' violations ',(integer Violations),' best_heldout_iteration ',integer BestIteration),(<'TRAINING VITERBI_TRAINING iterations ',(integer ViterbiIterations),' converged ',yes_no Converged),<'TRAINING SUPERVISED smoothing ',0{::selected
    preferences =. 4$0
    for_j. i.#Sequences do.
        likelihoods =. i.0
        for_k. i.4 do.
            result =. j{::k{::Decoded
            likelihoods =. likelihoods,5{::4{::result
        end.
        chosen =. maximum_index likelihoods
        preferences =. (1+chosen{preferences)chosen}preferences
    end.
    line =. 'PREFERENCE'
    for_k. i.4 do.
        line =. line,' ',(k{::ModelNames),' ',integer k{preferences
    end.
    rows =. rows,<line
    total =. positions Sequences
    for_first. i.3 do.
        for_second. (first+1)+i.4-(first+1) do.
            correct =. 0
            for_j. i.#Sequences do.
                a =. 0{::j{::first{::Decoded
                b =. 0{::j{::second{::Decoded
                correct =. correct+a correct_count b
            end.
            rows =. rows,<'AGREEMENT ',(first{::ModelNames),' ',(second{::ModelNames),' ',correct fraction total
        end.
    end.
    for_decoder. i.2 do.
        totals =. decoder{"1 Scores
        best =. maximum_index totals
        name =. decoder{::;:'VITERBI POSTERIOR'
        rows =. rows,<'BEST ',name,' ',(best{::ModelNames),' accuracy ',(best{totals)fraction TestPositions
    end.
    rows
)
stationary =: 3 : 0
    transition =. 1{::y
    count =. #transition
    matrix =. (0,count+1)$0.0
    for_equation. i.count-1 do.
        row =. equation{"1 transition
        row =. ((equation{row)-1.0)equation}row
        matrix =. matrix,row,0.0
    end.
    matrix =. matrix,(count+1)$1.0
    for_column. i.count do.
        pivot =. column
        for_row. column+i.count-column do.
            if. (|(<row,column){matrix)>|(<pivot,column){matrix do.
                pivot =. row
            end.
        end.
        temporary =. column{matrix
        matrix =. (pivot{matrix)column}matrix
        matrix =. temporary pivot}matrix
        divisor =. (<column,column){matrix
        for_j. column+i.1+count-column do.
            matrix =. (((<column,j){matrix)%divisor)(<column,j)}matrix
        end.
        for_row. i.count do.
            if. row=column do.
                continue.
            end.
            factor =. (<row,column){matrix
            for_j. column+i.1+count-column do.
                value =. ((<row,j){matrix)-factor*(<column,j){matrix
                matrix =. value (<row,j)}matrix
            end.
        end.
    end.
    count{"1 matrix
)
permutations =: 4 : 0
    prefix =. x
    if. (#prefix)=y do.
        ,<prefix return.
    end.
    result =. 0$a:
    for_k. i.y do.
        if. -.k e.prefix do.
            result =. result,(prefix,k)permutations y
        end.
    end.
    result
)
alignment =: 3 : 0
    matrix =. confusion_matrix #States
    for_record. TrainRecords do.
        record =. >record
        'path logprob' =. y viterbi 1{::record
        matrix =. matrix accumulate_confusion (2{record),<path
    end.
    best =. i.0
    best_correct =. _1
    for_permutation. (i.0)permutations #States do.
        permutation =. >permutation
        correct =. 0
        for_j. i.#States do.
            correct =. correct+(<(j{permutation),j){matrix
        end.
        if. correct>best_correct do.
            best_correct =. correct
            best =. permutation
        end.
    end.
    line =. 'ALIGNMENT'
    for_j. i.#States do.
        line =. line,' ',(j{States),'=',(j{best){States
    end.
    line,' agreement ',best_correct fraction TrainPositions
)
model_report =: 3 : 0
    model =. y{::Models
    results =. y{::Decoded
    transition =. 1{::model
    loglik =. 0.0
    observed =. 0
    segment_count =. 0
    segment_length =. 0
    islands =. 0
    paths =. 0$a:
    for_j. i.#Sequences do.
        sequence =. 1{::j{::Sequences
        result =. j{::results
        fb =. 4{::result
        loglik =. loglik+5{::fb
        path =. 0{::result
        paths =. paths,<path
        observed =. observed++/sequence~:_1
        for_segment. segments path do.
            segment_count =. segment_count+1
            segment_length =. segment_length+1+(1{segment)-0{segment
            details =. sequence composition segment
            islands =. islands+2{::details
        end.
    end.
    'counts run_counts total' =. path_statistics paths
    phi =. stationary model
    test_loglik =. model total_loglik record_observations TestRecords
    rows =. (<'MODEL ',y{::ModelNames),(<'LOGLIK unlabeled ',(real_text loglik),' per_symbol ',(real_text loglik%observed),' test ',real_text test_loglik),(<'SEGMENTS count ',(integer segment_count),' mean_length ',(segment_length mean_text segment_count),' islands ',integer islands),<alignment model
    for_state. i.#States do.
        duration =. 1.0%1.0-(<state,state){transition
        rows =. rows,<'STATE ',(state{States),' stationary ',(real_text state{phi),' duration ',(real_text duration),' occupancy ',(real_text (state{counts)%total),' mean_run ',(state{counts)mean_text state{run_counts
    end.
    rows
)
run =: 3 : 0
    'States Symbols Missing Initial SequenceRows LabeledRows Params' =: read_inputs ''
    Iterations =: ".1{::0{::Params
    Pseudocount =: ".1{::1{::Params
    Smoothing =: }.2{::Params
    Folds =: ".1{::3{::Params
    MinimumSequenceLength =: ".1{::4{::Params
    MaximumMissingPercent =: ".1{::5{::Params
    SegmentState =: States i.1{::6{::Params
    MergeGap =: ".1{::7{::Params
    MinimumSegmentLength =: ".1{::8{::Params
    Motif =: Symbols i.;}.9{::Params
    RichSymbols =: Symbols i.;}.10{::Params
    MinimumRichPercent =: ".1{::11{::Params
    MinimumMotifPercent =: ".1{::12{::Params
    Confidence =: ".1{::13{::Params
    BoundaryTolerance =: ".1{::14{::Params
    PosteriorSeed =: x:".1{::15{::Params
    PosteriorSamples =: ".1{::16{::Params
    SampleSeed =: x:".1{::17{::Params
    SampleCount =: ".1{::18{::Params
    SampleLength =: ".1{::19{::Params
    ModelNames =: ;:'INITIAL BAUM_WELCH VITERBI_TRAINING SUPERVISED'
    validate ''
    train_unsupervised ''
    train_supervised ''
    evaluate ''
    annotate ''
    synthetic_output ''
    trained =. 0$a:
    for_j. 1 2 3 do.
        trained =. trained,<(j{::ModelNames)model_lines j{::Models
    end.
    'trained_model.txt'write_lines join_blocks trained
    'loglik_trace.csv'write_lines BaumTrace
    'viterbi_trace.csv'write_lines ViterbiTrace
    'evaluation.txt'write_lines join_blocks EvaluationBlocks
    blocks =. (<input_report ''),<training_report ''
    for_j. i.4 do.
        blocks =. blocks,<model_report j
    end.
    'report.txt'write_lines join_blocks blocks
    i.0
)
run ''
