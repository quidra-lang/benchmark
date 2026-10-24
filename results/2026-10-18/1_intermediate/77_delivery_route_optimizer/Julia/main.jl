struct CommandError <: Exception
    message::String
end
fail(s)=throw(CommandError(s))
check(b,s)=b ? nothing : fail(s)
parsetime(s)=60parse(Int,s[1:2])+parse(Int,s[4:5])
timetext(t)=lpad(string(div(t,60)),2,'0')*":"*lpad(string(t%60),2,'0')
placename(i)=i==0 ? "D" : string(i)
notation(path)=join(["D";string.(path);"D"],'-')
tenths(i)="$(div(i,10)).$(i%10)"
struct Stop
    x::Int
    y::Int
    demand::Int
    service::Int
    opening::Int
    closing::Int
end
mutable struct Workbench
    depot::Union{Nothing,Tuple{Int,Int}}
    start::Int
    stops::Dict{Int,Stop}
    tour::Union{Nothing,Vector{Int}}
    routes::Union{Nothing,Vector{Vector{Int}}}
    capacity::Int
end
Workbench()=Workbench(nothing,480,Dict{Int,Stop}(),nothing,nothing,0)
stopids(w)=sort!(collect(keys(w.stops)))
coordinates(w,i)=i==0 ? w.depot : (w.stops[i].x,w.stops[i].y)
function distance(w,a,b)
    x,y=coordinates(w,a); u,v=coordinates(w,b); abs(x-u)+abs(y-v)
end
function pathlength(w,path)
    route=[0;path;0]; sum(distance(w,route[i],route[i+1]) for i in 1:length(route)-1)
end
pathload(w,path)=sum((w.stops[i].demand for i in path);init=0)
planlength(w)=sum(pathlength(w,path) for path in w.routes)
function normalize!(w)
    routes=[copy(path) for path in w.routes if !isempty(path)]
    for path in routes; first(path)>last(path) && reverse!(path); end
    sort!(routes;by=minimum); w.routes=routes
end
function requiredepot(w); check(w.depot!==nothing,"no depot"); end
function requirestops(w); check(!isempty(w.stops),"no stops"); end
function requiretour(w); check(w.tour!==nothing,"no tour"); end
function requireplan(w); check(w.routes!==nothing,"no plan"); end
function requirecapacity(w,q)
    for id in stopids(w); check(w.stops[id].demand<=q,"stop $id demand $(w.stops[id].demand) exceeds capacity $q"); end
end
function installtour!(w,label,path)
    w.tour=path; println("$label: $(notation(path)) length $(pathlength(w,path))")
end
function planreport(w,heading)
    println("$heading, routes $(length(w.routes)), length $(planlength(w))")
    for (r,path) in enumerate(w.routes); println("route $r: $(notation(path)) load $(pathload(w,path)) length $(pathlength(w,path))"); end
end
function simulate(w,path)
    visits=NTuple{6,Int}[]; timestamp=w.start; previous=0; waiting=0; service=0; violations=0; lateness=0
    for id in path
        stop=w.stops[id]; arrival=timestamp+distance(w,previous,id); wait=stop.opening<0 ? 0 : max(0,stop.opening-arrival); late=stop.closing<0 ? 0 : max(0,arrival-stop.closing); beginning=arrival+wait; timestamp=beginning+stop.service
        push!(visits,(id,arrival,wait,beginning,timestamp,late)); waiting+=wait; service+=stop.service; violations+=late>0; lateness+=late; previous=id
    end
    (visits=visits,finish=timestamp+distance(w,previous,0),travel=pathlength(w,path),wait=waiting,service=service,violations=violations,lateness=lateness)
end
function firstreversal(w,path)
    around=[0;path;0]
    for i in 1:length(path)-1, j in i+1:length(path)
        gain=distance(w,around[i],around[i+1])+distance(w,around[j+1],around[j+2])-distance(w,around[i],around[j+1])-distance(w,around[i+1],around[j+2]); gain>0 && return (i,j,gain)
    end
    nothing
end
function twoopt!(w,path;display=true)
    moves=0
    while true
        move=firstreversal(w,path); move===nothing && break; i,j,gain=move; display && println("reverse $(path[i])..$(path[j]) gain $gain"); path[i:j]=reverse(path[i:j]); moves+=1
    end
    moves
