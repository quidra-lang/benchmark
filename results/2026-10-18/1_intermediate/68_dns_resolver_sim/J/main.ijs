LF =: 10{a.
Types =: ;:'A NS CNAME SOA PTR MX TXT AAAA'
Kinds =: ;:'ANSWER CNAME REFERRAL NODATA NXDOMAIN LAME TIMEOUT'
Statuses =: ;:'NOERROR NODATA NXDOMAIN SERVFAIL'
Output =: 0$a:
num =: 3 : ',''0'' 8!:2 y'
emit =: 3 : 'Output=:Output,<y'
join =: 4 : '(#x)}.;(<x),&.>y'
split =: 4 : 0
    out=.0$a:
    start=.0
    for_i. i.#y do.
        if. x=i{y do. out=.out,<(i-start){.start}.y
            start=.i+1 end.
    end.
    out,<start}.y
)
lower =: 3 : 0
    upper=.'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    out=.y
    for_i. i.#y do.
        at=.upper i.i{y
        if. at<26 do. out=.((at{'abcdefghijklmnopqrstuvwxyz')i}out) end.
    end.
    out
)
fail =: 3 : 0
    Reason=:y
    throw.
)
check =: 4 : 'if. -.y do. fail x end.'
integerWord =: 4 : 0
    if. (0=#y)+.x<#y do. 0 return. end.
    (*./y e.'0123456789')*.((1=#y)+.'0'~:{.y)
)
ipv4 =: 3 : 0
    parts=.'.'split y
    ('bad address ',y)check 4=#parts
    value=.0
    for_part. parts do.
        p=.>part
        ('bad address ',y)check 3 integerWord p
        n=.0".p
        ('bad address ',y)check n<:255
        value=.(256*value)+n
    end.
    value
)
ip4text =: 3 : '''.''join num&.>256 256 256 256#:y'
hex =: 3 : 0
    if. y=0 do. '0' return. end.
    digits=.'0123456789abcdef'{~16 16 16 16#:y
    (digits i.({.digits-. '0'))}.digits
)
parseGroups =: 3 : 0
    if. 0=#y do. i.0 return. end.
    out=.i.0
    for_part. ':'split y do.
        p=.>part
        if. (0=#p)+.(4<#p)+.-.*./p e.'0123456789abcdefABCDEF' do. a: return. end.
        out=.out,16#.'0123456789abcdef'i.lower p
    end.
    out
)
ipv6 =: 3 : 0
    at=.{.I.'::'E.y
    if. 0=#I.'::'E.y do.
        values=.parseGroups y
        ('bad address ',y)check -.values-:a:
        ('bad address ',y)check 8=#values
        values return.
    end.
    front=.parseGroups at{.y
    back=.parseGroups (at+2)}.y
    ('bad address ',y)check (-.front-:a:)*.-.back-:a:
    ('bad address ',y)check 7>:(#front)+#back
    front,((8-(#front)+#back)$0),back
)
ip6text =: 3 : 0
    best=._1
    width=.1
    at=.0
    while. at<8 do.
        stop=.at
        while. stop<8 do. if. 0~:stop{y do. break. end.
            stop=.stop+1 end.
        if. width<stop-at do. best=.at
            width=.stop-at end.
        at=.stop>.at+1
    end.
    parts=.hex&.>y
    if. best<0 do. ':'join parts
    else. (':'join best{.parts),'::',':'join (best+width)}.parts end.
)
labels =: 3 : 'if. y-:''.'' do. 0$a: else. ''.''split }:y end.'
nameKey =: 3 : '|.labels y'
nameLess =: 4 : 0
    a=.nameKey x
    b=.nameKey y
    for_i. i.(#a)<.#b do.
        first=.i{::a
        second=.i{::b
        if. -.first-:second do. 0={./:first;second return. end.
    end.
    (#a)<#b
)
nameSort =: 3 : 0
    result=.y
    for_i. 1+i.0>.(_1+#result) do.
        j=.i
        while. j>0 do.
            a=.(j-1){::result
            b=.j{::result
            if. -.b nameLess a do. break. end.
            result=.(<b)(j-1)}result
            result=.(<a)j}result
            j=.j-1
        end.
    end.
    result
)
below =: 4 : 0
    if. y-:'.' do. 1 return. end.
    if. x-:y do. 1 return. end.
    suffix=.'.',y
    if. (#x)<#suffix do. 0 return. end.
    suffix-:(-#suffix){.x
)
ancestors =: 3 : 0
    parts=.labels y
    out=.0$a:
    for_i. i.1+#parts do.
        if. i=#parts do. out=.out,<'.' else. out=.out,<('.'join i}.parts),'.' end.
    end.
    out
)
parseName =: 4 : 0
    'wild origin'=.x
    if. (0<#origin)*.y-:'@' do. origin return. end.
    if. y-:'.' do. '.' return. end.
    absolute=.'.'={:y
    if. absolute do. text=.}:y else. text=.y end.
    parts=.'.'split text
    for_i. i.#parts do.
        p=.i{::parts
        if. wild*.(i=0)*.p-:'*' do. continue. end.
        ('bad name ',y)check (0<#p)*.63>:#p
        ('bad name ',y)check (*./p e.'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-')*.(('-'~:{.p)*.'-'~:{:p)
    end.
    out=.(lower text),'.'
    if. (0<#origin)*.(-.absolute)*.-.origin-:'.' do. out=.out,origin end.
    out
)
parseTTL =: 3 : 0
    if. 9 integerWord y do. n=.0".y
    else.
        n=.0
        previous=._1
        at=.0
        while. at<#y do.
            start=.at
            while. at<#y do. if. -. (at{y)e.'0123456789' do. break. end.
                at=.at+1 end.
            digits=.(at-start){.start}.y
            ('bad ttl ',y)check (3 integerWord digits)*.at<#y
            unit=.'wdhms'i.lower at{y
            ('bad ttl ',y)check (unit<5)*.unit>previous
            previous=.unit
            n=.n+(0".digits)*unit{604800 86400 3600 60 1
            at=.at+1
        end.
    end.
    ('bad ttl ',y)check (n>:1)*.n<:604800
    n
)
checkType =: 3 : '(''bad type '',y)check (<y)e.Types'
rOwner =: 3 : '0{::y'
rTTL =: 3 : '1{::y'
rKind =: 3 : '2{::y'
rData =: 3 : '3{::y'
rTarget =: 3 : '4{::y'
rNumber =: 3 : '5{::y'
rGroups =: 3 : '6{::y'
rMinimum =: 3 : '7{::y'
parseRecord =: 3 : 0
    'owner ttl kind fields origin'=.y
    data=.''
    target=.''
    number=.0
    groups=.i.0
    minimum=.0
    select. kind
    case. 'A' do. number=.ipv4 0{::fields
        data=.ip4text number
    case. 'AAAA' do. groups=.ipv6 0{::fields
        data=.ip6text groups
    case. 'NS';'CNAME';'PTR' do. target=.(0;origin)parseName 0{::fields
        data=.target
    case. 'MX' do.
        word=.0{::fields
        ('bad preference ',word)check 9 integerWord word
        number=.0".word
        ('bad preference ',word)check number<:65535
        target=.(0;origin)parseName 1{::fields
        data=.(num number),' ',target
    case. 'TXT' do.
        data=.' 'join fields
        ('bad text ',data)check 2<:#data
        ('bad text ',data)check ('"'={.data)*.('"'={:data)*.-.'"'e.}.}:data
    case. 'SOA' do.
        first=.(0;origin)parseName 0{::fields
        second=.(0;origin)parseName 1{::fields
        parts=.first;second
        for_i. 2 3 4 5 do.
            word=.i{::fields
            ('bad number ',word)check 9 integerWord word
            parts=.parts,<num 0".word
        end.
        word=.6{::fields
        ('bad minimum ',word)check 9 integerWord word
        minimum=.0".word
        ('bad minimum ',word)check (minimum>:1)*.minimum<:86400
        data=.' 'join parts,<num minimum
    end.
    (<owner),(<ttl),(<kind),(<data),(<target),(<number),(<groups),<minimum
)
recordText =: 3 : '(rOwner y),'' '',(num rTTL y),'' '',(rKind y),'' '',rData y'
dataLess =: 4 : 0
    select. rKind x
    case. 'A' do. (rNumber x)<rNumber y
    case. 'AAAA' do. (0={./:(rGroups x);rGroups y)*.-.(rGroups x)-:rGroups y
    case. 'NS';'CNAME';'PTR' do. (rTarget x)nameLess rTarget y
    case. 'MX' do.
        if. (rNumber x)~:rNumber y do. (rNumber x)<rNumber y else. (rTarget x)nameLess rTarget y end.
    case. do. (0={./:(rData x);rData y)*.-.(rData x)-:rData y
    end.
)
recordLess =: 4 : 0
    if. -. (rOwner x)-:rOwner y do. (rOwner x)nameLess rOwner y return. end.
    if. -. (rKind x)-:rKind y do. (Types i.<rKind x)<Types i.<rKind y return. end.
    x dataLess y
)
recordsSort =: 4 : 0
    out=.y
    for_i. 1+i.0>.(_1+#out) do.
        j=.i
        while. j>0 do.
            a=.(j-1){::out
            b=.j{::out
            if. x do. less=.b dataLess a else. less=.b recordLess a end.
            if. -.less do. break. end.
            out=.(<b)(j-1)}out
            out=.(<a)j}out
            j=.j-1
        end.
    end.
    out
)
atOwner =: 4 : 0
    'name kind'=.y
    out=.0$a:
    for_r. 3{::x do.
        r=.>r
        if. (name-:rOwner r)*.((0=#kind)+.kind-:rKind r) do. out=.out,<r end.
    end.
    if. #kind do. 1 recordsSort out else. out end.
)
exists =: 4 : 0
    for_r. 3{::x do. if. (rOwner >r)below y do. 1 return. end. end.
    0
)
soa =: 3 : 0
    for_r. 3{::y do. if. 'SOA'-:rKind >r do. >r return. end. end.
    a:
)
response =: 3 : '(<y),(<0$a:),(<0$a:),(<0$a:),<''.'''
summary =: 3 : 0
    k=.0{::y
    if. k-:'REFERRAL' do. 'REFERRAL ',4{::y
    elseif. k-:'CNAME' do. 'CNAME ',rTarget 0{::1{::y
    else. k end.
)
zoneInput =: 4 : 0
    w=.' 'split y
    command=.0{::w
    if. command-:'ROOT' do.
        addresses=.i.0
        for_word. }.w do.
            word=.>word
            address=.ipv4 word
            ('duplicate root ',word)check -.address e.Roots,addresses
            addresses=.addresses,address
        end.
        Roots=:Roots,addresses
    elseif. command-:'ZONE' do.
        Current=:_1
        origin=.(0;'')parseName 1{::w
        address=.ipv4 2{::w
        for_zone. Zones do.
            zone=.>zone
            ('duplicate zone ',origin,' at ',2{::w)check -.((origin-:0{::zone)*.address=1{::zone)
        end.
        Current=:#Zones
        Zones=:Zones,<(<origin),(<address),(<x),<0$a:
    else.
        'no current zone'check Current>:0
        zone=.Current{::Zones
        origin=.0{::zone
        owner=.(1;origin)parseName 0{::w
        ('out of zone ',owner)check owner below origin
        ttl=.parseTTL 1{::w
        kind=.2{::w
        checkType kind
        fields=.3}.w
        count=.1
        if. kind-:'MX' do. count=.2 elseif. kind-:'SOA' do. count=.7 elseif. kind-:'TXT' do. count=.#fields end.
        'wrong field count'check count=#fields
        r=.parseRecord (<owner),(<ttl),(<kind),(<fields),<origin
        'ns at wildcard'check -.((kind-:'NS')*.'*.'-:2{.owner)
        'soa not at origin'check (-.kind-:'SOA')+.owner-:origin
        'duplicate soa'check (-.kind-:'SOA')+.(soa zone)-:a:
        for_other. 3{::zone do.
            other=.>other
            same=.((rOwner other)-:owner)*.((rKind other)-:kind)*.(rData other)-:rData r
            'duplicate record'check -.same
        end.
        for_other. zone atOwner owner;'' do.
            other=.>other
            ('cname conflict ',owner)check -.((kind-:'CNAME')+.'CNAME'-:rKind other)
        end.
        zone=.(<(3{::zone),<r)3}zone
        Zones=:(<zone)Current}Zones
    end.
)
finishZones =: 3 : 0
    kept=.0$a:
    total=.0
    for_zone. Zones do.
        zone=.>zone
        label=.'zone ',(0{::zone),' at ',ip4text 1{::zone
        if. (soa zone)-:a: do. emit 'error line ',(num 2{::zone),': ',label,' has no soa'
        else.
            emit label,' records=',num #3{::zone
            kept=.kept,<zone
            total=.total+#3{::zone
        end.
    end.
    Zones=:kept
    emit 'loaded roots=',(num #Roots),' zones=',(num #Zones),' records=',num total
)
reachable =: 3 : '(-.y e.Down)*.y e.1&{::&>Zones'
respond =: 3 : 0
    'address name kind cut'=.y
    if. -.reachable address do. response 'TIMEOUT' return. end.
    chosen=._1
    width=._1
    for_i. i.#Zones do.
        zone=.i{::Zones
        if. (address=1{::zone)*.name below 0{::zone do.
            n=.#labels 0{::zone
            if. n>width do. chosen=.i
                width=.n end.
        end.
    end.
    if. (chosen<0)+.width<#labels cut do. response 'LAME' return. end.
    zone=.chosen{::Zones
    parts=.labels name
    for_n. (width+1)+i.(#parts)-width do.
        point=.('.'join (-n){.parts),'.'
        ns=.zone atOwner point;'NS'
        if. #ns do.
            glue=.0$a:
            for_r. ns do. glue=.glue,zone atOwner (rTarget >r);'A' end.
            result=.response 'REFERRAL'
            (<point)4}(<glue)3}(<ns)2}result
            return.
        end.
    end.
    records=.zone atOwner name;''
    status=.'NODATA'
    if. (0=#records)*.-.zone exists name do.
        for_parent. }.ancestors name do.
            parent=.>parent
            if. zone exists parent do.
                if. parent-:'.' do. wildcard=.'*.' else. wildcard=.'*.',parent end.
                records=.zone atOwner wildcard;''
                break.
            end.
        end.
        if. 0=#records do. status=.'NXDOMAIN' end.
    end.
    matching=.0$a:
    cnames=.0$a:
    for_r. records do.
        r=.(<name)0}>r
        if. kind-:rKind r do. matching=.matching,<r end.
        if. 'CNAME'-:rKind r do. cnames=.cnames,<r end.
    end.
    if. #matching do. (<1 recordsSort matching)1}response 'ANSWER' return. end.
    if. (-.kind-:'CNAME')*.0<#cnames do. (<cnames)1}response 'CNAME' return. end.
    (<,<soa zone)2}response status
)
ask =: 3 : 0
    r=.respond y
    address=.0{::y
    at=.QueryAddresses i.address
    if. at=#QueryAddresses do. QueryAddresses=:QueryAddresses,address
        QueryCounts=:QueryCounts,1 7$0 end.
    k=.Kinds i.<0{::r
    QueryCounts=:(>: (<at,k){QueryCounts)(<at,k)}QueryCounts
    r
)
entryIndex =: 3 : 0
    'name kind positive'=.y
    for_i. i.#Cache do.
        e=.i{::Cache
        if. (name-:0{::e)*.(kind-:1{::e)*.((-.positive)+.'POS'-:2{::e) do. i return. end.
    end.
    _1
)
store =: 3 : 0
    at=.entryIndex (0{::y);(1{::y);0
    if. at<0 do. Cache=:Cache,<y else. Cache=:(<y)at}Cache end.
)
positive =: 3 : 0
    ttl=.(Minttl>. <./rTTL&>y)<.Maxttl
    first=.0{::y
    store (<rOwner first),(<rKind first),(<'POS'),(<1 recordsSort y),<Clock+ttl
    ttl
)
aged =: 3 : 0
    ttl=.(4{::y)-Clock
    out=.0$a:
    for_r. 3{::y do. out=.out,<(<ttl)1}>r end.
    out
)
trace =: 4 : 'emit ((2*(x+1))#'' ''),y'
tryAddresses =: 3 : 0
    'addresses name kind cut depth'=.y
    for_address. addresses do.
        r=.ask (<address),(<name),(<kind),<cut
        depth trace 'ASK ',(ip4text address),' ',name,' ',kind,' -> ',summary r
        if. -. (<0{::r)e.'LAME';'TIMEOUT' do. r return. end.
    end.
    a:
)
lookup =: 3 : 0
    'name kind depth pending'=.y
    cached=.response ''
    at=.entryIndex name;kind;0
    if. at>:0 do.
        e=.at{::Cache
        if. 'POS'-:2{::e do. cached=.(<aged e)1}response 'ANSWER' else. cached=.response 2{::e end.
    else.
        for_e. Cache do.
            e=.>e
            if. ('NXDOMAIN'-:2{::e)*.name below 0{::e do. cached=.response 'NXDOMAIN' break. end.
        end.
        at=.entryIndex name;'CNAME';1
        if. (0=#0{::cached)*.(-.kind-:'CNAME')*.at>:0 do. cached=.(<aged at{::Cache)1}response 'CNAME' end.
    end.
    if. #0{::cached do.
        Hits=:Hits+1
        depth trace 'CACHE HIT ',name,' ',kind,' -> ',summary cached
        cached return.
    end.
    cut=.'.'
    servers=.0$a:
    hints=.1
    for_ancestor. ancestors name do.
        ancestor=.>ancestor
        at=.entryIndex ancestor;'NS';1
        if. at>:0 do.
            Hits=:Hits+1
            depth trace 'CACHE HIT ',name,' ',kind,' -> REFERRAL ',ancestor
            cut=.ancestor
            servers=.rTarget&.>3{::at{::Cache
            hints=.0
            break.
        end.
    end.
    while. 1 do.
        obtained=.a:
        if. hints do. obtained=.tryAddresses (<Roots),(<name),(<kind),(<cut),<depth
        else.
            for_host. nameSort servers do.
                host=.>host
                addresses=.i.0
                at=.entryIndex host;'A';1
                if. at>:0 do. addresses=.rNumber&>3{::at{::Cache
                else.
                    pair=.host;'A'
                    if. (<pair)e.pending do. depth trace 'GLUELESS ',host,' -> LOOP'
                    else.
                        depth trace 'GLUELESS ',host
                        'status answer'=.resolve (<host),(<'A'),(<depth+1),<pending
                        if. status-:'NOERROR' do.
                            for_r. answer do. if. 'A'-:rKind >r do. addresses=.addresses,rNumber >r end. end.
                        end.
                    end.
                end.
                addresses=./:~~.addresses
                obtained=.tryAddresses (<addresses),(<name),(<kind),(<cut),<depth
                if. -.obtained-:a: do. break. end.
            end.
        end.
        if. obtained-:a: do. response 'SERVFAIL no server for ',cut return. end.
        k=.0{::obtained
        if. k-:'REFERRAL' do.
            ttl=.positive 2{::obtained
            owners=.~.rOwner&.>3{::obtained
            for_owner. owners do.
                glue=.0$a:
                for_r. 3{::obtained do. if. (rOwner >r)-:>owner do. glue=.glue,r end. end.
                ttl=.positive glue
            end.
            cut=.4{::obtained
            servers=.rTarget&.>2{::obtained
            hints=.0
        elseif. (<k)e.'ANSWER';'CNAME' do.
            ttl=.positive 1{::obtained
            answer=.0$a:
            for_r. 1{::obtained do. answer=.answer,<(<ttl)1}>r end.
            (<answer)1}response k
            return.
        else.
            authority=.0{::2{::obtained
            ttl=.(rTTL authority)<.(rMinimum authority)<.Negttl
            store (<name),(<kind),(<k),(<0$a:),<Clock+ttl
            response k return.
        end.
    end.
)
resolve =: 3 : 0
    'name kind depth pending'=.y
    pending=.pending,<name;kind
    chain=.0$a:
    seen=.,<name
    current=.name
    while. 1 do.
        r=.lookup (<current),(<kind),(<depth),<pending
        if. -. 'CNAME'-:0{::r do. break. end.
        chain=.chain,1{::r
        target=.rTarget 0{::1{::r
        if. (<target)e.seen do. r=.response 'SERVFAIL cname loop' break. end.
        if. 9=#chain do. r=.response 'SERVFAIL cname chain too long' break. end.
        seen=.seen,<target
        current=.target
    end.
    status=.0{::r
    if. status-:'ANSWER' do. status=.'NOERROR' end.
    if. 'SERVFAIL'-:8{.status do. answer=.0$a:
        label=.'SERVFAIL'
    else. answer=.chain,1{::r
        label=.status end.
    at=.Statuses i.<label
    Resolutions=:(>:at{Resolutions)at}Resolutions
    status;<answer
)
report =: 4 : 0
    'status answer'=.resolve (<x),(<y),(<0),<0$a:
    for_r. answer do. emit 'answer ',recordText >r end.
    emit 'status ',status
    status;<answer
)
addressResolution =: 3 : 0
    addresses=.0$a:
    for_kind. 'A';'AAAA' do.
        kind=.>kind
        'status answer'=.resolve (<y),(<kind),(<0),<0$a:
        if. status-:'NOERROR' do.
            for_r. answer do. if. kind-:rKind >r do. addresses=.addresses,<rData >r end. end.
        end.
    end.
    if. #addresses do. ' 'join addresses else. 'no address' end.
)
execute =: 3 : 0
    w=.' 'split y
    command=.0{::w
    if. (<command)e.'RESOLVE';'MX' do.
        name=.(1;'')parseName 1{::w
        if. command-:'MX' do. kind=.'MX' else. kind=.2{::w end.
        checkType kind
        if. command-:'MX' do. emit 'mx ',name else. emit 'resolve ',name,' ',kind end.
        'status answer'=.name report kind
        if. command-:'MX' do.
            if. status-:'NOERROR' do.
                for_r. answer do.
                    r=.>r
                    if. -. 'MX'-:rKind r do. continue. end.
                    host=.rTarget r
                    if. host-:'.' do. addresses=.'null' else. addresses=.addressResolution host end.
                    emit 'exchange ',(num rNumber r),' ',host,' -> ',addresses
                end.
            elseif. status-:'NODATA' do.
                host=.name
                if. #answer do. host=.rTarget >{:answer end.
                addresses=.addressResolution host
                emit 'implicit ',host,' -> ',addresses
            end.
        end.
    elseif. command-:'REVERSE' do.
        word=.1{::w
        if. ':'e.word do.
            groups=.ipv6 word
            address=.ip6text groups
            digits=.;_4&{.&.>('0000'&,)&.>hex&.>groups
            name=.('.'join <"0|.digits),'.ip6.arpa.'
        else.
            address=.ip4text ipv4 word
            name=.('.'join |.'.'split address),'.in-addr.arpa.'
        end.
        emit 'reverse ',address,' ',name
        name report 'PTR'
    elseif. command-:'QUERY' do.
        address=.ipv4 1{::w
        name=.(1;'')parseName 2{::w
        kind=.3{::w
        checkType kind
        r=.ask (<address),(<name),(<kind),<'.'
        emit 'query ',(ip4text address),' ',name,' ',kind,' -> ',summary r
        for_i. 1 2 3 do.
            label=.i{::'';'answer';'authority';'additional'
            for_record. i{::r do. emit label,' ',recordText >record end.
        end.
    elseif. command-:'DUMP' do.
        address=.ipv4 1{::w
        name=.(0;'')parseName 2{::w
        prefix=.'dump ',(ip4text address),' ',name
        if. -.reachable address do. emit prefix,' -> TIMEOUT' return. end.
        chosen=._1
        for_i. i.#Zones do.
            z=.i{::Zones
            if. (address=1{::z)*.name-:0{::z do. chosen=.i end.
        end.
        if. chosen<0 do. emit prefix,' -> REFUSED'
        else.
            records=.0 recordsSort 3{::chosen{::Zones
            emit prefix,' records=',num #records
            for_r. records do. emit '  ',recordText >r end.
        end.
    elseif. (<command)e.'DOWN';'UP' do.
        address=.ipv4 1{::w
        if. command-:'DOWN' do.
            ('server ',(1{::w),' already down')check -.address e.Down
            Down=:Down,address
        else.
            ('server ',(1{::w),' not down')check address e.Down
            Down=:Down-.address
        end.
        emit (lower command),' ',ip4text address
    elseif. command-:'SET' do.
        key=.1{::w
        word=.2{::w
        ('bad setting ',key)check (<key)e.'MINTTL';'MAXTTL';'NEGTTL'
        ('bad value ',word)check 9 integerWord word
        value=.0".word
        ('bad value ',word)check (value>:1)*.value<:604800
        if. key-:'MINTTL' do. 'minttl above maxttl'check value<:Maxttl
            Minttl=:value
        elseif. key-:'MAXTTL' do. 'minttl above maxttl'check value>:Minttl
            Maxttl=:value
        else. Negttl=:value end.
        emit 'set ',key,'=',num value
    elseif. command-:'TIME' do.
        word=.1{::w
        ('bad time ',word)check 9 integerWord word
        value=.0".word
        ('bad time ',word)check (value>:1)*.value<:1000000
        Clock=:Clock+value
        before=.#Cache
        Cache=:Cache#~Clock<4&{::&>Cache
        emit 'time now=',(num Clock),' expired=',num before-#Cache
    elseif. (<command)e.'CACHE';'FLUSH' do.
        name=.'.'
        if. 1<#w do. name=.(0;'')parseName 1{::w end.
        selected=.i.0
        for_i. i.#Cache do. if. (0{::i{::Cache)below name do. selected=.selected,i end. end.
        if. command-:'FLUSH' do.
            Cache=:((i.#Cache)-.selected){Cache
            emit 'flush removed=',num #selected
        else.
            for_i. 1+i.0>.(_1+#selected) do.
                j=.i
                while. j>0 do.
                    a=.(j-1){selected
                    b=.j{selected
                    ae=.a{::Cache
                    be=.b{::Cache
                    if. (0{::ae)-:0{::be do. less=.(Types i.<1{::be)<Types i.<1{::ae
                    else. less=.(0{::be)nameLess 0{::ae end.
                    if. -.less do. break. end.
                    selected=.b (j-1)}selected
                    selected=.a j}selected
                    j=.j-1
                end.
            end.
            emit 'cache entries=',num #selected
            for_i. selected do.
                e=.i{::Cache
                if. 'POS'-:2{::e do. for_r. aged e do. emit '  ',recordText >r end.
                else. emit '  ',(0{::e),' ',(num (4{::e)-Clock),' ',(1{::e),' ',2{::e end.
            end.
        end.
    elseif. command-:'STATS' do.
        emit 'stats queries=',(num +/,QueryCounts),' hits=',num Hits
        for_i. /:QueryAddresses do.
            counts=.i{QueryCounts
            details=.0$a:
            for_k. i.7 do. details=.details,<(lower k{::Kinds),'=',num k{counts end.
            emit '  ',(ip4text i{QueryAddresses),' sent=',(num +/counts),' ',' 'join details
        end.
        details=.0$a:
        for_i. i.4 do. details=.details,<(lower i{::Statuses),'=',num i{Resolutions end.
        emit 'resolutions ',' 'join details
    end.
)
main =: 3 : 0
    Roots=:Down=:QueryAddresses=:i.0
    QueryCounts=:0 7$0
    Zones=:Cache=:0$a:
    Current=:_1
    Clock=:Hits=:0
    Minttl=:1
    Maxttl=:86400
    Negttl=:3600
    Resolutions=:4$0
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    inZones=.1
    for_i. i.#lines do.
        line=.i{::lines
        if. inZones*.line-:'END ZONES' do. finishZones''
            inZones=.0
            continue. end.
        if. (-.inZones)*.line-:'END' do. break. end.
        try.
            if. inZones do. (i+1)zoneInput line else. execute line end.
        catcht. emit 'error line ',(num i+1),': ',Reason end.
    end.
    1!:2&2 ;Output,&.><LF
)
main''
