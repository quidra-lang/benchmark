const NAME=r"^[a-z][a-z0-9_]{0,19}$"
const ROLE=r"^[a-z]{1,16}$"
const MEDIA=r"^[a-z0-9.+-]+/[a-z0-9.+-]+$"
const UNRESERVED="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
const REASONS=Dict(200=>"OK",204=>"No Content",301=>"Moved Permanently",302=>"Found",304=>"Not Modified",307=>"Temporary Redirect",308=>"Permanent Redirect",400=>"Bad Request",401=>"Unauthorized",403=>"Forbidden",404=>"Not Found",405=>"Method Not Allowed",406=>"Not Acceptable",412=>"Precondition Failed",429=>"Too Many Requests",501=>"Not Implemented")
const HEADERORDER=split("Location Allow Retry-After WWW-Authenticate Access-Control-Allow-Origin Access-Control-Allow-Methods Vary ETag Content-Type Content-Length")
struct InputError <: Exception
    message::String
end
fail(s)=throw(InputError(s))
part(s,a,b=length(s))=a>b ? "" : String(s[a:b])
trim(s)=String(strip(s,' '))
function partition(s,separator)
    p=findfirst(separator,s)
    p===nothing ? (String(s),false,"") : (part(s,1,first(p)-1),true,part(s,last(p)+1))
end
segment(s)=!isempty(s) && all(c->c in UNRESERVED,s) && !(s in (".",".."))
canonical(s)=s=="/" || startswith(s,"/") && all(segment,split(part(s,2),'/';keepempty=true))
decimal(s,lo,hi)=occursin(r"^(?:0|[1-9][0-9]*)$",s) && lo<=parse(BigInt,s)<=hi
decode(s)=replace(s,r"%[0-9A-Fa-f]{2}"=>x->string(Char(parse(Int,part(x,2);base=16))))
encode(s)=join(c in UNRESERVED ? string(c) : "%"*uppercase(string(Int(c);base=16,pad=2)) for c in s)
encoded(pairs)=join((encode(k)*"="*encode(v) for (k,v) in pairs),"&")
withhead(methods)="GET" in methods ? union(Set(methods),Set(["HEAD"])) : Set(methods)
struct Piece
    kind::Symbol
    name::String
end
function pattern(s)
    startswith(s,"/") || return nothing
    s=="/" && return Piece[]
    pieces=Piece[]; names=Set{String}()
    fields=split(part(s,2),'/';keepempty=true)
    for (i,field) in enumerate(fields)
        if segment(field); push!(pieces,Piece(:literal,field)); continue; end
        m=match(r"^\{([a-z][a-z0-9_]{0,19})(?::(int|slug))?\}$",field)
        w=match(r"^\{\*([a-z][a-z0-9_]{0,19})\}$",field)
        if w!==nothing && i==length(fields); k=:wildcard; name=String(w.captures[1])
        elseif m!==nothing; k=m.captures[2]===nothing ? :untyped : Symbol(m.captures[2]); name=String(m.captures[1])
        else; return nothing; end
        name in names && return nothing
        push!(names,name); push!(pieces,Piece(k,name))
    end
    pieces
end
fits(p,s)=p.kind==:literal ? s==p.name : p.kind==:int ? occursin(r"^[0-9]{1,9}$",s) : p.kind==:slug ? occursin(r"^[a-z0-9-]+$",s) : true
accepts(p,s)=p.kind==:untyped ? !(s in ("",".","..")) : p.kind==:wildcard ? isempty(s) || all(x->!(x in ("",".","..")),split(s,'/';keepempty=true)) : fits(p,s)
mutable struct Route
    name::String
    methods::Set{String}
    pattern::String
    pieces::Vector{Piece}
    role::String
    number::Int
    types::Vector{String}
    selections::Int
end
wild(r)=!isempty(r.pieces) && last(r.pieces).kind==:wildcard
priority(r)=(-count(p->p.kind==:literal,r.pieces),-count(p->p.kind in (:int,:slug),r.pieces),wild(r),r.number)
function matches(r,segments)
    n=length(r.pieces)-wild(r)
    length(segments)>=n && (wild(r) || length(segments)==n) && all(i->fits(r.pieces[i],segments[i]),1:n)
end
function rulepath(s)
    if endswith(s,"/*")
        base=part(s,1,length(s)-2); return base!="/" && canonical(base) ? (base,true) : nothing
    end
    canonical(s) ? (String(s),false) : nothing
