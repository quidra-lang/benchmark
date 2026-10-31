LF =: 10{a.
num =: 3 : ',''0'' 8!:2 y'
say =: 3 : '1!:2&2 y,LF'
join =: 4 : '(#x)}.;(<x),&.>y'
words =: 3 : '(<;._1 '' '',y)-.<'''''
fail =: 3 : 0
    Reason=:y
    throw.
)
check =: 4 : 'if. -.y do. fail x end.'
pointText =: 3 : '''('',(num 0{y),'','',(num 1{y),'')'''
boxText =: 3 : '(pointText 2{.y),''-'',pointText 2}.y'
nameList =: 3 : 'if. #y do. '' ''join y{RectNames else. ''none'' end.'
rectWidth =: 3 : '(2{y{Coords)-0{y{Coords'
rectHeight =: 3 : '(3{y{Coords)-1{y{Coords'
rectArea =: 3 : '(rectWidth y)*rectHeight y'
margins =: 4 : '((2{.y{Coords)-2{.x{Coords),(2}.x{Coords)-2}.y{Coords'
relation =: 4 : 0
    a=.x{Coords
    b=.y{Coords
    common=.((2{.a)>.2{.b),(2}.a)<.2}.b
    'ox oy'=.(2}.common)-2{.common
    if. (ox>0)*.oy>0 do. kind=.0
    elseif. (ox<0)+.oy<0 do. kind=.3
    elseif. (ox=0)*.oy=0 do. kind=.2
    else. kind=.1 end.
    if. (ox<0)*.oy<0 do. direction=.'diagonal' elseif. ox<0 do. direction=.'x' else. direction=.'y' end.
    (<kind),(<common),(<ox),(<oy),(<0>.(-ox)>.-oy),<direction
)
connected =: 4 : '(0{::x relation y)<:1'
bounding =: 3 : '(<./0{"1 y{Coords),(<./1{"1 y{Coords),(>./2{"1 y{Coords),>./3{"1 y{Coords'
lexLess =: 4 : 0
    if. 0=#y do. 1 return. end.
    different=.I.x~:y
    if. #different do. (x{~{.different)<y{~{.different else. 0 end.
)
getRect =: 3 : 0
    i=.RectNames i.<y
    ('unknown rectangle ',y)check i<#RectNames
    i
)
unused =: 3 : '(''duplicate rectangle '',y)check -.(<y)e.RectNames'
onLayer =: 3 : 0
    order=./:RectNames
    order#~(order{RectLayers)=<y
)
requireLayer =: 3 : 0
    result=.onLayer y
    ('no rectangles on ',y)check 0<#result
    result
)
pair =: 3 : 0
    a=.getRect 0{::y
    b=.getRect 1{::y
    ('same rectangle ',0{::y)check a~:b
    a,b
)
validBounds =: 3 : '''out of bounds''check *./10000>:|y'
report =: 4 : 0
    say x
    for_line. y do. say >line end.
)
overlapLines =: 3 : 0
    result=.0$a:
    for_i. i.#y do.
        a=.i{y
        for_b. (i+1)}.y do.
            'kind common ox oy gap direction'=.a relation b
            if. kind=0 do. result=.result,<(a{::RectNames),' ',(b{::RectNames),' ',(boxText common),' area ',num ox*oy end.
        end.
    end.
    result
)
spacingLines =: 4 : 0
    found=.0$a:
    keys=.i.0
    for_i. i.#y do.
        a=.i{y
        for_b. (i+1)}.y do.
            'kind common ox oy gap direction'=.a relation b
            if. kind=2 do. direction=.'corner'
            elseif. (kind~:3)+.gap>:x do. continue. end.
            keys=.keys,gap
            found=.found,<(a{::RectNames),' ',(b{::RectNames),' gap ',(num gap),' ',direction
        end.
    end.
    found{~/:keys
)
findNets =: 3 : 0
    seen=.(#y)$0
    result=.0$a:
    for_start. i.#y do.
        if. start{seen do. continue. end.
        pending=.,start
        seen=.(1)start}seen
        included=.(#y)$0
        while. #pending do.
            current=.{:pending
            pending=.}:pending
            included=.(1)current}included
            for_i. i.#y do.
                if. -.i{seen do. if. (current{y)connected i{y do.
                    seen=.(1)i}seen
                    pending=.pending,i
                end. end.
            end.
        end.
        result=.result,<included#y
    end.
    result
)
makeCoverage =: 3 : 0
    'ids extraX extraY'=.y
    xs=./:~ ~.extraX,,0 2{"1 ids{Coords
    ys=./:~ ~.extraY,,1 3{"1 ids{Coords
    cells=.((<:#ys),<:#xs)$0
    for_id. ids do.
        'x y0 u v'=.id{Coords
        for_i. (xs i.x)+i.(xs i.u)-xs i.x do.
            for_j. (ys i.y0)+i.(ys i.v)-ys i.y0 do. cells=.(((<j,i){cells)+1)(<j,i)}cells end.
        end.
    end.
    (<xs),(<ys),<cells
)
coverage =: 3 : 'makeCoverage (<y),(<i.0),<i.0'
cellArea =: 4 : 0
    'xs ys cells'=.x
    'i j'=.y
    (((i+1){xs)-i{xs)*((j+1){ys)-j{ys
)
covered =: 4 : 0
    'xs ys cells'=.x
    'i j'=.y
    if. (i<0)+.(j<0)+.(i>:(<:#xs))+.j>:(<:#ys) do. 0 else. 0<(<j,i){cells end.
)
covArea =: 4 : 0
    'xs ys cells'=.y
    result=.0
    for_j. i.<:#ys do.
        for_i. i.<:#xs do. if. ((<j,i){cells)>:x do. result=.result+y cellArea i,j end. end.
    end.
    result
)
perimeter =: 3 : 0
    'xs ys cells'=.y
    result=.0
    for_i. i.#xs do.
        for_j. i.<:#ys do. if. (y covered (i-1),j)~:y covered i,j do. result=.result+((j+1){ys)-j{ys end. end.
    end.
    for_j. i.#ys do.
        for_i. i.<:#xs do. if. (y covered i,j-1)~:y covered i,j do. result=.result+((i+1){xs)-i{xs end. end.
    end.
    result
)
runs =: 4 : 0
    result=.0 2$0
    i=.0
    while. i<#x do.
        if. -.i{x do. i=.i+1 continue. end.
        start=.i
        while. i<#x do. if. -.i{x do. break. end.
            i=.i+1 end.
        result=.result,(start{y),i{y
    end.
    result
)
holes =: 3 : 0
    'xs ys cells'=.y
    nx=.<:#xs
    ny=.<:#ys
    seen=.(ny,nx)$0
    result=.0$a:
    for_j. i.ny do.
        for_i. i.nx do.
            if. ((<j,i){seen)+.0<(<j,i){cells do. continue. end.
            pending=.,:i,j
            seen=.(1)(<j,i)}seen
            boundary=.0
            amount=.0
            bounds=.(i{xs),(j{ys),((i+1){xs),(j+1){ys
            while. #pending do.
                'a b'=.{:pending
                pending=.}:pending
                boundary=.boundary+.(a e.0,nx-1)+.b e.0,ny-1
                amount=.amount+y cellArea a,b
                bounds=.((2{.bounds)<.(a{xs),b{ys),(2}.bounds)>.((a+1){xs),(b+1){ys
                neighbors=.((a-1),b),((a+1),b),:(a,b-1)
                neighbors=.neighbors,a,b+1
                for_next. neighbors do.
                    'p q'=.next
                    if. (p>:0)*.(p<nx)*.(q>:0)*.q<ny do.
                        if. (-.(<q,p){seen)*.0=(<q,p){cells do.
                            seen=.(1)(<q,p)}seen
                            pending=.pending,p,q
                        end.
                    end.
                end.
            end.
            if. -.boundary do. result=.result,<(<amount),<bounds end.
        end.
    end.
    result
)
pieces =: 3 : 0
    'xs ys cells'=.y
    rows=.0$a:
    for_j. i.<:#ys do. rows=.rows,<(0<j{cells)runs xs end.
    result=.0 4$0
    for_j. i.#rows do.
        for_span. j{::rows do.
            if. j>0 do. if. (<span)e.<"1 (j-1){::rows do. continue. end. end.
            top=.j+1
            while. top<#rows do.
                if. -.(<span)e.<"1 top{::rows do. break. end.
                top=.top+1
            end.
            result=.result,(0{span),(j{ys),(1{span),top{ys
        end.
    end.
    result
)
largestEmpty =: 3 : 0
    'xs ys cells'=.y
    best=.i.0
    bounds=.i.0
    for_a. i.<:#xs do.
        free=.(<:#ys)$1
        for_b. (a+1)+i.(#xs)-a+1 do.
            free=.free*.0=(b-1){"1 cells
            width=.(b{xs)-a{xs
            for_span. free runs ys do.
                'bottom top'=.span
                candidate=.(-width*top-bottom),(a{xs),bottom,width
                if. candidate lexLess best do. best=.candidate
                    bounds=.(a{xs),bottom,(b{xs),top end.
            end.
        end.
    end.
    bounds
)
percentage =: 4 : 0
    h=.<.(10000x*x)%y
    (num <.h%100),'.',_2{.'00',num 100|h
)
ruleKey =: 3 : '(0{::y),'' '',(1{::y),'' '',2{::y'
ruleViolations =: 3 : 0
    'kind layer other value'=.y
    ids=.onLayer layer
    if. kind-:'spacing' do. value spacingLines ids return. end.
    result=.0$a:
    for_id. ids do.
        if. kind-:'width' do.
            size=.(rectWidth id)<.rectHeight id
            if. size<value do. result=.result,<(id{::RectNames),' width ',num size end.
        else.
            outers=.onLayer other
            if. 0=#outers do. result=.result,<(id{::RectNames),' best margin none' continue. end.
            best=.__
            for_outer. outers do. best=.best>.<./outer margins id end.
            if. best<value do. result=.result,<(id{::RectNames),' best margin ',num best end.
        end.
    end.
    result
)
execute =: 3 : 0
    parts=.words y
    command=.0{::parts
    args=.}.parts
    before=.(<RectNames),(<RectLayers),(<Coords),<y
    select. command
    case. 'ADD' do.
        name=.0{::args
        layer=.1{::args
        unused name
        bounds=.0".&>2}.args
        'x y0 u v'=.bounds
        'invalid rectangle'check (x<u)*.y0<v
        validBounds bounds
        RectNames=:RectNames,<name
        RectLayers=:RectLayers,<layer
        Coords=:Coords,bounds
        say 'added ',name,' ',layer,' ',boxText bounds
    case. 'COPY';'MOVE';'RESIZE';'SPLIT';'LAYER';'DELETE' do.
        name=.0{::args
        id=.getRect name
        layer=.id{::RectLayers
        bounds=.id{Coords
        'x y0 u v'=.bounds
        select. command
        case. 'COPY';'MOVE' do.
            if. command-:'COPY' do. new=.1{::args
                unused new
                numbers=.0".&>2}.args
            else. new=.name
                numbers=.0".&>1}.args end.
            moved=.bounds+4$numbers
            validBounds moved
            if. command-:'COPY' do. RectNames=:RectNames,<new
                RectLayers=:RectLayers,<layer
                Coords=:Coords,moved
                say 'copied ',name,' to ',new,' ',boxText moved
            else. Coords=:moved id}Coords
                say 'moved ',name,' to ',boxText moved end.
        case. 'RESIZE' do.
            'w h'=.0".&>1}.args
            'invalid size'check (w>0)*.h>0
            resized=.x,y0,(x+w),y0+h
            validBounds resized
            Coords=:resized id}Coords
            say 'resized ',name,' to ',boxText resized
        case. 'SPLIT' do.
            axis=.1{::args
            position=.0".2{::args
            new=.3{::args
            unused new
            if. axis-:'x' do. valid=.(x<position)*.position<u
                kept=.x,y0,position,v
                piece=.position,y0,u,v
            else. valid=.(y0<position)*.position<v
                kept=.x,y0,u,position
                piece=.x,position,u,v end.
            ('cut outside ',name)check valid
            Coords=:kept id}Coords
            RectNames=:RectNames,<new
            RectLayers=:RectLayers,<layer
            Coords=:Coords,piece
            say 'split ',name,' at ',axis,'=',(num position),': ',name,' ',(boxText kept),', ',new,' ',boxText piece
        case. 'LAYER' do.
            target=.1{::args
            ('already on ',target)check -.layer-:target
            RectLayers=:(<target)id}RectLayers
            say 'layer ',name,' ',layer,' -> ',target
        case. 'DELETE' do.
            mask=.(i.#RectNames)~:id
            RectNames=:mask#RectNames
            RectLayers=:mask#RectLayers
            Coords=:mask#Coords
            say 'deleted ',name
        end.
    case. 'UNDO' do.
        'nothing to undo'check 0<#History
        saved=.>{:History
        RectNames=:0{::saved
        RectLayers=:1{::saved
        Coords=:2{::saved
        original=.3{::saved
        History=:}:History
        say 'undo: ',original
    case. 'LIST' do.
        say 'rectangles: ',num #RectNames
        for_id. /:RectNames do. say (id{::RectNames),' ',(id{::RectLayers),' ',(boxText id{Coords),' ',(num rectWidth id),'x',num rectHeight id end.
    case. 'INFO' do.
        name=.0{::args
        id=.getRect name
        say name,' ',(id{::RectLayers),' ',(boxText id{Coords),' ',(num rectWidth id),'x',(num rectHeight id),' area ',num rectArea id
        others=.(/:RectNames)-.id
        labels=.words 'overlaps touches corners'
        for_kind. i.3 do.
            found=.i.0
            for_other. others do. if. (id{RectLayers)-:other{RectLayers do. if. kind=0{::id relation other do. found=.found,other end. end. end.
            say (kind{::labels),': ',nameList found
        end.
        enclosing=.enclosed=.i.0
        for_other. others do.
            if. 0<:<./id margins other do. enclosed=.enclosed,other end.
            if. 0<:<./other margins id do. enclosing=.enclosing,other end.
        end.
        say 'encloses: ',nameList enclosed
        say 'enclosed by: ',nameList enclosing
    case. 'LAYERS' do.
        layers=./:~ ~.RectLayers
        say 'layers: ',num #layers
        for_layer. layers do.
            layer=.>layer
            ids=.onLayer layer
            say layer,': ',(num #ids),' rectangles, area ',(num 1 covArea coverage ids),', nets ',num #findNets ids
        end.
    case. 'OVERLAPS' do.
        if. 0=#args do.
            lines=.0$a:
            for_layer. /:~ ~.RectLayers do.
                layer=.>layer
                for_line. overlapLines onLayer layer do. lines=.lines,<layer,' ',>line end.
            end.
            ('overlaps all layers: ',num #lines)report lines
        else.
            layer=.0{::args
            lines=.overlapLines requireLayer layer
            ('overlaps ',layer,': ',num #lines)report lines
        end.
    case. 'INTERSECT';'ADJACENT';'ENCLOSE';'PATH' do.
        'a b'=.2{.args
        'first second'=.pair args
        'kind common ox oy gap direction'=.first relation second
        if. command-:'INTERSECT' do.
            if. kind=0 do. detail=.(boxText common),' area ',num ox*oy
            elseif. kind=1 do. detail=.'segment ',(boxText common),' length ',num ox+oy
            elseif. kind=2 do. detail=.'point ',pointText 2{.common
            else. detail=.'none, gap ',num gap end.
            say 'intersect ',a,' ',b,': ',detail
        elseif. command-:'ADJACENT' do.
            if. kind=0 do. detail=.'overlapping'
            elseif. kind=1 do.
                if. ox=0 do. if. (2{first{Coords)=0{common do. side=.'west' else. side=.'east' end.
                else. if. (3{first{Coords)=1{common do. side=.'south' else. side=.'north' end. end.
                detail=.a,' is ',side,' of ',b,', edge ',(boxText common),', length ',num ox+oy
            elseif. kind=2 do. detail=.'corner only at ',pointText 2{.common
            else. detail=.'not adjacent' end.
            say 'adjacent ',a,' ',b,': ',detail
        elseif. command-:'ENCLOSE' do.
            'left bottom right top'=.first margins second
            smallest=.<./first margins second
            detail=.'margins left ',(num left),' bottom ',(num bottom),' right ',(num right),' top ',num top
            if. smallest>:0 do. detail=.'yes, ',detail,', min ',num smallest else. detail=.'no, ',detail end.
            say 'enclose ',a,' ',b,': ',detail
        else.
            'different layers'check (first{RectLayers)-:second{RectLayers
            ids=.onLayer first{::RectLayers
            distances=.(#RectNames)$_1
            distances=.(0)second}distances
            queue=.,second
            at=.0
            while. at<#queue do.
                current=.at{queue
                at=.at+1
                for_other. ids do. if. (other{distances)<0 do. if. current connected other do.
                    distances=.((current{distances)+1)other}distances
                    queue=.queue,other
                end. end. end.
            end.
            if. (first{distances)<0 do. say 'path ',a,' ',b,': none'
            else.
                path=.,first
                current=.first
                while. current~:second do.
                    for_other. ids do. if. (other{distances)=(current{distances)-1 do. if. current connected other do.
                        current=.other
                        path=.path,other
                        break.
                    end. end. end.
                end.
                say 'path ',a,' ',b,': ',(' -> 'join path{RectNames),' (',(num <:#path),' steps)'
            end.
        end.
    case. 'AT' do.
        'x y0'=.0".&>args
        found=.0$a:
        for_id. /:RectNames do.
            'a b c d'=.id{Coords
            if. (a<:x)*.(x<:c)*.(b<:y0)*.y0<:d do.
                position=.((x e.a,c)+y0 e.b,d){::words 'inside edge corner'
                found=.found,<(id{::RectNames),' ',(id{::RectLayers),' ',position
            end.
        end.
        if. #found do. text=.', 'join found else. text=.'none' end.
        say 'at ',(pointText x,y0),': ',text
    case. 'NEAREST' do.
        id=.getRect 0{::args
        others=.(onLayer id{::RectLayers)-.id
        closest=._1
        best=.0
        for_other. others do.
            gap=.4{::id relation other
            if. (closest<0)+.gap<best do. best=.gap
                closest=.other end.
        end.
        if. closest<0 do. text=.'none' else. text=.(closest{::RectNames),' gap ',num best end.
        say 'nearest ',(id{::RectNames),': ',text
    case. 'RULE' do.
        kind=.tolower 0{::args
        layer=.1{::args
        other=.''
        if. kind-:'enclose' do. other=.2{::args
            ('same layer ',layer)check -.layer-:other end.
        value=.0".>{:args
        rule=.(<kind),(<layer),(<other),<value
        key=.ruleKey rule
        keys=.ruleKey&.>Rules
        i=.keys i.<key
        if. i=#Rules do. Rules=:Rules,<rule else. Rules=:(<rule)i}Rules end.
        say 'rule ',kind,' ',' 'join }.args
    case. 'CHECK' do.
        'no rules'check 0<#Rules
        total=.0
        for_rule. Rules{~/:ruleKey&.>Rules do.
            rule=.>rule
            'kind layer other value'=.rule
            lines=.ruleViolations rule
            heading=.kind,' ',layer
            if. kind-:'enclose' do. heading=.heading,' ',other end.
            (heading,' ',(num value),': ',(num #lines),' violations')report lines
            total=.total+#lines
        end.
        say 'check: ',(num total),' violations in ',(num #Rules),' rules'
    case. do.
        threshold=.1
        if. command-:'COVER' do. threshold=.0".0{::args
            layer=.1{::args
        else. layer=.0{::args end.
        ids=.requireLayer layer
        if. command-:'DRC' do.
            spacing=.0".1{::args
            lines=.spacing spacingLines ids
            ('drc ',layer,' spacing ',(num spacing),': ',(num #lines),' violations')report lines
        elseif. command-:'NETS' do.
            groups=.findNets ids
            say 'nets ',layer,': ',num #groups
            for_i. i.#groups do.
                group=.i{::groups
                say 'net ',(num i+1),': ',(nameList group),' area ',num 1 covArea coverage group
            end.
        elseif. command-:'RENDER' do.
            'x y0 u v'=.0".&>}.args
            'invalid window'check (x<u)*.y0<v
            'window too large'check ((u-x)<:60)*.(v-y0)<:40
            say 'render ',layer,' ',boxText x,y0,u,v
            for_j. |.y0+i.v-y0 do.
                row=.''
                for_i. x+i.u-x do.
                    count=.0
                    for_id. ids do. 'a b c d'=.id{Coords
                        if. (a<:i)*.(i<c)*.(b<:j)*.j<d do. count=.count+1 end.
                    end.
                    if. count=0 do. row=.row,'.' elseif. count<10 do. row=.row,num count else. row=.row,'*' end.
                end.
                say row
            end.
        elseif. (<command)e.words 'BBOX DENSITY' do.
            bounds=.bounding ids
            'x y0 u v'=.bounds
            width=.u-x
            height=.v-y0
            if. command-:'BBOX' do.
                say 'bbox ',layer,': ',(boxText bounds),' ',(num width),'x',(num height),', ',(num #ids),' rectangles, density ',((1 covArea coverage ids)percentage width*height),'%'
            else.
                window=.0".1{::args
                nc=.>.width%window
                nr=.>.height%window
                'too many windows'check (nc<:20)*.nr<:20
                grid=.makeCoverage (<ids),(<x+window*i.nc+1),<y0+window*i.nr+1
                'xs ys cells'=.grid
                tiles=.(nr,nc)$0
                for_j. i.<:#ys do.
                    for_i. i.<:#xs do. if. 0<(<j,i){cells do.
                        a=.<.((i{xs)-x)%window
                        b=.<.((j{ys)-y0)%window
                        tiles=.(((<b,a){tiles)+grid cellArea i,j)(<b,a)}tiles
                    end. end.
                end.
                denominator=.(*:window)
                say 'density ',layer,' window ',(num window),': ',(num nc),'x',num nr
                for_row. |.tiles do. say ' 'join num&.><.(100x*row)%denominator end.
                for_label. words 'min max' do.
                    label=.>label
                    if. label-:'min' do. best=.<./,tiles else. best=.>./,tiles end.
                    pos=.{.I.best=,tiles
                    a=.nc|pos
                    b=.<.pos%nc
                    say label,' ',(best percentage denominator),'% at ',pointText (x+a*window),y0+b*window
                end.
            end.
        else.
            grid=.coverage ids
            if. command-:'AREA' do. say 'area ',layer,': ',num 1 covArea grid
            elseif. command-:'COVER' do. say 'cover ',layer,' >= ',(num threshold),': ',num threshold covArea grid
            elseif. command-:'PERIMETER' do. say 'perimeter ',layer,': ',num perimeter grid
            elseif. command-:'EMPTY' do.
                bounds=.largestEmpty grid
                if. 0=#bounds do. text=.'none' else. text=.(boxText bounds),' area ',num ((2{bounds)-0{bounds)*(3{bounds)-1{bounds end.
                say 'empty ',layer,': ',text
            elseif. command-:'HOLES' do.
                found=.holes grid
                say 'holes ',layer,': ',num #found
                for_i. i.#found do. 'amount bounds'=.i{::found
                    say 'hole ',(num i+1),': area ',(num amount),', bbox ',boxText bounds end.
            elseif. command-:'MERGE' do.
                found=.pieces grid
                ('merge ',layer,': ',(num #found),' pieces')report boxText&.><"1 found
            end.
        end.
    end.
    if. (<command)e.words 'ADD COPY MOVE RESIZE SPLIT LAYER DELETE' do. History=:History,<before end.
)
main =: 3 : 0
    RectNames=:RectLayers=:History=:Rules=:0$a:
    Coords=:0 4$0
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    count=.0".0{::lines
    for_i. i.count do.
        try. execute (i+1){::lines
        catcht. say 'error: ',Reason end.
    end.
)
main''
