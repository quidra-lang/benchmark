pruning_decide =: 3 : 0
    node =. y
    number =. 0{::node
    rows =. number{::Reached
    leaferror =. +/(rows{Labels)~:4{::node
    if. 0=#6{::node do. leaferror return. end.
    left =. pruning_decide 9{::node
    right =. pruning_decide 10{::node
    subtreeerror =. left+right
    pruned =. leaferror<:subtreeerror
    PruningDecisions =: PruningDecisions,number,(1{::node),(#rows),leaferror,subtreeerror,pruned
    if. pruned do. PruningCut =: PruningCut,number end.
    if. pruned do. leaferror else. subtreeerror end.
)
reduced_error_pruning =: 4 : 0
    root =. x
    view =. (<root),<0$0
    Reached =: (2^MaxDepth+1)$<0$0
    for_row. y do.
        for_box. 0{::view route row do.
            number =. 0{::>box
            Reached =: (<(number{::Reached),row) number}Reached
        end.
    end.
    PruningCut =: 0$0
    PruningDecisions =: 0 6$0
    pruning_decide root
    (<(<root),<PruningCut),<PruningDecisions
)
cost_complexity_sequence =: 3 : 0
    root =. y
    view =. (<root),<0$0
    sequence =. <(<0 1),<view
    while. -.view is_leaf root do.
        alpha =. 0$0
        weakest =. 0$0
        for_box. internal_nodes view do.
            node =. >box
            descendants =. leaves (<node),1{view
            errors =. 0
            for_leaf. descendants do. errors =. errors+5{::>leaf end.
            strength =. ((5{::node)-errors),(<:#descendants)
            if. 0=#alpha do. alpha =. strength
                weakest =. ,0{::node
            elseif. alpha is_greater strength do. alpha =. strength
                weakest =. ,0{::node
            elseif. -.strength is_greater alpha do. weakest =. weakest,0{::node end.
        end.
        view =. (<root),<~.(1{::view),weakest
        sequence =. sequence,<(<alpha),<view
    end.
    sequence
)
