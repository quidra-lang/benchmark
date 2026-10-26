half_text =: 3 : '(number y div 2),''.'',number 5*2|y'
goes_left =: 4 : 0
    'attribute point' =. x
    if. attribute{IntegerAttributes do. (2*y)<:point else. y=point end.
)
split_text =: 4 : 0
    'attribute point' =. x
    name =. attribute{::AttributeNames
    if. attribute{IntegerAttributes do.
        if. y do. operator =. ' <= ' else. operator =. ' > ' end.
        name,operator,half_text point
    else.
        if. y do. operator =. ' = ' else. operator =. ' != ' end.
        name,operator,point{::attribute{::ValueNames
    end.
)
candidates =: 4 : 0
    attribute =. x
    'rows labels count' =. y
    values =. attribute{"1 rows{Data
    distinct =. /:~~.values
    result =. 0$a:
    if. (#distinct)<2 do. result return. end.
    total =. count tally_labels labels
    if. attribute{IntegerAttributes do. points =. (}:distinct)+}.distinct
    else. points =. distinct end.
    for_point. points do.
        split =. attribute,point
        left =. count tally_labels labels#~split goes_left values
        right =. total-left
        result =. result,<(<split),(<left),(<right),<left evaluation_value right
    end.
    result
)
best_split =: 4 : 0
    best =. 0$a:
    for_attribute. x do.
        for_box. attribute candidates (<y),(<y{Labels),<ClassCount do.
            candidate =. >box
            if. ((+/1{::candidate)<MinSamplesLeaf)+.(+/2{::candidate)<MinSamplesLeaf do. continue. end.
            if. 0=#best do. best =. candidate
            elseif. (3{::candidate)is_greater 3{::best do. best =. candidate end.
        end.
    end.
    best
)
find_surrogates =: 4 : 0
    split =. x
    rows =. y
    primary =. split goes_left (0{split){"1 rows{Data
    directions =. -.primary
    size =. #rows
    limit =. (>./(+/primary),+/directions)
    result =. 0 4$0
    for_attribute. i.AttributeCount do.
        if. attribute=0{split do. continue. end.
        best =. 0$0
        for_box. attribute candidates (<rows),(<directions),<2 do.
            candidate =. >box
            agreement =. (0{1{::candidate)+1{2{::candidate
            direction =. agreement>:size-agreement
            score =. agreement>.size-agreement
            if. 0=#best do. best =. (0{::candidate),direction,score
            elseif. score>3{best do. best =. (0{::candidate),direction,score end.
        end.
        if. #best do. if. (3{best)>limit do. result =. result,best end. end.
    end.
    order =. /:(-3{"1 result),.0{"1 result
    (MaxSurrogates<.#result){.order{result
)
grow_node =: 3 : 0
    'rows number depth' =. y
    counts =. class_counts rows
    size =. #rows
    node =. (<number),(<depth),(<counts),(<size),(<majority counts),(<error_count counts),(<0$0),(<0 4$0),(<1),(<0$a:),<0$a:
    if. ((>./counts)=size)+.(depth=MaxDepth)+.size<MinSamplesSplit do. node return. end.
    best =. (i.AttributeCount) best_split rows
    if. 0=#best do. node return. end.
    if. -.(3{::best)improves counts do. node return. end.
    split =. 0{::best
    mask =. split goes_left (0{split){"1 rows{Data
    leftrows =. mask#rows
    rightrows =. (-.mask)#rows
    node =. (<split) 6}node
    node =. (<split find_surrogates rows) 7}node
    node =. (<(#leftrows)>:#rightrows) 8}node
    left =. grow_node (<leftrows),(<2*number),<depth+1
    right =. grow_node (<rightrows),(<1+2*number),<depth+1
    node =. (<left) 9}node
    (<right) 10}node
)
grow =: 3 : 'grow_node (<y),(<1),<0'
