load 'graph_io.ijs'
load 'acyclic_layering.ijs'
load 'crossing.ijs'
load 'coordinates.ijs'
load 'canvas.ijs'

intdiv =: 4 : '<.(x:x)%x:y'
integer =: 3 : 0
    text =. ,":y
    '-'(I.text='_')}text
)
parse_integer =: 3 : '".y'
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do.
            text =. text,x
        end.
        text =. text,i{::y
    end.
    text
)
split_words =: 3 : '<;._1 '' '',y'
numbers =: 3 : ''' ''join integer&.>y'
display_sequence =: 3 : ''' ''join y{VertexNames'
reachable_nodes =: 4 : 0
    found =. (#y)$0
    found =. 1 x}found
    queue =. ,x
    front =. 0
    while. front<#queue do.
        vertex =. front{queue
        front =. front+1
        for_neighbor. I.vertex{y do.
            if. -.neighbor{found do.
                found =. 1 neighbor}found
                queue =. queue,neighbor
            end.
        end.
    end.
    found
)
transitive_closure =: 3 : 0
    closure =. y+.(i.#y)=/i.#y
    for_middle. i.#y do.
        for_first. I.middle{"1 closure do.
            closure =. ((first{closure)+.middle{closure)first}closure
        end.
    end.
    closure
)
initialize_graph =: 3 : 0
    'name settings ids labels edges path self_loops duplicates error error_line' =. y
    GraphName =: name
    Settings =: settings
    order =. /:ids
    NodeIds =: order{ids
    NodeLabels =: order{labels
    NodeCount =: #ids
    EdgeSource =: NodeIds i.0{"1 edges
    EdgeTarget =: NodeIds i.1{"1 edges
    EdgeCount =: #edges
    PathIds =: path
    SelfLoops =: self_loops
    DuplicateEdges =: duplicates
    VertexNames =: integer&.>NodeIds
    VertexWidths =: 2+#&>NodeLabels
    RandomState =: setting 'seed'
)
analyze_graph =: 3 : 0
    adjacent =. (NodeCount,NodeCount)$0
    for_i. i.EdgeCount do.
        adjacent =. 1(<(i{EdgeSource),i{EdgeTarget)}adjacent
    end.
    outgoing =. +/"1 adjacent
    incoming =. +/adjacent
    Sources =: +/(incoming=0)*.outgoing>0
    Sinks =: +/(outgoing=0)*.incoming>0
    Isolated =: +/(incoming=0)*.outgoing=0
    undirected =. adjacent+.|:adjacent
    remaining =. NodeCount$1
    Components =: 0
    while. +./remaining do.
        component =. ({.I.remaining)reachable_nodes undirected
        remaining =. remaining*.-.component
        Components =: Components+1
    end.
    closure =. transitive_closure adjacent
    remaining =. NodeCount$1
    StrongComponents =: 0$a:
    while. +./remaining do.
        first =. {.I.remaining
        members =. I.remaining*.(first{closure)*.first{"1 closure
        remaining =. 0 members}remaining
        if. 1<#members do.
            StrongComponents =: StrongComponents,<members
        end.
    end.
)
prepare_dag =: 3 : 0
    edges =. EdgeSource,.EdgeTarget
    AcyclicOrder =: NodeCount acyclic_order edges
    positions =. NodeCount$0
    positions =. (i.NodeCount)AcyclicOrder}positions
    ReversedEdges =: (EdgeSource{positions)>EdgeTarget{positions
    EdgeUpper =: EdgeSource
    EdgeLower =: EdgeTarget
    selected =. I.ReversedEdges
    EdgeUpper =: (selected{EdgeTarget)selected}EdgeUpper
    EdgeLower =: (selected{EdgeSource)selected}EdgeLower
    TransitiveEdges =: EdgeCount$0
    if. 'on'-:setting 'reduce' do.
        adjacent =. (NodeCount,NodeCount)$0
        for_i. i.EdgeCount do.
            adjacent =. 1(<(i{EdgeUpper),i{EdgeLower)}adjacent
        end.
        closure =. transitive_closure adjacent
        for_i. I.-.ReversedEdges do.
            first =. i{EdgeUpper
            last =. i{EdgeLower
            for_following. (I.first{adjacent)-.last do.
                if. (<following,last){closure do.
                    TransitiveEdges =: 1 i}TransitiveEdges
                    break.
                end.
            end.
        end.
    end.
    DrawnEdges =: I.-.TransitiveEdges
)
assign_layers =: 3 : 0
    edges =. (DrawnEdges{EdgeUpper),.DrawnEdges{EdgeLower
    'heights labels before rounds promotions' =. NodeCount assign_heights edges
    CoffmanLabels =: labels
    DummiesBefore =: before
    PromotionRounds =: rounds
    Promotions =: promotions
    levels =. (>./heights)-heights
    used =. levels
    for_edge. edges do.
        'first second' =. edge
        low =. first{levels
        high =. second{levels
        used =. used,(low+1)+i.0>.high-(low+1)
    end.
    used =. /:~~.used
    VertexLayers =: used i.levels
    LayerCount =: #used
)
insert_dummies =: 3 : 0
    Chains =: EdgeCount$<i.0
    EdgeSpans =: EdgeCount$0
    for_edge. DrawnEdges do.
        first =. edge{EdgeUpper
        last =. edge{EdgeLower
        low =. first{VertexLayers
        high =. last{VertexLayers
        span =. high-low
        EdgeSpans =: span edge}EdgeSpans
        chain =. ,first
        for_layer. (low+1)+i.0>.high-(low+1) do.
            vertex =. #VertexLayers
            VertexLayers =: VertexLayers,layer
            VertexNames =: VertexNames,<'d',integer 1+vertex-NodeCount
            VertexWidths =: VertexWidths,1
            chain =. chain,vertex
        end.
        chain =. chain,last
        Chains =: (<chain)edge}Chains
    end.
    VertexCount =: #VertexLayers
    UpperNeighbors =: VertexCount$<i.0
    LowerNeighbors =: VertexCount$<i.0
    Gaps =: (LayerCount-1)$<0 3$0
    for_edge. DrawnEdges do.
        chain =. edge{::Chains
        for_i. i.(#chain)-1 do.
            first =. i{chain
            second =. (i+1){chain
            layer =. first{VertexLayers
            gap =. (layer{::Gaps),first,second,edge
            Gaps =: (<gap)layer}Gaps
            LowerNeighbors =: (<(first{::LowerNeighbors),second)first}LowerNeighbors
            UpperNeighbors =: (<(second{::UpperNeighbors),first)second}UpperNeighbors
        end.
    end.
)
initial_visit =: 3 : 0
    if. y{InitialVisited do.
        i.0 return.
    end.
    InitialVisited =: 1 y}InitialVisited
    layer =. y{VertexLayers
    InitialOrders =: (<(layer{::InitialOrders),y)layer}InitialOrders
    for_following. y{::LowerNeighbors do.
        initial_visit following
    end.
)
make_initial_order =: 3 : 0
    InitialOrders =: LayerCount$<i.0
    InitialVisited =: VertexCount$0
    for_vertex. i.NodeCount do.
        initial_visit vertex
    end.
    InitialCrossings =: total_crossings InitialOrders
)
next_random =: 3 : 0
    RandomState =: 2147483647|48271*RandomState
    RandomState
)
starting_order =: 3 : 0
    orders =. InitialOrders
    if. y>0 do.
        for_i. i.LayerCount do.
            vertices =. i{::orders
            for_last. |.1+i.(#vertices)-1 do.
                chosen =. (last+1)|next_random ''
                vertices =. ((chosen,last){vertices)(last,chosen)}vertices
            end.
            orders =. (<vertices)i}orders
        end.
    end.
    orders
)
reorder_layer =: 4 : 0
    'layer down' =. x
    orders =. y
    positions =. crossing_positions orders
    current =. layer{::orders
    reference =. LowerNeighbors
    if. down do.
        reference =. UpperNeighbors
    end.
    movable =. i.0
    keys =. (VertexCount,2)$0
    slots =. i.0
    for_i. i.#current do.
        vertex =. i{current
        neighbors =. vertex{::reference
        if. 0=#neighbors do.
            continue.
        end.
        values =. /:~neighbors{positions
        if. 'barycenter'-:setting 'heuristic' do.
            key =. (+/values),#values
        else.
            count =. #values
            a =. ((count-1)intdiv 2){values
            b =. (count intdiv 2){values
            key =. (a+b),1
        end.
        keys =. key vertex}keys
        movable =. movable,vertex
        slots =. slots,i
    end.
    sorted =. i.0
    for_vertex. movable do.
        'a b' =. vertex{keys
        position =. #sorted
        for_i. i.#sorted do.
            'c d' =. (i{sorted){keys
            if. (a*d)<c*b do.
                position =. i
                break.
            end.
        end.
        sorted =. (position{.sorted),vertex,position}.sorted
    end.
    current =. sorted slots}current
    (<current)layer}orders
)
exchange_adjacent =: 3 : 0
    orders =. y
    positions =. crossing_positions orders
    swaps =. 0
    while. 1 do.
        changed =. 0
        for_layer. i.LayerCount do.
            vertices =. layer{::orders
            for_i. i.(#vertices)-1 do.
                first =. i{vertices
                second =. (i+1){vertices
                before =. adjacent_cost(<first),(<second),<positions
                after =. adjacent_cost(<second),(<first),<positions
                if. before>after do.
                    vertices =. (second,first)(i,i+1)}vertices
                    positions =. (i+1)first}positions
                    positions =. i second}positions
                    swaps =. swaps+1
                    changed =. 1
                end.
            end.
            orders =. (<vertices)layer}orders
        end.
        if. -.changed do.
            break.
        end.
    end.
    (<orders),<swaps
)
perform_sweep =: 4 : 0
    sweep =. x
    orders =. y
    before =. crossing_positions orders
    down =. 2|sweep
    layers =. |.i.LayerCount-1
    if. down do.
        layers =. 1+i.LayerCount-1
    end.
    for_layer. layers do.
        orders =. (layer,down)reorder_layer orders
    end.
    after =. crossing_positions orders
    moved =. +/before~:after
    'orders swaps' =. exchange_adjacent orders
    (<orders),(<moved),(<swaps),<total_crossings orders
)
run_sweeps =: 3 : 0
    run =. y
    orders =. starting_order run
    count =. total_crossings orders
    SweepRecords =: SweepRecords,run,0,0,0,0,count
    history =. ,<orders
    best_order =. orders
    best_count =. count
    best_sweep =. 0
    sweep =. 1
    while. 1 do.
        if. (count=0)+.(sweep-1)=setting 'sweeps' do.
            break.
        end.
        if. (sweep-1)>:2 do.
            if. (_1{::history)-:_3{::history do.
                break.
            end.
        end.
        'orders moved swaps count' =. sweep perform_sweep orders
        direction =. 2-2|sweep
        SweepRecords =: SweepRecords,run,sweep,direction,moved,swaps,count
        history =. history,<orders
        if. count<best_count do.
            best_count =. count
            best_order =. orders
            best_sweep =. sweep
        end.
        sweep =. sweep+1
    end.
    if. (BestCrossings=_1)+.best_count<BestCrossings do.
        BestCrossings =: best_count
        BestRun =: run
        BestSweep =: best_sweep
        Orders =: best_order
    end.
)
sift_orders =: 3 : 0
    round =. 0
    while. 1 do.
        round =. round+1
        moves =. 0
        for_vertex. i.VertexCount do.
            layer =. vertex{VertexLayers
            vertices =. layer{::Orders
            original =. vertices i.vertex
            remaining =. vertices-.vertex
            costs =. i.0
            for_position. i.1+#remaining do.
                inserted =. (position{.remaining),vertex,position}.remaining
                Orders =: (<inserted)layer}Orders
                costs =. costs,layer local_crossings Orders
            end.
            minimum =. <./costs
            chosen =. costs i.minimum
            if. minimum=original{costs do.
                chosen =. original
            end.
            inserted =. (chosen{.remaining),vertex,chosen}.remaining
            Orders =: (<inserted)layer}Orders
            moves =. moves+chosen~:original
        end.
        SiftRecords =: SiftRecords,round,moves,total_crossings Orders
        if. moves=0 do.
            break.
        end.
    end.
)
reduce_crossings =: 3 : 0
    SweepRecords =: 0 6$0
    SiftRecords =: 0 3$0
    BestCrossings =: _1
    for_run. i.1+setting 'restarts' do.
        run_sweeps run
    end.
    if. 'on'-:setting 'sifting' do.
        sift_orders ''
    end.
)
finish_crossing_counts =: 3 : 0
    Positions =: crossing_positions Orders
    CrossingsByGap =: gap_crossings Orders
    FinalCrossings =: +/CrossingsByGap
    BruteCrossings =: 0
    EdgeCrossings =: EdgeCount$0
    for_segments. Gaps do.
        segments =. >segments
        BruteCrossings =: BruteCrossings+segments brute_crossings Positions
        for_i. i.#segments do.
            'p1 q1 first_edge' =. i{segments
            for_segment. (i+1)}.segments do.
                'p2 q2 second_edge' =. segment
                a =. (p1{Positions)-p2{Positions
                b =. (q1{Positions)-q2{Positions
                if. (a*b)<0 do.
                    EdgeCrossings =: (1+first_edge{EdgeCrossings)first_edge}EdgeCrossings
                    EdgeCrossings =: (1+second_edge{EdgeCrossings)second_edge}EdgeCrossings
                end.
            end.
        end.
    end.
)
assign_tracks =: 3 : 0
    segments =. y
    bent =. segments#~(XCoordinates{~0{"1 segments)~:XCoordinates{~1{"1 segments
    upper_counts =. VertexCount$0
    for_segment. bent do.
        first =. 0{segment
        upper_counts =. (1+first{upper_counts)first}upper_counts
    end.
    keys =. 0 2$0
    for_segment. bent do.
        'first second edge' =. segment
        if. 2<:first{upper_counts do.
            key =. 0,first
        else.
            key =. 1,second
        end.
        keys =. keys,key
    end.
    details =. 0 4$0
    buses =. 0$a:
    for_key. ~.keys do.
        selected =. I.key-:"1 keys
        members =. selected{bent
        values =. (,2{."1 members){XCoordinates
        low =. <./values
        high =. >./values
        'kind vertex' =. key
        details =. details,low,high,kind,vertex{XCoordinates
        buses =. buses,<members
    end.
    ends =. i.0
    assigned =. 0 3$0
    for_index. /:details do.
        'low high kind coordinate' =. index{details
        available =. I.(ends+1)<low
        chosen =. #ends
        if. #available do.
            chosen =. {.available
            ends =. high chosen}ends
        else.
            ends =. ends,high
        end.
        for_segment. index{::buses do.
            assigned =. assigned,(2{.segment),chosen+1
        end.
    end.
    total =. #ends
    gap =. (setting 'layer_gap')>.total+2
    shift =. (gap-(2+total))intdiv 2
    for_assignment. assigned do.
        'first second track' =. assignment
        SegmentOffsets =: (track+shift)(<first,second)}SegmentOffsets
    end.
    total,gap
)
route_geometry =: 3 : 0
    SegmentOffsets =: (VertexCount,VertexCount)$_1
    TrackCounts =: i.0
    GapWidths =: i.0
    for_segments. Gaps do.
        'tracks gap' =. assign_tracks >segments
        TrackCounts =: TrackCounts,tracks
        GapWidths =: GapWidths,gap
    end.
    vertical =. (<setting 'direction')e.;:'TB BT'
    BandThickness =: LayerCount$1
    if. -.vertical do.
        for_layer. i.LayerCount do.
            thickness =. >./(layer{::Orders){VertexWidths
            BandThickness =: thickness layer}BandThickness
        end.
    end.
    BandStarts =: ,0
    for_layer. i.LayerCount-1 do.
        next =. ({:BandStarts)+(layer{BandThickness)+layer{GapWidths
        BandStarts =: BandStarts,next
    end.
    MainLength =: ({:BandStarts)+{:BandThickness
    SecondaryLength =: 1+>./XCoordinates+RightExtent
    initialize_canvas(<setting 'direction'),(<MainLength),<SecondaryLength
    UpperEndpoints =: (EdgeCount,2)$0
    LowerEndpoints =: (EdgeCount,2)$0
    for_edge. DrawnEdges do.
        upper =. edge{EdgeUpper
        lower =. edge{EdgeLower
        size =. 1
        if. -.vertical do.
            size =. upper{VertexWidths
        end.
        a =. ((upper{VertexLayers){BandStarts)+size
        b =. ((lower{VertexLayers){BandStarts)-1
        UpperEndpoints =: (a,upper{XCoordinates)edge}UpperEndpoints
        LowerEndpoints =: (b,lower{XCoordinates)edge}LowerEndpoints
    end.
)
draw_lines_and_arrows =: 3 : 0
    for_vertex. i.VertexCount do.
        layer =. vertex{VertexLayers
        beginning =. layer{BandStarts
        end =. (beginning+layer{BandThickness)-1
        if. vertex>:NodeCount do.
            canvas_main_line beginning,end,vertex{XCoordinates
        elseif. (-.CanvasVertical)*.0<#vertex{::LowerNeighbors do.
            canvas_main_line (beginning+vertex{VertexWidths),end,vertex{XCoordinates
        end.
    end.
    for_layer. i.#Gaps do.
        beginning =. (layer{BandStarts)+layer{BandThickness
        gap =. layer{GapWidths
        for_segment. layer{::Gaps do.
            'first second edge' =. segment
            offset =. (<first,second){SegmentOffsets
            canvas_segment beginning,gap,(first{XCoordinates),(second{XCoordinates),offset
        end.
    end.
    for_edge. DrawnEdges do.
        point =. edge{LowerEndpoints
        if. edge{ReversedEdges do.
            point =. edge{UpperEndpoints
        end.
        (edge{ReversedEdges)canvas_arrow point
    end.
)
build_routes =: 3 : 0
    Routes =: EdgeCount$<0 2$0
    EdgeBends =: EdgeCount$0
    RouteLengths =: EdgeCount$0
    for_edge. DrawnEdges do.
        points =. ,:edge{UpperEndpoints
        bent =. 0
        chain =. edge{::Chains
        for_i. i.(#chain)-1 do.
            first =. i{chain
            second =. (i+1){chain
            if. (first{XCoordinates)=second{XCoordinates do.
                continue.
            end.
            layer =. first{VertexLayers
            main =. (layer{BandStarts)+(layer{BandThickness)+(<first,second){SegmentOffsets
            points =. points,main,first{XCoordinates
            points =. points,main,second{XCoordinates
            bent =. bent+1
        end.
        points =. points,edge{LowerEndpoints
        route =. canvas_cell"1 points
        if. edge{ReversedEdges do.
            route =. |.route
        end.
        length =. 1
        for_i. i.(#route)-1 do.
            length =. length++/|(i{route)-(i+1){route
        end.
        Routes =: (<route)edge}Routes
        EdgeBends =: (2*bent)edge}EdgeBends
        RouteLengths =: length edge}RouteLengths
    end.
)
find_path =: 3 : 0
    Path =: i.0
    if. 0=#PathIds do.
        i.0 return.
    end.
    'start end' =. NodeIds i.PathIds
    following =. (NodeCount,NodeCount)$0
    for_edge. DrawnEdges do.
        following =. 1(<(edge{EdgeSource),edge{EdgeTarget)}following
    end.
    parents =. NodeCount$_2
    parents =. _1 start}parents
    queue =. ,start
    front =. 0
    while. front<#queue do.
        vertex =. front{queue
        front =. front+1
        for_neighbor. I.vertex{following do.
            if. _2=neighbor{parents do.
                parents =. vertex neighbor}parents
                queue =. queue,neighbor
            end.
        end.
    end.
    if. _2~:end{parents do.
        reverse =. i.0
        vertex =. end
        while. vertex~:_1 do.
            reverse =. reverse,vertex
            vertex =. vertex{parents
        end.
        Path =: |.reverse
    end.
)
draw_highlights_and_boxes =: 3 : 0
    for_i. i.0>.(#Path)-1 do.
        first =. i{Path
        second =. (i+1){Path
        edges =. DrawnEdges#~(first=DrawnEdges{EdgeSource)*.second=DrawnEdges{EdgeTarget
        canvas_highlight ({.edges){::Routes
    end.
    for_vertex. i.NodeCount do.
        band =. (vertex{VertexLayers){BandStarts
        args =. (vertex{NodeLabels),(<band),(<vertex{XCoordinates),(<vertex{LeftExtent),<vertex e.Path
        canvas_box args
    end.
)
process_graph =: 3 : 0
    initialize_graph y
    analyze_graph ''
    prepare_dag ''
    assign_layers ''
    insert_dummies ''
    make_initial_order ''
    reduce_crossings ''
    finish_crossing_counts ''
    assign_coordinates Orders
    route_geometry ''
    draw_lines_and_arrows ''
    build_routes ''
    find_path ''
    draw_highlights_and_boxes ''
)
edge_name =: 3 : '(integer (y{EdgeSource){NodeIds),''->'',integer (y{EdgeTarget){NodeIds'
layer_line =: 3 : 0
    layer =. y
    vertices =. layer{::Orders
    first =. layer{BandStarts
    last =. (first+layer{BandThickness)-1
    if. (<setting 'direction')e.;:'BT RL' do.
        old_first =. first
        first =. MainLength-(1+last)
        last =. MainLength-(1+old_first)
    end.
    low =. <./vertices{XCoordinates-LeftExtent
    high =. >./vertices{XCoordinates+RightExtent
    items =. 0$a:
    for_vertex. vertices do.
        items =. items,<(vertex{::VertexNames),'@',integer vertex{XCoordinates
    end.
    line =. 'layer ',(integer layer),' band ',(integer first),' ',(integer last),' extent '
    line,(integer low),' ',(integer high),' : ',' 'join items
)
vertex_line =: 3 : 0
    vertex =. y
    line =. 'vertex ',(vertex{::VertexNames),' layer ',integer vertex{VertexLayers
    line =. line,' pos ',integer vertex{Positions
    for_variant. i.4 do.
        coordinate =. (<vertex,variant){AlignedCoordinates
        line =. line,' ',(variant{::Variants),' ',integer coordinate
    end.
    line,' x ',integer vertex{XCoordinates
)
edge_line =: 3 : 0
    edge =. y
    line =. 'edge ',(integer (edge{EdgeSource){NodeIds),' ',integer (edge{EdgeTarget){NodeIds
    if. edge{TransitiveEdges do.
        line,' transitive' return.
    end.
    chain =. edge{::Chains
    if. edge{ReversedEdges do.
        line =. line,' reversed'
        chain =. |.chain
    end.
    line =. line,' span ',(integer edge{EdgeSpans),' crossings ',integer edge{EdgeCrossings
    line =. line,' bends ',(integer edge{EdgeBends),' path ',numbers chain{XCoordinates
    route =. 0$a:
    for_point. edge{::Routes do.
        route =. route,<(integer 0{point),',',integer 1{point
    end.
    line,' route ',' 'join route
)
layout_lines =: 3 : 0
    lines =. <'graph ',GraphName
    items =. 0$a:
    for_i. i.#SettingNames do.
        value =. i{::Settings
        if. i e.IntegerSettings do.
            value =. integer value
        end.
        items =. items,<(i{::SettingNames),'=',value
    end.
    lines =. lines,<'settings ',' 'join items
    lines =. lines,<'acyclic ',display_sequence AcyclicOrder
    if. #CoffmanLabels do.
        items =. 0$a:
        for_vertex. i.NodeCount do.
            items =. items,<(vertex{::VertexNames),':',integer vertex{CoffmanLabels
        end.
        lines =. lines,<'labels ',' 'join items
    end.
    for_record. Promotions do.
        'round vertex difference' =. record
        lines =. lines,<'promote ',(integer round),' ',(vertex{::VertexNames),' ',integer difference
    end.
    directions =. ;:'initial down up'
    for_record. SweepRecords do.
        'run sweep direction moved swaps count' =. record
        line =. 'sweep ',(integer run),' ',(integer sweep),' ',direction{::directions
        if. sweep do.
            line =. line,' moved ',(integer moved),' swaps ',integer swaps
        end.
        lines =. lines,<line,' crossings ',integer count
    end.
    lines =. lines,<'best run ',(integer BestRun),' sweep ',(integer BestSweep),' crossings ',integer BestCrossings
    for_record. SiftRecords do.
        'round moves count' =. record
        lines =. lines,<'sift ',(integer round),' moves ',(integer moves),' crossings ',integer count
    end.
    for_layer. i.LayerCount do.
        lines =. lines,<layer_line layer
    end.
    for_gap. i.#Gaps do.
        line =. 'between ',(integer gap),' ',(integer gap+1),' segments ',integer #gap{::Gaps
        line =. line,' crossings ',(integer gap{CrossingsByGap),' tracks ',integer gap{TrackCounts
        lines =. lines,<line,' gap ',integer gap{GapWidths
    end.
    line =. 'bk conflicts ',integer +/,MarkedSegments
    for_variant. i.4 do.
        line =. line,' ',(variant{::Variants),'=',(integer variant{BlockCounts),'/',integer variant{VariantWidths
    end.
    lines =. lines,<line,' smallest ',SmallestVariant{::Variants
    for_layer. Orders do.
        for_vertex. >layer do.
            lines =. lines,<vertex_line vertex
        end.
    end.
    for_edge. i.EdgeCount do.
        lines =. lines,<edge_line edge
    end.
    lines,<'end'
)
edge_set_line =: 4 : 0
    line =. x,' ',integer #y
    for_edge. y do.
        line =. line,' ',edge_name edge
    end.
    line
)
statistics_lines =: 3 : 0
    lines =. <'graph ',GraphName
    line =. 'nodes ',(integer NodeCount),' edges ',(integer EdgeCount),' self_loops ',integer SelfLoops
    lines =. lines,<line,' duplicates ',integer DuplicateEdges
    line =. 'sources ',(integer Sources),' sinks ',(integer Sinks),' isolated ',integer Isolated
    lines =. lines,<line,' components ',integer Components
    for_component. StrongComponents do.
        lines =. lines,<'scc ',display_sequence >component
    end.
    lines =. lines,<'reversed'edge_set_line I.ReversedEdges
    lines =. lines,<'transitive'edge_set_line I.TransitiveEdges
    maximum_nodes =. 0
    for_layer. Orders do.
        maximum_nodes =. maximum_nodes>.+/(>layer)<NodeCount
    end.
    maximum_vertices =. >./#&>Orders
    line =. 'layers ',(integer LayerCount),' max_nodes ',integer maximum_nodes
    lines =. lines,<line,' max_vertices ',integer maximum_vertices
    if. 'on'-:setting 'promotion' do.
        line =. 'promotion rounds ',(integer PromotionRounds),' accepted ',integer #Promotions
        lines =. lines,<line,' dummies_before ',integer DummiesBefore
    else.
        lines =. lines,<'promotion off'
    end.
    spans =. DrawnEdges{EdgeSpans
    line =. 'dummies ',(integer VertexCount-NodeCount),' span_total ',integer +/spans
    lines =. lines,<line,' span_max ',integer >./0,spans
    if. #spans do.
        items =. 0$a:
        for_span. /:~~.spans do.
            items =. items,<(integer span),':',integer +/spans=span
        end.
        lines =. lines,<'spans ',' 'join items
    else.
        lines =. lines,<'spans none'
    end.
    long =. DrawnEdges#~2<:spans
    vertical =. 0
    for_edge. long do.
        dummy =. }:}.edge{::Chains
        vertical =. vertical+1=#~.dummy{XCoordinates
    end.
    lines =. lines,<'long_edges ',(integer #long),' vertical ',integer vertical
    line =. 'crossings initial ',(integer InitialCrossings),' swept ',integer BestCrossings
    line =. line,' best_run ',(integer BestRun),' best_sweep ',integer BestSweep
    lines =. lines,<line,' final ',(integer FinalCrossings),' brute ',integer BruteCrossings
    segments =. 0 3$0
    for_gap. Gaps do.
        segments =. segments,>gap
    end.
    straight =. 0
    offset =. 0
    for_segment. segments do.
        'first second edge' =. segment
        a =. first{XCoordinates
        b =. second{XCoordinates
        straight =. straight+a=b
        offset =. offset+|a-b
    end.
    line =. 'segments ',(integer #segments),' straight ',integer straight
    lines =. lines,<line,' bent ',(integer (#segments)-straight),' offset ',integer offset
    line =. 'routes length ',(integer +/DrawnEdges{RouteLengths),' bends ',integer +/DrawnEdges{EdgeBends
    if. #DrawnEdges do.
        lengths =. DrawnEdges{RouteLengths
        longest =. (lengths i.>./lengths){DrawnEdges
        line =. line,' longest ',(edge_name longest),' ',integer longest{RouteLengths
    end.
    lines =. lines,<line
    line =. 'canvas width ',(integer CanvasColumns),' height ',integer CanvasRows
    lines =. lines,<line,' crossing_cells ',integer canvas_crossings ''
    if. #PathIds do.
        line =. 'path ',numbers PathIds
        if. #Path do.
            line =. line,' hops ',(integer (#Path)-1),' : ',display_sequence Path
        else.
            line =. line,' none'
        end.
        lines =. lines,<line
    end.
    lines,<'end'
)
csv_lines =: 3 : 0
    lines =. 0$a:
    for_record. SweepRecords do.
        'run sweep direction moved swaps count' =. record
        lines =. lines,<GraphName,',',(integer run),',',(integer sweep),',',integer count
    end.
    lines
)
write_lines =: 4 : 0
    text =. ''
    if. #y do.
        text =. (LF join y),LF
    end.
    text 1!:2 <'output/',x
)
run =: 3 : 0
    read_defaults ''
    read_graphs ''
    layouts =. 0$a:
    statistics =. 0$a:
    crossings =. <'graph,run,sweep,crossings'
    drawings =. 0$a:
    totals =. 8$0
    for_graph. Graphs do.
        graph =. >graph
        totals =. (1+0{totals)0}totals
        name =. 0{::graph
        error =. 8{::graph
        if. #error do.
            lines =. (<'graph ',name),(<'error ',error,' line ',integer 9{::graph),<'end'
            layouts =. layouts,lines
            statistics =. statistics,lines
            drawings =. drawings,<,<'graph ',name,' error ',error
            totals =. (1+2{totals)2}totals
            continue.
        end.
        process_graph graph
        layouts =. layouts,layout_lines ''
        statistics =. statistics,statistics_lines ''
        crossings =. crossings,csv_lines ''
        header =. 'graph ',GraphName,' ',(integer CanvasColumns),'x',integer CanvasRows
        drawings =. drawings,<(<header),canvas_drawing ''
        additions =. 0,1,0,NodeCount,EdgeCount,(VertexCount-NodeCount),InitialCrossings,FinalCrossings
        totals =. totals+additions
    end.
    names =. ;:'graphs laid_out errors nodes edges dummies crossings_initial crossings_final'
    line =. 'summary'
    for_i. i.#names do.
        line =. line,' ',(i{::names),' ',integer i{totals
    end.
    statistics =. statistics,<line
    drawing_lines =. 0$a:
    for_i. i.#drawings do.
        if. i do.
            drawing_lines =. drawing_lines,<''
        end.
        drawing_lines =. drawing_lines,i{::drawings
    end.
    try.
        1!:5 <'output'
    catch.
    end.
    'layout.txt'write_lines layouts
    'stats.txt'write_lines statistics
    'crossings.csv'write_lines crossings
    'drawings.txt'write_lines drawing_lines
)
run ''
