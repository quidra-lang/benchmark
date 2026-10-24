using Dates
using Printf
struct CommandError <: Exception
    message::String
end
fail(s)=throw(CommandError(s))
check(b,s)=b ? nothing : fail(s)
signedtext(x)=x>=0 ? "+$x" : string(x)
namelist(xs)=join(sort!(collect(xs)),' ')
function decimals(n,d)
    cents=div(100n,d); @sprintf("%d.%02d",div(cents,100),cents%100)
end
function parsedate(text)
    try; Date(parse(Int,text[1:4]),parse(Int,text[6:7]),parse(Int,text[9:10]))
    catch e; e isa ArgumentError || rethrow(); fail("invalid date $text"); end
end
datetext(d)=Dates.format(d,dateformat"yyyy-mm-dd")*" "*["Mon","Tue","Wed","Thu","Fri","Sat","Sun"][dayofweek(d)]
mutable struct WorkTask
    base::Int
    resource::String
    units::Int
    notbefore::Int
    crashlimit::Union{Nothing,Int}
    crashcost::Int
    crashed::Int
    estimate::Union{Nothing,Tuple{Int,Int,Int}}
end
WorkTask(d,r,u)=WorkTask(d,r,u,0,nothing,0,0,nothing)
duration(t)=t.base-t.crashed
struct Dependency
    a::String
    b::String
    kind::String
    lag::Int
end
struct Schedule
    d::Dict{String,Int}
    es::Dict{String,Int}
    ef::Dict{String,Int}
    ls::Dict{String,Int}
    lf::Dict{String,Int}
    tf::Dict{String,Int}
    ff::Dict{String,Int}
    length::Int
end
mutable struct Project
    tasks::Dict{String,WorkTask}
    links::Dict{Tuple{String,String},Dependency}
    start::Union{Nothing,Date}
    holidays::Set{Date}
    deadline::Union{Nothing,Date}
    capacities::Dict{String,Int}
    baseline::Union{Nothing,Schedule}
end
Project()=Project(Dict{String,WorkTask}(),Dict{Tuple{String,String},Dependency}(),nothing,Set{Date}(),nothing,Dict{String,Int}(),nothing)
function gettask(p,name)
    check(haskey(p.tasks,name),"unknown task $name"); p.tasks[name]
end
tasknames(p)=sort!(collect(keys(p.tasks)))
preds(p,name)=sort!([dep for dep in values(p.links) if dep.b==name];by=x->x.a)
succs(p,name)=sort!([dep for dep in values(p.links) if dep.a==name];by=x->x.b)
function topo(p)
    pending=Set(tasknames(p)); order=String[]
    while !isempty(pending)
        ready=[name for name in sort!(collect(pending)) if all(dep->!(dep.a in pending),preds(p,name))]
        isempty(ready) && break; name=first(ready); delete!(pending,name); push!(order,name)
    end
    order
end
function cyclenotation(p,order)
    remaining=setdiff(Set(tasknames(p)),Set(order)); walk=[minimum(remaining)]
    while true
        previous=first([dep.a for dep in preds(p,last(walk)) if dep.a in remaining]); at=findfirst(==(previous),walk)
        if at!==nothing
            cycle=[previous;reverse(walk[at+1:end])]; firstat=argmin(cycle); cycle=[cycle[firstat:end];cycle[1:firstat-1]]; return join([cycle;first(cycle)]," -> ")
        end
        push!(walk,previous)
    end
end
function analysisorder(p)
    check(!isempty(p.tasks),"no tasks"); order=topo(p); check(length(order)==length(p.tasks),"cycle "*(length(order)<length(p.tasks) ? cyclenotation(p,order) : "")); order
end
startbound(dep,starts,finishes,d)=dep.kind=="FS" ? finishes[dep.a]+dep.lag : dep.kind=="SS" ? starts[dep.a]+dep.lag : finishes[dep.a]+dep.lag-d
finishbound(dep,starts,finishes,d)=dep.kind=="FS" ? starts[dep.b]-dep.lag : dep.kind=="SS" ? starts[dep.b]-dep.lag+d : finishes[dep.b]-dep.lag
margin(s,dep)=dep.kind=="FS" ? s.es[dep.b]-s.ef[dep.a]-dep.lag : dep.kind=="SS" ? s.es[dep.b]-s.es[dep.a]-dep.lag : s.ef[dep.b]-s.ef[dep.a]-dep.lag
function schedulefields(s,name)
    [s.es[name],s.ef[name],s.ls[name],s.lf[name],s.tf[name],s.ff[name]]
