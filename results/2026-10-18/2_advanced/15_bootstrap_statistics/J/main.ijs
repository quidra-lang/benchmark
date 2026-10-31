ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
div =: 4 : '_1 x:<.(x:x)%x:y'
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
text_line =: 3 : 0
    fields =. 0$a:
    for_box. y do.
        value =. >box
        if. 2~:3!:0 value do. value =. number value end.
        fields =. fields,<value
    end.
    ' ' join fields
)
load SourceDirectory,'dataset.ijs'
load SourceDirectory,'minstd.ijs'
load SourceDirectory,'resampling.ijs'
load SourceDirectory,'tests.ijs'
load SourceDirectory,'report.ijs'
GroupStatistics =: 'mean';'median';'trimmed_mean';'sd'
PairStatistics =: 'mean_diff';'median_ratio';'hodges_lehmann';'cohen_d'
TestStatistics =: 'mean';'median';'ranksum';'absdev'
ceil_div =: 4 : '((x+y)-1)div y'
summary =: 4 : 0
    estimate =. x
    values =. y
    ordered =. /:~values
    'average se' =. mean_and_se values
    low =. (LowRank-1){ordered
    high =. (HighRank-1){ordered
    (<estimate),(<values),(<ordered),(<average),(<se),(<average-estimate),(<low),(<high),(<(2*estimate)-high),<(2*estimate)-low
)
interval_text =: 3 : 0
    'se | bias | percentile | | basic | |' format real_text&.>(4 5 6 7 8 9){y
)
group_bootstrap =: 4 : 0
    group =. x
    indices =. y
    values =. group{::Groups
    samples =. indices{values
    estimates =. group_statistics values
    statistics =. (0,4)$0.0
    for_sample. samples do. statistics =. statistics,group_statistics sample end.
    summaries =. 0$a:
    for_statistic. i.4 do. summaries =. summaries,<(statistic{estimates)summary statistic{"1 statistics end.
    (<group),(<indices),(<samples),<summaries
)
pair_bootstrap =: 3 : 0
    'first second' =. y
    x =. first{::Groups
    values =. second{::Groups
    estimates =. x pair_statistics values
    firstsamples =. 2{::first{::Ordinary
    secondsamples =. 2{::second{::Ordinary
    statistics =. (0,4)$0.0
    for_index. i.Bootstrap do. statistics =. statistics,(index{firstsamples)pair_statistics index{secondsamples end.
    summaries =. 0$a:
    for_statistic. i.4 do. summaries =. summaries,<(statistic{estimates)summary statistic{"1 statistics end.
    name =. (first{::GroupNames),'-',second{::GroupNames
    (<first),(<second),(<name),<summaries
)
paired_bootstrap =: 3 : 0
    means =. correlations =. 0$0.0
    for_indices. (#Differences)ordinary_indices Bootstrap do.
        means =. means,mean indices{Differences
        correlations =. correlations,(indices{Before)correlation indices{After
    end.
    (<(mean Differences)summary means),<(Before correlation After)summary correlations
)
jackknife_spread =: 3 : 0
    count =. #y
    average =. (sequential_sum y)%count
    differences =. y-average
    squares =. sequential_sum differences*differences
    average,((count-1)*squares)%count
)
jackknife =: 4 : 0
    'average variance' =. jackknife_spread y
    (<y),(<average),(<variance),(<((#y)-1)*(average-x)),<%:variance
)
tally_count =: 4 : 0
    'observed extreme greater' =. x
    observed,(extreme+(|y)>:|observed),greater+y>:observed
)
tally_text =: 4 : 0
    'observed extreme greater' =. x
    'offset denominator' =. y
    'extreme | greater | p_two | p_greater |' format (<extreme),(<greater),(<(extreme+offset)p_value denominator),<(greater+offset)p_value denominator
)
display_position =: 4 : 0
    'low delta' =. x
    ((120*(y-100*low))+delta)div 2*delta
)
series_lines =: 3 : 0
    'kind name values display stems' =. y
    'low delta' =. display
    count =. #values
    average =. mean values
    deviation =. sd values
    'second third fourth' =. central_moments values
    clipped =. winsorized values
    firstquartile =. 25 quantile_numerator values
    thirdquartile =. 75 quantile_numerator values
    outliers =. I.((200*values)<(5*firstquartile)-3*thirdquartile)+.(200*values)>(5*thirdquartile)-3*firstquartile
    inside =. values#~-. (i.count)e.outliers
    whiskers =. (<./inside),>./inside
    band =. 61#'.'
    first =. display display_position 100*0{whiskers
    last =. display display_position 100*1{whiskers
    band =. '-' (first+i.1+last-first)}band
    first =. display display_position firstquartile
    last =. display display_position thirdquartile
    band =. '=' (first+i.1+last-first)}band
    band =. '|' (display display_position 50 quantile_numerator values)}band
    for_index. outliers do. band =. 'o' (display display_position 100*index{values)}band end.
    percentiles =. 0$a:
    for_percent. 5 10 90 95 do.
        label =. 'p',((percent<10)#'0'),number percent
        percentiles =. percentiles,<'| |' format (<label),<real_text (percent quantile_numerator values)%10000
    end.
    lines =. <kind,' ',name
    lines =. lines,<'n ',number count
    lines =. lines,<'mean ',real_text average
    lines =. lines,<'median ',real_text median values
    lines =. lines,<'trimmed_mean | trim |' format (<real_text trimmed_mean values),<trim_count count
    lines =. lines,<'winsorized_mean | winsorized_sd |' format (<real_text mean clipped),<real_text sd clipped
    lines =. lines,<'sd ',real_text deviation
    lines =. lines,<'se_mean ',real_text deviation%%:count
    lines =. lines,<'cv ',real_text deviation%average
    lines =. lines,<'skewness ',real_text third%(second*%:second)
    lines =. lines,<'kurtosis ',real_text (fourth%(second*second))-3
    lines =. lines,<'mad ',real_text mad values
    lines =. lines,<'min ',real_text (<./values)%100
    lines =. lines,<'q1 ',real_text firstquartile%10000
    lines =. lines,<'q3 ',real_text thirdquartile%10000
    lines =. lines,<'iqr ',real_text (thirdquartile-firstquartile)%10000
    lines =. lines,<'max ',real_text (>./values)%100
    lines =. lines,<'percentiles ',' ' join percentiles
    lines =. lines,<'whiskers | |' format real_text&.><"0 whiskers%100
    lines =. lines,<'outliers ',number_list outliers+1
    lines =. lines,<'box ',band
    if. stems do.
        ordered =. /:~values
        first =. ({.ordered)div 100
        last =. ({:ordered)div 100
        for_stem. first+i.1+last-first do.
            selected =. ordered#~stem=ordered div 100
            leaves =. Digits{~(100|selected)div 10
            text =. 'stem ',number stem
            if. #leaves do. text =. text,' ',leaves end.
            lines =. lines,<text
        end.
    end.
    lines
)
descriptive_lines =: 3 : 0
    combined =. ;Groups
    display =. (<./combined),100*((>./combined)-<./combined)
    lines =. <'groups | observations |' format (<GroupCount),<#combined
    for_group. i.GroupCount do.
        lines =. lines,series_lines (<'group'),(group{GroupNames),(group{Groups),(<display),<1
    end.
    lines =. lines,<'paired subjects ',number #Differences
    combined =. Before,After
    display =. (<./combined),100*((>./combined)-<./combined)
    lines =. lines,series_lines (<'series'),(<'before'),(<Before),(<display),<0
    lines =. lines,series_lines (<'series'),(<'after'),(<After),(<display),<0
    display =. (<./Differences),100*((>./Differences)-<./Differences)
    lines,series_lines (<'series'),(<'diff'),(<Differences),(<display),<0
)
summary_csv =: 4 : 0
    fields =. x,real_text&.>(0 4 5 6 7 8 9){y
    ',' join fields
)
bootstrap_lines =: 3 : 0
    lines =. <'group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi'
    for_group. i.GroupCount do.
        plain =. 3{::group{::Ordinary
        even =. 3{::group{::Balanced
        for_statistic. i.4 do.
            lines =. lines,<((group{GroupNames),statistic{GroupStatistics)summary_csv statistic{::plain
        end.
        for_statistic. i.4 do.
            name =. 'balanced_',statistic{::GroupStatistics
            lines =. lines,<((group{GroupNames),<name)summary_csv statistic{::even
        end.
    end.
    for_box. Pairs do.
        pair =. >box
        summaries =. 3{::pair
        for_statistic. i.4 do. lines =. lines,<((2{pair),statistic{PairStatistics)summary_csv statistic{::summaries end.
    end.
    lines
)
bca_alpha =: 3 : 0
    'z0 acceleration z' =. y
    phi z0+(z0+z)%1-acceleration*(z0+z)
)
bca_line =: 3 : 0
    'name summary jackknife' =. y
    estimate =. 0{::summary
    values =. 1{::summary
    below =. +/values<estimate
    z0 =. phi_inverse below%Bootstrap
    differences =. (1{::jackknife)-0{::jackknife
    squares =. sequential_sum differences*differences
    cubes =. sequential_sum (differences*differences)*differences
    acceleration =. cubes%((6*squares)*%:squares)
    low =. <.(Bootstrap+1)*bca_alpha z0,acceleration,ZLow
    high =. (Bootstrap+1)-<.(Bootstrap+1)*(1-bca_alpha z0,acceleration,-ZLow)
    low =. Bootstrap<.1>.low
    high =. Bootstrap<.1>.high
    ordered =. 2{::summary
    'bca | below | z0 | acceleration | ranks | | interval | |' format (<name),(<below),(<real_text z0),(<real_text acceleration),(<low),(<high),(<real_text (low-1){ordered),<real_text (high-1){ordered
)
group_jackknife_lines =: 3 : 0
    'group indices samples summaries' =. y
    values =. group{::Groups
    count =. #values
    statistics =. (0,4)$0.0
    for_index. i.count do. statistics =. statistics,group_statistics index without values end.
    jackknives =. 0$a:
    lines =. <'group | n |' format (group{GroupNames),<count
    for_statistic. i.4 do.
        s =. statistic{::summaries
        j =. (0{::s)jackknife statistic{"1 statistics
        jackknives =. jackknives,<j
        lines =. lines,<'jackknife | estimate | average | bias | se |' format (statistic{GroupStatistics),(<real_text 0{::s),(<real_text 1{::j),(<real_text 3{::j),<real_text 4{::j
    end.
    for_statistic. i.4 do.
        lines =. lines,<bca_line (statistic{GroupStatistics),(statistic{summaries),statistic{jackknives
    end.
    omitted =. 0$a:
    for_index. i.count do. omitted =. omitted,<I.-.+./"1 indices=index end.
    errors =. 0 4$0.0
    for_box. omitted do.
        numbers =. >box
        row =. 0$0.0
        for_statistic. i.4 do.
            s =. statistic{::summaries
            row =. row,1{mean_and_se numbers{1{::s
        end.
        errors =. errors,row
    end.
    for_statistic. i.4 do.
        'average variance' =. jackknife_spread statistic{"1 errors
        lines =. lines,<'after_bootstrap | se | average | se_of_se |' format (statistic{GroupStatistics),(<real_text 4{::statistic{::summaries),(<real_text average),<real_text %:variance
    end.
    sizes =. #&>omitted
    lines =. lines,<'without min | max |' format (<<./sizes),<>./sizes
    total =. +/values
    scores =. |(count*values)-total
    order =. /:(-scores),.i.count
    s =. 0{::summaries
    j =. 0{::jackknives
    for_rank. i.5 do.
        index =. rank{order
        influence =. (count-1)*((1{::j)-index{0{::j)
        shifted =. /:~((index{::omitted){1{::s)-0{::s
        quantiles =. 0$0.0
        for_percent. 5 50 95 do.
            position =. ((percent*index{sizes)ceil_div 100)-1
            quantiles =. quantiles,position{shifted
        end.
        lines =. lines,<'influence | obs | value | l | without | se | q05 | q50 | q95 |' format (<rank+1),(<index+1),(<real_text (index{values)%100),(<real_text influence),(<index{sizes),(<real_text (<index,0){errors),real_text&.><"0 quantiles
    end.
    lines
)
pair_jackknife_lines =: 3 : 0
    'first second name summaries' =. y
    x =. first{::Groups
    values =. second{::Groups
    firststats =. secondstats =. 0 4$0.0
    for_index. i.#x do. firststats =. firststats,(index without x)pair_statistics values end.
    for_index. i.#values do. secondstats =. secondstats,x pair_statistics index without values end.
    lines =. 0$a:
    for_statistic. i.4 do.
        estimate =. 0{::statistic{::summaries
        firstjack =. estimate jackknife statistic{"1 firststats
        secondjack =. estimate jackknife statistic{"1 secondstats
        bias =. (0.0+3{::firstjack)+3{::secondjack
        variance =. (0.0+2{::firstjack)+2{::secondjack
        lines =. lines,<'pair | | estimate | bias | se |' format (<name),(statistic{PairStatistics),(<real_text estimate),(<real_text bias),<real_text %:variance
    end.
    lines
)
split_statistics =: 3 : 0
    'values ranks order size' =. y
    first =. (size{.order){values
    second =. (size}.order){values
    k =. #first
    m =. #second
    firstcenter =. doubled_median first
    secondcenter =. doubled_median second
    ranktotal =. +/(size{.order){ranks
    firstdev =. +/|(2*first)-firstcenter
    seconddev =. +/|(2*second)-secondcenter
    (contrast (+/first),k,(+/second),m),(firstcenter-secondcenter),(ranktotal-k*(k+m)+1),contrast firstdev,k,seconddev,m
)
permutation_lines =: 4 : 0
    first =. x
    second =. y
    k =. #first
    m =. #second
    combined =. first,second
    ranks =. doubled_ranks combined
    positions =. i.#combined
    observed =. split_statistics (<combined),(<ranks),(<positions),<k
    tallies =. observed,.4 2$0
    for_repeat. i.Permutations do.
        order =. shuffle positions
        statistics =. split_statistics (<combined),(<ranks),(<order),<k
        for_statistic. i.4 do.
            tallies =. ((statistic{tallies)tally_count statistic{statistics) statistic}tallies
        end.
    end.
    ranktotal =. +/k{.ranks
    results =. 0$a:
    for_tally. tallies do. results =. results,<tally tally_text 1,Permutations+1 end.
    lines =. <'permutation n | | perms |' format (<k),(<m),<Permutations
    lines =. lines,<'mean diff | |' format (<real_text first mean_difference second),0{results
    lines =. lines,<'median diff | |' format (<real_text (1{observed)%200),1{results
    lines =. lines,<'ranksum w | u | |' format (<real_text ranktotal%2),(<real_text (ranktotal-k*k+1)%2),2{results
    lines =. lines,<'absdev diff | |' format (<real_text (3{observed)%((200*k)*m)),3{results
    (<lines),<1{"1 tallies
)
power_line =: 4 : 0
    first =. x
    second =. y
    k =. #first
    m =. #second
    rejections =. 0
    for_simulation. i.PowerSims do.
        samplex =. (resample_indices k){first
        sampley =. (resample_indices m){second
        combined =. samplex,sampley
        total =. +/combined
        observed =. |contrast (+/samplex),k,(+/sampley),m
        count =. 0
        for_repeat. i.PowerPerms do.
            shuffled =. shuffle combined
            head =. +/k{.shuffled
            count =. count+(|contrast head,k,(total-head),m)>:observed
        end.
        rejections =. rejections+(100*count+1)<:(100-Confidence)*PowerPerms+1
    end.
    power =. rejections%PowerSims
    se =. %:(power*(1-power))%PowerSims
    'power sims | perms | rejections | power | se |' format (<PowerSims),(<PowerPerms),(<rejections),(<real_text power),<real_text se
)
exact_lines =: 4 : 0
    first =. Pilot{.x
    second =. Pilot{.y
    combined =. first,second
    ranks =. doubled_ranks combined
    total =. +/combined
    means =. rankvalues =. 0$0
    for_choice. (2*Pilot)position_choices Pilot do.
        chosen =. +/choice{combined
        means =. means,contrast chosen,Pilot,(total-chosen),Pilot
        rankvalues =. rankvalues,(+/choice{ranks)-Pilot*(2*Pilot)+1
    end.
    splits =. #means
    meantally =. ({.means),0 0
    ranktally =. ({.rankvalues),0 0
    for_index. i.splits do.
        meantally =. meantally tally_count index{means
        ranktally =. ranktally tally_count index{rankvalues
    end.
    ranktotal =. +/Pilot{.ranks
    lines =. <'exact size | splits |' format (<Pilot),<splits
    lines =. lines,<'mean diff | |' format (<real_text first mean_difference second),<meantally tally_text 0,splits
    lines =. lines,<'ranksum w | u | |' format (<real_text ranktotal%2),(<real_text (ranktotal-Pilot*Pilot+1)%2),<ranktally tally_text 0,splits
    critical =. _1
    attained =. cumulative =. 0
    for_pair. |.value_counts |means do.
        'value count' =. pair
        cumulative =. cumulative+count
        if. (100*cumulative)>(100-Confidence)*splits do. break. end.
        critical =. value
        attained =. cumulative
    end.
    if. critical=_1 do. lines,<'critical diff none attained none'
    else. lines,<'critical diff | attained |' format (<real_text critical%((100*Pilot)*Pilot)),<attained p_value splits end.
)
studentized_lines =: 3 : 0
    'first second name summaries' =. y
    x =. first{::Groups
    values =. second{::Groups
    k =. #x
    m =. #values
    estimate =. x mean_difference values
    firstsd =. sd x
    secondsd =. sd values
    firstvariance =. (firstsd*firstsd)%k
    secondvariance =. (secondsd*secondsd)%m
    se0 =. %:firstvariance+secondvariance
    t =. estimate%se0
    differences =. 1{::0{::summaries
    firstreplicates =. 1{::3{::3{::first{::Ordinary
    secondreplicates =. 1{::3{::3{::second{::Ordinary
    statistics =. 0$0.0
    for_index. i.Bootstrap do.
        firstsd =. index{firstreplicates
        secondsd =. index{secondreplicates
        spread =. %:((firstsd*firstsd)%k)+(secondsd*secondsd)%m
        statistics =. statistics,((index{differences)-estimate)%spread
    end.
    extreme =. +/(|statistics)>:|t
    ordered =. /:~statistics
    lower =. estimate-((HighRank-1){ordered)*se0
    upper =. estimate-((LowRank-1){ordered)*se0
    denominator =. ((firstvariance*firstvariance)%k-1)+(secondvariance*secondvariance)%m-1
    totalvariance =. firstvariance+secondvariance
    degrees =. (totalvariance*totalvariance)%denominator
    greater =. equal =. 0
    for_value. x do.
        greater =. greater++/value>values
        equal =. equal++/value=values
    end.
    d =. x cohen_d values
    hedges =. d*(1-3%(4*((k+m)-2))-1)
    cles =. ((2*greater)+equal)%((2*k)*m)
    lines =. <'bootstrap_t t | df | extreme | p | interval | |' format (<real_text t),(<real_text degrees),(<extreme),(<(extreme+1)p_value Bootstrap+1),(<real_text lower),<real_text upper
    lines,<'effect pooled_sd | cohen_d | hedges_g | cles |' format (<real_text x pooled_sd values),(<real_text d),(<real_text hedges),<real_text cles
)
holm_lines =: 3 : 0
    extremes =. y
    count =. #PairIndices
    lines =. 0$a:
    for_statistic. i.4 do.
        values =. statistic{"1 extremes
        order =. /:values,.i.count
        adjusted =. 0
        for_rank. i.count do.
            index =. rank{order
            extreme =. index{values
            adjusted =. adjusted>.((Permutations+1)<.(count-rank)*extreme+1)
            if. (100*adjusted)<:(100-Confidence)*Permutations+1 do. verdict =. 'reject' else. verdict =. 'retain' end.
            'first second' =. index{PairIndices
            lines =. lines,<'holm | rank | | | p | adjusted | |' format (statistic{TestStatistics),(<rank+1),(first{GroupNames),(second{GroupNames),(<(extreme+1)p_value Permutations+1),(<adjusted p_value Permutations+1),<verdict
        end.
    end.
    lines
)
hyperbolic_tangent =: 3 : 0
    growth =. ^2*y
    (growth-1)%growth+1
)
paired_lines =: 3 : 0
    'meansummary correlationsummary' =. y
    count =. #Differences
    positive =. +/Differences>0
    negative =. +/Differences<0
    zero =. +/Differences=0
    average =. mean Differences
    deviation =. sd Differences
    r =. Before correlation After
    z =. 0.5*^.(1+r)%1-r
    halfwidth =. (-ZLow)%%:count-3
    lines =. <'paired subjects | positive | negative | zero |' format (<count),(<positive),(<negative),<zero
    lines =. lines,<'paired before | after | diff | sd_diff | t | dz |' format (<real_text mean Before),(<real_text mean After),(<real_text average),(<real_text deviation),(<real_text average%(deviation%%:count)),<real_text average%deviation
    lines =. lines,<'paired_bootstrap ',interval_text meansummary
    lines,<'correlation r | | fisher | |' format (<real_text r),(<interval_text correlationsummary),(<real_text hyperbolic_tangent z-halfwidth),<real_text hyperbolic_tangent z+halfwidth
)
sign_flip_lines =: 3 : 0
    nonzero =. Differences#~Differences~:0
    magnitudes =. |nonzero
    ranks =. doubled_ranks magnitudes
    signed =. (#Differences)$0
    for_index. i.#Differences do.
        value =. index{Differences
        if. value=0 do. continue. end.
        rank =. (magnitudes i.|value){ranks
        if. value<0 do. rank =. -rank end.
        signed =. rank index}signed
    end.
    meantally =. (+/Differences),0 0
    ranktally =. (+/signed),0 0
    for_repeat. i.Permutations do.
        signs =. 0$0
        for_index. i.#Differences do.
            value =. draw ''
            if. 2|value do. sign =. _1 else. sign =. 1 end.
            signs =. signs,sign
        end.
        meantally =. meantally tally_count +/signs*Differences
        ranktally =. ranktally tally_count +/signs*signed
    end.
    wplus =. (+/signed#~signed>0)%2
    lines =. <'signflip flips ',number Permutations
    lines =. lines,<'mean diff | |' format (<real_text mean Differences),<meantally tally_text 1,Permutations+1
    lines,<'signedrank w_plus | |' format (<real_text wplus),<ranktally tally_text 1,Permutations+1
)
welch_line =: 3 : 0
    samples =. y
    means =. mean&>samples
    weights =. 0$0.0
    for_box. samples do.
        sample =. >box
        deviation =. sd sample
        weights =. weights,(#sample)%(deviation*deviation)
    end.
    totalweight =. sequential_sum weights
    center =. (sequential_sum weights*means)%totalweight
    differences =. means-center
    spread =. (sequential_sum weights*(differences*differences))%GroupCount-1
    lambda =. 0.0
    for_index. i.GroupCount do.
        share =. 1-(index{weights)%totalweight
        lambda =. lambda+(share*share)%((#index{::samples)-1)
    end.
    f =. spread%(1+((2*(GroupCount-2))*lambda)%((GroupCount*GroupCount)-1))
    df =. ((GroupCount*GroupCount)-1)%3*lambda
    'welch f | df | |' format (<real_text f),(<GroupCount-1),<real_text df
)
group_deltas =: 4 : 0
    totals =. +/&>y
    sizes =. #&>y
    result =. 0 2$0
    for_pair. x do.
        'first second' =. pair
        numerator =. |contrast (first{totals),(first{sizes),(second{totals),second{sizes
        result =. result,numerator,(first{sizes)*second{sizes
    end.
    result
)
delta_at_least =: 4 : '((0{x)*1{y)>:(0{y)*1{x'
anova_lines =: 3 : 0
    samples =. Groups
    total =. +/Sizes
    'between within' =. sums_of_squares samples
    f =. f_statistic between,within,GroupCount,total
    eta =. between%between+within
    msw =. within%total-GroupCount
    omega =. (between-(GroupCount-1)*msw)%(between+within)+msw
    etavalues =. 0$0.0
    for_replicate. i.Bootstrap do.
        groups =. 0$a:
        for_box. Ordinary do. groups =. groups,<replicate{2{::>box end.
        'first second' =. sums_of_squares groups
        etavalues =. etavalues,first%first+second
    end.
    etasummary =. eta summary etavalues
    combined =. ;samples
    ranks =. doubled_ranks combined
    ranktotals =. +/&>Sizes split_list ranks
    ties =. value_counts combined
    ties =. (1{"1 ties)#~(1{"1 ties)>:2
    tietotal =. +/((ties*ties)*ties)-ties
    correction =. 1-tietotal%((total*total)*total)-total
    h =. h_statistic (<ranktotals),(<Sizes),<correction
    lines =. <'anova groups | observations | ssb | ssw | df | | f | eta_squared | omega_squared |' format (<GroupCount),(<total),(<real_text between),(<real_text within),(<GroupCount-1),(<total-GroupCount),(<real_text f),(<real_text eta),<real_text omega
    lines =. lines,<'eta_bootstrap ',interval_text etasummary
    lines =. lines,<welch_line samples
    lines =. lines,<'kruskal h | tie_groups |' format (<real_text h),<#ties
    pairs =. 0 2$0
    for_first. i.GroupCount do.
        for_second. (first+1)+i.GroupCount-first+1 do. pairs =. pairs,first,second end.
    end.
    observed =. pairs group_deltas samples
    extremes =. maxima =. (#pairs)$0
    fextreme =. hextreme =. 0
    positions =. i.total
    for_repeat. i.Permutations do.
        order =. shuffle positions
        parts =. Sizes split_list order
        groups =. 0$a:
        ranktotals =. 0$0
        for_part. parts do.
            groups =. groups,<(>part){combined
            ranktotals =. ranktotals,+/(>part){ranks
        end.
        'first second' =. sums_of_squares groups
        fstar =. f_statistic first,second,GroupCount,total
        hstar =. h_statistic (<ranktotals),(<Sizes),<correction
        fextreme =. fextreme+fstar>:(f-0.000000001*f)
        hextreme =. hextreme+hstar>:(h-0.000000001*h)
        deltas =. pairs group_deltas groups
        largest =. {.deltas
        for_delta. }.deltas do. if. -.largest delta_at_least delta do. largest =. delta end. end.
        for_index. i.#pairs do.
            extremes =. ((index{extremes)+(index{deltas)delta_at_least index{observed) index}extremes
            maxima =. ((index{maxima)+largest delta_at_least index{observed) index}maxima
        end.
    end.
    lines =. lines,<'anova_permutation perms | f_extreme | f_p | h_extreme | h_p |' format (<Permutations),(<fextreme),(<(fextreme+1)p_value Permutations+1),(<hextreme),<(hextreme+1)p_value Permutations+1
    for_index. i.#pairs do.
        'first second' =. index{pairs
        difference =. (first{::Groups)mean_difference second{::Groups
        extreme =. index{extremes
        maximum =. index{maxima
        lines =. lines,<'pairwise | | diff | extreme | p | maxt | adjusted |' format (first{GroupNames),(second{GroupNames),(<real_text difference),(<extreme),(<(extreme+1)p_value Permutations+1),(<maximum),<(maximum+1)p_value Permutations+1
    end.
    lines
)
histogram_lines =: 3 : 0
    'name statistic s' =. y
    estimate =. 0{::s
    values =. 1{::s
    low =. <./values
    high =. >./values
    counts =. Bins$0
    for_value. values do.
        index =. Bins bin_number value,low,high
        counts =. (1+index{counts) index}counts
    end.
    top =. >./counts
    marks =. Bins$<0$a:
    index =. Bins bin_number (6{::s),low,high
    marks =. (<(index{::marks),<'L') index}marks
    estimatebin =. 'none'
    if. (estimate>:low)*.estimate<:high do.
        index =. Bins bin_number estimate,low,high
        estimatebin =. number index+1
        marks =. (<(index{::marks),<'E') index}marks
    end.
    index =. Bins bin_number (7{::s),low,high
    marks =. (<(index{::marks),<'H') index}marks
    convergence =. 0$a:
    for_quarter. 1+i.4 do.
        size =. (quarter*Bootstrap)div 4
        convergence =. convergence,<'|:|' format (<size),<real_text 1{mean_and_se size{.values
    end.
    lines =. <'histogram | | min | max | width | top | estimate_bin |' format (<name),(<statistic),(<real_text low),(<real_text high),(<real_text (high-low)%Bins),(<top),<estimatebin
    lines =. lines,<'convergence ',' ' join convergence
    for_index. i.Bins do.
        count =. index{counts
        edge =. low+((high-low)*index)%Bins
        text =. 'bin | | |' format (<index+1),(<real_text edge),<count
        if. count>0 do. text =. text,' ',count bar top end.
        listed =. index{::marks
        if. #listed do. text =. text,' ',' ' join listed end.
        lines =. lines,<text
    end.
    lines
)
main =: 3 : 0
    load_dataset ''
    RandomState =: Seed
    LowRank =: ((Bootstrap+1)*(100-Confidence))div 200
    HighRank =: (Bootstrap+1)-LowRank
    ZLow =: phi_inverse (100-Confidence)%200
    Ordinary =: Balanced =: 0$a:
    for_group. i.GroupCount do.
        indices =. (group{Sizes)ordinary_indices Bootstrap
        Ordinary =: Ordinary,<group group_bootstrap indices
    end.
    for_group. i.GroupCount do.
        indices =. (group{Sizes)balanced_indices Bootstrap
        Balanced =: Balanced,<group group_bootstrap indices
    end.
    pairedsummaries =. paired_bootstrap ''
    Pairs =: 0$a:
    for_pair. PairIndices do. Pairs =: Pairs,<pair_bootstrap pair end.
    tests =. 0$a:
    extremes =. 0 4$0
    for_box. Pairs do.
        pair =. >box
        'first second name summaries' =. pair
        x =. first{::Groups
        values =. second{::Groups
        tests =. tests,<'compare | |' format (first{GroupNames),second{GroupNames
        'lines counts' =. x permutation_lines values
        tests =. tests,lines
        extremes =. extremes,counts
        tests =. tests,<x power_line values
        tests =. tests,(x exact_lines values),studentized_lines pair
    end.
    tests =. tests,holm_lines extremes
    tests =. tests,paired_lines pairedsummaries
    tests =. tests,sign_flip_lines ''
    tests =. tests,anova_lines ''
    jackknives =. histograms =. 0$a:
    for_box. Ordinary do.
        block =. >box
        jackknives =. jackknives,group_jackknife_lines block
        group =. 0{::block
        summaries =. 3{::block
        for_statistic. i.4 do.
            histograms =. histograms,histogram_lines (group{GroupNames),(statistic{GroupStatistics),statistic{summaries
        end.
    end.
    for_box. Pairs do.
        pair =. >box
        jackknives =. jackknives,pair_jackknife_lines pair
        summaries =. 3{::pair
        for_statistic. i.4 do.
            histograms =. histograms,histogram_lines (2{pair),(statistic{PairStatistics),statistic{summaries
        end.
    end.
    if. -.fexist 'output' do. 1!:5 <'output' end.
    'descriptives.txt' write_lines descriptive_lines ''
    'bootstrap.csv' write_lines bootstrap_lines ''
    'jackknife.txt' write_lines jackknives
    'tests.txt' write_lines tests
    'histograms.txt' write_lines histograms
    i.0
)
main ''
