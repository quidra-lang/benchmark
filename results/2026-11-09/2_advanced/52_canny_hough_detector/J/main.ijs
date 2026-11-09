load 'pgm_io.ijs'
load 'filters.ijs'
load 'canny.ijs'
load 'hough.ijs'
load 'corners.ijs'
PolygonKinds =: ;:'equilateral_triangle right_triangle triangle square rectangle parallelogram trapezoid quadrilateral'
cross =: 4 : '((0{x)*1{y)-(1{x)*0{y'
dot =: 4 : '+/x*y'
chebyshev =: 4 : '>./|x-y'
angle_difference =: 4 : 0
    gap =. |x-y
    gap<.180-gap
)
nearest =: 4 : 0
    numerator =. x
    denominator =. y
    if. denominator<0 do.
        numerator =. -numerator
        denominator =. -denominator
    end.
    ((2*numerator)+denominator)intdiv 2*denominator
)
inside_image =: 3 : 0
    'column row' =. y
    (column>:0)*.(column<Width)*.(row>:0)*.row<Height
)
raster_points =: 3 : 0
    indices =. I.,y
    (Width|indices),.indices intdiv Width
)
bresenham =: 4 : 0
    'column row' =. x
    'last_column last_row' =. y
    dx =. |last_column-column
    dy =. -|last_row-row
    sx =. _1
    sy =. _1
    if. column<last_column do.
        sx =. 1
    end.
    if. row<last_row do.
        sy =. 1
    end.
    error =. dx+dy
    result =. 0 2$0x
    while. 1 do.
        result =. result,column,row
        if. (column=last_column)*.row=last_row do.
            break.
        end.
        doubled =. 2*error
        if. doubled>:dy do.
            error =. error+dy
            column =. column+sx
        end.
        if. doubled<:dx do.
            error =. error+dx
            row =. row+sy
        end.
    end.
    result
)
circle_before =: 4 : 0
    left =. (3{x)*4{y
    right =. (3{y)*4{x
    if. left~:right do.
        left>right
    elseif. (0{x)~:0{y do.
        (0{x)<0{y
    elseif. (2{x)~:2{y do.
        (2{x)<2{y
    else.
        (1{x)<1{y
    end.
)
sort_circle_peaks =: 3 : 0
    values =. y
    count =. #values
    span =. 1
    while. span<count do.
        merged =. 0 5$0x
        for_start. (2*span)*i.((count+(2*span)-1)intdiv 2*span) do.
            middle =. count<.start+span
            finish =. count<.start+2*span
            first =. start
            second =. middle
            while. (first<middle)+.second<finish do.
                take_first =. second>:finish
                if. (first<middle)*.second<finish do.
                    take_first =. -. (second{values)circle_before first{values
                end.
                if. take_first do.
                    merged =. merged,first{values
                    first =. first+1
                else.
                    merged =. merged,second{values
                    second =. second+1
                end.
            end.
        end.
        values =. merged
        span =. 2*span
    end.
    values
)
offset_before =: 4 : 0
    half_x =. -.((1{x)>0)+.((1{x)=0)*.(0{x)>0
    half_y =. -.((1{y)>0)+.((1{y)=0)*.(0{y)>0
    if. half_x~:half_y do.
        half_x<half_y
    else.
        turn =. x cross y
        if. turn do.
            turn>0
        else.
            if. (0{x)~:0{y do.
                (0{x)<0{y
            else.
                (1{x)<1{y
            end.
        end.
    end.
)
ordered_outline =: 3 : 0
    result =. 0 2$0x
    for_point. y do.
        place =. #result
        for_i. i.#result do.
            if. point offset_before i{result do.
                place =. i
                break.
            end.
        end.
        result =. ((place{.result),point),place}.result
    end.
    result
)
circle_gaps =: 3 : 0
    center =. 0{::y
    outline =. ordered_outline 4{::y
    hits =. i.0
    for_offset. outline do.
        point =. center+offset
        hit =. 0
        if. inside_image point do.
            hit =. (<(1{point),0{point){Edges
        end.
        hits =. hits,hit
    end.
    count =. #hits
    if. *./hits do.
        0 1 return.
    elseif. -. +./hits do.
        count,0 return.
    end.
    arcs =. 0
    for_i. i.count do.
        if. (i{hits)*.-. (count|i+count-1){hits do.
            arcs =. arcs+1
        end.
    end.
    gap =. 0
    run =. 0
    for_i. i.2*count do.
        if. (count|i){hits do.
            run =. 0
        else.
            run =. run+1
            gap =. gap>.run
        end.
    end.
    (gap<.count),arcs
)
circumference =: 4 : 0
    center =. 0{::x
    radius =. 1{::x
    delta =. y-center
    squared =. delta dot delta
    (squared>:*:radius-1)*.squared<:*:radius+1
)
near_edge =: 3 : 0
    for_dy. _1 0 1 do.
        for_dx. _1 0 1 do.
            point =. y+dx,dy
            if. inside_image point do.
                if. (<(1{point),0{point){Edges do.
                    1 return.
                end.
            end.
        end.
    end.
    0
)
prepare_components =: 3 : 0
    EdgePoints =: raster_points Edges
    groups =. edge_components Edges
    Components =: 0$a:
    for_pixels. groups do.
        pixels =. >pixels
        low =. <./pixels
        high =. >./pixels
        ends =. 0
        strength =. 0x
        counts =. 4$0
        for_point. pixels do.
            'column row' =. point
            adjacent =. 0
            for_next. (Width,Height)neighbor_points point do.
                adjacent =. adjacent+(<(1{next),0{next){Edges
            end.
            ends =. ends+adjacent=1
            strength =. strength+(<row,column){Magnitude
            angle =. (<row,column){Directions
            category =. angle intdiv 45
            counts =. (1+category{counts)category}counts
        end.
        direction =. 45*counts i.>./counts
        record =. (<pixels),(<low,high),(<ends),(<strength intdiv #pixels),(<direction),(<_1),<0
        Components =: Components,<record
    end.
    i.0
)
detect_circles =: 3 : 0
    'candidate_count peaks' =. CircleMinimumPercent circle_peaks circle_votes (<EdgePoints),(<Width),(<Height),(<CircleMinimumRadius),<CircleMaximumRadius
    CircleCandidateCount =: candidate_count
    CirclePeakCount =: #peaks
    peaks =. sort_circle_peaks peaks
    Circles =: 0$a:
    for_peak. (CircleMaximumCount<.#peaks){.peaks do.
        'radius column row votes point_count' =. peak
        outline =. circle_points radius
        circle =. (<column,row),(<radius),(<votes),(<point_count),<outline
        'gap arcs' =. circle_gaps circle
        circle =. circle,(<gap),<arcs
        Circles =: Circles,<circle
    end.
    CircleEdge =: (Height,Width)$0
    for_point. EdgePoints do.
        for_circle. Circles do.
            if. (>circle)circumference point do.
                CircleEdge =: 1 (<(1{point),0{point)}CircleEdge
                break.
            end.
        end.
    end.
    LineEdge =: raster_points Edges*.-.CircleEdge
    i.0
)
detect_lines =: 3 : 0
    RhoLow =: 0
    RhoHigh =: 0
    image_corners =. 4 2$0,0,(Width-1),0,0,(Height-1),(Width-1),Height-1
    for_angle. i.180 do.
        args =. (<angle),(<Trig),<RhoStep
        for_point. image_corners do.
            value =. args rho point
            RhoLow =: RhoLow<.value
            RhoHigh =: RhoHigh>.value
        end.
    end.
    LineVotes =: line_votes (<LineEdge),(<Trig),(<RhoStep),(<RhoLow),<RhoHigh
    MaximumVotes =: >./,LineVotes
    peaks =. line_peaks (<LineVotes),(<RhoLow),<HoughThreshold
    LinePeakCount =: #peaks
    keys =. (-2{"1 peaks),.(0{"1 peaks),.1{"1 peaks
    peaks =. peaks /: keys
    Lines =: 0$a:
    Segments =: 0$a:
    Claimed =: (Height,Width)$0
    for_peak. peaks do.
        if. (#Lines)>:MaximumLines do.
            break.
        end.
        'angle radial votes' =. peak
        'cosine sine' =. angle{Trig
        available =. 0 3$0x
        args =. (<angle),(<Trig),<RhoStep
        for_point. LineEdge do.
            if. (<(1{point),0{point){Claimed do.
                continue.
            end.
            if. (|(args rho point)-radial)<:SegmentTolerance do.
                u =. ((1{point)*cosine)-(0{point)*sine
                available =. available,point,u
            end.
        end.
        keys =. (2{"1 available),.(0{"1 available),.1{"1 available
        ordered =. available /: keys
        groups =. 0$a:
        current =. 0 2$0x
        for_i. i.#ordered do.
            if. i do.
                if. ((2{i{ordered)-2{(i-1){ordered)>SegmentMaximumGap*16384 do.
                    groups =. groups,<current
                    current =. 0 2$0x
                end.
            end.
            current =. current,2{.i{ordered
        end.
        if. #current do.
            groups =. groups,<current
        end.
        pending =. 0$a:
        for_group. groups do.
            group =. >group
            first =. {.group
            last =. {:group
            length =. 1+first chebyshev last
            if. length>:SegmentMinimumLength do.
                pending =. pending,<(<first),(<last),(<angle),(<length),(<#group),<group
            end.
        end.
        if. 0=#pending do.
            continue.
        end.
        line =. #Lines
        identifiers =. i.0
        for_segment. pending do.
            segment =. (>segment),<line
            identifiers =. identifiers,#Segments
            Segments =: Segments,<segment
            for_point. 5{::segment do.
                Claimed =: 1 (<(1{point),0{point)}Claimed
            end.
        end.
        Lines =: Lines,<(<angle),(<radial),(<votes),<identifiers
    end.
    i.0
)
end_choice =: 4 : 0
    first =. (0{::x)chebyshev y
    last =. (1{::x)chebyshev y
    if. first<:last do.
        0,first
    else.
        1,last
    end.
)
end_for =: 4 : 0
    if. y=0{::x do.
        3{::x
    else.
        4{::x
    end.
)
joined =: 4 : 0
    first =. x<.y
    second =. x>.y
    target =. (first*SegmentCount)+second
    low =. 0
    high =. #JunctionKeys
    while. low<high do.
        middle =. (low+high)intdiv 2
        if. (middle{JunctionKeys)<target do.
            low =. middle+1
        else.
            high =. middle
        end.
    end.
    if. low<#JunctionKeys do.
        if. target=low{JunctionKeys do.
            low return.
        end.
    end.
    _1
)
make_junctions =: 3 : 0
    SegmentCount =: #Segments
    Junctions =: 0$a:
    JunctionKeys =: i.0
    Graph =: SegmentCount$<i.0
    for_first. i.0>.SegmentCount-1 do.
        for_second. (first+1)+i.SegmentCount-(first+1) do.
            a =. first{::Segments
            b =. second{::Segments
            if. ((2{::a)angle_difference 2{::b)<JunctionMinimumAngle do.
                continue.
            end.
            da =. (1{::a)-0{::a
            db =. (1{::b)-0{::b
            denominator =. da cross db
            if. denominator=0 do.
                continue.
            end.
            lambda =. ((0{::b)-0{::a)cross db
            point =. i.0x
            for_axis. i.2 do.
                numerator =. ((axis{0{::a)*denominator)+lambda*axis{da
                point =. point,numerator nearest denominator
            end.
            end_a =. a end_choice point
            end_b =. b end_choice point
            if. ((1{end_a)>JunctionDistance)+.(1{end_b)>JunctionDistance do.
                continue.
            end.
            record =. (<first),(<second),(<point),(<0{end_a),<0{end_b
            Junctions =: Junctions,<record
            JunctionKeys =: JunctionKeys,(first*SegmentCount)+second
            Graph =: (<(first{::Graph),second)first}Graph
            Graph =: (<(second{::Graph),first)second}Graph
        end.
    end.
    Graph =: /:~&.>Graph
    i.0
)
extend_polygon =: 3 : 0
    sequence =. y
    count =. PolygonTarget
    first =. {.sequence
    last =. {:sequence
    if. (#sequence)=count do.
        if. ((1{sequence)>:last)+.(last joined first)<0 do.
            i.0 return.
        end.
        vertices =. 0 2$0x
        for_i. i.count do.
            current =. i{sequence
            previous =. (count|i+count-1){sequence
            following =. (count|i+1){sequence
            entry =. (previous joined current){::Junctions
            exit =. (current joined following){::Junctions
            if. (entry end_for current)=exit end_for current do.
                i.0 return.
            end.
            vertices =. vertices,2{::entry
        end.
        positive =. 1
        negative =. 1
        for_i. i.count do.
            point =. i{vertices
            next =. (count|i+1){vertices
            after =. (count|i+2){vertices
            turn =. (next-point)cross after-next
            positive =. positive*.turn>0
            negative =. negative*.turn<0
        end.
        if. positive+.negative do.
            Polygons =: Polygons,<(<sequence),<vertices
        end.
        i.0 return.
    end.
    for_candidate. last{::Graph do.
        if. (candidate>first)*.-.candidate e.sequence do.
            extend_polygon sequence,candidate
        end.
    end.
    i.0
)
polygon_properties =: 3 : 0
    for_p. i.#Polygons do.
        'identifiers vertices' =. p{::Polygons
        count =. #identifiers
        theta =. i.0
        for_segment. identifiers do.
            theta =. theta,2{::segment{::Segments
        end.
        angles =. i.0
        lengths =. i.0x
        supports =. i.0
        sigma =. 0x
        all_sixty =. 1
        any_right =. 0
        all_right =. 1
        for_i. i.count do.
            previous =. (count|i+count-1){vertices
            point =. i{vertices
            following =. (count|i+1){vertices
            phi =. ((count|i+count-1){theta)angle_difference i{theta
            if. ((previous-point)dot following-point)<0 do.
                phi =. 180-phi
            end.
            angles =. angles,phi
            side =. following-point
            lengths =. lengths,side dot side
            raster =. point bresenham following
            support =. 0
            for_pixel. raster do.
                support =. support+near_edge pixel
            end.
            supports =. supports,(100*support)intdiv #raster
            sigma =. sigma+point cross following
            all_sixty =. all_sixty*.(|phi-60)<:AngleTolerance
            any_right =. any_right+.(|phi-90)<:AngleTolerance
            all_right =. all_right*.(|phi-90)<:AngleTolerance
        end.
        if. count=3 do.
            kind =. 'triangle'
            if. all_sixty do.
                kind =. 'equilateral_triangle'
            elseif. any_right do.
                kind =. 'right_triangle'
            end.
        else.
            first_parallel =. ((0{theta)angle_difference 2{theta)<:AngleTolerance
            second_parallel =. ((1{theta)angle_difference 3{theta)<:AngleTolerance
            if. (-.first_parallel)*.-.second_parallel do.
                kind =. 'quadrilateral'
            elseif. first_parallel~:second_parallel do.
                kind =. 'trapezoid'
            elseif. -.all_right do.
                kind =. 'parallelogram'
            else.
                low =. <./lengths
                high =. >./lengths
                if. (100*(high-low))<:SquareTolerance*high do.
                    kind =. 'square'
                else.
                    kind =. 'rectangle'
                end.
            end.
        end.
        record =. (<identifiers),(<vertices),(<angles),(<lengths),(<supports),(<sigma),(<kind),<count$_1
        Polygons =: (<record)p}Polygons
    end.
    i.0
)
detect_polygons =: 3 : 0
    Polygons =: 0$a:
    for_count. 3 4 do.
        PolygonTarget =: count
        for_first. i.SegmentCount do.
            extend_polygon ,first
        end.
    end.
    polygon_properties ''
)
inside_shape =: 4 : 0
    kind =. 0{::x
    if. kind=1 do.
        delta =. y-4{::x
        (delta dot delta)<:*:5{::x return.
    end.
    vertices =. 3{::x
    sigma =. 6{::x
    count =. #vertices
    for_i. i.count do.
        vertex =. i{vertices
        next =. (count|i+1){vertices
        turn =. (next-vertex)cross y-vertex
        if. (turn~:0)*.((turn>0)~:sigma>0) do.
            0 return.
        end.
    end.
    1
)
shape_text =: 3 : 0
    if. y<0 do.
        'none' return.
    end.
    shape =. y{::Shapes
    kind =. 'polygon'
    if. 0{::shape do.
        kind =. 'circle'
    end.
    kind,' ',integer 1+1{::shape
)
measure_shapes =: 3 : 0
    Shapes =: 0$a:
    for_index. i.#Polygons do.
        polygon =. index{::Polygons
        vertices =. 1{::polygon
        Shapes =: Shapes,<(<0),(<index),(<vertices),(<vertices),(<i.0),(<0),5{polygon
    end.
    for_index. i.#Circles do.
        circle =. index{::Circles
        'column row' =. 0{::circle
        radius =. 1{::circle
        points =. 4 2$(column+radius),row,column,(row+radius),(column-radius),row,column,row-radius
        Shapes =: Shapes,<(<1),(<index),(<points),(<0 2$0x),(0{circle),(1{circle),<0
    end.
    for_index. i.#Shapes do.
        shape =. index{::Shapes
        points =. 2{::shape
        low =. 0>.(<./points)-ContrastMargin
        high =. ((Width-1),Height-1)<.(>./points)+ContrastMargin
        'x0 y0' =. low
        'x1 y1' =. high
        inside_count =. 0
        outside_count =. 0
        inside_sum =. 0x
        outside_sum =. 0x
        for_row. y0+i.0>.1+y1-y0 do.
            for_column. x0+i.0>.1+x1-x0 do.
                value =. (<row,column){Original
                if. shape inside_shape column,row do.
                    inside_count =. inside_count+1
                    inside_sum =. inside_sum+value
                else.
                    outside_count =. outside_count+1
                    outside_sum =. outside_sum+value
                end.
            end.
        end.
        mean =. 0
        outside_mean =. 0
        if. inside_count do.
            mean =. inside_sum intdiv inside_count
        end.
        if. outside_count do.
            outside_mean =. outside_sum intdiv outside_count
        end.
        shape =. shape,(<inside_count),(<mean),(<mean-outside_mean),<_1
        Shapes =: (<shape)index}Shapes
    end.
    for_child. i.#Shapes do.
        enclosing =. _1
        child_shape =. child{::Shapes
        for_parent. i.#Shapes do.
            parent_shape =. parent{::Shapes
            if. (parent=child)+.(7{::parent_shape)<:7{::child_shape do.
                continue.
            end.
            all_inside =. 1
            for_point. 2{::child_shape do.
                if. -.parent_shape inside_shape point do.
                    all_inside =. 0
                    break.
                end.
            end.
            if. all_inside do.
                if. enclosing<0 do.
                    enclosing =. parent
                elseif. (7{::parent_shape)<7{::enclosing{::Shapes do.
                    enclosing =. parent
                end.
            end.
        end.
        child_shape =. (<enclosing)10}child_shape
        Shapes =: (<child_shape)child}Shapes
    end.
    i.0
)
match_corners =: 3 : 0
    'response candidates' =. harris_candidates (<Gx),(<Gy),(<HarrisWindow),<HarrisThreshold
    CornerCandidateCount =: #candidates
    DetectedCorners =: 0$a:
    for_candidate. (HarrisMaximumCount<.#candidates){.candidates do.
        point =. 2{.candidate
        best =. _1
        match_kind =. 0
        match_shape =. _1
        match_part =. _1
        for_p. i.#Polygons do.
            vertices =. 1{::p{::Polygons
            for_vertex. i.#vertices do.
                distance =. point chebyshev vertex{vertices
                if. (distance<:CornerMatchDistance)*.((best<0)+.distance<best) do.
                    best =. distance
                    match_kind =. 1
                    match_shape =. p
                    match_part =. vertex
                end.
            end.
        end.
        if. best<0 do.
            for_segment. i.#Segments do.
                record =. segment{::Segments
                endpoints =. (0{::record),:1{::record
                for_ending. i.2 do.
                    distance =. point chebyshev ending{endpoints
                    if. (distance<:CornerMatchDistance)*.((best<0)+.distance<best) do.
                        best =. distance
                        match_kind =. 2
                        match_shape =. segment
                        match_part =. ending
                    end.
                end.
            end.
        end.
        record =. (<point),(<2{candidate),(<match_kind),(<match_shape),<match_part
        DetectedCorners =: DetectedCorners,<record
    end.
    VerticesWithCorner =: 0
    for_p. i.#Polygons do.
        polygon =. p{::Polygons
        vertices =. 1{::polygon
        vertex_corners =. 7{::polygon
        for_vertex. i.#vertices do.
            best =. _1
            chosen =. _1
            for_c. i.#DetectedCorners do.
                point =. 0{::c{::DetectedCorners
                distance =. (vertex{vertices)chebyshev point
                if. (distance<:CornerMatchDistance)*.((best<0)+.distance<best) do.
                    best =. distance
                    chosen =. c
                end.
            end.
            if. best>:0 do.
                vertex_corners =. chosen vertex}vertex_corners
                VerticesWithCorner =: VerticesWithCorner+1
            end.
        end.
        polygon =. (<vertex_corners)7}polygon
        Polygons =: (<polygon)p}Polygons
    end.
    i.0
)
match_components =: 3 : 0
    for_index. i.#Shapes do.
        shape =. index{::Shapes
        explained =. (Width*Height)$0
        if. 0{::shape do.
            circle =. (1{::shape){::Circles
            for_point. EdgePoints do.
                if. circle circumference point do.
                    pixel =. (0{point)+Width*1{point
                    explained =. 1 pixel}explained
                end.
            end.
        else.
            vertices =. 3{::shape
            count =. #vertices
            for_i. i.count do.
                first =. i{vertices
                last =. (count|i+1){vertices
                for_point. first bresenham last do.
                    for_dy. _1 0 1 do.
                        for_dx. _1 0 1 do.
                            next =. point+dx,dy
                            if. inside_image next do.
                                if. (<(1{next),0{next){Edges do.
                                    pixel =. (0{next)+Width*1{next
                                    explained =. 1 pixel}explained
                                end.
                            end.
                        end.
                    end.
                end.
            end.
        end.
        for_c. i.#Components do.
            component =. c{::Components
            pixels =. 0{::component
            indices =. (0{"1 pixels)+Width*1{"1 pixels
            count =. +/indices{explained
            if. count>6{::component do.
                component =. (<index)5}component
                component =. (<count)6}component
                Components =: (<component)c}Components
            end.
        end.
    end.
    i.0
)
mark_pixel =: 3 : 0
    if. inside_image y do.
        Overlay =: 255 (<(1{y),0{y)}Overlay
    end.
    i.0
)
make_overlay =: 3 : 0
    Overlay =: Original intdiv OverlayDivisor
    for_segment. Segments do.
        segment =. >segment
        for_point. (0{::segment)bresenham 1{::segment do.
            mark_pixel point
        end.
    end.
    for_circle. Circles do.
        circle =. >circle
        center =. 0{::circle
        for_offset. 4{::circle do.
            mark_pixel center+offset
        end.
    end.
    for_corner. DetectedCorners do.
        point =. 0{::>corner
        for_offset. _2 _1 0 1 2 do.
            mark_pixel point+offset,0
            mark_pixel point+0,offset
        end.
    end.
    i.0
)
vote_image =: 3 : 0
    if. MaximumVotes do.
        |:(255*LineVotes)intdiv MaximumVotes
    else.
        ((1+RhoHigh-RhoLow),180)$0x
    end.
)
lines_listing =: 3 : 0
    result =. <'lines ',integer #Lines
    for_i. i.#Lines do.
        'angle radial votes identifiers' =. i{::Lines
        result =. result,<'line ',(integer i+1),' theta ',(integer angle),' rho ',(integer radial),' votes ',(integer votes),' segments ',integer #identifiers
        for_index. identifiers do.
            segment =. index{::Segments
            result =. result,<'segment ',(integer index+1),' start ',(words 0{::segment),' end ',(words 1{::segment),' length ',(integer 3{::segment),' pixels ',integer 4{::segment
        end.
    end.
    result
)
circles_listing =: 3 : 0
    result =. <'circles ',integer #Circles
    for_i. i.#Circles do.
        'center radius votes point_count outline gap arcs' =. i{::Circles
        shape =. ((#Polygons)+i){::Shapes
        result =. result,<'circle ',(integer i+1),' center ',(words center),' radius ',(integer radius),' votes ',(integer votes),' points ',(integer point_count),' gap ',(integer gap),' arcs ',(integer arcs),' pixels ',(integer 7{::shape),' mean ',(integer 8{::shape),' contrast ',(integer 9{::shape),' inside ',shape_text 10{::shape
    end.
    result
)
polygons_listing =: 3 : 0
    result =. <'polygons ',integer #Polygons
    for_p. i.#Polygons do.
        'identifiers vertices angles lengths supports sigma kind vertex_corners' =. p{::Polygons
        shape =. p{::Shapes
        amount =. |sigma
        digit =. '0'
        if. 2|amount do.
            digit =. '5'
        end.
        area =. (integer amount intdiv 2),'.',digit
        result =. result,<'polygon ',(integer p+1),' ',kind,' segments ',(words identifiers+1),' area ',area,' pixels ',(integer 7{::shape),' mean ',(integer 8{::shape),' contrast ',(integer 9{::shape),' inside ',shape_text 10{::shape
        for_i. i.#vertices do.
            corner =. i{vertex_corners
            corner_text =. 'none'
            if. corner>:0 do.
                corner_text =. integer corner+1
            end.
            result =. result,<'vertex ',(integer i+1),' ',(words i{vertices),' angle ',(integer i{angles),' corner ',corner_text
        end.
        for_i. i.#identifiers do.
            result =. result,<'side ',(integer i+1),' segment ',(integer 1+i{identifiers),' length2 ',(integer i{lengths),' support ',integer i{supports
        end.
    end.
    result
)
corners_listing =: 3 : 0
    result =. <'corners ',integer #DetectedCorners
    for_i. i.#DetectedCorners do.
        'point response match_kind match_shape match_part' =. i{::DetectedCorners
        match_text =. 'none'
        if. match_kind=1 do.
            match_text =. 'polygon ',(integer match_shape+1),' vertex ',integer match_part+1
        elseif. match_kind=2 do.
            ending =. match_part{::;:'start end'
            match_text =. 'segment ',(integer match_shape+1),' ',ending
        end.
        result =. result,<'corner ',(integer i+1),' ',(words point),' response ',(integer response),' match ',match_text
    end.
    result
)
components_listing =: 3 : 0
    result =. <'components ',integer #Components
    for_i. i.#Components do.
        'pixels bounds ends strength direction shape explained' =. i{::Components
        result =. result,<'component ',(integer i+1),' pixels ',(integer #pixels),' box ',(words bounds),' ends ',(integer ends),' strength ',(integer strength),' direction ',(integer direction),' shape ',(shape_text shape),' explained ',integer explained
    end.
    result
)
report_lines =: 3 : 0
    gradient_nonzero =. +/,Magnitude>0
    gradient_maximum =. >./,Magnitude
    nms_kept =. +/,Nonmax>0
    strong =. +/,Strong
    weak =. +/,Weak
    weak_kept =. +/,Weak*.Edges
    result =. (<'image ',(integer Width),' ',integer Height),(<'gradient_nonzero ',integer gradient_nonzero),(<'gradient_max ',integer gradient_maximum),(<'nms_kept ',integer nms_kept),(<'strong ',integer strong),(<'weak ',integer weak),(<'edges ',integer #EdgePoints),(<'weak_kept ',integer weak_kept),(<'weak_dropped ',integer weak-weak_kept),<'edge_components ',integer #Components
    for_direction. 0 45 90 135 do.
        count =. +/,Edges*.Directions=direction
        result =. result,<'direction_',(integer direction),' ',integer count
    end.
    names =. ;:'circle_candidates circle_peaks circles circle_edge_pixels line_edge_pixels hough_max_votes hough_peaks lines segments claimed_pixels junctions polygons'
    values =. CircleCandidateCount,CirclePeakCount,(#Circles),(+/,CircleEdge),(#LineEdge),MaximumVotes,LinePeakCount,(#Lines),(#Segments),(+/,Claimed),(#Junctions),#Polygons
    for_i. i.#names do.
        result =. result,<(i{::names),' ',integer i{values
    end.
    kinds =. 8$0
    for_polygon. Polygons do.
        kind =. 6{>polygon
        index =. PolygonKinds i.kind
        kinds =. (1+index{kinds)index}kinds
    end.
    for_i. i.#PolygonKinds do.
        result =. result,<(i{::PolygonKinds),' ',integer i{kinds
    end.
    matches =. 3$0
    for_corner. DetectedCorners do.
        kind =. 2{::>corner
        matches =. (1+kind{matches)kind}matches
    end.
    names =. ;:'corner_candidates corners corners_on_vertices corners_on_segments corners_unmatched vertices_with_corner'
    values =. CornerCandidateCount,(#DetectedCorners),(1{matches),(2{matches),(0{matches),VerticesWithCorner
    for_i. i.#names do.
        result =. result,<(i{::names),' ',integer i{values
    end.
    result
)
run =: 3 : 0
    'Original Trig Params' =: read_inputs ''
    'Height Width' =: $Original
    GaussSize =: {.0{::Params
    GaussKernel =: 1{::Params
    GaussDivisor =: {.2{::Params
    CannyLow =: {.3{::Params
    CannyHigh =: {.4{::Params
    CircleMinimumRadius =: {.5{::Params
    CircleMaximumRadius =: {.6{::Params
    CircleMinimumPercent =: {.7{::Params
    CircleMaximumCount =: {.8{::Params
    RhoStep =: {.9{::Params
    HoughThreshold =: {.10{::Params
    MaximumLines =: {.11{::Params
    SegmentTolerance =: {.12{::Params
    SegmentMaximumGap =: {.13{::Params
    SegmentMinimumLength =: {.14{::Params
    JunctionDistance =: {.15{::Params
    JunctionMinimumAngle =: {.16{::Params
    AngleTolerance =: {.17{::Params
    SquareTolerance =: {.18{::Params
    ContrastMargin =: {.19{::Params
    HarrisWindow =: {.20{::Params
    HarrisThreshold =: {.21{::Params
    HarrisMaximumCount =: {.22{::Params
    CornerMatchDistance =: {.23{::Params
    OverlayDivisor =: {.24{::Params
    smoothed =. ((<GaussSize),(<GaussKernel),<GaussDivisor)smoothing Original
    'Gx Gy Magnitude' =: gradient smoothed
    Directions =: directions (<Gx),<Gy
    Nonmax =: Magnitude suppress Directions
    'Edges Strong Weak' =: (CannyLow,CannyHigh)hysteresis Nonmax
    prepare_components ''
    detect_circles ''
    detect_lines ''
    make_junctions ''
    detect_polygons ''
    measure_shapes ''
    match_corners ''
    match_components ''
    make_overlay ''
    'edges.pgm'write_pgm 255*Edges
    'hough.pgm'write_pgm vote_image ''
    'overlay.pgm'write_pgm Overlay
    'lines.txt'write_lines lines_listing ''
    'circles.txt'write_lines circles_listing ''
    'polygons.txt'write_lines polygons_listing ''
    'corners.txt'write_lines corners_listing ''
    'components.txt'write_lines components_listing ''
    'report.txt'write_lines report_lines ''
    i.0
)
run ''
