ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
div =: 4 : '_1 x:<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
signed_num =: 3 : 0
    if. '-'={.y do. -num }.y else. num y end.
)
decimal =: 3 : 0
    sign =. 1
    if. '-'={.y do. sign =. _1
        y =. }.y end.
    parts =. '.' split y
    value =. num 0{::parts
    if. (#parts)>1 do.
        fraction =. 1{::parts
        value =. value+(num fraction)%10^#fraction
    end.
    sign*value
)
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
    parts =. 0$a:
    for_box. y do.
        value =. >box
        if. 2~:3!:0 value do. value =. number value end.
        parts =. parts,<value
    end.
    ' ' join parts
)
ascii_order =: 3 : '/: > (a.&i.)&.> y'
ascii_sort =: 3 : '(ascii_order y){y'
empty_table =: 3 : '0 2$a:'
table_keys =: 3 : '0{"1 y'
has_key =: 4 : '(<x)e.table_keys y'
get_key =: 4 : '((table_keys y)i.<x){::1{"1 y'
put_key =: 4 : 0
    'key value' =. x
    position =. (table_keys y)i.<key
    if. position<#y do. (<value) (<position,1)}y
    else. y,1 2$(<key),<value end.
)
load SourceDirectory,'transactions.ijs'
load SourceDirectory,'features.ijs'
load SourceDirectory,'kmeans.ijs'
load SourceDirectory,'validation.ijs'
load SourceDirectory,'profiles.ijs'
load SourceDirectory,'report.ijs'
draw =: 3 : 0
    RandomState =: 2147483647|48271*RandomState
    RandomState
)
yes_no =: 3 : 0
    if. y do. 'yes' else. 'no' end.
)
join_blocks =: 3 : 0
    lines =. 0$a:
    for_block. y do.
        if. #lines do. lines =. lines,<'' end.
        lines =. lines,>block
    end.
    lines
)
nearest_gaps =: 4 : 0
    gaps =. 0$0.0
    for_point. x do.
        distances =. 0$0.0
        for_index. y do. distances =. distances,point squared_distance index{x end.
        gaps =. gaps,<./distances
    end.
    gaps
)
maximin =: 4 : 0
    'count run' =. y
    overall =. mean_point x
    spreads =. 0$0.0
    for_point. x do. spreads =. spreads,point squared_distance overall end.
    order =. /:spreads,.i.#x
    chosen =. ,(run-1){order
    while. (#chosen)<count do.
        gaps =. x nearest_gaps chosen
        chosen =. chosen,gaps i.>./gaps
    end.
    chosen
)
initial_seeds =: 4 : 0
    points =. x
    'method count run' =. y
    if. method-:'maximin' do. points maximin count,run return. end.
    chosen =. 0$0
    if. method-:'forgy' do.
        while. (#chosen)<count do.
            index =. (#points)|draw ''
            if. -.index e.chosen do. chosen =. chosen,index end.
        end.
        chosen return.
    end.
    chosen =. ,(#points)|draw ''
    while. (#chosen)<count do.
        gaps =. points nearest_gaps chosen
        weight =. ordered_sum gaps
        threshold =. ((draw '')%2147483647)*weight
        total =. 0.0
        selected =. _1
        for_index. i.#gaps do.
            total =. total+index{gaps
            if. total>threshold do. selected =. index break. end.
        end.
        if. selected=_1 do. selected =. {:I.gaps>0 end.
        chosen =. chosen,selected
    end.
    chosen
)
improve =: 4 : 0
    points =. x
    'labels count limit' =. y
    sizes =. count cluster_sizes labels
    centers =. points cluster_centers (<labels),<count
    passes =. transfers =. 0
    moved =. 1
    while. moved*.passes<limit do.
        moved =. 0
        passes =. passes+1
        for_index. i.#points do.
            point =. index{points
            own =. index{labels
            if. 1=own{sizes do. continue. end.
            removal =. ((own{sizes)%(own{sizes)-1)*(point squared_distance own{centers)
            target =. _1
            targetcost =. 0.0
            for_other. i.count do.
                if. other=own do. continue. end.
                cost =. ((other{sizes)%1+other{sizes)*(point squared_distance other{centers)
                if. target=_1 do. target =. other
                    targetcost =. cost
                elseif. cost<targetcost do. target =. other
                    targetcost =. cost end.
            end.
            if. targetcost<removal do.
                labels =. target index}labels
                sizes =. ((own{sizes)-1) own}sizes
                sizes =. (1+target{sizes) target}sizes
                centers =. (points cluster_center (<labels),<own) own}centers
                centers =. (points cluster_center (<labels),<target) target}centers
                transfers =. transfers+1
                moved =. 1
            end.
        end.
    end.
    centers =. points cluster_centers (<labels),<count
    (<labels),(<passes),(<transfers),<points sse (<labels),<centers
)
make_run =: 4 : 0
    points =. x
    'method number seeds' =. y
    result =. points lloyd (<seeds{points),<MaxIterations
    initial =. points sse (0{result),1{result
    improvement =. points improve (0{result),(<#seeds),<MaxIterations
    (<method),(<number),(<seeds),(<result),(<initial),<improvement
)
best_run =: 3 : 0
    best =. 0{::y
    for_box. }.y do.
        run =. >box
        if. (four_decimal 3{::5{::run)<four_decimal 3{::5{::best do. best =. run end.
    end.
    best
)
solution =: 4 : 0
    'labels count' =. y
    groups =. 0$a:
    for_label. i.count do. groups =. groups,<I.labels=label end.
    order =. /:(-#&>groups),.{.&>groups
    groups =. order{groups
    labels =. (#labels)$0
    for_segment. i.count do. labels =. segment (segment{::groups)}labels end.
    centers =. x cluster_centers (<labels),<count
    (<count),(<groups),(<#&>groups),(<labels),(<centers),<x sse (<labels),<centers
)
category_totals =: 3 : 0
    totals =. empty_table ''
    for_box. y do.
        customer =. >box
        for_pair. 4{::customer do.
            'category spend' =. pair
            previous =. 0
            if. category has_key totals do. previous =. category get_key totals end.
            totals =. ((<category),<previous+spend)put_key totals
        end.
    end.
    totals
)
category_ranking =: 3 : 0
    names =. ascii_sort table_keys y
    positive =. 0$a:
    amounts =. 0$0
    for_namebox. names do.
        name =. >namebox
        spend =. name get_key y
        if. spend>0 do. positive =. positive,<name
            amounts =. amounts,spend end.
    end.
    positive{~\:amounts
)
rfm_scores =: 3 : 0
    raw =. RawValues
    spends =. (3&{::)&>Customers
    scores =. 0 3$0
    for_index. i.CustomerCount do.
        recency =. +/(0{"1 raw)>0{index{raw
        frequency =. +/(1{"1 raw)<1{index{raw
        monetary =. +/spends<index{spends
        scores =. scores,1+((5*recency,frequency,monetary)div CustomerCount)
    end.
    scores
)
gini =: 3 : 0
    values =. /:~y
    count =. #values
    total =. +/values
    weighted =. +/(1+i.count)*values
    ((2*weighted)-(count+1)*total)%(count*total)
)
lower_median =: 3 : '(((#y)-1)div 2){/:~y'
customer_ids =: 3 : ''' '' join y{CustomerIds'
candidate =: 3 : '(y-KMin){::Candidates'
analyze =: 3 : 0
    RandomState =: Seed
    ReferenceOrders =: group_orders 1,ReferenceDay
    CustomerOrders =: orders_by_customer ReferenceOrders
    Customers =: ReferenceOrders eligible_customers ReferenceDay
    CustomerCount =: #Customers
    CustomerIds =: 0$a:
    for_box. Customers do. CustomerIds =: CustomerIds,0{>box end.
    RawValues =: raw_values Customers
    transformed =. transform"1 RawValues
    'Means SDs' =: standardization transformed
    Points =: 0 6$0.0
    for_values. transformed do. Points =: Points,((<Means),<SDs)standardize values end.
    KValues =: KMin+i.1+KMax-KMin
    Candidates =: 0$a:
    for_k. KValues do.
        runs =. bests =. 0$a:
        for_methodbox. Methods do.
            method =. >methodbox
            methodruns =. 0$a:
            for_restart. 1+i.Restarts do.
                seeds =. Points initial_seeds (<method),(<k),<restart
                methodruns =. methodruns,<Points make_run (<method),(<restart),<seeds
            end.
            runs =. runs,methodruns
            bests =. bests,<best_run methodruns
        end.
        best =. best_run bests
        refinedlabels =. 0{::5{::best
        result =. Points solution (<refinedlabels),<k
        entry =. (<k),(<runs),(<bests),(<best),(<result),(<0$0.0),(<5$0.0),(<0$0),<0$a:
        Candidates =: Candidates,<entry
    end.
    table =. distance_table Points
    first =. 5{::4{::0{::Candidates
    last =. 5{::4{::>{:Candidates
    for_index. i.#Candidates do.
        entry =. index{::Candidates
        result =. 4{::entry
        'k groups sizes labels centers within' =. result
        values =. silhouettes (<table),(<labels),<sizes
        sil =. mean values
        ch =. Points calinski_harabasz (<centers),(<sizes),<within
        db =. Points davies_bouldin (<labels),(<centers),<sizes
        e =. elbow k,KMin,KMax,within,first,last
        h =. _1.0
        if. index<(<:#Candidates) do.
            next =. 5{::4{::(index+1){::Candidates
            h =. hartigan within,next,CustomerCount,k
        end.
        numbers =. 0$0
        names =. 0$a:
        for_center. centers do.
            rule =. Rules rule_number center
            repeats =. +/numbers=rule
            name =. 0{::rule{::Rules
            if. repeats>0 do. name =. name,'_',number repeats+1 end.
            numbers =. numbers,rule
            names =. names,<name
        end.
        entry =. (<values) 5}entry
        entry =. (<sil,ch,db,e,h) 6}entry
        entry =. (<numbers) 7}entry
        entry =. (<names) 8}entry
        Candidates =: (<entry) index}Candidates
    end.
    metrics =. 0 5$0.0
    for_box. Candidates do. metrics =. metrics,6{::>box end.
    e =. 1+({.\:four_decimal"0 3{"1 }:}.metrics)
    sil =. {.\:four_decimal"0 0{"1 metrics
    ch =. {.\:four_decimal"0 1{"1 metrics
    db =. {./:four_decimal"0 2{"1 metrics
    eligible =. I.(4{"1 }:metrics)<:10
    if. #eligible do. h =. {.eligible else. h =. <:#Candidates end.
    VoteNames =: 'elbow';'silhouette';'calinski_harabasz';'davies_bouldin';'hartigan'
    Votes =: e,sil,ch,db,h
    counts =. (#Candidates)$0
    for_vote. Votes do. counts =. (1+vote{counts) vote}counts end.
    order =. /:(-counts),.(-four_decimal"0 0{"1 metrics),.KValues
    FinalIndex =: {.order
    FinalVotes =: FinalIndex{counts
    Final =: FinalIndex{::Candidates
    'K Members SegmentSizes Labels Centers Within' =: 4{::Final
    Names =: 8{::Final
    Silhouettes =: 5{::Final
    Distances =: OtherDistances =: 0$0.0
    OtherLabels =: 0$0
    for_index. i.CustomerCount do.
        squared =. 0$0.0
        for_center. Centers do. squared =. squared,(index{Points)squared_distance center end.
        own =. index{Labels
        others =. (i.K)#~(i.K)~:own
        other =. ((others{squared)i.<./others{squared){others
        Distances =: Distances,%:own{squared
        OtherLabels =: OtherLabels,other
        OtherDistances =: OtherDistances,%:other{squared
    end.
    Scores =: rfm_scores ''
    Codes =: 0$a:
    for_score. Scores do. Codes =: Codes,<Digits{~score end.
    TotalSpend =: +/(3&{::)&>Customers
    OverallCategories =: category_totals Customers
    CategoryNames =: ascii_sort table_keys OverallCategories
    SegmentCustomers =: SegmentCategories =: Rankings =: 0$a:
    SegmentSpends =: SegmentSSE =: 0$0
    for_segment. i.K do.
        members =. segment{::Members
        customers =. members{Customers
        categories =. category_totals customers
        SegmentCustomers =: SegmentCustomers,<customers
        SegmentCategories =: SegmentCategories,<categories
        Rankings =: Rankings,<category_ranking categories
        SegmentSpends =: SegmentSpends,+/(3&{::)&>customers
        total =. 0.0
        for_pointindex. members do. total =. total+(pointindex{Points)squared_distance segment{Centers end.
        SegmentSSE =: SegmentSSE,total
    end.
    Jaccards =: (0,K)$0.0
    samplesize =. (CustomerCount*SubsamplePercent)div 100
    for_repeat. i.Subsamples do.
        order =. i.CustomerCount
        for_position. i.samplesize do.
            other =. position+(CustomerCount-position)|draw ''
            first =. position{order
            second =. other{order
            order =. second position}order
            order =. first other}order
        end.
        sample =. /:~samplesize{.order
        result =. (sample{Points)lloyd (<Centers),<MaxIterations
        labels =. 0{::result
        row =. 0$0.0
        for_segment. i.K do.
            insegment =. segment=sample{Labels
            best =. 0.0
            for_group. i.K do.
                both =. +/insegment*.labels=group
                either =. +/insegment+.labels=group
                if. either>0 do. best =. best>.both%either end.
            end.
            row =. row,best
        end.
        Jaccards =: Jaccards,row
    end.
    i.0
)
run_summary =: 3 : 0
    'method restart seeds result initial improved' =. y
    '| restart | sse |' format (<method),(<restart),<real_text 3{::improved
)
features_lines =: 3 : 0
    lines =. <'customer,recency,frequency,monetary,basket,categories,tenure,z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure'
    for_index. i.CustomerCount do.
        customer =. index{::Customers
        raw =. index{RawValues
        fields =. (0{customer),(<number 0{raw),(<number 1{raw),(<amount 3{::customer),(<real_text 3{raw),(<number 4{raw),<number 5{raw
        fields =. fields,real_text&.><"0 index{Points
        lines =. lines,<',' join fields
    end.
    lines
)
runs_lines =: 3 : 0
    blocks =. 0$a:
    for_box. Candidates do.
        entry =. >box
        lines =. <'k ',number 0{::entry
        for_runbox. 1{::entry do.
            'method restart seeds result initial improved' =. >runbox
            lines =. lines,<'run | | seeds | iterations | converged | reseeds | sse | passes | transfers | refined |' format (<method),(<restart),(<customer_ids seeds),(2{result),(<yes_no 3{::result),(4{result),(<real_text initial),(1{improved),(2{improved),<real_text 3{::improved
        end.
        for_runbox. 2{::entry do. lines =. lines,<'best ',run_summary >runbox end.
        lines =. lines,<'chosen ',run_summary 3{::entry
        lines =. lines,<'sizes ',text_line <"0 2{::4{::entry
        blocks =. blocks,<lines
    end.
    join_blocks blocks
)
selection_lines =: 3 : 0
    indices =. <'indices'
    names =. <'segments'
    stability =. <'stability'
    for_position. i.#Candidates do.
        entry =. position{::Candidates
        k =. 0{::entry
        result =. 4{::entry
        metrics =. 6{::entry
        h =. '-'
        if. position<(<:#Candidates) do. h =. real_text 4{metrics end.
        indices =. indices,<'k=| sse | elbow | silhouette | calinski_harabasz | davies_bouldin | hartigan |' format (<k),(<real_text 5{::result),(<real_text 3{metrics),(<real_text 0{metrics),(<real_text 1{metrics),(<real_text 2{metrics),<h
        parts =. <'k=',number k
        for_segment. i.k do.
            parts =. parts,<'|:|' format (segment{8{::entry),<segment{2{::result
        end.
        names =. names,<' ' join parts
        parts =. <'k=',number k
        bests =. 2{::entry
        for_first. i.#bests do.
            a =. first{::bests
            for_second. (first+1)+i.(#bests)-(first+1) do.
                b =. second{::bests
                index =. (0{::5{::a)adjusted_rand_index 0{::5{::b
                parts =. parts,<'|:| |' format (0{a),(0{b),<real_text index
            end.
        end.
        parts =. parts,<'final'
        for_runbox. bests do.
            run =. >runbox
            index =. (0{::5{::run)adjusted_rand_index 3{::result
            parts =. parts,<'| |' format (0{run),<real_text index
        end.
        next =. '-'
        if. position<(<:#Candidates) do.
            following =. 4{::(position+1){::Candidates
            next =. real_text (3{::result)adjusted_rand_index 3{::following
        end.
        parts =. parts,<'next ',next
        stability =. stability,<' ' join parts
    end.
    votes =. <'votes'
    for_index. i.5 do. votes =. votes,<'| k=|' format (index{VoteNames),<(index{Votes){KValues end.
    votes =. votes,<'chosen k=| votes |' format (<K),<FinalVotes
    join_blocks (<indices),(<votes),(<names),<stability
)
recommendation =: 3 : 0
    customer =. y{::Customers
    categories =. 4{::customer
    for_categorybox. (y{Labels){::Rankings do.
        category =. >categorybox
        spend =. 0
        if. category has_key categories do. spend =. category get_key categories end.
        if. spend<:0 do. category return. end.
    end.
    '-'
)
segments_lines =: 3 : 0
    lines =. <'customer,segment,name,distance,other,other_distance,silhouette,recommend'
    for_index. i.CustomerCount do.
        label =. index{Labels
        lines =. lines,<'|,|,|,|,|,|,|,|' format (index{CustomerIds),(<label+1),(label{Names),(<real_text index{Distances),(<1+index{OtherLabels),(<real_text index{OtherDistances),(<real_text index{Silhouettes),<recommendation index
    end.
    lines
)
related =: 4 : 0
    if. (y<KMin)+.y>KMax do. 'k=| -' format <y return. end.
    labels =. 3{::4{::candidate y
    counts =. y cluster_sizes x{labels
    best =. counts i.>./counts
    'k=| segment | shared |' format (<y),(<best+1),<best{counts
)
segment_profile =: 3 : 0
    segment =. y
    members =. segment{::Members
    customers =. segment{::SegmentCustomers
    size =. #members
    center =. segment{Centers
    spend =. segment{SegmentSpends
    lines =. <'segment | | rule | size | share | revenue | revenue_share |' format (<segment+1),(segment{Names),(<1+segment{7{::Final),(<size),(<real_text size%CustomerCount),(<amount spend),<real_text spend%TotalSpend
    lines =. lines,<'  center ',reals center
    original =. ((<Means),<SDs)original_scale center
    parts =. <'  value'
    for_feature. i.6 do. parts =. parts,<'| |' format (feature{FeatureNames),<real_text feature{original end.
    lines =. lines,<' ' join parts
    order =. /:(-|center),.i.6
    traits =. 0$a:
    for_feature. 2{.order do.
        if. (feature{center)>0 do. prefix =. 'high_' else. prefix =. 'low_' end.
        traits =. traits,<prefix,feature{::FeatureNames
    end.
    lines =. lines,<'  traits ',' ' join traits
    raw =. members{RawValues
    medians =. lower_median"1 |:raw
    monetary =. lower_median (3&{::)&>customers
    lines =. lines,<'  median recency | frequency | monetary | basket | categories | tenure |' format (<0{medians),(<1{medians),(<amount monetary),(<real_text 3{medians),(<4{medians),<5{medians
    lines =. lines,<'  related | |' format (<members related K-1),<members related K+1
    spends =. (3&{::)&>customers
    top =. members{~/: (-spends),.members
    parts =. <'  top_customers'
    for_index. (TopCustomers<.#top){.top do.
        parts =. parts,<'| |' format (index{CustomerIds),<amount 3{::index{::Customers
    end.
    lines =. lines,<' ' join parts
    gaps =. 0$0.0
    overdue =. 0
    bins =. (1+#OrderBins)$0
    gross =. returned =. cancelled =. 0
    for_customerbox. customers do.
        customer =. >customerbox
        raw =. 2{::customer
        if. (1{raw)>:2 do.
            active =. (5{raw)-0{raw
            intervals =. (1{raw)-1
            gaps =. gaps,active%intervals
            overdue =. overdue+((0{raw)*intervals)>OverdueFactor*active
        end.
        for_orderbox. 1{::customer do.
            order =. >orderbox
            bin =. +/(3{::order)>:100*OrderBins
            bins =. (1+bin{bins) bin}bins
        end.
        for_orderbox. (0{::customer)get_key CustomerOrders do.
            order =. >orderbox
            cancelled =. cancelled+(3{::order)<:0
            for_rowindex. 4{::order do.
                value =. 4{::rowindex{::ValidRows
                if. value>0 do. gross =. gross+value
                else. returned =. returned-value end.
            end.
        end.
    end.
    meangap =. '-'
    if. #gaps do. meangap =. real_text mean gaps end.
    lines =. lines,<'  cadence customers | mean_gap | overdue |' format (<#gaps),(<meangap),<overdue
    lines =. lines,<'  order_sizes ',text_line <"0 bins
    lines =. lines,<'  sse | share |' format (<real_text segment{SegmentSSE),<real_text (segment{SegmentSSE)%Within
    lines =. lines,<'  gini ',real_text gini spends
    lines =. lines,<'  returns rate | returned | cancelled |' format (<real_text returned%gross),(<amount returned),<cancelled
    values =. members{Silhouettes
    lines =. lines,<'  silhouette | negative |' format (<real_text mean values),<+/values<0
    values =. members{Scores
    means =. 0$0.0
    for_part. i.3 do. means =. means,(ordered_sum part{"1 values)%size end.
    codes =. members{Codes
    possible =. ascii_sort ~.codes
    counts =. 0$0
    for_codebox. possible do. counts =. counts,+/codes=codebox end.
    mode =. counts i.>./counts
    lines =. lines,<'  rfm r | f | m | mode | |' format (real_text&.><"0 means),(mode{possible),<mode{counts
    parts =. <'  categories'
    totals =. segment{::SegmentCategories
    ranking =. segment{::Rankings
    for_categorybox. (TopCategories<.#ranking){.ranking do.
        category =. >categorybox
        share =. (category get_key totals)%spend
        lift =. share%((category get_key OverallCategories)%TotalSpend)
        parts =. parts,<'| | |' format (<category),(<real_text share),<real_text lift
    end.
    lines =. lines,<' ' join parts
    outliers =. 0$0
    if. size>:2 do.
        distances =. members{Distances
        limit =. (mean distances)+OutlierSD*sample_sd distances
        outliers =. members#~distances>limit
    end.
    text =. '  outliers ',number #outliers
    if. #outliers do. text =. text,' ',customer_ids outliers end.
    lines,<text
)
profiles_lines =: 3 : 0
    blocks =. <<'segments k=| customers | revenue | gini |' format (<K),(<CustomerCount),(<amount TotalSpend),<real_text gini (3&{::)&>Customers
    for_segment. i.K do. blocks =. blocks,<segment_profile segment end.
    indices =. text_line <"0 1+i.K
    mix =. <'category_mix ',indices
    for_categorybox. CategoryNames do.
        category =. >categorybox
        shares =. 0$0.0
        for_segment. i.K do.
            totals =. segment{::SegmentCategories
            value =. 0
            if. category has_key totals do. value =. category get_key totals end.
            shares =. shares,value%segment{SegmentSpends
        end.
        mix =. mix,<category,' ',reals shares
    end.
    recency =. <'rfm_recency ',indices
    for_score. 5 4 3 2 1 do.
        counts =. K$0
        for_index. I.score=0{"1 Scores do.
            label =. index{Labels
            counts =. (1+label{counts) label}counts
        end.
        recency =. recency,<'r=| |' format (<score),<text_line <"0 counts
    end.
    recency =. recency,<'ari rfm_codes ',real_text Codes adjusted_rand_index Labels
    distances =. <'center_distances'
    for_first. i.K do.
        values =. 0$0.0
        for_second. i.K do. values =. values,%:(first{Centers)squared_distance second{Centers end.
        distances =. distances,<'| |' format (<first+1),<reals values
    end.
    blocks =. blocks,(<mix),(<recency),<distances
    join_blocks blocks
)
robustness_lines =: 3 : 0
    size =. (CustomerCount*SubsamplePercent)div 100
    subsamples =. <'subsamples | size |' format (<Subsamples),<size
    for_segment. i.K do.
        values =. segment{"1 Jaccards
        subsamples =. subsamples,<'segment | | mean_jaccard | min_jaccard |' format (<segment+1),(segment{Names),(<real_text mean values),<real_text <./values
    end.
    ablation =. <'ablation'
    for_feature. i.6 do.
        points =. (feature~:i.6)#"1 Points
        seeds =. points maximin K,1
        run =. points make_run (<'maximin'),(<1),<seeds
        result =. 3{::run
        improved =. 5{::run
        index =. (0{::improved)adjusted_rand_index Labels
        ablation =. ablation,<'without | seeds | iterations | converged | transfers | sse | ari |' format (feature{FeatureNames),(<customer_ids seeds),(2{result),(<yes_no 3{::result),(2{improved),(<real_text 3{::improved),<real_text index
    end.
    members =. 0{::Members
    points =. members{Points
    seeds =. points maximin 2 1
    run =. points make_run (<'maximin'),(<1),<seeds
    result =. 3{::run
    improved =. 5{::run
    parts =. points solution (0{improved),<2
    before =. 0{SegmentSSE
    after =. 3{::improved
    drilldown =. <'drilldown segment 1 | size | seeds | iterations | converged | transfers |' format (0{Names),(<#members),(<customer_ids seeds{members),(2{result),(<yes_no 3{::result),2{improved
    drilldown =. drilldown,<'sse before | after | gain |' format (<real_text before),(<real_text after),<real_text before-after
    for_part. i.2 do.
        drilldown =. drilldown,<'part | size | center |' format (<part+1),(<part{2{::parts),<reals part{4{::parts
    end.
    join_blocks (<subsamples),(<ablation),<drilldown
)
tracking_lines =: 3 : 0
    periods =. <'periods | days |' format (<Periods),<PeriodDays
    for_period. 1+i.Periods do.
        first =. 1+ReferenceDay-period*PeriodDays
        last =. ReferenceDay-(period-1)*PeriodDays
        revenue =. active =. acquired =. K$0
        for_index. i.CustomerCount do.
            customer =. index{::Customers
            label =. index{Labels
            nets =. 0$0
            for_orderbox. 1{::customer do.
                order =. >orderbox
                day =. 2{::order
                if. (day>:first)*.day<:last do. nets =. nets,3{::order end.
            end.
            if. #nets do.
                revenue =. ((label{revenue)++/nets) label}revenue
                active =. (1+label{active) label}active
            end.
            start =. ReferenceDay-5{2{::customer
            if. (start>:first)*.start<:last do. acquired =. (1+label{acquired) label}acquired end.
        end.
        periods =. periods,<'period | days | | revenue | active | acquired |' format (<period),(<first),(<last),(<(' ' join amount&.><"0 revenue)),(<text_line <"0 active),<text_line <"0 acquired
    end.
    snapshot =. (group_orders 1,SnapshotDay)eligible_customers SnapshotDay
    origins =. empty_table ''
    for_customerbox. snapshot do.
        customer =. >customerbox
        point =. ((<Means),<SDs)standardize transform 2{::customer
        distances =. 0$0.0
        for_center. Centers do. distances =. distances,point squared_distance center end.
        origins =. ((0{customer),<distances i.<./distances) put_key origins
    end.
    table =. ((K+1),K)$0
    moved =. 0$a:
    stayed =. new =. 0
    for_index. i.CustomerCount do.
        id =. index{::CustomerIds
        label =. index{Labels
        origin =. K
        if. id has_key origins do. origin =. id get_key origins end.
        table =. (1+(<origin,label){table) (<origin,label)}table
        if. origin=K do. new =. new+1
        elseif. origin=label do. stayed =. stayed+1
        else. moved =. moved,<'| | |' format (<id),(<origin+1),<label+1 end.
    end.
    lost =. +/-. (table_keys origins)e.CustomerIds
    migration =. <'migration day | customers |' format (<SnapshotDay),<#origins
    migration =. migration,<'from\to ',text_line <"0 1+i.K
    for_origin. i.K+1 do.
        if. origin=K do. text =. 'none' else. text =. number origin+1 end.
        migration =. migration,<text,' ',text_line <"0 origin{table
    end.
    migration =. migration,(<'moved_customers'),moved
    migration =. migration,<'stayed | moved | new | lost |' format (<stayed),(<#moved),(<new),<lost
    first =. ReferenceDay+1
    last =. ReferenceDay+OutcomeDays
    orders =. group_orders first,last
    valid =. 0$a:
    for_orderbox. orders do. if. (3{::>orderbox)>0 do. valid =. valid,orderbox end. end.
    purchases =. orders_by_customer valid
    outcome =. <'outcome days | |' format (<first),<last
    for_segment. i.K do.
        buyers =. spend =. 0
        customers =. segment{::SegmentCustomers
        for_customerbox. customers do.
            id =. 0{::>customerbox
            if. id has_key purchases do.
                buyers =. buyers+1
                for_orderbox. id get_key purchases do. spend =. spend+3{::>orderbox end.
            end.
        end.
        size =. #customers
        outcome =. outcome,<'segment | | size | buyers | rate | revenue | per_customer |' format (<segment+1),(segment{Names),(<size),(<buyers),(<real_text buyers%size),(<amount spend),<real_text (spend%100)%size
    end.
    outsiders =. (table_keys purchases)#~-. (table_keys purchases)e.CustomerIds
    spend =. 0
    for_idbox. outsiders do.
        for_orderbox. (>idbox)get_key purchases do. spend =. spend+3{::>orderbox end.
    end.
    outcome =. outcome,<'unsegmented buyers | revenue |' format (<#outsiders),<amount spend
    join_blocks (<periods),(<migration),<outcome
)
summary_lines =: 3 : 0
    used =. returns =. later =. 0
    for_rowbox. ValidRows do.
        row =. >rowbox
        if. (1{::row)<:ReferenceDay do.
            used =. used+1
            returns =. returns+(4{::row)<0
        else. later =. later+1 end.
    end.
    valid =. 0
    for_orderbox. ReferenceOrders do. valid =. valid+(3{::>orderbox)>0 end.
    excluded =. FileCustomers#~-.FileCustomers e.CustomerIds
    excludedtext =. '-'
    if. #excluded do. excludedtext =. ' ' join excluded end.
    data =. <'rows | duplicates | zero | used | returns | later |' format (<RowCount),(<Duplicates),(<FreeRows),(<used),(<returns),<later
    data =. data,<'orders | valid | cancelled |' format (<#ReferenceOrders),(<valid),<(#ReferenceOrders)-valid
    data =. data,<'customers | clustered | excluded |' format (<#FileCustomers),(<CustomerCount),<#excluded
    data =. data,<'excluded_ids ',excludedtext
    categories =. 0$a:
    for_categorybox. CategoryNames do.
        category =. >categorybox
        spend =. category get_key OverallCategories
        buyers =. 0
        for_customerbox. Customers do.
            totals =. 4{::>customerbox
            if. category has_key totals do. buyers =. buyers+(category get_key totals)>0 end.
        end.
        categories =. categories,<'category | revenue | share | customers |' format (<category),(<amount spend),(<real_text spend%TotalSpend),<buyers
    end.
    features =. 0$a:
    correlations =. <'correlation ',' ' join FeatureNames
    for_feature. i.6 do.
        column =. feature{"1 RawValues
        if. feature{SqrtFeatures do. transformname =. 'sqrt' else. transformname =. 'none' end.
        features =. features,<'feature | transform | raw_mean | raw_sd | mean | sd |' format (feature{FeatureNames),(<transformname),(<real_text mean column),(<real_text sample_sd column),(<real_text feature{Means),<real_text feature{SDs
        values =. 0$0.0
        for_second. i.6 do. values =. values,(feature,second)correlation Points end.
        correlations =. correlations,<(feature{::FeatureNames),' ',reals values
    end.
    join_blocks (<data),(<categories),(<features),<correlations
)
main =: 3 : 0
    read_params ''
    read_transactions ''
    Rules =: read_rules ''
    analyze ''
    if. -.fexist 'output' do. 1!:5 <'output' end.
    'features.csv' write_lines features_lines ''
    'runs.txt' write_lines runs_lines ''
    'selection.txt' write_lines selection_lines ''
    'segments.csv' write_lines segments_lines ''
    'profiles.txt' write_lines profiles_lines ''
    'robustness.txt' write_lines robustness_lines ''
    'tracking.txt' write_lines tracking_lines ''
    'summary.txt' write_lines summary_lines ''
    i.0
)
main ''
