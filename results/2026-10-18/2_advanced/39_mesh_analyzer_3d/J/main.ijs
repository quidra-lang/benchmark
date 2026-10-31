load 'obj_io.ijs'
load 'measure.ijs'
load 'repair.ijs'
load 'topology.ijs'
load 'orientation.ijs'
yes =: 3 : 'y{::''no'';''yes'''
names_listing =: 3 : 0
    if. #y do.
        ' 'join y
    else.
        '-'
    end.
)
fields =: 4 : 0
    result =. 0$a:
    for_index. i.#x do.
        result =. result,<(index{::x),' ',index{::y
    end.
    result
)
c_number =: 0&{::
c_faces =: 1&{::
c_vertices =: 2&{::
c_edges =: 3&{::
c_boundary =: 4&{::
c_nonmanifold =: 5&{::
c_bad_vertices =: 6&{::
c_closed =: 7&{::
c_manifold =: 8&{::
c_consistent =: 9&{::
c_solid =: 10&{::
c_inside =: 11&{::
c_orientable =: 12&{::
c_loops =: 13&{::
c_euler =: 14&{::
c_genus =: 15&{::
c_crosscaps =: 16&{::
c_volume =: 17&{::
c_area =: 18&{::
c_normal =: 19&{::
c_bbox =: 20&{::
c_center =: 21&{::
c_shapes =: 22&{::
c_angles =: 23&{::
c_edge_min =: 24&{::
c_edge_max =: 25&{::
c_valence_min =: 26&{::
c_valence_max =: 27&{::
read_parameters =: 3 : 0
    SnapSpacing =: 1
    Merge =: 1
    Degenerate =: 1
    Duplicates =: 1
    Orient =: 1
    Outward =: 1
    FillHoles =: 0
    KeepUnused =: 1
    Sections =: ;:'summary components'
    Queries =: 0$a:
    for_box. read_lines 'input/params.txt' do.
        line =. >box
        if. 0=#line do.
            continue.
        end.
        if. '#'={.line do.
            continue.
        end.
        tokens =. words line
        name =. 0{::tokens
        args =. }.tokens
        if. name-:'query' do.
            Queries =: Queries,<(<0{::args),<num&>}.args
        elseif. name-:'sections' do.
            Sections =: args
        elseif. name-:'snap' do.
            SnapSpacing =: num 0{::args
        elseif. name-:'fill_holes' do.
            FillHoles =: num 0{::args
        else.
            enabled =. 'on'-:0{::args
            select. name
            case. 'merge' do.
                Merge =: enabled
            case. 'degenerate' do.
                Degenerate =: enabled
            case. 'duplicates' do.
                Duplicates =: enabled
            case. 'orient' do.
                Orient =: enabled
            case. 'outward' do.
                Outward =: enabled
            case. 'keep_unused' do.
                KeepUnused =: enabled
            end.
        end.
    end.
    0
)
polygon_nonplanar =: 4 : 0
    corners =. x
    points =. y
    origin =. ((0{corners)-1){points
    total =. 0 0 0x
    for_index. 1+i.(#corners)-2 do.
        a =. (((index{corners)-1){points)-origin
        b =. ((((index+1){corners)-1){points)-origin
        total =. total+a cross b
    end.
    for_vertex. corners do.
        if. 0~:((((vertex-1){points)-origin)dot total) do.
            1 return.
        end.
    end.
    0
)
edge_shape =: 3 : 0
    'edge adjacent' =. y
    if. 2~:#adjacent do.
        '-' return.
    end.
    first =. ((0{adjacent)-1){Faces
    second =. ((1{adjacent)-1){Faces
    if. (first has_directed edge)=second has_directed edge do.
        'inconsistent' return.
    end.
    third =. {.(3{.second)-.edge
    origin =. ((0{first)-1){Points
    signed =. ((((third-1){Points)-origin)dot first normal Points)
    if. signed<0 do.
        'convex'
    elseif. signed>0 do.
        'concave'
    else.
        'flat'
    end.
)
coherent_loops =: 4 : 0
    mesh =. x
    faces =. y
    edges =. mesh_edges mesh
    edge_faces =. mesh_edge_faces mesh
    loops =. trace_loops (<edges),<mesh_boundary mesh
    for_index. i.#loops do.
        'number component sequence length kind filled' =. index{::loops
        if. kind-:'closed' do.
            forward =. 0
            for_position. i.length do.
                pair =. (position{sequence),((length|position+1){sequence)
                edge =. edges edge_index pair
                face =. (((0{edge{::edge_faces)-1){faces)
                forward =. forward+face has_directed pair
            end.
            kind =. 'mixed'
            if. (forward=0)+.forward=length do.
                kind =. 'coherent'
            end.
            if. forward=0 do.
                sequence =. (1{.sequence),|.}.sequence
            end.
            loop =. (<number),(<component),(<sequence),(<length),(<kind),<filled
            loops =. (<loop)index}loops
        end.
    end.
    loops
)
analyze_source =: 3 : 0
    'SourceLines OriginalPoints Polygons PolygonLines PolygonGroups SourceErrors Ignored' =: read_obj 0
    'Snapped SnapRecords' =: SnapSpacing snap_vertices OriginalPoints
    Representative =: Merge representatives Snapped
    Triangles =: split_polygons (<Polygons),<PolygonLines
    'kept Removed RemovalReasons' =. clean_faces (<Triangles),(<Snapped),(<Representative),(<Degenerate),<Duplicates
    Removed =: Removed
    RemovalReasons =: RemovalReasons
    present =. (#OriginalPoints)$0
    if. KeepUnused do.
        present =. Representative=1+i.#Representative
    else.
        present =. 1 ((~.,3{."1 kept)-1)}present
    end.
    originals =. I.present
    Points =: originals{Snapped
    Renumber =: (1+i.#originals)originals}(#OriginalPoints)$0
    Faces =: 0 6$0x
    for_face. kept do.
        vertices =. ((3{.face)-1){Renumber
        Faces =: Faces,vertices,3}.face
    end.
    FaceGroups =: ((4{"1 Faces)-1){PolygonGroups
    initial =. Faces
    InitialFaces =: #Faces
    BeforeMesh =: analyze_mesh (<Faces),<#Points
    before_edges =. mesh_edges BeforeMesh
    before_edge_faces =. mesh_edge_faces BeforeMesh
    InconsistentBefore =: #inconsistent (<Faces),(<before_edges),<before_edge_faces
    if. Orient do.
        Faces =: repair_orientation (<Faces),(<before_edges),<before_edge_faces
    end.
    InconsistentAfter =: inconsistent (<Faces),(<before_edges),<before_edge_faces
    LoopsBefore =: BeforeMesh coherent_loops Faces
    permitted =. 0=#&>mesh_nonmanifold BeforeMesh
    for_edge. InconsistentAfter do.
        number =. (((0{edge{::before_edge_faces)-1){mesh_face_components BeforeMesh)-1
        permitted =. 0 number}permitted
    end.
    Added =: 0
    for_index. i.#LoopsBefore do.
        'number component sequence length kind filled' =. index{::LoopsBefore
        allowed =. (kind-:'coherent')*.(length>:3)*.(length<:FillHoles)*.(length=#~.sequence)*.(component-1){permitted
        if. allowed do.
            added_faces =. filling sequence
            Faces =: Faces,added_faces
            FaceGroups =: FaceGroups,(#added_faces)$<'fill'
            Added =: Added+#added_faces
            loop =. (<number),(<component),(<sequence),(<length),(<kind),<1
            LoopsBefore =: (<loop)index}LoopsBefore
        end.
    end.
    Mesh =: analyze_mesh (<Faces),<#Points
    edges =. mesh_edges Mesh
    edge_faces =. mesh_edge_faces Mesh
    violations =. inconsistent (<Faces),(<edges),<edge_faces
    Components =: 0$a:
    for_number. i.#mesh_components Mesh do.
        ids =. number{::mesh_components Mesh
        vertices =. number{::mesh_vertices Mesh
        eids =. number{::mesh_component_edges Mesh
        boundary =. number{::mesh_boundary Mesh
        bad_edges =. number{::mesh_nonmanifold Mesh
        bad_vertices =. number{::mesh_bad_vertices Mesh
        closed =. 0=#boundary
        manifold =. (0=#bad_edges)*.0=#bad_vertices
        consistent =. -. +./eids e.violations
        solid =. closed*.manifold*.consistent
        component =. (<number+1),(<ids),(<vertices),(<eids),(<boundary),(<bad_edges),(<bad_vertices),(<closed),(<manifold),(<consistent),(<solid),<i.0
        Components =: Components,<component
    end.
    for_index. i.#Components do.
        component =. index{::Components
        inside =. i.0
        if. c_solid component do.
            for_box. Components do.
                other =. >box
                if. (c_solid other)*.(c_number other)~:c_number component do.
                    samples =. (c_vertices component)-.c_vertices other
                    if. #samples do.
                        sample =. ((0{samples)-1){Points
                        if. winding (<c_faces other),(<Faces),(<Points),<sample do.
                            inside =. inside,c_number other
                        end.
                    end.
                end.
            end.
        end.
        component =. (<inside)11}component
        Components =: (<component)index}Components
    end.
    OutwardComponents =: 0
    if. Outward do.
        for_box. Components do.
            component =. >box
            if. c_solid component do.
                signed =. volume6 (<c_faces component),(<Faces),<Points
                even =. 0=2|#c_inside component
                if. (signed~:0)*.((even*.signed<0)+.((-.even)*.signed>0)) do.
                    for_id. c_faces component do.
                        Faces =: (flip (id-1){Faces)(id-1)}Faces
                    end.
                    OutwardComponents =: OutwardComponents+1
                end.
            end.
        end.
    end.
    FlippedFaces =: +/-.initial-:"1 InitialFaces{.Faces
    copied =. repair_orientation (<Faces),(<edges),<edge_faces
    not_orientable =. inconsistent (<copied),(<edges),<edge_faces
    final_loops =. trace_loops (<edges),<mesh_boundary Mesh
    loop_counts =. (#Components)$0
    for_box. final_loops do.
        location =. (1{::>box)-1
        loop_counts =. (1+location{loop_counts)location}loop_counts
    end.
    Nonplanar =: 0$0
    for_box. Polygons do.
        Nonplanar =: Nonplanar,(>box)polygon_nonplanar Snapped
    end.
    GroupOrder =: ~.PolygonGroups
    if. Added do.
        GroupOrder =: GroupOrder,<'fill'
    end.
    for_index. i.#Components do.
        component =. index{::Components
        ids =. c_faces component
        vertices =. c_vertices component
        eids =. c_edges component
        orientable =. -. +./eids e.not_orientable
        loops =. index{loop_counts
        euler =. ((#vertices)-#eids)+#ids
        genus =. <.((2-euler)-loops)%2
        crosscaps =. (2-euler)-loops
        signed =. volume6 (<ids),(<Faces),<Points
        surface =. area (<ids),(<Faces),<Points
        bounds =. vertices bbox Points
        center =. 0$a:
        if. (c_solid component)*.signed~:0 do.
            center =. centroid (<ids),(<Faces),(<Points),<signed
        end.
        normals =. 0 0 0x
        angles =. 3$0
        for_id. ids do.
            face =. (id-1){Faces
            normals =. normals+face normal Points
            angle =. (;:'acute right obtuse')i.<face triangle_angle Points
            angles =. (1+angle{angles)angle}angles
        end.
        shapes =. 4$0
        degree =. (#Points)$0
        lengths =. i.0
        for_edge. eids do.
            pair =. edge{edges
            shape =. edge_shape (<pair),<edge{::edge_faces
            location =. (;:'convex concave flat inconsistent')i.<shape
            if. location<4 do.
                shapes =. (1+location{shapes)location}shapes
            end.
            degree =. (1+(pair-1){degree)(pair-1)}degree
            lengths =. lengths,pair length2 Points
        end.
        values =. (vertices-1){degree
        component =. component,(<orientable),(<loops),(<euler),(<genus),(<crosscaps),(<signed),(<surface),(<normals),(<bounds),(<center),(<shapes),(<angles),(< <./lengths),(< >./lengths),(< <./values),< >./values
        Components =: (<component)index}Components
    end.
    0
)
section_summary =: 3 : 0
    sizes =. #&>Polygons
    removals =. +/RemovalReasons=/;:'repeated zero_area duplicate'
    merged =. +/Representative~:1+i.#Representative
    filled =. +/5&{::&>LoopsBefore
    solids =. +/c_solid&>Components
    signed =. 0x
    for_box. Components do.
        component =. >box
        if. c_solid component do.
            signed =. signed+c_volume component
        end.
    end.
    values =. text&.>SourceLines,(#OriginalPoints),(#Polygons),(#SourceErrors),Ignored,+/Nonplanar
    result =. (<'[summary]'),(;:'lines vertices polygons errors ignored nonplanar_polygons')fields values
    for_size. /:~~.sizes do.
        result =. result,<'polygon_size ',(text size),' ',text +/sizes=size
    end.
    values =. text&.>(#Triangles),(#SnapRecords),merged,removals,InitialFaces,InconsistentBefore,FlippedFaces,OutwardComponents,(#LoopsBefore),filled,Added,(#Points),(#Faces),(#Components),solids
    result =. result,(;:'triangles snapped merged removed_repeated removed_zero_area removed_duplicate faces inconsistent_before flipped_faces outward_components boundary_loops holes_filled fill_faces final_vertices final_faces components solids')fields values
    total_area =. area (<1+i.#Faces),(<Faces),<Points
    result,(<'total_area ',real_text total_area),<'total_volume ',signed fraction 6
)
section_warnings =: 3 : 0
    (<'[warnings]'),SourceErrors
)
section_cleanup =: 3 : 0
    result =. (<'[cleanup]'),<'snapped ',text #SnapRecords
    for_number. SnapRecords do.
        result =. result,<'snap ',(text number),' ',(listing (number-1){OriginalPoints),' to ',listing (number-1){Snapped
    end.
    merged =. +/Representative~:1+i.#Representative
    result =. result,<'merged ',text merged
    for_original. i.#Representative do.
        if. (original+1)~:original{Representative do.
            continue.
        end.
        members =. 1+I.Representative=original+1
        if. 1<#members do.
            number =. '-'
            if. original{Renumber do.
                number =. text original{Renumber
            end.
            result =. result,<'merge ',number,' ',listing members
        end.
    end.
    result =. result,<'removed ',text #Removed
    for_index. i.#Removed do.
        'triangle polygon line' =. 3}.index{Removed
        result =. result,<'remove ',(text triangle),' polygon ',(text polygon),' line ',(text line),' ',index{::RemovalReasons
    end.
    result
)
section_components =: 3 : 0
    result =. 0$a:
    for_box. Components do.
        component =. >box
        ids =. c_faces component
        groups =. GroupOrder#~GroupOrder e.(ids-1){FaceGroups
        result =. result,<'[component ',(text c_number component),']'
        result =. result,<'groups ',names_listing groups
        values =. text&.>(#ids),(#c_vertices component),(#c_edges component),(#c_boundary component),(#c_nonmanifold component),(#c_bad_vertices component),c_loops component
        result =. result,(;:'faces vertices edges boundary_edges nonmanifold_edges nonmanifold_vertices boundary_loops')fields values
        values =. yes&.>(c_closed component),(c_manifold component),(c_orientable component),(c_consistent component),c_solid component
        result =. result,(;:'closed manifold orientable consistent solid')fields values
        result =. result,<'euler ',text c_euler component
        if. -.c_manifold component do.
            result =. result,<'genus -'
        elseif. c_orientable component do.
            result =. result,<'genus ',text c_genus component
        else.
            result =. result,<'crosscaps ',text c_crosscaps component
        end.
        volume =. '-'
        if. c_solid component do.
            volume =. (c_volume component)fraction 6
        end.
        result =. result,<'volume ',volume
        result =. result,<'area ',real_text c_area component
        result =. result,<'normal_sum ',listing c_normal component
        result =. result,<'bbox ',listing c_bbox component
        result =. result,<'inside ',listing c_inside component
        result =. result,<'centroid ',names_listing c_center component
        values =. text&.>(3{.c_shapes component),c_angles component
        result =. result,(;:'convex concave flat acute right obtuse')fields values
        result =. result,<'edge_len2 ',listing (c_edge_min component),c_edge_max component
        result =. result,<'valence ',listing (c_valence_min component),c_valence_max component
    end.
    result
)
section_groups =: 3 : 0
    result =. 0$a:
    face_components =. mesh_face_components Mesh
    for_box. GroupOrder do.
        group =. >box
        polygon_ids =. I.PolygonGroups=<group
        triangle_ids =. I.(<group)=((4{"1 Triangles)-1){PolygonGroups
        ids =. 1+I.FaceGroups=<group
        surface =. area (<ids),(<Faces),<Points
        parts =. /:~~.(ids-1){face_components
        values =. (<text #polygon_ids),(<text #triangle_ids),(<text +/polygon_ids{Nonplanar),(<text #ids),(<real_text surface),<listing parts
        result =. result,<'[group ',group,']'
        result =. result,(;:'polygons triangles nonplanar faces area components')fields values
    end.
    result
)
section_contacts =: 3 : 0
    result =. <'[contacts]'
    for_first_index. i.#Components do.
        first =. first_index{::Components
        for_second_index. (first_index+1)+i.(#Components)-(first_index+1) do.
            second =. second_index{::Components
            a =. c_bbox first
            b =. c_bbox second
            if. -. *./((3{.a)<:3}.b)*.(3{.b)<:3}.a do.
                continue.
            end.
            shared =. +/(c_vertices first)e.c_vertices second
            gap =. _1x
            for_u. c_vertices first do.
                for_v. c_vertices second do.
                    if. u~:v do.
                        delta =. ((u-1){Points)-(v-1){Points
                        distance =. delta dot delta
                        if. (gap<0)+.distance<gap do.
                            gap =. distance
                        end.
                    end.
                end.
            end.
            result =. result,<'contact ',(text c_number first),' ',(text c_number second),' shared ',(text shared),' gap2 ',text gap
        end.
    end.
    result
)
section_edges =: 3 : 0
    edges =. mesh_edges Mesh
    edge_faces =. mesh_edge_faces Mesh
    counts =. 3$0
    shapes =. 4$0
    maximum =. 0
    lengths =. i.0
    for_index. i.#edges do.
        count =. #index{::edge_faces
        location =. 2<.count-1
        counts =. (1+location{counts)location}counts
        maximum =. maximum>.count
        shape =. edge_shape (<index{edges),<index{::edge_faces
        location =. (;:'convex concave flat inconsistent')i.<shape
        if. location<4 do.
            shapes =. (1+location{shapes)location}shapes
        end.
        lengths =. lengths,(index{edges)length2 Points
    end.
    low =. <./lengths
    high =. >./lengths
    shortest =. (lengths i.low){edges
    longest =. (lengths i.high){edges
    values =. text&.>(#edges),counts,maximum,shapes
    result =. (<'[edges]'),(;:'edges boundary manifold nonmanifold max_faces convex concave flat inconsistent')fields values
    result,(<'shortest ',(listing shortest),' len2 ',text low),<'longest ',(listing longest),' len2 ',text high
)
section_valence =: 3 : 0
    degree =. (#Points)$0
    for_pair. mesh_edges Mesh do.
        degree =. (1+(pair-1){degree)(pair-1)}degree
    end.
    used =. degree#~degree>0
    values =. (<text #used),(<text (#Points)-#used),(<text <./used),(<text >./used),<(+/used)fraction #used
    result =. (<'[valence]'),(;:'used isolated min max mean')fields values
    for_value. /:~~.used do.
        result =. result,<'degree ',(text value),' ',text +/used=value
    end.
    result
)
query_vertex =: 3 : 0
    number =. y
    prefix =. 'vertex ',text number
    if. (number<1)+.number>#Points do.
        prefix,' invalid' return.
    end.
    containing =. I.+./"1 number=3{."1 Faces
    degree =. 0
    boundary =. 0
    edges =. mesh_edges Mesh
    edge_faces =. mesh_edge_faces Mesh
    for_index. i.#edges do.
        if. number e.index{edges do.
            degree =. degree+1
            boundary =. boundary+.1=#index{::edge_faces
        end.
    end.
    parts =. /:~~.containing{mesh_face_components Mesh
    fans =. #(number-1){::mesh_fans Mesh
    prefix,' at ',(listing (number-1){Points),' faces ',(text #containing),' valence ',(text degree),' fans ',(text fans),' boundary ',(yes boundary),' components ',listing parts
)
query_face =: 3 : 0
    number =. y
    prefix =. 'face ',text number
    if. (number<1)+.number>#Faces do.
        prefix,' invalid' return.
    end.
    face =. (number-1){Faces
    edges =. mesh_edges Mesh
    edge_faces =. mesh_edge_faces Mesh
    neighbors =. 0$a:
    for_pair. directed face do.
        edge =. edges edge_index pair
        adjacent =. edge{::edge_faces
        if. 1=#adjacent do.
            neighbors =. neighbors,<'-'
        elseif. 3<:#adjacent do.
            neighbors =. neighbors,<'*'
        else.
            neighbors =. neighbors,<text {.adjacent-.number
        end.
    end.
    polygon =. '-'
    line =. '-'
    if. 4{face do.
        polygon =. text 4{face
        line =. text 5{face
    end.
    prefix,' vertices ',(listing 3{.face),' group ',((number-1){::FaceGroups),' polygon ',polygon,' line ',line,' component ',(text (number-1){mesh_face_components Mesh),' normal ',(listing face normal Points),' area ',(real_text area (<,number),(<Faces),<Points),' neighbors ',names_listing neighbors
)
query_edge =: 3 : 0
    pair =. /:~y
    prefix =. 'edge ',listing pair
    edges =. mesh_edges Mesh
    index =. edges edge_index pair
    if. index=#edges do.
        prefix,' none' return.
    end.
    adjacent =. index{::mesh_edge_faces Mesh
    kind =. 'nonmanifold'
    if. 1=#adjacent do.
        kind =. 'boundary'
    elseif. 2=#adjacent do.
        kind =. 'manifold'
    end.
    prefix,' faces ',(listing adjacent),' kind ',kind,' shape ',(edge_shape (<pair),<adjacent),' len2 ',text pair length2 Points
)
query_point =: 3 : 0
    inside =. i.0
    total =. 0
    for_box. Components do.
        component =. >box
        if. c_solid component do.
            value =. winding (<c_faces component),(<Faces),(<Points),<y
            if. value~:0 do.
                inside =. inside,c_number component
                total =. total+value
            end.
        end.
    end.
    'point ',(listing y),' inside ',(listing inside),' winding ',text total
)
query_path =: 3 : 0
    'start target' =. y
    prefix =. 'path ',listing y
    if. +./(y<1)+.y>#Points do.
        prefix,' invalid' return.
    end.
    neighbors =. (#Points)$<i.0
    for_pair. mesh_edges Mesh do.
        'a b' =. pair-1
        neighbors =. (<(a{::neighbors),b+1)a}neighbors
        neighbors =. (<(b{::neighbors),a+1)b}neighbors
    end.
    parent =. 0 (start-1)}(#Points)$_1
    queue =. ,start
    head =. 0
    while. head<#queue do.
        current =. head{queue
        head =. head+1
        for_other. /:~(current-1){::neighbors do.
            if. 0>(other-1){parent do.
                parent =. current (other-1)}parent
                queue =. queue,other
            end.
        end.
    end.
    if. 0>(target-1){parent do.
        prefix,' none' return.
    end.
    path =. i.0
    current =. target
    while. current~:0 do.
        path =. current,path
        current =. (current-1){parent
    end.
    prefix,' hops ',(text (#path)-1),' vertices ',listing path
)
query_view =: 3 : 0
    scores =. i.0
    for_face. Faces do.
        scores =. scores,(face normal Points)dot y
    end.
    silhouette =. 0
    for_box. mesh_edge_faces Mesh do.
        adjacent =. >box
        if. 2=#adjacent do.
            'a b' =. (adjacent-1){scores
            if. ((a>0)*.b<0)+.((a<0)*.b>0) do.
                silhouette =. silhouette+1
            end.
        end.
    end.
    'view ',(listing y),' front ',(text +/scores>0),' back ',(text +/scores<0),' side ',(text +/scores=0),' silhouette ',text silhouette
)
section_queries =: 3 : 0
    result =. <'[queries]'
    for_box. Queries do.
        'kind args' =. >box
        select. kind
        case. 'vertex' do.
            answer =. query_vertex {.args
        case. 'face' do.
            answer =. query_face {.args
        case. 'edge' do.
            answer =. query_edge args
        case. 'point' do.
            answer =. query_point args
        case. 'path' do.
            answer =. query_path args
        case. 'view' do.
            answer =. query_view args
        end.
        result =. result,<answer
    end.
    result
)
components_csv =: 3 : 0
    result =. <'component,faces,vertices,closed,euler,genus,volume6,area'
    for_box. Components do.
        component =. >box
        genus =. '-'
        volume =. '-'
        if. (c_manifold component)*.c_orientable component do.
            genus =. text c_genus component
        end.
        if. c_solid component do.
            volume =. text c_volume component
        end.
        values =. (<text c_number component),(<text #c_faces component),(<text #c_vertices component),(<yes c_closed component),(<text c_euler component),(<genus),(<volume),<real_text c_area component
        result =. result,<','join values
    end.
    result
)
boundaries_report =: 3 : 0
    result =. <'loops ',text #LoopsBefore
    for_box. LoopsBefore do.
        'number component sequence length kind filled' =. >box
        state =. filled{::'kept';'filled'
        result =. result,<'loop ',(text number),' component ',(text component),' length ',(text length),' ',kind,' ',state,' vertices ',listing sequence
    end.
    edges =. mesh_edges BeforeMesh
    edge_faces =. mesh_edge_faces BeforeMesh
    bad_edges =. I.3<:#&>edge_faces
    result =. result,<'nonmanifold_edges ',text #bad_edges
    for_index. bad_edges do.
        result =. result,<'edge ',(listing index{edges),' faces ',listing index{::edge_faces
    end.
    vertices =. mesh_global_bad BeforeMesh
    result =. result,<'nonmanifold_vertices ',text #vertices
    for_vertex. vertices do.
        fans =. (vertex-1){::mesh_fans BeforeMesh
        parts =. i.0
        for_box. fans do.
            part =. >box
            parts =. parts,((({.part)-1){mesh_face_components BeforeMesh)
        end.
        result =. result,<'vertex ',(text vertex),' fans ',(text #fans),' components ',listing /:~~.parts
    end.
    result =. result,<'inconsistent_edges ',text #InconsistentAfter
    for_index. InconsistentAfter do.
        result =. result,<'edge ',(listing index{edges),' faces ',listing index{::edge_faces
    end.
    result
)
save_lines =: 4 : 0
    content =. ''
    for_box. y do.
        content =. content,(>box),LF
    end.
    content 1!:2 <'output/',x
)
run =: 3 : 0
    read_parameters 0
    analyze_source 0
    result =. 0$a:
    for_box. Sections do.
        select. >box
        case. 'summary' do.
            result =. result,section_summary 0
        case. 'warnings' do.
            result =. result,section_warnings 0
        case. 'cleanup' do.
            result =. result,section_cleanup 0
        case. 'components' do.
            result =. result,section_components 0
        case. 'groups' do.
            result =. result,section_groups 0
        case. 'contacts' do.
            result =. result,section_contacts 0
        case. 'edges' do.
            result =. result,section_edges 0
        case. 'valence' do.
            result =. result,section_valence 0
        case. 'queries' do.
            result =. result,section_queries 0
        end.
    end.
    try.
        1!:5 <'output'
    catch.
    end.
    'report.txt'save_lines result
    'components.csv'save_lines components_csv 0
    'boundaries.txt'save_lines boundaries_report 0
    'repaired.obj'save_lines repaired_obj (<Points),(<Faces),<FaceGroups
    0
)
run 0
