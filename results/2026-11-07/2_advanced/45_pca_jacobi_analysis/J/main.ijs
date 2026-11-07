load 'dataset.ijs'
load 'matrix.ijs'
load 'eigen.ijs'
load 'pca.ijs'
load 'plot.ijs'
integer =: 3 : 0
    text =. ":<.y
    '-'(I.text='_')}text
)
number =: 3 : 0
    text =. (0j4":y)-.' '
    text =. '-'(I.text='_')}text
    if. text-:'-0.0000' do.
        text =. '0.0000'
    end.
    text
)
six_decimal =: 3 : 0
    text =. (0j6":y)-.' '
    text =. '-'(I.text='_')}text
    if. text-:'-0.000000' do.
        text =. '0.000000'
    end.
    text
)
join =: 4 : 0
    result =. ''
    for_index. i.#y do.
        if. index do.
            result =. result,x
        end.
        result =. result,index{::y
    end.
    result
)
reals =: 3 : ''' ''join number&.>y'
sum_values =: 3 : 0
    total =. 0.0
    for_value. y do.
        total =. total+value
    end.
    total
)
argmax =: 3 : 'y i.>./y'
top_indices =: 4 : 0
    order =. /:(-x),.i.#x
    (y<.#order){.order
)
congruence =: 4 : '(x dot y)%%:((x dot x)*(y dot y))'
summarize =: 3 : 0
    summaries =. 0 6$0.0
    for_j. i.#Variables do.
        cells =. j{"1 RawRows
        values =. decimal&>cells#~cells~:< 'NA'
        mean =. (sum_values values)%#values
        squares =. 0.0
        for_value. values do.
            squares =. squares+(value-mean)*(value-mean)
        end.
        summaries =. summaries,(#values),((#RawRows)-#values),mean,(%:squares%((#values)-1)),(<./values),>./values
    end.
    incomplete =. 0$a:
    for_index. i.#RawRows do.
        if. (<'NA')e.index{RawRows do.
            incomplete =. incomplete,index{IDs
        end.
    end.
    (<summaries),<incomplete
)
analysis_data =: 3 : 0
    ids =. 0$a:
    rows =. (0,#Variables)$0.0
    for_index. i.#RawRows do.
        row =. index{RawRows
        complete =. -.(<'NA')e.row
        if. (-.complete)*.-.y-:'mean' do.
            continue.
        end.
        values =. i.0
        for_j. i.#Variables do.
            text =. j{::row
            if. text-:'NA' do.
                value =. (<j,2){Summaries
            else.
                value =. decimal text
            end.
            values =. values,value
        end.
        ids =. ids,index{IDs
        rows =. rows,values
    end.
    (<ids),<rows
)
sampling_adequacy =: 3 : 0
    'correlation n' =. y
    size =. #correlation
    'inverse determinant' =. inverse_determinant correlation
    msa =. i.0
    rr_total =. 0.0
    pp_total =. 0.0
    for_j. i.size do.
        rr =. 0.0
        pp =. 0.0
        for_k. i.size do.
            if. k=j do.
                continue.
            end.
            partial =. (-((<j,k){inverse))%%:((<j,j){inverse)*(<k,k){inverse
            value =. (<j,k){correlation
            rr =. rr+value*value
            pp =. pp+partial*partial
        end.
        msa =. msa,rr%(rr+pp)
        rr_total =. rr_total+rr
        pp_total =. pp_total+pp
    end.
    kmo =. rr_total%(rr_total+pp_total)
    bartlett =. (-((n-1)-((2*size)+5)%6.0))*^.determinant
    degrees =. <.(size*(size-1))%2
    (<msa),(<determinant),(<kmo),(<bartlett),<degrees
)
parallel_analysis =: 3 : 0
    'n size' =. y
    totals =. size$0.0
    state =. x:RandomSeed
    for_repetition. i.ParallelCount do.
        rows =. (n,size)$0.0
        for_i. i.n do.
            for_j. i.size do.
                state =. 2147483647x|48271x*state
                value =. (0.0+state)%2147483647.0
                rows =. value (<i,j)}rows
            end.
        end.
        prepared =. prepare_pca (<rows),<'correlation'
        result =. jacobi p_values prepared
        total =. sum_values e_values result
        for_k. i.size do.
            totals =. ((k{totals)+(k{e_values result)%total)k}totals
        end.
    end.
    totals%ParallelCount
)
c_total =: 0&{::
c_average =: 1&{::
c_ratios =: 2&{::
c_cumulative =: 3&{::
c_broken =: 4&{::
c_standard_errors =: 5&{::
c_separated =: 6&{::
c_criteria =: 7&{::
c_retained =: 8&{::
retention =: 3 : 0
    'values parallel n' =. y
    size =. #values
    total =. sum_values values
    average =. total%size
    cumulative =. 0.0
    ratios =. i.0
    cumulatives =. i.0
    broken =. i.0
    standard_errors =. i.0
    separated =. i.0
    criteria =. 0,size,size,size
    broken_found =. 0
    parallel_found =. 0
    cumulative_found =. 0
    for_k. i.size do.
        ratio =. (k{values)%total
        if. k=0 do.
            cumulative =. ratio
        else.
            cumulative =. cumulative+ratio
        end.
        ratios =. ratios,ratio
        cumulatives =. cumulatives,cumulative
        value =. 0.0
        for_index. (k+1)+i.size-k do.
            value =. value+1.0%index
        end.
        broken =. broken,value%size
        standard_error =. (k{values)*%:2.0%n
        standard_errors =. standard_errors,standard_error
        isolated =. 1
        for_other. (k-1),k+1 do.
            if. (other>:0)*.other<size do.
                if. (|(k{values)-other{values)<:standard_error do.
                    isolated =. 0
                end.
            end.
        end.
        separated =. separated,isolated
        if. (k{values)>average do.
            criteria =. (1+0{criteria)0}criteria
        end.
        if. (-.broken_found)*.ratio<:k{broken do.
            criteria =. k (1)}criteria
            broken_found =. 1
        end.
        if. (-.parallel_found)*.ratio<:k{parallel do.
            criteria =. k (2)}criteria
            parallel_found =. 1
        end.
        if. (-.cumulative_found)*.cumulative>:CumulativeTarget do.
            criteria =. (k+1)3}criteria
            cumulative_found =. 1
        end.
    end.
    names =. ;:'kaiser broken_stick parallel cumulative'
    index =. names i.<ComponentRule
    if. index<#names do.
        retained =. index{criteria
    else.
        retained =. <.decimal ComponentRule
    end.
    retained =. 1>.retained
    (<total),(<average),(<ratios),(<cumulatives),(<broken),(<standard_errors),(<separated),(<criteria),<retained
)
loading_analysis =: 3 : 0
    'values vectors analyzed count' =. y
    size =. #values
    loadings =. (size,size)$0.0
    communalities =. size$0.0
    correlations =. (size,2)$0.0
    for_j. i.size do.
        communality =. 0.0
        for_k. i.size do.
            value =. ((<k,j){vectors)*%:k{values
            loadings =. value (<j,k)}loadings
            if. k<count do.
                communality =. communality+value*value
            end.
            if. k<2 do.
                correlations =. (value%%:(<j,j){analyzed)(<j,k)}correlations
            end.
        end.
        communalities =. (communality%(<j,j){analyzed)j}communalities
    end.
    (<loadings),(<communalities),<correlations
)
varimax_criterion =: 4 : 0
    result =. 0.0
    size =. #x
    for_k. i.y do.
        q4 =. 0.0
        q2 =. 0.0
        for_j. i.size do.
            value =. (<j,k){x
            square =. value*value
            q4 =. q4+square*square
            q2 =. q2+square
        end.
        result =. result+((q4%size)-(q2%size)*(q2%size))
    end.
    result
)
v_loadings =: 0&{::
v_squares =: 1&{::
v_criteria =: 2&{::
v_closest =: 3&{::
v_congruences =: 4&{::
varimax =: 3 : 0
    'loadings count' =. y
    size =. #loadings
    lengths =. size$0.0
    normalized =. (size,count)$0.0
    for_j. i.size do.
        squared =. 0.0
        for_k. i.count do.
            value =. (<j,k){loadings
            squared =. squared+value*value
        end.
        length =. %:squared
        lengths =. length j}lengths
        for_k. i.count do.
            normalized =. (((<j,k){loadings)%length)(<j,k)}normalized
        end.
    end.
    criteria =. ,normalized varimax_criterion count
    for_cycle. i.RotationCycles do.
        for_a. i.count-1 do.
            for_b. (a+1)+i.count-a+1 do.
                sa =. 0.0
                sb =. 0.0
                sc =. 0.0
                sd =. 0.0
                for_j. i.size do.
                    first =. (<j,a){normalized
                    second =. (<j,b){normalized
                    phi =. (first*first)-second*second
                    psi =. (2.0*first)*second
                    sa =. sa+phi
                    sb =. sb+psi
                    sc =. sc+((phi*phi)-psi*psi)
                    sd =. sd+(2.0*phi)*psi
                end.
                numerator =. sd-((2.0*sa)*sb)%size
                denominator =. sc-((sa*sa)-sb*sb)%size
                omega =. %:(numerator*numerator)+denominator*denominator
                if. omega=0 do.
                    continue.
                end.
                cos4 =. denominator%omega
                sin4 =. numerator%omega
                cos2 =. %:(1.0+cos4)%2.0
                if. cos2=0 do.
                    sin2 =. 1.0
                else.
                    sin2 =. sin4%(2.0*cos2)
                end.
                cos1 =. %:(1.0+cos2)%2.0
                sin1 =. sin2%(2.0*cos1)
                for_j. i.size do.
                    first =. (<j,a){normalized
                    second =. (<j,b){normalized
                    normalized =. ((cos1*first)+sin1*second)(<j,a)}normalized
                    normalized =. (((-sin1)*first)+cos1*second)(<j,b)}normalized
                end.
            end.
        end.
        criteria =. criteria,normalized varimax_criterion count
    end.
    columns =. (0,size)$0.0
    squares =. i.0
    for_k. i.count do.
        vector =. orient (normalized column k)*lengths
        columns =. columns,vector
        squares =. squares,vector dot vector
    end.
    order =. squares top_indices count
    rotated =. (size,count)$0.0
    ss =. order{squares
    closest =. i.0
    congruences =. i.0
    for_k. i.count do.
        source =. k{order
        vector =. source{columns
        for_j. i.size do.
            rotated =. (j{vector)(<j,k)}rotated
        end.
        values =. i.0
        for_component. i.count do.
            values =. values,|vector congruence loadings column component
        end.
        selected =. argmax values
        closest =. closest,selected
        congruences =. congruences,selected{values
    end.
    (<rotated),(<ss),(<criteria),(<closest),<congruences
)
z_t2 =: 0&{::
z_spe =: 1&{::
z_quality =: 2&{::
z_flag =: 3&{::
z_t2_contributions =: 4&{::
z_spe_contributions =: 5&{::
diagnose =: 3 : 0
    'standardized scores values vectors count quality_needed' =. y
    result =. 0$a:
    for_i. i.#standardized do.
        row =. i{standardized
        score =. i{scores
        residual =. pca_residual (<row),(<score),(<vectors),<count
        t2 =. pca_t2 (<score),(<values),<count
        spe =. residual dot residual
        represented =. 0.0
        for_k. i.count do.
            value =. k{score
            represented =. represented+value*value
        end.
        quality =. 0.0
        if. quality_needed do.
            quality =. represented%(row dot row)
        end.
        flag =. ''
        if. t2>T2Limit do.
            flag =. flag,'T'
        end.
        if. spe>SpeLimit do.
            flag =. flag,'Q'
        end.
        if. 0=#flag do.
            flag =. '-'
        end.
        t2_contributions =. i.0
        spe_contributions =. i.0
        for_j. i.#row do.
            weight =. 0.0
            for_k. i.count do.
                weight =. weight+((k{score)%k{values)*(<k,j){vectors
            end.
            t2_contributions =. t2_contributions,(j{row)*weight
            value =. j{residual
            spe_contributions =. spe_contributions,value*value
        end.
        result =. result,<(<t2),(<spe),(<quality),(<flag),(<t2_contributions),<spe_contributions
    end.
    result
)
supplementary_nearest =: 3 : 0
    'scores reference count' =. y
    result =. 0 2$0.0
    for_row. scores do.
        nearest =. _1
        minimum =. 0.0
        for_index. i.#reference do.
            distance =. 0.0
            for_k. i.count do.
                difference =. (k{row)-(<index,k){reference
                distance =. distance+difference*difference
            end.
            if. (nearest<0)+.distance<minimum do.
                nearest =. index
                minimum =. distance
            end.
        end.
        result =. result,nearest,%:minimum
    end.
    result
)
eigen_report =: 3 : 0
    size =. #Variables
    count =. c_retained Retention
    values =. e_values EigenResult
    vectors =. e_vectors EigenResult
    lines =. <'pca rows ',(integer #RawRows),' used ',(integer #AnalysisIDs),' variables ',(integer size),' missing ',MissingStrategy,' scaling ',Scaling
    if. #Incomplete do.
        incomplete =. ' 'join Incomplete
    else.
        incomplete =. '-'
    end.
    lines =. lines,(<'incomplete ',(integer #Incomplete),' ',incomplete),(<''),<'variable observed missing mean sd min max msa'
    for_j. i.size do.
        row =. j{Summaries
        lines =. lines,<(j{::Variables),' ',(integer 0{row),' ',(integer 1{row),' ',reals (2 3 4 5{row),j{0{::Adequacy
    end.
    lines =. lines,<'adequacy kmo ',(number 2{::Adequacy),' determinant ',(six_decimal 1{::Adequacy),' bartlett ',(number 3{::Adequacy),' df ',integer 4{::Adequacy
    lines =. lines,(<''),<'matrix ',Scaling
    for_j. i.size do.
        lines =. lines,<(j{::Variables),' ',reals j{p_values Prepared
    end.
    pairs =. 0 2$0
    magnitudes =. i.0
    for_j. i.size-1 do.
        for_k. (j+1)+i.size-j+1 do.
            pairs =. pairs,j,k
            magnitudes =. magnitudes,|(<j,k){p_correlation Prepared
        end.
    end.
    strongest =. 0$a:
    for_index. magnitudes top_indices TopCount do.
        'j k' =. index{pairs
        strongest =. strongest,<(j{::Variables),':',(k{::Variables),':',number (<j,k){p_correlation Prepared
    end.
    lines =. lines,(<'strongest ',' 'join strongest),(<''),<'jacobi sweeps ',integer e_sweeps EigenResult
    lines =. lines,<'eigenvalues total ',(number c_total Retention),' average ',number c_average Retention
    lines =. lines,<'k eigenvalue ratio cumulative broken_stick parallel se separated'
    for_k. i.size do.
        fields =. (k{values),(k{c_ratios Retention),(k{c_cumulative Retention),(k{c_broken Retention),(k{ParallelValues),k{c_standard_errors Retention
        separation =. (k{c_separated Retention){::'no';'yes'
        lines =. lines,<(integer k+1),' ',(reals fields),' ',separation
    end.
    criteria =. c_criteria Retention
    lines =. lines,<'retention kaiser ',(integer 0{criteria),' broken_stick ',(integer 1{criteria),' parallel ',(integer 2{criteria),' cumulative ',(integer 3{criteria),' target ',number CumulativeTarget
    lines =. lines,(<'components ',(integer count),' rule ',ComponentRule),(<''),<'eigenvectors'
    header =. <'variable'
    for_k. 1+i.size do.
        header =. header,<'pc',integer k
    end.
    lines =. lines,<' 'join header
    for_j. i.size do.
        lines =. lines,<(j{::Variables),' ',reals vectors column j
    end.
    lines =. lines,(<''),(<'power_iteration iterations 1000'),<'k jacobi power agree_at match'
    matched =. 0
    for_k. i.size do.
        'value vector agreement match' =. k{::Powered
        matched =. matched+match
        if. agreement<0 do.
            agreement_text =. '-'
        else.
            agreement_text =. integer agreement
        end.
        lines =. lines,<(integer k+1),' ',(number k{values),' ',(number value),' ',agreement_text,' ',match{::'no';'yes'
    end.
    lines =. lines,(<'cross_check ',(integer matched),'/',integer size),(<''),(<'scores'),<'component sd min min_id max max_id contributors'
    for_k. i.count do.
        column_values =. Scores column k
        squared =. 0.0
        minimum =. 0
        maximum =. 0
        contributions =. i.0
        for_i. i.#column_values do.
            value =. i{column_values
            squared =. squared+value*value
            if. value<minimum{column_values do.
                minimum =. i
            end.
            if. value>maximum{column_values do.
                maximum =. i
            end.
            contributions =. contributions,(value*value)%(((#AnalysisIDs)-1)*k{values)
        end.
        fields =. 0$a:
        for_i. contributions top_indices TopCount do.
            fields =. fields,<(i{::AnalysisIDs),':',number i{contributions
        end.
        lines =. lines,<'pc',(integer k+1),' ',(number %:squared%((#AnalysisIDs)-1)),' ',(number minimum{column_values),' ',(minimum{::AnalysisIDs),' ',(number maximum{column_values),' ',(maximum{::AnalysisIDs),' ',' 'join fields
    end.
    lines =. lines,(<''),<'varimax components ',(integer count),' cycles ',integer RotationCycles
    for_index. i.#v_criteria Rotation do.
        lines =. lines,<'cycle ',(integer index),' criterion ',six_decimal index{v_criteria Rotation
    end.
    for_k. i.count do.
        lines =. lines,<'rc',(integer k+1),' ss ',(number k{v_squares Rotation),' ratio ',(number (k{v_squares Rotation)%c_total Retention),' closest pc',(integer 1+k{v_closest Rotation),' congruence ',number k{v_congruences Rotation
    end.
    lines =. lines,(<''),(<'sensitivity'),<'missing scaling rows sweeps eigenvalues cumulative congruence'
    combinations =. (<('listwise';'covariance')),(<('listwise';'correlation')),(<('mean';'covariance')),<('mean';'correlation')
    for_combination. combinations do.
        'strategy scaling' =. >combination
        'ids rows' =. analysis_data strategy
        prepared_variant =. prepare_pca (<rows),<scaling
        variant =. jacobi p_values prepared_variant
        total =. sum_values e_values variant
        cumulative =. 0.0
        agreements =. i.0
        for_k. i.count do.
            ratio =. (k{e_values variant)%total
            if. k=0 do.
                cumulative =. ratio
            else.
                cumulative =. cumulative+ratio
            end.
            agreements =. agreements,|(k{e_vectors variant)dot k{vectors
        end.
        lines =. lines,<strategy,' ',scaling,' ',(integer #ids),' ',(integer e_sweeps variant),' ',(reals count{.e_values variant),' ',(number cumulative),' ',reals agreements
    end.
    lines
)
loadings_report =: 3 : 0
    count =. c_retained Retention
    header =. <'variable'
    for_k. 1+i.count do.
        header =. header,<'pc',integer k
    end.
    header =. header,<'communality'
    for_k. 1+i.count do.
        header =. header,<'rc',integer k
    end.
    lines =. <','join header
    for_j. i.#Variables do.
        fields =. j{Variables
        fields =. fields,(number&.>count{.j{Loadings),(<number j{Communalities),number&.>j{v_loadings Rotation
        lines =. lines,<','join fields
    end.
    lines
)
scores_report =: 3 : 0
    count =. c_retained Retention
    header =. ;:'id set'
    for_k. 1+i.count do.
        header =. header,<'pc',integer k
    end.
    lines =. <','join header
    for_collection. i.2 do.
        if. collection=0 do.
            ids =. AnalysisIDs
            scores =. Scores
            label =. 'data'
        else.
            ids =. SupplementaryIDs
            scores =. SupplementaryScores
            label =. 'supplementary'
        end.
        for_index. i.#ids do.
            fields =. (index{ids),(<label),number&.>count{.index{scores
            lines =. lines,<','join fields
        end.
    end.
    lines
)
outliers_report =: 3 : 0
    count =. c_retained Retention
    lines =. (<'diagnostics components ',(integer count),' t2_limit ',(number T2Limit),' spe_limit ',number SpeLimit),<'id t2 spe quality flag'
    flagged_t =. 0
    flagged_q =. 0
    both =. 0
    any =. 0
    t2_values =. i.0
    spe_values =. i.0
    for_index. i.#Diagnostics do.
        row =. index{::Diagnostics
        lines =. lines,<(index{::AnalysisIDs),' ',(reals (z_t2 row),(z_spe row),z_quality row),' ',z_flag row
        flag =. z_flag row
        flagged_t =. flagged_t+'T'e.flag
        flagged_q =. flagged_q+'Q'e.flag
        both =. both+flag-:'TQ'
        any =. any+-.flag-:'-'
        t2_values =. t2_values,z_t2 row
        spe_values =. spe_values,z_spe row
    end.
    lines =. lines,<'flagged t2 ',(integer flagged_t),' spe ',(integer flagged_q),' both ',(integer both),' any ',integer any
    for_mode. ;:'t2 spe' do.
        mode =. >mode
        lines =. lines,(<''),(<'top ',mode),<'rank id ',mode,' variable contribution'
        if. mode-:'t2' do.
            values =. t2_values
        else.
            values =. spe_values
        end.
        order =. values top_indices TopCount
        for_rank. i.#order do.
            index =. rank{order
            row =. index{::Diagnostics
            if. mode-:'t2' do.
                contributions =. z_t2_contributions row
            else.
                contributions =. z_spe_contributions row
            end.
            variable =. argmax contributions
            lines =. lines,<(integer rank+1),' ',(index{::AnalysisIDs),' ',(number index{values),' ',(variable{::Variables),' ',number variable{contributions
        end.
    end.
    lines =. lines,(<''),(<'reconstruction'),<'k mean_spe max_spe max_id'
    for_k. 1+i.(#Variables)-1 do.
        total =. 0.0
        maximum =. 0.0
        maximum_index =. _1
        for_i. i.#Scores do.
            row =. i{p_standardized Prepared
            residual =. pca_residual (<row),(<i{Scores),(<e_vectors EigenResult),<k
            spe =. residual dot residual
            total =. total+spe
            if. (maximum_index<0)+.spe>maximum do.
                maximum =. spe
                maximum_index =. i
            end.
        end.
        lines =. lines,<(integer k),' ',(number total%#AnalysisIDs),' ',(number maximum),' ',maximum_index{::AnalysisIDs
    end.
    header =. <'id'
    for_k. 1+i.count do.
        header =. header,<'pc',integer k
    end.
    header =. header,;:'t2 spe flag nearest distance'
    lines =. lines,(<''),(<'supplementary'),<' 'join header
    for_i. i.#SupplementaryIDs do.
        row =. i{::SupplementaryDiagnostics
        nearest =. i{Nearest
        fields =. (i{SupplementaryIDs),number&.>count{.i{SupplementaryScores
        fields =. fields,(<number z_t2 row),(<number z_spe row),(<z_flag row),((<.0{nearest){AnalysisIDs),<number 1{nearest
        lines =. lines,<' 'join fields
    end.
    lines
)
axes =: 3 : 0
    'grid row column' =. y
    for_index. i.1{$grid do.
        grid =. '-'(<row,index)}grid
    end.
    for_index. i.#grid do.
        grid =. '|'(<index,column)}grid
    end.
    '+'(<row,column)}grid
)
draw_points =: 3 : 0
    'grid cells' =. y
    counts =. ($grid)$0
    for_cell. cells do.
        counts =. (1+(<cell){counts)(<cell)}counts
    end.
    for_row. i.#grid do.
        for_column. i.1{$grid do.
            count =. (<row,column){counts
            if. count>0 do.
                if. count=1 do.
                    character =. '.'
                elseif. count<:3 do.
                    character =. 'o'
                else.
                    character =. '@'
                end.
                grid =. character (<row,column)}grid
            end.
        end.
    end.
    grid
)
inside_circle =: 3 : 0
    'row column center_row center_column radius' =. y
    horizontal =. column-center_column
    vertical =. 2*(row-center_row)
    ((horizontal*horizontal)+vertical*vertical)<:radius*radius
)
plots_report =: 3 : 0
    values =. e_values EigenResult
    width =. ScreeWidth
    kaiser =. <.(((c_average Retention)%0{values)*width)+0.5
    lines =. <'scree width ',(integer width),' kaiser_column ',integer kaiser
    for_k. i.#values do.
        value =. k{values
        length =. <.((value%0{values)*width)+0.5
        broken =. <.((((k{c_broken Retention)*(c_total Retention))%0{values)*width)+0.5
        lines =. lines,<'|',(scree_line width,length,kaiser,broken),'| pc',(integer k+1),' ',number value
    end.
    'width height' =. BiplotSize
    maximum_x =. >./|(0{"1 Scores),0{"1 SupplementaryScores
    maximum_y =. >./|(1{"1 Scores),1{"1 SupplementaryScores
    largest_x =. >./|0{"1 Loadings
    largest_y =. >./|1{"1 Loadings
    arrow_scale =. 0.9*((maximum_x%largest_x)<.maximum_y%largest_y)
    grid =. new_grid width,height
    'origin_row origin_column' =. point_cell 0.0,0.0,maximum_x,maximum_y,width,height
    grid =. axes (<grid),(<origin_row),<origin_column
    tips =. 0 2$0
    for_row. Loadings do.
        'tip_row tip_column' =. point_cell (arrow_scale*0{row),(arrow_scale*1{row),maximum_x,maximum_y,width,height
        tips =. tips,tip_row,tip_column
        for_cell. shaft origin_row,origin_column,tip_row,tip_column do.
            'shaft_row shaft_column character' =. cell
            grid =. (a.{~character)(<shaft_row,shaft_column)}grid
        end.
    end.
    cells =. 0 2$0
    for_row. Scores do.
        cells =. cells,point_cell (0{row),(1{row),maximum_x,maximum_y,width,height
    end.
    grid =. draw_points (<grid),<cells
    for_index. i.#cells do.
        if. '-'-:z_flag index{::Diagnostics do.
            continue.
        end.
        grid =. 'X'(<index{cells)}grid
    end.
    for_row. SupplementaryScores do.
        cell =. point_cell (0{row),(1{row),maximum_x,maximum_y,width,height
        grid =. '*'(<cell)}grid
    end.
    letters =. 'ABCDEFGHIJKL'
    for_j. i.#tips do.
        grid =. (j{letters)(<j{tips)}grid
    end.
    lines =. lines,(<''),(<'biplot pc1 pc2 width ',(integer width),' height ',integer height),<'x ',(number -maximum_x),' ',(number maximum_x),' y ',(number -maximum_y),' ',(number maximum_y),' arrow_scale ',number arrow_scale
    lines =. lines,frame grid
    for_j. i.#Variables do.
        lines =. lines,<(j{letters),' ',(j{::Variables),' ',reals 2{.j{Loadings
    end.
    width =. (2*Radius)+3
    height =. Radius+3
    center_row =. (<.Radius%2)+1
    center_column =. Radius+1
    grid =. new_grid width,height
    grid =. axes (<grid),(<center_row),<center_column
    for_row. i.height do.
        for_column. i.width do.
            if. -.inside_circle row,column,center_row,center_column,Radius do.
                continue.
            end.
            neighbors =. ((row-1),column),((row+1),column),(row,column-1),row,column+1
            neighbors =. _2]\neighbors
            boundary =. 0
            for_neighbor. neighbors do.
                if. -.inside_circle neighbor,center_row,center_column,Radius do.
                    boundary =. 1
                end.
            end.
            if. boundary do.
                grid =. '.'(<row,column)}grid
            end.
        end.
    end.
    for_j. i.#Correlations do.
        row =. j{Correlations
        cell_row =. center_row-<.((1{row)*(Radius%2))+0.5
        column =. center_column+<.((0{row)*Radius)+0.5
        grid =. (j{letters)(<cell_row,column)}grid
    end.
    lines =. lines,(<''),<'circle radius ',integer Radius
    lines =. lines,frame grid
    for_j. i.#Variables do.
        row =. j{Correlations
        squared =. ((0{row)*0{row)+(1{row)*1{row
        lines =. lines,<(j{letters),' ',(j{::Variables),' ',reals row,squared
    end.
    'width height' =. DiagnosticSize
    maximum_t2 =. 2.0*T2Limit
    maximum_spe =. 2.0*SpeLimit
    grid =. new_grid width,height
    'limit_row limit_column' =. diagnostic_cell T2Limit,SpeLimit,maximum_t2,maximum_spe,width,height
    grid =. axes (<grid),(<limit_row),<limit_column
    cells =. 0 2$0
    for_box. Diagnostics do.
        row =. >box
        cells =. cells,diagnostic_cell (z_t2 row),(z_spe row),maximum_t2,maximum_spe,width,height
    end.
    grid =. draw_points (<grid),<cells
    for_box. SupplementaryDiagnostics do.
        row =. >box
        cell =. diagnostic_cell (z_t2 row),(z_spe row),maximum_t2,maximum_spe,width,height
        grid =. '*'(<cell)}grid
    end.
    lines =. lines,(<''),<'diagnostic width ',(integer width),' height ',(integer height),' t2_max ',(number maximum_t2),' spe_max ',number maximum_spe
    lines,frame grid
)
save_lines =: 4 : 0
    contents =. ''
    for_line. y do.
        contents =. contents,(>line),LF
    end.
    contents 1!:2 <'output/',x
)
run =: 3 : 0
    read_inputs 0
    'Summaries Incomplete' =: summarize 0
    'AnalysisIDs AnalysisRows' =: analysis_data MissingStrategy
    Prepared =: prepare_pca (<AnalysisRows),<Scaling
    EigenResult =: jacobi p_values Prepared
    Powered =: power_iteration (<p_values Prepared),<EigenResult
    ParallelValues =: parallel_analysis (#AnalysisRows),#Variables
    Retention =: retention (<e_values EigenResult),(<ParallelValues),<#AnalysisRows
    count =. c_retained Retention
    'Loadings Communalities Correlations' =: loading_analysis (<e_values EigenResult),(<e_vectors EigenResult),(<p_values Prepared),<count
    Rotation =: varimax (<Loadings),<count
    Scores =: (p_standardized Prepared)pca_scores e_vectors EigenResult
    Diagnostics =: diagnose (<p_standardized Prepared),(<Scores),(<e_values EigenResult),(<e_vectors EigenResult),(<count),<1
    supplementary =. standardize_supplementary (<SupplementaryRows),(<p_means Prepared),<p_scales Prepared
    SupplementaryScores =: supplementary pca_scores e_vectors EigenResult
    SupplementaryDiagnostics =: diagnose (<supplementary),(<SupplementaryScores),(<e_values EigenResult),(<e_vectors EigenResult),(<count),<0
    Nearest =: supplementary_nearest (<SupplementaryScores),(<Scores),<count
    Adequacy =: sampling_adequacy (<p_correlation Prepared),<#AnalysisRows
    try.
        1!:5 <'output'
    catch.
    end.
    'eigen.txt' save_lines eigen_report 0
    'loadings.csv' save_lines loadings_report 0
    'scores.csv' save_lines scores_report 0
    'outliers.txt' save_lines outliers_report 0
    'plots.txt' save_lines plots_report 0
)
run 0
