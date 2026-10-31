Variants =: ;:'ul ur dl dr'
mark_conflicts =: 3 : 0
    orders =. y
    positions =. crossing_positions orders
    marked =. (VertexCount,VertexCount)$0
    for_layer. i.(#orders)-1 do.
        above =. layer{::orders
        below =. (layer+1){::orders
        first_bound =. 0
        start =. 0
        for_last. i.#below do.
            vertex =. last{below
            inner =. 0
            if. vertex>:NodeCount do.
                inner =. NodeCount<:{.vertex{::UpperNeighbors
            end.
            if. (-.inner)*.last~:(#below)-1 do.
                continue.
            end.
            last_bound =. (#above)-1
            if. inner do.
                last_bound =. positions{~{.vertex{::UpperNeighbors
            end.
            for_following. (1+last-start){.start}.below do.
                for_previous. following{::UpperNeighbors do.
                    position =. previous{positions
                    if. (position<first_bound)+.position>last_bound do.
                        marked =. 1(<previous,following)}marked
                    end.
                end.
            end.
            start =. last+1
            first_bound =. last_bound
        end.
    end.
    marked
)
vertical_alignment =: 4 : 0
    variant =. x
    orders =. y
    rightward =. variant e.1 3
    downward =. variant>:2
    scan =. orders
    if. rightward do.
        scan =. |.&.>orders
    end.
    ranks =. crossing_positions scan
    roots =. i.VertexCount
    align =. roots
    layers =. i.#orders
    reference =. UpperNeighbors
    if. downward do.
        layers =. |.layers
        reference =. LowerNeighbors
    end.
    for_layer. }.layers do.
        boundary =. _1
        for_vertex. layer{::scan do.
            neighbors =. vertex{::reference
            neighbors =. (/:neighbors{ranks){neighbors
            count =. #neighbors
            if. count=0 do.
                continue.
            end.
            for_middle. (((count-1)intdiv 2),count intdiv 2) do.
                neighbor =. middle{neighbors
                pair =. neighbor,vertex
                if. downward do.
                    pair =. |.pair
                end.
                conflict =. (<pair){MarkedSegments
                if. ((vertex{align)=vertex)*.(-.conflict)*.boundary<neighbor{ranks do.
                    align =. vertex neighbor}align
                    roots =. (neighbor{roots)vertex}roots
                    align =. (vertex{roots)vertex}align
                    boundary =. neighbor{ranks
                end.
            end.
        end.
    end.
    (<roots),<scan
)
compact_blocks =: 3 : 0
    'roots scan variant' =. y
    blocks =. /:~~.roots
    count =. #blocks
    block_numbers =. blocks i.roots
    weights =. (count,count)$_1
    rightward =. variant e.1 3
    for_layer. scan do.
        layer =. >layer
        for_i. i.(#layer)-1 do.
            first =. i{layer
            second =. (i+1){layer
            a =. first
            b =. second
            if. rightward do.
                a =. second
                b =. first
            end.
            gap =. setting 'dummy_sep'
            if. (a<NodeCount)*.b<NodeCount do.
                gap =. setting 'node_sep'
            end.
            distance =. (RightExtent{~a)+(LeftExtent{~b)+1+gap
            origin =. first{block_numbers
            target =. second{block_numbers
            distance =. distance>.(<origin,target){weights
            weights =. distance(<origin,target)}weights
        end.
    end.
    pending =. +/weights>:0
    ready =. I.pending=0
    front =. 0
    ordered =. i.0
    first_coordinates =. count$0
    while. front<#ready do.
        block =. front{ready
        front =. front+1
        ordered =. ordered,block
        previous =. I.0<:block{"1 weights
        coordinate =. 0
        for_origin. previous do.
            coordinate =. coordinate>.(origin{first_coordinates)+(<origin,block){weights
        end.
        first_coordinates =. coordinate block}first_coordinates
        for_following. I.0<:block{weights do.
            pending =. ((following{pending)-1)following}pending
            if. 0=following{pending do.
                ready =. ready,following
            end.
        end.
    end.
    second_coordinates =. first_coordinates
    for_block. |.ordered do.
        following =. I.0<:block{weights
        if. #following do.
            values =. (following{second_coordinates)-following{block{weights
            coordinate =. (block{first_coordinates)>. <./values
            second_coordinates =. coordinate block}second_coordinates
        end.
    end.
    coordinates =. block_numbers{second_coordinates
    if. rightward do.
        coordinates =. -coordinates
    end.
    (<coordinates),<count
)
assign_coordinates =: 3 : 0
    orders =. y
    LeftExtent =: VertexCount$0
    RightExtent =: VertexCount$0
    if. (<setting 'direction')e.;:'TB BT' do.
        LeftExtent =: (VertexWidths-1)intdiv"0 2
        RightExtent =: VertexWidths-(1+LeftExtent)
    end.
    MarkedSegments =: mark_conflicts orders
    layouts =. (VertexCount,0)$0
    BlockCounts =: i.0
    lows =. i.0
    highs =. i.0
    VariantWidths =: i.0
    for_variant. i.4 do.
        'roots scan' =. variant vertical_alignment orders
        'coordinates count' =. compact_blocks(<roots),(<scan),<variant
        layouts =. layouts,.coordinates
        BlockCounts =: BlockCounts,count
        low =. <./coordinates-LeftExtent
        high =. >./coordinates+RightExtent
        lows =. lows,low
        highs =. highs,high
        VariantWidths =: VariantWidths,(high-low)+1
    end.
    SmallestVariant =: VariantWidths i.<./VariantWidths
    AlignedCoordinates =: (VertexCount,0)$0
    for_variant. i.4 do.
        if. variant e.1 3 do.
            shift =. (SmallestVariant{highs)-variant{highs
        else.
            shift =. (SmallestVariant{lows)-variant{lows
        end.
        coordinates =. shift+variant{"1 layouts
        AlignedCoordinates =: AlignedCoordinates,.coordinates
    end.
    XCoordinates =: i.0
    for_coordinates. AlignedCoordinates do.
        ordered =. /:~coordinates
        XCoordinates =: XCoordinates,((1{ordered)+2{ordered)intdiv 2
    end.
    XCoordinates =: XCoordinates-<./XCoordinates-LeftExtent
)
