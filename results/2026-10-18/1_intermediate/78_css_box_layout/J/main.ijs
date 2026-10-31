LF =: 10{a.
num =: 3 : ',''0'' 8!:2 y'
say =: 3 : '1!:2&2 y,LF'
join =: 4 : '(#x)}.;(<x),&.>y'
words =: 3 : '(<;._1 '' '',y)-.<'''''
splitBy =: 4 : 0
    rest=.y
    result=.0$a:
    while. 1 do.
        hits=.I.x E.rest
        if. 0=#hits do. result=.result,<rest break. end.
        at=.{.hits
        result=.result,<at{.rest
        rest=.(at+#x)}.rest
    end.
    result
)
naturalToken =: 3 : '((1<:#y)*.(#y)<:3)*.*./y e.''0123456789'''
positiveToken =: 3 : 'if. naturalToken y do. 0<0".y else. 0 end.'
signedToken =: 3 : 'if. ''-''={.y do. naturalToken }.y else. naturalToken y end.'
percentToken =: 3 : 'if. ''%''={:y do. naturalToken }:y else. 0 end.'
frToken =: 3 : 'if. (#y)>:2 do. if. ''fr''-:_2{.y do. positiveToken _2}.y else. 0 end. else. 0 end.'
Sides =: words 'top right bottom left'
PropNames =: words 'display position box-sizing width height min-width min-height max-width max-height flex-direction flex-wrap justify-content align-items align-self row-gap column-gap order flex-grow flex-shrink flex-basis grid-template-columns grid-template-rows grid-column grid-row'
Initial =: words 'block static content-box auto auto 0 0 none none row nowrap start stretch auto 0 0 0 0 1 auto none none auto auto'
initializeProperties =: 3 : 0
    for_side. Sides do.
        PropNames=:PropNames,side
        Initial=:Initial,<'auto'
        for_kind. words 'margin padding border' do.
            PropNames=:PropNames,<(>kind),'-',>side
            Initial=:Initial,<'0'
        end.
    end.
)
initializeProperties''
knownProperty =: 3 : '( (<y)e.PropNames)+.(<y)e.words ''margin padding border gap'''
gridlineValid =: 3 : 0
    n=.#y
    if. n=1 do. (('auto'-:0{::y)+.positiveToken 0{::y) return. end.
    if. n=2 do. (('span'-:0{::y)*.positiveToken 1{::y) return. end.
    if. n=3 do.
        if. (-.positiveToken 0{::y)+.(-.'/'-:1{::y)+.-.positiveToken 2{::y do. 0 return. end.
        (0".0{::y)<0".2{::y return.
    end.
    if. n=4 do. (positiveToken 0{::y)*.('/'-:1{::y)*.('span'-:2{::y)*.positiveToken 3{::y return. end.
    0
)
validLonghand =: 4 : 0
    if. (<x)e.words 'grid-template-columns grid-template-rows' do.
        if. y-:,<'none' do. 1 return. end.
        for_token. y do. token=.>token
            if. (-.token-:'auto')*.(-.naturalToken token)*.-.frToken token do. 0 return. end.
        end.
        1 return.
    end.
    if. (<x)e.words 'grid-column grid-row' do. gridlineValid y return. end.
    if. 1~:#y do. 0 return. end.
    s=.0{::y
    select. x
    case. 'display' do. (<s)e.words 'block flex grid none'
    case. 'position' do. (<s)e.words 'static relative absolute'
    case. 'box-sizing' do. (<s)e.words 'content-box border-box'
    case. 'flex-direction' do. (<s)e.words 'row row-reverse column column-reverse'
    case. 'flex-wrap' do. (<s)e.words 'nowrap wrap'
    case. 'justify-content' do. (<s)e.words 'start end center space-between space-around space-evenly'
    case. 'align-items' do. (<s)e.words 'stretch start end center'
    case. 'align-self' do. (<s)e.words 'auto stretch start end center'
    case. 'width';'height';'flex-basis' do. ('auto'-:s)+.(naturalToken s)+.percentToken s
    case. 'min-width';'min-height' do. (naturalToken s)+.percentToken s
    case. 'max-width';'max-height' do. ('none'-:s)+.(naturalToken s)+.percentToken s
    case. 'top';'right';'bottom';'left' do. ('auto'-:s)+.signedToken s
    case. 'order' do. signedToken s
    case. do.
        if. 'border-'-:(7<.#x){.x do. (<s)e.words '0 1' else. naturalToken s end.
    end.
)
expandDecl =: 4 : 0
    tokens=.words y
    if. (<x)e.PropNames do.
        if. x validLonghand tokens do. ,<(<x),<y else. 0$a: end.
        return.
    end.
    n=.#tokens
    if. x-:'gap' do.
        if. n>2 do. 0$a: return. end.
        if. -. *./naturalToken&>tokens do. 0$a: return. end.
        (<(<'row-gap'),{.tokens),<(<'column-gap'),{:tokens return.
    end.
    if. (<x)e.words 'margin padding border' do.
        if. n>4 do. 0$a: return. end.
        for_token. tokens do. if. -. (x,'-top')validLonghand ,token do. 0$a: return. end. end.
        picks=.(n-1){4 4$0 0 0 0 0 1 0 1 0 1 2 1 0 1 2 3
        result=.0$a:
        for_i. i.4 do. result=.result,<(<x,'-',i{::Sides),(i{picks){tokens end.
        result return.
    end.
    0$a:
)
prop =: 4 : '(PropNames i.<y){::x{Styles'
number =: 4 : '0".x prop y'
frame =: 4 : 0
    if. y do. sides=.words 'left right' else. sides=.words 'top bottom' end.
    total=.0
    for_side. sides do. total=.total+(x number 'padding-',>side)+x number 'border-',>side end.
    total
)
outer =: 4 : 0
    if. y do. sides=.words 'left right' else. sides=.words 'top bottom' end.
    result=.x frame y
    for_side. sides do. result=.result+x number 'margin-',>side end.
    result
)
borderWidth =: 3 : '(0{y{Geometry)+y frame 1'
borderHeight =: 3 : '(1{y{Geometry)+y frame 0'
flow =: 3 : 0
    result=.i.0
    for_child. y{::Children do.
        if. 6{child{Geometry do. if. -.'absolute'-:child prop 'position' do. result=.result,child end. end.
    end.
    result
)
items =: 3 : 0
    children=.flow y
    order=.i.0
    for_child. children do. order=.order,child number 'order' end.
    children{~/:order
)
resolveLength =: 3 : 0
    'id property reference horizontal'=.y
    value=.id prop property
    if. (<value)e.words 'auto none' do. _1 return. end.
    if. '%'={:value do.
        if. reference<0 do. _1 return. end.
        result=.<.(reference*0".}:value)%100
    else. result=.0".value end.
    if. 'border-box'-:id prop 'box-sizing' do. result=.0>.result-id frame horizontal end.
    result
)
constrain =: 3 : 0
    'id value horizontal reference'=.y
    if. horizontal do. axis=.'width' else. axis=.'height' end.
    lower=.0>.resolveLength (<id),(< 'min-',axis),(<reference),<horizontal
    upper=.resolveLength (<id),(< 'max-',axis),(<reference),<horizontal
    if. upper>:0 do. value=.value<.upper end.
    lower>.value
)
inset =: 4 : 'if. ''auto''-:x prop y do. 0 else. x number y end.'
itemAlign =: 4 : 'if. ''auto''-:y prop ''align-self'' do. x prop ''align-items'' else. y prop ''align-self'' end.'
alignOffset =: 4 : 'if. y<:0 do. 0 elseif. x-:''end'' do. y elseif. x-:''center'' do. <.y%2 else. 0 end.'
gapTotal =: 4 : 'x*0>.y-1'
distribute =: 4 : 0
    shares=.<.(x*y)%+/y
    remainder=.x-+/shares
    for_i. i.#y do. if. (remainder>0)*.(i{y)>0 do. shares=.((i{shares)+1)i}shares
        remainder=.remainder-1 end. end.
    shares
)
wrapWords =: 4 : 0
    result=.0$a:
    for_word. words y do.
        word=.>word
        if. #result do.
            last=.>{:result
            if. x>:(#last)+1+#word do. result=.(<last,' ',word)(<:#result)}result continue. end.
        end.
        result=.result,<word
    end.
    result
)
placeChild =: 3 : 0
    'container child left top'=.y
    rx=.(container number 'border-left')+(container number 'padding-left')+left
    ry=.(container number 'border-top')+(container number 'padding-top')+top
    Geometry=:rx(<child,2)}Geometry
    Geometry=:ry(<child,3)}Geometry
)
gridRequest =: 3 : 0
    t=.words y
    if. t-:,<'auto' do. 0 1 return. end.
    if. 'span'-:0{::t do. 0,0".1{::t return. end.
    a=.0".0{::t
    if. 1=#t do. a,1 return. end.
    if. 'span'-:2{::t do. a,0".3{::t else. a,(0".2{::t)-a end.
)
trackSpecs =: 4 : 'if. ''none''-:x prop y do. 0$a: else. words x prop y end.'
columnSpecs =: 3 : 'if. ''none''-:y prop ''grid-template-columns'' do. ,<''auto'' else. y trackSpecs ''grid-template-columns'' end.'
areaFits =: 4 : 0
    'r c rs cs'=.y
    for_area. x do.
        'a b as bs'=.area
        if. (a~:0)*.(r<a+as)*.(a<r+rs)*.(c<b+bs)*.b<c+cs do. 0 return. end.
    end.
    1
)
gridPlacement =: 4 : 0
    ordered=.y
    requests=.0 4$0
    nc=.#columnSpecs x
    for_id. ordered do.
        'r rs'=.gridRequest id prop 'grid-row'
        'c cs'=.gridRequest id prop 'grid-column'
        requests=.requests,r,rs,c,cs
        nc=.nc>.cs+(c-1)*c~:0
    end.
    areas=.((#ordered),4)$0
    for_i. i.#ordered do.
        'r rs c cs'=.i{requests
        if. (r~:0)*.c~:0 do. areas=.(r,c,rs,cs)i}areas end.
    end.
    cr=.cc=.1
    for_i. i.#ordered do.
        'r rs c cs'=.i{requests
        if. (r~:0)*.c~:0 do. continue. end.
        if. r~:0 do.
            c=.1
            for_candidate. 1+i.1+nc-cs do. if. areas areaFits r,candidate,rs,cs do. c=.candidate break. end. end.
        elseif. c~:0 do.
            if. c<cc do. cr=.cr+1 end.
            r=.cr
            while. -.areas areaFits r,c,rs,cs do. r=.r+1 end.
            cr=.r
            cc=.c+cs
        else.
            r=.cr
            c=.cc
            while. 1 do.
                if. (c+cs-1)>nc do. r=.r+1
                    c=.1
                elseif. -.areas areaFits r,c,rs,cs do. c=.c+1
                else. break. end.
            end.
            cr=.r
            cc=.c+cs
        end.
        areas=.(r,c,rs,cs)i}areas
    end.
    (<areas),<nc
)
trackSizes =: 3 : 0
    'specs count available gap contributions'=.y
    specifications=.specs,(count-#specs)#<'auto'
    sizes=.count$0
    for_i. i.count do.
        spec=.i{::specifications
        if. (spec-:'auto')+.((available<0)*.'fr'-:_2{.spec) do.
            for_entry. contributions do.
                'start span amount'=.entry
                if. (start=i+1)*.span=1 do. sizes=.((i{sizes)>.amount)i}sizes end.
            end.
        elseif. -.'fr'-:_2{.spec do. sizes=.(0".spec)i}sizes end.
    end.
    if. available>:0 do.
        leftover=.available-(+/sizes)+gap*count-1
        weights=.i.0
        for_spec. specifications do. spec=.>spec
            if. 'fr'-:_2{.spec do. weights=.weights,0"._2}.spec else. weights=.weights,0 end.
        end.
        if. 0=+/weights do. weights=.specifications=< 'auto' end.
        if. (leftover>0)*.0<+/weights do. sizes=.sizes+leftover distribute weights end.
    end.
    sizes
)
spanStart =: 3 : 0
    'sizes start gap'=.y
    (+/(start-1){.sizes)+gap*start-1
)
spanSize =: 3 : 0
    'sizes start span gap'=.y
    (+/span{.(start-1)}.sizes)+gap*span-1
)
maxContent =: 3 : 0
    if. (y{Intrinsic)>:0 do. y{Intrinsic return. end.
    text=.y{::Texts
    children=.flow y
    gap=.y number 'column-gap'
    if. #text do. result=.#text
    elseif. ('flex'-:y prop 'display')*.(<y prop 'flex-direction')e.words 'row row-reverse' do.
        result=.gap gapTotal #children
        for_child. children do. result=.result+contribution child end.
    elseif. 'grid'-:y prop 'display' do.
        ordered=.items y
        'areas nc'=.y gridPlacement ordered
        contributions=.0 3$0
        for_i. i.#ordered do. a=.i{areas
            contributions=.contributions,(1{a),(3{a),contribution i{ordered end.
        sizes=.trackSizes (<columnSpecs y),(<nc),(<_1),(<gap),<contributions
        result=.(+/sizes)+gap gapTotal nc
    else.
        result=.0
        for_child. children do. result=.result>.contribution child end.
    end.
    Intrinsic=:result y}Intrinsic
    result
)
contribution =: 3 : 0
    width=.resolveLength (<y),(<'width'),(<_1),<1
    if. width<0 do. width=.maxContent y end.
    (constrain y,width,1,_1)+y outer 1
)
layout =: 4 : 0
    'cwref chref fw fh'=.y
    if. fw<0 do.
        value=.resolveLength (<x),(<'width'),(<cwref),<1
        if. value<0 do. value=.0>.cwref-x outer 1 end.
        fw=.constrain x,value,1,cwref
    end.
    if. fh<0 do.
        value=.resolveLength (<x),(<'height'),(<chref),<0
        if. value>:0 do. fh=.constrain x,value,0,chref end.
    end.
    Geometry=:fw(<x,0)}Geometry
    text=.x{::Texts
    if. #text do.
        lines=.fw wrapWords text
        TextLines=:(<lines)x}TextLines
        natural=.#lines
    elseif. 'flex'-:x prop 'display' do. natural=.x flexLayout fw,fh,chref
    elseif. 'grid'-:x prop 'display' do. natural=.x gridLayout fw,fh
    else.
        bottom=.previous=.0
        for_child. flow x do.
            child layout fw,fh,_1,_1
            top=.bottom+previous>.child number 'margin-top'
            placeChild x,child,(child number 'margin-left'),top
            bottom=.top+borderHeight child
            previous=.child number 'margin-bottom'
        end.
        natural=.bottom+previous
    end.
    if. fh<0 do. fh=.constrain x,natural,0,chref end.
    Geometry=:fh(<x,1)}Geometry
    natural
)
resolveSizes =: 4 : 0
    'lengthmain gap horizontal reference'=.x
    line=.y
    n=.#line
    gaps=.gap gapTotal n
    growing=.((+/4{"1 line)+(+/1{"1 line)+gaps)<lengthmain
    weights=.i.0
    active=.i.0
    for_i. i.n do.
        'id outside cross base hypothetical target'=.i{line
        if. growing do. weight=.id number 'flex-grow'
            flexible=.base<:hypothetical
        else. weight=.base*id number 'flex-shrink'
            flexible=.base>:hypothetical end.
        weights=.weights,weight
        active=.active,(weight>0)*.flexible
        line=.hypothetical(<i,5)}line
    end.
    while. +/active do.
        free=.lengthmain-gaps
        for_i. i.n do.
            if. i{active do. value=.(<i,3){line else. value=.(<i,5){line end.
            free=.free-value+(<i,1){line
        end.
        if. growing do. amount=.0>.free else. amount=.0>.-free end.
        unfrozen=.I.active
        shares=.amount distribute unfrozen{weights
        violations=.n$0
        for_j. i.#unfrozen do.
            i=.j{unfrozen
            tentative=.(<i,3){line
            if. growing do. tentative=.tentative+j{shares else. tentative=.tentative-j{shares end.
            target=.constrain ((<i,0){line),tentative,horizontal,reference
            line=.target(<i,5)}line
            violations=.(target-tentative)i}violations
        end.
        total=.+/violations
        if. total=0 do. active=.n$0
        elseif. total>0 do. active=.active*.violations<:0
        else. active=.active*.violations>:0 end.
    end.
    line
)
justifySpaces =: 4 : 0
    'remaining count'=.y
    spaces=.count$0
    if. remaining<:0 do. spaces return. end.
    if. x-:'end' do. remaining 0}spaces
    elseif. x-:'center' do. (<.remaining%2)0}spaces
    elseif. x-:'start' do. spaces
    else.
        ends=.1
        middle=.1
        if. x-:'space-between' do. ends=.0 end.
        if. x-:'space-around' do. middle=.2 end.
        weights=.ends,((count-1)#middle),ends
        if. +/weights do. count{.remaining distribute weights else. spaces end.
    end.
)
flexLayout =: 4 : 0
    'cw k heightref'=.y
    direction=.x prop 'flex-direction'
    horizontal=.(<direction)e.words 'row row-reverse'
    if. horizontal do. gap=.x number 'column-gap'
        reference=.cw
    else. gap=.x number 'row-gap'
        reference=.k end.
    rowgap=.x number 'row-gap'
    all=.0 6$0
    for_id. items x do.
        align=.x itemAlign id
        cross=.0
        if. -.horizontal do.
            room=.0>.cw-id outer 1
            cross=.resolveLength (<id),(<'width'),(<cw),<1
            if. cross<0 do.
                if. align-:'stretch' do. cross=.room else. cross=.room<.maxContent id end.
            end.
            cross=.constrain id,cross,1,cw
        end.
        base=.resolveLength (<id),(<'flex-basis'),(<reference),<horizontal
        if. base<0 do.
            if. horizontal do. dimension=.'width' else. dimension=.'height' end.
            base=.resolveLength (<id),(<dimension),(<reference),<horizontal
        end.
        if. base<0 do.
            if. horizontal do. base=.maxContent id else. base=.id layout cw,k,cross,_1 end.
        end.
        hypothetical=.constrain id,base,horizontal,reference
        all=.all,id,(id outer horizontal),cross,base,hypothetical,0
    end.
    if. horizontal do. lengthmain=.cw
    elseif. k>:0 do. lengthmain=.k
    else. total=.(+/4{"1 all)+(+/1{"1 all)+gap gapTotal #all
        lengthmain=.constrain x,total,0,heightref end.
    lines=.0$a:
    if. horizontal*.'wrap'-:x prop 'flex-wrap' do.
        for_item. all do.
            appended=.0
            if. #lines do.
                line=.>{:lines
                used=.(+/4{"1 line)+(+/1{"1 line)+(gap*#line)+(4{item)+1{item
                if. used<:lengthmain do. lines=.(<line,item)(<:#lines)}lines
                    appended=.1 end.
            end.
            if. -.appended do. lines=.lines,<,:item end.
        end.
    elseif. #all do. lines=.,<all end.
    crossstart=.totalcross=.0
    for_raw. lines do.
        line=.(lengthmain,gap,horizontal,reference)resolveSizes >raw
        lc=.cw
        if. horizontal do.
            largest=.0
            for_i. i.#line do.
                id=.(<i,0){line
                id layout cw,k,((<i,5){line),_1
                cross=.(<id,1){Geometry
                line=.cross(<i,2)}line
                largest=.largest>.cross+id outer 0
            end.
            if. (#lines)>1 do. lc=.largest
            elseif. k>:0 do. lc=.k
            else. lc=.constrain x,largest,0,heightref end.
        end.
        used=.(+/5{"1 line)+(+/1{"1 line)+gap gapTotal #line
        spaces=.(x prop 'justify-content')justifySpaces (lengthmain-used),#line
        backwards=.'-reverse'-:_8{.direction
        if. backwards do. cursor=.lengthmain else. cursor=.0 end.
        for_i. i.#line do.
            'id outside cross base hypothetical size'=.i{line
            align=.x itemAlign id
            amount=.size+outside
            if. backwards do. cursor=.cursor-(i{spaces)+amount
                mainposition=.cursor
                cursor=.cursor-gap
            else. cursor=.cursor+i{spaces
                mainposition=.cursor
                cursor=.cursor+amount+gap end.
            if. horizontal do. mainposition=.mainposition+id number 'margin-left' else. mainposition=.mainposition+id number 'margin-top' end.
            if. -.horizontal do. id layout cw,k,cross,size
            elseif. (align-:'stretch')*.'auto'-:id prop 'height' do.
                cross=.constrain id,(0>.lc-id outer 0),0,k
                id layout cw,k,size,cross
            else. id layout cw,k,size,_1 end.
            offset=.align alignOffset lc-cross+id outer -.horizontal
            if. horizontal do. placeChild x,id,mainposition,(crossstart+offset+id number 'margin-top')
            else. placeChild x,id,(crossstart+offset+id number 'margin-left'),mainposition end.
        end.
        totalcross=.totalcross+lc
        crossstart=.crossstart+lc+rowgap
    end.
    if. horizontal do. totalcross+rowgap gapTotal #lines else. lengthmain end.
)
gridLayout =: 4 : 0
    'cw k'=.y
    ordered=.items x
    'areas nc'=.x gridPlacement ordered
    cg=.x number 'column-gap'
    rg=.x number 'row-gap'
    contributions=.0 3$0
    for_i. i.#ordered do. area=.i{areas
        contributions=.contributions,(1{area),(3{area),contribution i{ordered end.
    columns=.trackSizes (<columnSpecs x),(<nc),(<cw),(<cg),<contributions
    widths=.0 2$0
    contributions=.0 3$0
    for_i. i.#ordered do.
        id=.i{ordered
        'r c rs cs'=.i{areas
        aw=.spanSize (<columns),(<c),(<cs),<cg
        width=.resolveLength (<id),(<'width'),(<aw),<1
        if. width<0 do. width=.0>.aw-id outer 1 end.
        gw=.constrain id,width,1,aw
        id layout aw,_1,gw,_1
        widths=.widths,aw,gw
        contributions=.contributions,r,rs,((<id,1){Geometry)+id outer 0
    end.
    specifications=.x trackSpecs 'grid-template-rows'
    nr=.#specifications
    for_area. areas do. nr=.nr>.(0{area)+(2{area)-1 end.
    rows=.trackSizes (<specifications),(<nr),(<k),(<rg),<contributions
    for_i. i.#ordered do.
        id=.i{ordered
        'r c rs cs'=.i{areas
        'aw gw'=.i{widths
        ah=.spanSize (<rows),(<r),(<rs),<rg
        align=.x itemAlign id
        if. (align-:'stretch')*.'auto'-:id prop 'height' do. fh=.constrain id,(0>.ah-id outer 0),0,ah
            id layout aw,ah,gw,fh
        else. id layout aw,ah,gw,_1 end.
        offset=.align alignOffset ah-((<id,1){Geometry)+id outer 0
        left=.(spanStart (<columns),(<c),<cg)+id number 'margin-left'
        top=.(spanStart (<rows),(<r),<rg)+offset+id number 'margin-top'
        placeChild x,id,left,top
    end.
    (+/rows)+rg gapTotal nr
)
ancestor =: 3 : 0
    p=.y{Parents
    while. p>:0 do.
        if. -.'static'-:p prop 'position' do. break. end.
        p=.p{Parents
    end.
    p
)
borderBox =: 3 : '(4 5{y{Geometry),(borderWidth y),borderHeight y'
marginBox =: 3 : 0
    'x y0 w h'=.borderBox y
    (x-y number 'margin-left'),(y0-y number 'margin-top'),((0{y{Geometry)+y outer 1),(1{y{Geometry)+y outer 0
)
paddingBox =: 3 : 0
    'x y0 w h'=.borderBox y
    (x+y number 'border-left'),(y0+y number 'border-top'),((0{y{Geometry)+(y number 'padding-left')+y number 'padding-right'),(1{y{Geometry)+(y number 'padding-top')+y number 'padding-bottom'
)
contentBox =: 3 : 0
    'x y0 w h'=.paddingBox y
    (x+y number 'padding-left'),(y0+y number 'padding-top'),0 1{y{Geometry
)
performLayout =: 3 : 0
    Intrinsic=:(#ElementIDs)$_1
    for_i. i.#ElementIDs do.
        shown=.-.'none'-:i prop 'display'
        p=.i{Parents
        if. p>:0 do. shown=.shown*.(<p,6){Geometry end.
        Geometry=:shown(<i,6)}Geometry
    end.
    if. 6{0{Geometry do.
        if. -.'absolute'-:0 prop 'position' do.
            0 layout ViewWidth,ViewHeight,_1,_1
            Geometry=:(0 number 'margin-left')(<0,2)}Geometry
            Geometry=:(0 number 'margin-top')(<0,3)}Geometry
        end.
    end.
    for_i. i.#ElementIDs do.
        if. (-.6{i{Geometry)+.-.'absolute'-:i prop 'position' do. continue. end.
        p=.ancestor i
        if. p<0 do. bw=.ViewWidth
            bh=.ViewHeight
        else. 'ox oy bw bh'=.paddingBox p end.
        left=.i inset 'left'
        right=.i inset 'right'
        top=.i inset 'top'
        bottom=.i inset 'bottom'
        hasleft=.-.'auto'-:i prop 'left'
        hasright=.-.'auto'-:i prop 'right'
        hastop=.-.'auto'-:i prop 'top'
        hasbottom=.-.'auto'-:i prop 'bottom'
        width=.resolveLength (<i),(<'width'),(<bw),<1
        if. width<0 do.
            room=.0>.bw-left+right+i outer 1
            if. hasleft*.hasright do. width=.room else. width=.room<.maxContent i end.
        end.
        fw=.constrain i,width,1,bw
        fh=._1
        if. ('auto'-:i prop 'height')*.hastop*.hasbottom do. fh=.constrain i,(0>.bh-top+bottom+i outer 0),0,bh end.
        i layout bw,bh,fw,fh
        if. hasleft do. rx=.left+i number 'margin-left'
        elseif. hasright do. rx=.bw-right+(i number 'margin-right')+borderWidth i
        else. rx=.i number 'margin-left' end.
        if. hastop do. ry=.top+i number 'margin-top'
        elseif. hasbottom do. ry=.bh-bottom+(i number 'margin-bottom')+borderHeight i
        else. ry=.i number 'margin-top' end.
        Geometry=:rx(<i,2)}Geometry
        Geometry=:ry(<i,3)}Geometry
    end.
    for_i. i.#ElementIDs do.
        if. -.6{i{Geometry do. continue. end.
        position=.i prop 'position'
        if. position-:'absolute' do. p=.ancestor i else. p=.i{Parents end.
        ox=.oy=.0
        if. p>:0 do.
            if. position-:'absolute' do. 'ox oy'=.2{.paddingBox p else. 'ox oy'=.4 5{p{Geometry end.
        end.
        x=.ox+(<i,2){Geometry
        y0=.oy+(<i,3){Geometry
        if. position-:'relative' do.
            if. 'auto'-:i prop 'left' do. x=.x-i inset 'right' else. x=.x+i inset 'left' end.
            if. 'auto'-:i prop 'top' do. y0=.y0-i inset 'bottom' else. y0=.y0+i inset 'top' end.
        end.
        Geometry=:x(<i,4)}Geometry
        Geometry=:y0(<i,5)}Geometry
    end.
)
snapshot =: 3 : 0
    result=.0$a:
    for_i. i.#ElementIDs do.
        if. 6{i{Geometry do. result=.result,<borderBox i else. result=.result,<i.0 end.
    end.
    result
)
changes =: 3 : 0
    after=.snapshot''
    result=.0$a:
    for_i. i.#ElementIDs do. if. -.(i{::y)-:i{::after do. result=.result,i{ElementIDs end. end.
    if. #result do. ' 'join result else. 'no change' end.
)
boxText =: 3 : ''' ''join num&.>y'
overflows =: 3 : 0
    if. #y{::Texts do.
        lines=.y{::TextLines
        ((>./#&>lines)>0{y{Geometry)+.(#lines)>1{y{Geometry return.
    end.
    'x y0 w h'=.contentBox y
    for_child. flow y do.
        'a b c d'=.marginBox child
        if. (a<x)+.(b<y0)+.((a+c)>x+w)+.(b+d)>y0+h do. 1 return. end.
    end.
    0
)
render =: 3 : 0
    screen=.(ViewHeight,ViewWidth)$'.'
    for_i. i.#ElementIDs do.
        if. -.6{i{Geometry do. continue. end.
        'x y0 w h'=.borderBox i
        for_yy. (0>.y0)+i.0>.(ViewHeight<.y0+h)-0>.y0 do.
            for_xx. (0>.x)+i.0>.(ViewWidth<.x+w)-0>.x do.
                onrow=.((i number 'border-top')*.yy=y0)+.(i number 'border-bottom')*.yy=y0+h-1
                oncol=.((i number 'border-left')*.xx=x)+.(i number 'border-right')*.xx=x+w-1
                if. onrow*.oncol do. c=.'+' elseif. onrow do. c=.'-' elseif. oncol do. c=.'|' else. c=.' ' end.
                screen=.c(<yy,xx)}screen
            end.
        end.
        if. #i{::Texts do.
            'tx ty cw ch'=.contentBox i
            lines=.i{::TextLines
            for_row. i.#lines do.
                text=.row{::lines
                for_col. i.#text do.
                    xx=.tx+col
                    yy=.ty+row
                    if. (xx>:0)*.(xx<ViewWidth)*.(yy>:0)*.yy<ViewHeight do. screen=.(col{text)(<yy,xx)}screen end.
                end.
            end.
        end.
    end.
    say 'render ',(num ViewWidth),'x',num ViewHeight
    edge=.(ViewWidth+2)#'#'
    say edge
    for_row. screen do. say '#',row,'#' end.
    say edge
)
execute =: 3 : 0
    p=.words y
    command=.0{::p
    select. command
    case. 'LAYOUT' do.
        say 'layout ',(num ViewWidth),'x',num ViewHeight
        for_i. i.#ElementIDs do.
            if. 6{i{Geometry do. box=.boxText borderBox i else. box=.'none' end.
            say ((2*i{Depths)#' '),(i{::ElementIDs),' ',box
        end.
    case. 'BOX';'SET' do.
        id=.1{::p
        i=.ElementIDs i.<id
        if. i=#ElementIDs do. say 'error: unknown element ',id return. end.
        if. command-:'BOX' do.
            if. -.6{i{Geometry do. say 'box ',id,': none'
            else.
                say 'box ',id
                say 'margin ',boxText marginBox i
                say 'border ',boxText borderBox i
                say 'padding ',boxText paddingBox i
                say 'content ',boxText contentBox i
            end.
        else.
            property=.2{::p
            value=.' 'join 3}.p
            if. -.knownProperty property do. say 'error: unknown property ',property return. end.
            declarations=.property expandDecl value
            if. 0=#declarations do. say 'error: invalid value for ',property,': ',value return. end.
            before=.snapshot''
            for_decl. declarations do.
                'name val'=.>decl
                Styles=:(<val)(<i,PropNames i.<name)}Styles
            end.
            performLayout''
            say 'set ',id,' ',property,' ',value,': ',changes before
        end.
    case. 'RENDER' do. render''
    case. 'HIT' do.
        'x y0'=.0".&>1 2{p
        if. (x>:ViewWidth)+.y0>:ViewHeight do. say 'error: point ',(num x),' ',(num y0),' outside viewport' return. end.
        target=._1
        for_i. i.#ElementIDs do.
            'a b w h'=.borderBox i
            if. (6{i{Geometry)*.(a<:x)*.(x<a+w)*.(b<:y0)*.y0<b+h do. target=.i end.
        end.
        path=.0$a:
        while. target>:0 do. path=.(target{ElementIDs),path
            target=.target{Parents end.
        if. #path do. text=.' > 'join path else. text=.'none' end.
        say 'hit ',(num x),' ',(num y0),': ',text
    case. 'VIEWPORT' do.
        'w h'=.0".&>}.p
        if. (w<1)+.(w>80)+.(h<1)+.h>40 do. say 'error: invalid viewport ',(num w),' ',num h return. end.
        before=.snapshot''
        ViewWidth=:w
        ViewHeight=:h
        performLayout''
        say 'viewport ',(num w),' ',(num h),': ',changes before
    case. 'OVERFLOW' do.
        result=.0$a:
        for_i. i.#ElementIDs do. if. 6{i{Geometry do. if. overflows i do. result=.result,i{ElementIDs end. end. end.
        if. #result do. text=.' 'join result else. text=.'none' end.
        say 'overflow: ',text
    case. do. say 'error: unknown command ',command
    end.
)
main =: 3 : 0
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    'ViewWidth ViewHeight'=:0".&>words 0{::lines
    rules=.0$a:
    at=.1
    while. -. '---'-:at{::lines do.
        line=.at{::lines
        boundary=.{.I.' { 'E.line
        selectors=.', 'splitBy boundary{.line
        body=._2}.(boundary+3)}.line
        declarations=.0$a:
        for_decl. '; 'splitBy body do.
            decl=.>decl
            colon=.{.I.': 'E.decl
            declarations=.declarations,(colon{.decl)expandDecl (colon+2)}.decl
        end.
        rules=.rules,<(<selectors),<declarations
        at=.at+1
    end.
    at=.at+1
    ElementIDs=:Tags=:Classes=:Texts=:Children=:TextLines=:0$a:
    Parents=:Depths=:i.0
    Styles=:(0,#PropNames)$a:
    Geometry=:0 7$0
    stack=.i.0
    while. -.'==='-:at{::lines do.
        line=.at{::lines
        spaces=.0
        while. spaces<#line do. if. ' '~:spaces{line do. break. end.
            spaces=.spaces+1 end.
        depth=.<.spaces%2
        rest=.spaces}.line
        headend=.{.I.' '=rest,' '
        head=.headend{.rest
        text=.''
        if. headend<#rest do. text=.}.}:(headend+1)}.rest end.
        hash=.{.I.'#'=head
        tag=.hash{.head
        names=. '.'splitBy (hash+1)}.head
        id=.0{::names
        classes=.}.names
        stack=.depth{.stack
        parent=._1
        if. #stack do. parent=.{:stack end.
        i=.#ElementIDs
        ElementIDs=:ElementIDs,<id
        Tags=:Tags,<tag
        Classes=:Classes,<classes
        Texts=:Texts,<text
        Parents=:Parents,parent
        Depths=:Depths,depth
        Children=:Children,<i.0
        TextLines=:TextLines,<0$a:
        style=.Initial
        winners=.(#PropNames)$_1
        for_rule. rules do.
            'selectors declarations'=.>rule
            specificity=._1
            for_selector. selectors do.
                selector=.>selector
                score=._1
                if. '#'={.selector do. if. (}.selector)-:id do. score=.2 end.
                elseif. '.'={.selector do. if. (<}.selector)e.classes do. score=.1 end.
                elseif. selector-:tag do. score=.0 end.
                specificity=.specificity>.score
            end.
            if. specificity<0 do. continue. end.
            for_decl. declarations do.
                'property value'=.>decl
                p=.PropNames i.<property
                if. specificity>:p{winners do. winners=.specificity p}winners
                    style=.(<value)p}style end.
            end.
        end.
        Styles=:Styles,style
        Geometry=:Geometry,0 0 0 0 0 0 0
        if. parent>:0 do. Children=:(<(parent{::Children),i)parent}Children end.
        stack=.stack,i
        at=.at+1
    end.
    performLayout''
    at=.at+1
    while. -.'END'-:at{::lines do. execute at{::lines
        at=.at+1 end.
)
main''
