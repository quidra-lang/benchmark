LF =: 10{a.
Letters =: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
Unreserved =: Letters,'-._~'
Output =: 0$a:
emit =: 3 : 'Output =: Output,<y'
num =: 3 : ',''0'' 8!:2 y'
join =: 4 : '(#x) }. ; (<x) ,&.> y'
lower =: 3 : '(''abcdefghijklmnopqrstuvwxyz'',a.) {~ (''ABCDEFGHIJKLMNOPQRSTUVWXYZ'',a.) i.y'
trim =: 3 : 0
    while. #y do. if. ' '~:{.y do. break. end. y=.}.y end.
    while. #y do. if. ' '~:{:y do. break. end. y=.}:y end.
    y
)
split =: 4 : 0
    result=.0$a:
    start=.0
    for_i. i.#y do.
        if. x=i{y do.
            result=.result,<(i-start){.start}.y
            start=.i+1
        end.
    end.
    result,<start}.y
)
partition =: 4 : 0
    at=.y i.x
    (<at{.y),(<at<#y),<((at+1)<.#y)}.y
)
starts =: 4 : 0
    if. (#x)>#y do. 0 return. end.
    x-:(#x){.y
)
ends =: 4 : 0
    if. (#x)>#y do. 0 return. end.
    x-:(-#x){.y
)
fields =: 4 : 0
    result=.0$a:
    for_row. y do.
        result=.result,<x{::>row
    end.
    result
)
fail =: 3 : 0
    Reason=:y
    throw.
)
validName =: 3 : 0
    if. (0=#y)+.20<#y do. 0 return. end.
    (({.y)e.'abcdefghijklmnopqrstuvwxyz')*.*./y e.'abcdefghijklmnopqrstuvwxyz0123456789_'
)
roleName =: 3 : '(0<#y)*.(16>:#y)*.*./y e.''abcdefghijklmnopqrstuvwxyz'''
segment =: 3 : '(0<#y)*.(-.(<y)e.''.'';''..'')*.*./y e.Unreserved'
canonical =: 3 : 0
    if. y-:'/' do. 1 return. end.
    if. -. '/'starts y do. 0 return. end.
    *./segment&> '/'split }.y
)
media =: 3 : 0
    parts=.'/'split y
    if. 2~:#parts do. 0 return. end.
    if. 0 e.#&>parts do. 0 return. end.
    *./(;parts)e.'abcdefghijklmnopqrstuvwxyz0123456789.+-'
)
decimal =: 3 : 0
    'word low high'=.y
    if. 0=#word do. 0 return. end.
    if. (-.*./word e.'0123456789')+.((1<#word)*.'0'={.word) do. 0 return. end.
    n=.0".word
    (n>:low)*.n<:high
)
hexvalue =: 3 : 0
    digits=.'0123456789abcdef'i.lower y
    if. 16 e.digits do. _1 else. 16#.digits end.
)
hex =: 4 : '(''0123456789ABCDEF''{~(x$16)#:y)'
decode =: 3 : 0
    out=.''
    at=.0
    while. at<#y do.
        if. '%'=at{y do.
            out=.out,a.{~hexvalue 2{.(at+1)}.y
            at=.at+3
        else.
            out=.out,at{y
            at=.at+1
        end.
    end.
    out
)
encode =: 3 : 0
    out=.''
    for_c. y do.
        if. c e.Unreserved do. out=.out,c
        else. out=.out,'%',2 hex a.i.c end.
    end.
    out
)
encoded =: 3 : 0
    parts=.0$a:
    for_pair. y do.
        'k v'=.>pair
        parts=.parts,<(encode k),'=',encode v
    end.
    '&'join parts
)
jsonString =: 3 : 0
    out=.'"'
    for_c. y do.
        if. c e.'\"' do. out=.out,'\' end.
        out=.out,c
    end.
    out,'"'
)
jsonObject =: 3 : 0
    parts=.0$a:
    for_pair. y do.
        'k v'=.>pair
        parts=.parts,<(jsonString k),':',jsonString v
    end.
    '{',(','join parts),'}'
)
html =: 3 : 0
    out=.''
    for_c. y do.
        n=.'&<>"'i.c
        if. n<4 do. out=.out,n{::'&amp;';'&lt;';'&gt;';'&quot;'
        else. out=.out,c end.
    end.
    out
)
pattern =: 3 : 0
    if. -. '/'starts y do. fail 'bad pattern ',y end.
    if. y-:'/' do. 0$a: return. end.
    pieces=.0$a:
    names=.0$a:
    fields=.'/'split }.y
    for_i. i.#fields do.
        field=.i{::fields
        if. segment field do. pieces=.pieces,<'literal';field continue. end.
        if. (-.'{'starts field)+.-.'}'ends field do. fail 'bad pattern ',y end.
        inside=.}.}:field
        kind=.'untyped'
        name=.inside
        if. '*'starts inside do.
            name=.}.inside
            kind=.'wildcard'
            if. i~:<:#fields do. fail 'bad pattern ',y end.
        elseif. ':'e.inside do.
            parts=.':'split inside
            if. 2~:#parts do. fail 'bad pattern ',y end.
            'name kind'=.parts
            if. -. (<kind)e.'int';'slug' do. fail 'bad pattern ',y end.
        end.
        if. (-.validName name)+.(<name)e.names do. fail 'bad pattern ',y end.
        names=.names,<name
        pieces=.pieces,<kind;name
    end.
    pieces
)
wildcard =: 3 : 0
    if. 0=#y do. 0 else. 'wildcard'-:0{::_1{::y end.
)
fits =: 4 : 0
    'kind name'=.x
    select. kind
    case. 'literal' do. y-:name
    case. 'int' do. (0<#y)*.(9>:#y)*.*./y e.'0123456789'
    case. 'slug' do. (0<#y)*.*./y e.'abcdefghijklmnopqrstuvwxyz0123456789-'
    case. do. 1
    end.
)
matches =: 4 : 0
    wild=.wildcard x
    n=.(#x)-wild
    if. ((#y)<n)+.((-.wild)*.(#y)~:n) do. 0 return. end.
    for_i. i.n do. if. -. (i{::x)fits i{::y do. 0 return. end. end.
    1
)
rulePath =: 3 : 0
    wild=.'/*'ends y
    base=.y
    if. wild do. base=._2}.y end.
    if. (-.canonical base)+.(wild*.base-:'/') do. fail 'bad path ',y end.
    (<base),<wild
)
routeId =: 3 : 0
    for_i. i.#Routes do. if. y-:0{::i{::Routes do. i return. end. end.
    _1
)
setRoute =: 3 : 0
    'id field value'=.y
    r=.id{::Routes
    r=.(<value)field}r
    Routes=:(<r)id}Routes
)
priority =: 3 : 0
    pieces=.3{::y
    kinds=.0 fields pieces
    (-(+/(<'literal')=kinds)),(-(+/kinds e.'int';'slug')),wildcard pieces
)
configure =: 3 : 0
    words=.' 'split y
    cmd=.0{::words
    a=.}.words
    n=.#a
    if. -. (<cmd)e.'ROUTE';'TOKEN';'REDIRECT';'ORIGIN';'LIMIT';'TYPES' do. fail 'unknown command ',cmd end.
    select. cmd
    case. 'ROUTE' do. valid=.n e.3 5
    case. 'TOKEN';'LIMIT' do. valid=.n=2
    case. 'REDIRECT' do. valid=.n=3
    case. 'ORIGIN' do. valid=.n=1
    case. 'TYPES' do. valid=.n>:2
    end.
    if. -.valid do. fail 'wrong number of arguments' end.
    select. cmd
    case. 'ROUTE' do.
        'name methods word'=.3{.a
        if. -.validName name do. fail 'bad route name ',name end.
        if. 0<:routeId name do. fail 'duplicate route ',name end.
        ms=.','split methods
        if. (-.*./ms e.;:'GET POST PUT PATCH DELETE')+.(#ms)~:#~.ms do. fail 'bad methods ',methods end.
        pieces=.pattern word
        role=.'none'
        if. n=5 do.
            if. -.'ROLE'-:3{::a do. fail 'unknown option ',3{::a end.
            role=.4{::a
            if. -.roleName role do. fail 'bad role ',role end.
        end.
        Routes=:Routes,<((<name),(<ms),(<word),(<pieces),(<role),(<0$a:),<0)
    case. 'TOKEN' do.
        'token role'=.a
        if. (0=#token)+.(32<#token)+.-.*./token e.Letters,'._-' do. fail 'bad token ',token end.
        if. (<token)e.TokenNames do. fail 'duplicate token ',token end.
        if. -.roleName role do. fail 'bad role ',role end.
        TokenNames=:TokenNames,<token
        TokenRoles=:TokenRoles,<role
    case. 'REDIRECT' do.
        'from to code'=.a
        'base prefix'=.rulePath from
        'target wild'=.rulePath to
        if. prefix~:wild do. fail 'wildcard mismatch' end.
        if. -. (<code)e.'301';'302';'307';'308' do. fail 'bad redirect code ',code end.
        if. (<from)e.0 fields Redirects do. fail 'duplicate redirect ',from end.
        Redirects=:Redirects,<from;base;prefix;target;(0".code)
    case. 'ORIGIN' do.
        origin=.0{::a
        start=.0
        if. 'http://'starts origin do. start=.7 elseif. 'https://'starts origin do. start=.8 end.
        if. (start=0)+.(start=#origin)+.-.*./(start}.origin)e.'abcdefghijklmnopqrstuvwxyz0123456789.:-' do. fail 'bad origin ',origin end.
        if. (<origin)e.Origins do. fail 'duplicate origin ',origin end.
        Origins=:Origins,<origin
    case. 'LIMIT' do.
        if. (-.decimal (0{::a);1;100)+.-.decimal (1{::a);1;3600 do. fail 'bad limit' end.
        if. Capacity>0 do. fail 'duplicate limit' end.
        Capacity=:0".0{::a
        Period=:0".1{::a
    case. 'TYPES' do.
        name=.0{::a
        id=.routeId name
        if. id<0 do. fail 'unknown route ',name end.
        if. #5{::id{::Routes do. fail 'duplicate types ',name end.
        seen=.0$a:
        for_type. }.a do.
            type=.>type
            if. -.media type do. fail 'bad media type ',type end.
            if. (<type)e.seen do. fail 'duplicate media type ',type end.
            seen=.seen,<type
        end.
        setRoute (<id),(<5),<}.a
    end.
)
finish =: 3 : 0
    limit=.'none'
    if. Capacity>0 do. limit=.(num Capacity),'/',num Period end.
    emit 'CONFIG routes=',(num #Routes),' tokens=',(num #TokenNames),' redirects=',(num #Redirects),' origins=',(num #Origins),' limit=',limit,' errors=',num Errors
    for_i. i.#Routes do.
        if. 0=#5{::i{::Routes do. setRoute (<i),(<5),<,<'application/json' end.
    end.
    Ranked=:/:>priority&.>Routes
    for_rank. i.#Ranked do.
        r=.(rank{Ranked){::Routes
        'name methods word pieces role types selections'=.r
        if. (<'GET')e.methods do. methods=.methods,<'HEAD' end.
        if. role-:'none' do. role=.'-' end.
        emit 'TABLE ',(num rank+1),' ',name,' ',(','join /:~methods),' ',word,' role=',role,' types=',','join types
    end.
)
response =: 3 : 0
    'Status Body'=:y
)
rh =: 4 : 0
    at=.ResponseNames i.<x
    if. at=#ResponseNames do. ResponseNames=:ResponseNames,<x
        ResponseValues=:ResponseValues,<y
    else. ResponseValues=:(<y)at}ResponseValues end.
)
header =: 3 : 0
    at=.HeaderNames i.<y
    if. at=#HeaderNames do. '' else. at{::HeaderValues end.
)
redirect =: 3 : 0
    'code location'=.y
    response code;'redirect to ',location
    'Location'rh location
)
normalize =: 3 : 0
    out=.''
    at=.0
    while. at<#y do.
        if. '%'=at{y do.
            code=.hexvalue 2{.(at+1)}.y
            c=.code{a.
            if. c e.Unreserved do. out=.out,c else. out=.out,'%',2 hex code end.
            at=.at+3
        else. out=.out,at{y
            at=.at+1
        end.
    end.
    parts=.0$a:
    for_p. '/'split }.out do.
        p=.>p
        if. p-:'..' do. if. #parts do. parts=.}:parts end.
        elseif. -. (<p)e.'';'.' do. parts=.parts,<p end.
    end.
    '/', '/'join parts
)
weight =: 3 : 0
    parts=.'.'split y
    if. (2<#parts)+.-.(<0{::parts)e.'0';'1' do. _1 return. end.
    fraction=.''
    if. 2=#parts do. fraction=.1{::parts end.
    alphabet=.'0123456789'
    if. '1'-:0{::parts do. alphabet=.'0' end.
    if. (3<#fraction)+.-.*./fraction e.alphabet do. _1 return. end.
    (1000*0".0{::parts)+0".fraction,(3-#fraction)#'0'
)
negotiate =: 3 : 0
    if. -. (<'accept')e.HeaderNames do. 0{::y return. end.
    elements=.0$a:
    for_raw. ','split header 'accept' do.
        parts=.trim&.>';'split >raw
        range=.lower 0{::parts
        specificity=.0
        if. range-:'*/*' do. specificity=.1
        elseif. '/*'ends range do.
            main=._2}.range
            if. (0<#main)*.*./main e.'abcdefghijklmnopqrstuvwxyz0123456789.+-' do. specificity=.2 end.
        elseif. media range do. specificity=.3 end.
        w=.1000
        for_p. }.parts do.
            'key equal value'=. '='partition >p
            if. equal*.'q'-:lower trim key do. w=.weight trim value break. end.
        end.
        if. (specificity>0)*.w>:0 do. elements=.elements,<range;specificity;w end.
    end.
    selected=.''
    best=.0
    for_type. y do.
        type=.>type
        specific=.0
        w=.0
        for_e. elements do.
            'range rank value'=.>e
            fits=.(range-:'*/*')+.range-:type
            if. '/*'ends range do. fits=.fits+.(_1}.range)starts type end.
            if. fits*.rank>specific do. specific=.rank
                w=.value
            end.
        end.
        if. w>best do. best=.w
            selected=.type
        end.
    end.
    selected
)
etag =: 3 : 0
    a=.1
    b=.0
    for_c. a.i.y do.
        a=.65521|a+c
        b=.65521|b+a
    end.
    '"',(lower (4 hex b),4 hex a),'"'
)
renderBody =: 3 : 0
    'type name params query cookies'=.y
    if. type-:'application/json' do.
        items=.0$a:
        for_pair. query do.
            'k v'=.>pair
            items=.items,<'[',(jsonString k),',',(jsonString v),']'
        end.
        '{"route":',(jsonString name),',"params":',(jsonObject params),',"query":[',(','join items),'],"cookies":',(jsonObject cookies),'}' return.
    end.
    if. type-:'text/html' do.
        out=.'<dl><dt>route</dt><dd>',(html name),'</dd>'
        groups=.,<((<'param'),<params)
        groups=.groups,<((<'query'),<query)
        groups=.groups,<((<'cookie'),<cookies)
        for_group. groups do.
            'prefix pairs'=.>group
            for_pair. pairs do.
                'k v'=.>pair
                out=.out,'<dt>',prefix,' ',(html k),'</dt><dd>',(html v),'</dd>'
            end.
        end.
        out,'</dl>' return.
    end.
    lists=.0$a:
    for_pairs. (<params),(<query),<cookies do.
        value=.encoded >pairs
        if. 0=#value do. value=.'-' end.
        lists=.lists,<value
    end.
    'route=',name,' params=',(0{::lists),' query=',(1{::lists),' cookies=',2{::lists
)
routeRequest =: 3 : 0
    'method path query hasquery'=.y
    segments=.0$a:
    if. -.path-:'/' do. segments=.'/'split }.path end.
    matching=.i.0
    allowed=.,<'OPTIONS'
    for_id. Ranked do.
        r=.id{::Routes
        if. (3{::r)matches segments do. matching=.matching,id
            allowed=.~.allowed,1{::r
        end.
    end.
    if. 0=#matching do. response 404;'not found: ',path return. end.
    if. (<'GET')e.allowed do. allowed=.allowed,<'HEAD' end.
    allow=.', 'join /:~allowed
    if. method-:'OPTIONS' do. response 204;''
        'Allow'rh allow
        return.
    end.
    lookup=.method
    if. method-:'HEAD' do. lookup=.'GET' end.
    selected=._1
    for_id. matching do.
        if. (<lookup)e.1{::id{::Routes do. selected=.id break. end.
    end.
    if. selected<0 do. response 405;'method not allowed: ',method
        'Allow'rh allow
        return.
    end.
    r=.selected{::Routes
    setRoute selected;6;(1+6{::r)
    role=.4{::r
    if. -.role-:'none' do.
        if. -. (<'authorization')e.HeaderNames do.
            response 401;'unauthorized: missing token'
            'WWW-Authenticate'rh 'Bearer realm="api"'
            return.
        end.
        'scheme equal token'=. ' 'partition header 'authorization'
        if. (-.'bearer'-:lower scheme)+.-.(<token)e.TokenNames do.
            response 401;'unauthorized: invalid token'
            'WWW-Authenticate'rh 'Bearer realm="api", error="invalid_token"'
            return.
        end.
        tokenrole=.(TokenNames i.<token){::TokenRoles
        if. -. (<tokenrole)e.role;'admin' do. response 403;'forbidden: requires role ',role return. end.
    end.
    types=.5{::r
    if. 1<#types do. 'Vary'rh 'Accept' end.
    type=.negotiate types
    if. 0=#type do. response 406;'not acceptable: ',', 'join types return. end.
    params=.0$a:
    pieces=.3{::r
    for_i. i.#pieces do.
        'kind name'=.i{::pieces
        if. kind-:'literal' do. continue. end.
        if. kind-:'wildcard' do. value=.'/'join decode&.>i}.segments
        elseif. kind-:'int' do. value=.num 0".i{::segments
        elseif. kind-:'untyped' do. value=.decode i{::segments
        else. value=.i{::segments end.
        params=.params,<name;value
    end.
    params=.params /:0 fields params
    queries=.0$a:
    if. hasquery do.
        for_raw. '&'split query do.
            raw=.>raw
            if. 0=#raw do. continue. end.
            'k equal v'=. '='partition raw
            k=.decode ' ' (I.k='+')}k
            v=.decode ' ' (I.v='+')}v
            queries=.queries,<k;v
        end.
    end.
    cookies=.0$a:
    names=.0$a:
    for_raw. ';'split header 'cookie' do.
        'k equal v'=. '='partition trim >raw
        if. equal*.(0<#k)*.-.(<k)e.names do.
            cookies=.cookies,<k;v
            names=.names,<k
        end.
    end.
    cookies=.cookies /:0 fields cookies
    body=.renderBody (<type),(<0{::r),(<params),(<queries),<cookies
    tag=.etag body
    if. (<'if-none-match')e.HeaderNames do.
        for_raw. ','split header 'if-none-match' do.
            candidate=.trim >raw
            if. 'W/'starts candidate do. candidate=.2}.candidate end.
            if. (<candidate)e.'*';tag do.
                if. lookup-:'GET' do. response 304;''
                    'ETag'rh tag
                else. response 412;'precondition failed: ',tag end.
                return.
            end.
        end.
    end.
    response 200;body
    ContentType=:type
    'ETag'rh tag
)
dispatch =: 3 : 0
    'method target'=.y
    if. -. (<method)e.;:'GET HEAD POST PUT PATCH DELETE OPTIONS' do. response 501;'not implemented: ',method return. end.
    if. 0=#header 'host' do. response 400;'bad request: missing host' return. end.
    effective=.method
    if. (<'x-http-method-override')e.HeaderNames do.
        override=.header 'x-http-method-override'
        if. (-.method-:'POST')+.-.(<override)e.;:'PUT PATCH DELETE' do. response 400;'bad request: method override' return. end.
        effective=.override
    end.
    client=.header 'x-client'
    if. #client do.
        time=.0".header 'x-time'
        id=.ClientNames i.<client
        if. id=#ClientNames do.
            ClientNames=:ClientNames,<client
            Clients=:Clients,<(Capacity*Period),time,0,0
        end.
        c=.id{::Clients
        wait=.0
        if. Capacity>0 do.
            level=.(Capacity*Period)<.(0{c)+(time-1{c)*Capacity
            c=.time 1}level 0}c
            if. level<Period do. wait=.>. (Period-level)%Capacity
            else. c=.(level-Period)0}c end.
        end.
        if. wait>0 do.
            c=.(1+3{c)3}c
            Clients=:(<c)id}Clients
            response 429;'too many requests: client ',client
            'Retry-After'rh num wait
            return.
        end.
        c=.(1+2{c)2}c
        Clients=:(<c)id}Clients
    end.
    'path question query'=. '?'partition target
    suffix=.''
    if. question do. suffix=.'?',query end.
    normal=.normalize path
    if. -.normal-:path do. redirect 308;normal,suffix return. end.
    for_rule. Redirects do.
        'from base prefix to code'=.>rule
        if. (path-:base)+.(prefix*.(base,'/')starts path) do. redirect code;to,((#base)}.path),suffix return. end.
    end.
    routeRequest effective;path;query;question
)
respond =: 3 : 0
    'line headers'=.y
    ResponseNames=:ResponseValues=:0$a:
    ContentType=:'text/plain'
    ShowBody=:1
    parts=.' 'split line
    valid=.0
    if. 3=#parts do.
        'method target version'=.parts
        valid=.(0<#method)*.(16>:#method)*.(*./method e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ')*.('/'starts target)*.(-.'#'e.target)*.version-:'HTTP/1.1'
    end.
    if. -.valid do. response 400;'bad request: request line' return. end.
    ShowBody=:-.method-:'HEAD'
    for_i. I.target='%' do.
        code=._1
        if. (i+2)<#target do. code=.hexvalue 2{.(i+1)}.target end.
        if. (code<32)+.code>126 do. response 400;'bad request: percent escape' return. end.
    end.
    HeaderNames=:HeaderValues=:0$a:
    for_i. i.#headers do.
        'name colon value'=. ':'partition i{::headers
        if. (-.colon)+.(0=#name)+.-.*./name e.Letters,'-' do. response 400;'bad request: header line ',num i+1 return. end.
        name=.lower name
        if. (<name)e.HeaderNames do. response 400;'bad request: duplicate header ',name return. end.
        HeaderNames=:HeaderNames,<name
        HeaderValues=:HeaderValues,<trim value
    end.
    dispatch method;target
    origin=.header 'origin'
    if. (<origin)e.Origins do.
        'Access-Control-Allow-Origin'rh origin
        if. (Status=204)*.(<'access-control-request-method')e.HeaderNames do.
            'Access-Control-Allow-Methods'rh (ResponseNames i.<'Allow'){::ResponseValues
        end.
    end.
)
buildUrl =: 3 : 0
    'name args'=.y
    id=.routeId name
    if. id<0 do. fail 'unknown route ',name end.
    r=.id{::Routes
    pieces=.3{::r
    names=.0$a:
    for_p. pieces do. if. -.'literal'-:0{::>p do. names=.names,<1{::>p end. end.
    keys=.0$a:
    vals=.0$a:
    query=.0$a:
    for_arg. args do.
        arg=.>arg
        'k equal v'=. '='partition arg
        if. (-.equal)+.0=#k do. fail 'bad argument ',arg end.
        if. (<k)e.names do.
            if. (<k)e.keys do. fail 'duplicate parameter ',k end.
            keys=.keys,<k
            vals=.vals,<v
        else. query=.query,<k;v end.
    end.
    segments=.0$a:
    for_p. pieces do.
        p=.>p
        'kind pname'=.p
        if. kind-:'literal' do. segments=.segments,<pname continue. end.
        at=.keys i.<pname
        if. (at=#keys)*.-.kind-:'wildcard' do. fail 'missing parameter ',pname end.
        value=.''
        if. at<#keys do. value=.at{::vals end.
        valid=.1
        if. kind-:'untyped' do. valid=.-.(<value)e.'';'.';'..'
        elseif. kind-:'wildcard' do.
            if. #value do. valid=.-.+./('/'split value)e.'';'.';'..' end.
        else. valid=.p fits value end.
        if. -.valid do. fail 'bad value for ',pname end.
        if. kind-:'wildcard' do.
            if. #value do. segments=.segments,encode&.>'/'split value end.
        else. segments=.segments,<encode value end.
    end.
    url=.'/', '/'join segments
    if. #query do. url=.url,'?',encoded query end.
    url
)
phrase =: 3 : 0
    codes=.200 204 301 302 304 307 308 400 401 403 404 405 406 412 429 501
    (codes i.y){::'OK';'No Content';'Moved Permanently';'Found';'Not Modified';'Temporary Redirect';'Permanent Redirect';'Bad Request';'Unauthorized';'Forbidden';'Not Found';'Method Not Allowed';'Not Acceptable';'Precondition Failed';'Too Many Requests';'Not Implemented'
)
main =: 3 : 0
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    Routes=:TokenNames=:TokenRoles=:Redirects=:Origins=:ClientNames=:Clients=:0$a:
    Errors=:Capacity=:Period=:Requests=:UrlOk=:UrlErrors=:0
    Statuses=:502$0
    at=.0
    while. -. 'REQUESTS'-:at{::lines do.
        try. configure at{::lines
        catcht. Errors=:Errors+1
            emit 'CONFIG ERROR ',(num at+1),': ',Reason
        end.
        at=.at+1
    end.
    finish''
    at=.at+1
    while. -. 'END'-:at{::lines do.
        line=.at{::lines
        at=.at+1
        if. 'URLFOR 'starts line do.
            fields=.' 'split line
            name=.1{::fields
            try. url=.buildUrl (<name),<2}.fields
                UrlOk=:UrlOk+1
                emit 'URLFOR ',name,' ',url
            catcht. UrlErrors=:UrlErrors+1
                emit 'URLFOR ERROR ',Reason
            end.
            continue.
        end.
        headers=.0$a:
        while. #at{::lines do. headers=.headers,at{lines
            at=.at+1
        end.
        at=.at+1
        respond (<line),<headers
        Requests=:Requests+1
        Statuses=:(1+Status{Statuses)Status}Statuses
        emit 'REQUEST ',num Requests
        emit 'HTTP/1.1 ',(num Status),' ',phrase Status
        if. -.Status e.204 304 do. 'Content-Type'rh ContentType
            'Content-Length'rh num #Body
        end.
        for_name. ;:'Location Allow Retry-After WWW-Authenticate Access-Control-Allow-Origin Access-Control-Allow-Methods Vary ETag Content-Type Content-Length' do.
            i=.ResponseNames i.name
            if. i<#ResponseNames do. emit (>name),': ',i{::ResponseValues end.
        end.
        if. ShowBody*.-.Status e.204 304 do. emit Body end.
    end.
    emit 'SUMMARY requests=',(num Requests),' urlfor_ok=',(num UrlOk),' urlfor_error=',num UrlErrors
    for_status. I.Statuses do. emit 'STATUS ',(num status),' ',num status{Statuses end.
    for_r. Routes do. emit 'ROUTE ',(0{::>r),' ',num 6{::>r end.
    for_name. /:~ClientNames do.
        c=.(ClientNames i.name){::Clients
        emit 'CLIENT ',(>name),' allowed=',(num 2{c),' limited=',num 3{c
    end.
    1!:2&2 ;Output,&.><LF
)
main''