end
mutable struct Response
    status::Int
    body::Union{Nothing,String}
    headers::Dict{String,String}
    type::String
end
Response(status,body=nothing,headers=Dict{String,String}(),type="text/plain")=Response(status,body,headers,type)
redirect(code,destination)=Response(code,"redirect to $destination",Dict("Location"=>destination))
mutable struct Client
    level::Int
    time::Int
    allowed::Int
    limited::Int
end
mutable struct Router
    routes::Vector{Route}
    ranked::Vector{Route}
    tokens::Dict{String,String}
    redirects::Vector{Tuple{String,String,Bool,String,Int}}
    origins::Set{String}
    capacity::Int
    period::Int
    errors::Int
    requests::Int
    urlok::Int
    urlerror::Int
    statuses::Dict{Int,Int}
    clients::Dict{String,Client}
end
Router()=Router(Route[],Route[],Dict{String,String}(),Tuple{String,String,Bool,String,Int}[],Set{String}(),0,0,0,0,0,0,Dict{Int,Int}(),Dict{String,Client}())
findroute(r,name)=findfirst(x->x.name==name,r.routes)
function configure!(r,line)
    words=String.(split(line,' ')); cmd=words[1]; a=words[2:end]; n=length(a)
    cmd in ("ROUTE","TOKEN","REDIRECT","ORIGIN","LIMIT","TYPES") || fail("unknown command $cmd")
    valid=cmd=="ROUTE" ? n in (3,5) : cmd=="TOKEN" ? n==2 : cmd=="REDIRECT" ? n==3 : cmd=="ORIGIN" ? n==1 : cmd=="LIMIT" ? n==2 : n>=2
    valid || fail("wrong number of arguments")
    if cmd=="ROUTE"
        name,methods,word=a[1:3]; occursin(NAME,name) || fail("bad route name $name")
        findroute(r,name)!==nothing && fail("duplicate route $name")
        ms=String.(split(methods,',';keepempty=true))
        all(m->m in ("GET","POST","PUT","PATCH","DELETE"),ms) && length(unique(ms))==length(ms) || fail("bad methods $methods")
        pieces=pattern(word); pieces===nothing && fail("bad pattern $word")
        role="none"
        if n==5
            a[4]=="ROLE" || fail("unknown option $(a[4])"); occursin(ROLE,a[5]) || fail("bad role $(a[5])"); role=a[5]
        end
        push!(r.routes,Route(name,Set(ms),word,pieces,role,length(r.routes)+1,String[],0))
    elseif cmd=="TOKEN"
        token,role=a; occursin(r"^[A-Za-z0-9._-]{1,32}$",token) || fail("bad token $token")
        haskey(r.tokens,token) && fail("duplicate token $token"); occursin(ROLE,role) || fail("bad role $role"); r.tokens[token]=role
    elseif cmd=="REDIRECT"
        from,to,code=a; src=rulepath(from); src===nothing && fail("bad path $from")
        dst=rulepath(to); dst===nothing && fail("bad path $to")
        src[2]==dst[2] || fail("wildcard mismatch"); code in ("301","302","307","308") || fail("bad redirect code $code")
        any(x->x[1]==from,r.redirects) && fail("duplicate redirect $from")
        push!(r.redirects,(from,src[1],src[2],dst[1],parse(Int,code)))
    elseif cmd=="ORIGIN"
        s=a[1]; occursin(r"^https?://[a-z0-9.:-]+$",s) || fail("bad origin $s")
        s in r.origins && fail("duplicate origin $s"); push!(r.origins,s)
    elseif cmd=="LIMIT"
        decimal(a[1],1,100) && decimal(a[2],1,3600) || fail("bad limit")
        r.capacity>0 && fail("duplicate limit"); r.capacity=parse(Int,a[1]); r.period=parse(Int,a[2])
    else
        name=a[1]; idx=findroute(r,name); idx===nothing && fail("unknown route $name")
        route=r.routes[idx]; !isempty(route.types) && fail("duplicate types $name"); seen=Set{String}()
        for t in a[2:end]
            occursin(MEDIA,t) || fail("bad media type $t"); t in seen && fail("duplicate media type $t"); push!(seen,t)
        end
        route.types=a[2:end]
    end
