load 'rational.ijs'
load 'intersections.ijs'
load 'rings.ijs'
load 'greiner_hormann.ijs'
load 'render.ijs'

Kinds =: ;:'UNION INTERSECTION DIFFERENCE XOR CLIP AREA MOVE ROTATE MIRROR SNAP LOCATE RENDER'
WordCounts =: 3 3 3 3 3 2 5 6 5 3 4 8
integer =: 3 : 0
    text =. ,":y
    '-'(I.text='_')}text
)
parse_integer =: 3 : 'x:". ''_''(I.y=''-'')}y'
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
words =: 3 : '<;._1 '' '',y'
records =: 3 : 0
    result =. 0$a:
    lines =. <;._2 (1!:1 <'input/',y)
    for_i. i.#lines do.
        line =. i{::lines
        if. 0=#line do.
            continue.
        end.
        if. '#'~:{.line do.
            result =. result,<( <i+1),<line
        end.
    end.
    result
)
digits =: 3 : '(0<#y)*.(9>:#y)*.*/y e.''0123456789'''
integer_word =: 3 : 0
    text =. y
    if. #text do.
        if. '-'={.text do.
            text =. }.text
        end.
    end.
    digits text
)
valid_name =: 3 : '(0<#y)*.(16>:#y)*.*/y e.''abcdefghijklmnopqrstuvwxyz0123456789_'''
edge_at =: 4 : '(x{y),:((#y)|x+1){y'
parse_rings =: 4 : 0
    rings =. 0$a:
    position =. 0
    while. position<#y do.
        'line text' =. position{::y
        fields =. words text
        if. 2~:#fields do.
            (<line),<0$a: return.
        end.
        header =. 0{::fields
        if. -.(<header)e.'OUTER';'HOLE' do.
            (<line),<0$a: return.
        end.
        if. -.digits 1{::fields do.
            (<line),<0$a: return.
        end.
        count =. parse_integer 1{::fields
        if. count<1 do.
            (<line),<0$a: return.
        end.
        if. ((header-:'OUTER')*.0<#rings)+.((header-:'HOLE')*.0=#rings) do.
            (<line),<0$a: return.
        end.
        position =. position+1
        ring =. 0 2$0x
        remaining =. count
        while. remaining>0 do.
            if. position=#y do.
                (<x),<0$a: return.
            end.
            'line text' =. position{::y
            fields =. words text
            if. 2~:#fields do.
                (<line),<0$a: return.
            end.
            if. -.*/integer_word&>fields do.
                (<line),<0$a: return.
            end.
            ring =. ring,parse_integer&>fields
            position =. position+1
            remaining =. remaining-1
        end.
        rings =. rings,<ring
    end.
    if. 0=#rings do.
        (<x),<0$a:
    else.
        (<0),<rings
    end.
)
check_ring =: 4 : 0
    ring =. y
    count =. #ring
    suffix =. ' ring ',integer x
    if. count<3 do.
        'too_few_vertices',suffix return.
    end.
    seen =. 0 2$0x
    for_point. ring do.
        if. +./(point<0)+.point>1000 do.
            'out_of_range',suffix,' ',point_text point return.
        end.
    end.
    for_point. ring do.
        if. +./point-:"1 seen do.
            'duplicate_vertex',suffix,' ',point_text point return.
        end.
        seen =. seen,point
    end.
    for_i. i.count do.
        a =. (count|i-1){ring
        b =. i{ring
        c =. (count|i+1){ring
        if. 0=cross a,b,:c do.
            'collinear',suffix,' ',point_text b return.
        end.
    end.
    for_i. i.count do.
        for_j. (i+2)+i.0>.count-(i+2) do.
            if. (i=0)*.j=count-1 do.
                continue.
            end.
            a =. i edge_at ring
            b =. j edge_at ring
            if. touch a,b do.
                'self_intersection',suffix,' ',(segment_text a),' ',segment_text b return.
            end.
        end.
    end.
    ''
)
check_polygon =: 3 : 0
    for_i. i.#y do.
        error =. (i+1)check_ring i{::y
        if. #error do.
            error return.
        end.
    end.
    for_i. i.#y do.
        a =. i{::y
        for_j. (i+1)+i.(#y)-(i+1) do.
            b =. j{::y
            for_e. i.#a do.
                first =. e edge_at a
                for_f. i.#b do.
                    second =. f edge_at b
                    if. touch first,second do.
                        prefix =. 'rings_touch rings ',(integer i+1),' ',integer j+1
                        prefix,' ',(segment_text first),' ',segment_text second return.
                    end.
                end.
            end.
        end.
    end.
    outer =. 0{::y
    for_i. 1+i.(#y)-1 do.
        point =. 0{i{::y
        if. -.outer inside point do.
            'hole_outside ring ',(integer i+1),' ',point_text point return.
        end.
    end.
    for_i. 1+i.(#y)-1 do.
        for_j. (i+1)+i.(#y)-(i+1) do.
            a =. i{::y
            b =. j{::y
            if. a inside 0{b do.
                point =. 0{b
            elseif. b inside 0{a do.
                point =. 0{a
            else.
                continue.
            end.
            'hole_in_hole rings ',(integer i+1),' ',(integer j+1),' ',point_text point return.
        end.
    end.
    ''
)
new_polygon =: 4 : 0
    outer =. 1 normalize_ring 0{::y
    holes =. 0$a:
    for_ring. }.y do.
        holes =. holes,<0 normalize_ring >ring
    end.
    canonical =. (<outer),sort_rings holes
    (<x),(<y),<canonical
)
define_polygon =: 3 : 0
    name =. 0{::y
    UsedNames =: UsedNames,<name
    PolygonNames =: PolygonNames,<name
    Polygons =: Polygons,<y
)
read_polygons =: 3 : 0
    UsedNames =: 0$a:
    PolygonNames =: 0$a:
    Polygons =: 0$a:
    InvalidBlocks =: 0$a:
    BlockCount =: 0
    ValidBlocks =: 0
    lines =. records 'polygons.txt'
    position =. 0
    while. position<#lines do.
        'start_line header' =. position{::lines
        name =. 1{::words header
        position =. position+1
        content =. 0$a:
        while. -. 'END'-:1{::position{::lines do.
            content =. content,position{lines
            position =. position+1
        end.
        end_line =. 0{::position{::lines
        position =. position+1
        BlockCount =: BlockCount+1
        error =. ''
        if. (<name)e.UsedNames do.
            error =. 'duplicate_name line ',integer start_line
        else.
            UsedNames =: UsedNames,<name
            'error_line sequence' =. end_line parse_rings content
            if. error_line do.
                error =. 'format line ',integer error_line
            else.
                error =. check_polygon sequence
            end.
            if. 0=#error do.
                PolygonNames =: PolygonNames,<name
                Polygons =: Polygons,<name new_polygon sequence
                ValidBlocks =: ValidBlocks+1
            end.
        end.
        if. #error do.
            InvalidBlocks =: InvalidBlocks,<( <name),<error
        end.
    end.
)
resolve_polygon =: 3 : 0
    if. -.(<y)e.UsedNames do.
        (<'unknown_polygon ',y),<0$a: return.
    end.
    index =. PolygonNames i.<y
    if. index=#PolygonNames do.
        (<'invalid_polygon ',y),<0$a: return.
    end.
    (<''),index{Polygons
)
resolve_target =: 3 : 0
    if. '@'={.y do.
        text =. }.y
        if. digits text do.
            number =. parse_integer text
            if. number<#Regions do.
                region =. number{::Regions
                if. #region do.
                    (<''),<region return.
                end.
            end.
        end.
        (<'bad_target ',y),<0$a: return.
    end.
    'error polygon' =. resolve_polygon y
    if. #error do.
        (<error),<0$a: return.
    end.
    polygons =. ,<2{::polygon
    region =. (<polygons),<0$a:
    (<''),<region
)
arguments_valid =: 3 : 0
    kind =. 0{::y
    index =. Kinds i.<kind
    if. (#y)~:index{WordCounts do.
        0 return.
    end.
    if. index<6 do.
        1 return.
    end.
    if. index e.6 7 8 9 do.
        if. -.valid_name _1{::y do.
            0 return.
        end.
    end.
    select. kind
    case. 'SNAP' do. 1
    case. 'MIRROR' do.
        axis =. 2{::y
        if. -.(axis-:,'x')+.axis-:,'y' do.
            0 return.
        end.
        text =. 3{::y
        if. -.integer_word text do.
            0 return.
        end.
        value =. parse_integer text
        (value>:0)*.value<:1000
    case. 'MOVE';'ROTATE';'LOCATE';'RENDER' do.
        fields =. 2}.y
        if. kind-:'MOVE' do.
            fields =. 2{.fields
        elseif. kind-:'ROTATE' do.
            fields =. 3{.fields
        end.
        if. -.*/integer_word&>fields do.
            0 return.
        end.
        values =. parse_integer&>fields
        select. kind
        case. 'MOVE' do. (*/values>:_1000)*.*/values<:1000
        case. 'ROTATE' do.
            'cx cy q' =. values
            (cx>:0)*.(cx<:1000)*.(cy>:0)*.(cy<:1000)*.(q>:1)*.q<:3
        case. 'LOCATE' do. (*/values>:0)*.*/values<:1000
        case. 'RENDER' do.
            'x0 y0 cw ch columns rows' =. values
            good =. (x0>:0)*.(y0>:0)*.(cw>:1)*.(cw<:100)*.(ch>:1)*.ch<:100
            good =. good*.(columns>:1)*.(columns<:100)*.(rows>:1)*.rows<:60
            good*.(1000>:x0+cw*columns)*.1000>:y0+ch*rows
        end.
    end.
)
all_edges =: 3 : 0
    result =. 0$a:
    for_ring. y do.
        ring =. >ring
        for_edge. i.#ring do.
            result =. result,<edge edge_at ring
        end.
    end.
    result
)
general_position =: 4 : 0
    first_vertices =. ;2{::x
    second_vertices =. ;2{::y
    for_point. first_vertices do.
        if. +./point-:"1 second_vertices do.
            'shared_vertex ',point_text point return.
        end.
    end.
    first_edges =. all_edges 2{::x
    second_edges =. all_edges 2{::y
    for_a. first_edges do.
        for_b. second_edges do.
            if. overlap (>a),>b do.
                'overlapping_edges ',(segment_text >a),' ',segment_text >b return.
            end.
        end.
    end.
    operands =. (<x),<y
    vertices =. (<first_vertices),<second_vertices
    edges =. (<first_edges),<second_edges
    for_side. i.2 do.
        source =. side{::operands
        other =. (1-side){::operands
        for_point. side{::vertices do.
            for_edge. (1-side){::edges do.
                edge =. >edge
                if. point on_segment edge do.
                    line =. 'vertex_on_edge ',(0{::source),' ',point_text point
                    line,' ',(0{::other),' ',segment_text edge return.
                end.
            end.
        end.
    end.
    ''
)
transformed_rings =: 4 : 0
    polygon =. x
    fields =. y
    kind =. 0{::fields
    result =. 0$a:
    for_ring. 1{::polygon do.
        transformed =. 0 2$0x
        for_point. >ring do.
            'xx yy' =. point
            select. kind
            case. 'MOVE' do.
                xx =. xx+parse_integer 2{::fields
                yy =. yy+parse_integer 3{::fields
            case. 'ROTATE' do.
                'cx cy q' =. parse_integer&>3{.2}.fields
                for_turn. i.q do.
                    old_x =. xx
                    xx =. cx-(yy-cy)
                    yy =. cy+(old_x-cx)
                end.
            case. 'MIRROR' do.
                center =. parse_integer 3{::fields
                if. 'x'={.2{::fields do.
                    xx =. (2*center)-xx
                else.
                    yy =. (2*center)-yy
                end.
            end.
            transformed =. transformed,xx,yy
        end.
        result =. result,<transformed
    end.
    result
)
check_operation =: 3 : 0
    fields =. y
    kind =. 0{::fields
    index =. Kinds i.<kind
    CheckedFirst =: 0$a:
    CheckedSecond =: 0$a:
    CheckedTarget =: 0$a:
    CheckedDefined =: 0$a:
    if. index=#Kinds do.
        'unknown_operation ',kind return.
    end.
    if. -.arguments_valid fields do.
        'bad_arguments' return.
    end.
    if. index<9 do.
        'error polygon' =. resolve_polygon 1{::fields
        if. #error do.
            error return.
        end.
        CheckedFirst =: polygon
        if. index<5 do.
            'error polygon' =. resolve_polygon 2{::fields
            if. #error do.
                error return.
            end.
            CheckedSecond =: polygon
        end.
    else.
        'error target' =. resolve_target 1{::fields
        if. #error do.
            error return.
        end.
        CheckedTarget =: target
    end.
    if. index e.6 7 8 9 do.
        name =. _1{::fields
        if. (<name)e.UsedNames do.
            'duplicate_name ',name return.
        end.
    end.
    if. index=9 do.
        if. 1~:#0{::CheckedTarget do.
            'not_single ',1{::fields return.
        end.
    end.
    if. index=4 do.
        window =. 2{::CheckedSecond
        convex =. 1=#window
        ring =. 0{::window
        for_i. i.#ring do.
            a =. ((#ring)|i-1){ring
            b =. i{ring
            c =. ((#ring)|i+1){ring
            convex =. convex*.0<cross a,b,:c
        end.
        if. -.convex do.
            'not_convex ',2{::fields return.
        end.
    end.
    if. index<5 do.
        error =. CheckedFirst general_position CheckedSecond
        if. #error do.
            error return.
        end.
    end.
    if. index e.6 7 8 do.
        sequence =. CheckedFirst transformed_rings fields
        for_ring. sequence do.
            if. +./,(0> >ring)+.1000< >ring do.
                'out_of_range ',_1{::fields return.
            end.
        end.
        CheckedDefined =: (_1{::fields)new_polygon sequence
    elseif. index=9 do.
        sequence =. 0{::0{::CheckedTarget
        rounded =. 0$a:
        for_ring. sequence do.
            rounded =. rounded,<<.(>ring)+1r2
        end.
        error =. check_polygon rounded
        if. #error do.
            'invalid_result ',error return.
        end.
        CheckedDefined =: (_1{::fields)new_polygon rounded
    end.
    ''
)
total_area =: 3 : 0
    total =. 0.0
    for_polygon. y do.
        for_ring. >polygon do.
            total =. total+ring_area >ring
        end.
    end.
    total
)
binary_result =: 3 : 0
    'kind first second' =. y
    graph =. (2{::first)make_graph 2{::second
    intersection =. assemble graph traverse_graph 0 0
    union =. assemble graph traverse_graph 1 1
    select. kind
    case. 'UNION' do. polygons =. union
    case. 'INTERSECTION';'CLIP' do. polygons =. intersection
    case. 'DIFFERENCE';'XOR' do.
        polygons =. assemble graph traverse_graph 1 0
        if. kind-:'XOR' do.
            reverse =. (2{::second)make_graph 2{::first
            polygons =. polygons,assemble reverse traverse_graph 1 0
            keys =. 0 2$0x
            for_polygon. polygons do.
                keys =. keys,point_key 0{0{::>polygon
            end.
            polygons =. (/:keys){polygons
        end.
    end.
    relation =. 'overlap'
    if. 0=#7{::graph do.
        states =. 9{::graph
        na =. +/0{::states
        nb =. +/1{::states
        if. (na=#2{::first)*.nb=0 do.
            relation =. 'within'
        elseif. (nb=#2{::second)*.na=0 do.
            relation =. 'contains'
        elseif. (na=0)*.nb=0 do.
            relation =. 'disjoint'
        end.
    end.
    iou =. (total_area intersection)%total_area union
    operands =. (<first),<second
    region =. (<polygons),<operands
    (<region),(<graph),(<relation),<iou
)
cyclic_equal =: 4 : 0
    if. (#x)~:#y do.
        0 return.
    end.
    for_start. i.#y do.
        if. x-:start|.y do.
            1 return.
        end.
    end.
    0
)
crosscheck_clip =: 4 : 0
    'first window' =. x
    clipped =. 0$a:
    window_ring =. 0{::2{::window
    for_ring. 2{::first do.
        points =. >ring
        for_edge. i.#window_ring do.
            segment =. edge edge_at window_ring
            replacement =. 0 2$0x
            for_i. i.#points do.
                previous =. ((#points)|i-1){points
                current =. i{points
                a =. cross segment,previous
                b =. cross segment,current
                if. (a>0)~:b>0 do.
                    replacement =. replacement,((previous,:current)clipping_point a,b)
                end.
                if. b>0 do.
                    replacement =. replacement,current
                end.
            end.
            points =. replacement
        end.
        if. #points do.
            keep =. +./"1 points~:_1|.points
            points =. keep#points
            if. 3<:#points do.
                clipped =. clipped,<points
            end.
        end.
    end.
    rings =. ;y
    matches =. (#rings)=#clipped
    for_ring. rings do.
        found =. 0
        for_other. clipped do.
            found =. found+.(>ring)cyclic_equal >other
        end.
        matches =. matches*.found
    end.
    decision =. 'mismatch'
    if. matches do.
        decision =. 'match'
    end.
    (<decision),(<#clipped),<+/#&>clipped
)
result_values =: 4 : 0
    'first second' =. x
    first_vertices =. ;2{::first
    second_vertices =. 0 2$0x
    if. #second do.
        second_vertices =. ;2{::second
    end.
    polygon_count =. #y
    ring_count =. +/#&>y
    hole_count =. ring_count-polygon_count
    vertex_count =. 0
    area =. 0.0
    perimeter =. 0.0
    sx =. 0.0
    sy =. 0.0
    origins =. 3$0
    vertices =. 0 2$0x
    ring_lines =. 0$a:
    for_pi. i.#y do.
        polygon =. pi{::y
        for_ri. i.#polygon do.
            ring =. ri{::polygon
            value =. ring_area ring
            area =. area+value
            perimeter =. perimeter+ring_perimeter ring
            vertex_count =. vertex_count+#ring
            vertices =. vertices,ring
            if. ri=0 do.
                line =. 'outer ',integer pi+1
            else.
                line =. 'hole ',(integer pi+1),' ',integer ri
            end.
            line =. line,' ',(integer #ring),' ',3 format_real value
            ring_lines =. ring_lines,<line,' ',' 'join <@point_text"1 ring
            for_index. i.#ring do.
                a =. index{ring
                b =. ((#ring)|index+1){ring
                origin =. 2
                if. +./a-:"1 first_vertices do.
                    origin =. 0
                elseif. +./a-:"1 second_vertices do.
                    origin =. 1
                end.
                origins =. (1+origin{origins)origin}origins
                'x1 y1' =. real"0 a
                'x2 y2' =. real"0 b
                c =. (x1*y2)-x2*y1
                sx =. sx+(x1+x2)*c
                sy =. sy+(y1+y2)*c
            end.
        end.
    end.
    line =. 'polygons ',(integer polygon_count),' rings ',(integer ring_count),' holes ',integer hole_count
    lines =. (<line,' vertices ',(integer vertex_count),' area ',3 format_real area),ring_lines
    if. #vertices do.
        low =. <./vertices
        high =. >./vertices
        lines =. lines,<'bbox ',(point_text low),' ',point_text high
        cx =. sx%6.0*area
        cy =. sy%6.0*area
        lines =. lines,<'centroid (',(3 format_real cx),',',(3 format_real cy),')'
    else.
        lines =. lines,'bbox none';'centroid none'
    end.
    lines =. lines,<'perimeter ',3 format_real perimeter
    line =. 'origins a ',(integer 0{origins),' b ',integer 1{origins
    lines =. lines,<line,' crossing ',integer 2{origins
    (<lines),(<ring_count),(<hole_count),(<vertex_count),<area
)
convex_hull =: 3 : 0
    ordered =. (/:y){y
    chains =. 0$a:
    for_direction. i.2 do.
        sequence =. ordered
        if. direction do.
            sequence =. |.ordered
        end.
        chain =. 0 2$0x
        for_point. sequence do.
            while. 1<#chain do.
                if. 0<cross (_2{chain),(_1{chain),:point do.
                    break.
                end.
                chain =. }:chain
            end.
            chain =. chain,point
        end.
        chains =. chains,<chain
    end.
    (}:0{::chains),}:1{::chains
)
exact_double_area =: 3 : 0
    total =. 0x
    for_index. i.#y do.
        'x1 y1' =. index{y
        'x2 y2' =. ((#y)|index+1){y
        total =. total+(x1*y2)-x2*y1
    end.
    total
)
property_lines =: 4 : 0
    polygon =. x
    orientations =. 0$a:
    for_ring. 1{::polygon do.
        orientation =. 'cw'
        if. 0<exact_double_area >ring do.
            orientation =. 'ccw'
        end.
        orientations =. orientations,<orientation
    end.
    reflex =. 0
    for_ring. 2{::polygon do.
        ring =. >ring
        for_index. i.#ring do.
            a =. ((#ring)|index-1){ring
            b =. index{ring
            c =. ((#ring)|index+1){ring
            reflex =. reflex+0>cross a,b,:c
        end.
    end.
    hull =. convex_hull 0{::2{::polygon
    hull_area =. real (exact_double_area hull)%2
    line =. 'hull ',(integer #hull),' ',3 format_real hull_area
    lines =. (<'input ',' 'join orientations),<'reflex ',integer reflex
    lines,<line,' solidity ',6 format_real y%hull_area
)
locate =: 4 : 0
    point =. y
    for_pi. i.#x do.
        polygon =. pi{::x
        for_ri. i.#polygon do.
            if. (ri{::polygon)boundary point do.
                if. ri=0 do.
                    'boundary outer ',integer pi+1 return.
                else.
                    'boundary hole ',(integer pi+1),' ',integer ri return.
                end.
            end.
        end.
    end.
    for_pi. i.#x do.
        polygon =. pi{::x
        if. (0{::polygon)inside point do.
            in_hole =. 0
            for_hole. }.polygon do.
                in_hole =. in_hole+.(>hole)inside point
            end.
            if. -.in_hole do.
                'inside polygon ',integer pi+1 return.
            end.
        end.
    end.
    'outside'
)
operand_location =: 4 : 0
    rings =. 2{::x
    for_ring. rings do.
        if. (>ring)boundary y do.
            'boundary' return.
        end.
    end.
    if. rings interior y do.
        'inside'
    else.
        'outside'
    end.
)
record_region =: 3 : 0
    'number line fields' =. y
    kind =. 0{::fields
    index =. Kinds i.<kind
    ResultLines =: ResultLines,<'op ',(integer number),' ',line
    if. index<5 do.
        first =. CheckedFirst
        second =. CheckedSecond
        'region graph relation iou' =. binary_result(<kind),(<first),<second
        ResultLines =: ResultLines,<'relation ',relation,' iou ',6 format_real iou
        order =. 7{::graph
        ResultLines =: ResultLines,<'crossings ',integer #order
        CrossingTotal =: CrossingTotal+#order
        for_node. order do.
            direction =. 'out'
            if. node{6{::graph do.
                direction =. 'in'
            end.
            point =. node{0{::graph
            ResultLines =: ResultLines,<'crossing ',(point_text point),' ',direction
        end.
    else.
        first =. CheckedFirst
        if. index e.6 7 8 9 do.
            first =. CheckedDefined
        end.
        second =. 0$a:
        polygons =. ,<2{::first
        region =. (<polygons),<0$a:
    end.
    Regions =: (<region)number}Regions
    polygons =. 0{::region
    'value_lines rings holes vertices area' =. ((<first),<second)result_values polygons
    ResultLines =: ResultLines,value_lines
    if. index>:5 do.
        ResultLines =: ResultLines,first property_lines area
    end.
    if. index=4 do.
        'decision count vertices_sh' =. ((<first),<second)crosscheck_clip polygons
        line =. 'crosscheck ',decision,' rings ',integer count
        ResultLines =: ResultLines,<line,' vertices ',integer vertices_sh
    end.
    identifier =. (integer number),':',':'join fields
    csv =. identifier,',',(integer rings),',',(integer holes),',',integer vertices
    AreaLines =: AreaLines,<csv,',',3 format_real area
)
record_location =: 3 : 0
    'number line fields' =. y
    point =. parse_integer&>2}.fields
    'polygons operands' =. CheckedTarget
    ResultLines =: ResultLines,<'op ',(integer number),' ',line
    ResultLines =: ResultLines,<'location ',polygons locate point
    if. #operands do.
        a =. (0{::operands)operand_location point
        b =. (1{::operands)operand_location point
        ResultLines =: ResultLines,<'operands a ',a,' b ',b
    end.
)
record_render =: 3 : 0
    'number line fields' =. y
    parameters =. parse_integer&>2}.fields
    'lines counts' =. CheckedTarget render_grid parameters
    'x0 y0 cw ch columns rows' =. parameters
    line =. 'render ',(integer number),' ',(1{::fields),' cols ',(integer columns),' rows ',integer rows
    line =. line,' result ',(integer 0{counts),' a ',(integer 1{counts),' b ',integer 2{counts
    RenderLines =: RenderLines,(<line,' both ',integer 3{counts),lines
)
summary_lines =: 3 : 0
    line =. 'summary polygons ',(integer BlockCount),' valid ',integer ValidBlocks
    ResultLines =: ResultLines,<line,' invalid ',(integer #InvalidBlocks),' defined ',integer DefinedCount
    line =. 'summary operations ',(integer OperationCount),' succeeded ',integer Succeeded
    ResultLines =: ResultLines,<line,' rejected ',integer #RejectedOperations
    ResultLines =: ResultLines,<'summary crossings ',integer CrossingTotal
    for_i. i.#Kinds do.
        line =. 'kind ',(i{::Kinds),' ',integer i{KindTotals
        ResultLines =: ResultLines,<line,' ',integer i{KindSucceeded
    end.
)
write_lines =: 4 : 0
    text =. ''
    if. #y do.
        text =. (LF join y),LF
    end.
    text 1!:2 <'output/',x
)
run =: 3 : 0
    read_polygons ''
    operations =. records 'operations.txt'
    OperationCount =: #operations
    Regions =: (OperationCount+1)$<0$a:
    ResultLines =: 0$a:
    AreaLines =: <'operation,rings,holes,vertices,area'
    RenderLines =: 0$a:
    RejectedOperations =: 0$a:
    KindTotals =: (#Kinds)$0
    KindSucceeded =: (#Kinds)$0
    Succeeded =: 0
    DefinedCount =: 0
    CrossingTotal =: 0
    for_number. 1+i.OperationCount do.
        line =. 1{::(number-1){::operations
        fields =. words line
        kind =. 0{::fields
        index =. Kinds i.<kind
        if. index<#Kinds do.
            KindTotals =: (1+index{KindTotals)index}KindTotals
        end.
        error =. check_operation fields
        if. #error do.
            RejectedOperations =: RejectedOperations,<( <number),<error
            continue.
        end.
        Succeeded =: Succeeded+1
        KindSucceeded =: (1+index{KindSucceeded)index}KindSucceeded
        if. index e.6 7 8 9 do.
            define_polygon CheckedDefined
            DefinedCount =: DefinedCount+1
        end.
        arguments =. (<number),(<line),<fields
        select. kind
        case. 'RENDER' do. record_render arguments
        case. 'LOCATE' do. record_location arguments
        case. do. record_region arguments
        end.
    end.
    summary_lines ''
    rejected =. <'rejections ',integer (#InvalidBlocks)+#RejectedOperations
    for_block. InvalidBlocks do.
        'name error' =. >block
        rejected =. rejected,<'polygon ',name,' ',error
    end.
    for_operation. RejectedOperations do.
        'number error' =. >operation
        rejected =. rejected,<'op ',(integer number),' ',error
    end.
    try.
        1!:5 <'output'
    catch.
    end.
    'results.txt'write_lines ResultLines
    'areas.csv'write_lines AreaLines
    'render.txt'write_lines RenderLines
    'rejections.txt'write_lines rejected
)
run ''
