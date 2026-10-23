const DROPS = split("down martian rpf invalid acl_in ttl noroute acl_out exhausted")
struct CommandError <: Exception
    message::String
end
fail(s)=throw(CommandError(s))
function decimal(s,maxdigits)
    1<=length(s)<=maxdigits && all(c->'0'<=c<='9',s) && (length(s)==1 || first(s)!='0') ? parse(Int,s) : nothing
end
function address(s)
    fields=split(s,'.';keepempty=true); length(fields)==4 || return nothing
    a=0
    for field in fields
        x=decimal(field,3); (x===nothing || x>255) && return nothing
        a=256a+x
    end
    a
end
function prefix(s)
    parts=split(s,'/';keepempty=true); length(parts)==2 || return nothing
    a=address(parts[1]); n=decimal(parts[2],2)
    a===nothing || n===nothing || n>32 ? nothing : (a,n)
end
network(a,n)=fld(a,2^(32-n))*2^(32-n)
inprefix(a,n,b)=network(a,n)==network(b,n)
ip(a)=join((mod(fld(a,2^k),256) for k in (24,16,8,0)),".")
cidr(a,n)="$(ip(a))/$n"
endpoint(a,p)="$(ip(a)):$p"
flowtext(t)="$(endpoint(t[2],t[3])) > $(endpoint(t[4],t[5]))"
function requireaddress(s)
    a=address(s); a===nothing && fail("bad address $s"); a
end
function requireprefix(s;acl=false)
    acl && s=="ANY" && return (0,0)
    p=prefix(s); p===nothing && fail("bad prefix $s")
    network(p...)==p[1] || fail("host bits set in $s"); p
end
function requireint(s,lo,hi,message)
    n=parse(Int,s); lo<=n<=hi || fail(message); n
end
function portrange(s)
    s=="ANY" && return (0,65535,"any")
    b=parse.(Int,split(s,'-')); lo=first(b); hi=last(b)
    lo<=hi<=65535 || fail("bad port range $s")
    lo,hi,lo==hi ? string(lo) : "$lo-$hi"
end
mutable struct Rule
    seq::Int
    action::String
    proto::String
    src::Tuple{Int,Int}
    sports::Tuple{Int,Int,String}
    dst::Tuple{Int,Int}
    dports::Tuple{Int,Int,String}
    established::Bool
    hits::Int
end
mutable struct Pat
    proto::String
    inside::Int
    inport::Int
    port::Int
    used::Int
end
mutable struct Interface
    name::String
    addr::Int
    length::Int
    up::Bool
    outside::Bool
    pool::Int
    rpf::String
    rx::Int
    tx::Int
    drop::Int
    rules::Dict{String,Vector{Rule}}
    defaults::Dict{String,Int}
    pat::Vector{Pat}
end
Interface(n,a,l)=Interface(n,a,l,true,false,0,"off",0,0,0,Dict("in"=>Rule[],"out"=>Rule[]),Dict("in"=>0,"out"=>0),Pat[])
mutable struct Route
    kind::String
    addr::Int
    length::Int
    iface::Interface
    hop::Union{Nothing,Int}
    metric::Int
    hits::Int
end
notation(r)="$(r.kind) $(cidr(r.addr,r.length))"*(r.hop===nothing ? "" : " via $(ip(r.hop))")*" dev $(r.iface.name) metric $(r.metric)"
struct Forward
    iface::Interface
    proto::String
    port::Int
    inside::Int
    inport::Int
end
const Flow=Tuple{String,Int,Int,Int,Int}
mutable struct Connection
    number::Int
    orig::Flow
    reply::Flow
    inbound::Interface
    outbound::Interface
    state::String
    origcount::Int
    replycount::Int
    used::Int
    origfin::Bool
    replyfin::Bool
end
mutable struct Router
    interfaces::Vector{Interface}
    routes::Vector{Route}
    statics::Vector{Tuple{Int,Int}}
    forwards::Vector{Forward}
    conns::Vector{Connection}
    timeouts::Dict{String,Int}
    clock::Int
    packets::Int
    serial::Int
    counts::Dict{String,Int}
    errors::Int
end
Router()=Router(Interface[],Route[],Tuple{Int,Int}[],Forward[],Connection[],Dict("TCP"=>300,"UDP"=>60,"ICMP"=>30),0,0,0,Dict(k=>0 for k in [DROPS;["forwarded","local"]]),0)
function iface(r,name)
    n=findfirst(i->i.name==name,r.interfaces); n===nothing && fail("no interface $name"); r.interfaces[n]
