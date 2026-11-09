fp_node =: 3 : '''item parent count children'' record y,(<0),<empty_table '''''
fp_tree =: 3 : 0
    'base minimum' =. y
    counts =. empty_table ''
    for_pairbox. base do.
        'items weight' =. >pairbox
        for_itembox. items do. counts =. (itembox,<weight) increment_key counts end.
    end.
    header =. 0$a:
    keys =. 0 2$a:
    for_row. counts do.
        'item count' =. row
        if. count>:minimum do.
            header =. header,<item
            keys =. keys,1 2$(<-count),<item
        end.
    end.
    header =. (/:keys){header
    nodes =. <fp_node (<''),<_1
    links =. empty_table ''
    for_itembox. header do. links =. (itembox,<0$0) put_key links end.
    for_pairbox. base do.
        'items weight' =. >pairbox
        current =. 0
        for_itembox. header#~header e.items do.
            item =. >itembox
            node =. current{::nodes
            children =. 'children' get_key node
            if. item has_key children do. child =. item get_key children
            else.
                child =. #nodes
                nodes =. nodes,<fp_node (<item),<current
                children =. (itembox,<child) put_key children
                node =. ((<'children'),<children) put_key node
                nodes =. (<node) current}nodes
                links =. (itembox,<(item get_key links),child) put_key links
            end.
            node =. ((<'count'),<weight+'count' get_key child{::nodes) put_key child{::nodes
            nodes =. (<node) child}nodes
            current =. child
        end.
    end.
    'header nodes links' record (<header),(<nodes),<links
)
conditional_base =: 4 : 0
    nodes =. 'nodes' get_key y
    base =. 0$a:
    for_index. x get_key 'links' get_key y do.
        node =. index{::nodes
        path =. 0$a:
        parent =. 'parent' get_key node
        while. parent>0 do.
            ancestor =. parent{::nodes
            path =. (<'item' get_key ancestor),path
            parent =. 'parent' get_key ancestor
        end.
        base =. base,<(<path),<'count' get_key node
    end.
    base
)
fp_growth =: 3 : 0
    'base minimum maximum' =. y
    tree =. fp_tree (<base),<minimum
    headercount =. #'header' get_key tree
    nodecount =. <:#'nodes' get_key tree
    conditionaltrees =. conditionalnodes =. 0
    supports =. empty_table ''
    stack =. <(<tree),<0$a:
    while. #stack do.
        'current suffix' =. >{:stack
        stack =. }:stack
        nodes =. 'nodes' get_key current
        for_itembox. |.'header' get_key current do.
            item =. >itembox
            itemset =. /:~suffix,itembox
            count =. 0
            for_index. item get_key 'links' get_key current do. count =. count+'count' get_key index{::nodes end.
            supports =. ((<itemset_text itemset),<count) put_key supports
            if. (#itemset)<maximum do.
                conditional =. fp_tree (<item conditional_base current),<minimum
                size =. <:#'nodes' get_key conditional
                if. size>0 do.
                    stack =. stack,<(<conditional),<itemset
                    conditionaltrees =. conditionaltrees+1
                    conditionalnodes =. conditionalnodes+size
                end.
            end.
        end.
    end.
    'header nodes conditional_trees conditional_nodes supports' record (<headercount),(<nodecount),(<conditionaltrees),(<conditionalnodes),<supports
)
