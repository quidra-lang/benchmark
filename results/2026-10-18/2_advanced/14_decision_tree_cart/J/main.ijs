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
counts_text =: 3 : 'text_line <"0 y'
join_sections =: 3 : 0
    lines =. 0$a:
    for_section. y do.
        if. #lines do. lines =. lines,<'' end.
        lines =. lines,>section
    end.
    lines
)
load SourceDirectory,'dataset.ijs'
load SourceDirectory,'impurity.ijs'
load SourceDirectory,'tree_builder.ijs'
load SourceDirectory,'evaluation.ijs'
load SourceDirectory,'pruning.ijs'
ModelNames =: 'grown';'pruned';'depth';'cost_complexity';'bagging'
next_random =: 3 : 0
    RandomState =: 2147483647|48271*RandomState
    RandomState
)
accuracy =: 4 : '(x correct_count y)ratio_text #y'
missing_count =: 3 : '+/_1=y{Data'
limited =: 4 : 0
    cuts =. 0$0
    for_box. internal_nodes x do.
        node =. >box
        if. y=1{::node do. cuts =. cuts,0{::node end.
    end.
    (0{x),<cuts
)
condition_text =: 3 : 0
    'attribute lower upper equal excluded' =. y
    name =. attribute{::AttributeNames
    if. attribute{IntegerAttributes do.
        if. (lower~:_1)*.upper~:_1 do. (half_text lower),' < ',name,' <= ',half_text upper return. end.
        if. lower~:_1 do. name,' > ',half_text lower return. end.
        name,' <= ',half_text upper return.
    end.
    values =. attribute{::ValueNames
    if. equal~:_1 do. name,' = ',equal{::values return. end.
    if. 1=#excluded do. name,' != ',({.excluded){::values return. end.
    name,' not in {',(',' join excluded{values),'}'
)
conditions_text =: 3 : 0
    if. 0=#y do. 'true' return. end.
    ' and ' join condition_text&.>y
)
holds =: 4 : 0
    'attribute lower upper equal excluded' =. x
    value =. (<y,attribute){Data
    if. value=_1 do. 0 return. end.
    if. attribute{IntegerAttributes do.
        ((lower=_1)+.(2*value)>lower)*.((upper=_1)+.(2*value)<:upper)
    elseif. equal~:_1 do. value=equal
    else. -.value e.excluded end.
)
simplify =: 3 : 0
    result =. 0$a:
    for_attribute. i.AttributeCount do.
        steps =. y#~attribute=0{"1 y
        if. 0=#steps do. continue. end.
        lower =. upper =. equal =. _1
        excluded =. 0$0
        for_step. steps do.
            'ignored point left' =. step
            if. attribute{IntegerAttributes do.
                if. left do.
                    if. upper=_1 do. upper =. point else. upper =. upper<.point end.
                else.
                    lower =. lower>.point
                end.
            elseif. left do. equal =. point
            else. excluded =. excluded,point end.
        end.
        result =. result,<(<attribute),(<lower),(<upper),(<equal),</:~~.excluded
    end.
    result
)
coverage =: 4 : 0
    conditions =. x
    'rows label' =. y
    covered =. hits =. 0
    for_row. rows do.
        accepted =. 1
        for_condition. conditions do.
            if. -. (>condition)holds row do. accepted =. 0 break. end.
        end.
        if. accepted do.
            covered =. covered+1
            hits =. hits+label=row{Labels
        end.
    end.
    hits,covered
)
laplace =: 4 : '(x coverage y)+1,ClassCount'
generalize =: 4 : 0
    current =. x
    removed =. 0$a:
    while. #current do.
        estimate =. current laplace y
        bestindex =. _1
        best =. 0 1
        for_index. i.#current do.
            trial =. ((index~:i.#current)#current)laplace y
            if. bestindex=_1 do. bestindex =. index
                best =. trial
            elseif. trial is_greater best do. bestindex =. index
                best =. trial end.
        end.
        if. estimate is_greater best do. break. end.
        attribute =. 0{::bestindex{::current
        removed =. removed,attribute{AttributeNames
        current =. (bestindex~:i.#current)#current
    end.
    (<current),<removed
)
collect_rules =: 4 : 0
    view =. x
    'node steps' =. y
    if. view is_leaf node do.
        conditions =. simplify steps
        'general removed' =. conditions generalize (<Validation),<4{::node
        rule =. (<1+#Rules),(<node),(<conditions),(<general),<removed
        Rules =: Rules,<rule
        i.0 return.
    end.
    split =. 6{::node
    view collect_rules (9{node),<steps,split,1
    view collect_rules (10{node),<steps,split,0
    i.0
)
analyze =: 3 : 0
    Grown =: (<grow Train),<0$0
    'Pruned Decisions' =: (0{::Grown)reduced_error_pruning Validation
    Rules =: 0$a:
    Pruned collect_rules (0{Pruned),<0 3$0
    size =. #Train
    Bounds =: ((i.Folds+1)*size)div Folds
    FoldRows =: FoldTrees =: 0$a:
    for_fold. i.Folds do.
        low =. fold{Bounds
        high =. (fold+1){Bounds
        rows =. (high-low){.low}.Train
        training =. (low{.Train),high}.Train
        FoldRows =: FoldRows,<rows
        FoldTrees =: FoldTrees,<(<grow training),<0$0
    end.
    DepthResults =: 0$a:
    scores =. 0$0
    for_depth. i.MaxDepth+1 do.
        correct =. 0
        for_fold. i.Folds do.
            tree =. (fold{::FoldTrees)limited depth
            correct =. correct+tree correct_count fold{::FoldRows
        end.
        DepthResults =: DepthResults,<(<depth),(<Grown limited depth),<correct
        scores =. scores,correct
    end.
    SelectedDepth =: (scores i.>./scores){::DepthResults
    Sequence =: cost_complexity_sequence 0{::Grown
    SelectedIndex =: 0
    best =. #Validation
    for_index. i.#Sequence do.
        tree =. 1{::index{::Sequence
        errors =. (#Validation)-tree correct_count Validation
        if. errors<:best do. SelectedIndex =: index
            best =. errors end.
    end.
    RandomState =: BagSeed
    Bags =: 0$a:
    OobVotes =: (size,ClassCount)$0
    for_bag. i.BagTrees do.
        indices =. 0$0
        for_draw. i.size do. indices =. indices,size|next_random '' end.
        tree =. (<grow indices{Train),<0$0
        sampled =. ~.indices
        oob =. (i.size)#~-. (i.size)e.sampled
        correct =. 0
        for_index. oob do.
            row =. index{Train
            prediction =. tree predict row
            position =. index,prediction
            OobVotes =: (1+(<position){OobVotes) (<position)}OobVotes
            correct =. correct+prediction=row{Labels
        end.
        Bags =: Bags,<(<tree),(<#sampled),(<#oob),<correct
    end.
    TestVotes =: ((#Test),ClassCount)$0
    for_bag. Bags do.
        tree =. 0{::>bag
        for_index. i.#Test do.
            prediction =. tree predict index{Test
            position =. index,prediction
            TestVotes =: (1+(<position){TestVotes) (<position)}TestVotes
        end.
    end.
    Models =: (<Grown),(<Pruned),(1{SelectedDepth),<1{::SelectedIndex{::Sequence
    Predictions =: 0$a:
    for_box. Models do.
        predicted =. 0$0
        for_row. Test do. predicted =. predicted,(>box)predict row end.
        Predictions =: Predictions,<predicted
    end.
    Predictions =: Predictions,<majority"1 TestVotes
    i.0
)
tree_node_lines =: 4 : 0
    view =. x
    'node condition' =. y
    'number depth counts size prediction errors' =. 6{.node
    prefix =. ((2*depth)#' '),'| | n | counts |' format (<number),(<condition),(<size),<counts_text counts
    if. view is_leaf node do. <prefix,' leaf ',prediction{::ClassNames return. end.
    lines =. <prefix
    split =. 6{::node
    lines =. lines,view tree_node_lines (9{node),<split split_text 1
    lines,view tree_node_lines (10{node),<split split_text 0
)
tree_lines =: 3 : 0
    view =. y
    lines =. view tree_node_lines (0{view),<'root'
    nodes =. preorder view
    terminal =. leaves view
    depth =. tree_depth view
    lines =. lines,(<''),<'nodes | leaves | depth | errors |' format (<#nodes),(<#terminal),(<depth),<(training_errors view)ratio_text #Train
    for_level. i.depth+1 do.
        nodecount =. leafcount =. rows =. errors =. 0
        for_box. nodes do.
            node =. >box
            if. level~:1{::node do. continue. end.
            nodecount =. nodecount+1
            if. view is_leaf node do.
                leafcount =. leafcount+1
                rows =. rows+3{::node
                errors =. errors+5{::node
            end.
        end.
        lines =. lines,<'level | nodes | leaves | rows | errors |' format (<level),(<nodecount),(<leafcount),(<rows),<errors
    end.
    lines
)
root_candidate_lines =: 3 : 0
    found =. 0$a:
    for_attribute. i.AttributeCount do.
        candidate =. (,attribute)best_split Train
        if. 0=#candidate do. continue. end.
        position =. 0
        while. position<#found do.
            if. (3{::candidate)is_greater 3{::position{::found do. break. end.
            position =. position+1
        end.
        found =. (position{.found),(<candidate),position}.found
    end.
    counts =. 2{::0{::Grown
    size =. #Train
    lines =. <'root candidates n | counts |' format (<size),<counts_text counts
    for_index. i.#found do.
        candidate =. index{::found
        'numerator denominator' =. 3{::candidate
        gain =. ((numerator%denominator)%size)-(square_sum counts)%size*size
        lines =. lines,<'| | left | right | gain |' format (<index+1),(<(0{::candidate)split_text 1),(<+/1{::candidate),(<+/2{::candidate),<6 real_text gain
    end.
    lines
)
surrogate_lines =: 3 : 0
    lines =. <'surrogates'
    for_box. internal_nodes Grown do.
        node =. >box
        parts =. 0$a:
        for_surrogate. 7{::node do.
            if. 2{surrogate do. direction =. 'left' else. direction =. 'right' end.
            parts =. parts,<'| | |/|' format (<(2{.surrogate)split_text 1),(<direction),(<3{surrogate),3{node
        end.
        listed =. 'none'
        if. #parts do. listed =. ' ; ' join parts end.
        if. 8{::node do. default =. 'left' else. default =. 'right' end.
        lines =. lines,<'node | split | default | surrogates |' format (0{node),(<(6{::node)split_text 1),(<default),<listed
    end.
    lines
)
pruned_tree_file =: 3 : 0
    lines =. <'reduced_error_pruning validation ',number #Validation
    for_decision. Decisions do.
        'number depth rows leaferror subtreeerror pruned' =. decision
        if. pruned do. verdict =. 'pruned' else. verdict =. 'kept' end.
        lines =. lines,<'node | depth | rows | leaf | subtree | |' format (<number),(<depth),(<rows),(<leaferror),(<subtreeerror),<verdict
    end.
    pruned =. +/5{"1 Decisions
    count =. #Decisions
    lines =. lines,<'examined | pruned | kept |' format (<count),(<pruned),<count-pruned
    lines,(<''),tree_lines Pruned
)
predictions_file =: 3 : 0
    lines =. <'id,predicted,actual,grown,leaf,path,missing'
    for_row. Test do.
        'path methods' =. Pruned route row
        leaf =. >{:path
        numbers =. 0$0
        for_box. path do. numbers =. numbers,0{::>box end.
        lines =. lines,<'|,|,|,|,|,|,|' format (row{RowIds),((4{::leaf){ClassNames),((row{Labels){ClassNames),((Grown predict row){ClassNames),(0{leaf),(<('-' join number&.><"0 numbers)),<+/methods~:0
    end.
    lines
)
rules_file =: 3 : 0
    ordinary =. <'rules ',number #Rules
    generalized =. <'generalized ',number #Rules
    for_box. Rules do.
        'number leaf conditions general removed' =. >box
        label =. 4{::leaf
        reached =. 0$0
        for_row. Test do.
            if. (0{::leaf)=0{::Pruned leaf_of row do. reached =. reached,row end.
        end.
        hits =. +/label=reached{Labels
        trainratio =. (>./2{::leaf)ratio_text 3{::leaf
        ordinary =. ordinary,<'rule | node | if | then | train | test |' format (<number),(0{leaf),(<conditions_text conditions),(label{ClassNames),(<trainratio),<hits ratio_text #reached
        'hits covered' =. general coverage (<Validation),<label
        'testhits testcovered' =. general coverage (<Test),<label
        removedtext =. 'none'
        if. #removed do. removedtext =. ',' join removed end.
        estimate =. ((hits+1),covered+ClassCount)fraction_text 4
        generalized =. generalized,<'general | if | then | removed | laplace | validation |/| test |/|' format (<number),(<conditions_text general),(label{ClassNames),(<removedtext),(<estimate),(<hits),(<covered),(<testhits),<testcovered
    end.
    wrong =. 0$0
    for_row. Test do. if. (Pruned predict row)~:row{Labels do. wrong =. wrong,row end. end.
    explanations =. <'misclassified ',number #wrong
    marks =. ''; ' [surrogate]'; ' [default]'
    for_row. wrong do.
        'path methods' =. Pruned route row
        leaf =. >{:path
        number =. 0
        for_rulebox. Rules do.
            rule =. >rulebox
            if. (0{::leaf)=0{::1{::rule do. number =. 0{::rule break. end.
        end.
        parts =. 0$a:
        for_index. i.#methods do.
            node =. index{::path
            child =. (index+1){::path
            left =. (0{::child)=0{::9{::node
            parts =. parts,<((6{::node)split_text left),(index{methods){::marks
        end.
        text =. 'root'
        if. #parts do. text =. '; ' join parts end.
        explanations =. explanations,<'| actual | predicted | rule | path |' format (row{RowIds),((row{Labels){ClassNames),((4{::leaf){ClassNames),(<number),<text
    end.
    join_sections (<ordinary),(<generalized),<explanations
)
data_lines =: 3 : 0
    lines =. <'data train | validation | test | attributes | classes | target |' format (<#Train),(<#Validation),(<#Test),(<AttributeCount),(<ClassCount),<Target
    train =. class_counts Train
    validation =. class_counts Validation
    test =. class_counts Test
    for_label. i.ClassCount do.
        lines =. lines,<'class | train | validation | test |' format (label{ClassNames),(<label{train),(<label{validation),<label{test
    end.
    vm =. +/,_1=Validation{Data
    tm =. +/,_1=Test{Data
    lines =. lines,<'missing validation | test |' format (<vm),<tm
    for_attribute. i.AttributeCount do.
        vm =. +/_1=attribute{"1 Validation{Data
        tm =. +/_1=attribute{"1 Test{Data
        lines =. lines,<'missing | validation | test |' format (attribute{AttributeNames),(<vm),<tm
    end.
    lines
)
summary_line =: 4 : 0
    '| nodes | leaves | depth | train | validation | test |' format (<x),(<#preorder y),(<#leaves y),(<tree_depth y),(<y accuracy Train),(<y accuracy Validation),<y accuracy Test
)
model_evaluation =: 3 : 0
    title =. (y{::ModelNames),' test'
    title classification_lines (<Test{Labels),y{Predictions
)
routing_lines =: 3 : 0
    internal =. internal_nodes Pruned
    numbers =. 0$0
    for_box. internal do. numbers =. numbers,0{::>box end.
    tallies =. ((#internal),3)$0
    for_row. Test do.
        'path methods' =. Pruned route row
        for_index. i.#methods do.
            node =. index{::path
            position =. (numbers i.0{::node),index{methods
            tallies =. (1+(<position){tallies) (<position)}tallies
        end.
    end.
    lines =. <'routing pruned test'
    for_index. i.#internal do.
        tally =. index{tallies
        lines =. lines,<'node | rows | primary | surrogate | default |' format (<index{numbers),(<+/tally),<"0 tally
    end.
    for_complete. 1 0 do.
        rows =. 0$0
        for_row. Test do.
            if. complete=(0=missing_count row) do. rows =. rows,row end.
        end.
        if. complete do. title =. 'complete' else. title =. 'incomplete' end.
        lines =. lines,<'| rows | correct |' format (<title),(<#rows),<Pruned accuracy rows
    end.
    lines
)
cross_validation_lines =: 3 : 0
    lines =. <'cross_validation folds ',number Folds
    total =. 0
    for_fold. i.Folds do.
        rows =. fold{::FoldRows
        tree =. fold{::FoldTrees
        correct =. tree correct_count rows
        total =. total+correct
        lines =. lines,<'fold | rows |-| leaves | correct |' format (<fold+1),(<1+fold{Bounds),(<(fold+1){Bounds),(<#leaves tree),<correct ratio_text #rows
    end.
    lines,<'cv accuracy ',total ratio_text #Train
)
depth_lines =: 3 : 0
    lines =. <'depth_selection'
    for_box. DepthResults do.
        'depth tree correct' =. >box
        lines =. lines,<'depth | leaves | cv | train | validation | test |' format (<depth),(<#leaves tree),(<correct ratio_text #Train),(<tree accuracy Train),(<tree accuracy Validation),<tree accuracy Test
    end.
    'depth tree correct' =. SelectedDepth
    lines,<'selected depth | leaves | test |' format (<depth),(<#leaves tree),<tree accuracy Test
)
cost_complexity_lines =: 3 : 0
    lines =. <'cost_complexity'
    for_index. i.#Sequence do.
        'alpha tree' =. index{::Sequence
        normalized =. (0{alpha),(1{alpha)*#Train
        errors =. (#Validation)-tree correct_count Validation
        lines =. lines,<'subtree | alpha | leaves | train_errors | validation_errors |' format (<index),(<normalized fraction_text 6),(<#leaves tree),(<training_errors tree),<errors
    end.
    selected =. 1{::SelectedIndex{::Sequence
    lines,<'selected subtree | leaves | test |' format (<SelectedIndex),(<#leaves selected),<selected accuracy Test
)
bagging_lines =: 3 : 0
    lines =. <'bagging trees | seed |' format (<BagTrees),<BagSeed
    for_index. i.#Bags do.
        'tree distinct oob correct' =. index{::Bags
        lines =. lines,<'bag | distinct | leaves | oob |' format (<index+1),(<distinct),(<#leaves tree),<correct ratio_text oob
    end.
    voted =. hits =. 0
    for_index. i.#Train do.
        votes =. index{OobVotes
        if. 0=+/votes do. continue. end.
        voted =. voted+1
        hits =. hits+(majority votes)=(index{Train){Labels
    end.
    lines =. lines,<'oob accuracy | unvoted |' format (<hits ratio_text voted),<(#Train)-voted
    lines,model_evaluation 4
)
mcnemar_lines =: 3 : 0
    lines =. <'mcnemar pruned test'
    pruned =. (1{::Predictions)=Test{Labels
    for_model. 0 2 3 4 do.
        other =. (model{::Predictions)=Test{Labels
        b =. +/pruned*.-.other
        c =. +/other*.-.pruned
        disagreements =. b+c
        u =. (0>. (|b-c)-1)^2
        if. disagreements=0 do. statistic =. '0/1 0.0000'
        else. statistic =. (u,disagreements)fraction_text 4 end.
        if. (1000*u)>3841*disagreements do. significant =. 'yes' else. significant =. 'no' end.
        lines =. lines,<'versus | b | c | statistic | significant |' format (model{ModelNames),(<b),(<c),(<statistic),<significant
    end.
    lines
)
auc_lines =: 3 : 0
    lines =. 0$a:
    for_model. 0 1 4 do.
        scores =. 0$a:
        for_index. i.#Test do.
            if. model=4 do.
                row =. (index{TestVotes),.(ClassCount#BagTrees)
            else.
                leaf =. (model{::Models)leaf_of index{Test
                row =. (2{::leaf),.ClassCount#3{::leaf
            end.
            scores =. scores,<row
        end.
        parts =. (<'auc'),model{ModelNames
        values =. 0$0.0
        for_label. i.ClassCount do.
            positives =. I.label=Test{Labels
            negatives =. I.label~:Test{Labels
            wins =. 0
            for_positive. positives do.
                first =. label{positive{::scores
                for_negative. negatives do.
                    second =. label{negative{::scores
                    if. first is_greater second do. wins =. wins+2
                    elseif. -.second is_greater first do. wins =. wins+1 end.
                end.
            end.
            denominator =. 2*(#positives)*#negatives
            parts =. parts,(label{ClassNames),<(wins,denominator)fraction_text 4
            if. denominator>0 do. values =. values,wins%denominator end.
        end.
        macro =. '-'
        if. #values do. macro =. 4 real_text average values end.
        lines =. lines,<text_line parts,(<'macro'),<macro
    end.
    lines
)
learning_curve_lines =: 3 : 0
    lines =. <'learning_curve'
    for_size. Curve do.
        grown =. (<grow size{.Train),<0$0
        result =. (0{::grown)reduced_error_pruning Validation
        pruned =. 0{::result
        lines =. lines,<'size | grown leaves | test | pruned leaves | test |' format (<size),(<#leaves grown),(<grown accuracy Test),(<#leaves pruned),<pruned accuracy Test
    end.
    lines
)
evaluation_file =: 3 : 0
    sections =. <data_lines ''
    sections =. sections,<('grown' summary_line Grown);('pruned' summary_line Pruned)
    sections =. sections,<model_evaluation 0
    sections =. sections,<model_evaluation 1
    sections =. sections,<routing_lines ''
    sections =. sections,<cross_validation_lines ''
    sections =. sections,<depth_lines ''
    sections =. sections,<cost_complexity_lines ''
    sections =. sections,<bagging_lines ''
    sections =. sections,<mcnemar_lines ''
    sections =. sections,<auc_lines ''
    sections =. sections,<learning_curve_lines ''
    join_sections sections
)
impurity_lines =: 4 : 0
    importance =. AttributeCount$0.0
    splits =. AttributeCount$0
    for_box. internal_nodes y do.
        node =. >box
        attribute =. 0{6{::node
        delta =. impurity_decrease (2{node),(2{9{::node),2{10{::node
        importance =. ((attribute{importance)+delta) attribute}importance
        splits =. (1+attribute{splits) attribute}splits
    end.
    total =. 0.0
    for_value. importance do. total =. total+value end.
    if. total=0 do. shares =. AttributeCount$0.0 else. shares =. importance%total end.
    rounded =. <.0.5+10000*shares
    order =. /:(-rounded),.i.AttributeCount
    lines =. <'impurity ',x
    for_rank. i.AttributeCount do.
        attribute =. rank{order
        lines =. lines,<'| | decrease | share | splits |' format (<rank+1),(attribute{AttributeNames),(<4 real_text (attribute{importance)%#Train),(<4 real_text attribute{shares),<attribute{splits
    end.
    lines
)
permutation_lines =: 3 : 0
    RandomState =: PermutationSeed
    base =. Pruned correct_count Test
    original =. Data
    results =. 0$a:
    drops =. 0$0
    for_attribute. i.AttributeCount do.
        counts =. 0$0
        for_repeat. i.PermutationRepeats do.
            values =. attribute{"1 Test{original
            for_position. |.1+i.(#Test)-1 do.
                other =. (position+1)|next_random ''
                first =. position{values
                second =. other{values
                values =. second position}values
                values =. first other}values
            end.
            Data =: original
            for_index. i.#Test do. Data =: (index{values) (<(index{Test),attribute)}Data end.
            counts =. counts,Pruned correct_count Test
        end.
        Data =: original
        drop =. (PermutationRepeats*base)-+/counts
        results =. results,<(<attribute),(<counts),<drop
        drops =. drops,drop
    end.
    order =. /:(-drops),.i.AttributeCount
    lines =. <'permutation pruned test repeats | seed | base |' format (<PermutationRepeats),(<PermutationSeed),<base ratio_text #Test
    for_rank. i.AttributeCount do.
        'attribute counts drop' =. (rank{order){::results
        lines =. lines,<'| | correct | drop |' format (<rank+1),(attribute{AttributeNames),(<counts_text counts),<(drop,PermutationRepeats*#Test)fraction_text 4
    end.
    lines
)
write_file =: 4 : 0
    ((LF join y),LF)1!:2 <'output/',x
    i.0
)
main =: 3 : 0
    load_dataset ''
    analyze ''
    if. -.fexist 'output' do. 1!:5 <'output' end.
    'tree.txt' write_file join_sections (<root_candidate_lines ''),(<tree_lines Grown),<surrogate_lines ''
    'pruned_tree.txt' write_file pruned_tree_file ''
    'predictions.csv' write_file predictions_file ''
    'rules.txt' write_file rules_file ''
    'evaluation.txt' write_file evaluation_file ''
    'importance.txt' write_file join_sections (<'grown' impurity_lines Grown),(<'pruned' impurity_lines Pruned),<permutation_lines ''
    i.0
)
main ''
