ClassPairs =: 1 2;1 3;2 3
multiclass_train =: 4 : 0
    'kernel coefficient' =. x
    points =. 1{::y
    classes =. 2{::y
    matrix =. kernel kernel_matrix points
    rest =. pairs =. 0$a:
    for_class. 1+i.3 do.
        labels =. _1+2*classes=class
        rest =. rest,<smo_train (<points),(<labels),(<kernel),(<matrix),<coefficient
    end.
    for_pair. ClassPairs do.
        'first second' =. >pair
        indices =. I.classes e.first,second
        labels =. _1+2*(indices{classes)=first
        selected =. indices{points
        submatrix =. indices kernel_submatrix matrix
        pairs =. pairs,<smo_train (<selected),(<labels),(<kernel),(<submatrix),<coefficient
    end.
    (<kernel),(<coefficient),(<rest),<pairs
)
multiclass_classify =: 4 : 0
    rest =. 2{::x
    pairs =. 3{::x
    restvalues =. pairvalues =. i.0
    for_model. rest do. restvalues =. restvalues,(>model)smo_decision y end.
    chosen_rest =. restvalues i.>./restvalues
    votes =. 3$0
    scores =. 3$0.0
    for_i. i.3 do.
        'first second' =. i{::ClassPairs
        value =. (i{::pairs)smo_decision y
        pairvalues =. pairvalues,value
        if. value>0 do. winner =. first-1 else. winner =. second-1 end.
        votes =. (1+winner{votes)winner}votes
        scores =. (((first-1){scores)+value)(first-1)}scores
        scores =. (((second-1){scores)-value)(second-1)}scores
    end.
    candidates =. I.votes=>./votes
    chosen_pair =. {.candidates
    for_candidate. }.candidates do.
        if. (candidate{scores)>chosen_pair{scores do. chosen_pair =. candidate end.
    end.
    (<restvalues),(<pairvalues),(<votes),(<chosen_rest+1),(<chosen_pair+1),<1<#candidates
)