end
critical(s)=Set(name for (name,value) in s.tf if value==0)
function compute_schedule(p,order,changed=nothing,replacement=0)
    durations=Dict(name=>duration(task) for (name,task) in p.tasks); changed!==nothing && (durations[changed]=replacement)
    es=Dict{String,Int}(); ef=Dict{String,Int}(); ls=Dict{String,Int}(); lf=Dict{String,Int}()
    for name in order; es[name]=maximum([p.tasks[name].notbefore;[startbound(dep,es,ef,durations[name]) for dep in preds(p,name)]]); ef[name]=es[name]+durations[name]; end
    projectlength=maximum(values(ef))
    for name in reverse(order); lf[name]=minimum([projectlength;[finishbound(dep,ls,lf,durations[name]) for dep in succs(p,name)]]); ls[name]=lf[name]-durations[name]; end
    tf=Dict(name=>ls[name]-es[name] for name in order); ff=Dict{String,Int}(); result=Schedule(durations,es,ef,ls,lf,tf,ff,projectlength)
    for name in order; ff[name]=minimum([projectlength-ef[name];[margin(result,dep) for dep in succs(p,name)]]); end
    result
end
function criticalpaths(p,s)
    selected=critical(s); links=Dict(name=>[dep.b for dep in succs(p,name) if dep.b in selected && margin(s,dep)==0] for name in selected); targets=Set([name for following in values(links) for name in following]); result=Vector{String}[]
    function visit(path)
        following=links[last(path)]
        if isempty(following); push!(result,path)
        else; for next in following; visit([path;next]); end; end
    end
    for name in sort!(collect(setdiff(selected,targets))); visit([name]); end
    result
end
function resourceusage(p,resource,starts,finishes)
    usage=Dict{Int,Int}()
    for (name,task) in p.tasks
        task.resource==resource || continue
        for day in starts[name]:finishes[name]-1; usage[day]=get(usage,day,0)+task.units; end
    end
    usage
end
working(p,date)=dayofweek(date)<=5 && !(date in p.holidays)
function workingdates(p,count)
    result=Date[]; date=p.start
    while length(result)<count; working(p,date) && push!(result,date); date+=Day(1); end
    result
end
function workbetween(p,after,until)
    total=0; date=after+Day(1)
    while date<=until; total+=working(p,date); date+=Day(1); end
    total
end
function calendarreport(p,s)
    dates=workingdates(p,s.length)
    for name in sort!(tasknames(p);by=x->(s.es[x],x)); println("$name $(datetext(dates[s.es[name]+1])) - $(datetext(dates[s.ef[name]]))"); end
    spanstart=first(dates); finish=last(dates); println("project $(datetext(spanstart)) - $(datetext(finish)), $(s.length) working days, $(Dates.value(finish-spanstart)+1) calendar days")
    if p.deadline!==nothing
        if finish<=p.deadline; println("deadline $(datetext(p.deadline)) met, $(workbetween(p,finish,p.deadline)) working days to spare")
        else; println("deadline $(datetext(p.deadline)) missed by $(workbetween(p,p.deadline,finish)) working days"); end
    end
    holidays=sort!([date for date in p.holidays if dayofweek(date)<=5 && spanstart<=date<=finish]); println("holidays in span: ",isempty(holidays) ? "none" : join(datetext.(holidays),", "))
