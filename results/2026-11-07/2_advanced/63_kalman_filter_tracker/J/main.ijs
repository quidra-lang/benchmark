ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'matrix.ijs'
load SourceDirectory,'association.ijs'
load SourceDirectory,'evaluation.ijs'
load SourceDirectory,'kalman.ijs'
load SourceDirectory,'imm.ijs'

FilterNames =: <;._1 ' cv ca abg imm rts'
StatusWords =: 'tentative';'confirmed';'deleted'
split_words =: 3 : '<;._1 '' '',y'
listed =: 4 : 0
    if. #y do. x,' ',' 'join y else. x,' none' end.
)
write_lines =: 4 : 0
    text =. ''
    for_line. y do. text =. text,(>line),LF end.
    text 1!:2 <'output/',x
    i.0 0
)
path_length =: 3 : 0
    total =. 0.0
    for_i. 1+i.(#y)-1 do. total =. total+((i-1){y)distance i{y end.
    total
)
read_inputs =: 3 : 0
    Measurements =: 0$a:
    Times =: i.0
    for_line. }. <;._2 (1!:1 <'input/measurements.csv') do.
        fields =. <;._1 ',',>line
        scan =. (parse_number 0{::fields)-1
        time =. 0.0+parse_number 1{::fields
        point =. 0.0+parse_number&>2 3{fields
        if. scan=#Measurements do.
            Measurements =: Measurements,<0 2$0.0
            Times =: Times,time
        end.
        positions =. (scan{::Measurements),point
        Measurements =: (<positions)scan}Measurements
    end.
    Scans =: #Measurements
    ids =. scans =. i.0
    points =. 0 2$0.0
    for_line. }. <;._2 (1!:1 <'input/truth.csv') do.
        fields =. <;._1 ',',>line
        ids =. ids,parse_number 0{::fields
        scans =. scans,(parse_number 1{::fields)-1
        points =. points,0.0+parse_number&>2 3{fields
    end.
    TargetIDs =: ~.ids
    TargetCount =: #TargetIDs
    TruthExists =: (TargetCount,Scans)$0
    TruthPositions =: (TargetCount,Scans,2)$0.0
    for_i. i.#ids do.
        target =. TargetIDs i.i{ids
        scan =. i{scans
        TruthExists =: 1(<target,scan)}TruthExists
        TruthPositions =: (i{points)(<target,scan)}TruthPositions
    end.
    TargetFirst =: TargetLast =: i.0
    for_exists. TruthExists do.
        indices =. I.exists
        TargetFirst =: TargetFirst,{.indices
        TargetLast =: TargetLast,{:indices
    end.
    for_line. <;._2 (1!:1 <'input/params.txt') do.
        fields =. split_words >line
        key =. 0{::fields
        if. key-:'MODEL' do.
            PrimaryModel =: 1{::fields
            continue.
        end.
        values =. 0.0+parse_number&>}.fields
        select. key
        case. 'Q_CV' do. QCV =: {.values
        case. 'Q_CA' do. QCA =: {.values
        case. 'SIGMA' do. MeasurementSigma =: {.values
        case. 'INIT_VELOCITY_VARIANCE' do. VelocityVariance =: {.values
        case. 'INIT_ACCELERATION_VARIANCE' do. AccelerationVariance =: {.values
        case. 'GATE' do. GateValue =: {.values
        case. 'CONFIRM' do. 'ConfirmM ConfirmN' =: parse_number&>}.fields
        case. 'DELETE' do. DeleteCount =: parse_number 1{::fields
        case. 'ABG' do. ABGCoefficients =: values
        case. 'IMM_Q' do. IMMNoise =: values
        case. 'IMM_TRANSITION' do. IMMTransition =: 2 2$values
        case. 'IMM_INITIAL' do. IMMInitial =: values
        case. 'MATCH_DISTANCE' do. MatchDistance =: {.values
        case. 'OSPA_CUTOFF' do. OSPACutoff =: {.values
        case. 'CONSISTENCY_BOUND' do. ConsistencyBound =: {.values
        case. 'NIS_EDGES' do. NISEdges =: values
        case. 'PLOT_X' do. PlotX =: values
        case. 'PLOT_Y' do. PlotY =: values
        case. 'PLOT_SIZE' do. 'PlotWidth PlotHeight' =: parse_number&>}.fields
        end.
    end.
    PrimaryFilter =: 0
    PrimaryQ =: QCV
    if. PrimaryModel-:'CA' do. PrimaryFilter =: 1 [ PrimaryQ =: QCA end.
    TrackFilters =: TrackObservations =: TrackNIS =: 0$a:
    TrackBirth =: TrackLast =: TrackStatus =: TrackHits =: TrackMisses =: TrackConfirm =: TrackDelete =: i.0
    TrackRows =: <'track,scan,x,y,vx,vy,status'
    AssociationLines =: 0$a:
    ConflictMeasurements =: ConflictTracks =: GreedyDifferences =: 0
    i.0 0
)
track_all_scans =: 3 : 0
    for_scan. i.Scans do.
        live =. I.TrackStatus<2
        measurements =. scan{::Measurements
        number =. #measurements
        if. scan>0 do.
            interval =. (scan{Times)-(scan-1){Times
            for_track. live do.
                model =. interval k_predict track{::TrackFilters
                TrackFilters =: (<model)track}TrackFilters
            end.
        end.
        costs =. ((#live),number)$0.0
        usable =. ((#live),number)$0
        rowgates =. (#live)$0
        columngates =. number$0
        candidates =. 0 3$0.0
        gates =. 0$a:
        for_row. i.#live do.
            track =. row{live
            model =. track{::TrackFilters
            for_column. i.number do.
                innovation =. (column{measurements)k_innovation model
                value =. 3{::innovation
                if. value<:GateValue do.
                    usable =. 1(<row,column)}usable
                    costs =. value(<row,column)}costs
                    rowgates =. (1+row{rowgates)row}rowgates
                    columngates =. (1+column{columngates)column}columngates
                    candidates =. candidates,value,row,column
                    text =. (integer track+1),':',(integer column+1),'=',real value
                    gates =. gates,<text
                end.
            end.
        end.
        assigned =. usable optimal_assignment costs
        greedy =. 0 2$0
        usedrows =. (#live)$0
        usedcolumns =. number$0
        for_candidate. (/:candidates){candidates do.
            'value row column' =. candidate
            if. (-.row{usedrows)*.-.column{usedcolumns do.
                greedy =. greedy,row,column
                usedrows =. 1 row}usedrows
                usedcolumns =. 1 column}usedcolumns
            end.
        end.
        greedy =. (/:greedy){greedy
        equal =. 1
        if. (#assigned)~:#greedy do. equal =. 0
        elseif. -.*/,assigned=greedy do. equal =. 0 end.
        if. -.equal do. GreedyDifferences =: GreedyDifferences+1 end.
        matches =. (#live)$_1
        usedcolumns =. number$0
        for_pair. assigned do.
            'row column' =. pair
            matches =. column row}matches
            usedcolumns =. 1 column}usedcolumns
        end.
        missed =. confirmed =. deleted =. i.0
        for_row. i.#live do.
            track =. row{live
            column =. row{matches
            if. column>:0 do.
                measurement =. column{measurements
                'model nis loglik s' =. measurement k_update track{::TrackFilters
                TrackFilters =: (<model)track}TrackFilters
                observations =. track{::TrackObservations
                observations =. (<measurement)scan}observations
                TrackObservations =: (<observations)track}TrackObservations
                values =. track{::TrackNIS
                values =. ((<row,column){costs)scan}values
                TrackNIS =: (<values)track}TrackNIS
                TrackLast =: scan track}TrackLast
                TrackHits =: (1+track{TrackHits)track}TrackHits
                TrackMisses =: 0 track}TrackMisses
            else.
                TrackMisses =: (1+track{TrackMisses)track}TrackMisses
                missed =. missed,track+1
            end.
            if. 1=track{TrackStatus do.
                if. DeleteCount<:track{TrackMisses do.
                    TrackStatus =: 2 track}TrackStatus
                    TrackDelete =: scan track}TrackDelete
                    deleted =. deleted,track+1
                end.
            elseif. ConfirmM<:track{TrackHits do.
                TrackStatus =: 1 track}TrackStatus
                TrackConfirm =: scan track}TrackConfirm
                confirmed =. confirmed,track+1
            elseif. ConfirmN<:1+scan-track{TrackBirth do.
                TrackStatus =: 2 track}TrackStatus
                TrackDelete =: scan track}TrackDelete
                deleted =. deleted,track+1
            end.
        end.
        processed =. live
        new =. 0$a:
        for_column. I.-.usedcolumns do.
            measurement =. column{measurements
            model =. k_new (<PrimaryModel),(<PrimaryQ),<measurement
            track =. #TrackBirth
            TrackFilters =: TrackFilters,<model
            TrackBirth =: TrackBirth,scan
            TrackLast =: TrackLast,scan
            TrackStatus =: TrackStatus,0
            TrackHits =: TrackHits,1
            TrackMisses =: TrackMisses,0
            TrackConfirm =: TrackConfirm,_1
            TrackDelete =: TrackDelete,_1
            observations =. Scans$<i.0
            observations =. (<measurement)scan}observations
            TrackObservations =: TrackObservations,<observations
            TrackNIS =: TrackNIS,<Scans$_1.0
            processed =. processed,track
            new =. new,<(integer track+1),':',integer column+1
        end.
        conflicts_m =. +/columngates>:2
        conflicts_t =. +/rowgates>:2
        ConflictMeasurements =: ConflictMeasurements+conflicts_m
        ConflictTracks =: ConflictTracks+conflicts_t
        assignments =. greedies =. 0$a:
        for_pair. assigned do.
            'row column' =. pair
            assignments =. assignments,<(integer 1+row{live),':',integer column+1
        end.
        for_pair. greedy do.
            'row column' =. pair
            greedies =. greedies,<(integer 1+row{live),':',integer column+1
        end.
        AssociationLines =: AssociationLines,<emit 'scan';(scan+1);'tracks';(#live);'measurements';number
        AssociationLines =: AssociationLines,<'gate'listed gates
        AssociationLines =: AssociationLines,<'assign'listed assignments
        AssociationLines =: AssociationLines,<'greedy'listed greedies
        AssociationLines =: AssociationLines,<'missed'listed integer&.>missed
        AssociationLines =: AssociationLines,<'new'listed new
        AssociationLines =: AssociationLines,<'confirmed'listed integer&.>confirmed
        AssociationLines =: AssociationLines,<'deleted'listed integer&.>deleted
        AssociationLines =: AssociationLines,<emit 'status tentative';(+/TrackStatus=0);'confirmed';+/TrackStatus=1
        AssociationLines =: AssociationLines,<emit 'conflicts measurements';conflicts_m;'tracks';conflicts_t
        for_track. processed do.
            values =. 4{.2{::track{::TrackFilters
            fields =. (<integer track+1),(<integer scan+1),(real&.>values),<(track{TrackStatus){::StatusWords
            TrackRows =: TrackRows,<','join fields
        end.
    end.
    Evaluated =: I.TrackConfirm>:0
    EvaluatedCount =: #Evaluated
    i.0 0
)
compare_filters =: 3 : 0
    EstimateStates =: (5,EvaluatedCount,Scans,4)$0.0
    SpanMasks =: (EvaluatedCount,Scans)$0
    PrimaryCovariances =: (EvaluatedCount,Scans,2,2)$0.0
    ModelLogs =: (EvaluatedCount,2)$0.0
    HighProbabilities =: (EvaluatedCount,Scans)$0.0
    TrackPaths =: EvaluatedCount$0.0
    LongestGaps =: EvaluatedCount$0
    for_e. i.EvaluatedCount do.
        track =. e{Evaluated
        birth =. track{TrackBirth
        last =. track{TrackLast
        span =. birth+i.1+last-birth
        mask =. Scans$0
        mask =. 1 span}mask
        SpanMasks =: mask e}SpanMasks
        observations =. track{::TrackObservations
        first =. birth{::observations
        for_filter. i.2 do.
            modelname =. filter{::'CV';'CA'
            q =. filter{QCV,QCA
            model =. k_new (<modelname),(<q),<first
            history =. 0$a:
            likelihood =. 0.0
            for_scan. span do.
                if. scan>birth do.
                    interval =. (scan{Times)-(scan-1){Times
                    model =. interval k_predict model
                    measurement =. scan{::observations
                    if. #measurement do.
                        'model nis value s' =. measurement k_update model
                        likelihood =. likelihood+value
                    end.
                end.
                state =. 4{.2{::model
                EstimateStates =: state(<filter,e,scan)}EstimateStates
                history =. history,<k_snapshot model
                if. filter=PrimaryFilter do.
                    covariance =. 0 1{"1 0 1{3{::model
                    PrimaryCovariances =: covariance(<e,scan)}PrimaryCovariances
                end.
            end.
            ModelLogs =: likelihood(<e,filter)}ModelLogs
            if. filter=PrimaryFilter do. primaryhistory =. history end.
        end.
        smoothed =. k_smooth primaryhistory
        positions =. 0 2$0.0
        for_i. i.#span do.
            scan =. i{span
            state =. 4{.i{::smoothed
            EstimateStates =: state(<4,e,scan)}EstimateStates
            positions =. positions,2{.state
        end.
        TrackPaths =: (path_length positions)e}TrackPaths
        'alpha beta gamma' =. ABGCoefficients
        state =. first,4$0.0
        for_scan. span do.
            if. scan>birth do.
                interval =. (scan{Times)-(scan-1){Times
                measurement =. scan{::observations
                for_axis. i.2 do.
                    p =. axis{state
                    v =. (axis+2){state
                    w =. (axis+4){state
                    p =. (p+interval*v)+((interval*interval)*w)%2
                    v =. v+interval*w
                    if. #measurement do.
                        residual =. (axis{measurement)-p
                        p =. p+alpha*residual
                        v =. v+(beta*residual)%interval
                        w =. w+((2*gamma)*residual)%(interval*interval)
                    end.
                    state =. p axis}state
                    state =. v(axis+2)}state
                    state =. w(axis+4)}state
                end.
            end.
            EstimateStates =: (4{.state)(<2,e,scan)}EstimateStates
        end.
        imm =. imm_new first
        gap =. longest =. 0
        for_scan. span do.
            measurement =. scan{::observations
            if. scan>birth do.
                interval =. (scan{Times)-(scan-1){Times
                imm =. imm_step (<imm),(<interval),<measurement
            end.
            EstimateStates =: (imm_estimate imm)(<3,e,scan)}EstimateStates
            HighProbabilities =: (1{1{::imm)(<e,scan)}HighProbabilities
            if. #measurement do. gap =. 0 else. gap =. gap+1 end.
            longest =. longest>.gap
        end.
        LongestGaps =: longest e}LongestGaps
    end.
    i.0 0
)
evaluate_scans =: 3 : 0
    Labels =: (5,TargetCount,Scans)$_1
    PrimaryMatches =: (EvaluatedCount,Scans)$_1
    OSPAValues =: (5,Scans)$0.0
    ScanSizes =: (Scans,2)$0
    for_scan. i.Scans do.
        tracks =. I.scan{"1 SpanMasks
        targets =. I.scan{"1 TruthExists
        positions =. 0 2$0.0
        for_target. targets do. positions =. positions,(<target,scan){TruthPositions end.
        ScanSizes =: ((#targets),#tracks)scan}ScanSizes
        for_filter. i.5 do.
            estimates =. 0 2$0.0
            for_e. tracks do. estimates =. estimates,2{.(<filter,e,scan){EstimateStates end.
            costs =. ((#tracks),#targets)$0.0
            usable =. ((#tracks),#targets)$0
            for_row. i.#tracks do.
                for_column. i.#targets do.
                    value =. (row{estimates)distance column{positions
                    costs =. value(<row,column)}costs
                    if. value<:MatchDistance do. usable =. 1(<row,column)}usable end.
                end.
            end.
            for_pair. usable optimal_assignment costs do.
                'row column' =. pair
                e =. row{tracks
                target =. column{targets
                Labels =: e(<filter,target,scan)}Labels
                if. filter=PrimaryFilter do. PrimaryMatches =: target(<e,scan)}PrimaryMatches end.
            end.
            value =. ospa (<estimates),(<positions),<OSPACutoff
            OSPAValues =: value(<filter,scan)}OSPAValues
        end.
    end.
    Continuities =: (5,TargetCount,4)$0
    for_filter. i.5 do.
        for_target. i.TargetCount do.
            scans =. I.target{TruthExists
            labels =. (<filter,target){Labels
            value =. continuity scans{labels
            Continuities =: value(<filter,target)}Continuities
        end.
    end.
    i.0 0
)
match_tracks =: 3 : 0
    costs =. (EvaluatedCount,TargetCount)$0.0
    usable =. (EvaluatedCount,TargetCount)$0
    for_e. i.EvaluatedCount do.
        for_target. i.TargetCount do.
            span =. e{SpanMasks
            exists =. target{TruthExists
            common =. I.span*.exists
            allowed =. 0
            distances =. Scans$OSPACutoff
            for_scan. common do.
                estimate =. (<PrimaryFilter,e,scan){EstimateStates
                point =. (<target,scan){TruthPositions
                value =. estimate distance point
                distances =. (OSPACutoff<.value)scan}distances
                if. value<OSPACutoff do. allowed =. 1 end.
            end.
            if. allowed do.
                union =. I.span+.exists
                cost =. (m_total union{distances)%#union
                costs =. cost(<e,target)}costs
                usable =. 1(<e,target)}usable
            end.
        end.
    end.
    MatchedTargets =: EvaluatedCount$_1
    MatchedTracks =: TargetCount$_1
    MatchedMeans =: EvaluatedCount$0.0
    MatchedCommon =: EvaluatedCount$<i.0
    for_pair. usable optimal_assignment costs do.
        'e target' =. pair
        MatchedTargets =: target e}MatchedTargets
        MatchedTracks =: e target}MatchedTracks
        MatchedMeans =: ((<e,target){costs)e}MatchedMeans
        common =. I.(e{SpanMasks)*.target{TruthExists
        MatchedCommon =: (<common)e}MatchedCommon
    end.
    i.0 0
)
evaluate_errors =: 3 : 0
    PositionRMSE =: VelocityRMSE =: (TargetCount,5)$0.0
    VelocityCounts =: TargetCount$0
    NEESValues =: TargetCount$<i.0
    positionsum =. velocitysum =. 5$0.0
    positioncount =. velocitycount =. 0
    for_target. i.TargetCount do.
        e =. target{MatchedTracks
        if. e<0 do. continue. end.
        common =. e{::MatchedCommon
        velocityscans =. i.0
        velocities =. (Scans,2)$0.0
        for_scan. common do.
            if. (scan>0)*.(scan+1)<Scans do.
                before =. (<target,scan-1){TruthExists
                after =. (<target,scan+1){TruthExists
                if. before*.after do.
                    pointbefore =. (<target,scan-1){TruthPositions
                    pointafter =. (<target,scan+1){TruthPositions
                    interval =. ((scan+1){Times)-(scan-1){Times
                    velocity =. (pointafter-pointbefore)%interval
                    velocities =. velocity scan}velocities
                    velocityscans =. velocityscans,scan
                end.
            end.
        end.
        VelocityCounts =: (#velocityscans)target}VelocityCounts
        positioncount =. positioncount+#common
        velocitycount =. velocitycount+#velocityscans
        for_filter. i.5 do.
            total =. 0.0
            for_scan. common do.
                estimate =. (<filter,e,scan){EstimateStates
                truth =. (<target,scan){TruthPositions
                value =. estimate squared_distance truth
                total =. total+value
                positionsum =. ((filter{positionsum)+value)filter}positionsum
            end.
            PositionRMSE =: (%:total%#common)(<target,filter)}PositionRMSE
            total =. 0.0
            for_scan. velocityscans do.
                estimate =. 2}.(<filter,e,scan){EstimateStates
                value =. estimate squared_distance scan{velocities
                total =. total+value
                velocitysum =. ((filter{velocitysum)+value)filter}velocitysum
            end.
            VelocityRMSE =: (%:total%#velocityscans)(<target,filter)}VelocityRMSE
        end.
        nees =. i.0
        for_scan. common do.
            estimate =. 2{.(<PrimaryFilter,e,scan){EstimateStates
            truth =. (<target,scan){TruthPositions
            covariance =. (<e,scan){PrimaryCovariances
            nees =. nees,(estimate-truth)m_quadratic2 m_inverse covariance
        end.
        NEESValues =: (<nees)target}NEESValues
    end.
    OverallPosition =: %:positionsum%positioncount
    OverallVelocity =: %:velocitysum%velocitycount
    i.0 0
)
track_nis =: 3 : 0
    values =. y{::TrackNIS
    (values>:0)#values
)
optional_scan =: 3 : 0
    if. y<0 do. ,'-' else. integer y+1 end.
)
optional_target =: 3 : 0
    if. y<0 do. ,'-' else. integer y{TargetIDs end.
)
rmse_suffix =: 3 : 0
    fields =. 0$a:
    keys =. i.0
    for_filter. i.5 do.
        text =. real filter{y
        keys =. keys,parse_number ((text~:'.')#text),'x'
        fields =. fields,(filter{FilterNames),<text
    end.
    best =. keys i.!.0 <./keys
    emit fields,'best';best{::FilterNames
)
matched_segments =: 3 : 0
    segments =. 0$a:
    scan =. 0
    while. scan<#y do.
        target =. scan{y
        if. target<0 do.
            scan =. scan+1
            continue.
        end.
        first =. last =. scan
        scan =. scan+1
        while. scan<#y do.
            if. target~:scan{y do. break. end.
            last =. scan
            scan =. scan+1
        end.
        segments =. segments,<(integer first+1),'-',(integer last+1),':',integer target{TargetIDs
    end.
    segments
)
scan_segments =: 3 : 0
    segments =. 0$a:
    index =. 0
    while. index<#y do.
        first =. last =. index{y
        index =. index+1
        while. index<#y do.
            if. (index{y)~:last+1 do. break. end.
            last =. index{y
            index =. index+1
        end.
        segments =. segments,<(integer first+1),'-',integer last+1
    end.
    segments
)
evaluation_report =: 3 : 0
    lines =. <'summary'
    lines =. lines,<emit 'scans';Scans
    lines =. lines,<emit 'measurements';+/#&>Measurements
    lines =. lines,<emit 'targets';TargetCount
    lines =. lines,<emit 'tracks_created';#TrackBirth
    lines =. lines,<emit 'tracks_confirmed';EvaluatedCount
    lines =. lines,<emit 'false_tracks';+/0=+/"1 PrimaryMatches>:0
    lines =. lines,<emit 'missed_targets';+/MatchedTracks<0
    lines =. lines,<emit 'measurements_used';+/Evaluated{TrackHits
    lines =. lines,<emit 'conflict_measurements';ConflictMeasurements
    lines =. lines,<emit 'conflict_tracks';ConflictTracks
    lines =. lines,<emit 'greedy_differences';GreedyDifferences
    lines =. lines,(<''),<'targets'
    for_target. i.TargetCount do.
        scans =. I.target{TruthExists
        positions =. scans{target{TruthPositions
        length =. path_length positions
        interval =. (({:scans){Times)-({.scans){Times
        lines =. lines,<emit 'target';(target{TargetIDs);'first';(1+{.scans);'last';(1+{:scans);'scans';(#scans);'path';(real length);'mean_speed';real length%interval
    end.
    lines =. lines,(<''),<'tracks'
    for_e. i.EvaluatedCount do.
        track =. e{Evaluated
        birth =. track{TrackBirth
        last =. track{TrackLast
        nis =. track_nis track
        inside =. (integer +/nis<:ConsistencyBound),'/',integer #nis
        lines =. lines,<emit 'track';(track+1);'birth';(birth+1);'confirmed';(1+track{TrackConfirm);'end';(last+1);'deleted';(optional_scan track{TrackDelete);'hits';(track{TrackHits);'misses';((1+last-birth)-track{TrackHits);'longest_gap';(e{LongestGaps);'path';(real e{TrackPaths);'nis';(real (m_total nis)%#nis);'nis_inside';inside
    end.
    lines =. lines,(<''),<'matching'
    for_e. i.EvaluatedCount do.
        track =. e{Evaluated
        target =. e{MatchedTargets
        text =. emit 'track';(track+1);'target';optional_target target
        if. target>:0 do.
            text =. text,' ',emit 'common';(#e{::MatchedCommon);'mean_distance';real e{MatchedMeans
        end.
        labels =. e{PrimaryMatches
        text =. text,' ',emit 'matched_scans';+/labels>:0
        lines =. lines,<text,' ','segments'listed matched_segments labels
    end.
    lines =. lines,(<''),<'rmse'
    for_target. i.TargetCount do.
        e =. target{MatchedTracks
        if. e<0 do.
            lines =. lines,<emit 'target';(target{TargetIDs);'track -'
            continue.
        end.
        text =. emit 'target';(target{TargetIDs);'track';(1+e{Evaluated);'common';#e{::MatchedCommon
        lines =. lines,<text,' ',rmse_suffix target{PositionRMSE
        text =. emit 'target';(target{TargetIDs);'velocity';target{VelocityCounts
        lines =. lines,<text,' ',rmse_suffix target{VelocityRMSE
    end.
    lines =. lines,<'overall position ',rmse_suffix OverallPosition
    lines =. lines,<'overall velocity ',rmse_suffix OverallVelocity
    lines =. lines,(<''),<'consistency'
    for_target. i.TargetCount do.
        e =. target{MatchedTracks
        text =. emit 'target';(target{TargetIDs);'track'
        if. e<0 do. lines =. lines,<text,' -'
        else.
            values =. target{::NEESValues
            ratio =. (integer +/values<:ConsistencyBound),'/',integer #values
            lines =. lines,<text,' ',emit (1+e{Evaluated);'nees';(real (m_total values)%#values);'inside';ratio
        end.
    end.
    nis =. i.0
    for_track. Evaluated do. nis =. nis,track_nis track end.
    lower =. 0.0,NISEdges
    upper =. NISEdges,_
    observed =. i.0
    expected =. i.0
    for_bin. i.#lower do.
        lo =. bin{lower
        hi =. bin{upper
        observed =. observed,+/(nis>:lo)*.nis<hi
        tail =. 0.0
        if. bin<#NISEdges do. tail =. ^(-hi)%2 end.
        expected =. expected,(#nis)*((^(-lo)%2)-tail)
    end.
    lines =. lines,<emit 'nis_histogram total';(#nis);'observed';(' 'join integer&.>observed);'expected';formatted expected
    lines =. lines,(<''),<'models'
    for_e. i.EvaluatedCount do.
        logs =. e{ModelLogs
        better =. 0
        if. (1{logs)>0{logs do. better =. 1 end.
        lines =. lines,<emit 'track';(1+e{Evaluated);'updates';(#track_nis e{Evaluated);'cv';(real 0{logs);'ca';(real 1{logs);'better';better{::FilterNames
    end.
    lines =. lines,(<''),<emit 'ospa cutoff';(real OSPACutoff);'order 2'
    lines =. lines,<'scan targets tracks cv ca abg imm rts'
    for_scan. i.Scans do.
        text =. emit (scan+1);(0{scan{ScanSizes);1{scan{ScanSizes
        lines =. lines,<text,' ',formatted scan{"1 OSPAValues
    end.
    means =. i.0
    for_values. OSPAValues do. means =. means,(m_total values)%Scans end.
    lines =. lines,<'mean ',formatted means
    lines =. lines,(<''),<'continuity'
    for_filter. i.5 do.
        total =. +/filter{Continuities
        lines =. lines,<emit (filter{::FilterNames);'covered';(0{total);'breaks';(1{total);'swaps';2{total
        for_target. i.TargetCount do.
            'covered breaks swaps delay' =. (<filter,target){Continuities
            delaytext =. ,'-'
            if. delay>:0 do. delaytext =. integer delay end.
            text =. emit 'target';(target{TargetIDs);'scans';(+/target{TruthExists);'covered';covered;'breaks';breaks;'swaps';swaps;'delay';delaytext
            lines =. lines,<'  ',text
        end.
    end.
    lines =. lines,(<''),<'imm'
    for_e. i.EvaluatedCount do.
        scans =. I.e{SpanMasks
        values =. scans{e{HighProbabilities
        maximum =. >./values
        where =. values i.!.0 maximum
        high =. (values>0.5)#scans
        text =. emit 'track';(1+e{Evaluated);'mean_high';(real (m_total values)%#values);'max_high';(real maximum);'at';(1+where{scans);'high_scans';#high
        lines =. lines,<text,' ','segments'listed scan_segments high
    end.
    lines
)
TrackCharacters =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
plot_cell =: 3 : 0
    column =. <.((0{y)-0{PlotX)%((1{PlotX)-0{PlotX)%PlotWidth
    row =. <.((1{PlotY)-1{y)%((1{PlotY)-0{PlotY)%PlotHeight
    if. (column<0)+.(column>:PlotWidth)+.(row<0)+.row>:PlotHeight do. i.0 else. row,column end.
)
framed =: 3 : 0
    width =. {:$y
    border =. '+',(width$'-'),'+'
    lines =. <border
    for_row. y do. lines =. lines,<'|',(,row),'|' end.
    lines,<border
)
plots =: 3 : 0
    lines =. <emit 'tracks x';(real 0{PlotX);(real 1{PlotX);'y';(real 0{PlotY);(real 1{PlotY);'size';PlotWidth;PlotHeight
    grid =. (PlotHeight,PlotWidth)$' '
    for_target. i.TargetCount do.
        for_scan. I.target{TruthExists do.
            cell =. plot_cell (<target,scan){TruthPositions
            if. #cell do. grid =. '.'(<cell)}grid end.
        end.
    end.
    for_e. i.EvaluatedCount do.
        for_scan. I.e{SpanMasks do.
            cell =. plot_cell (<4,e,scan){EstimateStates
            if. #cell do. grid =. (e{TrackCharacters)(<cell)}grid end.
        end.
    end.
    lines =. lines,framed grid
    for_e. i.EvaluatedCount do.
        lines =. lines,<emit (e{TrackCharacters);'track';(1+e{Evaluated);'target';optional_target e{MatchedTargets
    end.
    lines =. lines,(<''),<'measurements'
    counts =. (PlotHeight,PlotWidth)$0
    for_measurements. Measurements do.
        for_point. >measurements do.
            cell =. plot_cell point
            if. #cell do. counts =. (1+(<cell){counts)(<cell)}counts end.
        end.
    end.
    grid =. (PlotHeight,PlotWidth)$' '
    for_row. i.PlotHeight do.
        for_column. i.PlotWidth do.
            count =. (<row,column){counts
            if. count>:10 do. char =. '#'
            else. char =. count{' 123456789' end.
            grid =. char(<row,column)}grid
        end.
    end.
    lines =. lines,framed grid
    lines =. lines,(<''),<'timeline'
    for_target. i.TargetCount do.
        text =. Scans$' '
        for_scan. I.target{TruthExists do.
            label =. (<PrimaryFilter,target,scan){Labels
            char =. '.'
            if. label>:0 do. char =. label{TrackCharacters end.
            text =. char scan}text
        end.
        lines =. lines,<(integer target{TargetIDs),' |',text,'|'
    end.
    lines =. lines,(<''),<'ospa ',PrimaryFilter{::FilterNames
    heights =. <.(10*PrimaryFilter{OSPAValues)%OSPACutoff
    grid =. (10,Scans)$' '
    for_row. i.10 do.
        for_scan. I.heights>:10-row do. grid =. '#'(<row,scan)}grid end.
    end.
    lines,framed grid
)
smoothed_rows =: 3 : 0
    lines =. <'track,scan,x,y,vx,vy'
    for_e. i.EvaluatedCount do.
        for_scan. I.e{SpanMasks do.
            state =. (<4,e,scan){EstimateStates
            fields =. (<integer 1+e{Evaluated),(<integer scan+1),real&.>state
            lines =. lines,<','join fields
        end.
    end.
    lines
)
main =: 3 : 0
    read_inputs''
    track_all_scans''
    compare_filters''
    evaluate_scans''
    match_tracks''
    evaluate_errors''
    1!:5 ::0: <'output'
    'tracks.csv'write_lines TrackRows
    'smoothed.csv'write_lines smoothed_rows''
    'association_log.txt'write_lines AssociationLines
    'evaluation.txt'write_lines evaluation_report''
    'track_plot.txt'write_lines plots''
    i.0 0
)
main''
