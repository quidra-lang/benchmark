load 'predicates.ijs'
load 'triangulation.ijs'
load 'voronoi.ijs'
load 'proximity.ijs'
load 'plot.ijs'
integer =: 3 : 0
    text =. ":<.y
    '-'(I.text='_')}text
)
real_text =: 3 : 0
    text =. (0j3":y)-.' '
    text =. '-'(I.text='_')}text
    if. text-:'-0.000' do.
        text =. '0.000'
    end.
    text
)
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do.
            result =. result,x
        end.
        result =. result,i{::y
    end.
    result
)
words =: 3 : ''' ''join integer&.>y'
read_lines =: 3 : '<;._2 (1!:1 <y)'
split_words =: 3 : '<;._1 '' '',y'
integer_word =: 3 : 0
    value =. y
    if. '-'={.value do.
        value =. }.value
    end.
    (0<#value)*.*./value e.'0123456789'
)
integer_value =: 3 : 0
    negative =. '-'={.y
    value =. negative}.y
    result =. 0
    for_character. value do.
        result =. (result*10)+'0123456789'i.character
    end.
    if. negative do.
        result =. -result
    end.
    result
)
read_inputs =: 3 : 0
    lines =. read_lines 'input/points.txt'
    LineCount =: #lines
    Points =: 0 2$0
    Rejected =: 0$a:
    for_i. i.#lines do.
        line =. i{::lines
        if. 0=#line do.
            continue.
        end.
        if. '#'={.line do.
            continue.
        end.
        fields =. split_words line
        valid =. (#fields)=2
        if. valid do.
            valid =. *./integer_word&>fields
        end.
        if. -.valid do.
            Rejected =: Rejected,<'reject ',(integer i+1),' format'
            continue.
        end.
        values =. integer_value&>fields
        if. +./(values<0)+.values>1000 do.
            Rejected =: Rejected,<'reject ',(integer i+1),' range'
            continue.
        end.
        duplicate =. 0
        for_k. i.#Points do.
            if. values-:k{Points do.
                duplicate =. k+1
                break.
            end.
        end.
        if. duplicate do.
            Rejected =: Rejected,<'reject ',(integer i+1),' duplicate ',integer duplicate
        else.
            Points =: Points,values
        end.
    end.
    Dimensions =: 61 31
    PlotLayers =: ;:'edges hull sites'
    Sections =: <'summary'
    Alphas =: i.0
    Queries =: 0$a:
    for_box. read_lines 'input/params.txt' do.
        line =. >box
        if. 0=#line do.
            continue.
        end.
        if. '#'={.line do.
            continue.
        end.
        fields =. split_words line
        name =. 0{::fields
        values =. }.fields
        select. name
        case. 'plot' do.
            Dimensions =: integer_value&>values
        case. 'plot_layers' do.
            PlotLayers =: values
        case. 'sections' do.
            Sections =: values
        case. 'alpha' do.
            Alphas =: integer_value&>values
        case. 'query' do.
            Queries =: Queries,<6}.line
        end.
    end.
    N =: #Points
    i.0 0
)
build_mesh =: 3 : 0
    mesh_init Points
    Insertions =: 0$a:
    for_site. 4+i.N-3 do.
        Insertions =: Insertions,<insert_site site
    end.
    Triangles =: mesh_triangles 0
    EdgeTriangles =: (N,N)$0
    EdgeIndex =: (N,N)$0
    Edges =: 0 2$0
    Length2 =: i.0
    for_k. i.#Triangles do.
        triangle =. k{Triangles
        for_side. i.3 do.
            u =. (side{triangle)-1
            v =. ((3|side+1){triangle)-1
            EdgeTriangles =: (k+1)(<u,v)}EdgeTriangles
        end.
    end.
    for_i. 1+i.N do.
        for_j. (i+1)+i.N-i do.
            if. ((<(i-1),(j-1)){Directed)+(<(j-1),(i-1)){Directed do.
                Edges =: Edges,i,j
                Length2 =: Length2,((i-1){Points)d2 (j-1){Points
                index =. #Edges
                EdgeIndex =: index(<(i-1),(j-1))}EdgeIndex
                EdgeIndex =: index(<(j-1),(i-1))}EdgeIndex
            end.
        end.
    end.
    HullNext =: HullPrev =: N$0
    for_edge. hull_edges 0 do.
        'u v' =. edge
        HullNext =: v(u-1)}HullNext
        HullPrev =: u(v-1)}HullPrev
    end.
    start =. 1+{.I.HullNext>0
    Hull =: ,start
    while. start~:(({:Hull)-1){HullNext do.
        Hull =: Hull,(({:Hull)-1){HullNext
    end.
    HullEdges =: 0 2$0
    HullPerimeter =: 0.0
    HullArea2 =: 0x
    for_i. i.#Hull do.
        u =. i{Hull
        v =. ((#Hull)|i+1){Hull
        HullEdges =: HullEdges,u,v
        p =. (u-1){Points
        q =. (v-1){Points
        HullPerimeter =: HullPerimeter+%:0.0+p d2 q
        HullArea2 =: HullArea2+((0{p)*1{q)-(0{q)*1{p
    end.
    adjacent =. N$a:
    for_edge. Edges do.
        'i j' =. edge-1
        adjacent =. (<(i{::adjacent),j+1)i}adjacent
        adjacent =. (<(j{::adjacent),i+1)j}adjacent
    end.
    Neighbors =: 0$a:
    Degree =: i.0
    for_site. 1+i.N do.
        order =. neighbor_order (<site),(<(site-1){::adjacent),(<Directed),<HullNext
        Neighbors =: Neighbors,<order
        Degree =: Degree,#order
    end.
    i.0 0
)
angle_degrees =: 4 : 0
    value =. (0.0+y)j.(0.0+x)
    ((12 o.value)*180.0)%3.141592653589793
)
analyze_triangles =: 3 : 0
    Area2 =: i.0
    Kinds =: 0$a:
    KindCounts =: 3$0
    MinAngles =: MaxAngles =: i.0
    AngleBins =: 6$0
    MinAngleTotal =: 0.0
    MinimumTriangle =: MaximumTriangle =: 0
    for_k. i.#Triangles do.
        'a b c' =. (k{Triangles)-1
        a =. a{Points
        b =. b{Points
        c =. c{Points
        area =. orient a,b,:c
        products =. (dot a,b,:c),(dot b,c,:a),dot c,a,:b
        lengths =. (b d2 c),(c d2 a),a d2 b
        kind =. 0
        if. 0 e.products do.
            kind =. 1
        elseif. (<./products)<0 do.
            kind =. 2
        end.
        names =. ;:'acute right obtuse'
        Kinds =: Kinds,kind{names
        KindCounts =: (1+kind{KindCounts)kind}KindCounts
        shortest =. {./:lengths
        longest =. {.\:lengths
        minimum =. area angle_degrees shortest{products
        maximum =. area angle_degrees longest{products
        Area2 =: Area2,area
        MinAngles =: MinAngles,minimum
        MaxAngles =: MaxAngles,maximum
        bin =. <.minimum%10.0
        AngleBins =: (1+bin{AngleBins)bin}AngleBins
        MinAngleTotal =: MinAngleTotal+minimum
        if. MinimumTriangle=0 do.
            MinimumTriangle =: k+1
        elseif. minimum<(MinimumTriangle-1){MinAngles do.
            MinimumTriangle =: k+1
        end.
        if. MaximumTriangle=0 do.
            MaximumTriangle =: k+1
        elseif. maximum>(MaximumTriangle-1){MaxAngles do.
            MaximumTriangle =: k+1
        end.
    end.
    i.0 0
)
c_vertices =: 0&{::
c_clip =: 1&{::
c_bounded =: 2&{::
c_area =: 3&{::
c_incoming =: 4&{::
c_outgoing =: 5&{::
analyze_voronoi =: 3 : 0
    Centers =: 0 3$0x
    Radius2 =: i.0
    Positions =: 0$a:
    PositionCounts =: 3$0
    EmptyCandidates =: i.0
    EmptyVertex =: 0
    for_k. i.#Triangles do.
        vertices =. ((k{Triangles)-1){Points
        center =. circumcenter vertices
        position =. center_position (<center),(<Points),<Hull
        Centers =: Centers,center
        Radius2 =: Radius2,radius2 vertices
        Positions =: Positions,<position
        index =. ('inside';'on';'outside')i.<position
        PositionCounts =: (1+index{PositionCounts)index}PositionCounts
        if. position-:'inside' do.
            EmptyCandidates =: EmptyCandidates,k+1
            if. EmptyVertex=0 do.
                EmptyVertex =: k+1
            elseif. (k{Radius2)>(EmptyVertex-1){Radius2 do.
                EmptyVertex =: k+1
            end.
        end.
    end.
    Duals =: 0$a:
    for_edge. Edges do.
        'i j' =. edge-1
        left =. (<i,j){EdgeTriangles
        right =. (<j,i){EdgeTriangles
        if. (left>0)*.right>0 do.
            dual =. 'segment ',(integer left),' ',integer right
        else.
            u =. i+1
            v =. j+1
            number =. left
            if. left=0 do.
                u =. j+1
                v =. i+1
                number =. right
            end.
            direction =. outward (<Points),(<u),<v
            dual =. 'ray ',(integer number),' ',words direction
        end.
        Duals =: Duals,<dual
    end.
    Cells =: 0$a:
    CellTotal =: ClipTotal =: 0.0
    LargestCell =: 0
    for_site. 1+i.N do.
        vertices =. i.0
        centers =. 0 3$0x
        for_other. (site-1){::Neighbors do.
            number =. (<(site-1),(other-1)){EdgeTriangles
            if. number do.
                vertices =. vertices,number
                centers =. centers,(number-1){Centers
            end.
        end.
        clipped =. clipped_area (<Points),(<site),<(site-1){::Neighbors
        bounded =. 0=(site-1){HullNext
        area =. 0.0
        incoming =. outgoing =. i.0
        if. bounded do.
            area =. bounded_area (<(site-1){Points),<centers
            CellTotal =: CellTotal+area
            if. LargestCell=0 do.
                LargestCell =: site
            elseif. area>c_area (LargestCell-1){::Cells do.
                LargestCell =: site
            end.
        else.
            incoming =. outward (<Points),(<site),<(site-1){HullNext
            outgoing =. outward (<Points),(<(site-1){HullPrev),<site
        end.
        ClipTotal =: ClipTotal+clipped
        Cells =: Cells,<(<vertices),(<clipped),(<bounded),(<area),(<incoming),<outgoing
    end.
    i.0 0
)
analyze_proximity =: 3 : 0
    Nearest =: nearest_neighbors (<Points),<Neighbors
    MutualPairs =: 0 2$0
    for_site. 1+i.N do.
        other =. (site-1){Nearest
        if. (site<other)*.site=(other-1){Nearest do.
            MutualPairs =: MutualPairs,site,other
        end.
    end.
    Closest =: {.I.Length2=<./Length2
    Components =: nearest_components Nearest
    ComponentNumber =: N$0
    ComponentPairs =: 0 2$0
    for_k. i.#Components do.
        pair =. i.0
        for_site. k{::Components do.
            ComponentNumber =: (k+1)(site-1)}ComponentNumber
            other =. (site-1){Nearest
            if. (site<other)*.site=(other-1){Nearest do.
                pair =. site,other
            end.
        end.
        ComponentPairs =: ComponentPairs,pair
    end.
    Mst =: kruskal (<Points),<Edges
    MstSet =: Gabriel =: Rng =: (#Edges)$0
    GGdegree =: RngDegree =: MstDegree =: N$0
    MstLength =: 0.0
    for_edge. Mst do.
        'i j' =. edge-1
        index =. ((<i,j){EdgeIndex)-1
        MstSet =: 1 index}MstSet
        MstLength =: MstLength+%:0.0+(i{Points)d2 j{Points
        MstDegree =: (1+i{MstDegree)i}MstDegree
        MstDegree =: (1+j{MstDegree)j}MstDegree
    end.
    for_k. i.#Edges do.
        edge =. k{Edges
        'i j' =. edge-1
        if. is_gabriel (<Points),(<edge),<Directed do.
            Gabriel =: 1 k}Gabriel
            GGdegree =: (1+i{GGdegree)i}GGdegree
            GGdegree =: (1+j{GGdegree)j}GGdegree
        end.
        if. is_relative (<Points),<edge do.
            Rng =: 1 k}Rng
            RngDegree =: (1+i{RngDegree)i}RngDegree
            RngDegree =: (1+j{RngDegree)j}RngDegree
        end.
    end.
    i.0 0
)
circle_basis =: 3 : 0
    result =. y
    if. (#result)=3 do.
        if. (orient (result-1){Points)<0 do.
            result =. 0 2 1{result
        end.
    end.
    result
)
circle_value =: 4 : 0
    if. (#x)=1 do.
        -((({.x)-1){Points)d2 y
    elseif. (#x)=2 do.
        -dot y,((({.x)-1){Points),:(({:x)-1){Points
    else.
        incircle ((x-1){Points),y
    end.
)
enclosing_circle =: 3 : 0
    basis =. i.0
    for_i. i.#Hull do.
        site =. i{Hull
        outside =. 0=#basis
        if. -.outside do.
            outside =. (basis circle_value (site-1){Points)<0
        end.
        if. outside do.
            basis =. ,site
            for_j. i.i do.
                second =. j{Hull
                if. (basis circle_value (second-1){Points)<0 do.
                    basis =. site,second
                    for_k. i.j do.
                        third =. k{Hull
                        if. (basis circle_value (third-1){Points)<0 do.
                            basis =. circle_basis site,second,third
                        end.
                    end.
                end.
            end.
        end.
    end.
    boundary =. i.0
    for_site. 1+i.N do.
        if. 0=basis circle_value (site-1){Points do.
            boundary =. boundary,site
        end.
    end.
    diameter_pair =. i.0
    for_i. i.(#boundary)-1 do.
        for_j. (i+1)+i.(#boundary)-(i+1) do.
            a =. i{boundary
            b =. j{boundary
            valid =. 1
            for_other. boundary do.
                if. 0~:dot ((other-1){Points),((a-1){Points),:(b-1){Points do.
                    valid =. 0
                end.
            end.
            if. valid do.
                diameter_pair =. a,b
                break.
            end.
        end.
        if. #diameter_pair do.
            break.
        end.
    end.
    if. #diameter_pair do.
        a =. ((0{diameter_pair)-1){Points
        b =. ((1{diameter_pair)-1){Points
        EnclosingCenter =: (a+b),2
        EnclosingRadius2 =: (0.0+a d2 b)%4.0
    else.
        ordered =. circle_basis boundary
        vertices =. (ordered-1){Points
        EnclosingCenter =: circumcenter vertices
        EnclosingRadius2 =: radius2 vertices
    end.
    EnclosingSites =: boundary
    i.0 0
)
analyze_extent =: 3 : 0
    Diameter =: 1 2
    Diameter2 =: (0{Points)d2 1{Points
    for_i. 1+i.N do.
        for_j. (i+1)+i.N-i do.
            value =. ((i-1){Points)d2 (j-1){Points
            if. value>Diameter2 do.
                Diameter =: i,j
                Diameter2 =: value
            end.
        end.
    end.
    Width =: _
    for_edge. HullEdges do.
        a =. ((0{edge)-1){Points
        b =. ((1{edge)-1){Points
        maximum =. 0x
        for_site. Hull do.
            maximum =. maximum>.orient a,b,:(site-1){Points
        end.
        distance =. %:0.0+a d2 b
        value =. (0.0+maximum)%distance
        if. value<Width do.
            Width =: value
            WidthEdge =: edge
        end.
    end.
    enclosing_circle 0
)
layer_hull =: 3 : 0
    if. (#y)<:2 do.
        /:~y return.
    end.
    ordered =. (/:((y-1){Points)){y
    lower =. upper =. i.0
    for_site. ordered do.
        while. (#lower)>:2 do.
            ids =. (_2{.lower),site
            if. (orient (ids-1){Points)>0 do.
                break.
            end.
            lower =. }:lower
        end.
        lower =. lower,site
    end.
    for_site. |.ordered do.
        while. (#upper)>:2 do.
            ids =. (_2{.upper),site
            if. (orient (ids-1){Points)>0 do.
                break.
            end.
            upper =. }:upper
        end.
        upper =. upper,site
    end.
    layer =. (}:lower),}:upper
    (layer i.<./layer)|.layer
)
analyze_layers =: 3 : 0
    remaining =. 1+i.N
    Layers =: 0$a:
    Depth =: N$0
    while. #remaining do.
        layer =. layer_hull remaining
        Layers =: Layers,<layer
        Depth =: (#Layers)(layer-1)}Depth
        remaining =. remaining#~-.remaining e.layer
    end.
    i.0 0
)
shortest_from =: 3 : 0
    if. 0=#(y-1){::PathDistances do.
        'distances previous' =. dijkstra (<Points),(<Neighbors),<y
        PathDistances =: (<distances)(y-1)}PathDistances
        PathPrevious =: (<previous)(y-1)}PathPrevious
    end.
    (<(y-1){::PathDistances),<(y-1){::PathPrevious
)
analyze_spanner =: 3 : 0
    PathDistances =: PathPrevious =: N$a:
    PairCount =: <.0.0+(N*(N-1))intdiv 2
    MaximumStretch =: 0.0
    StretchPair =: i.0
    total =. 0.0
    for_i. 1+i.N-1 do.
        'distances previous' =. shortest_from i
        for_j. (i+1)+i.N-i do.
            length =. (j-1){distances
            distance =. %:0.0+((i-1){Points)d2 (j-1){Points
            stretch =. length%distance
            total =. total+stretch
            if. (0=#StretchPair)+.stretch>MaximumStretch do.
                MaximumStretch =: stretch
                StretchPair =: i,j
                StretchLength =: length
                StretchDistance =: distance
            end.
        end.
    end.
    MeanStretch =: total%PairCount
    i.0 0
)
analyze_alpha =: 3 : 0
    AlphaResults =: 0 9$0x
    for_alpha. Alphas do.
        faces =. total_area =. 0
        incidence =. (#Edges)$0
        selected =. (#Edges)$0
        for_k. i.#Triangles do.
            if. (k{Radius2)<:alpha do.
                faces =. faces+1
                total_area =. total_area+k{Area2
                triangle =. k{Triangles
                for_side. i.3 do.
                    u =. (side{triangle)-1
                    v =. ((3|side+1){triangle)-1
                    index =. ((<u,v){EdgeIndex)-1
                    incidence =. (1+index{incidence)index}incidence
                    selected =. 1 index}selected
                end.
            end.
        end.
        selected =. selected+.Gabriel*.Length2<:4*alpha
        sets_init N
        incident =. N$0
        selected_edges =. boundary =. dangling =. 0
        for_k. I.selected do.
            'u v' =. k{Edges
            u join_sets v
            incident =. 1 ((u-1),v-1)}incident
            selected_edges =. selected_edges+1
            boundary =. boundary+(k{incidence)=1
            dangling =. dangling+(k{incidence)=0
        end.
        isolated =. N-+/incident
        holes =. SetCount-((N-selected_edges)+faces)
        AlphaResults =: AlphaResults,alpha,faces,selected_edges,boundary,dangling,isolated,SetCount,holes,total_area
    end.
    i.0 0
)
locate_query =: 3 : 0
    query =. y
    distances =. i.0
    for_point. Points do.
        distances =. distances,point d2 query
    end.
    nearest =. {.I.distances=<./distances
    best =. nearest{distances
    location =. 'outside'
    if. best=0 do.
        location =. 'vertex ',integer nearest+1
    else.
        for_edge. Edges do.
            a =. ((0{edge)-1){Points
            b =. ((1{edge)-1){Points
            if. (0=orient a,b,:query)*.0>dot query,a,:b do.
                location =. 'edge ',words edge
                break.
            end.
        end.
        if. location-:'outside' do.
            for_triangle. Triangles do.
                if. triangle inside_triangle query do.
                    location =. 'triangle ',words triangle
                    break.
                end.
            end.
        end.
    end.
    location,' nearest ',(integer nearest+1),' d2 ',integer best
)
answer_query =: 3 : 0
    query =. y
    fields =. split_words query
    name =. 0{::fields
    values =. integer_value&>}.fields
    if. (<name)e.;:'route path neighbors edge' do.
        if. +./(values<1)+.values>N do.
            query,' error unknown_site' return.
        end.
        if. name-:'edge' do.
            if. (0{values)=1{values do.
                query,' error same_site' return.
            end.
        end.
    end.
    select. name
    case. 'locate' do.
        answer =. locate_query values
    case. 'walk' do.
        'path outside' =. visibility_walk (<values),(<Triangles),<EdgeTriangles
        stopping =. 'triangle ',integer {:path
        if. #outside do.
            stopping =. 'outside ',words outside
        end.
        answer =. 'steps ',(integer (#path)-1),' ',stopping,' path ',words path
    case. 'natural' do.
        count =. 0
        present =. N$0
        for_triangle. Triangles do.
            if. 0<incircle ((triangle-1){Points),values do.
                count =. count+1
                present =. 1 (triangle-1)}present
            end.
        end.
        sites =. 1+I.present
        sequence =. '-'
        if. #sites do.
            sequence =. words sites
        end.
        answer =. 'triangles ',(integer count),' sites ',sequence
    case. 'route' do.
        'path length' =. greedy_route (<Points),(<Neighbors),(<0{values),<1{values
        answer =. 'hops ',(integer (#path)-1),' length ',(real_text length),' path ',words path
    case. 'path' do.
        'first second' =. values
        'distances previous' =. shortest_from first
        reverse =. ,second
        while. ({:reverse)~:first do.
            reverse =. reverse,(({:reverse)-1){previous
        end.
        path =. |.reverse
        length =. (second-1){distances
        stretch =. '-'
        if. first~:second do.
            distance =. %:0.0+((first-1){Points)d2 (second-1){Points
            stretch =. real_text length%distance
        end.
        answer =. 'length ',(real_text length),' stretch ',stretch,' hops ',(integer (#path)-1),' sites ',words path
    case. 'neighbors' do.
        site =. ({.values)-1
        answer =. 'degree ',(integer site{Degree),' sites ',words site{::Neighbors
    case. 'edge' do.
        'i j' =. values-1
        index =. ((<i,j){EdgeIndex)-1
        if. index>:0 do.
            gabriel =. 'no'
            rng =. 'no'
            mst =. 'no'
            if. index{Gabriel do. gabriel =. 'yes' end.
            if. index{Rng do. rng =. 'yes' end.
            if. index{MstSet do. mst =. 'yes' end.
            answer =. 'delaunay len2 ',(integer index{Length2),' gabriel ',gabriel,' rng ',rng,' mst ',mst,' dual ',index{::Duals
        else.
            crossings =. 0$a:
            a =. i{Points
            b =. j{Points
            for_edge. Edges do.
                p =. ((0{edge)-1){Points
                q =. ((1{edge)-1){Points
                first =. (orient a,b,:p)*orient a,b,:q
                second =. (orient p,q,:a)*orient p,q,:b
                if. (first<0)*.second<0 do.
                    crossings =. crossings,<(integer 0{edge),'-',integer 1{edge
                end.
            end.
            answer =. 'missing crossings ',integer #crossings
            if. #crossings do.
                answer =. answer,' ',' 'join crossings
            end.
        end.
    end.
    query,' ',answer
)
draw_plots =: 3 : 0
    canvas_init Dimensions
    for_box. PlotLayers do.
        layer =. >box
        select. layer
        case. 'sites' do.
            for_point. Points do.
                'o' canvas_mark point
            end.
        case. 'circle' do.
            if. EmptyVertex do.
                '@' canvas_mark (EmptyVertex-1){Centers
            end.
        case. do.
            selected =. Edges
            character =. '.'
            if. layer-:'mst' do.
                selected =. Mst
                character =. '*'
            elseif. layer-:'hull' do.
                selected =. HullEdges
                character =. '#'
            end.
            for_edge. selected do.
                canvas_line (<((0{edge)-1){Points),(<((1{edge)-1){Points),<character
            end.
        end.
    end.
    DelaunayPlot =: canvas_framed 0
    canvas_init Dimensions
    canvas_voronoi Points
    VoronoiPlot =: canvas_framed 0
    i.0 0
)
section_input =: 3 : 0
    (<'lines ',integer LineCount),(<'accepted ',integer N),(<'rejected ',integer #Rejected),Rejected
)
section_summary =: 3 : 0
    flips =. outside =. 0
    maximum =. _1
    maximum_flips =. _1
    for_k. i.#Insertions do.
        insertion =. k{::Insertions
        flips =. flips+3{::insertion
        outside =. outside+'outside'-:0{::insertion
        if. (3{::insertion)>maximum_flips do.
            maximum =. k
            maximum_flips =. 3{::insertion
        end.
    end.
    maximum_line =. 'max_flips none'
    if. maximum>:0 do.
        maximum_line =. 'max_flips ',(integer maximum+4),' ',integer maximum_flips
    end.
    lines =. (<'sites ',integer N),(<'triangles ',integer #Triangles),(<'edges ',integer #Edges),<'hull_vertices ',integer #Hull
    lines =. lines,(<'interior_sites ',integer N-#Hull),(<'euler ',integer (N-#Edges)+#Triangles),(<'flips ',integer flips),<'outside_insertions ',integer outside
    lines,(<maximum_line),(<'acute ',integer 0{KindCounts),(<'right ',integer 1{KindCounts),<'obtuse ',integer 2{KindCounts
)
section_insertions =: 3 : 0
    lines =. <'init ',words Initial
    for_k. i.#Insertions do.
        'kind containing visible flips triangles hull' =. k{::Insertions
        description =. 'outside ',integer visible
        if. kind-:'inside' do.
            description =. 'inside ',words containing
        end.
        lines =. lines,<'insert ',(integer k+4),' ',description,' flips ',(integer flips),' triangles ',(integer triangles),' hull ',integer hull
    end.
    lines
)
optional_id =: 3 : 0
    if. y=0 do. '-' else. integer y end.
)
section_triangles =: 3 : 0
    lines =. 0$a:
    for_k. i.#Triangles do.
        triangle =. k{Triangles
        'a b c' =. triangle-1
        adjacent =. ((<c,b){EdgeTriangles),((<a,c){EdgeTriangles),(<b,a){EdgeTriangles
        lines =. lines,<'tri ',(integer k+1),' ',(words triangle),' area2 ',(integer k{Area2),' ',(k{::Kinds),' adj ',' 'join optional_id&.>adjacent
    end.
    lines
)
section_edges =: 3 : 0
    lines =. 0$a:
    for_k. i.#Edges do.
        edge =. k{Edges
        'i j' =. edge-1
        left =. (<i,j){EdgeTriangles
        right =. (<j,i){EdgeTriangles
        kind =. 'hull'
        if. (left>0)*.right>0 do.
            kind =. 'inner'
        end.
        lines =. lines,<'edge ',(words edge),' ',kind,' len2 ',(integer k{Length2),' left ',(optional_id left),' right ',optional_id right
    end.
    lines
)
section_hull =: 3 : 0
    (<'hull_vertices ',integer #Hull),(<'order ',words Hull),(<'perimeter ',real_text HullPerimeter),<'area2 ',integer HullArea2
)
section_convex_layers =: 3 : 0
    lines =. <'layers ',integer #Layers
    for_k. i.#Layers do.
        layer =. k{::Layers
        lines =. lines,<'layer ',(integer k+1),' size ',(integer #layer),' sites ',words layer
    end.
    lines
)
section_quality =: 3 : 0
    lines =. (<'min_angle ',(real_text (MinimumTriangle-1){MinAngles),' tri ',integer MinimumTriangle),<'max_angle ',(real_text (MaximumTriangle-1){MaxAngles),' tri ',integer MaximumTriangle
    lines =. lines,<'mean_min_angle ',real_text MinAngleTotal%#Triangles
    for_bin. i.6 do.
        lines =. lines,<'bin ',(integer bin*10),' ',(integer (bin+1)*10),' ',integer bin{AngleBins
    end.
    lines
)
section_vertices =: 3 : 0
    lines =. (<'inside ',integer 0{PositionCounts),(<'on ',integer 1{PositionCounts),<'outside ',integer 2{PositionCounts
    for_k. i.#Centers do.
        'x y d' =. k{Centers
        lines =. lines,<'v ',(integer k+1),' ',(x fraction d),' ',(y fraction d),' r ',(real_text %:k{Radius2),' ',k{::Positions
    end.
    lines
)
section_voronoi_edges =: 3 : 0
    lines =. (<'segments ',integer (#Edges)-#Hull),<'rays ',integer #Hull
    for_k. i.#Edges do.
        lines =. lines,<'ve ',(words k{Edges),' ',k{::Duals
    end.
    lines
)
section_cells =: 3 : 0
    lines =. (<'bounded ',integer N-#Hull),(<'unbounded ',integer #Hull),(<'total_area ',real_text CellTotal),<'clip_total ',real_text ClipTotal
    largest =. 'largest none'
    if. LargestCell do.
        largest =. 'largest ',(integer LargestCell),' area ',real_text c_area (LargestCell-1){::Cells
    end.
    lines =. lines,<largest
    for_i. i.#Cells do.
        cell =. i{::Cells
        vertices =. c_vertices cell
        line =. 'cell ',(integer i+1),' '
        if. c_bounded cell do.
            line =. line,'bounded ',(integer #vertices),' area ',(real_text c_area cell),' clip ',(real_text c_clip cell),' vertices ',words vertices
        else.
            line =. line,'unbounded ',(integer #vertices),' clip ',(real_text c_clip cell),' from ',(words c_incoming cell),' vertices ',(words vertices),' to ',words c_outgoing cell
        end.
        lines =. lines,<line
    end.
    lines
)
section_nearest =: 3 : 0
    lines =. (<'mutual_pairs ',integer #MutualPairs),<'closest_pair ',(words Closest{Edges),' d2 ',integer Closest{Length2
    for_site. 1+i.N do.
        other =. (site-1){Nearest
        mutual =. '-'
        if. site=(other-1){Nearest do.
            mutual =. 'mutual'
        end.
        distance =. ((site-1){Points)d2 (other-1){Points
        lines =. lines,<'nn ',(integer site),' ',(integer other),' d2 ',(integer distance),' ',mutual
    end.
    lines
)
section_components =: 3 : 0
    lines =. <'components ',integer #Components
    for_k. i.#Components do.
        group =. k{::Components
        lines =. lines,<'component ',(integer k+1),' size ',(integer #group),' pair ',(words k{ComponentPairs),' sites ',words group
    end.
    lines
)
section_mst =: 3 : 0
    longest =. {:Mst
    distance =. (((0{longest)-1){Points)d2 ((1{longest)-1){Points
    lines =. (<'edges ',integer N-1),(<'total_length ',real_text MstLength),<'longest ',(words longest),' len2 ',integer distance
    for_edge. Mst do.
        distance =. (((0{edge)-1){Points)d2 ((1{edge)-1){Points
        lines =. lines,<'mst ',(words edge),' len2 ',integer distance
    end.
    lines
)
section_proximity =: 3 : 0
    lines =. (<'delaunay ',integer #Edges),(<'gabriel ',integer +/Gabriel),(<'rng ',integer +/Rng),(<'mst ',integer N-1),<'nn ',integer N-#MutualPairs
    for_k. I.Rng*.-.MstSet do.
        lines =. lines,<'rng_extra ',(words k{Edges),' len2 ',integer k{Length2
    end.
    lines
)
section_degrees =: 3 : 0
    lines =. (<'min ',integer <./Degree),<'max ',integer >./Degree
    for_degree. /:~~.Degree do.
        lines =. lines,<'degree ',(integer degree),' count ',integer +/Degree=degree
    end.
    lines
)
section_empty_circle =: 3 : 0
    lines =. <'candidates ',integer #EmptyCandidates
    if. EmptyVertex=0 do.
        lines,<'none' return.
    end.
    k =. EmptyVertex-1
    'x y d' =. k{Centers
    lines,(<'vertex ',integer EmptyVertex),(<'center ',(x fraction d),' ',y fraction d),(<'radius ',real_text %:k{Radius2),<'sites ',words k{Triangles
)
section_extent =: 3 : 0
    'x y d' =. EnclosingCenter
    lines =. (<'diameter ',(words Diameter),' d2 ',integer Diameter2),<'width ',(real_text Width),' edge ',words WidthEdge
    lines,(<'enclosing_center ',(x fraction d),' ',y fraction d),(<'enclosing_radius ',real_text %:EnclosingRadius2),<'enclosing_sites ',words EnclosingSites
)
section_spanner =: 3 : 0
    line =. 'max_stretch ',(real_text MaximumStretch),' pair ',(words StretchPair),' length ',(real_text StretchLength),' distance ',real_text StretchDistance
    (<'pairs ',integer PairCount),(<line),<'mean_stretch ',real_text MeanStretch
)
section_alpha =: 3 : 0
    lines =. 0$a:
    for_row. AlphaResults do.
        'alpha faces edges boundary dangling isolated components holes area2' =. row
        line =. 'alpha ',(integer alpha),' triangles ',(integer faces),' edges ',(integer edges),' boundary ',(integer boundary),' dangling ',integer dangling
        line =. line,' isolated ',(integer isolated),' components ',(integer components),' holes ',(integer holes),' area2 ',integer area2
        lines =. lines,<line
    end.
    lines
)
section_sites =: 3 : 0
    lines =. 0$a:
    for_i. i.N do.
        position =. 'inner'
        if. i{HullNext do.
            position =. 'hull'
        end.
        line =. 'site ',(integer i+1),' ',(words i{Points),' ',position,' dt ',(integer i{Degree),' gg ',(integer i{GGdegree),' rng ',(integer i{RngDegree),' mst ',integer i{MstDegree
        line =. line,' nn ',(integer i{Nearest),' comp ',(integer i{ComponentNumber),' depth ',integer i{Depth
        lines =. lines,<line
    end.
    lines
)
section_queries =: 3 : 'Answers'
section_delaunay_plot =: 3 : 'DelaunayPlot'
section_voronoi_plot =: 3 : 'VoronoiPlot'
section =: 3 : 0
    select. y
    case. 'input' do. section_input 0
    case. 'summary' do. section_summary 0
    case. 'insertions' do. section_insertions 0
    case. 'triangles' do. section_triangles 0
    case. 'edges' do. section_edges 0
    case. 'hull' do. section_hull 0
    case. 'convex_layers' do. section_convex_layers 0
    case. 'quality' do. section_quality 0
    case. 'vertices' do. section_vertices 0
    case. 'voronoi_edges' do. section_voronoi_edges 0
    case. 'cells' do. section_cells 0
    case. 'nearest' do. section_nearest 0
    case. 'components' do. section_components 0
    case. 'mst' do. section_mst 0
    case. 'proximity' do. section_proximity 0
    case. 'degrees' do. section_degrees 0
    case. 'empty_circle' do. section_empty_circle 0
    case. 'extent' do. section_extent 0
    case. 'spanner' do. section_spanner 0
    case. 'alpha' do. section_alpha 0
    case. 'sites' do. section_sites 0
    case. 'queries' do. section_queries 0
    case. 'delaunay_plot' do. section_delaunay_plot 0
    case. 'voronoi_plot' do. section_voronoi_plot 0
    end.
)
write_sections =: 3 : 0
    filenames =. 'triangulation.txt';'voronoi.txt';'derived.txt';'plot.txt'
    owners =. (<;:'input summary insertions triangles edges hull convex_layers quality'),(<;:'vertices voronoi_edges cells'),(<;:'nearest components mst proximity degrees empty_circle extent spanner alpha sites queries'),<;:'delaunay_plot voronoi_plot'
    contents =. 4#<0$a:
    for_box. Sections do.
        name =. >box
        owner =. 0
        for_i. i.4 do.
            if. (<name)e.i{::owners do.
                owner =. i
            end.
        end.
        lines =. owner{::contents
        lines =. lines,(<'[',name,']'),section name
        contents =. (<lines)owner}contents
    end.
    for_i. i.4 do.
        lines =. i{::contents
        text =. ''
        if. #lines do.
            text =. ;lines,each<LF
        end.
        text 1!:2 <'output/',i{::filenames
    end.
    i.0 0
)
run =: 3 : 0
    read_inputs 0
    build_mesh 0
    analyze_triangles 0
    analyze_voronoi 0
    analyze_proximity 0
    analyze_extent 0
    analyze_layers 0
    analyze_spanner 0
    analyze_alpha 0
    Answers =: answer_query&.>Queries
    draw_plots 0
    write_sections 0
    i.0 0
)
run 0
