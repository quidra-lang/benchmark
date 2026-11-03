load 'dataset.ijs'
load 'kdtree.ijs'
load 'quadtree.ijs'
load 'rtree.ijs'
load 'grid.ijs'
load 'report.ijs'
Names =: ;:'kdtree quadtree rtree str grid rtree_rect str_rect'
CommandNames =: ;:'RANGE RADIUS KNN WINDOWCOUNT CONTAINS NEAREST JOIN'
point_objects =: 3 : '0 1 2 1 2{"1 y'
minimum_distance =: 4 : 0
    query =. 2{.x
    difference =. (0 1{y)-query
    difference =. (0>.difference)>.query-2 3{y
    +/difference*difference
)
new_view_node =: 3 : 0
    'box depth mark source' =. y
    (<box),(<0 5$0x),(<i.0),(<0,depth,source,0,0,0),(<mark),<i.0
)
finish_counts =: 3 : 0
    nodes =. y
    for_index. |.i.#nodes do.
        record =. index{::nodes
        children =. 2{::record
        count =. #1{::record
        for_child. children do.
            count =. count+0{3{::child{::nodes
        end.
        meta =. count 0}3{::record
        nodes =. (<(<meta)3}record)index}nodes
    end.
    nodes
)
preorder =: 3 : 0
    result =. i.0
    pending =. ,0
    while. #pending do.
        index =. {:pending
        pending =. }:pending
        result =. result,index
        pending =. pending,|.2{::index{::y
    end.
    result
)
kd_view =: 3 : 0
    nodes =. ,<new_view_node (<0,0,(World-1),World-1),(<0), (<'root'),<KDRoot
    pending =. ,0
    while. #pending do.
        index =. {:pending
        pending =. }:pending
        record =. index{::nodes
        meta =. 3{::record
        original =. (2{meta){KDNodes
        axis =. 3{original
        meta =. axis 3}meta
        record =. (<meta)3}record
        record =. (<point_objects ,:3{.original)1}record
        children =. i.0
        split =. (axis+1){original
        for_side. i.2 do.
            source =. (side+4){original
            if. source>:0 do.
                box =. 0{::record
                column =. axis+2*side=0
                box =. split column}box
                child =. #nodes
                mark =. side{::;:'L R'
                child_record =. new_view_node (<box),(<1+1{meta),(<mark),<source
                nodes =. nodes,<child_record
                children =. children,child
            end.
        end.
        record =. (<children)2}record
        nodes =. (<record)index}nodes
        pending =. pending,|.children
    end.
    finish_counts nodes
)
quad_view =: 3 : 0
    nodes =. ,<new_view_node (<0,0,(World-1),World-1),(<0),(<'root'),<0
    pending =. ,0
    while. #pending do.
        index =. {:pending
        pending =. }:pending
        record =. index{::nodes
        meta =. 3{::record
        'square points children' =. (2{meta){::QuadNodes
        record =. (<square)5}record
        successors =. i.0
        if. 0=#children do.
            record =. (<point_objects points)1}record
        else.
            for_side. i.4 do.
                source =. side{children
                'origin_x origin_y size' =. 0{::source{::QuadNodes
                box =. origin_x,origin_y,(origin_x+size-1),origin_y+size-1
                mark =. side{::;:'NW NE SW SE'
                successors =. successors,#nodes
                nodes =. nodes,<new_view_node (<box),(<1+1{meta),(<mark),<source
            end.
        end.
        record =. (<successors)2}record
        nodes =. (<record)index}nodes
        pending =. pending,|.successors
    end.
    finish_counts nodes
)
rt_view =: 4 : 0
    objects =. y
    rt_load x
    root_box =. rt_node_box RTRoot
    nodes =. ,<new_view_node (<root_box),(<0),(<'root'),<RTRoot
    pending =. ,0
    while. #pending do.
        index =. {:pending
        pending =. }:pending
        record =. index{::nodes
        meta =. 3{::record
        'level entries parent' =. (2{meta){::RTNodes
        meta =. level 4}meta
        meta =. (#entries)5}meta
        record =. (<meta)3}record
        successors =. i.0
        if. level=0 do.
            positions =. (0{"1 objects)i.4{"1 entries
            record =. (<positions{objects)1}record
        else.
            for_entry. entries do.
                successors =. successors,#nodes
                child_record =. new_view_node (<4{.entry),(<1+1{meta),(<' '),<5{entry
                nodes =. nodes,<child_record
            end.
        end.
        record =. (<successors)2}record
        nodes =. (<record)index}nodes
        pending =. pending,|.successors
    end.
    finish_counts nodes
)
grid_view =: 3 : 0
    nodes =. ,<new_view_node (<0,0,(World-1),World-1),(<0),(<'root'),<_1
    children =. i.0
    for_index. i.#GridCells do.
        child_record =. new_view_node (<index{GridBounds),(<1),(<' '),<index
        child_record =. (<point_objects index{::GridCells)1}child_record
        children =. children,#nodes
        nodes =. nodes,<child_record
    end.
    root =. (<children)2}0{::nodes
    nodes =. (<root)0}nodes
    finish_counts nodes
)
all_views =: 3 : 0
    result =. (<kd_view ''),<quad_view ''
    result =. result,<PointTree rt_view Points
    result =. result,<BulkTree rt_view Points
    result =. result,<grid_view ''
    result =. result,<RectTree rt_view Rectangles
    result,<RectBulk rt_view Rectangles
)
object_condition =: 4 : 0
    'values object' =. y
    box =. 1}.object
    if. x=1 do.
        (values minimum_distance box)<:*:2{values
    elseif. x=4 do.
        box box_contains 0 1 0 1{values
    else.
        values box_contains box
    end.
)
region_condition =: 4 : 0
    'values box' =. y
    if. x=1 do.
        (values minimum_distance box)<:*:2{values
    elseif. x=4 do.
        box box_contains 0 1 0 1{values
    else.
        box box_intersects values
    end.
)
conditional_search =: 4 : 0
    command =. x
    'nodes values' =. y
    pending =. ,0
    ids =. i.0
    count =. 0
    visits =. 0
    tests =. 0
    while. #pending do.
        index =. {:pending
        pending =. }:pending
        'box objects children meta mark square' =. index{::nodes
        visits =. visits+1
        if. (command=3)*.values box_contains box do.
            count =. count+0{meta
        else.
            tests =. tests+#objects
            for_object. objects do.
                if. command object_condition (<values),<object do.
                    ids =. ids,0{object
                    count =. count+1
                end.
            end.
            for_child. |.children do.
                child_box =. 0{::child{::nodes
                if. command region_condition (<values),<child_box do.
                    pending =. pending,child
                end.
            end.
        end.
    end.
    (</:~ids),(<0 2$0x),(<count),(<visits),<tests
)
heap_push =: 3 : 0
    Heap =: Heap,y
    index =. <:#Heap
    while. index>0 do.
        parent =. (index-1)intdiv 2
        if. -. (3{.y)lex_less 3{.parent{Heap do.
            break.
        end.
        Heap =: (parent{Heap)index}Heap
        index =. parent
    end.
    Heap =: y index}Heap
    i.0
)
heap_pop =: 3 : 0
    result =. {.Heap
    last =. {:Heap
    Heap =: }:Heap
    if. 0=#Heap do.
        result return.
    end.
    index =. 0
    while. (1+2*index)<#Heap do.
        child =. 1+2*index
        if. (child+1)<#Heap do.
            if. (3{.(child+1){Heap)lex_less 3{.child{Heap do.
                child =. child+1
            end.
        end.
        if. -. (3{.child{Heap)lex_less 3{.last do.
            break.
        end.
        Heap =: (child{Heap)index}Heap
        index =. child
    end.
    Heap =: last index}Heap
    result
)
nearest_search =: 3 : 0
    'nodes values' =. y
    Heap =: 0 5$0x
    answer =. 0 2$0x
    serial =. 1
    visits =. 0
    tests =. 0
    heap_push (values minimum_distance 0{::0{::nodes),0,0,0,_1
    while. #Heap do.
        item =. heap_pop ''
        if. 1=1{item do.
            answer =. answer,(4{item),0{item
            if. (#answer)=2{values do.
                break.
            end.
        else.
            record =. (3{item){::nodes
            objects =. 1{::record
            visits =. visits+1
            tests =. tests+#objects
            for_object. objects do.
                distance =. values minimum_distance 1}.object
                heap_push distance,1,(0{object),_1,0{object
            end.
            for_child. 2{::record do.
                distance =. values minimum_distance 0{::child{::nodes
                heap_push distance,0,serial,child,_1
                serial =. serial+1
            end.
        end.
    end.
    (<i.0),(<answer),(<#answer),(<visits),<tests
)
join_visit =: 3 : 0
    'a b' =. y
    left =. a{::JoinLeft
    right =. b{::JoinRight
    left_children =. 2{::left
    right_children =. 2{::right
    JoinNodes =: JoinNodes+1
    if. (0=#left_children)*.0=#right_children do.
        points =. 1{::left
        rectangles =. 1{::right
        JoinTests =: JoinTests+(#points)*#rectangles
        for_point. points do.
            for_rectangle. rectangles do.
                if. (1}.rectangle)box_contains 1}.point do.
                    JoinPairs =: JoinPairs,(0{rectangle),0{point
                end.
            end.
        end.
    elseif. 0=#left_children do.
        for_child. right_children do.
            if. (0{::left)box_intersects 0{::child{::JoinRight do.
                join_visit a,child
            end.
        end.
    elseif. 0=#right_children do.
        for_child. left_children do.
            if. (0{::child{::JoinLeft)box_intersects 0{::right do.
                join_visit child,b
            end.
        end.
    else.
        for_u. left_children do.
            for_v. right_children do.
                if. (0{::u{::JoinLeft)box_intersects 0{::v{::JoinRight do.
                    join_visit u,v
                end.
            end.
        end.
    end.
    i.0
)
join_search =: 4 : 0
    JoinLeft =: x
    JoinRight =: y
    JoinPairs =: 0 2$0x
    JoinNodes =: 0
    JoinTests =: 0
    join_visit 0 0
    (<i.0),(</:~JoinPairs),(<#JoinPairs),(<JoinNodes),<JoinTests
)
dump_tree =: 4 : 0
    name =. x
    lines =. 0$a:
    for_index. preorder y do.
        'box objects children meta mark square' =. index{::y
        select. name
        case. 'kdtree' do.
            axis =. (3{meta){::;:'x y'
            text =. mark,' ',axis,' ',(words 3{.{.objects),' box ',words box
        case. 'quadtree' do.
            text =. mark,' ',words square
            if. #children do.
                text =. text,' node count ',integer 0{meta
            else.
                text =. text,' leaf ',ids_text 0{"1 objects
            end.
        case. do.
            if. 0=4{meta do.
                text =. 'leaf ',(words box),' ids ',ids_text 0{"1 objects
            else.
                text =. 'node ',(integer 4{meta),' ',(words box),' entries ',integer 5{meta
            end.
        end.
        indent =. (2*1+1{meta)$' '
        lines =. lines,<indent,text
    end.
    lines
)
kd_statistics =: 3 : 0
    height =. 0
    leaves =. 0
    one_child =. 0
    depth_sum =. 0
    for_record. y do.
        record =. >record
        depth =. 1{3{::record
        children =. #2{::record
        height =. height>.depth+1
        leaves =. leaves+children=0
        one_child =. one_child+children=1
        depth_sum =. depth_sum+depth
    end.
    ideal =. 0
    capacity =. 0
    while. capacity<#y do.
        ideal =. ideal+1
        capacity =. 1+2*capacity
    end.
    lines =. <'kdtree height ',(integer height),' ideal ',(integer ideal),' nodes ',(integer #y),' leaves ',(integer leaves),' one_child ',(integer one_child),' depth_sum ',(integer depth_sum),' avg_depth ',depth_sum fraction #y
    for_depth. i.height do.
        counts =. 0 0 0
        for_record. y do.
            record =. >record
            if. depth=1{3{::record do.
                children =. #2{::record
                counts =. counts+1,(children=0),children=1
            end.
        end.
        lines =. lines,<'  depth ',(integer depth),' nodes ',(integer 0{counts),' leaves ',(integer 1{counts),' one_child ',integer 2{counts
    end.
    lines
)
quad_statistics =: 3 : 0
    height =. 0
    internal =. 0
    leaves =. 0
    empty =. 0
    largest =. 0
    for_record. y do.
        record =. >record
        height =. height>.1+1{3{::record
        if. #2{::record do.
            internal =. internal+1
        else.
            count =. #1{::record
            leaves =. leaves+1
            empty =. empty+count=0
            largest =. largest>.count
        end.
    end.
    total =. 0{3{::0{::y
    lines =. <'quadtree height ',(integer height),' internal ',(integer internal),' leaves ',(integer leaves),' empty ',(integer empty),' max_leaf ',(integer largest),' fill ',total fraction leaves*Bucket
    for_depth. i.height do.
        counts =. 0 0 0
        for_record. y do.
            record =. >record
            if. depth=1{3{::record do.
                if. #2{::record do.
                    counts =. counts+1 0 0
                else.
                    counts =. counts+0,1,#1{::record
                end.
            end.
        end.
        lines =. lines,<'  depth ',(integer depth),' internal ',(integer 0{counts),' leaves ',(integer 1{counts),' points ',integer 2{counts
    end.
    lines
)
rt_statistics =: 4 : 0
    name =. x
    height =. 1+4{3{::0{::y
    entries =. 0
    leaves =. 0
    for_record. y do.
        meta =. 3{::>record
        entries =. entries+5{meta
        leaves =. leaves+0=4{meta
    end.
    lines =. <name,' height ',(integer height),' nodes ',(integer #y),' leaves ',(integer leaves),' entries ',(integer entries),' fill ',entries fraction RTMax*#y
    for_level. |.i.height do.
        records =. 0$a:
        for_record. y do.
            if. level=4{3{::>record do.
                records =. records,record
            end.
        end.
        counts =. i.0
        for_record. records do.
            counts =. counts,5{3{::>record
        end.
        total_area =. 0
        overlap =. 0
        for_i. i.#records do.
            box =. 0{::i{::records
            total_area =. total_area+box_area box
            for_j. (i+1)+i.(#records)-i+1 do.
                overlap =. overlap+box box_overlap 0{::j{::records
            end.
        end.
        lines =. lines,<'  level ',(integer level),' nodes ',(integer #records),' entries ',(integer +/counts),' min ',(integer <./counts),' max ',(integer >./counts),' under ',(integer +/counts<RTMin),' area ',(integer total_area),' overlap ',integer overlap
    end.
    lines
)
grid_statistics =: 3 : 0
    counts =. #&>GridCells
    lines =. <'grid cells ',(integer #counts),' used ',(integer +/counts>0),' max ',integer >./counts
    fields =. 0$a:
    for_count. /:~~.counts do.
        fields =. fields,<(integer count),':',integer +/counts=count
    end.
    lines,<'  occupancy ',' 'join fields
)
snapshot =: 3 : 0
    roots =. all_views ''
    if. #Structures do.
        Structures =: Structures,<''
        Statistics =: Statistics,<''
    end.
    header =. 'snapshot ',(integer SnapshotCount),' query ',(integer y),' points ',(integer #Points),' rects ',integer #Rectangles
    Structures =: Structures,<header
    Statistics =: Statistics,<header
    for_structure. 0 1 2 3 5 6 do.
        name =. structure{::Names
        Structures =: Structures,(<name),name dump_tree structure{::roots
    end.
    Statistics =: Statistics,(kd_statistics 0{::roots),quad_statistics 1{::roots
    for_structure. 2 3 5 6 do.
        Statistics =: Statistics,(structure{::Names)rt_statistics structure{::roots
    end.
    Statistics =: Statistics,grid_statistics ''
    i.0
)
brute =: 4 : 0
    command =. x
    values =. y
    if. command=6 do.
        pairs =. 0 2$0x
        for_rectangle. Rectangles do.
            for_point. Points do.
                if. (1}.rectangle)box_contains 1}.point do.
                    pairs =. pairs,(0{rectangle),0{point
                end.
            end.
        end.
        (<i.0),(</:~pairs),<#pairs return.
    end.
    objects =. Points
    if. command e.4 5 do.
        objects =. Rectangles
    end.
    ids =. i.0
    pairs =. 0 2$0x
    for_object. objects do.
        if. command e.2 5 do.
            pairs =. pairs,(0{object),values minimum_distance 1}.object
        elseif. command object_condition (<values),<object do.
            ids =. ids,0{object
        end.
    end.
    if. command e.2 5 do.
        pairs =. pairs /: 1 0{"1 pairs
        pairs =. (2{values){.pairs
        (<i.0),(<pairs),<#pairs
    else.
        (</:~ids),(<0 2$0x),<#ids
    end.
)
record_visit =: 3 : 0
    'number command structure nodes tests' =. y
    Visits =: Visits,<(integer number),',',(command{::CommandNames),',',(structure{::Names),',',(integer nodes),',',integer tests
    total =. (<command,structure){Totals
    total =. total+1,nodes,tests,0
    total =. (nodes>.3{total)3}total
    Totals =: total (<command,structure)}Totals
    i.0
)
search =: 3 : 0
    'number command values' =. y
    roots =. all_views ''
    expected =. command brute values
    indices =. i.5
    if. command e.4 5 do.
        indices =. 5 6
    elseif. command=6 do.
        indices =. 2 3
    end.
    mismatches =. 0$a:
    for_structure. indices do.
        nodes =. structure{::roots
        if. command=6 do.
            actual =. nodes join_search (structure+3){::roots
        elseif. command e.2 5 do.
            actual =. nearest_search (<nodes),<values
        else.
            actual =. command conditional_search (<nodes),<values
        end.
        record_visit number,command,structure,(3{::actual),4{::actual
        field =. 0
        if. command=3 do.
            field =. 2
        elseif. command e.2 5 6 do.
            field =. 1
        end.
        if. -. (field{::actual)-:field{::expected do.
            mismatches =. mismatches,structure{Names
        end.
    end.
    check =. 'ok'
    if. #mismatches do.
        check =. 'mismatch ',' 'join mismatches
    end.
    line =. (integer number),' ',(command{::CommandNames),' count ',integer 2{::expected
    if. command e.2 5 do.
        line =. line,' ids ',distances_text 1{::expected
    elseif. -.command e.3 6 do.
        line =. line,' ids ',ids_text 0{::expected
    end.
    Answers =: Answers,<line,' check ',check
    if. command=6 do.
        for_pair. 1{::expected do.
            Joins =: Joins,<(integer number),',',(integer 0{pair),',',integer 1{pair
        end.
    end.
    i.0
)
locate =: 4 : 0
    number =. x
    id =. y
    position =. (0{"1 Points)i.id
    prefix =. (integer number),' LOCATE ',integer id
    if. position=#Points do.
        prefix,' missing' return.
    end.
    point =. 3{.position{Points
    current =. KDRoot
    kd_path =. ''
    while. id~:0{current{KDNodes do.
        node =. current{KDNodes
        if. (3{node)kd_less point,:3{.node do.
            kd_path =. kd_path,'L'
            current =. 4{node
        else.
            kd_path =. kd_path,'R'
            current =. 5{node
        end.
    end.
    if. 0=#kd_path do.
        kd_path =. '-'
    end.
    current =. 0
    quad_path =. 0$a:
    while. #2{::current{::QuadNodes do.
        child =. current quad_destination point
        quad_path =. quad_path,child{;:'NW NE SW SE'
        current =. child{2{::current{::QuadNodes
    end.
    quad_text =. '-'
    if. #quad_path do.
        quad_text =. '/'join quad_path
    end.
    prefix,' kdtree ',kd_path,' quadtree ',quad_text,' rtree ',(PointTree rt_position point),' str ',(BulkTree rt_position point),' grid ',words grid_position point
)
insert_point =: 3 : 0
    kd_insert y
    quad_insert y
    PointTree =: PointTree rt_insert y
    BulkTree =: BulkTree rt_insert y
    grid_insert y
    Points =: Points,point_objects ,:y
    i.0
)
delete_point =: 3 : 0
    position =. (0{"1 Points)i.y
    if. position=#Points do.
        0 return.
    end.
    point =. 3{.position{Points
    kd_delete point
    quad_delete point
    PointTree =: PointTree rt_delete point
    BulkTree =: BulkTree rt_delete point
    grid_delete point
    Points =: (position~:i.#Points)#Points
    1
)
process =: 4 : 0
    number =. x
    'name values' =. y
    select. name
    case. 'LOCATE' do.
        Answers =: Answers,<number locate {.values
    case. 'INSERT' do.
        insert_point values
        Answers =: Answers,<(integer number),' INSERT ',(integer {.values),' inserted points ',integer #Points
    case. 'DELETE' do.
        removed =. delete_point {.values
        status =. removed{::;:'missing deleted'
        Answers =: Answers,<(integer number),' DELETE ',(integer {.values),' ',status,' points ',integer #Points
    case. 'DUMP' do.
        SnapshotCount =: SnapshotCount+1
        snapshot number
        Answers =: Answers,<(integer number),' DUMP snapshot ',integer SnapshotCount
    case. do.
        command =. CommandNames i.<name
        search (<number),(<command),<values
    end.
    i.0
)
finish =: 3 : 0
    Statistics =: Statistics,(<''),<'visits'
    for_command. i.7 do.
        indices =. i.0
        keys =. 0 3$0x
        for_structure. i.7 do.
            total =. (<command,structure){Totals
            if. 0{total do.
                indices =. indices,structure
                keys =. keys,(1{total),(2{total),structure
                line =. (command{::CommandNames),' ',(structure{::Names),' queries ',(integer 0{total),' nodes ',(integer 1{total),' tests ',(integer 2{total),' max_nodes ',(integer 3{total),' mean_nodes ',(1{total)fraction 0{total
                Statistics =: Statistics,<line
            end.
        end.
        if. #indices do.
            ranked =. indices /: keys
            Statistics =: Statistics,<'rank ',(command{::CommandNames),' ',' 'join ranked{Names
        end.
    end.
    'answers.txt'write_lines Answers
    'visits.csv'write_lines Visits
    'join.csv'write_lines Joins
    'structures.txt'write_lines Structures
    'stats.txt'write_lines Statistics
    i.0
)
run =: 3 : 0
    'raw_points rectangles params commands' =. read_data ''
    'World Bucket RTMax RTMin CellSize' =: params
    Points =: point_objects raw_points
    Rectangles =: rectangles
    kd_build raw_points
    (World,Bucket)quad_build raw_points
    PointTree =: (RTMax,RTMin,0)rt_build Points
    BulkTree =: (RTMax,RTMin,1)rt_build Points
    RectTree =: (RTMax,RTMin,0)rt_build Rectangles
    RectBulk =: (RTMax,RTMin,1)rt_build Rectangles
    (World,CellSize)grid_build raw_points
    SnapshotCount =: 0
    Answers =: 0$a:
    Visits =: <'query,command,structure,nodes,tests'
    Joins =: <'query,rect,point'
    Structures =: 0$a:
    Statistics =: 0$a:
    Totals =: 7 7 4$0x
    snapshot 0
    for_index. i.#commands do.
        (index+1)process index{::commands
    end.
    finish ''
)
run ''