end
function firstsegment(w,path)
    n=length(path); around=[0;path;0]
    for size in 1:3, i in 1:n-size+1
        rest=[path[1:i-1];path[i+size:end]]; remaining=[0;rest;0]; firstid=path[i]; lastid=path[i+size-1]; removal=distance(w,around[i],firstid)+distance(w,lastid,around[i+size+1])-distance(w,around[i],around[i+size+1])
        for j in 0:length(rest)
            j==i-1 && continue; gain=removal-distance(w,remaining[j+1],firstid)-distance(w,lastid,remaining[j+2])+distance(w,remaining[j+1],remaining[j+2]); gain>0 && return (i,size,j,gain)
        end
    end
    nothing
end
function firstswap(w,path)
    before=pathlength(w,path)
    for i in 1:length(path)-1, j in i+1:length(path)
        changed=copy(path); changed[i],changed[j]=changed[j],changed[i]; gain=before-pathlength(w,changed); gain>0 && return (i,j,gain)
    end
    nothing
end
function exacttour(w)
    ids=stopids(w); n=length(ids); full=(1<<n)-1; costs=zeros(Int,full+1,n)
    for i in 1:n; costs[1,i]=distance(w,ids[i],0); end
    for mask in 1:full-1, i in 1:n
        (mask & (1<<(i-1)))!=0 && continue
        costs[mask+1,i]=minimum(distance(w,ids[i],ids[j])+costs[(mask ⊻ (1<<(j-1)))+1,j] for j in 1:n if (mask & (1<<(j-1)))!=0)
    end
    cost=minimum(distance(w,0,ids[i])+costs[(full ⊻ (1<<(i-1)))+1,i] for i in 1:n); path=Int[]; current=0; mask=full
    while mask!=0
        choice=first(i for i in 1:n if (mask & (1<<(i-1)))!=0 && distance(w,current,ids[i])+costs[(mask ⊻ (1<<(i-1)))+1,i]==cost)
        mask ⊻=1<<(choice-1); cost=costs[mask+1,choice]; current=ids[choice]; push!(path,current)
    end
    path
end
function spanningtree(w,vertices)
    tree=vertices[1:1]; remaining=vertices[2:end]; edges=NTuple{3,Int}[]
    while !isempty(remaining)
        weight,child,at=minimum((distance(w,parent,child),child,at) for child in remaining for (at,parent) in enumerate(tree)); parent=tree[at]; push!(edges,(parent,child,weight)); push!(tree,child); filter!(!=(child),remaining)
    end
    edges
end
function sweeporder(w)
    function less(a,b)
        x,y=coordinates(w,a).-w.depot; u,v=coordinates(w,b).-w.depot
        az=x==0 && y==0; bz=u==0 && v==0
        az!=bz && return az; az && return a<b
        ah=(y>0 || (y==0 && x>0)) ? 0 : 1; bh=(v>0 || (v==0 && u>0)) ? 0 : 1; ah!=bh && return ah<bh
        cross=x*v-y*u; cross!=0 && return cross>0; d=abs(x)+abs(y); e=abs(u)+abs(v); d!=e ? d<e : a<b
    end
    sort!(stopids(w);lt=less)
end
function savings!(w,q,limit)
    ids=stopids(w)
    if limit!==nothing; for id in ids; check(2distance(w,0,id)<=limit,"stop $id too far for limit $limit"); end; end
    pairs=Tuple{Int,Int,Int}[]
    for (i,a) in enumerate(ids), b in ids[i+1:end]; saving=distance(w,0,a)+distance(w,0,b)-distance(w,a,b); saving>0 && push!(pairs,(-saving,a,b)); end
    sort!(pairs); routes=[[id] for id in ids]; merges=0
    for (_,a,b) in pairs
        r=findfirst(path->a in path,routes); t=findfirst(path->b in path,routes); r==t && continue; firstpath=routes[r]; secondpath=routes[t]
        a in (first(firstpath),last(firstpath)) && b in (first(secondpath),last(secondpath)) || continue
        pathload(w,firstpath)+pathload(w,secondpath)<=q || continue
        merged=[first(firstpath)==a ? reverse(firstpath) : firstpath;last(secondpath)==b ? reverse(secondpath) : secondpath]
        limit!==nothing && pathlength(w,merged)>limit && continue
        routes=[path for (i,path) in enumerate(routes) if i!=r && i!=t]; push!(routes,merged); merges+=1
    end
    w.capacity=q; w.routes=routes; normalize!(w); planreport(w,"vrp: capacity $q, merges $merges")
