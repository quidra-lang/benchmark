load 'dataset.ijs'
load 'numerics.ijs'
load 'estimators.ijs'
load 'group_tests.ijs'
load 'cox.ijs'
load 'plot.ijs'
text =: 3 : 0
    value =. ":y
    '-'(I.value='_')}value
)
integer =: 3 : 'text <.y'
number =: 3 : 0
    value =. (0j4":y)-.' '
    value =. '-'(I.value='_')}value
    if. value-:'-0.0000' do.
        value =. '0.0000'
    end.
    value
)
one_decimal =: 3 : 0
    value =. (0j1":y)-.' '
    value =. '-'(I.value='_')}value
    if. value-:'-0.0' do.
        value =. '0.0'
    end.
    value
)
optional_number =: 3 : 0
    if. y<0 do.
        'NA'
    else.
        number y
    end.
)
day =: 3 : 0
    if. y<0 do.
        'NA'
    else.
        integer y
    end.
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
integers =: 3 : ''' ''join integer&.>y'
group_subset =: 4 : 'x#~(1{"1 x)e.y'
event_count =: 3 : '+/3{"1 y'
variable_column =: 3 : '5+-.y-:''sex'''
level_text =: 4 : 0
    if. x-:'sex' do.
        y{'FM'
    else.
        integer y
    end.
)
percentile_time =: 3 : 0
    'rows threshold column' =. y
    for_row. rows do.
        value =. column{row
        if. 0=4{row do.
            value =. 0.0
        end.
        if. (value>:0)*.value<:threshold do.
            <.0{row return.
        end.
    end.
    _1
)
restricted_mean =: 4 : 0
    selected =. x#~y>:0{"1 x
    moments =. 0,(<.0{"1 selected),y
    survival =. 1.0,4{"1 selected
    count =. #survival
    tails =. count$0.0
    for_index. |.i.count do.
        rectangle =. (index{survival)*((index+1){moments)-index{moments
        if. index=count-1 do.
            value =. rectangle
        else.
            value =. rectangle+(index+1){tails
        end.
        tails =. value index}tails
    end.
    variance =. 0.0
    for_index. i.#selected do.
        n =. <.(<index,1){selected
        d =. <.(<index,2){selected
        tail =. (index+1){tails
        variance =. variance+(tail*tail)*d fraction n*(n-d)
    end.
    estimate =. 0{tails
    standard_error =. %:variance
    estimate,standard_error,(estimate-Z95*standard_error),estimate+Z95*standard_error
)
s_rows =: 0&{::
s_life =: 1&{::
s_count =: 2&{::
s_events =: 3&{::
s_maximum =: 4&{::
s_days =: 5&{::
s_rate =: 6&{::
s_rate_lower =: 7&{::
s_rate_upper =: 8&{::
s_followup =: 9&{::
s_life_median =: 10&{::
s_percentiles =: 11&{::
s_rmst =: 12&{::
summarize =: 3 : 0
    subjects =. y
    rows =. kaplan_meier subjects
    life =. life_table (<subjects),(<LifeWidth),<LifeIntervals
    events =. event_count subjects
    days =. +/2{"1 subjects
    maximum =. >./2{"1 subjects
    reverse =. subjects
    for_index. i.#reverse do.
        reverse =. (1-(<index,3){subjects)(<index,3)}reverse
    end.
    rate =. (1000*events)fraction days
    eta =. Z95%%:events
    life_median =. _1.0
    previous =. 1.0
    for_row. life do.
        if. (7{row)<:0.5 do.
            life_median =. (0{row)+((LifeWidth*(previous-0.5))%(previous-7{row))
            break.
        end.
        previous =. 7{row
    end.
    percentiles =. 0 4$0
    for_index. i.3 do.
        threshold =. index{0.75 0.5 0.25
        percentile =. 25*index+1
        for_column. 4 6 7 do.
            percentile =. percentile,percentile_time (<rows),(<threshold),<column
        end.
        percentiles =. percentiles,percentile
    end.
    followup =. percentile_time (<kaplan_meier reverse),(<0.5),<4
    (<rows),(<life),(<#subjects),(<events),(<maximum),(<days),(<rate),(<^(^.rate)-eta),(<^(^.rate)+eta),(<followup),(<life_median),(<percentiles),<rows restricted_mean Tau
)
km_lines =: 3 : 0
    'name subjects summary' =. y
    lines =. <'group ',name,' subjects ',(integer #subjects),' events ',(integer s_events summary),' censored ',(integer (#subjects)-s_events summary),' max_time ',integer s_maximum summary
    lines =. lines,<'person_days ',(integer s_days summary),' rate ',(number s_rate summary),' lower ',(number s_rate_lower summary),' upper ',number s_rate_upper summary
    lines =. lines,<'followup_median ',day s_followup summary
    lines =. lines,<'life_table_median ',optional_number s_life_median summary
    for_row. s_percentiles summary do.
        lines =. lines,<'percentile ',(integer 0{row),' time ',(day 1{row),' lower ',(day 2{row),' upper ',day 3{row
    end.
    rmst =. s_rmst summary
    lines =. lines,<'rmst tau ',(integer Tau),' estimate ',(number 0{rmst),' se ',(number 1{rmst),' lower ',(number 2{rmst),' upper ',number 3{rmst
    for_moment. ReportTimes do.
        row =. (s_rows summary)row_at moment
        risk =. +/moment<:2{"1 subjects
        events =. +/(moment>:2{"1 subjects)*.3{"1 subjects
        lines =. lines,<'at ',(integer moment),' at_risk ',(integer risk),' events ',(integer events),' survival ',(number 4{row),' std_err ',(optional_number 5{row),' lower ',(optional_number 6{row),' upper ',(optional_number 7{row),' cum_hazard ',(number 8{row),' hazard_se ',number 9{row
    end.
    lines =. lines,<'     time  at_risk   events censored survival  std_err    lower    upper  cum_haz   haz_se'
    for_row. s_rows summary do.
        fields =. integer&.>4{.row
        fields =. fields,(<number 4{row),(optional_number&.>5 6 7{row),number&.>8 9{row
        line =. ''
        for_box. fields do.
            value =. >box
            line =. line,((9-#value)#' '),value
        end.
        lines =. lines,<line
    end.
    lines
)
life_lines =: 3 : 0
    lines =. <'group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard'
    for_index. i.#Names do.
        summary =. index{::Summaries
        for_row. s_life summary do.
            fields =. (index{Names),<(integer 0{row),'-',integer 1{row
            fields =. fields,(integer&.>2 3 4{row),(<one_decimal 5{row),number&.>6 7 8 9{row
            lines =. lines,<','join fields
        end.
    end.
    lines
)
baseline_line =: 3 : 0
    'name subjects' =. y
    count =. #subjects
    ages =. 4{"1 subjects
    mean =. (+/ages)fraction count
    variance =. 0.0
    for_age. ages do.
        difference =. age-mean
        variance =. variance+difference*difference
    end.
    ages =. /:~ages
    median =. (((<.(count-1)%2){ages)+(<.count%2){ages)%2.0
    stages =. i.0
    for_stage. 1+i.4 do.
        stages =. stages,+/stage=6{"1 subjects
    end.
    '  group ',name,' subjects ',(integer count),' age_mean ',(number mean),' age_sd ',(number %:variance%(count-1)),' age_median ',(one_decimal median),' male ',(integer +/5{"1 subjects),' stage ',integers stages
)
kruskal =: 3 : 0
    order =. /:(4{"1 Subjects),.0{"1 Subjects
    ranks =. (#Subjects)$0.0
    ties =. 0
    position =. 0
    while. position<#order do.
        finish =. position
        while. finish<#order do.
            if. ((<(finish{order),4){Subjects)~:(<(position{order),4){Subjects do.
                break.
            end.
            finish =. finish+1
        end.
        rank =. ((position+1)+finish)%2.0
        indices =. (position+i.finish-position){order
        ranks =. rank indices}ranks
        count =. finish-position
        ties =. (ties+((count*count)*count))-count
        position =. finish
    end.
    weighted =. 0.0
    for_group. i.#Groups do.
        mask =. group=1{"1 Subjects
        sum =. ordered_sum mask#ranks
        weighted =. weighted+(sum*sum)%+/mask
    end.
    count =. #Subjects
    raw =. ((12.0*weighted)%(count*(count+1)))-3*(count+1)
    raw%(1.0-ties fraction ((count*count)*count)-count)
)
contingency =: 3 : 0
    column =. variable_column y
    levels =. /:~~.column{"1 Subjects
    statistic =. 0.0
    for_group. i.#Groups do.
        members =. Subjects group_subset ,group
        for_level. levels do.
            column_count =. +/level=column{"1 Subjects
            observed =. +/level=column{"1 members
            expected =. ((#members)*column_count)fraction #Subjects
            difference =. observed-expected
            statistic =. statistic+(difference*difference)%expected
        end.
    end.
    statistic,((#Groups)-1)*((#levels)-1)
)
baseline_lines =: 3 : 0
    lines =. <'baseline'
    for_index. i.#Names do.
        lines =. lines,<baseline_line (index{Names),<index{::Collections
    end.
    statistic =. kruskal 0
    degrees =. (#Groups)-1
    lines =. lines,<'  age kruskal_wallis chisq ',(number statistic),' df ',(integer degrees),' p ',number statistic chi_p degrees
    for_variable. ;:'sex stage' do.
        'statistic degrees' =. contingency >variable
        lines =. lines,<'  ',(>variable),' chisq ',(number statistic),' df ',(integer degrees),' p ',number statistic chi_p degrees
    end.
    lines
)
group_lines =: 3 : 0
    lines =. 0$a:
    for_index. i.#t_groups y do.
        name =. ((index{t_groups y){::Groups)
        observed =. index{t_observed y
        expected =. index{t_expected y
        variance =. (<index,index){t_covariance y
        lines =. lines,<'  group ',name,' events ',(integer index{t_events y),' observed ',(number observed),' expected ',(number expected),' o_minus_e ',(number observed-expected),' variance ',number variance
    end.
    lines
)
test_fields =: 3 : '''chisq '',(number t_statistic y),'' df '',(integer t_degrees y),'' p '',number t_probability y'
overall_lines =: 3 : 0
    lines =. 0$a:
    stored =. 0$a:
    for_weight. i.3 do.
        result =. weighted_test (<Subjects),(<i.#Groups),(<weight),<#Subjects
        stored =. stored,<result
        lines =. lines,(<'test ',(weight{::Weights),' ',test_fields result),group_lines result
    end.
    logrank =. 0{::stored
    trend =. 0.0
    variance =. 0.0
    for_g. i.#Groups do.
        trend =. trend+(g+1)*((g{t_observed logrank)-g{t_expected logrank)
        inner =. 0.0
        for_h. i.#Groups do.
            inner =. inner+((g+1)*(h+1))*(<g,h){t_covariance logrank
        end.
        variance =. variance+inner
    end.
    statistic =. (trend*trend)%variance
    lines,<'test logrank_trend chisq ',(number statistic),' df 1 p ',number statistic chi_p 1
)
stratified_lines =: 3 : 0
    variable =. Strata
    column =. variable_column variable
    levels =. /:~~.column{"1 Subjects
    strata =. 0$a:
    for_level. levels do.
        strata =. strata,<Subjects#~level=column{"1 Subjects
    end.
    lines =. 0$a:
    for_weight. i.3 do.
        results =. 0$a:
        for_box. strata do.
            results =. results,<weighted_test (< >box),(<i.#Groups),(<weight),<#Subjects
        end.
        combined =. combine_strata (<results),<i.#Groups
        lines =. lines,<'stratified ',(weight{::Weights),' by ',variable,' ',test_fields combined
        for_index. i.#levels do.
            result =. index{::results
            members =. index{::strata
            lines =. lines,<'  stratum ',(variable level_text index{levels),' subjects ',(integer #members),' events ',(integer event_count members),' chisq ',(number t_statistic result),' p ',number t_probability result
        end.
        lines =. lines,group_lines combined
    end.
    lines
)
landmark_lines =: 3 : 0
    selected =. Subjects#~Landmark<2{"1 Subjects
    result =. weighted_test (<selected),(<i.#Groups),(<0),<#Subjects
    (<'landmark ',(integer Landmark),' subjects ',(integer #selected),' ',test_fields result),group_lines result
)
q_test =: 0&{::
q_ratio =: 1&{::
q_variance =: 2&{::
q_log_ratio =: 3&{::
q_lower =: 4&{::
q_upper =: 5&{::
two_group =: 3 : 0
    'subjects groups' =. y
    result =. weighted_test (<subjects),(<groups),(<0),<#Subjects
    observed =. t_observed result
    expected =. t_expected result
    ratio =. ((1{observed)%1{expected)%((0{observed)%0{expected)
    variance =. (1.0%0{expected)+1.0%1{expected
    logarithm =. ^.ratio
    lower =. ^logarithm-Z95*%:variance
    upper =. ^logarithm+Z95*%:variance
    (<result),(<ratio),(<variance),(<logarithm),(<lower),<upper
)
pairwise_lines =: 3 : 0
    pairs =. 0 2$0
    results =. 0$a:
    for_a. i.(#Groups)-1 do.
        for_b. (a+1)+i.(#Groups)-a+1 do.
            pair =. a,b
            pairs =. pairs,pair
            selected =. Subjects group_subset pair
            results =. results,<two_group (<selected),<pair
        end.
    end.
    probabilities =. t_probability@q_test&>results
    order =. /:probabilities,.i.#pairs
    adjusted =. (#pairs)$0.0
    previous =. 0.0
    for_rank. i.#order do.
        index =. rank{order
        candidate =. ((#pairs)-rank)*index{probabilities
        previous =. previous>.1.0<.candidate
        adjusted =. previous index}adjusted
    end.
    lines =. <'pairwise logrank adjust holm'
    for_index. i.#pairs do.
        'a b' =. index{pairs
        result =. index{::results
        weighted =. q_test result
        lines =. lines,<'  ',(a{::Groups),' ',(b{::Groups),' chisq ',(number t_statistic weighted),' p ',(number t_probability weighted),' p_holm ',(number index{adjusted),' hr ',(number q_ratio result),' lower ',(number q_lower result),' upper ',number q_upper result
    end.
    lines
)
subgroup_lines =: 3 : 0
    lines =. <'subgroups reference ',0{::Groups
    for_box. Subgroups do.
        variable =. >box
        column =. variable_column variable
        levels =. /:~~.column{"1 Subjects
        for_b. 1+i.(#Groups)-1 do.
            results =. 0$a:
            for_level. levels do.
                selected =. (Subjects group_subset 0,b)
                selected =. selected#~level=column{"1 selected
                result =. two_group (<selected),<0,b
                results =. results,<result
                weighted =. q_test result
                lines =. lines,<'  ',variable,' ',(variable level_text level),' ',(b{::Groups),' subjects ',(integer #selected),' events ',(integer event_count selected),' hr ',(number q_ratio result),' lower ',(number q_lower result),' upper ',(number q_upper result),' p ',number t_probability weighted
            end.
            numerator =. 0.0
            denominator =. 0.0
            for_box. results do.
                result =. >box
                weight =. 1.0%q_variance result
                numerator =. numerator+weight*q_log_ratio result
                denominator =. denominator+weight
            end.
            mean =. numerator%denominator
            statistic =. 0.0
            for_box. results do.
                result =. >box
                difference =. (q_log_ratio result)-mean
                statistic =. statistic+((1.0%q_variance result)*difference)*difference
            end.
            degrees =. (#levels)-1
            lines =. lines,<'  ',variable,' ',(b{::Groups),' heterogeneity chisq ',(number statistic),' df ',(integer degrees),' p ',number statistic chi_p degrees
        end.
    end.
    lines
)
difference_fields =: 3 : 0
    'difference standard_error' =. y
    statistic =. difference%standard_error
    'difference ',(number difference),' se ',(number standard_error),' lower ',(number difference-Z95*standard_error),' upper ',(number difference+Z95*standard_error),' z ',(number statistic),' p ',number (statistic*statistic)chi_p 1
)
rmst_lines =: 3 : 0
    lines =. <'rmst_difference tau ',(integer Tau),' reference ',0{::Groups
    control =. s_rmst 0{::Summaries
    for_index. 1+i.(#Groups)-1 do.
        row =. s_rmst index{::Summaries
        standard_error =. %:((1{row)*1{row)+(1{control)*1{control
        lines =. lines,<'  ',(index{::Groups),' ',difference_fields ((0{row)-0{control),standard_error
    end.
    lines
)
rate_lines =: 3 : 0
    lines =. <'rate_ratio reference ',0{::Groups
    control =. 0{::Summaries
    for_index. 1+i.(#Groups)-1 do.
        row =. index{::Summaries
        ratio =. (s_rate row)%s_rate control
        standard_error =. %:(1 fraction s_events row)+1 fraction s_events control
        logarithm =. ^.ratio
        statistic =. logarithm%standard_error
        lines =. lines,<'  ',(index{::Groups),' ratio ',(number ratio),' lower ',(number ^logarithm-Z95*standard_error),' upper ',(number ^logarithm+Z95*standard_error),' z ',(number statistic),' p ',number (statistic*statistic)chi_p 1
    end.
    lines
)
survival_lines =: 3 : 0
    lines =. <'survival_difference reference ',0{::Groups
    for_moment. ReportTimes do.
        control =. (s_rows 0{::Summaries)row_at moment
        for_index. 1+i.(#Groups)-1 do.
            row =. (s_rows index{::Summaries)row_at moment
            standard_error =. %:((5{row)*5{row)+(5{control)*5{control
            lines =. lines,<'  at ',(integer moment),' ',(index{::Groups),' ',difference_fields ((4{row)-4{control),standard_error
        end.
    end.
    lines
)
is_group =: 3 : '-.(<y)e.;:''age male stage'''
covariate_vectors =: 3 : 0
    vectors =. (0,#Covariates)$0
    for_subject. Subjects do.
        values =. i.0
        for_box. Covariates do.
            name =. >box
            if. name-:'age' do.
                value =. 4{subject
            elseif. name-:'male' do.
                value =. 5{subject
            elseif. name-:'stage' do.
                value =. 6{subject
            else.
                value =. name-:(1{subject){::Groups
            end.
            values =. values,value
        end.
        vectors =. vectors,values
    end.
    vectors
)
coefficient_fields =: 3 : 0
    'coefficient standard_error' =. y
    statistic =. coefficient%standard_error
    'coef ',(number coefficient),' se ',(number standard_error),' z ',(number statistic),' p ',(number (statistic*statistic)chi_p 1),' hr ',(number ^coefficient),' lower ',(number ^coefficient-Z95*standard_error),' upper ',number ^coefficient+Z95*standard_error
)
coefficient_lines =: 3 : 0
    'beta covariance' =. y
    lines =. 0$a:
    for_index. i.#Covariates do.
        standard_error =. %:(<index,index){covariance
        lines =. lines,<'term ',(index{::Covariates),' ',coefficient_fields (index{beta),standard_error
    end.
    for_a. i.(#Covariates)-1 do.
        if. -.is_group a{::Covariates do.
            continue.
        end.
        for_b. (a+1)+i.(#Covariates)-a+1 do.
            if. -.is_group b{::Covariates do.
                continue.
            end.
            coefficient =. (b{beta)-a{beta
            standard_error =. %:(((<b,b){covariance)+(<a,a){covariance)-2.0*(<a,b){covariance
            lines =. lines,<'contrast ',(b{::Covariates),' vs ',(a{::Covariates),' ',coefficient_fields coefficient,standard_error
        end.
    end.
    lines
)
cox_tests =: 3 : 0
    'vectors model' =. y
    size =. #Covariates
    beta =. m_beta model
    final =. m_final model
    null =. m_null model
    likelihood_ratio =. 2.0*((c_loglik final)-c_loglik null)
    information =. c_information final
    wald =. 0.0
    for_c. i.size do.
        inner =. 0.0
        for_d. i.size do.
            inner =. inner+((<c,d){information)*d{beta
        end.
        wald =. wald+(c{beta)*inner
    end.
    solution =. solve (<c_information null),<c_score null
    score =. ordered_sum (c_score null)*solution
    labels =. ;:'likelihood_ratio wald score'
    statistics =. likelihood_ratio,wald,score
    lines =. 0$a:
    for_index. i.3 do.
        statistic =. index{statistics
        lines =. lines,<(index{::labels),' chisq ',(number statistic),' df ',(integer size),' p ',number statistic chi_p size
    end.
    for_omitted. i.size do.
        likelihood =. c_loglik null
        if. size>:2 do.
            columns =. (i.size)-.omitted
            reduced =. columns{"1 vectors
            reduced_model =. cox_fit (<Subjects),<reduced
            likelihood =. c_loglik m_final reduced_model
        end.
        statistic =. 2.0*((c_loglik final)-likelihood)
        lines =. lines,<'drop ',(omitted{::Covariates),' loglik ',(number likelihood),' chisq ',(number statistic),' df 1 p ',number statistic chi_p 1
    end.
    lines
)
concordance_line =: 3 : 0
    'vectors predictors' =. y
    comparable =. 0
    concordant =. 0
    tied =. 0
    for_i. i.#Subjects do.
        first =. i{Subjects
        if. 0=3{first do.
            continue.
        end.
        for_j. i.#Subjects do.
            second =. j{Subjects
            qualifies =. ((2{first)<2{second)+.((2{first)=2{second)*.0=3{second
            if. (i=j)+.-.qualifies do.
                continue.
            end.
            comparable =. comparable+1
            if. (i{vectors)-:j{vectors do.
                tied =. tied+1
            elseif. (i{predictors)>j{predictors do.
                concordant =. concordant+1
            end.
        end.
    end.
    value =. ((2*concordant)+tied)fraction 2*comparable
    'concordance ',(number value),' comparable ',(integer comparable),' concordant ',(integer concordant),' tied ',integer tied
)
ph_lines =: 3 : 0
    'vectors event_sums' =. y
    events =. I.3{"1 Subjects
    order =. /:((events{2{"1 Subjects),.events{0{"1 Subjects)
    events =. order{events
    moments =. i.0
    for_box. event_sums do.
        moments =. moments,0{::>box
    end.
    count =. #events
    mean_time =. (+/events{2{"1 Subjects)fraction count
    lines =. 0$a:
    for_c. i.#Covariates do.
        residuals =. i.0
        for_index. events do.
            moment =. (<index,2){Subjects
            sums =. (moments i.moment){::event_sums
            s0 =. 2{::sums
            s1 =. 3{::sums
            residuals =. residuals,((<index,c){vectors)-(c{s1)%s0
        end.
        mean =. (ordered_sum residuals)%count
        sxy =. 0.0
        sxx =. 0.0
        syy =. 0.0
        for_position. i.count do.
            index =. position{events
            x =. (position{residuals)-mean
            z =. ((<index,2){Subjects)-mean_time
            sxy =. sxy+x*z
            sxx =. sxx+x*x
            syy =. syy+z*z
        end.
        correlation =. sxy%%:sxx*syy
        statistic =. (0.5*^.(1.0+correlation)%(1.0-correlation))*%:count-3
        lines =. lines,<'ph_check ',(c{::Covariates),' rho ',(number correlation),' z ',(number statistic),' p ',number (statistic*statistic)chi_p 1
    end.
    lines
)
baseline_hazard =: 3 : 0
    cumulative =. 0.0
    rows =. 0 2$0.0
    for_box. |.y do.
        sums =. >box
        cumulative =. cumulative+(1{::sums)%2{::sums
        rows =. rows,(0{::sums),cumulative
    end.
    rows
)
hazard_at =: 4 : 0
    for_row. |.x do.
        if. (0{row)<:y do.
            1{row return.
        end.
    end.
    0.0
)
residual_lines =: 3 : 0
    'predictors hazard' =. y
    residuals =. 0 2$0.0
    for_index. i.#Subjects do.
        subject =. index{Subjects
        martingale =. (3{subject)-(hazard hazard_at 2{subject)*^index{predictors
        if. 3{subject do.
            deviance =. %:_2.0*(martingale+^.1.0-martingale)
        else.
            deviance =. %:_2.0*martingale
        end.
        if. martingale<:0 do.
            deviance =. -deviance
        end.
        residuals =. residuals,martingale,deviance
    end.
    order =. /:(-|1{"1 residuals),.0{"1 Subjects
    lines =. <'residuals top ',integer ResidualCount
    for_index. ResidualCount{.order do.
        subject =. index{Subjects
        'martingale deviance' =. index{residuals
        lines =. lines,<'  id ',(integer 0{subject),' group ',((1{subject){::Groups),' time ',(integer 2{subject),' event ',(integer 3{subject),' martingale ',(number martingale),' deviance ',number deviance
    end.
    lines
)
adjusted_lines =: 3 : 0
    'vectors beta hazard' =. y
    means =. (#Covariates)$0.0
    fields =. 0$a:
    for_c. i.#Covariates do.
        name =. c{::Covariates
        if. -.is_group name do.
            mean =. (+/c{"1 vectors)fraction #vectors
            means =. mean c}means
            fields =. fields,<name,' ',number mean
        end.
    end.
    if. 0=#fields do.
        fields =. <'none'
    end.
    lines =. <'adjusted_survival mean ',' 'join fields
    risks =. i.0
    for_group. Groups do.
        predictor =. 0.0
        for_c. i.#Covariates do.
            name =. c{::Covariates
            if. is_group name do.
                value =. name-:>group
            else.
                value =. c{means
            end.
            predictor =. predictor+(c{beta)*value
        end.
        risks =. risks,^predictor
    end.
    for_moment. ReportTimes do.
        fields =. 0$a:
        cumulative =. hazard hazard_at moment
        for_index. i.#Groups do.
            fields =. fields,<(index{::Groups),' ',number ^(-cumulative)*index{risks
        end.
        lines =. lines,<'  at ',(integer moment),' ',' 'join fields
    end.
    fields =. 0$a:
    for_index. i.#Groups do.
        median =. _1
        for_row. hazard do.
            if. (^(-(1{row))*index{risks)<:0.5 do.
                median =. <.0{row
                break.
            end.
        end.
        fields =. fields,<(index{::Groups),' ',day median
    end.
    lines,<'  median ',' 'join fields
)
cox_lines =: 3 : 0
    vectors =. covariate_vectors 0
    model =. cox_fit (<Subjects),<vectors
    final =. m_final model
    null =. m_null model
    covariance =. inverse c_information final
    event_sums =. c_event_sums final
    lines =. <'cox covariates ',(' 'join Covariates),' subjects ',(integer #Subjects),' events ',(integer event_count Subjects),' event_times ',integer #event_sums
    for_box. m_iterations model do.
        'iteration likelihood beta' =. >box
        lines =. lines,<'iter ',(integer iteration),' loglik ',(number likelihood),' beta ',' 'join number&.>beta
    end.
    lines =. lines,<'final loglik ',(number c_loglik final),' null_loglik ',number c_loglik null
    lines =. lines,coefficient_lines (<m_beta model),<covariance
    lines =. lines,cox_tests (<vectors),<model
    lines =. lines,<concordance_line (<vectors),<c_predictors final
    lines =. lines,ph_lines (<vectors),<event_sums
    hazard =. baseline_hazard event_sums
    lines =. lines,residual_lines (<c_predictors final),<hazard
    lines,adjusted_lines (<vectors),(<m_beta model),<hazard
)
plot_lines =: 3 : 0
    'width height time_limit divisions' =. PlotSize
    legend =. 0$a:
    estimates =. 0$a:
    for_index. i.#Groups do.
        legend =. legend,<(index{'ABCDEF'),' ',index{::Groups
        estimates =. estimates,<s_rows index{::Summaries
    end.
    lines =. (<'km_plot width ',(integer width),' height ',(integer height),' time ',integer time_limit),<'legend ',' 'join legend
    lines =. lines,curve_lines (<(#Groups){.Collections),(<estimates),(<width),(<height),<time_limit
    lines =. lines,<'time 0 to ',(integer time_limit),' days, ',(integer <.time_limit%width),' days per column'
    moments =. (i.divisions+1)*<.time_limit%divisions
    lines =. lines,<'at_risk ',integers moments
    for_group. i.#Groups do.
        members =. group{::Collections
        counts =. i.0
        for_moment. moments do.
            counts =. counts,+/moment<:2{"1 members
        end.
        lines =. lines,<(group{::Groups),' ',integers counts
    end.
    lines
)
join_sections =: 3 : 0
    lines =. 0$a:
    for_index. i.#y do.
        if. index do.
            lines =. lines,<''
        end.
        lines =. lines,index{::y
    end.
    lines
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
    Names =: Groups,<'all'
    Collections =: 0$a:
    Summaries =: 0$a:
    tables =. 0$a:
    for_index. i.#Names do.
        if. index=#Groups do.
            members =. Subjects
        else.
            members =. Subjects group_subset ,index
        end.
        Collections =: Collections,<members
        summary =. summarize members
        Summaries =: Summaries,<summary
        tables =. tables,<km_lines (index{Names),(<members),<summary
    end.
    sections =. (<baseline_lines 0),(<overall_lines 0),(<stratified_lines 0),(<landmark_lines 0),(<pairwise_lines 0),(<subgroup_lines 0),(<rmst_lines 0),(<rate_lines 0),<survival_lines 0
    try.
        1!:5 <'output'
    catch.
    end.
    'km_tables.txt' save_lines join_sections tables
    'life_table.csv' save_lines life_lines 0
    'tests.txt' save_lines join_sections sections
    'cox.txt' save_lines cox_lines 0
    'km_plot.txt' save_lines plot_lines 0
)
run 0