end
function finish!(r)
    limit=r.capacity==0 ? "none" : "$(r.capacity)/$(r.period)"
    println("CONFIG routes=$(length(r.routes)) tokens=$(length(r.tokens)) redirects=$(length(r.redirects)) origins=$(length(r.origins)) limit=$limit errors=$(r.errors)")
    for route in r.routes; isempty(route.types) && push!(route.types,"application/json"); end
    r.ranked=sort(r.routes;by=priority)
    for (i,route) in enumerate(r.ranked)
        println("TABLE $i $(route.name) $(join(sort!(collect(withhead(route.methods))),',')) $(route.pattern) role=$(route.role=="none" ? "-" : route.role) types=$(join(route.types,','))")
    end
end
function normalized(path)
    escaped=replace(path,r"%[0-9A-Fa-f]{2}"=>s->begin
        c=Char(parse(Int,part(s,2);base=16)); c in UNRESERVED ? string(c) : uppercase(s)
    end)
    pieces=String[]
    for s in split(part(escaped,2),'/';keepempty=true)
        if s==".."; !isempty(pieces) && pop!(pieces)
        elseif !(s in ("",".")); push!(pieces,s); end
    end
    "/"*join(pieces,'/')
end
function negotiate(types,accept)
    accept===nothing && return types[1]
    elements=Tuple{String,Int,Int}[]
    for raw in split(accept,',';keepempty=true)
        parts=trim.(split(raw,';';keepempty=true)); range=lowercase(parts[1])
        specificity=range=="*/*" ? 1 : occursin(r"^[a-z0-9.+-]+/\*$",range) ? 2 : occursin(MEDIA,range) ? 3 : 0
        weight=1000
        for parameter in parts[2:end]
            key,equal,v=partition(parameter,"=")
            if equal && lowercase(trim(key))=="q"
                v=trim(v)
                if !occursin(r"^(?:0(?:\.[0-9]{0,3})?|1(?:\.0{0,3})?)$",v); weight=-1
                else
                    whole,_,fraction=partition(v,"."); weight=1000*parse(Int,whole)+parse(Int,rpad(fraction,3,'0'))
                end
                break
            end
        end
        specificity>0 && weight>=0 && push!(elements,(range,specificity,weight))
    end
    best=nothing; bestweight=0
    for type in types
        specificity=0; weight=0
        for (range,rank,w) in elements
            fits=range=="*/*" || endswith(range,"/*") && startswith(type,part(range,1,length(range)-1)) || range==type
            if fits && rank>specificity; specificity=rank; weight=w; end
        end
        if weight>bestweight; best=type; bestweight=weight; end
    end
    best
end
jsonstring(s)="\""*replace(s,'\\'=>"\\\\",'"'=>"\\\"")*"\""
jsonobject(pairs)="{"*join((jsonstring(k)*":"*jsonstring(v) for (k,v) in pairs),',')*"}"
html(s)=replace(s,'&'=>"&amp;",'<'=>"&lt;",'>'=>"&gt;",'"'=>"&quot;")
function body(type,name,params,query,cookies)
    if type=="application/json"
        q=join(("["*jsonstring(k)*","*jsonstring(v)*"]" for (k,v) in query),',')
        return "{\"route\":"*jsonstring(name)*",\"params\":"*jsonobject(params)*",\"query\":["*q*"],\"cookies\":"*jsonobject(cookies)*"}"
    elseif type=="text/html"
        entries=[("route",name)]
        for (prefix,pairs) in (("param",params),("query",query),("cookie",cookies)); append!(entries,[(prefix*" "*k,v) for (k,v) in pairs]); end
        return "<dl>"*join("<dt>$(html(k))</dt><dd>$(html(v))</dd>" for (k,v) in entries)*"</dl>"
    end
    lists=[isempty(pairs) ? "-" : encoded(pairs) for pairs in (params,query,cookies)]
    "route=$name params=$(lists[1]) query=$(lists[2]) cookies=$(lists[3])"
end
function etag(s)
    a=1; b=0
    for c in s; a=mod(a+Int(c),65521); b=mod(b+a,65521); end
    "\""*string(b;base=16,pad=4)*string(a;base=16,pad=4)*"\""
