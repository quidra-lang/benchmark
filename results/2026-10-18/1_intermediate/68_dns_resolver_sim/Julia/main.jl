const TYPES=("A","NS","CNAME","SOA","PTR","MX","TXT","AAAA")
const KINDS=("ANSWER","CNAME","REFERRAL","NODATA","NXDOMAIN","LAME","TIMEOUT")
const STATUSES=("NOERROR","NODATA","NXDOMAIN","SERVFAIL")
const Name=Tuple{Vararg{String}}
const ROOT=()
struct InputError <: Exception
    message::String
end
fail(s)=throw(InputError(s))
require(b,s)=b ? nothing : fail(s)
part(s,a,b=length(s))=a>b ? "" : String(s[a:b])
integerword(s)=occursin(r"^(?:0|[1-9][0-9]{0,8})$",s)
function ipv4(s)
    fields=split(s,'.';keepempty=true)
    length(fields)==4 && all(x->occursin(r"^(?:0|[1-9][0-9]{0,2})$",x),fields) || fail("bad address $s")
    values=parse.(Int,fields); all(<=(255),values) || fail("bad address $s")
    foldl((a,b)->a*256+b,values;init=0)
end
ip4text(n)=join([div(n,256^i)%256 for i in 3:-1:0],'.')
function groups(s)
    isempty(s) && return Int[]
    parts=split(s,':';keepempty=true)
    all(x->occursin(r"^[0-9a-fA-F]{1,4}$",x),parts) || return nothing
    parse.(Int,parts;base=16)
end
function ipv6(s)
    parts=split(s,"::";limit=2,keepempty=true)
    if length(parts)==1
        values=groups(s); values!==nothing && length(values)==8 || fail("bad address $s"); return Tuple(values)
    end
    front=groups(parts[1]); back=groups(parts[2])
    front!==nothing && back!==nothing && length(front)+length(back)<=7 || fail("bad address $s")
    Tuple([front;zeros(Int,8-length(front)-length(back));back])
end
function ip6text(values)
    best=0; width=1; at=1
    while at<=8
        stop=at
        while stop<=8 && values[stop]==0; stop+=1; end
        if stop-at>width; best=at; width=stop-at; end
        at=max(stop,at+1)
    end
    parts=[string(x;base=16) for x in values]
    best==0 ? join(parts,':') : join(parts[1:best-1],':')*"::"*join(parts[best+width:end],':')
