real_text =: 4 : 0
    text =. (0 j.x)":y
    positions =. I.text~:' '
    text =. (1+({:positions)-{.positions){.({.positions)}.text
    text =. '-' (I.text='_')}text
    if. text-:'-0.',x#'0' do. }.text else. text end.
)
ratio_text =: 4 : 0
    if. y=0 do. '0/0 -' return. end.
    (number x),'/',(number y),' ',4 real_text x%y
)
fraction_text =: 4 : 0
    'numerator denominator' =. x
    if. denominator=0 do. '- -' return. end.
    divisor =. (|numerator)+.denominator
    numerator =. numerator div divisor
    denominator =. denominator div divisor
    (number numerator),'/',(number denominator),' ',y real_text numerator%denominator
)
average =: 3 : 0
    total =. 0.0
    for_value. y do. total =. total+value end.
    total%#y
)
is_leaf =: 4 : '(0=#6{::y)+.(0{::y)e.1{::x'
preorder =: 3 : 0
    view =. y
    pending =. <0{::view
    result =. 0$a:
    while. #pending do.
        node =. >{:pending
        pending =. }:pending
        result =. result,<node
        if. -.view is_leaf node do. pending =. pending,(10{node),9{node end.
    end.
    result
)
leaves =: 3 : 0
    result =. 0$a:
    for_box. preorder y do. if. y is_leaf >box do. result =. result,box end. end.
    result
)
internal_nodes =: 3 : 0
    result =. 0$a:
    for_box. preorder y do. if. -.y is_leaf >box do. result =. result,box end. end.
    result
)
tree_depth =: 3 : '>./(1&{::)&>leaves y'
training_errors =: 3 : '+/(5&{::)&>leaves y'
direction =: 4 : 0
    node =. x
    split =. 6{::node
    value =. (<y,0{split){Data
    if. value~:_1 do. (split goes_left value),0 return. end.
    for_surrogate. 7{::node do.
        value =. (<y,0{surrogate){Data
        if. value~:_1 do. (((2{.surrogate)goes_left value)=2{surrogate),1 return. end.
    end.
    (8{::node),2
)
route =: 4 : 0
    node =. 0{::x
    path =. <node
    methods =. 0$0
    while. -.x is_leaf node do.
        'left method' =. node direction y
        if. left do. node =. 9{::node else. node =. 10{::node end.
        path =. path,<node
        methods =. methods,method
    end.
    (<path),<methods
)
leaf_of =: 4 : '>{:0{::x route y'
predict =: 4 : '4{::x leaf_of y'
correct_count =: 4 : 0
    result =. 0
    for_row. y do. result =. result+(x predict row)=row{Labels end.
    result
)
classification_lines =: 4 : 0
    'actual predicted' =. y
    matrix =. (ClassCount,ClassCount)$0
    for_index. i.#actual do.
        position =. (index{actual),index{predicted
        matrix =. (1+(<position){matrix) (<position)}matrix
    end.
    correct =. 0
    for_label. i.ClassCount do. correct =. correct+(<label,label){matrix end.
    lines =. <'confusion | correct |/| accuracy |' format (<x),(<correct),(<#actual),<(correct,#actual)fraction_text 4
    lines =. lines,<'actual\predicted ',' ' join ClassNames
    for_label. i.ClassCount do. lines =. lines,<text_line (label{ClassNames),<"0 label{matrix end.
    values =. 0$0.0
    for_label. i.ClassCount do.
        hits =. (<label,label){matrix
        predictedtotal =. +/label{"1 matrix
        support =. +/label{matrix
        if. (predictedtotal+support)>0 do. values =. values,(2*hits)%predictedtotal+support end.
        lines =. lines,<'class | precision | recall | f1 | support |' format (label{ClassNames),(<(hits,predictedtotal)fraction_text 4),(<(hits,support)fraction_text 4),(<((2*hits),predictedtotal+support)fraction_text 4),<support
    end.
    lines,<'macro_f1 ',4 real_text average values
)