end
function splitplan!(w,q)
    path=w.tour; n=length(path); best=fill(typemax(Int),n+1); best[1]=0; previous=zeros(Int,n+1)
    for j in 1:n, i in 0:j-1
        segment=path[i+1:j]; pathload(w,segment)>q && continue; cost=best[i+1]+pathlength(w,segment)
        if cost<best[j+1]; best[j+1]=cost; previous[j+1]=i; end
    end
    routes=Vector{Int}[]; j=n
    while j>0; i=previous[j+1]; push!(routes,path[i+1:j]); j=i; end
    w.capacity=q; w.routes=routes; normalize!(w); planreport(w,"split: capacity $q")
end
function firstrelocation(w)
    routes=w.routes
    for (r,source) in enumerate(routes)
        around=[0;source;0]
        for (p,id) in enumerate(source), (t,target) in enumerate(routes)
            t==r && continue; pathload(w,target)+w.stops[id].demand<=w.capacity || continue; near=[0;target;0]
            removal=distance(w,around[p],id)+distance(w,id,around[p+2])-distance(w,around[p],around[p+2])
            for j in 0:length(target)
                gain=removal-distance(w,near[j+1],id)-distance(w,id,near[j+2])+distance(w,near[j+1],near[j+2]); gain>0 && return (r,p,t,j,gain)
            end
        end
    end
    nothing
end
function firstexchange(w)
    for r in 1:length(w.routes)-1, t in r+1:length(w.routes)
        a=w.routes[r]; b=w.routes[t]; total=pathlength(w,a)+pathlength(w,b)
        for p in eachindex(a), j in eachindex(b)
            shift=w.stops[b[j]].demand-w.stops[a[p]].demand; pathload(w,a)+shift<=w.capacity && pathload(w,b)-shift<=w.capacity || continue
            firstpath=copy(a); secondpath=copy(b); firstpath[p]=b[j]; secondpath[j]=a[p]; gain=total-pathlength(w,firstpath)-pathlength(w,secondpath); gain>0 && return (r,p,t,j,gain)
        end
    end
    nothing
end
function firstcross(w)
    for r in 1:length(w.routes)-1, t in r+1:length(w.routes)
        a=w.routes[r]; b=w.routes[t]; arounda=[0;a;0]; aroundb=[0;b;0]
        for i in 0:length(a), j in 0:length(b)
            pathload(w,[a[1:i];b[j+1:end]])<=w.capacity && pathload(w,[b[1:j];a[i+1:end]])<=w.capacity || continue
            gain=distance(w,arounda[i+1],arounda[i+2])+distance(w,aroundb[j+1],aroundb[j+2])-distance(w,arounda[i+1],aroundb[j+2])-distance(w,aroundb[j+1],arounda[i+2]); gain>0 && return (r,i,t,j,gain)
        end
    end
    nothing
end
function improveplan!(w,kind)
    before=planlength(w); countbefore=length(w.routes); moves=0
    while true
        move=kind=="RELOCATE" ? firstrelocation(w) : kind=="EXCHANGE" ? firstexchange(w) : firstcross(w); move===nothing && break; r,p,t,j,gain=move
        if kind=="RELOCATE"
            id=w.routes[r][p]; after=j==0 ? "D" : string(w.routes[t][j]); println("relocate $id from route $r to route $t after $after gain $gain"); deleteat!(w.routes[r],p); insert!(w.routes[t],j+1,id)
        elseif kind=="EXCHANGE"
            a=w.routes[r][p]; b=w.routes[t][j]; println("exchange $a (route $r) with $b (route $t) gain $gain"); w.routes[r][p]=b; w.routes[t][j]=a
        else
            a=w.routes[r]; b=w.routes[t]; println("cross route $r after $(p==0 ? "D" : string(a[p])) with route $t after $(j==0 ? "D" : string(b[j])) gain $gain"); w.routes[r]=[a[1:p];b[j+1:end]]; w.routes[t]=[b[1:j];a[p+1:end]]
        end
        normalize!(w); moves+=1
    end
    counts=kind=="EXCHANGE" ? "" : "routes $countbefore -> $(length(w.routes)), "; println("$(lowercase(kind)): moves $moves, $(counts)length $before -> $(planlength(w))")