end
localiface(r,a)=findfirst(i->i.addr==a,r.interfaces)
function selectroute(r,a)
    best=nothing
    for route in r.routes
        route.iface.up && inprefix(route.addr,route.length,a) || continue
        if best===nothing || route.length>best.length || route.length==best.length && route.metric<best.metric; best=route; end
    end
    best
end
function evaluate!(i,d,t,established)
    isempty(i.rules[d]) && return nothing
    p,s,sp,dst,dp=t
    for rule in i.rules[d]
        rule.proto in ("ANY",p) && inprefix(rule.src...,s) && inprefix(rule.dst...,dst) || continue
        rule.proto in ("TCP","UDP") && !(rule.sports[1]<=sp<=rule.sports[2] && rule.dports[1]<=dp<=rule.dports[2]) && continue
        rule.established && !established && continue
        rule.hits+=1; label="acl $(i.name) $d $(rule.seq)"
        return rule.action=="PERMIT" ? nothing : rule.action=="DENY" ? "DROP $label" : "REJECT $label "*(p=="TCP" ? "tcp-reset" : "icmp-prohibited")
    end
    i.defaults[d]+=1; "DROP acl $(i.name) $d default"
end
function record!(c,d,flags,clock)
    d=="reply" ? (c.replycount+=1) : (c.origcount+=1); c.used=clock
    if c.orig[1]!="TCP"
        d=="reply" && (c.state="REPLIED")
    elseif occursin('R',flags); c.state="CLOSED"
    else
        c.state=="SYN_SENT" && d=="reply" && occursin('S',flags) && occursin('A',flags) && (c.state="ESTABLISHED")
        if occursin('F',flags) && c.state in ("ESTABLISHED","FIN_WAIT")
            d=="reply" ? (c.replyfin=true) : (c.origfin=true)
            c.state=c.origfin && c.replyfin ? "CLOSED" : "FIN_WAIT"
        end
    end
end
function process!(r,i,p,flags,s,sp,d,dp,ttl)
    !i.up && return "down","DROP down"
    if any(x->inprefix(x[1],x[2],s) || inprefix(x[1],x[2],d),((0,8),(2130706432,8),(3758096384,3))) || localiface(r,s)!==nothing
        return "martian","DROP martian"
    end
    if i.rpf!="off"
        route=selectroute(r,s)
        (route===nothing || i.rpf=="strict" && route.iface!==i) && return "rpf","DROP rpf"
    end
    t=(p,s,sp,d,dp); pure=p=="TCP" && flags=="S"; c=nothing; direction=""
    for (j,conn) in enumerate(r.conns)
        dir=conn.orig==t ? "orig" : conn.reply==t ? "reply" : ""
        isempty(dir) && continue
        if conn.state=="CLOSED" && pure; deleteat!(r.conns,j)
        else; c=conn; direction=dir; end
        break
    end
    p=="TCP" && c===nothing && !pure && return "invalid","DROP invalid"
    verdict=evaluate!(i,"in",t,c!==nothing); verdict!==nothing && return "acl_in",verdict
    nd=d; np=dp; used=nothing
    if i.outside
        st=findfirst(x->x[2]==d,r.statics)
        if st!==nothing; nd=r.statics[st][1]
        elseif d==i.addr
            f=findfirst(x->x.iface===i && x.proto==p && x.port==dp,r.forwards)
            m=findfirst(x->x.proto==p && x.port==dp,i.pat)
            if f!==nothing; nd=r.forwards[f].inside; np=r.forwards[f].inport
            elseif m!==nothing; used=i.pat[m]; nd=used.inside; np=used.inport; end
        end
    end
    loc=localiface(r,nd); loc!==nothing && return "local","LOCAL $(r.interfaces[loc].name)"
    ttl==1 && return "ttl","DROP ttl"
    route=selectroute(r,nd); route===nothing && return "noroute","DROP noroute"
    o=route.iface; verdict=evaluate!(o,"out",(p,s,sp,nd,np),c!==nothing)
    verdict!==nothing && return "acl_out",verdict
    ns=s; nsp=sp
    if !i.outside && o.outside
        st=findfirst(x->x[1]==s,r.statics)
        f=findfirst(x->x.iface===o && x.proto==p && x.inside==s && x.inport==sp,r.forwards)
        if st!==nothing; ns=r.statics[st][2]
        elseif f!==nothing; ns=o.addr; nsp=r.forwards[f].port
        elseif o.pool>0
            m=findfirst(x->x.proto==p && x.inside==s && x.inport==sp,o.pat)
            if m===nothing
                port=findfirst(x->!any(y->y.port==x,o.pat) && !any(y->y.iface===o && y.port==x,r.forwards),20000:19999+o.pool)
                port===nothing && return "exhausted","DROP exhausted"
                used=Pat(p,s,sp,19999+port,r.clock); push!(o.pat,used)
            else; used=o.pat[m]; end
            ns=o.addr; nsp=used.port
        end
    end
    used!==nothing && (used.used=r.clock)
    if c===nothing
        r.serial+=1; c=Connection(r.serial,t,(p,nd,np,ns,nsp),i,o,p=="TCP" ? "SYN_SENT" : "UNREPLIED",0,0,r.clock,false,false)
        push!(r.conns,c); direction="new"
    end
    record!(c,direction,flags,r.clock); o.tx+=1; route.hits+=1
    verdict="FORWARD $(o.name) "*(route.hop===nothing ? "direct" : "via $(ip(route.hop))")*" ttl=$(ttl-1)"
    (nd,np)!=(d,dp) && (verdict*=" dnat=$(endpoint(nd,np))")
    (ns,nsp)!=(s,sp) && (verdict*=" snat=$(endpoint(ns,nsp))")
    "forwarded",verdict*" conn=$(c.number) $direction"
