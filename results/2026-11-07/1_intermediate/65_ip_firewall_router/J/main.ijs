LF =: 10{a.
Digits =: '0123456789'
Drops =: ;:'down martian rpf invalid acl_in ttl noroute acl_out exhausted'
Output =: 0$a:
emit =: 3 : 'Output =: Output,<y'
num =: 3 : ',''0'' 8!:2 y'
join =: 4 : '(#x) }. ; (<x) ,&.> y'
lower =: 3 : '(''abcdefghijklmnopqrstuvwxyz'',a.) {~ (''ABCDEFGHIJKLMNOPQRSTUVWXYZ'',a.) i.y'
split =: 4 : 0
    out=.0$a:
    start=.0
    for_i. i.#y do.
        if. x=i{y do.
            out=.out,<(i-start){.start}.y
            start=.i+1
        end.
    end.
    out,<start}.y
)
fields =: 4 : 0
    result=.0$a:
    for_row. y do.
        result=.result,<x{::>row
    end.
    result
)
orderFields =: 4 : 0
    keys=.(0,#x)$a:
    for_row. y do.
        keys=.keys,x{>row
    end.
    /:keys
)
fail =: 3 : 0
    Reason=:y
    throw.
)
decimal =: 4 : 0
    if. (0=#y)+.(x<#y) do. _1 return. end.
    if. (-.*./y e.Digits)+.((1<#y)*.'0'={.y) do. _1 return. end.
    0".y
)
address =: 3 : 0
    parts=.'.'split y
    if. 4~:#parts do. _1 return. end.
    value=.0
    for_p. parts do.
        n=.3 decimal >p
        if. (n<0)+.n>255 do. _1 return. end.
        value=.(256*value)+n
    end.
    value
)
prefix =: 3 : 0
    parts=.'/'split y
    if. 2~:#parts do. _1 _1 return. end.
    a=.address 0{::parts
    n=.2 decimal 1{::parts
    if. (a<0)+.(n<0)+.n>32 do. _1 _1 else. a,n end.
)
network =: 4 : '(2^32-y)*<.x%2^32-y'
contains =: 4 : 0
    'a n'=.x
    (a network n)=y network n
)
ip =: 3 : '''.''join num&.>256 256 256 256#:y'
cidr =: 3 : '(ip 0{y),''/'',num 1{y'
endpoint =: 3 : '(ip 0{y),'':'',num 1{y'
flowtext =: 3 : '(endpoint >1 2{y),'' > '',endpoint >3 4{y'
reqAddress =: 3 : 0
    a=.address y
    if. a<0 do. fail 'bad address ',y end.
    a
)
reqPrefix =: 3 : 0
    p=.prefix y
    if. 0>{.p do. fail 'bad prefix ',y end.
    if. ({.p)~:({.p)network {:p do. fail 'host bits set in ',y end.
    p
)
aclPrefix =: 3 : 0
    if. y-:'ANY' do. 0 0 else. reqPrefix y end.
)
reqNumber =: 3 : 0
    'word low high message'=.y
    n=.0".word
    if. (n<low)+.n>high do. fail message end.
    n
)
ports =: 3 : 0
    if. y-:'ANY' do. 0;65535;'any' return. end.
    b=.0".&>'-'split y
    low=.{.b
    high=.{:b
    if. (low>high)+.high>65535 do. fail 'bad port range ',y end.
    if. low=high do. label=.num low else. label=.(num low),'-',num high end.
    low;high;label
)
iface =: 3 : 0
    for_i. i.#Ifaces do.
        if. y-:0{::i{::Ifaces do. i return. end.
    end.
    fail 'no interface ',y
)
localIface =: 3 : 0
    for_i. i.#Ifaces do. if. y=1{::i{::Ifaces do. i return. end. end.
    _1
)
setI =: 3 : 0
    'i field value'=.y
    row=.i{::Ifaces
    row=.(<value)field}row
    Ifaces=:(<row)i}Ifaces
)
setR =: 3 : 0
    'i field value'=.y
    row=.i{::Routes
    row=.(<value)field}row
    Routes=:(<row)i}Routes
)
setA =: 3 : 0
    'i field value'=.y
    row=.i{::Rules
    row=.(<value)field}row
    Rules=:(<row)i}Rules
)
setM =: 3 : 0
    'i field value'=.y
    row=.i{::Mappings
    row=.(<value)field}row
    Mappings=:(<row)i}Mappings
)
interfaceOrder =: 3 : '/:0 fields Ifaces'
selectRoute =: 3 : 0
    best=._1
    for_i. i.#Routes do.
        r=.i{::Routes
        if. -.3{::(3{::r){::Ifaces do. continue. end.
        if. -. (>1 2{r)contains y do. continue. end.
        if. best<0 do. best=.i
        else.
            b=.best{::Routes
            if. ((2{::r)>2{::b)+.((2{::r)=2{::b)*.(5{::r)<5{::b do. best=.i end.
        end.
    end.
    best
)
routeText =: 3 : 0
    'k a n i hop metric hits'=.y
    out=.k,' ',cidr a,n
    if. hop>:0 do. out=.out,' via ',ip hop end.
    out,' dev ',(0{::i{::Ifaces),' metric ',num metric
)
ruleOrder =: 3 : 0
    'i dir'=.y
    ids=.i.0
    for_j. i.#Rules do.
        r=.j{::Rules
        if. (i=0{::r)*.dir-:1{::r do. ids=.ids,j end.
    end.
    ids /:2 fields ids{Rules
)
acl =: 3 : 0
    'i dir flow established'=.y
    ids=.ruleOrder i;dir
    if. 0=#ids do. '' return. end.
    'p s sp d dp'=.flow
    label=.'acl ',(0{::i{::Ifaces),' ',dir
    for_id. ids do.
        r=.id{::Rules
        if. -. (<4{::r)e.'ANY';p do. continue. end.
        if. (-.(>5 6{r)contains s)+.-.(>10 11{r)contains d do. continue. end.
        if. (<4{::r)e.'TCP';'UDP' do.
            if. (sp<7{::r)+.(sp>8{::r)+.(dp<12{::r)+.dp>13{::r do. continue. end.
        end.
        if. (15{::r)*.-.established do. continue. end.
        setA id;16;(1+16{::r)
        action=.3{::r
        if. action-:'PERMIT' do. '' return. end.
        suffix=.label,' ',num 2{::r
        if. action-:'DENY' do. 'DROP ',suffix return. end.
        why=.'icmp-prohibited'
        if. p-:'TCP' do. why=.'tcp-reset' end.
        'REJECT ',suffix,' ',why return.
    end.
    field=.10+dir-:'out'
    setI i;field;(1+field{::i{::Ifaces)
    'DROP ',label,' default'
)
timeout =: 3 : 'Timeouts{~(''TCP'';''UDP'';''ICMP'')i.<y'
process =: 3 : 0
    'inbound p flags s sp d dp ttl'=.y
    incoming=.inbound{::Ifaces
    if. -.3{::incoming do. 'down';'DROP down' return. end.
    for_range. 0 8;2130706432 8;3758096384 3 do.
        if. ((>range)contains s)+.(>range)contains d do. 'martian';'DROP martian' return. end.
    end.
    if. 0<:localIface s do. 'martian';'DROP martian' return. end.
    mode=.6{::incoming
    if. -.mode-:'off' do.
        route=.selectRoute s
        if. route<0 do. 'rpf';'DROP rpf' return. end.
        if. (mode-:'strict')*.inbound~:3{::route{::Routes do. 'rpf';'DROP rpf' return. end.
    end.
    flow=.p;s;sp;d;dp
    conn=._1
    side=.''
    pure=.(p-:'TCP')*.flags-:'S'
    for_j. i.#Conns do.
        c=.j{::Conns
        if. flow-:1 2 3 4 5{c do. dir=.'orig'
        elseif. flow-:1 6 7 8 9{c do. dir=.'reply'
        else. continue. end.
        if. pure*.'CLOSED'-:12{::c do. Conns=:((i.#Conns)~:j)#Conns
        else. conn=.j
            side=.dir
        end.
        break.
    end.
    if. (p-:'TCP')*.(conn<0)*.-.pure do. 'invalid';'DROP invalid' return. end.
    denied=.acl (<inbound),(< 'in'),(<flow),<conn>:0
    if. #denied do. 'acl_in';denied return. end.
    nd=.d
    np=.dp
    used=._1
    translated=.0
    if. 4{::incoming do.
        for_st. Statics do.
            'a b'=.>st
            if. b=d do. nd=.a
                translated=.1
                break.
            end.
        end.
        if. (-.translated)*.d=1{::incoming do.
            for_f. Forwards do.
                'i protocol port inside inport'=.>f
                if. (i=inbound)*.(protocol-:p)*.port=dp do.
                    nd=.inside
                    np=.inport
                    translated=.1
                    break.
                end.
            end.
            if. -.translated do.
                for_j. i.#Mappings do.
                    'i protocol inside inport port time'=.j{::Mappings
                    if. (i=inbound)*.(protocol-:p)*.port=dp do. nd=.inside
                        np=.inport
                        used=.j
                        break.
                    end.
                end.
            end.
        end.
    end.
    loc=.localIface nd
    if. loc>:0 do. 'local';'LOCAL ',0{::loc{::Ifaces return. end.
    if. ttl=1 do. 'ttl';'DROP ttl' return. end.
    route=.selectRoute nd
    if. route<0 do. 'noroute';'DROP noroute' return. end.
    r=.route{::Routes
    outbound=.3{::r
    outgoing=.outbound{::Ifaces
    translatedflow=.p;s;sp;nd;np
    denied=.acl (<outbound),(< 'out'),(<translatedflow),<conn>:0
    if. #denied do. 'acl_out';denied return. end.
    ns=.s
    nsp=.sp
    if. (-.4{::incoming)*.4{::outgoing do.
        translated=.0
        for_st. Statics do.
            'a b'=.>st
            if. a=s do. ns=.b
                translated=.1
                break.
            end.
        end.
        if. -.translated do.
            for_f. Forwards do.
                'i protocol port inside inport'=.>f
                if. (i=outbound)*.(protocol-:p)*.(inside=s)*.inport=sp do.
                    ns=.1{::outgoing
                    nsp=.port
                    translated=.1
                    break.
                end.
            end.
        end.
        if. (-.translated)*.0<5{::outgoing do.
            used=._1
            for_j. i.#Mappings do.
                'i protocol inside inport port time'=.j{::Mappings
                if. (i=outbound)*.(protocol-:p)*.(inside=s)*.inport=sp do. used=.j break. end.
            end.
            if. used<0 do.
                occupied=.i.0
                for_m. Mappings do. if. outbound=0{::>m do. occupied=.occupied,4{::>m end. end.
                for_f. Forwards do. if. outbound=0{::>f do. occupied=.occupied,2{::>f end. end.
                free=.(20000+i.5{::outgoing)-.occupied
                if. 0=#free do. 'exhausted';'DROP exhausted' return. end.
                Mappings=:Mappings,<outbound;p;s;sp;({.free);Clock
                used=.<:#Mappings
            end.
            ns=.1{::outgoing
            nsp=.4{::used{::Mappings
        end.
    end.
    if. used>:0 do. setM used;5;Clock end.
    if. conn<0 do.
        Serial=:Serial+1
        state=.'UNREPLIED'
        if. p-:'TCP' do. state=.'SYN_SENT' end.
        Conns=:Conns,<Serial;p;s;sp;d;dp;nd;np;ns;nsp;inbound;outbound;state;0;0;Clock;0;0
        conn=.<:#Conns
        side=.'new'
    end.
    c=.conn{::Conns
    field=.13+side-:'reply'
    c=.(<1+field{::c)field}c
    c=.(<Clock)15}c
    state=.12{::c
    if. -.p-:'TCP' do.
        if. side-:'reply' do. state=.'REPLIED' end.
    elseif. 'R'e.flags do. state=.'CLOSED'
    else.
        if. (state-:'SYN_SENT')*.(side-:'reply')*.('S'e.flags)*.'A'e.flags do. state=.'ESTABLISHED' end.
        if. ('F'e.flags)*.(<state)e.'ESTABLISHED';'FIN_WAIT' do.
            c=.(<1)(16+side-:'reply')}c
            if. (16{::c)*.17{::c do. state=.'CLOSED' else. state=.'FIN_WAIT' end.
        end.
    end.
    c=.(<state)12}c
    Conns=:(<c)conn}Conns
    setI outbound;8;(1+8{::outgoing)
    setR route;6;(1+6{::r)
    hop=.'direct'
    if. 0<:4{::r do. hop=.'via ',ip 4{::r end.
    verdict=.'FORWARD ',(0{::outgoing),' ',hop,' ttl=',num ttl-1
    if. -. (nd,np)-:d,dp do. verdict=.verdict,' dnat=',endpoint nd,np end.
    if. -. (ns,nsp)-:s,sp do. verdict=.verdict,' snat=',endpoint ns,nsp end.
    'forwarded';verdict,' conn=',(num 0{::c),' ',side
)
show =: 3 : 0
    ordered=.interfaceOrder''
    select. y
    case. 'IFACES' do.
        emit 'show ifaces count=',num #Ifaces
        for_id. ordered do.
            i=.id{::Ifaces
            used=.+/id=>0 fields Mappings
            out=.(0{::i),' ',(cidr >1 2{i),' ',((3{::i){::'down';'up'),' ',((4{::i){::'inside';'outside'),' rpf=',6{::i
            if. 0<5{::i do. out=.out,' pat=',(num used),'/',num 5{::i end.
            emit out
        end.
    case. 'ROUTES' do.
        emit 'show routes count=',num #Routes
        order=.1 2 5 orderFields Routes
        for_id. order do.
            r=.id{::Routes
            out=.(routeText r),' hits=',num 6{::r
            if. -.3{::(3{::r){::Ifaces do. out=.out,' inactive' end.
            emit out
        end.
    case. 'ACL' do.
        emit 'show acl count=',num #Rules
        for_id. ordered do.
            for_dir. 'in';'out' do.
                dir=.>dir
                ids=.ruleOrder id;dir
                if. 0=#ids do. continue. end.
                label=.'acl ',(0{::id{::Ifaces),' ',dir
                for_j. ids do.
                    r=.j{::Rules
                    src=.'any'
                    dst=.'any'
                    if. 0<6{::r do. src=.cidr >5 6{r end.
                    if. 0<11{::r do. dst=.cidr >10 11{r end.
                    out=.label,' ',(num 2{::r),' ',(3{::r),' ',(4{::r),' ',src,' ',(9{::r),' ',dst,' ',14{::r
                    if. 15{::r do. out=.out,' established' end.
                    emit out,' hits=',num 16{::r
                end.
                emit label,' default DENY hits=',num (10+dir-:'out'){::id{::Ifaces
            end.
        end.
    case. 'NAT' do.
        emit 'show nat static=',(num #Statics),' forward=',(num #Forwards),' pat=',num #Mappings
        for_st. Statics /:0 fields Statics do. emit 'static ',(ip 0{::>st),' ',ip 1{::>st end.
        for_id. ordered do.
            fs=.0$a:
            ms=.0$a:
            for_f. Forwards do. if. id=0{::>f do. fs=.fs,f end. end.
            for_m. Mappings do. if. id=0{::>m do. ms=.ms,m end. end.
            for_f. fs {~ 2 1 orderFields fs do.
                f=.>f
                emit 'forward ',(0{::id{::Ifaces),' ',(1{::f),' ',(num 2{::f),' ',endpoint >3 4{f
            end.
            for_m. ms /:4 fields ms do.
                m=.>m
                emit 'pat ',(0{::id{::Ifaces),' ',(num 4{::m),' ',(1{::m),' ',(endpoint >2 3{m),' idle=',num Clock-5{::m
            end.
        end.
    case. 'CONNS' do.
        emit 'show conns count=',num #Conns
        for_c. Conns do.
            c=.>c
            emit 'conn ',(num 0{::c),' ',(1{::c),' ',(flowtext 1 2 3 4 5{c),' reply ',(flowtext 1 6 7 8 9{c),' in=',(0{::(10{::c){::Ifaces),' out=',(0{::(11{::c){::Ifaces),' state=',(12{::c),' pkts=',(num 13{::c),'/',(num 14{::c),' idle=',num Clock-15{::c
        end.
    case. 'COUNTERS' do.
        dropped=.+/9{.Counts
        emit 'show counters packets=',(num +/Counts),' forwarded=',(num 9{Counts),' local=',(num 10{Counts),' dropped=',(num dropped),' errors=',num Errors
        emit 'drops ', ' 'join Drops ,&.> (<'=') ,&.> num&.>9{.Counts
        for_id. ordered do.
            i=.id{::Ifaces
            emit 'iface ',(0{::i),' rx=',(num 7{::i),' tx=',(num 8{::i),' drop=',num 9{::i
        end.
    end.
)
execute =: 3 : 0
    words=.' 'split y
    cmd=.0{::words
    a=.}.words
    select. cmd
    case. 'IFACE' do.
        'name word'=.a
        if. (<name)e.0 fields Ifaces do. fail 'duplicate interface ',name end.
        p=.prefix word
        'addr len'=.p
        if. (addr<0)+.(len<8)+.len>30 do. fail 'bad prefix ',word end.
        base=.addr network len
        host=.addr-base
        if. (host=0)+.host=(2^32-len)-1 do. fail 'bad host address ',word end.
        for_i. Ifaces do.
            i=.>i
            if. ((1{::i),len<.2{::i)contains addr do. fail 'subnet overlaps ',0{::i end.
        end.
        Routes=:Routes,<'C';base;len;(#Ifaces);_1;0;0
        Ifaces=:Ifaces,<name;addr;len;1;0;0;'off';0;0;0;0;0
        emit 'ok iface ',name,' ',word,' network ',cidr base,len
    case. 'UP';'DOWN' do.
        name=.0{::a
        id=.iface name
        state=.cmd-:'UP'
        word=.lower cmd
        if. state=3{::id{::Ifaces do. fail 'interface ',name,' already ',word end.
        setI id;3;state
        emit 'ok ',word,' ',name
    case. 'ROUTE' do.
        'word mode target metricword'=.a
        'addr len'=.reqPrefix word
        hop=._1
        if. mode-:'VIA' do. hop=.reqAddress target else. id=.iface target end.
        metric=.reqNumber metricword;1;255;'bad metric ',metricword
        if. mode-:'VIA' do.
            if. 0<:localIface hop do. fail 'nexthop ',target,' is local' end.
            id=._1
            for_j. i.#Ifaces do.
                if. (>1 2{j{::Ifaces)contains hop do. id=.j break. end.
            end.
            if. id<0 do. fail 'nexthop ',target,' unreachable' end.
        end.
        for_r. Routes do.
            r=.>r
            if. ('S'-:0{::r)*.(addr=1{::r)*.(len=2{::r)*.(id=3{::r)*.hop=4{::r do. fail 'duplicate route ',word end.
        end.
        r=.'S';addr;len;id;hop;metric;0
        Routes=:Routes,<r
        emit 'ok route ',routeText r
    case. 'NOROUTE' do.
        word=.0{::a
        'addr len'=.reqPrefix word
        keep=.i.0
        for_r. Routes do.
            r=.>r
            keep=.keep,-.('S'-:0{::r)*.(addr=1{::r)*.len=2{::r
        end.
        removed=.+/-.keep
        if. 0=removed do. fail 'no static route ',word end.
        Routes=:keep#Routes
        emit 'ok noroute ',word,' removed=',num removed
    case. 'LOOKUP' do.
        word=.0{::a
        id=.selectRoute reqAddress word
        out=.'none'
        if. id>:0 do. out=.routeText id{::Routes end.
        emit 'lookup ',word,' ',out
    case. 'ACL' do.
        'name dir seq action p src sports dst dports'=.9{.a
        id=.iface name
        sequence=.reqNumber seq;1;9999;'bad sequence ',seq
        s=.aclPrefix src
        sp=.ports sports
        d=.aclPrefix dst
        dp=.ports dports
        if. ((<p)e.'ICMP';'ANY')*.-.(sports;dports)-:'ANY';'ANY' do. fail 'ports not allowed for ',p end.
        dir=.lower dir
        for_r. Rules do.
            r=.>r
            if. (id=0{::r)*.(dir-:1{::r)*.sequence=2{::r do. fail 'duplicate sequence ',seq end.
        end.
        Rules=:Rules,<id;dir;sequence;action;p;({.s);({:s);(0{::sp);(1{::sp);(2{::sp);({.d);({:d);(0{::dp);(1{::dp);(2{::dp);(10=#a);0
        emit 'ok acl ',name,' ',dir,' ',seq
    case. 'NOACL' do.
        'name dir seq'=.a
        id=.iface name
        dir=.lower dir
        found=._1
        for_j. i.#Rules do.
            r=.j{::Rules
            if. (id=0{::r)*.(dir-:1{::r)*.(0".seq)=2{::r do. found=.j break. end.
        end.
        if. found<0 do. fail 'no rule ',seq,' on ',name,' ',dir end.
        hits=.16{::found{::Rules
        Rules=:((i.#Rules)~:found)#Rules
        emit 'ok noacl ',name,' ',dir,' ',seq,' hits=',num hits
    case. 'NAT' do.
        kind=.0{::a
        a=.}.a
        if. kind-:'STATIC' do.
            'x y'=.a
            inside=.reqAddress x
            outside=.reqAddress y
            if. 0<:localIface inside do. fail 'address ',x,' is local' end.
            if. 0<:localIface outside do. fail 'address ',y,' is local' end.
            if. inside e.>0 fields Statics do. fail 'duplicate static ',x end.
            if. outside e.>1 fields Statics do. fail 'duplicate static ',y end.
            Statics=:Statics,<inside;outside
            emit 'ok nat static ',x,' ',y
            return.
        end.
        name=.0{::a
        id=.iface name
        i=.id{::Ifaces
        if. kind-:'OUTSIDE' do.
            if. 4{::i do. fail 'interface ',name,' already outside' end.
            setI id;4;1
            emit 'ok nat outside ',name
        elseif. kind-:'PAT' do.
            word=.1{::a
            size=.reqNumber word;1;1000;'bad pool size ',word
            if. 0<5{::i do. fail 'pat already on ',name end.
            setI id;5;size
            setI id;4;1
            emit 'ok nat pat ',name,' ',(ip 1{::i),' 20000-',num 19999+size
        else.
            'name p word insideword inword'=.a
            port=.reqNumber word;1;65535;'bad port ',word
            inside=.reqAddress insideword
            inport=.reqNumber inword;1;65535;'bad port ',inword
            if. -.4{::i do. fail 'interface ',name,' not outside' end.
            if. 0<:localIface inside do. fail 'address ',insideword,' is local' end.
            for_f. Forwards do.
                f=.>f
                if. (id=0{::f)*.(p-:1{::f)*.port=2{::f do. fail 'duplicate forward ',name,' ',p,' ',word end.
            end.
            Forwards=:Forwards,<id;p;port;inside;inport
            emit 'ok nat forward ',name,' ',p,' ',word,' ',insideword,':',inword
        end.
    case. 'RPF' do.
        'name mode'=.a
        id=.iface name
        setI id;6;lower mode
        emit 'ok rpf ',name,' ',lower mode
    case. 'TIMEOUT' do.
        'p word'=.a
        seconds=.reqNumber word;1;86400;'bad timeout ',word
        Timeouts=:seconds (('TCP';'UDP';'ICMP')i.<p)}Timeouts
        emit 'ok timeout ',p,' ',word
    case. 'TICK' do.
        word=.0{::a
        Clock=:Clock+reqNumber word;1;86400;'bad tick ',word
        kept=.0$a:
        for_c. Conns do.
            c=.>c
            duration=.timeout 1{::c
            if. ('TCP'-:1{::c)*.-.'ESTABLISHED'-:12{::c do.
                duration=.60
                if. 'CLOSED'-:12{::c do. duration=.10 end.
            end.
            if. (Clock-15{::c)<duration do. kept=.kept,<c end.
        end.
        nc=.(#Conns)-#kept
        Conns=:kept
        kept=.0$a:
        for_m. Mappings do.
            m=.>m
            if. (Clock-5{::m)<timeout 1{::m do. kept=.kept,<m end.
        end.
        nm=.(#Mappings)-#kept
        Mappings=:kept
        emit 'ok tick time=',(num Clock),' expired conns=',(num nc),' nat=',num nm
    case. 'PACKET' do.
        'name p flags sw spw dw dpw tw'=.a
        id=.iface name
        if. (-.p-:'TCP')*.-.flags-:'-' do. fail 'flags not allowed for ',p end.
        if. (p-:'TCP')*.-.flags-:'-' do.
            if. (-.*./flags e.'SAFR')+.(#flags)~:#~.flags do. fail 'bad flags ',flags end.
        end.
        s=.reqAddress sw
        sp=.reqNumber spw;0;65535;'bad port ',spw
        d=.reqAddress dw
        dp=.reqNumber dpw;0;65535;'bad port ',dpw
        ttl=.reqNumber tw;1;255;'bad ttl ',tw
        Packets=:Packets+1
        setI id;7;(1+7{::id{::Ifaces)
        fs=.flags
        if. flags-:'-' do. fs=.'' end.
        'reason verdict'=.process id;p;fs;s;sp;d;dp;ttl
        index=.(Drops,'forwarded';'local')i.<reason
        Counts=:(1+index{Counts)index}Counts
        if. index<9 do. setI id;9;(1+9{::id{::Ifaces) end.
        emit '#',(num Packets),' ',p,' ',flags,' ',sw,':',spw,' > ',dw,':',dpw,' ',verdict
    case. 'SHOW' do. show 0{::a
    case. 'CLEAR' do.
        if. 'COUNTERS'-:0{::a do.
            Counts=:11$0
            Errors=:0
            for_j. i.#Ifaces do. for_field. 7 8 9 10 11 do. setI j;field;0 end. end.
            for_j. i.#Routes do. setR j;6;0 end.
            for_j. i.#Rules do. setA j;16;0 end.
            emit 'ok clear counters'
        else.
            emit 'ok clear conns=',(num #Conns),' nat=',num #Mappings
            Conns=:Mappings=:0$a:
        end.
    end.
)
main =: 3 : 0
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    Ifaces=:Routes=:Rules=:Statics=:Forwards=:Mappings=:Conns=:0$a:
    Clock=:Packets=:Serial=:Errors=:0
    Counts=:11$0
    Timeouts=:300 60 30
    for_line. (0".0{::lines){.}.lines do.
        try. execute >line
        catcht. Errors=:Errors+1
            emit 'error: ',Reason
        end.
    end.
    1!:2&2 ;Output,&.><LF
)
main''
