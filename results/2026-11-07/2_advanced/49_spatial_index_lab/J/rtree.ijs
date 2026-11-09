box_area =: 3 : '((2{y)-0{y)*(3{y)-1{y'
box_mbr =: 4 : '((0 1{x)<.0 1{y),(2 3{x)>.2 3{y'
box_enlargement =: 4 : '(box_area x box_mbr y)-box_area x'
box_contains =: 4 : '(*./(0 1{x)<:0 1{y)*.*./(2 3{y)<:2 3{x'
box_intersects =: 4 : '(*./(0 1{x)<:2 3{y)*.*./(0 1{y)<:2 3{x'
box_overlap =: 4 : 0
    sides =. ((2 3{x)<.2 3{y)-(0 1{x)>.0 1{y
    */0>.sides
)
lex_less =: 4 : 0
    different =. I.x~:y
    if. 0=#different do.
        0
    else.
        index =. {.different
        (index{x)<index{y
    end.
)
rt_load =: 3 : 0
    'RTNodes RTRoot RTMaximum RTMinimum' =: y
    i.0
)
rt_state =: 3 : '(<RTNodes),(<RTRoot),(<RTMaximum),<RTMinimum'
rt_node_box =: 3 : 0
    entries =. 1{::y{::RTNodes
    (<./0 1{"1 entries),>./2 3{"1 entries
)
rt_store =: 4 : 'RTNodes =: (<y)x}RTNodes'
rt_entries =: 4 : 0
    record =. x{::RTNodes
    x rt_store (<y)1}record
    if. 0{::record do.
        for_child. 5{"1 y do.
            child rt_store (<x)2}child{::RTNodes
        end.
    end.
    i.0
)
rt_new_node =: 3 : 0
    'level entries parent' =. y
    index =. #RTNodes
    RTNodes =: RTNodes,<(<level),(<entries),<parent
    if. level do.
        for_child. 5{"1 entries do.
            child rt_store (<index)2}child{::RTNodes
        end.
    end.
    index
)
rt_choose =: 4 : 0
    current =. RTRoot
    while. x<0{::current{::RTNodes do.
        entries =. 1{::current{::RTNodes
        selected =. 0
        best =. ((4{.0{entries)box_enlargement y),box_area 4{.0{entries
        for_i. }.i.#entries do.
            box =. 4{.i{entries
            key =. (box box_enlargement y),box_area box
            if. key lex_less best do.
                selected =. i
                best =. key
            end.
        end.
        current =. 5{selected{entries
    end.
    current
)
rt_split =: 3 : 0
    current =. y
    record =. current{::RTNodes
    entries =. 1{::record
    first_seed =. 0
    second_seed =. 1
    a =. 4{.0{entries
    b =. 4{.1{entries
    best =. (box_area a box_mbr b)-(box_area a)+box_area b
    for_i. i.<:#entries do.
        for_j. (i+1)+i.(#entries)-i+1 do.
            a =. 4{.i{entries
            b =. 4{.j{entries
            waste =. (box_area a box_mbr b)-(box_area a)+box_area b
            if. waste>best do.
                first_seed =. i
                second_seed =. j
                best =. waste
            end.
        end.
    end.
    first =. ,:first_seed{entries
    second =. ,:second_seed{entries
    rest =. entries#~-. (i.#entries)e.first_seed,second_seed
    box1 =. 4{.{.first
    box2 =. 4{.{.second
    while. #rest do.
        if. RTMinimum=(#first)+#rest do.
            first =. first,rest
            break.
        elseif. RTMinimum=(#second)+#rest do.
            second =. second,rest
            break.
        end.
        selected =. 0
        greatest =. _1
        selected_d1 =. 0
        selected_d2 =. 0
        for_i. i.#rest do.
            box =. 4{.i{rest
            d1 =. box1 box_enlargement box
            d2 =. box2 box_enlargement box
            difference =. |d1-d2
            if. difference>greatest do.
                selected =. i
                greatest =. difference
                selected_d1 =. d1
                selected_d2 =. d2
            end.
        end.
        entry =. selected{rest
        rest =. (selected~:i.#rest)#rest
        key1 =. selected_d1,(box_area box1),(#first),0
        key2 =. selected_d2,(box_area box2),(#second),1
        if. key1 lex_less key2 do.
            first =. first,entry
            box1 =. box1 box_mbr 4{.entry
        else.
            second =. second,entry
            box2 =. box2 box_mbr 4{.entry
        end.
    end.
    current rt_entries first
    rt_new_node (0{record),(<second),2{record
)
rt_insert_entry =: 4 : 0
    level =. x
    entry =. y
    current =. level rt_choose 4{.entry
    current rt_entries (1{::current{::RTNodes),entry
    while. 1 do.
        sibling =. _1
        if. RTMaximum<#1{::current{::RTNodes do.
            sibling =. rt_split current
        end.
        parent =. 2{::current{::RTNodes
        if. parent<0 do.
            if. sibling>:0 do.
                entries =. ((rt_node_box current),0,current),:(rt_node_box sibling),0,sibling
                RTRoot =: rt_new_node (<1+0{::current{::RTNodes),(<entries),<_1
            end.
            i.0 return.
        end.
        entries =. 1{::parent{::RTNodes
        position =. (5{"1 entries)i.current
        entries =. ((rt_node_box current),0,current)position}entries
        if. sibling>:0 do.
            entries =. entries,(rt_node_box sibling),0,sibling
        end.
        parent rt_entries entries
        current =. parent
    end.
)
rt_find =: 3 : 0
    'id box' =. y
    pending =. ,RTRoot
    while. #pending do.
        current =. {:pending
        pending =. }:pending
        'level entries parent' =. current{::RTNodes
        if. level=0 do.
            position =. (4{"1 entries)i.id
            if. position<#entries do.
                current,position return.
            end.
        else.
            for_entry. |.entries do.
                if. (4{.entry)box_contains box do.
                    pending =. pending,5{entry
                end.
            end.
        end.
    end.
    _1 _1
)
rt_insert =: 4 : 0
    rt_load x
    0 rt_insert_entry (1 2 1 2{y),(0{y),_1
    rt_state ''
)
rt_delete =: 4 : 0
    rt_load x
    'current position' =. rt_find (<0{y),<1 2 1 2{y
    entries =. 1{::current{::RTNodes
    current rt_entries (position~:i.#entries)#entries
    removed =. i.0
    while. current~:RTRoot do.
        parent =. 2{::current{::RTNodes
        entries =. 1{::parent{::RTNodes
        position =. (5{"1 entries)i.current
        if. RTMinimum>#1{::current{::RTNodes do.
            parent rt_entries (position~:i.#entries)#entries
            removed =. removed,current
            current rt_store (<_1)2}current{::RTNodes
        else.
            entries =. ((rt_node_box current),0,current)position}entries
            parent rt_entries entries
        end.
        current =. parent
    end.
    for_discarded. removed do.
        record =. discarded{::RTNodes
        level =. 0{::record
        for_entry. 1{::record do.
            level rt_insert_entry entry
        end.
    end.
    while. (0<0{::RTRoot{::RTNodes)*.1=#1{::RTRoot{::RTNodes do.
        RTRoot =: 5{0{1{::RTRoot{::RTNodes
        RTRoot rt_store (<_1)2}RTRoot{::RTNodes
    end.
    rt_state ''
)
rt_bulk =: 3 : 0
    entries =. y
    numbers =. 4{"1 entries
    level =. 0
    while. 1 do.
        count =. #entries
        pages =. <.(x:count+RTMaximum-1)%RTMaximum
        slabs =. 1
        while. (slabs*slabs)<pages do.
            slabs =. slabs+1
        end.
        centers =. (0 1{"1 entries)+2 3{"1 entries
        ordered =. /:centers,.numbers
        slab_size =. slabs*RTMaximum
        created =. i.0
        for_start. slab_size*i.<.(x:count+slab_size-1)%slab_size do.
            indices =. ((count<.start+slab_size)-start){.start}.ordered
            keys =. (1 0{"1 indices{centers),.indices{numbers
            indices =. indices /: keys
            for_offset. RTMaximum*i.<.(x:(#indices)+RTMaximum-1)%RTMaximum do.
                group =. ((#indices)<.offset+RTMaximum)-offset
                selected =. group{.offset}.indices
                created =. created,rt_new_node (<level),(<selected{entries),<_1
            end.
        end.
        if. 1=#created do.
            RTRoot =: {.created
            i.0 return.
        end.
        entries =. 0 6$0x
        for_child. created do.
            entries =. entries,(rt_node_box child),0,child
        end.
        numbers =. i.#created
        level =. level+1
    end.
)
rt_build =: 4 : 0
    'RTMaximum RTMinimum bulk' =: x
    RTNodes =: 0$a:
    RTRoot =: rt_new_node (<0),(<0 6$0x),<_1
    entries =. (1 2 3 4{"1 y),.(0{"1 y),.(#y)#_1
    if. bulk do.
        rt_bulk entries
    else.
        for_entry. entries do.
            0 rt_insert_entry entry
        end.
    end.
    rt_state ''
)
rt_position =: 4 : 0
    rt_load x
    'current position' =. rt_find (<0{y),<1 2 1 2{y
    path =. ,position+1
    while. (2{::current{::RTNodes)>:0 do.
        parent =. 2{::current{::RTNodes
        entries =. 1{::parent{::RTNodes
        position =. (5{"1 entries)i.current
        path =. (position+1),path
        current =. parent
    end.
    '/'join integer&.>path
)
