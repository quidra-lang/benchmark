Modifiers =: ;:'AUTO COR'
ModifierWords =: 'automated';'corrected'
Descriptors =: ;:'MI BC PR DR BL SH TS FZ'
DescriptorWords =: 'shallow';'patches';'partial';'low drifting';'blowing';'showers';'thunderstorm';'freezing'
Phenomena =: ;:'DZ RA SN SG IC PL GR GS UP BR FG FU VA DU SA HZ PY PO SQ FC SS DS'
PhenomenonWords =: 'drizzle';'rain';'snow';'snow grains';'ice crystals';'ice pellets';'hail';'small hail';'unknown precipitation';'mist';'fog';'smoke';'volcanic ash';'dust';'sand';'haze';'spray';'dust whirls';'squalls';'funnel cloud';'sandstorm';'duststorm'
Precipitation =: 9{.Phenomena
Amounts =: ;:'FEW SCT BKN OVC'
AmountWords =: ;:'few scattered broken overcast'
Clear =: ;:'SKC CLR NSC'
ClearWords =: 'sky clear';'clear below 12000 ft';'no significant cloud'
CloudTypes =: ;:'CB TCU'
CloudTypeWords =: 'cumulonimbus';'towering cumulus'
NB. Section fields follow the ten METAR slots. NONE and empty lists differ.
section =: 3 : '(<''''),(<NONE),(<NONE),(<NONE),(<0$a:),(<NONE),(<NONE),(<NONE),(<NONE),<0'
state =: 3 : '1 3 5 6{y'
calm =: 3 : '(-.0{::y)*.(0=1{::y)*.0=2{::y'
directed =: 3 : '(-.0{::y)*.-.calm y'
strength =: 3 : 'if. _1=3{::y do. 2{::y else. 3{::y end.'
parse_fraction =: 3 : 0
    p =. '/' split y
    if. 2~:#p do. NONE return. end.
    if. (-.1 1 width 0{::p)+.-.1 2 width 1{::p do. NONE return. end.
    num&>p
)
parse_wind =: 3 : 0
    t =. y
    if. 'KT'-:_2{.t do. unit =. 'KT'
    t =. _2}.t
    elseif. 'MPS'-:_3{.t do. unit =. 'MPS'
    t =. _3}.t
    else. NONE return. end.
    d =. 3{.t
    if. (-.d-:'VRB')*.-.3 3 width d do. NONE return. end.
    p =. 'G' split 3}.t
    if. (#p)>2 do. NONE return. end.
    if. -.*./(2 3)&width&>p do. NONE return. end.
    speed =. num 0{::p
    gust =. NONE
    if. 2=#p do. gust =. num 1{::p end.
    variable =. d-:'VRB'
    direction =. 0
    if. -.variable do. direction =. num d end.
    (<variable),(<direction),(<speed),(<gust),<unit
)
parse_visibility =: 3 : 0
    t =. y
    if. t-:'CAVOK' do. 'CAVOK';'P';10000;0;0;0;0 return. end.
    if. 4 4 width t do.
        if. t-:'9999' do. 'METERS';'P';10000;0;0;0;0
        else. (<'METERS'),(<''),(<num t),(<0),(<0),(<0),<0 end. return.
    end.
    if. -.'SM'-:_2{.t do. NONE return. end.
    t =. _2}.t
    p =. ' ' split t
    whole =. numerator =. denominator =. joined =. 0
    qual =. ''
    if. 2=#p do.
        if. -.1 1 width 0{::p do. NONE return. end.
        f =. parse_fraction 1{::p
        if. isnone f do. NONE return. end.
        whole =. num 0{::p
        'numerator denominator' =. f
        joined =. 1
    elseif. 1=#p do.
        if. ({.t)e.'MP' do. qual =. 1{.t
        t =. }.t end.
        if. 1 2 width t do. whole =. num t
        else.
            f =. parse_fraction t
            if. isnone f do. NONE return. end.
            'numerator denominator' =. f
        end.
    else. NONE return. end.
    (<'MILES'),(<qual),(<0),(<whole),(<numerator),(<denominator),<joined
)
parse_reading =: 3 : 0
    t =. y
    q =. ''
    if. ({.t)e.'MP' do. q =. 1{.t
    t =. }.t end.
    if. -.4 4 width t do. NONE return. end.
    (<q),<num t
)
parse_rvr =: 3 : 0
    if. 'R'~:{.y do. NONE return. end.
    p =. '/' split }.y
    if. 2~:#p do. NONE return. end.
    runway =. 0{::p
    t =. 1{::p
    if. (-.2 2 width 2{.runway)+.-.(<2}.runway)e.'';'L';'C';'R' do. NONE return. end.
    trend =. ''
    if. ({:t)e.'UDN' do. trend =. _1{.t
    t =. }:t end.
    feet =. 'FT'-:_2{.t
    if. feet do. t =. _2}.t end.
    p =. 'V' split t
    if. (#p)>2 do. NONE return. end.
    readings =. parse_reading&.>p
    if. +./isnone&>readings do. NONE return. end.
    (<runway),(<readings),(<feet),<trend
)
parse_weather =: 3 : 0
    if. y-:'NSW' do. (<''),(<0$a:),<'NSW' return. end.
    t =. y
    intensity =. ''
    if. ({.t)e.'-+' do. intensity =. 1{.t
    t =. }.t
    elseif. 'VC'-:2{.t do. intensity =. 'VC'
    t =. 2}.t end.
    if. (0=#t)+.2|#t do. NONE return. end.
    codes =. 0$a:
    while. #t do. codes =. codes,<2{.t
    t =. 2}.t end.
    if. -.*./codes e.Descriptors,Phenomena do. NONE return. end.
    (<intensity),(<codes),<y
)
parse_cloud =: 3 : 0
    if. (<y)e.Clear do. (<y),(<NONE),(<'') ,<y return. end.
    if. ('VV'-:2{.y)*.3 3 width 2}.y do. (<'VV'),(<100*num 2}.y),(<'') ,<y return. end.
    a =. 3{.y
    h =. 3{.3}.y
    c =. 6}.y
    if. ((<a)e.Amounts)*.(3 3 width h)*.(<c)e.(<''),CloudTypes do.
        (<a),(<100*num h),(<c),<y
    else. NONE end.
)
celsius =: 3 : 0
    t =. y
    sign =. 1
    if. 'M'={.t do. sign =. _1
    t =. }.t end.
    if. -.2 2 width t do. NONE return. end.
    sign*num t
)
parse_group =: 4 : 0
    select. x
    case. 0 do. if. (<y)e.Modifiers do. y else. NONE end.
    case. 1 do. parse_wind y
    case. 2 do.
        if. 7~:#y do. NONE return. end.
        if. ('V'=3{y)*.(3 3 width 3{.y)*.3 3 width 4}.y do.
            (num 3{.y),num 4}.y
        else. NONE end.
    case. 3 do. parse_visibility y
    case. 4 do. parse_rvr y
    case. 5 do. parse_weather y
    case. 6 do. parse_cloud y
    case. 7 do.
        p =. '/' split y
        if. 2~:#p do. NONE return. end.
        NB. M01 legitimately equals the NONE numeric sentinel; validate syntax first.
        for_b. p do.
            t =. >b
            if. 'M'={.t do. t =. }.t end.
            if. -.2 2 width t do. NONE return. end.
        end.
        celsius&>p
    case. 8 do.
        if. (({.y)e.'AQ')*.4 4 width }.y do. (<1{.y),<num }.y else. NONE end.
    case. 9 do. if. y-:'NOSIG' do. 1 else. NONE end.
    end.
)
descriptor =: 3 : 0
    codes =. 1{::y
    if. #codes do. if. ({.codes)e.Descriptors do. >{.codes return. end. end.
    ''
)
phenomena =: 3 : '((1{::y)e.Phenomena)#1{::y'
valid_group =: 4 : 0
    'v s nsw runways' =. y
    select. x
    case. 1 do.
        'variable d speed gust unit' =. v
        if. variable do. if. speed<1 do. 0 return. end.
        else.
            if. (d>360)+.(0~:10|d)+.(d=0)~:speed=0 do. 0 return. end.
        end.
        (gust=_1)+.(-.calm v)*.gust>speed
    case. 2 do.
        if. isnone 1{::s do. 0 return. end.
        (*./v e.10*i.>:36)*.(0~:0{v)*.(0~:1{v)*.((0{v)~:1{v)*.directed 1{::s
    case. 3 do.
        'kind qual meters whole p q joined' =. v
        if. -.kind-:'MILES' do. 1 return. end.
        if. q=0 do. (-.joined)*.whole>:1 else. ((-.joined)+.whole>:1)*.(q e.2 4 8 16)*.(p>:1)*.p<q end.
    case. 4 do.
        'runway readings feet trend' =. v
        if. -.(<runway)e.runways do. 0 return. end.
        if. 1=#readings do. 1 else. (1{::0{::readings)<1{::1{::readings end.
    case. 5 do.
        accepted =. 5{::s
        if. isnone accepted do. accepted =. 0$a: end.
        if. 3<:#accepted do. 0 return. end.
        for_b. accepted do. if. 'NSW'-:2{::>b do. 0 return. end. end.
        if. 'NSW'-:2{::v do. nsw*.0=#accepted return. end.
        codes =. 1{::v
        intensity =. 0{::v
        if. +./(}.codes)e.Descriptors do. 0 return. end.
        p =. phenomena v
        if. (#~.p)~:#p do. 0 return. end.
        if. (0=#p)*.-.(<descriptor v)e.;:'TS SH' do. 0 return. end.
        if. ((<intensity)e.'-';'+')*.-.+./p e.Precipitation do. 0 return. end.
        (2>#p)+.*./p e.Precipitation
    case. 6 do.
        accepted =. 6{::s
        if. (isnone accepted)+.0=#accepted do. 1 return. end.
        last =. >{:accepted
        if. (-.(<0{::v)e.Amounts)+.-.(<0{::last)e.Amounts do. 0 return. end.
        (1{::v)>1{::last
    case. 7 do. (1{v)<:0{v
    case. 8 do.
        'u n' =. v
        if. u-:'A' do. (2500<:n)*.n<:3150 else. (850<:n)*.n<:1070 end.
    case. do. 1
    end.
)
record_group =: 4 : 0
    'kind value' =. x
    if. kind=1 do.
        unit =. 4{::value
        speed =. unit knots 2{::value
        gust =. 3{::value
        if. gust~:_1 do. gust =. unit knots gust end.
        value =. (<speed) 2}value
        value =. (<gust) 3}value
    elseif. kind e.4 5 6 do.
        old =. kind{::y
        if. isnone old do. old =. 0$a: end.
        value =. old,<value
    end.
    (<value) kind}y
)