end
function route_request!(r,method,path,query,h)
    segments=path=="/" ? String[] : String.(split(part(path,2),'/'))
    matching=filter(route->matches(route,segments),r.ranked)
    isempty(matching) && return Response(404,"not found: $path")
    allowed=Set(["OPTIONS"]); for route in matching; union!(allowed,route.methods); end
    allow=join(sort!(collect(withhead(allowed))),", ")
    method=="OPTIONS" && return Response(204,nothing,Dict("Allow"=>allow))
    lookup=method=="HEAD" ? "GET" : method
    idx=findfirst(route->lookup in route.methods,matching)
    idx===nothing && return Response(405,"method not allowed: $method",Dict("Allow"=>allow))
    route=matching[idx]; route.selections+=1
    if route.role!="none"
        !haskey(h,"authorization") && return Response(401,"unauthorized: missing token",Dict("WWW-Authenticate"=>"Bearer realm=\"api\""))
        scheme,_,token=partition(h["authorization"]," ")
        (lowercase(scheme)!="bearer" || !haskey(r.tokens,token)) && return Response(401,"unauthorized: invalid token",Dict("WWW-Authenticate"=>"Bearer realm=\"api\", error=\"invalid_token\""))
        r.tokens[token] in (route.role,"admin") || return Response(403,"forbidden: requires role $(route.role)")
    end
    vary=length(route.types)>1 ? Dict("Vary"=>"Accept") : Dict{String,String}()
    type=negotiate(route.types,get(h,"accept",nothing))
    type===nothing && return Response(406,"not acceptable: $(join(route.types,", "))",vary)
    params=Tuple{String,String}[]
    for (i,p) in enumerate(route.pieces)
        p.kind==:literal && continue
        v=p.kind==:wildcard ? join(decode.(segments[i:end]),'/') : p.kind==:int ? string(parse(Int,segments[i])) : p.kind==:untyped ? decode(segments[i]) : segments[i]
        push!(params,(p.name,v))
    end
    sort!(params;by=first); queries=Tuple{String,String}[]
    if query!==nothing
        for raw in split(query,'&';keepempty=true)
            isempty(raw) && continue
            k,_,v=partition(raw,"="); push!(queries,(decode(replace(k,'+'=>' ')),decode(replace(v,'+'=>' '))))
        end
    end
    cookies=Dict{String,String}()
    for raw in split(get(h,"cookie",""),';';keepempty=true)
        k,equal,v=partition(trim(raw),"="); equal && !isempty(k) && !haskey(cookies,k) && (cookies[k]=v)
    end
    result=body(type,route.name,params,queries,sort!(collect(cookies);by=first)); tag=etag(result)
    if haskey(h,"if-none-match")
        hit=any(raw->begin x=trim(raw); startswith(x,"W/") && (x=part(x,3)); x in ("*",tag) end,split(h["if-none-match"],',';keepempty=true))
        if hit
            if lookup=="GET"; vary["ETag"]=tag; return Response(304,nothing,vary)
            else; return Response(412,"precondition failed: $tag",vary); end
        end
    end
    vary["ETag"]=tag; Response(200,result,vary,type)
end
function dispatch!(r,method,target,h)
    method in ("GET","HEAD","POST","PUT","PATCH","DELETE","OPTIONS") || return Response(501,"not implemented: $method")
    isempty(get(h,"host","")) && return Response(400,"bad request: missing host")
    effective=method
    if haskey(h,"x-http-method-override")
        override=h["x-http-method-override"]
        method=="POST" && override in ("PUT","PATCH","DELETE") || return Response(400,"bad request: method override")
        effective=override
    end
    client=get(h,"x-client","")
    if !isempty(client)
        time=parse(Int,h["x-time"]); c=get!(r.clients,client,Client(r.capacity*r.period,time,0,0)); wait=0
        if r.capacity>0
            c.level=min(r.capacity*r.period,c.level+(time-c.time)*r.capacity); c.time=time
            if c.level<r.period; wait=cld(r.period-c.level,r.capacity)
            else; c.level-=r.period; end
        end
        if wait>0; c.limited+=1; return Response(429,"too many requests: client $client",Dict("Retry-After"=>string(wait))); end
        c.allowed+=1
    end
    path,question,query=partition(target,"?"); suffix=question ? "?"*query : ""; normal=normalized(path)
    normal!=path && return redirect(308,normal*suffix)
    for (_,base,prefix,to,code) in r.redirects
        (path==base || prefix && startswith(path,base*"/")) && return redirect(code,to*part(path,length(base)+1)*suffix)
    end
    route_request!(r,effective,path,question ? query : nothing,h)