end
function parsename(s;wildcard=false,origin=nothing)
    origin!==nothing && s=="@" && return origin
    s=="." && return ROOT
    absolute=endswith(s,"."); fields=split(absolute ? part(s,1,length(s)-1) : s,'.';keepempty=true)
    for (i,label) in enumerate(fields)
        wildcard && i==1 && label=="*" && continue
        occursin(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$",label) || fail("bad name $s")
    end
    name=Tuple(lowercase.(String.(fields)))
    origin!==nothing && !absolute ? (name...,origin...) : name
end
nametext(n)=isempty(n) ? "." : join(n,'.')*"."
namekey(n)=reverse(n)
below(n,a)=length(n)>=length(a) && n[length(n)-length(a)+1:end]==a
ancestors(n)=[n[i:end] for i in 1:length(n)+1]
function ttlword(s)
    if integerword(s); n=parse(Int,s)
    else
        pairs=collect(eachmatch(r"(0|[1-9][0-9]{0,2})([wWdDhHmMsS])",s))
        join(m.match for m in pairs)==s && !isempty(pairs) || fail("bad ttl $s")
        previous=0; n=0
        for m in pairs
            at=findfirst(==(lowercase(m.captures[2])[1]),"wdhms")
            at>previous || fail("bad ttl $s"); previous=at; n+=parse(Int,m.captures[1])*(604800,86400,3600,60,1)[at]
        end
    end
    require(1<=n<=604800,"bad ttl $s"); n
end
checktype(s)=require(s in TYPES,"bad type $s")
function parsedata(kind,fields,origin)
    kind=="A" && return ipv4(fields[1])
    kind=="AAAA" && return ipv6(fields[1])
    kind in ("NS","CNAME","PTR") && return parsename(fields[1];origin)
    if kind=="MX"
        require(integerword(fields[1]) && parse(Int,fields[1])<=65535,"bad preference $(fields[1])")
        return (parse(Int,fields[1]),parsename(fields[2];origin))
    end
    if kind=="TXT"
        s=join(fields,' '); require(length(s)>=2 && s[1]=='"' && s[end]=='"' && !('"' in part(s,2,length(s)-1)),"bad text $s"); return s
    end
    first=parsename(fields[1];origin); second=parsename(fields[2];origin); numbers=Int[]
    for s in fields[3:6]; require(integerword(s),"bad number $s"); push!(numbers,parse(Int,s)); end
    s=fields[7]; require(integerword(s) && 1<=parse(Int,s)<=86400,"bad minimum $s")
    (first,second,numbers...,parse(Int,s))
end
struct Record
    owner::Name
    ttl::Int
    kind::String
    data::Any
end
withttl(r,t)=Record(r.owner,t,r.kind,r.data)
withowner(r,n)=Record(n,r.ttl,r.kind,r.data)
samerecord(a,b)=a.owner==b.owner && a.kind==b.kind && a.data==b.data
datakey(r)=r.kind in ("NS","CNAME","PTR") ? namekey(r.data) : r.kind=="MX" ? (r.data[1],namekey(r.data[2])) : r.data
recordkey(r)=(namekey(r.owner),findfirst(==(r.kind),TYPES),datakey(r))
dataorder(records)=sort(records;by=datakey)
function datatext(r)
    r.kind=="A" && return ip4text(r.data)
    r.kind=="AAAA" && return ip6text(r.data)
    r.kind in ("NS","CNAME","PTR") && return nametext(r.data)
    r.kind=="MX" && return string(r.data[1])*" "*nametext(r.data[2])
    r.kind=="SOA" && return nametext(r.data[1])*" "*nametext(r.data[2])*" "*join(r.data[3:end],' ')
    r.data
end
recordtext(r)=nametext(r.owner)*" $(r.ttl) $(r.kind) "*datatext(r)
mutable struct Zone
    origin::Name
    server::Int
    line::Int
    records::Vector{Record}
end
atowner(z,n)=[r for r in z.records if r.owner==n]
findrecords(z,n,t)=dataorder([r for r in z.records if r.owner==n && r.kind==t])
exists(z,n)=any(r->below(r.owner,n),z.records)
soa(z)=z.records[findfirst(r->r.kind=="SOA",z.records)]
struct Response
    kind::String
    answer::Vector{Record}
    authority::Vector{Record}
    additional::Vector{Record}
    referral::Name
end
Response(k;answer=Record[],authority=Record[],additional=Record[],referral=ROOT)=Response(k,answer,authority,additional,referral)
response_summary(r)=r.kind=="REFERRAL" ? "REFERRAL "*nametext(r.referral) : r.kind=="CNAME" ? "CNAME "*nametext(r.answer[1].data) : r.kind
struct Entry
    kind::String
    records::Vector{Record}
    expiry::Int
end
mutable struct Resolver
    roots::Vector{Int}
    zones::Vector{Zone}
    current::Int
    down::Set{Int}
    clock::Int
    cache::Dict{Tuple{Name,String},Entry}
    settings::Dict{String,Int}
    queries::Dict{Int,Vector{Int}}
    hits::Int
    resolutions::Vector{Int}
end
Resolver()=Resolver(Int[],Zone[],0,Set{Int}(),0,Dict{Tuple{Name,String},Entry}(),Dict("MINTTL"=>1,"MAXTTL"=>86400,"NEGTTL"=>3600),Dict{Int,Vector{Int}}(),0,zeros(Int,4))
function zoneinput!(s,line,number)
    words=String.(split(line,' ')); command=words[1]
    if command=="ROOT"
        addresses=Int[]
        for word in words[2:end]
            n=ipv4(word); require(!(n in s.roots || n in addresses),"duplicate root $word"); push!(addresses,n)
        end
        append!(s.roots,addresses)
    elseif command=="ZONE"
        s.current=0; origin=parsename(words[2]); server=ipv4(words[3])
        require(!any(z->z.origin==origin && z.server==server,s.zones),"duplicate zone $(nametext(origin)) at $(words[3])")
        push!(s.zones,Zone(origin,server,number,Record[])); s.current=length(s.zones)
    else
        require(s.current!=0,"no current zone"); z=s.zones[s.current]; owner=parsename(words[1];wildcard=true,origin=z.origin)
        require(below(owner,z.origin),"out of zone $(nametext(owner))"); ttl=ttlword(words[2]); kind=words[3]; checktype(kind); fields=words[4:end]
        counts=Dict("A"=>1,"AAAA"=>1,"NS"=>1,"CNAME"=>1,"PTR"=>1,"MX"=>2,"SOA"=>7)
        require(!haskey(counts,kind) || length(fields)==counts[kind],"wrong field count")
        r=Record(owner,ttl,kind,parsedata(kind,fields,z.origin))
        require(!(kind=="NS" && !isempty(owner) && owner[1]=="*"),"ns at wildcard")
        require(kind!="SOA" || owner==z.origin,"soa not at origin")
        require(kind!="SOA" || !any(x->x.kind=="SOA",z.records),"duplicate soa")
        require(!any(x->samerecord(x,r),z.records),"duplicate record"); existing=atowner(z,owner)
        require(!((kind=="CNAME" && !isempty(existing)) || (kind!="CNAME" && any(x->x.kind=="CNAME",existing))),"cname conflict $(nametext(owner))")
        push!(z.records,r)
    end
end
function finishzones!(s)
    kept=Zone[]
    for z in s.zones
        label="zone $(nametext(z.origin)) at $(ip4text(z.server))"
        if any(r->r.kind=="SOA",z.records); println(label," records=$(length(z.records))"); push!(kept,z)
        else; println("error line $(z.line): $label has no soa"); end
    end
    s.zones=kept; println("loaded roots=$(length(s.roots)) zones=$(length(kept)) records=$(sum(z->length(z.records),kept;init=0))")
end
reachable(s,a)=!(a in s.down) && any(z->z.server==a,s.zones)
function dnsresponse(s,server,name,kind,cut)
    reachable(s,server) || return Response("TIMEOUT")
    candidates=[z for z in s.zones if z.server==server && below(name,z.origin)]
    isempty(candidates) && return Response("LAME")
    z=candidates[argmax(length(z.origin) for z in candidates)]
    length(z.origin)>=length(cut) || return Response("LAME")
    for n in length(z.origin)+1:length(name)
        point=name[length(name)-n+1:end]; ns=findrecords(z,point,"NS")
        if !isempty(ns)
            glue=Record[]; for r in ns; append!(glue,findrecords(z,r.data,"A")); end
            return Response("REFERRAL";authority=ns,additional=glue,referral=point)
        end
    end
    records=atowner(z,name)
    if isempty(records)
        exists(z,name) && return Response("NODATA";authority=[soa(z)])
        closest=first(a for a in ancestors(name)[2:end] if exists(z,a)); records=atowner(z,("*",closest...))
        isempty(records) && return Response("NXDOMAIN";authority=[soa(z)])
    end
    records=withowner.(records,Ref(name)); matching=dataorder([r for r in records if r.kind==kind])
    !isempty(matching) && return Response("ANSWER";answer=matching)
    cnames=[r for r in records if r.kind=="CNAME"]
    kind!="CNAME" && !isempty(cnames) && return Response("CNAME";answer=cnames)
    Response("NODATA";authority=[soa(z)])
end
function dnsask!(s,a,n,t,c)
    response=dnsresponse(s,a,n,t,c); counts=get!(()->zeros(Int,7),s.queries,a); counts[findfirst(==(response.kind),KINDS)]+=1; response
end
function positive!(s,records)
    ttl=min(max(minimum(r.ttl for r in records),s.settings["MINTTL"]),s.settings["MAXTTL"])
    first=records[1]; s.cache[(first.owner,first.kind)]=Entry("POS",dataorder(records),s.clock+ttl); ttl
end
function negative!(s,name,kind,r)
    soa=r.authority[1]; ttl=min(soa.ttl,soa.data[end],s.settings["NEGTTL"]); s.cache[(name,kind)]=Entry(r.kind,Record[],s.clock+ttl)
end
function positiveentry(s,name,kind)
    e=get(s.cache,(name,kind),nothing); e!==nothing && e.kind=="POS" ? e : nothing
end
aged(s,e)=[withttl(r,e.expiry-s.clock) for r in e.records]
trace(d,message)=println(repeat("  ",d+1),message)
function dnslookup!(s,name,kind,depth,pending)
    entry=get(s.cache,(name,kind),nothing); cached=nothing
    if entry!==nothing; cached=Response(entry.kind=="POS" ? "ANSWER" : entry.kind;answer=entry.kind=="POS" ? aged(s,entry) : Record[])
    elseif any(kv->kv.second.kind=="NXDOMAIN" && below(name,kv.first[1]),s.cache); cached=Response("NXDOMAIN")
    elseif kind!="CNAME"
        e=positiveentry(s,name,"CNAME"); e!==nothing && (cached=Response("CNAME";answer=aged(s,e)))
    end
    query=nametext(name)*" "*kind
    if cached!==nothing; s.hits+=1; trace(depth,"CACHE HIT $query -> $(response_summary(cached))"); return cached; end
    cut=ROOT; nameservers=nothing
    for ancestor in ancestors(name)
        e=positiveentry(s,ancestor,"NS")
        if e!==nothing; s.hits+=1; trace(depth,"CACHE HIT $query -> REFERRAL $(nametext(ancestor))"); cut=ancestor; nameservers=[r.data for r in e.records]; break; end
    end
    while true
        response=nothing
        hosts=nameservers===nothing ? [nothing] : sort(nameservers;by=namekey)
        for host in hosts
            addresses=Int[]
            if host===nothing; addresses=s.roots
            else
                e=positiveentry(s,host,"A")
                if e!==nothing; addresses=sort(unique([r.data for r in e.records]))
                elseif (host,"A") in pending; trace(depth,"GLUELESS $(nametext(host)) -> LOOP")
                else
                    trace(depth,"GLUELESS $(nametext(host))"); status,answer=dnsresolve!(s,host,"A",depth+1,pending)
                    status=="NOERROR" && (addresses=sort(unique([r.data for r in answer if r.kind=="A"])))
                end
            end
            for address in addresses
                r=dnsask!(s,address,name,kind,cut); trace(depth,"ASK $(ip4text(address)) $query -> $(response_summary(r))")
                if !(r.kind in ("LAME","TIMEOUT")); response=r; break; end
            end
            response!==nothing && break
        end
        response===nothing && return Response("SERVFAIL no server for "*nametext(cut))
        if response.kind=="REFERRAL"
            positive!(s,response.authority)
            owners=unique([r.owner for r in response.additional])
            for owner in owners; positive!(s,[r for r in response.additional if r.owner==owner]); end
            cut=response.referral; nameservers=[r.data for r in response.authority]
        elseif response.kind in ("ANSWER","CNAME")
            ttl=positive!(s,response.answer); return Response(response.kind;answer=[withttl(r,ttl) for r in response.answer])
        else; negative!(s,name,kind,response); return Response(response.kind); end
    end
end
function dnsresolve!(s,name,kind,depth=0,pending=Tuple{Name,String}[])
    pending=[pending;[(name,kind)]]; chain=Record[]; seen=Set{Name}([name]); current=name
    response=Response("")
    while true
        response=dnslookup!(s,current,kind,depth,pending)
        response.kind!="CNAME" && break
        append!(chain,response.answer); target=response.answer[1].data
        if target in seen; response=Response("SERVFAIL cname loop"); break; end
        if length(chain)==9; response=Response("SERVFAIL cname chain too long"); break; end
        push!(seen,target); current=target
    end
    status=response.kind=="ANSWER" ? "NOERROR" : response.kind
    answer=startswith(status,"SERVFAIL") ? Record[] : [chain;response.answer]
    label=startswith(status,"SERVFAIL") ? "SERVFAIL" : status; s.resolutions[findfirst(==(label),STATUSES)]+=1
    status,answer
end
function report!(s,name,kind)
    status,answer=dnsresolve!(s,name,kind)
    for r in answer; println("answer ",recordtext(r)); end
    println("status ",status); status,answer
end
function addressresolution!(s,host)
    addresses=String[]
    for kind in ("A","AAAA")
        status,answer=dnsresolve!(s,host,kind)
        status=="NOERROR" && append!(addresses,[datatext(r) for r in answer if r.kind==kind])
    end
    isempty(addresses) ? "no address" : join(addresses,' ')
end
function execute!(s,line)
    w=String.(split(line,' ')); command=w[1]
    if command in ("RESOLVE","MX")
        name=parsename(w[2];wildcard=true); kind=command=="MX" ? "MX" : w[3]; checktype(kind)
        println(command=="MX" ? "mx $(nametext(name))" : "resolve $(nametext(name)) $kind")
        status,answer=report!(s,name,kind)
        if command=="MX"
            if status=="NOERROR"
                for r in answer
                    r.kind=="MX" || continue; preference,host=r.data
                    println("exchange $preference $(nametext(host)) -> ",isempty(host) ? "null" : addressresolution!(s,host))
                end
            elseif status=="NODATA"
                host=isempty(answer) ? name : answer[end].data; addresses=addressresolution!(s,host); println("implicit $(nametext(host)) -> $addresses")
            end
        end
    elseif command=="REVERSE"
        if ':' in w[2]
            hextets=ipv6(w[2]); address=ip6text(hextets); digits=join(lpad(string(x;base=16),4,'0') for x in hextets); name=(string.(reverse(collect(digits)))...,"ip6","arpa")
        else; n=ipv4(w[2]); address=ip4text(n); name=(reverse(String.(split(address,'.')))...,"in-addr","arpa"); end
        println("reverse $address $(nametext(name))"); report!(s,name,"PTR")
    elseif command=="QUERY"
        address=ipv4(w[2]); name=parsename(w[3];wildcard=true); checktype(w[4]); response=dnsask!(s,address,name,w[4],ROOT)
        println("query $(ip4text(address)) $(nametext(name)) $(w[4]) -> $(response_summary(response))")
        for (label,records) in (("answer",response.answer),("authority",response.authority),("additional",response.additional)), r in records; println(label," ",recordtext(r)); end
    elseif command=="DUMP"
        address=ipv4(w[2]); name=parsename(w[3]); prefix="dump $(ip4text(address)) $(nametext(name))"
        if !reachable(s,address); println(prefix," -> TIMEOUT")
        else
            at=findfirst(z->z.server==address && z.origin==name,s.zones)
            if at===nothing; println(prefix," -> REFUSED")
            else; z=s.zones[at]; println(prefix," records=$(length(z.records))"); for r in sort(z.records;by=recordkey); println("  ",recordtext(r)); end; end
        end
    elseif command in ("DOWN","UP")
        address=ipv4(w[2]); require(command=="DOWN" ? !(address in s.down) : address in s.down,"server $(w[2]) "*(command=="DOWN" ? "already down" : "not down"))
        command=="DOWN" ? push!(s.down,address) : delete!(s.down,address); println(lowercase(command)," ",ip4text(address))
    elseif command=="SET"
        key=w[2]; require(haskey(s.settings,key),"bad setting $key"); require(integerword(w[3]) && 1<=parse(Int,w[3])<=604800,"bad value $(w[3])")
        value=parse(Int,w[3]); next=copy(s.settings); next[key]=value; require(next["MINTTL"]<=next["MAXTTL"],"minttl above maxttl"); s.settings=next; println("set $key=$value")
    elseif command=="TIME"
        require(integerword(w[2]) && 1<=parse(Int,w[2])<=1000000,"bad time $(w[2])"); s.clock+=parse(Int,w[2]); expired=[k for (k,e) in s.cache if e.expiry<=s.clock]
        for k in expired; delete!(s.cache,k); end
        println("time now=$(s.clock) expired=$(length(expired))")
    elseif command in ("CACHE","FLUSH")
        name=length(w)==1 ? nothing : parsename(w[2]); selected=[k for k in keys(s.cache) if name===nothing || below(k[1],name)]
        if command=="FLUSH"
            for k in selected; delete!(s.cache,k); end
            println("flush removed=$(length(selected))")
        else
            sort!(selected;by=k->(namekey(k[1]),findfirst(==(k[2]),TYPES))); println("cache entries=$(length(selected))")
            for k in selected
                e=s.cache[k]
                if e.kind=="POS"; for r in aged(s,e); println("  ",recordtext(r)); end
                else; println("  $(nametext(k[1])) $(e.expiry-s.clock) $(k[2]) $(e.kind)"); end
            end
        end
    elseif command=="STATS"
        println("stats queries=$(sum(x->sum(x),values(s.queries);init=0)) hits=$(s.hits)")
        for a in sort(collect(keys(s.queries)))
            counts=s.queries[a]; println("  $(ip4text(a)) sent=$(sum(counts)) ",join([lowercase(KINDS[i])*"=$(counts[i])" for i in 1:7],' '))
        end
        println("resolutions ",join([lowercase(STATUSES[i])*"=$(s.resolutions[i])" for i in 1:4],' '))
    end
end
function main()
    resolver=Resolver(); zones=true
    for (number,line) in enumerate(eachline())
        line=="END" && !zones && break
        if zones && line=="END ZONES"; finishzones!(resolver); zones=false; continue; end
        try; zones ? zoneinput!(resolver,line,number) : execute!(resolver,line)
        catch e; e isa InputError || rethrow(); println("error line $number: $(e.message)"); end
    end
end
main()
