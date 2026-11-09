load 'fixed_point.ijs'
load 'vector3.ijs'
load 'scene.ijs'
load 'intersect.ijs'
load 'shading.ijs'
RayKinds =: ;:'primary reflection refraction shadow'
integer =: 3 : 0
    text =. ":y
    '-'(I.text='_')}text
)
join =: 4 : 0
    result =. ''
    for_j. i.#y do.
        if. j do.
            result =. result,x
        end.
        result =. result,j{::y
    end.
    result
)
words =: 3 : ''' ''join integer&.>y'
write_lines =: 4 : 0
    content =. ''
    if. #y do.
        content =. (LF join y),LF
    end.
    content 1!:2 <'output/',x
)
empty_info =: 3 : '(<_1),(<0x),(<3$0x),(<3$0x),(<1),(<3$0x),(<0 3$0x),<0'
new_pixel =: 3 : 0
    'x_coordinate y_coordinate' =. y
    (<x_coordinate),(<y_coordinate),(<0x),(<0),(<1),(<,'.'),(<3$0x),(<3$0x),<empty_info ''
)
union_box =: 3 : 0
    box =. ({.y){::ObjectBounds
    low =. 0{box
    high =. 1{box
    for_index. y do.
        bounds =. index{::ObjectBounds
        low =. low<.0{bounds
        high =. high>.1{bounds
    end.
    low,:high
)
surface_cost =: 3 : 0
    box =. union_box y
    'dx dy dz' =. (1{box)-0{box
    ((dx*dy)+(dy*dz)+dz*dx)*#y
)
axis_order =: 4 : 0
    keys =. 0 2$0x
    for_index. y do.
        box =. index{::ObjectBounds
        center =. (((<0,x){box)+(<1,x){box)floor_div 2
        keys =. keys,center,index
    end.
    y /: keys
)
build =: 3 : 0
    'members depth' =. y
    bounds =. union_box members
    index =. #Nodes
    node =. (<0{bounds),(<1{bounds),(<depth),(<i.0),(<_1),(<_1),<0x
    Nodes =: Nodes,<node
    if. (#members)<:2 do.
        node =. (</:~members)3}node
        Nodes =: (<node)index}Nodes
        LeafDepths =: depth members}LeafDepths
        index return.
    end.
    best_cost =. _1x
    best_left =. best_right =. i.0
    for_axis. i.3 do.
        ordered =. axis axis_order members
        for_split. 1+i.<:#ordered do.
            left =. split{.ordered
            right =. split}.ordered
            cost =. (surface_cost left)+surface_cost right
            if. (best_cost<0)+.cost<best_cost do.
                best_cost =. cost
                best_left =. left
                best_right =. right
            end.
        end.
    end.
    left =. build (<best_left),<depth+1
    right =. build (<best_right),<depth+1
    node =. (<left)4}node
    node =. (<right)5}node
    Nodes =: (<node)index}Nodes
    index
)
prepare =: 3 : 0
    ObjectBounds =: 0$a:
    LeafDepths =: (#Objects)$_1
    Planes =: i.0
    Nodes =: 0$a:
    bounded =. i.0
    for_index. i.#Objects do.
        'label kind material geometry' =. index{::Objects
        bounds =. kind object_bounds (<geometry),<Margin
        ObjectBounds =: ObjectBounds,<bounds
        if. #bounds do.
            bounded =. bounded,index
        else.
            Planes =: Planes,index
        end.
    end.
    Root =: _1
    if. #bounded do.
        Root =: build (<bounded),<0
    end.
    Rays =: 4$0x
    Misses =: 3$0x
    DepthCounts =: (MaxDepth+1)$0x
    Tests =: 4 2$0x
    ObjectCounts =: ((#Objects),3)$0x
    LightCounts =: ((#Lights),6)$0x
    TotalInternal =: Clamped =: Supersampled =: 0x
    Pixels =: 0$a:
    TraceRecords =: 0$a:
    i.0
)
test_node =: 4 : 0
    'kind counted' =. x
    'index origin direction' =. y
    node =. index{::Nodes
    if. counted do.
        Tests =: (1+(<kind,0){Tests)(<kind,0)}Tests
        node =. (<1+6{::node)6}node
        Nodes =: (<node)index}Nodes
    end.
    interval =. slab (0{node),(1{node),(<origin),<direction
    if. #interval do.
        if. (2{interval)>Epsilon do.
            interval return.
        end.
    end.
    i.0x
)
test_object =: 4 : 0
    'kind counted' =. x
    'index origin direction' =. y
    if. counted do.
        Tests =: (1+(<kind,1){Tests)(<kind,1)}Tests
    end.
    'label shape material geometry' =. index{::Objects
    shape candidate (<geometry),(<origin),(<direction),<Epsilon
)
consider =: 4 : 0
    'index origin direction best_object best_hit' =. y
    hit =. x test_object (<index),(<origin),<direction
    take =. 0
    if. #hit do.
        if. (0{hit)<:Far do.
            take =. best_object<0
            if. -.take do.
                take =. ((0{hit)<0{best_hit)+.((0{hit)=0{best_hit)*.index<best_object
            end.
        end.
    end.
    if. take do.
        best_object =. index
        best_hit =. hit
    end.
    (<best_object),<best_hit
)
nearest =: 4 : 0
    'origin direction' =. y
    best_object =. _1
    best_hit =. i.0x
    for_index. Planes do.
        'best_object best_hit' =. x consider (<index),(<origin),(<direction),(<best_object),<best_hit
    end.
    pending =. i.0
    if. Root>:0 do.
        pending =. ,Root
    end.
    while. #pending do.
        index =. {:pending
        pending =. }:pending
        interval =. x test_node (<index),(<origin),<direction
        if. 0=#interval do.
            continue.
        end.
        if. (0{interval)>Far do.
            continue.
        end.
        if. best_object>:0 do.
            if. (0{interval)>0{best_hit do.
                continue.
            end.
        end.
        node =. index{::Nodes
        members =. 3{::node
        if. #members do.
            for_object. members do.
                'best_object best_hit' =. x consider (<object),(<origin),(<direction),(<best_object),<best_hit
            end.
        else.
            pending =. pending,(5{::node),4{::node
        end.
    end.
    (<best_object),<best_hit
)
test_occluder =: 4 : 0
    'index origin direction distance' =. y
    hit =. (3,x)test_object (<index),(<origin),<direction
    if. #hit do.
        if. (0{hit)<distance do.
            if. x do.
                ObjectCounts =: (1+(<index,2){ObjectCounts)(<index,2)}ObjectCounts
            end.
            1 return.
        end.
    end.
    0
)
occluders =: 4 : 0
    'origin direction distance' =. y
    found =. i.0
    for_index. Planes do.
        if. x test_occluder (<index),(<origin),(<direction),<distance do.
            found =. found,index
        end.
    end.
    pending =. i.0
    if. Root>:0 do.
        pending =. ,Root
    end.
    while. #pending do.
        index =. {:pending
        pending =. }:pending
        interval =. (3,x)test_node (<index),(<origin),<direction
        if. 0=#interval do.
            continue.
        end.
        if. (0{interval)>:distance do.
            continue.
        end.
        node =. index{::Nodes
        members =. 3{::node
        if. #members do.
            for_object. members do.
                if. x test_occluder (<object),(<origin),(<direction),<distance do.
                    found =. found,object
                end.
            end.
        else.
            pending =. pending,(5{::node),4{::node
        end.
    end.
    /:~found
)
camera =: 3 : 0
    'qx qy' =. y
    u =. ((qx-2*Width)*0{View)floor_div 2*Width
    v =. (((2*Height)-qy)*1{View)floor_div 2*Height
    direction =. (Forward+Right vscale u)+Up vscale v
    (<Eye),<vnorm direction
)
light_samples =: 4 : 0
    point =. y
    'kind values samples' =. x{::Lights
    intensity =. {:values
    if. kind-:'sun' do.
        1 5$(3{.values),Far,intensity return.
    end.
    positions =. 0 3$0x
    if. kind-:'area' do.
        k =. 9{values
        for_j. i.k do.
            for_i. i.k do.
                position =. (3{.values)+(((1+2*i)*3 4 5{values)floor_div 2*k)+((1+2*j)*6 7 8{values)floor_div 2*k
                positions =. positions,position
            end.
        end.
    else.
        positions =. ,:3{.values
    end.
    result =. 0 5$0x
    for_position. positions do.
        relative =. position-point
        result =. result,(vnorm relative),(vlength relative),intensity floor_div samples
    end.
    result
)
cone =: 4 : 0
    'kind values samples' =. x{::Lights
    if. -.kind-:'spot' do.
        S return.
    end.
    cosine =. -y vdot 3 4 5{values
    if. cosine<:6{values do.
        0x return.
    elseif. cosine>:7{values do.
        S return.
    end.
    ((cosine-6{values)*S)floor_div (7{values)-6{values
)
local_color =: 4 : 0
    counted =. x
    'info direction pixel' =. y
    'object distance point normal front base lighting illumination' =. info
    material =. 1{::(2{::object{::Objects){::Materials
    diffuse_sum =. specular_sum =. 0x
    lighting =. 0 3$0x
    illumination =. 0
    for_index. i.#Lights do.
        lit =. diffuse =. specular =. 0x
        for_sample. index light_samples point do.
            toward =. 3{.sample
            ndl =. normal vdot toward
            if. ndl<:0 do.
                if. counted do.
                    LightCounts =: (1+(<index,4){LightCounts)(<index,4)}LightCounts
                end.
                continue.
            end.
            factor =. index cone toward
            if. factor=0 do.
                if. counted do.
                    LightCounts =: (1+(<index,5){LightCounts)(<index,5)}LightCounts
                end.
                continue.
            end.
            if. counted do.
                Rays =: (1+3{Rays)3}Rays
                pixel =. (<1+2{::pixel)2}pixel
                LightCounts =: (1+(<index,1){LightCounts)(<index,1)}LightCounts
            end.
            blockers =. counted occluders (<point),(<toward),<3{sample
            for_blocker. blockers do.
                blocker_material =. 1{::(2{::blocker{::Objects){::Materials
                factor =. factor fixed_mul 7{blocker_material
            end.
            if. factor=0 do.
                if. counted do.
                    LightCounts =: (1+(<index,2){LightCounts)(<index,2)}LightCounts
                end.
                continue.
            end.
            if. counted*.0<#blockers do.
                LightCounts =: (1+(<index,3){LightCounts)(<index,3)}LightCounts
            end.
            'dif spe' =. phong (<material),(<normal),(<toward),(<-direction),(<ndl),(<4{sample),<factor
            lit =. lit+1
            diffuse =. diffuse+dif
            specular =. specular+spe
        end.
        lighting =. lighting,lit,diffuse,specular
        illumination =. illumination+lit>0
        diffuse_sum =. diffuse_sum+diffuse
        specular_sum =. specular_sum+specular
    end.
    raw =. ((base*(Ambient+diffuse_sum))floor_div S)+(255*specular_sum)floor_div S
    if. counted do.
        Clamped =: Clamped++/raw>255
    end.
    info =. (<lighting)6}info
    info =. (<illumination)7}info
    (<raw<.255),(<info),<pixel
)
trace =: 4 : 0
    'kind depth counted recording' =. x
    'origin direction pixel' =. y
    if. counted do.
        Rays =: (1+kind{Rays)kind}Rays
        DepthCounts =: (1+depth{DepthCounts)depth}DepthCounts
        pixel =. (<1+2{::pixel)2}pixel
        pixel =. (<depth>.3{::pixel)3}pixel
    end.
    if. recording do.
        TraceRecords =: TraceRecords,<'ray ',(kind{::RayKinds),' ',(integer depth),' origin ',(words origin),' direction ',words direction
    end.
    'object hit' =. (kind,counted)nearest (<origin),<direction
    if. object<0 do.
        if. counted do.
            Misses =: (1+kind{Misses)kind}Misses
        end.
        if. recording do.
            TraceRecords =: TraceRecords,(<'miss'),<'color ',words Background
        end.
        (<Background),(<empty_info ''),<pixel return.
    end.
    'label shape material_index_value geometry' =. object{::Objects
    material_record =. material_index_value{::Materials
    material =. 1{::material_record
    point =. origin+direction vscale 0{hit
    outward =. shape outward_normal (<geometry),(<point),(<direction),<hit
    front =. (outward vdot direction)<:0
    normal =. outward
    if. -.front do.
        normal =. -outward
    end.
    base =. ((<material),(2{material_record),3{material_record)base_color point
    info =. (<object),(<0{hit),(<point),(<normal),(<front),(<base),(<0 3$0x),<0
    if. counted do.
        category =. kind~:0
        ObjectCounts =: (1+(<object,category){ObjectCounts)(<object,category)}ObjectCounts
    end.
    'local_value info pixel' =. counted local_color (<info),(<direction),<pixel
    if. recording do.
        TraceRecords =: TraceRecords,<'hit ',label,' t ',(integer 0{hit),' point ',(words point),' normal ',(words normal),' base ',words base
        lighting =. 6{::info
        for_j. i.#Lights do.
            values =. j{lighting
            samples =. 2{::j{::Lights
            TraceRecords =: TraceRecords,<'light ',(integer j+1),' lit ',(integer 0{values),' of ',(integer samples),' diffuse ',(integer 1{values),' specular ',integer 2{values
        end.
        TraceRecords =: TraceRecords,<'local ',words local_value
    end.
    color =. local_value
    if. (depth<MaxDepth)*.(0<6{material)+.0<7{material do.
        'wr wt transmitted internal' =. refraction (<material),(<direction),(<normal),<front
        if. internal do.
            if. counted do.
                TotalInternal =: TotalInternal+1
            end.
            if. recording do.
                TraceRecords =: TraceRecords,<'total_internal_reflection'
            end.
        end.
        local_weight =. (S-6{material)-7{material
        if. recording do.
            TraceRecords =: TraceRecords,<'weights ',words local_weight,wr,wt
        end.
        reflected_color =. refracted_color =. 3$0x
        if. wr>0 do.
            context =. 1,(depth+1),counted,recording
            'reflected_color child pixel' =. context trace (<point),(<direction reflected normal),<pixel
        end.
        if. wt>0 do.
            context =. 2,(depth+1),counted,recording
            'refracted_color child pixel' =. context trace (<point),(<transmitted),<pixel
        end.
        color =. ((<local_value),(<reflected_color),<refracted_color)mix local_weight,wr,wt
    end.
    if. #Fog do.
        factor =. 0x
        if. (0{hit)>:4{Fog do.
            factor =. S
        elseif. (0{hit)>3{Fog do.
            factor =. (((0{hit)-3{Fog)*S)floor_div (4{Fog)-3{Fog
        end.
        color =. ((<color),<3{.Fog)mix (S-factor),factor
    end.
    if. recording do.
        TraceRecords =: TraceRecords,<'color ',words color
    end.
    (<color),(<info),<pixel
)
render =: 3 : 0
    for_y. i.Height do.
        for_x. i.Width do.
            pixel =. new_pixel x,y
            'origin direction' =. camera (2+4*x),2+4*y
            'color info pixel' =. 0 0 1 0 trace (<origin),(<direction),<pixel
            pixel =. (<color)6}pixel
            pixel =. (<color)7}pixel
            pixel =. (<info)8}pixel
            if. (0{::info)>:0 do.
                object =. (0{::info){::Objects
                pixel =. (0{object)5}pixel
                lighting =. 6{::info
                for_j. i.#Lights do.
                    if. (<j,0){lighting do.
                        LightCounts =: (1+(<j,0){LightCounts)(<j,0)}LightCounts
                    end.
                end.
            end.
            Pixels =: Pixels,<pixel
        end.
    end.
    for_index. i.#Pixels do.
        pixel =. index{::Pixels
        x =. 0{::pixel
        y =. 1{::pixel
        boundary =. 0
        for_offset. 4 2$0 _1 0 1 _1 0 1 0 do.
            'nx ny' =. (x,y)+offset
            if. (nx>:0)*.(nx<Width)*.(ny>:0)*.ny<Height do.
                other =. (nx+Width*ny){::Pixels
                difference =. >./|(6{::pixel)-6{::other
                if. (-.(5{::pixel)-:5{::other)+.difference>Contrast do.
                    boundary =. 1
                end.
            end.
        end.
        if. -.boundary do.
            continue.
        end.
        Supersampled =: Supersampled+1
        pixel =. (<4)4}pixel
        sum_color =. 3$0x
        for_offset. 4 2$1 1 3 1 1 3 3 3 do.
            'origin direction' =. camera ((4*x)+0{offset),(4*y)+1{offset
            'color info pixel' =. 0 0 1 0 trace (<origin),(<direction),<pixel
            sum_color =. sum_color+color
        end.
        pixel =. (<sum_color floor_div 4)7}pixel
        Pixels =: (<pixel)index}Pixels
    end.
    i.0
)
distance_range =: 3 : 0
    low =. high =. _1x
    for_pixel. Pixels do.
        hit =. 8{::>pixel
        if. (0{::hit)>:0 do.
            distance =. 1{::hit
            if. low<0 do.
                low =. high =. distance
            else.
                low =. low<.distance
                high =. high>.distance
            end.
        end.
    end.
    if. low<0 do.
        i.0x
    else.
        low,high
    end.
)
mean_color =: 3 : 0
    sum_color =. 3$0x
    for_pixel. y do.
        sum_color =. sum_color+7{::>pixel
    end.
    sum_color floor_div #y
)
netpbm =: 4 : 0
    'name magic' =. x
    rows =. (<magic),(<(integer Width),' ',integer Height),<'255'
    for_row. i.Height do.
        values =. ,((row*Width)+i.Width){y
        rows =. rows,<words values
    end.
    name write_lines rows
)
character_map =: 4 : 0
    rows =. 0$a:
    for_row. i.Height do.
        rows =. rows,<;((row*Width)+i.Width){y
    end.
    x write_lines rows
)
write_images =: 3 : 0
    distances =. distance_range ''
    max_cost =. 0x
    for_pixel. Pixels do.
        max_cost =. max_cost>.2{::>pixel
    end.
    colors =. normals =. albedos =. 0 3$0x
    depths =. costs =. 0 1$0x
    labels =. lights =. ray_depths =. 0$a:
    for_pixel. Pixels do.
        pixel =. >pixel
        colors =. colors,7{::pixel
        costs =. costs,(255*2{::pixel)floor_div max_cost
        labels =. labels,5{pixel
        ray_depths =. ray_depths,<integer 3{::pixel
        hit =. 8{::pixel
        if. (0{::hit)<0 do.
            depths =. depths,0x
            normals =. normals,3$0x
            albedos =. albedos,3$0x
            lights =. lights,<,'.'
        else.
            value =. 255x
            if. (0{distances)~:1{distances do.
                value =. 255-(235*((1{::hit)-0{distances))floor_div (1{distances)-0{distances
            end.
            depths =. depths,value
            normal =. 0>.255<.(((3{::hit)+S)*255)floor_div 2*S
            normals =. normals,normal
            albedos =. albedos,5{::hit
            lights =. lights,<integer 7{::hit
        end.
    end.
    ((<'image.ppm'),<'P3')netpbm colors
    ((<'depth.pgm'),<'P2')netpbm depths
    ((<'normal.ppm'),<'P3')netpbm normals
    ((<'albedo.ppm'),<'P3')netpbm albedos
    ((<'cost.pgm'),<'P2')netpbm costs
    'object_map.txt'character_map labels
    'light_map.txt'character_map lights
    'ray_depth.txt'character_map ray_depths
)
statistics =: 3 : 0
    rows =. (<'image ',(integer Width),' ',integer Height),<'supersampled ',integer Supersampled
    ray_line =. 'rays'
    miss_line =. 'misses'
    for_kind. i.4 do.
        ray_line =. ray_line,' ',(kind{::RayKinds),' ',integer kind{Rays
        if. kind<3 do.
            miss_line =. miss_line,' ',(kind{::RayKinds),' ',integer kind{Misses
        end.
    end.
    rows =. rows,(<ray_line,' total ',integer +/Rays),(<miss_line),<'depth ',words DepthCounts
    for_kind. i.4 do.
        rows =. rows,<'tests ',(kind{::RayKinds),' nodes ',(integer (<kind,0){Tests),' objects ',integer (<kind,1){Tests
    end.
    rows =. rows,(<'total_internal_reflection ',integer TotalInternal),<'clamped ',integer Clamped
    distances =. distance_range ''
    text =. 'none'
    if. #distances do.
        text =. words distances
    end.
    rows =. rows,<'distance ',text
    max_cost =. 0x
    histogram =. 8$0x
    for_pixel. Pixels do.
        pixel =. >pixel
        max_cost =. max_cost>.2{::pixel
        'r g b' =. 7{::pixel
        brightness =. ((299*r)+(587*g)+114*b)floor_div 1000
        bucket =. brightness floor_div 32
        histogram =. (1+bucket{histogram)bucket}histogram
    end.
    rows =. rows,(<'max_pixel_rays ',integer max_cost),(<'mean ',words mean_color Pixels),<'histogram ',words histogram
    for_node. Nodes do.
        'low high depth members left right visits' =. >node
        role =. 'inner'
        if. #members do.
            labels =. ''
            for_index. members do.
                labels =. labels,0{::index{::Objects
            end.
            role =. 'leaf ',labels
        end.
        rows =. rows,<'node ',(integer depth),' ',role,' box ',(words low),' ',(words high),' visits ',integer visits
    end.
    for_index. i.#Objects do.
        'label kind material geometry' =. index{::Objects
        chosen =. 0$a:
        xmin =. Width
        ymin =. Height
        xmax =. ymax =. _1
        for_pixel. Pixels do.
            pixel =. >pixel
            if. label-:5{::pixel do.
                chosen =. chosen,<pixel
                xmin =. xmin<.0{::pixel
                ymin =. ymin<.1{::pixel
                xmax =. xmax>.0{::pixel
                ymax =. ymax>.1{::pixel
            end.
        end.
        box =. color =. 'none'
        if. #chosen do.
            box =. words xmin,ymin,xmax,ymax
            color =. words mean_color chosen
        end.
        counts =. index{ObjectCounts
        rows =. rows,<'object ',label,' ',kind,' primary ',(integer 0{counts),' secondary ',(integer 1{counts),' shadow ',(integer 2{counts),' pixels ',(integer #chosen),' box ',box,' color ',color
    end.
    for_index. i.#Lights do.
        'kind values samples' =. index{::Lights
        counts =. index{LightCounts
        rows =. rows,<'light ',(integer index+1),' ',kind,' samples ',(integer samples),' pixels ',(integer 0{counts),' shadow_rays ',(integer 1{counts),' blocked ',(integer 2{counts),' attenuated ',(integer 3{counts),' backfacing ',(integer 4{counts),' outside ',integer 5{counts
    end.
    rows
)
queries =: 3 : 0
    rows =. 0$a:
    input =. read_lines 'input/queries.txt'
    for_number. i.#input do.
        line =. number{::input
        rows =. rows,<'query ',(integer number+1),' ',line
        fields =. split_words line
        kind =. 0{::fields
        if. kind-:'object' do.
            for_index. i.#Objects do.
                'label shape material geometry' =. index{::Objects
                if. -.label-:1{::fields do.
                    continue.
                end.
                result =. shape,' material ',0{::material{::Materials
                bounds =. index{::ObjectBounds
                if. #bounds do.
                    result =. result,' bounds ',(words ,bounds),' leaf ',integer index{LeafDepths
                else.
                    result =. result,' bounds none leaf none'
                end.
                rows =. rows,<result
                break.
            end.
            continue.
        end.
        values =. integer_value&>}.fields
        if. kind-:'pixel' do.
            pixel =. ((0{values)+Width*1{values){::Pixels
            hit =. 8{::pixel
            distance =. 'none'
            if. (0{::hit)>:0 do.
                distance =. integer 1{::hit
            end.
            rows =. rows,<'label ',(5{::pixel),' distance ',distance,' color ',(words 7{::pixel),' samples ',(integer 4{::pixel),' rays ',integer 2{::pixel
        elseif. (<kind)e.;:'trace ray' do.
            if. kind-:'trace' do.
                'origin direction' =. camera 2+4*values
            else.
                origin =. 3{.values
                direction =. vnorm 3}.values
            end.
            TraceRecords =: 0$a:
            dummy =. new_pixel 0 0
            result =. 0 0 0 1 trace (<origin),(<direction),<dummy
            rows =. rows,TraceRecords
        elseif. kind-:'visible' do.
            relative =. values-Eye
            direction =. vnorm relative
            blockers =. 0 occluders (<Eye),(<direction),<(vlength relative)-Epsilon
            visibility =. 'yes'
            if. #blockers do.
                visibility =. 'no'
            end.
            'object hit' =. 0 0 nearest (<Eye),<direction
            result =. visibility,' first none'
            if. object>:0 do.
                result =. visibility,' first ',(0{::object{::Objects),' t ',integer 0{hit
            end.
            rows =. rows,<result
        elseif. kind-:'shadow' do.
            for_index. i.#Lights do.
                factor_sum =. 0x
                found =. (#Objects)$0
                for_sample. index light_samples values do.
                    direction =. 3{.sample
                    factor =. index cone direction
                    blockers =. 0 occluders (<values),(<direction),<3{sample
                    for_object. blockers do.
                        found =. 1 object}found
                        material =. 1{::(2{::object{::Objects){::Materials
                        factor =. factor fixed_mul 7{material
                    end.
                    factor_sum =. factor_sum+factor
                end.
                labels =. ''
                for_j. I.found do.
                    labels =. labels,0{::j{::Objects
                end.
                if. 0=#labels do.
                    labels =. 'none'
                end.
                rows =. rows,<'light ',(integer index+1),' factor ',(integer factor_sum),' occluders ',labels
            end.
        elseif. kind-:'region' do.
            'x0 y0 x1 y1' =. values
            chosen =. 0$a:
            for_y. y0+i.1+y1-y0 do.
                for_x. x0+i.1+x1-x0 do.
                    chosen =. chosen,(x+Width*y){Pixels
                end.
            end.
            rows =. rows,<'pixels ',(integer #chosen),' mean ',words mean_color chosen
            labels =. 0$a:
            for_object. Objects do.
                labels =. labels,0{>object
            end.
            labels =. labels,<,'.'
            for_label. labels do.
                label =. >label
                count =. 0
                for_pixel. chosen do.
                    count =. count+label-:5{::>pixel
                end.
                if. count do.
                    rows =. rows,<'label ',label,' ',integer count
                end.
            end.
        end.
    end.
    rows
)
run =: 3 : 0
    'Eye Forward Right Up View Background Ambient Fog Materials Objects Lights' =: read_scene ''
    rows =. split_words&.>read_lines 'input/render.txt'
    'Width Height' =: integer_value&>}.0{::rows
    Contrast =: integer_value 1{::1{::rows
    MaxDepth =: integer_value 1{::2{::rows
    Far =: integer_value 1{::3{::rows
    Epsilon =: integer_value 1{::4{::rows
    Margin =: integer_value 1{::5{::rows
    prepare ''
    render ''
    write_images ''
    'stats.txt'write_lines statistics ''
    'queries.txt'write_lines queries ''
    i.0
)
run ''