end
aclprefix(p)=p[2]==0 ? "any" : cidr(p...)
function showstate(r,what)
    interfaces=sort(r.interfaces;by=i->i.name)
    if what=="IFACES"
        println("show ifaces count=$(length(interfaces))")
        for i in interfaces
            println("$(i.name) $(cidr(i.addr,i.length)) $(i.up ? "up" : "down") $(i.outside ? "outside" : "inside") rpf=$(i.rpf)",i.pool>0 ? " pat=$(length(i.pat))/$(i.pool)" : "")
        end
    elseif what=="ROUTES"
        println("show routes count=$(length(r.routes))")
        for route in sort(r.routes;by=x->(x.addr,x.length,x.metric),alg=Base.Sort.MergeSort)
            println(notation(route)," hits=$(route.hits)",route.iface.up ? "" : " inactive")
        end
    elseif what=="ACL"
        println("show acl count=$(sum(length(i.rules[d]) for i in interfaces for d in ("in","out");init=0))")
        for i in interfaces, d in ("in","out")
            isempty(i.rules[d]) && continue
            for rule in i.rules[d]
                println("acl $(i.name) $d $(rule.seq) $(rule.action) $(rule.proto) $(aclprefix(rule.src)) $(rule.sports[3]) $(aclprefix(rule.dst)) $(rule.dports[3])",rule.established ? " established" : ""," hits=$(rule.hits)")
            end
            println("acl $(i.name) $d default DENY hits=$(i.defaults[d])")
        end
    elseif what=="NAT"
        println("show nat static=$(length(r.statics)) forward=$(length(r.forwards)) pat=$(sum(length(i.pat) for i in interfaces;init=0))")
        for (a,b) in sort(r.statics;by=first); println("static $(ip(a)) $(ip(b))"); end
        for f in sort(r.forwards;by=x->(x.iface.name,x.port,x.proto)); println("forward $(f.iface.name) $(f.proto) $(f.port) $(endpoint(f.inside,f.inport))"); end
        for i in interfaces, m in sort(i.pat;by=x->x.port); println("pat $(i.name) $(m.port) $(m.proto) $(endpoint(m.inside,m.inport)) idle=$(r.clock-m.used)"); end
    elseif what=="CONNS"
        println("show conns count=$(length(r.conns))")
        for c in r.conns
            println("conn $(c.number) $(c.orig[1]) $(flowtext(c.orig)) reply $(flowtext(c.reply)) in=$(c.inbound.name) out=$(c.outbound.name) state=$(c.state) pkts=$(c.origcount)/$(c.replycount) idle=$(r.clock-c.used)")
        end
    else
        dropped=sum(r.counts[k] for k in DROPS); forwarded=r.counts["forwarded"]; localcount=r.counts["local"]
        println("show counters packets=$(forwarded+localcount+dropped) forwarded=$forwarded local=$localcount dropped=$dropped errors=$(r.errors)")
        println("drops ",join(("$k=$(r.counts[k])" for k in DROPS)," "))
        for i in interfaces; println("iface $(i.name) rx=$(i.rx) tx=$(i.tx) drop=$(i.drop)"); end
    end