end
function execute!(w,line)
    parts=String.(split(line,' ')); command=parts[1]; args=parts[2:end]
    if command=="DEPOT"; x,y=parse.(Int,args); w.depot=(x,y); println("depot at ($x,$y)")
    elseif command=="START"; w.start=parsetime(args[1]); println("start $(timetext(w.start))")
    elseif command=="STOP"
        id,x,y,demand,service=parse.(Int,args[1:5]); check(!haskey(w.stops,id),"stop $id already exists"); opening=-1; closing=-1
        if length(args)==7; opening=parsetime(args[6]); closing=parsetime(args[7]); check(opening<=closing,"invalid window"); end
        w.stops[id]=Stop(x,y,demand,service,opening,closing); w.tour=nothing; w.routes=nothing; println("stop $id added")
    elseif command=="REMOVE"
        id=parse(Int,args[1]); check(haskey(w.stops,id),"unknown stop $id"); delete!(w.stops,id)
        w.tour!==nothing && filter!(!=(id),w.tour)
        if w.routes!==nothing; for path in w.routes; filter!(!=(id),path); end; normalize!(w); end
        if isempty(w.stops); w.tour=nothing; w.routes=nothing; end; println("stop $id removed")
    elseif command=="LIST"
        println(w.depot===nothing ? "depot none" : "depot ($(w.depot[1]),$(w.depot[2]))"); println("start $(timetext(w.start))\nstops $(length(w.stops))")
        for id in stopids(w); stop=w.stops[id]; window=stop.opening<0 ? "none" : timetext(stop.opening)*"-"*timetext(stop.closing); println("$id at ($(stop.x),$(stop.y)) demand $(stop.demand) service $(stop.service) window $window"); end
    elseif command=="MATRIX"
        requiredepot(w); ids=[0;stopids(w)]; table=[[placename(id);[string(distance(w,id,other)) for other in ids]] for id in ids]; header=placename.(ids); width=maximum(length,[header;reduce(vcat,table)]); println(join([repeat(" ",width);lpad.(header,width)],' ')); for row in table; println(join(lpad.(row,width),' ')); end
    elseif command in ("ORDER","NEAREST","INSERTION","EXACT","BOUND","VRP","SWEEP")
        requiredepot(w); requirestops(w)
        if command=="ORDER"
            path=parse.(Int,args); for id in path; check(haskey(w.stops,id),"unknown stop $id"); end
            seen=Set{Int}(); for id in path; check(!(id in seen),"duplicate stop $id"); push!(seen,id); end
            check(length(path)==length(w.stops),"order has $(length(path)) stops, expected $(length(w.stops))"); installtour!(w,"order",path)
        elseif command=="NEAREST"
            remaining=stopids(w); path=Int[]; current=0
            while !isempty(remaining); chosen=remaining[argmin([(distance(w,current,id),id) for id in remaining])]; push!(path,chosen); filter!(!=(chosen),remaining); current=chosen; end
            installtour!(w,"nearest",path)
        elseif command=="INSERTION"
            remaining=stopids(w); path=Int[]
            while !isempty(remaining)
                around=[0;path;0]; _,id,j=minimum((distance(w,around[j+1],id)+distance(w,id,around[j+2])-distance(w,around[j+1],around[j+2]),id,j) for id in remaining for j in 0:length(path)); insert!(path,j+1,id); filter!(!=(id),remaining)
            end
            installtour!(w,"insertion",path)
        elseif command=="EXACT"; check(length(w.stops)<=10,"too many stops for exact ($(length(w.stops)))"); installtour!(w,"exact",exacttour(w))
        elseif command=="BOUND"
            ids=stopids(w); edges=spanningtree(w,[0;ids]); mst=sum(e[3] for e in edges); println("mst: ",join(["$(placename(a))-$b" for (a,b,_) in edges],' ')," (length $mst)"); distances=sort([distance(w,0,id) for id in ids]); one=length(ids)==1 ? 2distances[1] : sum(e[3] for e in spanningtree(w,ids))+distances[1]+distances[2]; best=max(mst,one); println("bound: mst $mst, one-tree $one, best $best")
            if w.tour===nothing; println("gap: no tour"); else; total=pathlength(w,w.tour); gap=best==0 ? 0 : div(2000*(total-best)+best,2best); println("gap: tour $total, $(tenths(gap))%"); end
        else
            q=parse(Int,args[1]); requirecapacity(w,q)
            if command=="VRP"; savings!(w,q,length(args)==2 ? parse(Int,args[2]) : nothing)
            else
                routes=[Int[]]; used=0
                for id in sweeporder(w); demand=w.stops[id].demand; if used+demand>q; push!(routes,Int[]); used=0; end; push!(last(routes),id); used+=demand; end
                w.capacity=q; w.routes=routes; normalize!(w); planreport(w,"sweep: capacity $q")
            end
        end
    elseif command=="TOUR"; requiretour(w); println("tour: $(notation(w.tour)) length $(pathlength(w,w.tour))")
    elseif command in ("TWOOPT","OROPT","SWAP")
        requiretour(w); before=pathlength(w,w.tour); moves=0
        if command=="TWOOPT"; moves=twoopt!(w,w.tour)
        else
            while true
                move=command=="OROPT" ? firstsegment(w,w.tour) : firstswap(w,w.tour); move===nothing && break
                if command=="OROPT"
                    i,size,j,gain=move; segment=w.tour[i:i+size-1]; rest=[w.tour[1:i-1];w.tour[i+size:end]]; println("move $(join(segment,'-')) after $(j==0 ? "D" : string(rest[j])) gain $gain"); w.tour=[rest[1:j];segment;rest[j+1:end]]
                else; i,j,gain=move; println("swap $(w.tour[i]) and $(w.tour[j]) gain $gain"); w.tour[i],w.tour[j]=w.tour[j],w.tour[i]; end
                moves+=1
            end
        end
        println("$(lowercase(command)): moves $moves, length $before -> $(pathlength(w,w.tour))")
    elseif command=="TIMECHECK"
        if isempty(args); requiretour(w); path=w.tour; println("timecheck tour depart $(timetext(w.start))")
        else; requireplan(w); r=parse(Int,args[1]); check(r<=length(w.routes),"no route $r"); path=w.routes[r]; println("timecheck route $r depart $(timetext(w.start))"); end
        run=simulate(w,path)
        for (id,arrival,wait,beginning,leave,late) in run.visits; println("$id arrive $(timetext(arrival)) wait $wait begin $(timetext(beginning)) leave $(timetext(leave)) $(late>0 ? "late $late" : "ok")"); end
        println("return $(timetext(run.finish)), travel $(run.travel), wait $(run.wait), service $(run.service), violations $(run.violations), lateness $(run.lateness)")
    elseif command=="SPLIT"; requiretour(w); q=parse(Int,args[1]); requirecapacity(w,q); splitplan!(w,q)
    elseif command=="ROUTES"; requireplan(w); planreport(w,"plan: capacity $(w.capacity)")
    elseif command in ("RELOCATE","EXCHANGE","CROSS"); requireplan(w); improveplan!(w,command)
    elseif command=="ROUTEOPT"
        requireplan(w); before=planlength(w)
        for (r,path) in enumerate(w.routes); old=pathlength(w,path); moves=twoopt!(w,path;display=false); println("route $r: moves $moves, length $old -> $(pathlength(w,path))"); end
        normalize!(w); println("routeopt: length $before -> $(planlength(w))")
    elseif command=="REPORT"
        println("report: stops $(length(w.stops)), demand $(sum((s.demand for s in values(w.stops));init=0)), service $(sum((s.service for s in values(w.stops));init=0)), windows $(count(s->s.opening>=0,values(w.stops)))")
        if w.tour===nothing; println("tour: none"); else; run=simulate(w,w.tour); println("tour: length $(run.travel), return $(timetext(run.finish)), violations $(run.violations), lateness $(run.lateness)"); end
        if w.routes===nothing; println("plan: none")
        else
            runs=[simulate(w,path) for path in w.routes]; k=length(w.routes); total=sum(pathload(w,path) for path in w.routes); utilization=div(2000total+k*w.capacity,2k*w.capacity); println("plan: capacity $(w.capacity), routes $k, length $(planlength(w)), utilization $(tenths(utilization))%, return $(timetext(maximum(r.finish for r in runs))), violations $(sum(r.violations for r in runs)), lateness $(sum(r.lateness for r in runs))")
        end
    end
end
function main()
    workbench=Workbench(); n=parse(Int,readline())
    for _ in 1:n
        line=readline()
        try; execute!(workbench,line)
        catch e; e isa CommandError || rethrow(); println("error: $(e.message)"); end
    end
end
main()