end
function respond!(r,line,headers)
    fields=String.(split(line,' ';keepempty=true))
    valid=length(fields)==3 && occursin(r"^[A-Z]{1,16}$",fields[1]) && startswith(fields[2],"/") && !occursin('#',fields[2]) && fields[3]=="HTTP/1.1"
    valid || return Response(400,"bad request: request line"),true
    method,target,_=fields; showbody=method!="HEAD"
    for i in eachindex(target)
        if target[i]=='%'
            raw=part(target,i+1,min(i+2,length(target)))
            occursin(r"^[0-9A-Fa-f]{2}$",raw) && 32<=parse(Int,raw;base=16)<=126 || return Response(400,"bad request: percent escape"),showbody
        end
    end
    h=Dict{String,String}()
    for (i,header) in enumerate(headers)
        name,colon,v=partition(header,":")
        colon && occursin(r"^[A-Za-z0-9-]+$",name) || return Response(400,"bad request: header line $i"),showbody
        name=lowercase(name); haskey(h,name) && return Response(400,"bad request: duplicate header $name"),showbody
        h[name]=trim(v)
    end
    response=dispatch!(r,method,target,h); origin=get(h,"origin",nothing)
    if origin in r.origins
        response.headers["Access-Control-Allow-Origin"]=origin
        response.status==204 && haskey(h,"access-control-request-method") && (response.headers["Access-Control-Allow-Methods"]=response.headers["Allow"])
    end
    response,showbody
end
function urlfor(r,name,args)
    idx=findroute(r,name); idx===nothing && fail("unknown route $name"); route=r.routes[idx]
    names=Set(p.name for p in route.pieces if p.kind!=:literal); values=Dict{String,String}(); query=Tuple{String,String}[]
    for arg in args
        k,equal,v=partition(arg,"="); equal && !isempty(k) || fail("bad argument $arg")
        if k in names; haskey(values,k) && fail("duplicate parameter $k"); values[k]=v
        else; push!(query,(k,v)); end
    end
    segments=String[]
    for p in route.pieces
        if p.kind==:literal; push!(segments,p.name); continue; end
        v=get(values,p.name,nothing)
        v===nothing && p.kind!=:wildcard && fail("missing parameter $(p.name)")
        v!==nothing && !accepts(p,v) && fail("bad value for $(p.name)")
        if p.kind!=:wildcard; push!(segments,encode(v))
        elseif v!==nothing && !isempty(v); append!(segments,encode.(split(v,'/'))); end
    end
    "/"*join(segments,'/')*(isempty(query) ? "" : "?"*encoded(query))
end
function main()
    lines=readlines(); r=Router(); at=1
    while lines[at]!="REQUESTS"
        try; configure!(r,lines[at])
        catch e
            e isa InputError || rethrow(); r.errors+=1; println("CONFIG ERROR $at: $(e.message)")
        end
        at+=1
    end
    finish!(r); at+=1
    while lines[at]!="END"
        if startswith(lines[at],"URLFOR ")
            fields=String.(split(lines[at],' ')); name=fields[2]
            try; url=urlfor(r,name,fields[3:end]); r.urlok+=1; println("URLFOR $name $url")
            catch e
                e isa InputError || rethrow(); r.urlerror+=1; println("URLFOR ERROR $(e.message)")
            end
            at+=1
        else
            line=lines[at]; at+=1; headers=String[]
            while !isempty(lines[at]); push!(headers,lines[at]); at+=1; end
            at+=1; response,showbody=respond!(r,line,headers); r.requests+=1; status=response.status
            r.statuses[status]=get(r.statuses,status,0)+1; println("REQUEST $(r.requests)\nHTTP/1.1 $status $(REASONS[status])")
            if response.body!==nothing; response.headers["Content-Type"]=response.type; response.headers["Content-Length"]=string(length(response.body)); end
            for name in HEADERORDER; haskey(response.headers,name) && println("$name: $(response.headers[name])"); end
            response.body!==nothing && showbody && println(response.body)
        end
    end
    println("SUMMARY requests=$(r.requests) urlfor_ok=$(r.urlok) urlfor_error=$(r.urlerror)")
    for status in sort!(collect(keys(r.statuses))); println("STATUS $status $(r.statuses[status])"); end
    for route in r.routes; println("ROUTE $(route.name) $(route.selections)"); end
    for name in sort!(collect(keys(r.clients))); c=r.clients[name]; println("CLIENT $name allowed=$(c.allowed) limited=$(c.limited)"); end
end
main()
