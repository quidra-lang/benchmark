ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
div =: 4 : '_1 x:<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
number =: 3 : 0
    y =. x:y
    sign =. ''
    if. y<0 do. sign =. '-'
        y =. -y end.
    text =. ''
    while. y>0 do. text =. ((10|y){Digits),text
        y =. <.y%10x end.
    if. #text do. sign,text else. '0' end.
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
    parts =. '|'split x
    text =. 0{::parts
    for_index. i.#y do.
        value =. index{::y
        if. 2~:3!:0 value do. value =. number value end.
        text =. text,value,(index+1){::parts
    end.
    text
)
ascii_order =: 3 : '/: > (a.&i.)&.> y'
four_digit =: 3 : 0
    value =. x:y
    (*value)*<.(1r2)+10000*|value
)
real =: 3 : 0
    if. 2=3!:0 y do. '-' return. end.
    rounded =. four_digit y
    sign =. ''
    if. rounded<0 do. sign =. '-'
        rounded =. -rounded end.
    tail =. number 10000|rounded
    sign,(number <.rounded%10000x),'.',((4-#tail)$'0'),tail
)
reals =: 3 : ''' ''join real&.><"0 y'
integers =: 3 : ''' ''join <"0 y'
ari_value =: 3 : '(0{y)%1{y'
ari_text =: 3 : '(number 0{y),''/'',(number 1{y),'' '',real ari_value y'
ari_greater =: 4 : '((0{x)*1{y)>(0{y)*1{x'
paragraph =: 4 : 0
    if. #x do. x,(<''),y else. y end.
)
load SourceDirectory,'dataset.ijs'
load SourceDirectory,'distances.ijs'
load SourceDirectory,'agglomerative.ijs'
load SourceDirectory,'dendrogram.ijs'
load SourceDirectory,'validation.ijs'
pair_values =: 3 : 0
    values =. 0$0.0
    for_i. i.#y do.
        for_j. (i+1)+i.(#y)-(i+1)do. values =. values,(<i,j){y end.
    end.
    values
)
histogram_bin =: 4 : '9<.<.(10*y)%x'
cluster_members =: 3 : 0
    members =. 0$a:
    for_group. 1+i.>./y do. members =. members,<I.y=group end.
    members
)
centroid =: 3 : 0
    center =. 0$0.0
    for_feature. i.{:$y do. center =. center,(sequential_sum feature{"1 y)%#y end.
    center
)
centroids =: 3 : 0
    centers =. (0,FeatureCount)$0.0
    for_members. cluster_members y do. centers =. centers,centroid (>members){Vectors end.
    centers
)
majority_class =: 3 : 'y i.>./y'
make_tree =: 4 : 0
    count =. y
    merges =. x
    heights =. subtree_heights =. 0$0.0
    children =. merges ordered_children count
    order =. count leaf_order children
    members =. <"0 i.count
    depths =. count$0
    for_merge. merges do.
        merge =. >merge
        a =. 0{::merge
        b =. 1{::merge
        height =. 2{::merge
        heights =. heights,height
        members =. members,<(a{::members),b{::members
        depths =. depths,1+(a{depths)>.b{depths
        first =. second =. 0.0
        if. a>:count do. first =. (a-count){subtree_heights end.
        if. b>:count do. second =. (b-count){subtree_heights end.
        subtree_heights =. subtree_heights,height>.first>.second
    end.
    (<count),(<merges),(<heights),(<children),(<order),(<members),(<depths),<subtree_heights
)
cut_partition =: 4 : 0
    count =. 0{::x
    owner =. i.count
    members =. 5{::x
    for_step. I.y do.
        node =. count+step
        owner =. node (node{::members)}owner
    end.
    numbers =. ((2*count)-1)$0
    groups =. 0
    for_leaf. 4{::x do.
        node =. leaf{owner
        if. 0=node{numbers do. groups =. groups+1
            numbers =. groups node}numbers end.
    end.
    owner{numbers
)
cut_into =: 4 : 'x cut_partition (i.(0{::x)-1)<(0{::x)-y'
cut_at =: 4 : 'x cut_partition (7{::x)<:y'
tree_cophenetic =: 3 : 0
    count =. 0{::y
    members =. 5{::y
    matrix =. (count,count)$0.0
    for_merge. 1{::y do.
        merge =. >merge
        a =. 0{::merge
        b =. 1{::merge
        height =. 2{::merge
        for_i. a{::members do.
            for_j. b{::members do.
                matrix =. height (<i,j)}matrix
                matrix =. height (<j,i)}matrix
            end.
        end.
    end.
    pair_values matrix
)
joining_heights =: 3 : 0
    count =. 0{::y
    heights =. count$0.0
    for_merge. 1{::y do.
        merge =. >merge
        for_child. >0 1{merge do.
            if. child<count do. heights =. (2{::merge)child}heights end.
        end.
    end.
    heights
)
height_sequence =: 4 : 0
    'step depth' =. y
    if. depth=0 do. 0$0.0 return. end.
    count =. 0{::x
    merge =. step{::1{::x
    values =. ,2{::merge
    for_child. >0 1{merge do.
        if. child>:count do. values =. values,x height_sequence (child-count),depth-1 end.
    end.
    values
)
tree_height =: 4 : 0
    if. y<0{::x do. 0.0 else. (y-0{::x){2{::x end.
)
tree_newick =: 4 : 0
    count =. 0{::x
    if. y<count do. y{::Ids return. end.
    'upper lower' =. (y-count){3{::x
    height =. x tree_height y
    '(', (x tree_newick upper),':',(real height-x tree_height upper),',',(x tree_newick lower),':',(real height-x tree_height lower),')'
)
class_table =: 3 : '((>./y),ClassCount)contingency_table (<y-1),<Targets'
label_ari =: 3 : 'adjusted_rand_index class_table y'
partition_ari =: 4 : 'adjusted_rand_index ((>./x),>./y)contingency_table (<x-1),<y-1'
match_count =: 3 : '+/>./"1 class_table y'
mean_silhouette =: 4 : 0
    if. (>./x)<2 do. ''
    else. (sequential_sum x silhouette_values y)%#x end.
)
within_sum =: 3 : 0
    centers =. centroids y
    total =. 0.0
    for_i. i.Count do. total =. total+(i{Vectors)squared_distance ((i{y)-1){centers end.
    total
)
evaluate =: 3 : 0
    groups =. >./y
    members =. cluster_members y
    sizes =. #&>members
    wss =. within_sum y
    silhouette =. y mean_silhouette Distances
    diameter =. separation =. 0.0
    found =. 0
    for_i. i.Count do.
        for_j. (i+1)+i.Count-(i+1)do.
            value =. (<i,j){Distances
            if. (i{y)=j{y do. diameter =. diameter>.value
            elseif. (-.found)+.value<separation do. separation =. value
                found =. 1 end.
        end.
    end.
    dunn =. ch =. ''
    if. (groups>:2)*.diameter>0 do. dunn =. separation%diameter end.
    if. (groups>:2)*.groups<Count do.
        overall =. centroid Vectors
        centers =. centroids y
        bss =. 0.0
        for_group. i.groups do. bss =. bss+(group{sizes)*(group{centers)squared_distance overall end.
        ch =. (bss%groups-1)%(wss%Count-groups)
    end.
    (<y),(<sizes),(<silhouette),(<dunn),(<wss),(<ch),<label_ari y
)
evaluation_text =: 3 : 0
    'partition sizes silhouette dunn wss ch ari' =. y
    'sizes | silhouette | dunn | wss | ch | ari |'format (integers sizes);(real silhouette);(real dunn);(real wss);(real ch);ari_text ari
)
analyse_linkage =: 3 : 0
    tree =. (y agglomerate Distances)make_tree Count
    cophenetic =. tree_cophenetic tree
    height_cuts =. count_cuts =. 0$a:
    for_height. CutHeights do. height_cuts =. height_cuts,<evaluate tree cut_at height end.
    for_count. CutCounts do. count_cuts =. count_cuts,<evaluate tree cut_into count end.
    (<y),(<tree),(<cophenetic),(<DistancePairs correlation cophenetic),(<height_cuts),(<count_cuts),<tree cut_into ClassCount
)
prepare_study =: 3 : 0
    read_dataset''
    'Means Deviations' =: feature_statistics Raw
    Vectors =: Raw
    if. Standardize-:'yes' do. Vectors =: (Means;Deviations)standardize_vectors Raw end.
    Distances =: DistanceName distance_matrix Vectors
    DistancePairs =: pair_values Distances
    DistanceMax =: >./DistancePairs
    Neighbors =: 0$0
    for_i. i.Count do.
        best =. _1
        for_j. i.Count do.
            if. i=j do. continue. end.
            if. best<0 do. best =. j
            elseif. ((<i,j){Distances)<(<i,best){Distances do. best =. j end.
        end.
        Neighbors =: Neighbors,best
    end.
    Results =: 0$a:
    for_method. Linkages do. Results =: Results,<analyse_linkage >method end.
    ChosenIndex =: ChosenPosition =: 0
    for_method. i.#Results do.
        cuts =. 5{::method{::Results
        for_position. i.#CutCounts do.
            best =. ChosenPosition{::5{::ChosenIndex{::Results
            if. (6{::position{::cuts)ari_greater 6{::best do.
                ChosenIndex =: method
                ChosenPosition =: position
            end.
        end.
    end.
    Chosen =: ChosenIndex{::Results
    Kappa =: ChosenPosition{CutCounts
    SelectedCut =: ChosenPosition{::5{::Chosen
    Selected =: 0{::SelectedCut
    Members =: cluster_members Selected
    Silhouettes =: Selected silhouette_values Distances
    ClassTable =: class_table Selected
    Majority =: majority_class"1 ClassTable
    i.0
)
linkage_table =: 3 : 0
    lines =. <'method,step,a,b,height,size'
    for_result. Results do.
        result =. >result
        method =. 0{::result
        merges =. 1{::1{::result
        for_step. i.#merges do.
            'a b height size' =. step{::merges
            lines =. lines,<'|,|,|,|,|,|'format method;(step+1);a;b;(real height);size
        end.
    end.
    lines
)
clusters_table =: 3 : 0
    header =. 'id';'label'
    for_method. Linkages do.
        method =. >method
        for_index. i.#CutHeights do. header =. header,<method,'_h',number index+1 end.
        for_k. CutCounts do. header =. header,<method,'_k',number k end.
    end.
    lines =. <','join header
    for_i. i.Count do.
        row =. (i{Ids),i{Labels
        for_result. Results do.
            result =. >result
            for_cut. (4{::result),5{::result do. row =. row,<i{0{::>cut end.
        end.
        lines =. lines,<','join row
    end.
    lines
)
dendrogram_report =: 3 : 0
    lines =. 0$a:
    for_result. Results do.
        result =. >result
        tree =. 1{::result
        maximum =. >./2{::tree
        columns =. 0$0
        for_height. CutHeights do. columns =. columns,(maximum,Width)height_column height end.
        part =. <'dendrogram | height_max | width |'format (0{::result);(real maximum);Width
        part =. part,dendrogram_rows (<tree),(<maximum),<columns
        for_index. i.#CutHeights do.
            column =. '-'
            if. (index{columns)<:Width do. column =. number index{columns end.
            part =. part,<'cut | column |'format (real index{CutHeights);column
        end.
        lines =. lines paragraph part
    end.
    lines
)
trees_report =: 3 : 0
    lines =. 0$a:
    for_result. Results do.
        result =. >result
        tree =. 1{::result
        lines =. lines,<(0{::result),' ',(tree tree_newick (2*Count)-2),';'
    end.
    lines
)
pair_text =: 3 : 0
    'i j' =. y
    (real (<i,j){Distances),' ',(i{::Ids),' ',j{::Ids
)
data_part =: 3 : 0
    lines =. <'data n | features | classes | distance | standardize |'format Count;FeatureCount;ClassCount;DistanceName;Standardize
    for_feature. i.FeatureCount do. lines =. lines,<'feature | mean | sd |'format (feature{::FeatureNames);(real feature{Means);real feature{Deviations end.
    smallest =. largest =. 0 1
    for_i. i.Count do.
        for_j. (i+1)+i.Count-(i+1)do.
            value =. (<i,j){Distances
            if. value<(<smallest){Distances do. smallest =. i,j end.
            if. value>(<largest){Distances do. largest =. i,j end.
        end.
    end.
    lines =. lines,<'distances pairs | min | max | mean |'format (#DistancePairs);(pair_text smallest);(pair_text largest);real (sequential_sum DistancePairs)%#DistancePairs
    total =. 0.0
    reciprocal =. 0
    for_i. i.Count do.
        neighbor =. i{Neighbors
        total =. total+(<i,neighbor){Distances
        reciprocal =. reciprocal+(i<neighbor)*.i=neighbor{Neighbors
    end.
    lines =. lines,<'nearest_neighbors mean | reciprocal_pairs |'format (real total%Count);reciprocal
    lines,<'labels ',evaluation_text evaluate Targets+1
)
correlation_part =: 3 : 0
    lines =. <'correlation ',' 'join FeatureNames
    for_first. i.FeatureCount do.
        values =. 0$0.0
        for_second. i.FeatureCount do. values =. values,(first{"1 Raw)correlation second{"1 Raw end.
        lines =. lines,<(first{::FeatureNames),' ',reals values
    end.
    lines
)
histogram_part =: 3 : 0
    counts =. 10$0
    for_value. DistancePairs do.
        bin =. DistanceMax histogram_bin value
        counts =. (1+bin{counts)bin}counts
    end.
    highest =. >./counts
    lines =. <'histogram'
    for_bin. i.10 do.
        count =. bin{counts
        text =. '| | |'format (real (bin*DistanceMax)%10);(real ((bin+1)*DistanceMax)%10);count
        length =. (count*50)div highest
        if. length do. text =. text,' ',length$'#' end.
        lines =. lines,<text
    end.
    lines
)
linkage_part =: 3 : 0
    'method tree cophenetic coefficient height_cuts count_cuts label_partition' =. y
    heights =. 2{::tree
    order =. 4{::tree
    path =. 0.0
    for_row. i.Count-1 do. path =. path+(<(row{order),(row+1){order){Distances end.
    inversions =. 0$0
    for_step. 1+i.Count-2 do. if. (step{heights)<(step-1){heights do. inversions =. inversions,step end. end.
    lines =. (<'linkage ',method),<'cophenetic | leaf_path |'format (real coefficient);real path
    lines =. lines,<'heights min | max | inversions |'format (real <./heights);(real >./heights);#inversions
    for_step. inversions do. lines =. lines,<'inversion step | height | previous |'format (step+1);(real step{heights);real (step-1){heights end.
    ordered =. /:~7{::tree
    gaps =. 0$0.0
    for_k. 2+i.GapMaxK-1 do. gaps =. gaps,((Count-k){ordered)-((Count-k)-1){ordered end.
    suggested =. 2
    for_k. 3+i.GapMaxK-2 do.
        if. (four_digit (k-2){gaps)>four_digit (suggested-2){gaps do. suggested =. k end.
    end.
    lines =. lines,<'gaps ',reals gaps
    lines =. lines,<'suggested_k ',number suggested
    joining =. joining_heights tree
    late =. ListSize{./:(-joining),.i.Count
    pairs =. 0$a:
    for_leaf. late do. pairs =. pairs,<(leaf{::Ids),':',real leaf{joining end.
    lines =. lines,<'late_joiners ',' 'join pairs
    kinds =. 3$0
    for_merge. 1{::tree do.
        leaves =. +/(>0 1{>merge)<Count
        kind =. 2-leaves
        kinds =. (1+kind{kinds)kind}kinds
    end.
    lines =. lines,<'merges leaf_leaf | leaf_cluster | cluster_cluster | depth |'format (0{kinds);(1{kinds);(2{kinds);{:6{::tree
    matches =. match_count label_partition
    lines =. lines,<'label_cut k | purity |/| |'format ClassCount;matches;Count;real matches%Count
    lines =. lines,<'inconsistency depth ',InconsistencyDepthText
    for_step. ((Count-InconsistencyCount)-1)+i.InconsistencyCount do.
        sequence =. tree height_sequence step,InconsistencyDepth
        size =. #sequence
        mean =. (sequential_sum sequence)%size
        deviation =. coefficient =. 0.0
        if. size>:2 do.
            squares =. 0.0
            for_value. sequence do. difference =. value-mean
                squares =. squares+difference*difference end.
            deviation =. %:squares%size-1
            coefficient =. ((step{heights)-mean)%deviation
        end.
        lines =. lines,<'step | height | mean | sd | count | coefficient |'format (step+1);(real step{heights);(real mean);(real deviation);size;real coefficient
    end.
    for_index. i.#CutHeights do.
        cut =. index{::height_cuts
        lines =. lines,<'cut height | clusters | |'format (real index{CutHeights);(#1{::cut);evaluation_text cut
    end.
    for_index. i.#CutCounts do. lines =. lines,<'cut k | |'format (index{CutCounts);evaluation_text index{::count_cuts end.
    lines
)
mst_part =: 3 : 0
    single =. (Linkages i.<'single'){::Results
    tree =. 1{::single
    edges =. minimum_spanning_tree Distances
    weights =. 0$0.0
    linked =. (Count,Count)$0
    for_edge. edges do.
        'parent child weight' =. >edge
        weights =. weights,weight
        linked =. 1 (<parent,child)}linked
        linked =. 1 (<child,parent)}linked
    end.
    total =. sequential_sum weights
    matches =. *./0.000000001>:|(/:~weights)-2{::tree
    match_text =. 'mismatch'
    if. matches do. match_text =. 'match' end.
    nn_edges =. 0
    for_i. i.Count do. nn_edges =. nn_edges+(<i,i{Neighbors){linked end.
    lines =. <'mst total | heights | nn_edges |/|'format (real total);match_text;nn_edges;Count
    ordered =. (/:weights){edges
    for_position. i.#CutCounts do.
        k =. position{CutCounts
        component =. i.Count
        for_edge. (Count-k){.ordered do.
            'parent child weight' =. >edge
            old =. child{component
            new =. parent{component
            component =. new (I.component=old)}component
        end.
        partition =. 0{::position{::5{::single
        matches =. 1
        for_i. i.Count do.
            for_j. (i+1)+i.Count-(i+1)do.
                if. ((i{component)=j{component)~:((i{partition)=j{partition)do. matches =. 0 end.
            end.
        end.
        match_text =. 'mismatch'
        if. matches do. match_text =. 'match' end.
        lines =. lines,<'mst partition k | |'format k;match_text
    end.
    lines
)
compare_part =: 3 : 0
    lines =. <'compare linkage | k |'format CompareLinkage;ClassCount
    for_kind. 'euclidean';'manhattan';'correlation' do.
        kind =. >kind
        delta =. kind distance_matrix Vectors
        tree =. (CompareLinkage agglomerate delta)make_tree Count
        partition =. tree cut_into ClassCount
        coefficient =. (pair_values delta)correlation tree_cophenetic tree
        lines =. lines,<'metric | cophenetic | silhouette | ari |'format kind;(real coefficient);(real partition mean_silhouette delta);ari_text label_ari partition
    end.
    lines
)
cophenetic_part =: 3 : 0
    lines =. (<'cophenetic_matrix'),<'linkage ',' 'join Linkages
    for_first. Results do.
        first =. >first
        values =. 0$0.0
        for_second. Results do. values =. values,(2{::first)correlation 2{::>second end.
        lines =. lines,<(0{::first),' ',reals values
    end.
    lines
)
agreement_part =: 3 : 0
    lines =. (<'agreement k ',number ClassCount),<'linkage ',' 'join Linkages
    for_first. Results do.
        first =. >first
        values =. 0$0.0
        for_second. Results do. values =. values,ari_value (6{::first)partition_ari 6{::>second end.
        lines =. lines,<(0{::first),' ',reals values
    end.
    lines
)
summary_part =: 3 : 0
    coefficients =. 0$0.0
    for_result. Results do. coefficients =. coefficients,four_digit 3{::>result end.
    ranking =. /:(-coefficients),.i.#Results
    lines =. (<'summary'),<'cophenetic_ranking ',' 'join ranking{Linkages
    for_position. i.#CutCounts do.
        best =. 0{::Results
        best_cut =. position{::5{::best
        for_result. }.Results do.
            result =. >result
            cut =. position{::5{::result
            if. (6{::cut)ari_greater 6{::best_cut do. best =. result
                best_cut =. cut end.
        end.
        lines =. lines,<'best_ari k | | |'format (position{CutCounts);(0{::best);ari_text 6{::best_cut
    end.
    for_result. Results do.
        result =. >result
        cuts =. 5{::result
        best =. 0
        for_position. 1+i.(#cuts)-1 do.
            if. (four_digit 2{::position{::cuts)>four_digit 2{::best{::cuts do. best =. position end.
        end.
        lines =. lines,<'best_silhouette | k | |'format (0{::result);(best{CutCounts);real 2{::best{::cuts
    end.
    lines,<'selected | k |'format (0{::Chosen);Kappa
)
validation_report =: 3 : 0
    lines =. data_part''
    lines =. lines paragraph correlation_part''
    lines =. lines paragraph histogram_part''
    for_result. Results do. lines =. lines paragraph linkage_part >result end.
    if. (<'single')e.Linkages do. lines =. lines paragraph mst_part'' end.
    lines =. lines paragraph compare_part''
    lines =. lines paragraph cophenetic_part''
    lines =. lines paragraph agreement_part''
    lines paragraph summary_part''
)
cluster_lines =: 3 : 0
    group =. y{::Members
    size =. #group
    silhouette =. (sequential_sum group{Silhouettes)%size
    majority =. y{Majority
    majority_count =. (<y,majority){ClassTable
    means =. centroid group{Raw
    medoid =. _1
    medoid_sum =. 0.0
    for_i. group do.
        total =. 0.0
        for_j. group do. total =. total+(<i,j){Distances end.
        if. (medoid<0)+.total<medoid_sum do. medoid =. i
            medoid_sum =. total end.
    end.
    diameter =. '0.0000 - -'
    first =. second =. _1
    for_position. i.#group do.
        i =. position{group
        for_j. (position+1)}.group do.
            if. first<0 do. first =. i
                second =. j
            elseif. ((<i,j){Distances)>(<first,second){Distances do. first =. i
                second =. j end.
        end.
    end.
    if. first>:0 do. diameter =. pair_text first,second end.
    nearest =. _1
    nearest_separation =. 0.0
    for_h. i.Kappa do.
        if. h=y do. continue. end.
        other =. h{::Members
        separation =. (<({.group),{.other){Distances
        for_i. group do.
            for_j. other do. separation =. separation<.(<i,j){Distances end.
        end.
        if. (nearest<0)+.separation<nearest_separation do. nearest =. h
            nearest_separation =. separation end.
    end.
    lines =. <'cluster | size | silhouette | majority | purity |/| |'format (y+1);size;(real silhouette);(majority{::Classes);majority_count;size;real majority_count%size
    lines =. lines,<'  mean ',reals means
    lines,<'  medoid | diameter | nearest | separation |'format (medoid{::Ids);diameter;(nearest+1);real nearest_separation
)
selection_part =: 3 : 0
    lines =. <'selected linkage | k | ari | silhouette |'format (0{::Chosen);Kappa;(ari_text 6{::SelectedCut);real 2{::SelectedCut
    for_group. i.Kappa do. lines =. lines,cluster_lines group end.
    lines
)
centroid_part =: 3 : 0
    centers =. centroids Selected
    lines =. <'centroid_distances'
    for_g. i.Kappa do.
        values =. 0$0.0
        for_h. i.Kappa do. values =. values,%:(g{centers)squared_distance h{centers end.
        lines =. lines,<(number g+1),' ',reals values
    end.
    lines
)
profile_part =: 3 : 0
    width =. >./#&>FeatureNames
    lines =. <'profile_bars'
    for_g. i.Kappa do.
        group =. g{::Members
        lines =. lines,<'cluster ',number g+1
        for_f. i.FeatureCount do.
            zeta =. 0.0
            for_i. group do. zeta =. zeta+(((<i,f){Raw)-f{Means)%f{Deviations end.
            zeta =. zeta%#group
            length =. 10<.<.4*|zeta
            left =. right =. 10$' '
            if. zeta<0 do. left =. ((10-length)$' '),length$'#'
            else. right =. (length$'#'),(10-length)$' ' end.
            name =. f{::FeatureNames
            lines =. lines,<name,((width-#name)$' '),' ',left,'|',right,' ',real zeta
        end.
    end.
    lines
)
contingency_part =: 3 : 0
    lines =. (<'contingency'),<'cluster ',(' 'join Classes),' total'
    for_g. i.Kappa do.
        row =. g{ClassTable
        lines =. lines,<(number g+1),' ',(integers row),' ',number +/row
    end.
    lines =. lines,<'total ',(integers +/ClassTable),' ',number Count
    matches =. match_count Selected
    lines,<'purity |/| |'format matches;Count;real matches%Count
)
misplaced_part =: 3 : 0
    lines =. <'misplaced'
    count =. 0
    for_i. i.Count do.
        majority =. ((i{Selected)-1){Majority
        if. (i{Targets)~:majority do.
            count =. count+1
            lines =. lines,<'| label | cluster | majority |'format (i{::Ids);(i{::Labels);(i{Selected);majority{::Classes
        end.
    end.
    lines,<'count ',number count
)
weakest_part =: 3 : 0
    ordered =. ListSize{./:Silhouettes,.i.Count
    lines =. <'weakest'
    for_i. ordered do. lines =. lines,<'| label | cluster | silhouette |'format (i{::Ids);(i{::Labels);(i{Selected);real i{Silhouettes end.
    lines
)
feature_part =: 3 : 0
    ratios =. 0$0.0
    for_f. i.FeatureCount do.
        values =. f{"1 Vectors
        overall =. (sequential_sum values)%Count
        means =. 0$0.0
        for_group. Members do. means =. means,(sequential_sum (>group){values)%#>group end.
        between =. within =. 0.0
        for_g. i.Kappa do.
            difference =. (g{means)-overall
            term =. (#g{::Members)*difference
            between =. between+term*difference
        end.
        for_i. i.Count do.
            difference =. (i{values)-((i{Selected)-1){means
            within =. within+difference*difference
        end.
        ratios =. ratios,(between%Kappa-1)%(within%Count-Kappa)
    end.
    ranking =. /:(-four_digit ratios),.i.FeatureCount
    lines =. <'features'
    for_rank. i.FeatureCount do.
        f =. rank{ranking
        lines =. lines,<'| | f_ratio |'format (rank+1);(f{::FeatureNames);real f{ratios
    end.
    lines
)
class_counts =: 4 : 0
    counts =. ClassCount$0
    for_i. y{::5{::x do.
        label =. i{Targets
        counts =. (1+label{counts)label}counts
    end.
    '/'join <"0 counts
)
top_merges_part =: 3 : 0
    tree =. 1{::Chosen
    members =. 5{::tree
    lines =. <'top_merges'
    for_step. ((Count-InconsistencyCount)-1)+i.InconsistencyCount do.
        merge =. step{::1{::tree
        a =. 0{::merge
        b =. 1{::merge
        lines =. lines,<'step | height | a | | | b | | |'format (step+1);(real 2{::merge);a;(#a{::members);(tree class_counts a);b;(#b{::members);tree class_counts b
    end.
    lines
)
drop_feature_part =: 3 : 0
    lines =. <'drop_feature'
    for_f. i.FeatureCount do.
        columns =. (i.FeatureCount)-.f
        reduced =. columns{"1 Vectors
        delta =. DistanceName distance_matrix reduced
        tree =. ((0{::Chosen)agglomerate delta)make_tree Count
        partition =. tree cut_into Kappa
        lines =. lines,<'| ari_selected | ari_labels |'format (f{::FeatureNames);(ari_text partition partition_ari Selected);ari_text label_ari partition
    end.
    lines
)
refinement_part =: 3 : 0
    centers =. centroids Selected
    previous =. Selected
    iterations =. RefineIterations
    for_iteration. 1+i.RefineIterations do.
        assignment =. 0$0
        for_vector. Vectors do.
            best =. 0
            best_value =. vector squared_distance 0{centers
            for_g. 1+i.Kappa-1 do.
                value =. vector squared_distance g{centers
                if. value<best_value do. best =. g
                    best_value =. value end.
            end.
            assignment =. assignment,best+1
        end.
        if. assignment-:previous do. iterations =. iteration
            break. end.
        groups =. cluster_members assignment
        for_g. i.Kappa do.
            group =. g{::groups
            if. #group do. centers =. (centroid group{Vectors)g}centers end.
        end.
        previous =. assignment
    end.
    sizes =. #&>cluster_members previous
    lines =. <'refinement max_iterations ',number RefineIterations
    lines =. lines,<'iterations | changed | wss | -> |'format iterations;(+/Selected~:previous);(real within_sum Selected);real within_sum previous
    lines =. lines,<'sizes | silhouette |'format (integers sizes);real previous mean_silhouette Distances
    lines,<'ari_selected | ari_labels |'format (ari_text previous partition_ari Selected);ari_text label_ari previous
)
jaccard_values =: 4 : 0
    table =. (Kappa,>./x)contingency_table (<y-1),<x-1
    column_sizes =. +/table
    values =. 0$0.0
    for_row. table do.
        size =. +/row
        best =. 0 1
        if. size>0 do.
            for_h. i.#row do.
                common =. h{row
                candidate =. common,((size+h{column_sizes)-common)
                if. candidate ari_greater best do. best =. candidate end.
            end.
        end.
        values =. values,ari_value best
    end.
    values
)
stability_part =: 3 : 0
    state =. Seed
    size =. (Count*Percent)div 100
    aris =. 0$0.0
    jaccards =. (0,Kappa)$0.0
    lines =. <'stability replicates | percent | seed |'format Replicates;Percent;Seed
    for_replicate. 1+i.Replicates do.
        sample =. i.Count
        for_t. i.size do.
            state =. 2147483647|48271*state
            j =. t+(Count-t)|state
            first =. t{sample
            second =. j{sample
            sample =. second t}sample
            sample =. first j}sample
        end.
        sample =. /:~size{.sample
        delta =. sample{"1 sample{Distances
        tree =. ((0{::Chosen)agglomerate delta)make_tree size
        partition =. tree cut_into Kappa
        restricted =. sample{Selected
        ari =. partition partition_ari restricted
        jaccard =. partition jaccard_values restricted
        aris =. aris,ari_value ari
        jaccards =. jaccards,jaccard
        lines =. lines,<'replicate | size | ari | jaccard |'format replicate;size;(ari_text ari);reals jaccard
    end.
    means =. 0$0.0
    for_g. i.Kappa do. means =. means,(sequential_sum g{"1 jaccards)%Replicates end.
    lines =. lines,<'mean_ari ',real (sequential_sum aris)%Replicates
    lines,<'mean_jaccard ',reals means
)
distance_map_part =: 3 : 0
    frame =. '+',(Count$'-'),'+'
    lines =. (<'distance_map ',0{::Chosen),<frame
    order =. 4{::1{::Chosen
    for_i. order do.
        row =. '|'
        for_j. order do. row =. row,(DistanceMax histogram_bin (<i,j){Distances){'@%#*+=-:. ' end.
        lines =. lines,<row,'|'
    end.
    lines,<frame
)
profiles_report =: 3 : 0
    lines =. selection_part''
    lines =. lines paragraph centroid_part''
    lines =. lines paragraph profile_part''
    lines =. lines paragraph contingency_part''
    lines =. lines paragraph misplaced_part''
    lines =. lines paragraph weakest_part''
    lines =. lines paragraph feature_part''
    lines =. lines paragraph top_merges_part''
    lines =. lines paragraph drop_feature_part''
    lines =. lines paragraph refinement_part''
    lines =. lines paragraph stability_part''
    lines paragraph distance_map_part''
)
main =: 3 : 0
    prepare_study''
    1!:5 ::0: <'output'
    'linkage.csv'write_lines linkage_table''
    'clusters.csv'write_lines clusters_table''
    'dendrogram.txt'write_lines dendrogram_report''
    'trees.txt'write_lines trees_report''
    'validation.txt'write_lines validation_report''
    'profiles.txt'write_lines profiles_report''
    i.0
)
main''
