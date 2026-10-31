integer =: 3 : 0
    text =. ,":y
    '-'(I.text='_')}text
)
parse_number =: 3 : '". ''_''(I.y=''-'')}y'
format_real =: 4 : 0
    text =. ,(0 j.x)":y
    if. (0=0".text)*.'_'={.text do.
        text =. }.text
    end.
    '-'(I.text='_')}text
)
fixed =: 3 : '4 format_real y'
six =: 3 : '6 format_real y'
ratio =: 4 : 0
    if. y>0 do. fixed x%y else. ,'-' end.
)
sgn =: 3 : '_1+2*0<y'
join =: 4 : 0
    result =. ''
    for_index. i.#y do.
        if. index do. result =. result,x end.
        result =. result,index{::y
    end.
    result
)
render_value =: 3 : 0
    if. 2=3!:0 y do. ,y else. integer y end.
)
emit =: 3 : ''' ''join render_value&.>y'
sum_ordered =: 3 : 0
    total =. 0.0
    for_value. y do. total =. total+value end.
    total
)
make_folds =: 4 : 0
    partitions =. 0$a:
    for_fold. i.y do.
        testing =. I.fold=y|i.x
        training =. I.fold~:y|i.x
        partitions =. partitions,<(<training),<testing
    end.
    partitions
)
correct_count =: 4 : '+/x=sgn y'
binary_counts =: 4 : 0
    prediction =. sgn y
    positive =. x=1
    tp =. +/positive*.prediction=1
    fp =. +/(-.positive)*.prediction=1
    tn =. +/(-.positive)*.prediction=_1
    fn =. +/positive*.prediction=_1
    tp,fp,tn,fn
)
auc =: 4 : 0
    positive =. I.x=1
    negative =. I.x=_1
    total =. 0.0
    for_a. positive do.
        for_b. negative do.
            if. (a{y)>b{y do. total =. total+1
            elseif. (a{y)=b{y do. total =. total+0.5 end.
        end.
    end.
    total%((#positive)*#negative)
)
confusion_matrix =: 4 : 0
    matrix =. 3 3$0
    for_index. i.#x do.
        cell =. <((index{x)-1),(index{y)-1
        matrix =. (1+cell{matrix)cell}matrix
    end.
    matrix
)
confusion_lines =: 3 : 0
    lines =. 0$a:
    for_row. y do. lines =. lines,<' 'join integer&.>row end.
    for_class. i.3 do.
        value =. (<class,class){y
        precision =. value ratio +/class{"1 y
        recall =. value ratio +/class{y
        lines =. lines,<emit 'class';(class+1);'precision';precision;'recall';recall
    end.
    lines
)
write_lines =: 4 : 0
    text =. ''
    for_line. y do. text =. text,(>line),LF end.
    text 1!:2 <'output/',x
    i.0 0
)