end
function execute!(r,line)
    words=String.(split(line)); cmd=words[1]; a=words[2:end]
    if cmd=="IFACE"
        name,word=a; any(i->i.name==name,r.interfaces) && fail("duplicate interface $name")
        p=prefix(word); (p===nothing || !(8<=p[2]<=30)) && fail("bad prefix $word")
        addr,len=p; host=addr-network(addr,len); host in (0,2^(32-len)-1) && fail("bad host address $word")
        for i in r.interfaces; inprefix(i.addr,min(len,i.length),addr) && fail("subnet overlaps $(i.name)"); end
        i=Interface(name,addr,len); push!(r.interfaces,i); push!(r.routes,Route("C",network(addr,len),len,i,nothing,0,0))
        println("ok iface $name $word network $(cidr(network(addr,len),len))")
    elseif cmd in ("UP","DOWN")
        i=iface(r,a[1]); state=cmd=="UP"; word=lowercase(cmd)
        i.up==state && fail("interface $(i.name) already $word"); i.up=state; println("ok $word $(i.name)")
    elseif cmd=="ROUTE"
        word,mode,target,m=a; addr,len=requireprefix(word); hop=nothing; i=nothing
        if mode=="VIA"; hop=requireaddress(target); else; i=iface(r,target); end
        metric=requireint(m,1,255,"bad metric $m")
        if mode=="VIA"
            localiface(r,hop)!==nothing && fail("nexthop $target is local")
            idx=findfirst(x->inprefix(x.addr,x.length,hop),r.interfaces)
            idx===nothing && fail("nexthop $target unreachable"); i=r.interfaces[idx]
        end
        any(x->x.kind=="S" && x.addr==addr && x.length==len && x.iface===i && x.hop==hop,r.routes) && fail("duplicate route $word")
        route=Route("S",addr,len,i,hop,metric,0); push!(r.routes,route); println("ok route ",notation(route))
    elseif cmd=="NOROUTE"
        addr,len=requireprefix(a[1]); removed=count(x->x.kind=="S" && x.addr==addr && x.length==len,r.routes)
        removed==0 && fail("no static route $(a[1])")
        filter!(x->!(x.kind=="S" && x.addr==addr && x.length==len),r.routes); println("ok noroute $(a[1]) removed=$removed")
    elseif cmd=="LOOKUP"
        route=selectroute(r,requireaddress(a[1])); println("lookup $(a[1]) ",route===nothing ? "none" : notation(route))
    elseif cmd=="ACL"
        name,d,seq,action,p,src,sports,dst,dports=a[1:9]; i=iface(r,name); n=requireint(seq,1,9999,"bad sequence $seq")
        s=requireprefix(src;acl=true); sp=portrange(sports); dest=requireprefix(dst;acl=true); dp=portrange(dports)
        p in ("ICMP","ANY") && (sports!="ANY" || dports!="ANY") && fail("ports not allowed for $p")
        dir=lowercase(d); any(x->x.seq==n,i.rules[dir]) && fail("duplicate sequence $seq")
        push!(i.rules[dir],Rule(n,action,p,s,sp,dest,dp,last(a)=="ESTABLISHED",0)); sort!(i.rules[dir];by=x->x.seq)
        println("ok acl $name $dir $seq")
    elseif cmd=="NOACL"
        name,d,seq=a; i=iface(r,name); dir=lowercase(d); n=parse(Int,seq); idx=findfirst(x->x.seq==n,i.rules[dir])
        idx===nothing && fail("no rule $seq on $name $dir")
        hits=i.rules[dir][idx].hits; deleteat!(i.rules[dir],idx); println("ok noacl $name $dir $seq hits=$hits")
    elseif cmd=="NAT"
        kind=a[1]; a=a[2:end]
        if kind=="STATIC"
            x,y=a; inside=requireaddress(x); outside=requireaddress(y)
            for (addr,word) in ((inside,x),(outside,y)); localiface(r,addr)!==nothing && fail("address $word is local"); end
            any(s->s[1]==inside,r.statics) && fail("duplicate static $x")
            any(s->s[2]==outside,r.statics) && fail("duplicate static $y")
            push!(r.statics,(inside,outside)); println("ok nat static $x $y")
        elseif kind=="OUTSIDE"
            i=iface(r,a[1]); i.outside && fail("interface $(i.name) already outside"); i.outside=true; println("ok nat outside $(i.name)")
        elseif kind=="PAT"
            name,word=a; i=iface(r,name); n=requireint(word,1,1000,"bad pool size $word")
            i.pool>0 && fail("pat already on $name"); i.pool=n; i.outside=true; println("ok nat pat $name $(ip(i.addr)) 20000-$(19999+n)")
        else
            name,p,word,insideword,inword=a; i=iface(r,name); port=requireint(word,1,65535,"bad port $word"); inside=requireaddress(insideword); inport=requireint(inword,1,65535,"bad port $inword")
            i.outside || fail("interface $name not outside"); localiface(r,inside)!==nothing && fail("address $insideword is local")
            any(f->f.iface===i && f.proto==p && f.port==port,r.forwards) && fail("duplicate forward $name $p $word")
            push!(r.forwards,Forward(i,p,port,inside,inport)); println("ok nat forward $name $p $word $insideword:$inword")
        end
    elseif cmd=="RPF"
        i=iface(r,a[1]); i.rpf=lowercase(a[2]); println("ok rpf $(i.name) $(i.rpf)")
    elseif cmd=="TIMEOUT"
        p,word=a; r.timeouts[p]=requireint(word,1,86400,"bad timeout $word"); println("ok timeout $p $word")
    elseif cmd=="TICK"
        word=a[1]; r.clock+=requireint(word,1,86400,"bad tick $word"); nc=length(r.conns); nm=sum(length(i.pat) for i in r.interfaces;init=0)
        filter!(c->r.clock-c.used < (c.orig[1]!="TCP" || c.state=="ESTABLISHED" ? r.timeouts[c.orig[1]] : c.state=="CLOSED" ? 10 : 60),r.conns)
        for i in r.interfaces; filter!(m->r.clock-m.used<r.timeouts[m.proto],i.pat); end
        println("ok tick time=$(r.clock) expired conns=$(nc-length(r.conns)) nat=$(nm-sum(length(i.pat) for i in r.interfaces;init=0))")
    elseif cmd=="PACKET"
        name,p,flags,sw,spw,dw,dpw,tw=a; i=iface(r,name)
        p!="TCP" && flags!="-" && fail("flags not allowed for $p")
        p=="TCP" && flags!="-" && (!all(c->c in "SAFR",flags) || length(unique(flags))!=length(flags)) && fail("bad flags $flags")
        s=requireaddress(sw); sp=requireint(spw,0,65535,"bad port $spw"); d=requireaddress(dw); dp=requireint(dpw,0,65535,"bad port $dpw"); ttl=requireint(tw,1,255,"bad ttl $tw")
        r.packets+=1; i.rx+=1; reason,verdict=process!(r,i,p,flags=="-" ? "" : flags,s,sp,d,dp,ttl)
        r.counts[reason]+=1; reason in DROPS && (i.drop+=1)
        println("#$(r.packets) $p $flags $sw:$spw > $dw:$dpw $verdict")
    elseif cmd=="SHOW"; showstate(r,a[1])
    elseif a[1]=="COUNTERS"
        for k in keys(r.counts); r.counts[k]=0; end; r.errors=0
        for i in r.interfaces
            i.rx=i.tx=i.drop=0
            for d in ("in","out"); i.defaults[d]=0; for rule in i.rules[d]; rule.hits=0; end; end
        end
        for route in r.routes; route.hits=0; end
        println("ok clear counters")
    else
        nc=length(r.conns); nm=sum(length(i.pat) for i in r.interfaces;init=0); empty!(r.conns)
        for i in r.interfaces; empty!(i.pat); end; println("ok clear conns=$nc nat=$nm")
    end
end
function main()
    r=Router(); n=parse(Int,readline())
    for _ in 1:n
        line=readline()
        try; execute!(r,line)
        catch e
            e isa CommandError || rethrow(); r.errors+=1; println("error: $(e.message)")
        end
    end
end
main()