end
function levelreport(p,s,limit)
    resources=sort!(unique([task.resource for task in values(p.tasks)])); capacity=Dict(r=>get(p.capacities,r,limit) for r in resources)
    for name in tasknames(p); task=p.tasks[name]; check(task.units<=capacity[task.resource],"capacity $(capacity[task.resource]) too small for $name"); end
    starts=Dict{String,Int}(); finishes=Dict{String,Int}(); usage=Dict{Tuple{String,Int},Int}(); order=String[]
    while length(order)<length(p.tasks)
        ready=[name for name in tasknames(p) if !haskey(starts,name) && all(dep->haskey(starts,dep.a),preds(p,name))]; name=ready[argmin([(s.ls[x],x) for x in ready])]; task=p.tasks[name]; d=duration(task)
        start=maximum([task.notbefore;[startbound(dep,starts,finishes,d) for dep in preds(p,name)]])
        while any(day->get(usage,(task.resource,day),0)+task.units>capacity[task.resource],start:start+d-1); start+=1; end
        starts[name]=start; finishes[name]=start+d; push!(order,name)
        for day in start:start+d-1; key=(task.resource,day); usage[key]=get(usage,key,0)+task.units; end
    end
    println("level capacity $limit: duration $(s.length) -> $(maximum(values(finishes)))")
    for name in order; println("$name start $(starts[name]) finish $(finishes[name]) shift $(starts[name]-s.es[name])"); end
    for resource in resources
        before=maximum(values(resourceusage(p,resource,s.es,s.ef));init=0); after=maximum(values(resourceusage(p,resource,starts,finishes));init=0)
        println("resource $resource capacity $(capacity[resource]) peak $before -> $after")
    end
end
function crash!(p,order,budget)
    remaining=budget; steps=0; s=compute_schedule(p,order); initial=s.length; reason=""
    while true
        candidates=[name for name in tasknames(p) if s.tf[name]==0 && p.tasks[name].crashlimit!==nothing && p.tasks[name].crashed<p.tasks[name].crashlimit && compute_schedule(p,order,name,duration(p.tasks[name])-1).length<s.length]
        if isempty(candidates); reason="no candidate"; break; end
        name=candidates[argmin([(p.tasks[x].crashcost,x) for x in candidates])]; task=p.tasks[name]
        if task.crashcost>remaining; reason="insufficient budget"; break; end
        old=duration(task); task.crashed+=1; remaining-=task.crashcost; steps+=1; s=compute_schedule(p,order); println("step $steps: $name $old -> $(duration(task)), cost $(task.crashcost), project $(s.length)")
    end
    println("crash done: $steps days, cost $(budget-remaining), project $initial -> $(s.length), budget left $remaining, $reason")
