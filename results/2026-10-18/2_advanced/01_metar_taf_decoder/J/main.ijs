ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'units.ijs'
load SourceDirectory,'groups.ijs'
load SourceDirectory,'metar.ijs'
load SourceDirectory,'taf.ijs'
load SourceDirectory,'verification.ijs'

error =: 4 : 0
    Errors =: Errors,<(<x),<y
    i.0
)
read_stations =: 3 : 0
    stations =. 0$a:
    for_b. lines 'input/stations.txt' do.
        ws =. ' ' split >b
        runways =. 0$a:
        for_r. ',' split 2{::ws do.
            p =. '/' split >r
            runways =. runways,<(<0{::p),<num 1{::p
        end.
        elev =. 1{::ws
        sign =. 1
        if. '-'={.elev do. elev =. }.elev
        sign =. _1 end.
        stations =. stations,<(<0{::ws),(<sign*num elev),(<runways),<' ' join 3}.ws
    end.
    stations
)
read_settings =: 3 : 0
    p =. ' '&split&.>lines 'input/params.txt'
    Calendar =: calendar (num 1{::0{::p),num 1{::1{::p
    CrosswindLimit =: num 1{::2{::p
    TailwindLimit =: num 1{::3{::p
    Verify =: }.4{::p
    i.0
)
read_reports =: 3 : 0
    reports =. 0$a:
    for_b. lines 'input/reports.txt' do.
        line =. >b
        continued =. ' '={.line
        while. ' '={.line do. line =. }.line end.
        ws =. ' ' split line
        if. continued do. reports =. (}:reports),< (>{:reports),ws
        else. reports =. reports,<ws end.
    end.
    reports
)
parse_time =: 3 : 0
    if. 7~:#y do. NONE return. end.
    if. ('Z'~:{:y)+.-.6 6 width 6{.y do. NONE return. end.
    d =. num 2{.y
    h =. num 2{.2}.y
    m =. num 2{.4}.y
    if. (d<1)+.(d>2{Calendar)+.(h>23)+.m>59 do. NONE return. end.
    dayminutes d,h,m
)
join_groups =: 4 : 0
    ws =. y
    i =. x
    gs =. 0$a:
    while. i<#ws do.
        pos =. i+1
        t =. i{::ws
        i =. i+1
        if. (1 1 width t)*.i<#ws do.
            following =. i{::ws
            if. 'SM'-:_2{.following do.
                f =. parse_fraction _2}.following
                if. -.isnone f do. t =. t,' ',following
                i =. i+1 end.
            end.
        end.
        gs =. gs,<(<pos),<t
    end.
    gs
)
parse_header =: 3 : 0
    ws =. y
    kind =. 0{::y
    if. -.(<kind)e.;:'METAR SPECI TAF' do.
        1 error 'rejected report, invalid type "',kind,'"'
        NONE return.
    end.
    i =. 1
    modifier =. ''
    station =. time =. start =. finish =. NONE
    if. kind-:'TAF' do.
        if. i<#ws do.
            if. (<i{::ws)e.;:'AMD COR' do. modifier =. i{::ws
            i =. i+1 end.
        end.
    end.
    items =. ;:'station time'
    if. kind-:'TAF' do. items =. items,<'validity' end.
    for_b. items do.
        item =. >b
        if. i=#ws do. (i+1) error 'rejected report, missing ',item
        NONE return. end.
        w =. i{::ws
        valid =. 0
        select. item
        case. 'station' do.
            for_j. i.#Stations do.
                if. w-:0{::j{::Stations do. station =. j
                valid =. 1
                break. end.
            end.
        case. 'time' do. time =. parse_time w
        valid =. -.isnone time
        case. 'validity' do.
            p =. (dayof time) period w
            if. -.isnone p do. 'start finish' =. p
            valid =. finish<:start+1800 end.
        end.
        if. -.valid do. (i+1) error 'rejected report, invalid ',item,' "',w,'"'
        NONE return. end.
        i =. i+1
    end.
    (<kind),(<modifier),(<station),(<time),(<start),(<finish),<i join_groups ws
)
NB. Matching advances only after acceptance; CAVOK skips weather and cloud slots.
match_groups =: 4 : 0
    'slots nsw runways' =. x
    s =. section ''
    current =. 0
    for_b. y do.
        'pos text' =. >b
        index =. NONE
        value =. NONE
        for_j. current+i.(#slots)-current do.
            value =. (j{slots) parse_group text
            if. -.isnone value do. index =. j
            break. end.
        end.
        if. index=_1 do.
            label =. 'unknown group'
            for_j. i.current do.
                if. -.isnone (j{slots) parse_group text do. label =. 'out of order group'
                break. end.
            end.
            pos error label,' "',text,'"'
            continue.
        end.
        kind =. index{slots
        if. -.kind valid_group (<value),(<s),(<nsw),<runways do.
            pos error 'invalid group "',text,'"'
            continue.
        end.
        s =. ((<kind),<value) record_group s
        if. (kind=3)*.'CAVOK'-:0{::value do.
            s =. (<0$a:) 5}s
            s =. (<0$a:) 6}s
            current =. 1+slots i.6
        else. current =. index+-.kind e.Repeatable end.
    end.
    s
)
forecast_state =: 4 : 'state ((<TafSlots),(<x),<0$a:) match_groups y'
decode_forecast =: 4 : 0
    h =. y
    f =. (<x),(<2{::h),(<3{::h),(<1{::h),(<4{::h),(<5{::h),(<NONE),<0$a:
    'base changes' =. f split_changes 6{::h
    f =. (<0 forecast_state base) 6}f
    decoded =. 0$a:
    for_b. changes do.
        c =. >b
        c =. (<1 forecast_state 3{::c) 4}c
        decoded =. decoded,<c
    end.
    (<decoded) 7}f
)
ceiling =: 3 : 0
    clouds =. 3{::y
    if. isnone clouds do. NONE return. end.
    for_b. clouds do.
        c =. >b
        if. (<0{::c)e.;:'BKN OVC VV' do. 1{::c return. end.
    end.
    NONE
)
category =: 3 : 0
    c =. ceiling y
    if. isnone c do. c =. 1000000 end.
    p =. 1x
    q =. 0x
    if. -.isnone 1{::y do. 'p q' =. miles 1{::y end.
    if. (c<500)+.p<q do. 'LIFR'
    elseif. (c<1000)+.p<3*q do. 'IFR'
    elseif. (c<:3000)+.p<:5*q do. 'MVFR'
    else. 'VFR' end.
)
inhg_value =: 3 : 'if. ''A''-:0{::y do. 1{::y else. inhg 1{::y end.'
components =: 3 : 0
    'direction heading speed' =. y
    angle =. direction-heading
    ((speed*icos angle) div 1000),(speed*isin angle) div 1000
)
runway_winds =: 4 : 0
    wind =. y
    if. isnone wind do. NONE return. end.
    if. -.directed wind do. NONE return. end.
    winds =. 0$a:
    for_b. 2{::x{::Stations do.
        r =. >b
        mean =. components (1{::wind),(1{::r),2{::wind
        gust =. NONE
        if. _1~:3{::wind do. gust =. components (1{::wind),(1{::r),3{::wind end.
        deciding =. mean
        if. -.isnone gust do. deciding =. gust end.
        usable =. ((|1{deciding)<:CrosswindLimit)*.(-0{deciding)<:TailwindLimit
        winds =. winds,<(<0{::r),(<mean),(<gust),<usable
    end.
    winds
)
wind_changes =: 3 : 0
    'a b alpha' =. y
    reasons =. 0$a:
    if. (isnone a)+.isnone b do. reasons return. end.
    d =. 360|| (1{::a)-1{::b
    if. (directed a)*.(directed b)*.(10<:(2{::a)>.2{::b)*.(d<.360-d)>:alpha do.
        reasons =. reasons,<'wind shift'
    end.
    if. 10<:|(2{::a)-2{::b do. reasons =. reasons,<'wind speed' end.
    reasons
)
has_thunderstorm =: 3 : 0
    w =. 2{::y
    if. isnone w do. 0 return. end.
    for_b. w do. if. 'TS'-:descriptor >b do. 1 return. end. end.
    0
)
has_freezing =: 3 : 0
    w =. 2{::y
    if. isnone w do. 0 return. end.
    for_b. w do.
        if. ('FZ'-:descriptor >b)*.+./(phenomena >b)e.;:'DZ RA' do. 1 return. end.
    end.
    0
)
speci_reasons =: 4 : 0
    if. isnone x do. <'no previous report' return. end.
    before =. state 4{::x
    now =. state 4{::y
    reasons =. 0$a:
    if. -.(9{::x)-:9{::y do. reasons =. reasons,<'category ',(9{::x),' to ',9{::y end.
    reasons =. reasons,wind_changes (<0{::before),(<0{::now),<45
    if. (has_thunderstorm before)~:has_thunderstorm now do.
        if. has_thunderstorm now do. text =. 'thunderstorm began' else. text =. 'thunderstorm ended' end.
        reasons =. reasons,<text
    end.
    if. (has_freezing before)~:has_freezing now do.
        if. has_freezing now do. text =. 'freezing precipitation began' else. text =. 'freezing precipitation ended' end.
        reasons =. reasons,<text
    end.
    if. 0=#reasons do. <'no criteria met' else. reasons end.
)
decode_observation =: 4 : 0
    'number h previous' =. y
    station =. 2{::h
    runways =. 0$a:
    for_b. 2{::station{::Stations do. runways =. runways,<0{::>b end.
    'mainpart trendpart remarks' =. split_body 6{::h
    s =. ((<MainSlots),(<0),<runways) match_groups mainpart
    trends =. 0$a:
    for_b. trend_sections trendpart do.
        t =. read_trend >b
        if. -.isnone t do.
            ts =. ((<TrendSlots),(<1),<0$a:) match_groups 2{::t
            trends =. trends,<t,<state ts
        end.
    end.
    'slp temps' =. read_remarks remarks
    st =. state s
    pa =. da =. NONE
    if. -.isnone 8{::s do.
        pa =. (1{::station{::Stations)+10*2992-inhg_value 8{::s
        if. -.isnone 7{::s do.
            da =. pa+(120*((1000*0{7{::s)-15000)+2*pa) div 1000
        end.
    end.
    o =. (<number),(<0{::h),(<station),(<3{::h),(<s),(<trends),(<slp),(<temps),(<ceiling st),(<category st),(<pa),(<da),(<station runway_winds 0{::st),<0$a:
    if. 'SPECI'-:0{::h do. o =. (<previous speci_reasons o) 13}o end.
    o
)

qualifier_word =: 3 : 0
    if. y-:'M' do. 'less than ' elseif. y-:'P' do. 'more than ' else. '' end.
)
wind_phrase =: 3 : 0
    'variable d speed gust unit' =. y
    if. calm y do. t =. 'calm'
    elseif. variable do. t =. 'variable at ',(number speed),' KT'
    else. t =. (3 pad d),' degrees at ',(number speed),' KT' end.
    if. gust~:_1 do. t =. t,' gusting ',(number gust),' KT' end.
    t
)
mile_number =: 3 : 0
    'kind qual meters whole p q joined' =. y
    if. q=0 do. number whole return. end.
    t =. (number p),'/',number q
    if. whole>0 do. t =. (number whole),' ',t end.
    t
)
visibility_phrase =: 3 : 0
    'kind qual meters whole p q joined' =. y
    if. kind-:'CAVOK' do. '10 km or more (CAVOK)'
    elseif. kind-:'METERS' do.
        if. qual-:'P' do. '10 km or more' else. (number meters),' m' end.
    else. (qualifier_word qual),(mile_number y),' SM' end.
)
weather_phrase =: 3 : 0
    'intensity codes text' =. y
    if. text-:'NSW' do. 'no significant weather' return. end.
    parts =. 0$a:
    if. #intensity do. parts =. parts,<((;:'- + VC')i.<intensity){::;:'light heavy nearby' end.
    d =. descriptor y
    if. #d do. parts =. parts,<(Descriptors i.<d){::DescriptorWords end.
    ps =. phenomena y
    if. #ps do. parts =. parts,<' and ' join (Phenomena i.ps){PhenomenonWords end.
    ' ' join parts
)
cloud_phrase =: 3 : 0
    'amount height ctype text' =. y
    if. (<amount)e.Clear do. (Clear i.<amount){::ClearWords return. end.
    if. amount-:'VV' do. 'vertical visibility ',(number height),' ft' return. end.
    t =. ((Amounts i.<amount){::AmountWords),' at ',(number height),' ft'
    if. #ctype do. t =. t,' ',(CloudTypes i.<ctype){::CloudTypeWords end.
    t
)
summary =: 3 : 0
    'wind visibility weather cloud' =. y
    parts =. 0$a:
    if. -.isnone wind do. parts =. parts,<'wind ',wind_phrase wind end.
    if. -.isnone visibility do. parts =. parts,<'visibility ',visibility_phrase visibility end.
    if. -.isnone weather do.
        if. #weather do. parts =. parts,<'weather ',', ' join weather_phrase&.>weather end.
    end.
    if. -.isnone cloud do.
        if. #cloud do. parts =. parts,<'cloud ',', ' join cloud_phrase&.>cloud end.
    end.
    if. #parts do. '; ' join parts else. 'no conditions' end.
)
wind_code =: 3 : 0
    if. calm y do. '00000KT' return. end.
    'variable d speed gust unit' =. y
    if. variable do. t =. 'VRB' else. t =. 3 pad d end.
    t =. t,2 pad speed
    if. gust~:_1 do. t =. t,'G',2 pad gust end.
    t,'KT'
)
visibility_code =: 3 : 0
    'kind qual meters whole p q joined' =. y
    if. kind-:'CAVOK' do. 'CAVOK'
    elseif. kind-:'METERS' do. if. qual-:'P' do. '9999' else. 4 pad meters end.
    else. qual,(mile_number y),'SM' end.
)
tokens =: 3 : 0
    'wind visibility weather cloud' =. y
    parts =. 0$a:
    if. -.isnone wind do. parts =. parts,<wind_code wind end.
    if. -.isnone visibility do. parts =. parts,<visibility_code visibility end.
    if. -.isnone weather do.
        for_b. weather do. if. -.'NSW'-:2{::>b do. parts =. parts,<2{::>b end. end.
    end.
    if. -.isnone cloud do. for_b. cloud do. parts =. parts,<3{::>b end. end.
    ' ' join parts,<category y
)
tenths_text =: 3 : 0
    sign =. ''
    if. y<0 do. sign =. '-' end.
    sign,(number (|y) div 10),'.',number 10||y
)
inhg_text =: 3 : '(number y div 100),''.'',2 pad 100|y'
component_phrase =: 3 : 0
    'head cross' =. y
    if. head<0 do. t =. 'tailwind ',(number -head),' KT'
    else. t =. 'headwind ',(number head),' KT' end.
    t =. t,', crosswind ',(number |cross),' KT'
    if. cross>0 do. t,' from right' elseif. cross<0 do. t,' from left' else. t end.
)
rvr_phrase =: 3 : 0
    'runway readings feet trend' =. y
    texts =. 0$a:
    for_b. readings do.
        'qual value' =. >b
        texts =. texts,<(qualifier_word qual),number value
    end.
    t =. 'runway ',runway,' '
    if. 1=#texts do. t =. t,0{::texts else. t =. t,'between ',' and ' join texts end.
    if. feet do. t =. t,' ft' else. t =. t,' m' end.
    if. #trend do. t =. t,', ',(('UDN'i.{.trend){::'rising';'falling';'no change') end.
    t
)
temperature_phrase =: 3 : 0
    if. isnone y do. 'not reported' return. end.
    'air dew' =. y
    (number air),' C, dew point ',(number dew),' C, spread ',(number air-dew),' C'
)
altimeter_phrase =: 3 : 0
    if. isnone y do. 'not reported' return. end.
    'unit value' =. y
    a =. inhg_text inhg_value y
    if. unit-:'A' do. a,' inHg (',(number hpa value),' hPa)'
    else. (number value),' hPa (',a,' inHg)' end.
)
station_title =: 3 : 0
    s =. y{::Stations
    (0{::s),' (',(3{::s),')'
)
observation_lines =: 3 : 0
    'rn kind station time main trends slp temps ceil cat pa da winds reasons' =. y
    'wind visibility weather cloud' =. state main
    ls =. (<'REPORT ',(number rn),': ',kind,' ',station_title station),<'  time: ',stamp time
    modifier =. 0{::main
    if. #modifier do. ls =. ls,<'  modifier: ',(Modifiers i.<modifier){::ModifierWords end.
    w =. 'not reported'
    if. -.isnone wind do. w =. wind_phrase wind end.
    variation =. 2{::main
    if. -.isnone variation do. w =. w,', varying between ',(3 pad 0{variation),' and ',(3 pad 1{variation),' degrees' end.
    ls =. ls,<'  wind: ',w
    if. isnone visibility do. v =. 'not reported' else. v =. visibility_phrase visibility end.
    ls =. ls,<'  visibility: ',v
    for_b. 4{::main do. ls =. ls,<'  runway visual range: ',rvr_phrase >b end.
    if. -.isnone weather do. for_b. weather do. ls =. ls,<'  weather: ',weather_phrase >b end. end.
    cavok =. 0
    if. -.isnone visibility do. cavok =. 'CAVOK'-:0{::visibility end.
    if. cavok do. ls =. ls,<'  cloud: no significant cloud'
    elseif. isnone cloud do. ls =. ls,<'  cloud: not reported'
    else. for_b. cloud do. ls =. ls,<'  cloud: ',cloud_phrase >b end. end.
    ls =. ls,<'  temperature: ',temperature_phrase 7{::main
    ls =. ls,<'  altimeter: ',altimeter_phrase 8{::main
    if. 9{::main do. ls =. ls,<'  trend: no significant change' end.
    for_b. trends do.
        'tk times gs ts' =. >b
        if. tk-:'BECMG' do. t =. 'becoming' else. t =. 'temporarily' end.
        for_time. times do.
            'prefix hour minute' =. >time
            word =. ((;:'FM TL AT')i.<prefix){::;:'from until at'
            t =. t,' ',word,' ',(2 pad hour),':',(2 pad minute),'Z'
        end.
        ls =. ls,<'  trend: ',t,': ',summary ts
    end.
    for_b. slp do. ls =. ls,<'  sea level pressure: ',(tenths_text >b),' hPa' end.
    for_b. temps do.
        'air dew' =. >b
        ls =. ls,<'  precise temperature: ',(tenths_text air),' C, dew point ',(tenths_text dew),' C'
    end.
    if. isnone ceil do. c =. 'none' else. c =. (number ceil),' ft' end.
    ls =. ls,<'  ceiling: ',c
    ls =. ls,<'  flight category: ',cat
    NB. An altitude of negative one is valid; presence follows pressure and temperature.
    pat =. dat =. 'not available'
    if. -.isnone 8{::main do.
        pat =. (number pa),' ft'
        if. -.isnone 7{::main do. dat =. (number da),' ft' end.
    end.
    ls =. ls,<'  pressure altitude: ',pat
    ls =. ls,<'  density altitude: ',dat
    if. isnone winds do. ls =. ls,<'  runway wind: not computed'
    else.
        usable =. 0$a:
        preferred =. 'none'
        best =. NONE
        for_b. winds do.
            'name mean gust ok' =. >b
            t =. '  runway ',name,': ',component_phrase mean
            if. -.isnone gust do. t =. t,'; gusts ',component_phrase gust end.
            ls =. ls,<t
            if. ok do.
                usable =. usable,<name
                if. preferred-:'none' do. preferred =. name
                best =. 0{mean
                elseif. best<0{mean do. preferred =. name
                best =. 0{mean end.
            end.
        end.
        if. #usable do. u =. ' ' join usable else. u =. 'none' end.
        ls =. ls,<'  usable runways: ',u
        ls =. ls,<'  preferred runway: ',preferred
    end.
    if. kind-:'SPECI' do. ls =. ls,<'  speci check: ',', ' join reasons end.
    ls
)
forecast_lines =: 3 : 0
    'rn station issue modifier start finish base changes' =. y
    ls =. (<'REPORT ',(number rn),': TAF ',station_title station),<'  issued: ',stamp issue
    if. #modifier do.
        if. modifier-:'AMD' do. word =. 'amended' else. word =. 'corrected' end.
        ls =. ls,<'  modifier: ',word
    end.
    ls =. ls,<'  valid: ',(stamp start),' to ',stamp finish
    ls =. ls,<'  base: ',summary base
    for_b. changes do.
        'kind s e gs st' =. >b
        t =. stamp s
        if. -.kind-:'FM' do. t =. t,' to ',stamp e end.
        ls =. ls,<'  ',kind,' ',t,': ',summary st
    end.
    ls
)
category_counts =: 3 : 0
    parts =. 0$a:
    for_b. Categories do. parts =. parts,<(>b),' ',number +/b=y end.
    ', ' join parts
)
category_lines =: 3 : 0
    ls =. <'station,time,ceiling,visibility,category'
    for_b. y do.
        o =. >b
        c =. 'NONE'
        v =. 'NONE'
        if. -.isnone 8{::o do. c =. number 8{::o end.
        visibility =. 3{::4{::o
        if. -.isnone visibility do. v =. (1{::visibility),number meter_value visibility end.
        code =. 0{::(2{::o){::Stations
        ls =. ls,<code,',',(stamp 3{::o),',',c,',',v,',',9{::o
    end.
    ls
)
timeline_lines =: 3 : 0
    f =. y
    code =. 0{::(1{::f){::Stations
    ls =. <'TAF ',code,' issued ',(stamp 2{::f),' valid ',(stamp 4{::f),' to ',stamp 5{::f
    cs =. 0$a:
    for_h. (4{::f)+60*i.((5{::f)-4{::f) div 60 do.
        s =. f prevailing h
        t =. (stamp h),' ',tokens s
        for_b. f temporary h do.
            'kind ts' =. >b
            t =. t,' | ',kind,' ',tokens ts
        end.
        ls =. ls,<t
        cs =. cs,<category s
    end.
    ls,<'summary: ',category_counts cs
)
extreme_lines =: 3 : 0
    cold =. warm =. windy =. lowcloud =. lowvis =. NONE
    for_b. y do.
        o =. >b
        m =. 4{::o
        temp =. 7{::m
        if. -.isnone temp do.
            if. isnone cold do. cold =. o
            elseif. (0{temp)<0{7{::4{::cold do. cold =. o end.
            if. isnone warm do. warm =. o
            elseif. (0{temp)>0{7{::4{::warm do. warm =. o end.
        end.
        wind =. 1{::m
        if. -.isnone wind do.
            if. isnone windy do. windy =. o
            elseif. (strength wind)>strength 1{::4{::windy do. windy =. o end.
        end.
        ceil =. 8{::o
        if. -.isnone ceil do.
            if. isnone lowcloud do. lowcloud =. o
            elseif. ceil<8{::lowcloud do. lowcloud =. o end.
        end.
        vis =. 3{::m
        if. -.isnone vis do.
            if. isnone lowvis do. lowvis =. o
            elseif. (miles vis) fraction_less miles 3{::4{::lowvis do. lowvis =. o end.
        end.
    end.
    labels =. 'lowest temperature';'highest temperature';'strongest wind';'lowest ceiling';'lowest visibility'
    found =. (<cold),(<warm),(<windy),(<lowcloud),<lowvis
    ls =. 0$a:
    for_i. i.5 do.
        o =. i{::found
        t =. 'not available'
        if. -.isnone o do.
            select. i
            case. 0;1 do. t =. (number 0{7{::4{::o),' C'
            case. 2 do. t =. wind_phrase 1{::4{::o
            case. 3 do. t =. (number 8{::o),' ft'
            case. 4 do. t =. visibility_phrase 3{::4{::o
            end.
            t =. t,' at ',stamp 3{::o
        end.
        ls =. ls,<(i{::labels),': ',t
    end.
    ls
)
table_row =: 4 : 0
    t =. x,(0>.8-#x)#' '
    for_b. y do.
        v =. >b
        if. 2~:3!:0 v do. v =. number v end.
        t =. t,((0>.6-#v)#' '),v
    end.
    t
)
bucket_lines =: 4 : 0
    pairs =. hits =. 5$0x
    for_fb. x do.
        f =. >fb
        for_ob. y do.
            o =. >ob
            if. f covers 3{::o do.
                h =. hourmark 3{::o
                b =. (h-4{::f) div 360
                pairs =. (1+b{pairs) b}pairs
                hit =. (category f prevailing h)-:9{::o
                hits =. (hit+b{hits) b}hits
            end.
        end.
    end.
    ls =. 0$a:
    for_b. i.5 do.
        ls =. ls,<'hours ',(number 6*b),'-',(number 5+6*b),': ',fraction (b{hits),b{pairs
    end.
    ls
)
verification_lines =: 3 : 0
    'station observations forecasts' =. y
    os =. fs =. 0$a:
    for_b. observations do. if. station=2{::>b do. os =. os,b end. end.
    for_b. forecasts do. if. station=1{::>b do. fs =. fs,b end. end.
    count =. 0
    cats =. 0$a:
    for_b. os do.
        if. 'METAR'-:1{::>b do. count =. count+1 end.
        cats =. cats,<9{::>b
    end.
    ls =. <'station ',station_title station
    ls =. ls,<'reports: METAR ',(number count),', SPECI ',number (#os)-count
    ls =. ls,<'observed categories: ',category_counts cats
    ls =. ls,extreme_lines os
    ct =. contingency ''
    noforecast =. 0
    amendments =. 0$a:
    for_b. os do.
        o =. >b
        t =. 3{::o
        f =. fs chosen_forecast t
        if. isnone f do. noforecast =. noforecast+1
        continue. end.
        h =. hourmark t
        s =. f prevailing h
        expected =. category s
        alternatives =. <expected
        for_tb. f temporary h do. alternatives =. alternatives,<category 1{::>tb end.
        hit =. (<9{::o)e.alternatives
        ct =. ((<expected),(<9{::o),<hit) add_hit ct
        reasons =. 0$a:
        if. -.hit do. reasons =. reasons,<'category ',(9{::o),', forecast ',expected end.
        wind =. 1{::4{::o
        if. #wind_changes (<0{::s),(<wind),<60 do.
            reasons =. reasons,<'wind ',(wind_code wind),', forecast ',wind_code 0{::s
        end.
        if. #reasons do. amendments =. amendments,<'amendment ',(stamp t),': ','; ' join reasons end.
    end.
    ls =. ls,<'verified: ',number total ct
    ls =. ls,<'no forecast: ',number noforecast
    ls =. ls,<'forecast' table_row Categories,<'total'
    table =. >{.ct
    rows =. row_totals ct
    cols =. column_totals ct
    for_i. i.4 do. ls =. ls,<(i{::Categories) table_row <"0 (i{table),i{rows end.
    ls =. ls,<'total' table_row <"0 cols,total ct
    ls =. ls,<'hit rate: ',fraction hits ct
    ls =. ls,<'hit rate with temporary groups: ',fraction hits_temporary ct
    ls =. ls,<'heidke skill score: ',fraction skill ct
    for_i. i.4 do.
        ls =. ls,<(i{::Categories),': pod ',(fraction i pod ct),', far ',fraction i far ct
    end.
    ls,(fs bucket_lines os),amendments
)
write_lines =: 4 : 0
    text =. ''
    for_b. y do. text =. text,(>b),LF end.
    text 1!:2 <'output/',x
    i.0
)
write_blocks =: 4 : 0
    ls =. 0$a:
    for_b. y do.
        if. #ls do. ls =. ls,<'' end.
        ls =. ls,>b
    end.
    x write_lines ls
)
main =: 3 : 0
    Stations =: read_stations ''
    read_settings ''
    reports =. read_reports ''
    observations =. forecasts =. decoded =. allerrors =. 0$a:
    latest =. (#Stations)$<NONE
    for_ri. i.#reports do.
        Errors =: 0$a:
        h =. parse_header ri{::reports
        if. -.isnone h do.
            if. 'TAF'-:0{::h do.
                f =. (ri+1) decode_forecast h
                forecasts =. forecasts,<f
                decoded =. decoded,<forecast_lines f
            else.
                station =. 2{::h
                o =. 0 decode_observation (<ri+1),(<h),<station{::latest
                latest =. (<o) station}latest
                observations =. observations,<o
                decoded =. decoded,<observation_lines o
            end.
        end.
        positions =. 0$0
        for_b. Errors do. positions =. positions,0{::>b end.
        for_b. (/:positions){Errors do.
            'pos message' =. >b
            allerrors =. allerrors,<'report ',(number ri+1),' word ',(number pos),': ',message
        end.
    end.
    if. 0=#1!:0 <'output' do. 1!:5 <'output' end.
    'decoded.txt' write_blocks decoded
    'categories.csv' write_lines category_lines observations
    timelines =. 0$a:
    for_b. forecasts do. timelines =. timelines,<timeline_lines >b end.
    'taf_timeline.txt' write_blocks timelines
    verifications =. 0$a:
    for_code. Verify do.
        for_i. i.#Stations do.
            if. (>code)-:0{::i{::Stations do.
                verifications =. verifications,<verification_lines (<i),(<observations),<forecasts
                break.
            end.
        end.
    end.
    'verification.txt' write_blocks verifications
    'errors.txt' write_lines allerrors
    i.0
)
main ''
