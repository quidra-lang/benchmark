load 'dataset.ijs'
load 'gaussian.ijs'
load 'em.ijs'
load 'kmeans.ijs'
load 'report.ijs'
winner =: 3 : 'y i.>./y'
row_entropy =: 3 : 0
    total =. 0.0
    for_value. y do.
        if. value>0.0 do.
            total =. total+value*^.value
        end.
    end.
    -total
)
parameter_count =: 4 : 0
    select. x
    case. 'FULL' do. (6*y)-1
    case. 'TIED' do. (3*y)+2
    case. 'DIAG' do. (5*y)-1
    case. do. (4*y)-1
    end.
)
fit =: 4 : 0
    points =. x
    'initial count kind type_index' =. y
    'model records densities trace' =. run_em (<points),(<initial),(<kind),(<Iterations),<Epsilon
    p =. kind parameter_count count
    loglik =. {:trace
    bic =. (-2.0*loglik)+p*^.#points
    aic =. (-2.0*loglik)+2*p
    labels =. i.0
    sizes =. count$0
    entropy =. 0.0
    for_row. records do.
        k =. winner row
        labels =. labels,k
        sizes =. (1+k{sizes)k}sizes
        entropy =. entropy+row_entropy row
    end.
    icl =. bic+2.0*entropy
    settled =. <: #trace
    for_t. |.i.#trace do.
        if. (|(t{trace)-loglik)>Tolerance do.
            break.
        end.
        settled =. t
    end.
    largest_t =. 1
    largest_value =. __
    violations =. i.0
    for_t. 1+i.<:#trace do.
        previous =. (t-1){trace
        current =. t{trace
        increase =. current-previous
        if. increase>largest_value do.
            largest_t =. t
            largest_value =. increase
        end.
        if. current<previous-0.000001*|previous do.
            violations =. violations,t
        end.
    end.
    (<model),(<records),(<densities),(<trace),(<count),(<kind),(<type_index),(<p),(<loglik),(<bic),(<aic),(<icl),(<labels),(<sizes),(<entropy),(<settled),(<largest_t),(<largest_value),<violations
)
ranking =: 4 : 0
    indices =. y
    keys =. 0 4$0x
    for_index. indices do.
        model =. index{::Models
        keys =. keys,(4 scaled (9+x){::model),(7{::model),(4{::model),6{::model
    end.
    indices /: keys
)
by_count =: 3 : 0
    indices =. i.0
    for_i. i.#Models do.
        if. y=4{::i{::Models do.
            indices =. indices,i
        end.
    end.
    indices
)
by_kind =: 3 : 0
    indices =. i.0
    for_i. i.#Models do.
        if. y-:5{::i{::Models do.
            indices =. indices,i
        end.
    end.
    indices
)
contingency =: 3 : 0
    'left right rows columns' =. y
    matrix =. (rows,columns)$0x
    for_i. i.#left do.
        position =. <(i{left),i{right
        matrix =. (1+position{matrix)position}matrix
    end.
    matrix
)
choose2 =: 3 : '(y*(y-1))intdiv 2'
ari =: 3 : 0
    'left right rows columns' =. y
    matrix =. contingency y
    shared =. +/,choose2 matrix
    a =. +/choose2 +/"1 matrix
    b =. +/choose2 +/matrix
    z =. choose2 #left
    numerator =. 2*((z*shared)-a*b)
    denominator =. (z*(a+b))-2*a*b
    if. denominator=0 do.
        numerator =. 1x
        denominator =. 1x
    else.
        if. denominator<0 do.
            numerator =. -numerator
            denominator =. -denominator
        end.
        divisor =. (|numerator)+.denominator
        numerator =. numerator intdiv divisor
        denominator =. denominator intdiv divisor
    end.
    (integer numerator),'/',(integer denominator),' ',dec (0.0+numerator)%denominator
)
partition_metrics =: 4 : 0
    'labels count' =. y
    points =. x
    sample_size =. #points
    sizes =. count$0
    centers =. (count,2)$0.0
    occupied =. i.0
    center =. 2$0.0
    for_point. points do.
        center =. center+point
    end.
    center =. center%sample_size
    for_k. i.count do.
        total =. 2$0.0
        size =. 0
        for_i. i.sample_size do.
            if. k=i{labels do.
                total =. total+i{points
                size =. size+1
            end.
        end.
        sizes =. size k}sizes
        if. size do.
            occupied =. occupied,k
            centers =. (total%size)k}centers
        end.
    end.
    cluster =. count$0.0
    if. (#occupied)<2 do.
        (<0),(<0.0),(<0.0),(<0.0),<cluster return.
    end.
    silhouette =. 0.0
    for_i. i.sample_size do.
        own =. i{labels
        own_sum =. 0.0
        nearest =. _
        for_k. occupied do.
            total =. 0.0
            for_j. i.sample_size do.
                if. (k=j{labels)*.j~:i do.
                    total =. total+(i{points)distance j{points
                end.
            end.
            if. k=own do.
                own_sum =. total
            else.
                nearest =. nearest<.total%k{sizes
            end.
        end.
        score =. 0.0
        if. (own{sizes)>1 do.
            a =. own_sum%(own{sizes)-1
            score =. (nearest-a)%(a>.nearest)
        end.
        silhouette =. silhouette+score
        cluster =. (score+own{cluster)own}cluster
    end.
    between =. 0.0
    within =. 0.0
    scatter =. count$0.0
    for_k. occupied do.
        cluster =. ((k{cluster)%k{sizes)k}cluster
        between =. between+(k{sizes)*(k{centers)distance2 center
        total =. 0.0
        for_i. i.sample_size do.
            if. k=i{labels do.
                total =. total+(i{points)distance k{centers
            end.
        end.
        scatter =. (total%k{sizes)k}scatter
    end.
    for_i. i.sample_size do.
        within =. within+(i{points)distance2 (i{labels){centers
    end.
    groups =. #occupied
    ch =. (between%(groups-1))%(within%(sample_size-groups))
    db =. 0.0
    for_k. occupied do.
        worst =. __
        for_other. occupied do.
            if. other~:k do.
                candidate =. ((k{scatter)+other{scatter)%(k{centers)distance other{centers
                worst =. worst>.candidate
            end.
        end.
        db =. db+worst
    end.
    (<1),(<silhouette%sample_size),(<ch),(<db%groups),<cluster
)
metric_text =: 4 : 0
    if. -.0{::y do.
        '-' return.
    end.
    dec (x+1){::y
)
cluster_statistics =: 4 : 0
    clusters =. x
    total =. 0.0
    sizes =. (#clusters)$0
    for_row. y do.
        probabilities =. i.0
        for_cluster. clusters do.
            probability =. 0.0
            for_k. >cluster do.
                probability =. probability+k{row
            end.
            probabilities =. probabilities,probability
        end.
        total =. total+row_entropy probabilities
        k =. winner probabilities
        sizes =. (1+k{sizes)k}sizes
    end.
    (<total),<sizes
)
merge_clusters =: 4 : 0
    'first second' =. x
    result =. 0$a:
    for_j. i.#y do.
        if. j=second do.
            continue.
        end.
        cluster =. j{::y
        if. j=first do.
            cluster =. /:~cluster,second{::y
        end.
        result =. result,<cluster
    end.
    result
)
cluster_name =: 3 : '''+''join integer&.>y+1'
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
estimate =: 3 : 0
    Models =: 0$a:
    Means =: 0$a:
    for_count. Ks do.
        centers =. 1 2{"1 count{::Initial
        Means =: Means,<run_kmeans (<Points),(<centers),<KmeansIterations
        for_type_index. i.#Types do.
            args =. (<count{::Initial),(<count),(type_index{Types),<type_index
            Models =: Models,<Points fit args
        end.
    end.
    BicRanking =: 0 ranking i.#Models
    AicRanking =: 1 ranking i.#Models
    IclRanking =: 2 ranking i.#Models
    Selected =: ({.BicRanking){::Models
    SelectedMeans =: (Ks i.4{::Selected){::Means
    i.0
)
model_files =: 3 : 0
    blocks =. 0$a:
    trace_lines =. <'K,type,iteration,loglik'
    for_fitted. Models do.
        fitted =. >fitted
        'model records densities trace count kind type_index p loglik bic aic icl labels sizes entropy settled largest_t largest_value violations' =. fitted
        block =. (<'model K=',(integer count),' type=',kind),(<'parameters ',integer p),(<'loglik ',dec loglik),(<'bic ',dec bic),(<'aic ',dec aic),(<'icl ',dec icl),(<'mean_entropy ',dec entropy%#Points),(<'settled_at ',integer settled),(<'largest_increase iteration ',(integer largest_t),' value ',dec largest_value),(<'violations ',integer #violations),<'sizes ',integers sizes
        for_k. i.count do.
            component =. k{model
            geometry =. eigen_data 3}.component
            block =. block,<'component ',(integer k+1),' weight ',(dec 0{component),' mean ',(values 1 2{component),' cov ',(values 3}.component),' axes ',(values 5 6{geometry),' angle ',dec 4{geometry
        end.
        blocks =. blocks,<block
        for_t. i.#trace do.
            trace_lines =. trace_lines,<(integer count),',',kind,',',(integer t),',',dec t{trace
        end.
    end.
    'models.txt'write_blocks blocks
    'loglik_trace.csv'write_lines trace_lines
    labels =. 12{::Selected
    records =. 1{::Selected
    densities =. 2{::Selected
    km_labels =. 1{::SelectedMeans
    assignments =. <'id,component,max_responsibility,log_density,kmeans_cluster'
    for_i. i.#Points do.
        assignments =. assignments,<(i{::Ids),',',(integer 1+i{labels),',',(dec >./i{records),',',(dec i{densities),',',integer 1+i{km_labels
    end.
    'assignments.csv'write_lines assignments
)
rankings_and_partitions =: 3 : 0
    SelectionBlocks =: 0$a:
    block =. (<'ranking by bic'),<'rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank'
    for_j. i.#BicRanking do.
        index =. j{BicRanking
        fitted =. index{::Models
        'model records densities trace count kind type_index p loglik bic aic icl labels sizes entropy settled largest_t largest_value violations' =. fitted
        delta =. ((4 scaled bic)-4 scaled 9{::Selected)%10000.0
        block =. block,<(integer j+1),' ',(integer count),' ',kind,' ',(integer p),' ',(dec loglik),' ',(dec bic),' ',(dec delta),' ',(dec aic),' ',(integer 1+AicRanking i.index),' ',(dec icl),' ',integer 1+IclRanking i.index
    end.
    names =. ;:'selected best_aic best_icl'
    indices =. ({.BicRanking),({.AicRanking),{.IclRanking
    for_j. i.3 do.
        fitted =. (j{indices){::Models
        block =. block,<(j{::names),' K=',(integer 4{::fitted),' type=',5{::fitted
    end.
    SelectionBlocks =: SelectionBlocks,<block
    block =. <'best K per type'
    for_kind. Types do.
        indices =. by_kind >kind
        best =. 0$a:
        for_criterion. i.3 do.
            index =. {.criterion ranking indices
            best =. best,<integer 4{::index{::Models
        end.
        block =. block,<(>kind),' bic ',(0{::best),' aic ',(1{::best),' icl ',2{::best
    end.
    SelectionBlocks =: SelectionBlocks,<block
    best_models =. 0$a:
    for_index. i.#Ks do.
        count =. index{Ks
        best =. ({.0 ranking by_count count){::Models
        best_models =. best_models,<best
        km =. index{::Means
        gm_stats =. Points partition_metrics (12{best),<count
        km_stats =. Points partition_metrics (1{km),<count
        block =. (<'K=',(integer count),' type=',(5{::best),' bic ',dec 9{::best),(<'  kmeans iterations ',(integer 2{::km),' inertia ',dec 3{::km),<'  ari ',ari (12{best),(1{km),(<count),<count
        metric_names =. ;:'silhouette calinski_harabasz davies_bouldin'
        for_key. i.3 do.
            block =. block,<'  ',(key{::metric_names),' gmm ',(key metric_text gm_stats),' kmeans ',key metric_text km_stats
        end.
        if. index do.
            previous =. (index-1){::best_models
            matrix =. contingency (12{previous),(12{best),(4{previous),<count
            parents =. 0$a:
            shares =. i.0
            for_k. i.count do.
                counts =. k{"1 matrix
                largest =. >./counts
                parent =. '-'
                if. largest do.
                    parent =. integer 1+counts i.largest
                end.
                parents =. parents,<parent
                shares =. shares,largest
            end.
            block =. block,<'  parents K=',(integer 4{::previous),' ',(' 'join parents),' shared ',integers shares
        end.
        SelectionBlocks =: SelectionBlocks,<block
    end.
    block =. <'violations'
    for_fitted. Models do.
        fitted =. >fitted
        for_t. 18{::fitted do.
            trace =. 3{::fitted
            block =. block,<'K=',(integer 4{::fitted),' type=',(5{::fitted),' iteration ',(integer t),' previous ',(dec (t-1){trace),' current ',dec t{trace
        end.
    end.
    if. 1=#block do.
        block =. block,<'none'
    end.
    SelectionBlocks =: SelectionBlocks,<block
    i.0
)
components_and_overlap =: 3 : 0
    model =. 0{::Selected
    records =. 1{::Selected
    labels =. 12{::Selected
    sizes =. 13{::Selected
    count =. 4{::Selected
    stats =. Points partition_metrics (<labels),<count
    block =. <'selected components'
    for_k. i.count do.
        component =. k{model
        geometry =. eigen_data 3}.component
        observed =. (1+#GofEdges)$0
        soft =. 0.0
        inside_one =. 0
        inside_two =. 0
        for_i. i.#Points do.
            soft =. soft+(<i,k){records
            if. k=i{labels do.
                q =. (i{Points)mahalanobis component
                inside_one =. inside_one+q<:1.0
                inside_two =. inside_two+q<:4.0
                rho =. %:q
                bucket =. +/rho>:GofEdges
                observed =. (1+bucket{observed)bucket}observed
            end.
        end.
        expected =. i.0
        left =. 0.0
        chi =. 0.0
        for_j. i.#observed do.
            end_probability =. 0.0
            if. j<#GofEdges do.
                right =. j{GofEdges
                end_probability =. ^(-right*right)%2.0
            end.
            start_probability =. ^(-left*left)%2.0
            expectation =. (k{sizes)*(start_probability-end_probability)
            expected =. expected,expectation
            delta =. (j{observed)-expectation
            chi =. chi+(delta*delta)%expectation
            if. j<#GofEdges do.
                left =. j{GofEdges
            end.
        end.
        silhouette =. '-'
        if. (0{::stats)*.(k{sizes)>0 do.
            silhouette =. dec k{4{::stats
        end.
        block =. block,<'component ',(integer k+1),' weight ',(dec 0{component),' size ',(integer k{sizes),' soft_size ',(dec soft),' mean ',values 1 2{component
        block =. block,<'  cov ',(values 3}.component),' corr ',dec 8{geometry
        block =. block,<'  eigen ',(values 0 1{geometry),' direction ',(values 2 3{geometry),' angle ',dec 4{geometry
        block =. block,<'  axes_1sigma ',(values 5 6{geometry),' axes_2sigma ',values 2.0*5 6{geometry
        block =. block,<'  inside_1sigma ',(integer inside_one),' inside_2sigma ',(integer inside_two),' area_1sigma ',dec 7{geometry
        block =. block,<'  silhouette ',silhouette
        block =. block,<'  gof observed ',(integers observed),' expected ',(values expected),' chi2 ',dec chi
    end.
    SelectionBlocks =: SelectionBlocks,<block
    block =. <'overlap'
    for_first. i.0>.count-1 do.
        for_second. (first+1)+i.count-(first+1) do.
            overlap =. (first{model)bhattacharyya second{model
            shared =. 0.0
            for_row. records do.
                shared =. shared+(first{row)*second{row
            end.
            block =. block,<(integer first+1),'-',(integer second+1),' bhattacharyya ',(dec 0{overlap),' coefficient ',(dec 1{overlap),' shared ',dec shared
        end.
    end.
    if. 1=#block do.
        block =. block,<'none'
    end.
    SelectionBlocks =: SelectionBlocks,<block
    i.0
)
merging =: 3 : 0
    records =. 1{::Selected
    clusters =. 0$a:
    for_k. i.4{::Selected do.
        clusters =. clusters,<,k
    end.
    'start_entropy initial_sizes' =. clusters cluster_statistics records
    block =. (<'merging'),<'start entropy ',dec start_entropy
    step =. 0
    while. (#clusters)>1 do.
        best =. 0$a:
        first =. _1
        second =. _1
        best_entropy =. _
        best_sizes =. i.0
        for_a. i.<:#clusters do.
            for_b. (a+1)+i.(#clusters)-(a+1) do.
                proposed =. (a,b)merge_clusters clusters
                'total sizes' =. proposed cluster_statistics records
                take =. first<0
                if. -.take do.
                    take =. (4 scaled total)<4 scaled best_entropy
                end.
                if. take do.
                    best =. proposed
                    first =. a
                    second =. b
                    best_entropy =. total
                    best_sizes =. sizes
                end.
            end.
        end.
        step =. step+1
        block =. block,<'step ',(integer step),' merge ',(cluster_name first{::clusters),' ',(cluster_name second{::clusters),' entropy ',(dec best_entropy),' sizes ',integers best_sizes
        clusters =. best
    end.
    SelectionBlocks =: SelectionBlocks,<block
    i.0
)
kmeans_comparison_and_refit =: 3 : 0
    count =. 4{::Selected
    labels =. 12{::Selected
    records =. 1{::Selected
    'centers km_labels iterations inertia sizes' =. SelectedMeans
    matrix =. contingency (<labels),(<km_labels),(<count),<count
    best_permutation =. i.0
    agreement =. _1
    for_permutation. (i.0)permutations count do.
        permutation =. >permutation
        total =. 0
        for_j. i.count do.
            total =. total+(<(j{permutation),j){matrix
        end.
        if. total>agreement do.
            agreement =. total
            best_permutation =. permutation
        end.
    end.
    block =. (<'kmeans K=',integer count),(<'iterations ',integer iterations),(<'inertia ',dec inertia),<'sizes ',integers sizes
    for_k. i.count do.
        block =. block,<'center ',(integer k+1),' ',values k{centers
    end.
    block =. block,<'contingency'
    for_row. matrix do.
        block =. block,<integers row
    end.
    block =. block,<'ari ',ari (<labels),(<km_labels),(<count),<count
    block =. block,<'matching ',integers best_permutation+1
    block =. block,<'agreement ',(integer agreement),'/',(integer #Points),' ',dec agreement%#Points
    disagreements =. 0
    for_i. i.#Points do.
        cluster =. i{km_labels
        if. (cluster{best_permutation)~:i{labels do.
            disagreements =. disagreements+1
            block =. block,<'disagree ',(i{::Ids),' gmm ',(integer 1+i{labels),' kmeans ',(integer cluster+1),' max ',dec >./i{records
        end.
    end.
    block =. block,<'disagreements ',integer disagreements
    SelectionBlocks =: SelectionBlocks,<block
    initial =. 0 6$0.0
    for_k. i.count do.
        a =. 0.0
        b =. 0.0
        c =. 0.0
        for_i. i.#Points do.
            if. k=i{km_labels do.
                'dx dy' =. (i{Points)-k{centers
                a =. a+dx*dx
                b =. b+dx*dy
                c =. c+dy*dy
            end.
        end.
        size =. k{sizes
        initial =. initial,(size%#Points),(k{centers),((a%size)+Epsilon),(b%size),(c%size)+Epsilon
    end.
    refit =. Points fit (<initial),(4{Selected),(5{Selected),6{Selected
    block =. (<'refit_from_kmeans K=',(integer count),' type=',5{::Selected),(<'loglik ',(dec 8{::refit),' bic ',(dec 9{::refit),' settled_at ',integer 15{::refit),(<'sizes ',integers 13{::refit),<'ari_vs_selected ',ari (<labels),(12{refit),(<count),<count
    SelectionBlocks =: SelectionBlocks,<block
    i.0
)
cross_validation =: 3 : 0
    count =. 4{::Selected
    kind =. 5{::Selected
    block =. <'cross_validation K=',(integer count),' type=',kind,' folds ',integer Folds
    total =. 0.0
    for_fold. i.Folds do.
        indices =. i.#Points
        testing =. Points#~fold=Folds|indices
        training =. Points#~fold~:Folds|indices
        'model records densities trace' =. run_em (<training),(<count{::Initial),(<kind),(<Iterations),<Epsilon
        'test_records test_densities test_total' =. testing expectation model
        train_loglik =. ({:trace)%#training
        test_loglik =. test_total%#testing
        total =. total+test_loglik
        block =. block,<'fold ',(integer fold+1),' train ',(integer #training),' test ',(integer #testing),' train_loglik ',(dec train_loglik),' test_loglik ',dec test_loglik
    end.
    block =. block,<'mean_test_loglik ',dec total%Folds
    SelectionBlocks =: SelectionBlocks,<block
    i.0
)
point_order =: 3 : 0
    records =. 1{::Selected
    densities =. 2{::Selected
    indices =. i.0
    keys =. 0 2$0x
    for_i. i.#Points do.
        if. y do.
            score =. >./i{records
            threshold =. UncertainThreshold
        else.
            score =. i{densities
            threshold =. LowDensityThreshold
        end.
        if. score<threshold do.
            indices =. indices,i
            keys =. keys,(4 scaled score),i
        end.
    end.
    indices /: keys
)
uncertain_and_outliers =: 3 : 0
    records =. 1{::Selected
    labels =. 12{::Selected
    densities =. 2{::Selected
    model =. 0{::Selected
    uncertain =. point_order 1
    block =. <'uncertain threshold ',dec UncertainThreshold
    for_i. uncertain do.
        row =. i{records
        block =. block,<(i{::Ids),' component ',(integer 1+i{labels),' max ',(dec >./row),' responsibilities ',values row
    end.
    block =. block,<'count ',integer #uncertain
    SelectionBlocks =: SelectionBlocks,<block
    outliers =. point_order 0
    block =. <'outliers threshold ',dec LowDensityThreshold
    for_i. outliers do.
        k =. i{labels
        q =. (i{Points)mahalanobis k{model
        block =. block,<(i{::Ids),' component ',(integer k+1),' log_density ',(dec i{densities),' q ',dec q
    end.
    block =. block,<'count ',integer #outliers
    SelectionBlocks =: SelectionBlocks,<block
    i.0
)
map_cell =: 3 : '<.(((0{y)-Xmin),Ymax-1{y)%Dx,Dy'
valid_cell =: 3 : '(0<:0{y)*.((0{y)<Width)*.(0<:1{y)*.(1{y)<Height'
map_file =: 3 : 0
    count =. 4{::Selected
    kind =. 5{::Selected
    model =. 0{::Selected
    coordinates =. (Height,Width,2)$0.0
    densities =. (Height,Width)$0.0
    responsibilities =. (Height,Width,count)$0.0
    winners =. (Height,Width)$0
    maximum =. 0.0
    mass =. 0.0
    for_row. i.Height do.
        for_column. i.Width do.
            point =. (Xmin+(column+0.5)*Dx),Ymax-(row+0.5)*Dy
            coordinates =. point (<row,column)}coordinates
            scores =. i.0
            density =. 0.0
            for_component. model do.
                score =. point weighted_log_density component
                scores =. scores,score
                density =. density+^score
            end.
            probabilities =. ^scores->./scores
            normalizer =. 0.0
            for_term. probabilities do.
                normalizer =. normalizer+term
            end.
            probabilities =. probabilities%normalizer
            densities =. density (<row,column)}densities
            responsibilities =. probabilities (<row,column)}responsibilities
            winners =. (winner scores)(<row,column)}winners
            maximum =. maximum>.density
            mass =. mass+density
        end.
    end.
    density_map =. (Height,Width)$' '
    region_map =. density_map
    uncertainty_map =. density_map
    point_map =. density_map
    level_counts =. 10$0
    for_row. i.Height do.
        for_column. i.Width do.
            level =. 9<.<.(10.0*(<row,column){densities)%maximum
            level_counts =. (1+level{level_counts)level}level_counts
            density_map =. (level{Levels)(<row,column)}density_map
            digit =. integer 1+(<row,column){winners
            region_map =. ({.digit)(<row,column)}region_map
            level =. 0
            if. count>:2 do.
                level =. (0>.9<.<.(10.0*row_entropy (<row,column){responsibilities)%^.count)
            end.
            uncertainty_map =. (level{Levels)(<row,column)}uncertainty_map
            contour =. 0
            for_component. model do.
                if. (((<row,column){coordinates)mahalanobis component)>4.0 do.
                    continue.
                end.
                for_offset. 4 2$0 _1 0 1 _1 0 1 0 do.
                    neighbor =. (column,row)+offset
                    if. valid_cell neighbor do.
                        if. (((<(1{neighbor),0{neighbor){coordinates)mahalanobis component)>4.0 do.
                            contour =. 1
                            break.
                        end.
                    end.
                end.
                if. contour do.
                    break.
                end.
            end.
            if. contour do.
                point_map =. '.'(<row,column)}point_map
            end.
        end.
    end.
    for_k. i.count do.
        cell =. map_cell 1 2{k{model
        if. valid_cell cell do.
            density_map =. ({.integer k+1)(<(1{cell),0{cell)}density_map
        end.
    end.
    bins =. (Height,Width)$_1
    outside =. 0
    labels =. 12{::Selected
    for_i. i.#Points do.
        cell =. map_cell i{Points
        if. -.valid_cell cell do.
            outside =. outside+1
            continue.
        end.
        position =. <(1{cell),0{cell
        previous =. position{bins
        if. previous=_1 do.
            bins =. (i{labels)position}bins
        elseif. previous~:i{labels do.
            bins =. _2 position}bins
        end.
    end.
    for_row. i.Height do.
        for_column. i.Width do.
            component =. (<row,column){bins
            if. component=_2 do.
                point_map =. '*'(<row,column)}point_map
            elseif. component>:0 do.
                point_map =. ({.integer component+1)(<row,column)}point_map
            end.
        end.
    end.
    rows =. (<'density K=',(integer count),' type=',kind),(<'x ',(dec Xmin),' ',(dec Xmax),' y ',(dec Ymin),' ',(dec Ymax),' grid ',(integer Width),'x',integer Height),<'max_density ',(6 decimal maximum),' mass_in_map ',dec (mass*Dx)*Dy
    rows =. rows,framed <"1 density_map
    for_level. i.10 do.
        rows =. rows,<'level ',(integer level),' "',(level{Levels),'" from ',(6 decimal (level*maximum)%10.0),' cells ',integer level{level_counts
    end.
    rows =. rows,(<''),(<'regions'),framed <"1 region_map
    rows =. rows,(<''),(<'uncertainty'),framed <"1 uncertainty_map
    rows =. rows,(<''),(<'points'),framed <"1 point_map
    rows =. rows,<'outside ',integer outside
    'density_map.txt'write_lines rows
)
run =: 3 : 0
    'Ids Points Initial Params' =: read_inputs ''
    Ks =: 0{::Params
    Iterations =: {.1{::Params
    Types =: 2{::Params
    Epsilon =: {.3{::Params
    Tolerance =: {.4{::Params
    KmeansIterations =: {.5{::Params
    Folds =: {.6{::Params
    UncertainThreshold =: {.7{::Params
    LowDensityThreshold =: {.8{::Params
    GofEdges =: 9{::Params
    'Xmin Xmax' =: 10{::Params
    'Ymin Ymax' =: 11{::Params
    'Width Height' =: 12{::Params
    Dx =: (Xmax-Xmin)%Width
    Dy =: (Ymax-Ymin)%Height
    estimate ''
    model_files ''
    rankings_and_partitions ''
    components_and_overlap ''
    merging ''
    kmeans_comparison_and_refit ''
    cross_validation ''
    uncertain_and_outliers ''
    'selection.txt'write_blocks SelectionBlocks
    map_file ''
    i.0
)
run ''