end
function execute!(p,line)
    words=String.(split(line,' ')); command=words[1]; args=words[2:end]
    if command=="TASK"
        name=args[1]; check(!haskey(p.tasks,name),"task $name already exists"); p.tasks[name]=WorkTask(parse(Int,args[2]),args[3],parse(Int,args[4])); println("task $name added")
    elseif command in ("DEP","UNDEP")
        a,b=args[1:2]; gettask(p,a); gettask(p,b); key=(a,b)
        if command=="DEP"
            check(a!=b,"self dependency $a"); check(!haskey(p.links,key),"dependency $a -> $b already exists"); dep=Dependency(a,b,args[3],parse(Int,args[4])); p.links[key]=dep; println("dependency $a -> $b $(dep.kind)$(signedtext(dep.lag)) added")
        else; check(haskey(p.links,key),"no dependency $a -> $b"); delete!(p.links,key); println("dependency $a -> $b removed"); end
    elseif command=="REMOVE"
        name=args[1]; gettask(p,name); selected=[key for key in keys(p.links) if name in key]; for key in selected; delete!(p.links,key); end; delete!(p.tasks,name); println("task $name removed with $(length(selected)) dependencies")
    elseif command in ("NOTBEFORE","CRASHCOST","UNCRASH","PERT")
        name=args[1]; task=gettask(p,name)
        if command=="NOTBEFORE"; task.notbefore=parse(Int,args[2]); println("notbefore $name $(args[2])")
        elseif command=="CRASHCOST"
            limit=parse(Int,args[2]); check(limit<task.base,"crash limit too large for $name"); check(limit>=task.crashed,"crash limit below used days for $name"); task.crashlimit=limit; task.crashcost=parse(Int,args[3]); println("crash $name max $limit cost $(args[3])")
        elseif command=="UNCRASH"; println("uncrash $name restored $(task.crashed) days"); task.crashed=0
        else
            o,m,pe=parse.(Int,args[2:4]); check(o<=m<=pe,"invalid estimate"); task.estimate=(o,m,pe); println("pert $name expected $(decimals(o+4m+pe,6)) variance $(decimals((pe-o)^2,36))")
        end
    elseif command=="CAPACITY"; p.capacities[args[1]]=parse(Int,args[2]); println("capacity $(args[1]) $(args[2])")
    elseif command in ("START","HOLIDAY","DEADLINE")
        date=parsedate(args[1])
        if command=="START"; p.start=date
        elseif command=="DEADLINE"; p.deadline=date
        else; check(!(date in p.holidays),"duplicate holiday $(args[1])"); push!(p.holidays,date); end
        println(lowercase(command)," ",datetext(date))
    elseif command=="LIST"
        println("tasks $(length(p.tasks)), dependencies $(length(p.links)), holidays $(length(p.holidays))")
        for name in tasknames(p); task=p.tasks[name]; previous=[dep.a for dep in preds(p,name)]; println("$name duration $(duration(task)) resource $(task.resource) units $(task.units) preds ",isempty(previous) ? "none" : join(previous,' ')); end
    elseif command=="SHOW"
        name=args[1]; task=gettask(p,name); println("task $name duration $(duration(task)) resource $(task.resource) units $(task.units)",task.notbefore==0 ? "" : " notbefore $(task.notbefore)")
        for (title,links) in (("preds",preds(p,name)),("succs",succs(p,name)))
            entries=["$(title=="preds" ? dep.a : dep.b) $(dep.kind)$(signedtext(dep.lag))" for dep in links]; println("$title: ",isempty(entries) ? "none" : join(entries,", "))
        end
        println("crash: ",task.crashlimit===nothing ? "none" : "max $(task.crashlimit) used $(task.crashed) cost $(task.crashcost)"); println("pert: ",task.estimate===nothing ? "none" : join(task.estimate,' ')); order=topo(p)
        if length(order)<length(p.tasks); println("schedule: unavailable")
        else; s=compute_schedule(p,order); println("schedule: ",join(["$label $value" for (label,value) in zip(["ES","EF","LS","LF","TF","FF"],schedulefields(s,name))],' '),s.tf[name]==0 ? " critical" : ""); end
    elseif command=="IMPACT"
        name=args[1]; gettask(p,name); seen=Set{String}(); queue=[name]; at=1
        while at<=length(queue); current=queue[at]; at+=1; for dep in succs(p,current); if !(dep.b in seen); push!(seen,dep.b); push!(queue,dep.b); end; end; end
        delete!(seen,name); println("impact $name: ",isempty(seen) ? "none" : namelist(seen))
    else
        order=analysisorder(p)
        if command=="CALENDAR"; check(p.start!==nothing,"no start date")
        elseif command=="LOAD"; check(any(t->t.resource==args[1],values(p.tasks)),"unknown resource $(args[1])")
        elseif command=="WHATIF"; gettask(p,args[1])
        elseif command=="VARIANCE"; check(p.baseline!==nothing,"no baseline"); end
        s=compute_schedule(p,order)
        if command=="CPM"
            width=max(4,maximum(length,tasknames(p))); println(rpad("TASK",width),join(lpad.( ["DUR","ES","EF","LS","LF","TF","FF"],5)))
            for name in tasknames(p); println(rpad(name,width),join(lpad.(string.([s.d[name];schedulefields(s,name)]),5)),s.tf[name]==0 ? " *" : ""); end
            println("project duration $(s.length)")
        elseif command=="CRITICAL"
            paths=criticalpaths(p,s); println("critical paths: $(length(paths))"); for path in paths; println(join(path," -> ")); end
        elseif command=="SLACK"
            for f in sort!(unique(collect(values(s.tf)))); println("float $f: ",namelist([name for name in tasknames(p) if s.tf[name]==f])); end
        elseif command=="DRAG"
            for name in sort!(collect(critical(s))); println("$name drag $(s.length-compute_schedule(p,order,name,0).length)"); end
        elseif command=="STATS"
            n=length(p.tasks); c=length(critical(s)); counts=[count(dep->dep.kind==kind,values(p.links)) for kind in ("FS","SS","FF")]; println("tasks $n, critical $c, dependencies $(length(p.links)) (FS $(counts[1]), SS $(counts[2]), FF $(counts[3]))")
            resources=sort!(unique([t.resource for t in values(p.tasks)])); totals=["$r $(sum(duration(t)*t.units for t in values(p.tasks) if t.resource==r))" for r in resources]; println("work ",join(totals,", ")); total=sum(values(s.tf)); println("float total $total, average $(decimals(total,n))\nduration $(s.length), critical share $(decimals(100c,n))%")
        elseif command=="CALENDAR"; calendarreport(p,s)
        elseif command=="GANTT"
            check(s.length<=60,"chart too wide ($(s.length) days)"); width=maximum(length,tasknames(p)); println(repeat(" ",width)," |",join(k%10 for k in 0:s.length-1),"|")
            for name in sort!(tasknames(p);by=x->(s.es[x],x))
                bar=join(s.es[name]<=k<s.ef[name] ? (s.tf[name]==0 ? '=' : '-') : s.ef[name]<=k<s.lf[name] ? '.' : ' ' for k in 0:s.length-1); println(rpad(name,width)," |",bar,"|")
            end
        elseif command=="LEVEL"; levelreport(p,s,parse(Int,args[1]))
        elseif command=="LOAD"
            resource=args[1]; usage=resourceusage(p,resource,s.es,s.ef); daily=[get(usage,k,0) for k in 0:s.length-1]; peak=maximum(daily); println("load $resource: ",join(daily,' ')); println("peak $peak on day $(findfirst(==(peak),daily)-1)")
            haskey(p.capacities,resource) && println("capacity $(p.capacities[resource]) exceeded on $(count(>(p.capacities[resource]),daily)) days")
        elseif command=="PERTSUM"
            for path in criticalpaths(p,s)
                mean=0; variance=0
                for name in path; task=p.tasks[name]; o,m,pe=task.estimate===nothing ? (duration(task),duration(task),duration(task)) : task.estimate; mean+=o+4m+pe; variance+=(pe-o)^2; end
                println(join(path," -> "),": expected $(decimals(mean,6)) variance $(decimals(variance,36))")
            end
        elseif command=="CRASH"; crash!(p,order,parse(Int,args[1]))
        elseif command=="WHATIF"
            name=args[1]; replacement=parse(Int,args[2]); after=compute_schedule(p,order,name,replacement); println("whatif $name $(duration(p.tasks[name])) -> $replacement: project $(s.length) -> $(after.length)")
            for other in tasknames(p)
                changes=["$label $old->$new" for (label,old,new) in zip(("ES","EF","TF"),(s.es[other],s.ef[other],s.tf[other]),(after.es[other],after.ef[other],after.tf[other])) if old!=new]; !isempty(changes) && println(other," ",join(changes,' '))
            end
            critical(s)!=critical(after) && println("critical ",namelist(critical(s))," -> ",namelist(critical(after)))
        elseif command=="BASELINE"; p.baseline=s; println("baseline saved: $(length(p.tasks)) tasks, duration $(s.length)")
        elseif command=="VARIANCE"
            before=p.baseline; println("variance: duration $(before.length) -> $(s.length) ($(signedtext(s.length-before.length)))"); printed=false
            for name in sort!(collect(union(Set(keys(before.es)),Set(tasknames(p)))))
                if !haskey(p.tasks,name); println("$name removed"); printed=true
                elseif !haskey(before.es,name); println("$name new"); printed=true
                elseif (before.es[name],before.ef[name])!=(s.es[name],s.ef[name]); println("$name start $(signedtext(s.es[name]-before.es[name])) finish $(signedtext(s.ef[name]-before.ef[name]))"); printed=true; end
            end
            !printed && println("no task changes")
        end
    end
end
function main()
    project=Project(); n=parse(Int,readline())
    for _ in 1:n
        line=readline()
        try; execute!(project,line)
        catch e; e isa CommandError || rethrow(); println("error: $(e.message)"); end
    end
end
main()
