struct ExpressionNode
    kind::Symbol
    text::String
    value::Int
    children::Vector{ExpressionNode}
end
ExpressionNode(kind,text="",value=0,children=ExpressionNode[])=ExpressionNode(kind,text,value,children)
const LEVELS=(("||",),("&&",),("==","!=","<","<=",">",">="),("+","-"),("*","/","%"))
mutable struct ExpressionReader
    tokens::Vector{String}
    position::Int
end
function expression(text)
    tokens=[String(m.match) for m in eachmatch(r"[0-9]+|[A-Za-z_][A-Za-z0-9_]*|\|\||&&|[=!<>]=|[-+*/%!()<>]",text)]
    readexpression!(ExpressionReader(tokens,1),1)
end
exprpeek(r)=r.position<=length(r.tokens) ? r.tokens[r.position] : ""
function readtoken!(r::ExpressionReader); token=r.tokens[r.position]; r.position+=1; token; end
function readexpression!(r,level)
    level==6 && return readunary!(r)
    node=readexpression!(r,level+1)
    while exprpeek(r) in LEVELS[level]; op=readtoken!(r); right=readexpression!(r,level+1); node=ExpressionNode(:binary,op,0,[node,right]); end
    node
end
function readunary!(r)
    token=readtoken!(r)
    token in ("!","-") && return ExpressionNode(:unary,token,0,[readunary!(r)])
    if token=="("; node=readexpression!(r,1); readtoken!(r); return node; end
    isdigit(token[1]) && return ExpressionNode(:number,"",parse(Int,token))
    if token=="in"; readtoken!(r); name=readtoken!(r); readtoken!(r); return ExpressionNode(:state,name); end
    ExpressionNode(token=="_data" ? :data : :variable,token)
end
struct Action
    kind::Symbol
    name::String
    delay::Int
    text::String
    expr::Union{Nothing,ExpressionNode}
end
function actions(text)
    result=Action[]
    isempty(text) && return result
    for item in split(text,"; ")
        parts=split(item,' ';limit=2); word=parts[1]; rest=parts[2]
        if word=="raise"
            fields=split(rest,' ';limit=2); push!(result,Action(:raise,fields[1],0,"",length(fields)==2 ? expression(fields[2]) : nothing))
        elseif word=="send"
            fields=split(rest,' ';limit=3); push!(result,Action(:send,fields[1],parse(Int,fields[2]),"",length(fields)==3 ? expression(fields[3]) : nothing))
        elseif word=="cancel"; push!(result,Action(:cancel,rest,0,"",nothing))
        elseif word=="log"
            if startswith(rest,'"')
                closing=findnext('"',rest,2); tail=closing<length(rest) ? rest[closing+2:end] : ""; push!(result,Action(:log,"",0,rest[2:closing-1],isempty(tail) ? nothing : expression(tail)))
            else; push!(result,Action(:log,"",0,"",expression(rest))); end
        else; push!(result,Action(:assign,word,0,"",expression(rest[3:end]))); end
    end
    result
end
mutable struct ChartState
    name::String
    kind::String
    parent::Int
    depth::Int
    children::Vector{Int}
    initialname::String
    defaultname::String
    deep::Bool
    entries::Vector{Vector{Action}}
    exits::Vector{Vector{Action}}
    transitions::Vector{Int}
end
ChartState(name,kind,parent,depth,initial="",default="",deep=false)=ChartState(name,kind,parent,depth,Int[],initial,default,deep,Vector{Action}[],Vector{Action}[],Int[])
struct Transition
    source::Int
    kind::String
    descriptors::Vector{String}
    delay::Int
    guard::Union{Nothing,ExpressionNode}
    target::Int
    localtarget::Bool
    actions::Vector{Action}
end
struct Chart
    states::Vector{ChartState}
    names::Dict{String,Int}
    variables::Dict{String,Int}
    transitions::Vector{Transition}
    order::Vector{Int}
end
childstates(c,s)=[x for x in c.states[s].children if c.states[x].kind!="history"]
compound(c,s)=s==1 || (c.states[s].kind=="state" && !isempty(childstates(c,s)))
parallelstate(c,s)=c.states[s].kind=="parallel" && !isempty(childstates(c,s))
atomic(c,s)=c.states[s].kind!="history" && isempty(childstates(c,s))
function descendant(c,s,parent)
    s=c.states[s].parent
    while s!=0; s==parent && return true; s=c.states[s].parent; end
    false
end
initial(c,s)=isempty(c.states[s].initialname) ? childstates(c,s)[1] : c.names[c.states[s].initialname]
defaulttarget(c,s)=isempty(c.states[s].defaultname) ? initial(c,c.states[s].parent) : c.names[c.states[s].defaultname]
function checkexpression(c,node)
    node===nothing && return ""
    node.kind==:variable && !haskey(c.variables,node.text) && return "unknown variable $(node.text)"
    node.kind==:state && !haskey(c.names,node.text) && return "unknown state $(node.text)"
    for child in node.children; error=checkexpression(c,child); !isempty(error) && return error; end
    ""
end
function checkactions(c,list)
    for action in list
        action.kind==:assign && !haskey(c.variables,action.name) && return "unknown variable $(action.name)"
        error=checkexpression(c,action.expr); !isempty(error) && return error
    end
    ""
end
function buildchart(definitions)
    c=Chart([ChartState("","root",0,0)],Dict{String,Int}(),Dict{String,Int}(),Transition[],Int[]); errors=Dict{Int,String}(); stateat=Dict{Int,Int}()
    for (line,text) in definitions
        fields=split(text,' '); kind=fields[1]
        if kind in ("state","parallel","final","history")
            name=fields[2]; parentname=""; init=""; default=""; deep=false
            if kind=="state"
                at=3
                if length(fields)>=3 && fields[3]!="initial"; parentname=fields[3]; at=4; end
                at<=length(fields) && (init=fields[at+1])
            elseif kind=="parallel"; length(fields)==3 && (parentname=fields[3])
            else; parentname=fields[3]
                if kind=="history"; deep=fields[4]=="deep"; length(fields)==5 && (default=fields[5]); end
            end
            if haskey(c.names,name); errors[line]="duplicate state $name"
            elseif !isempty(parentname) && !haskey(c.names,parentname); errors[line]="unknown state $parentname"
            elseif !isempty(parentname) && c.states[c.names[parentname]].kind in ("final","history"); errors[line]="$parentname cannot have children"
            else
                parent=isempty(parentname) ? 1 : c.names[parentname]; index=length(c.states)+1; push!(c.states,ChartState(name,kind,parent,c.states[parent].depth+1,init,default,deep)); c.names[name]=index; push!(c.states[parent].children,index); stateat[line]=index
            end
        elseif kind=="var"
            name=fields[2]
            if haskey(c.variables,name); errors[line]="duplicate variable $name"; else; c.variables[name]=parse(Int,fields[3]); end
        end
    end
    for (line,text) in definitions
        haskey(errors,line) && continue; fields=split(text,' '); kind=fields[1]; error=""
        if kind in ("state","final","history")
            s=stateat[line]; state=c.states[s]
            if kind=="state" && !isempty(state.initialname)
                child=state.initialname
                if !haskey(c.names,child); error="unknown state $child"
                elseif c.states[c.names[child]].parent!=s || c.states[c.names[child]].kind=="history"; error="$child is not a child of $(state.name)"; end
            elseif kind in ("final","history")
                p=state.parent
                if c.states[p].kind!="state" || isempty(childstates(c,p)); error="$(state.name) needs a compound parent"
                elseif kind=="history" && !isempty(state.defaultname)
                    target=state.defaultname
                    if !haskey(c.names,target); error="unknown state $target"
                    elseif !descendant(c,c.names[target],p) || c.states[c.names[target]].kind=="history"; error="$target is not a descendant of $(c.states[p].name)"; end
                end
            end
        elseif kind in ("entry","exit")
            name=fields[2]
            if !haskey(c.names,name); error="unknown state $name"
            elseif c.states[c.names[name]].kind=="history"; error="$name cannot have actions"
            else
                list=actions(split(text," / ";limit=2)[2]); error=checkactions(c,list)
                if isempty(error); push!(kind=="entry" ? c.states[c.names[name]].entries : c.states[c.names[name]].exits,list); end
            end
        elseif kind=="on"
            matched=match(r"\Aon (\S+) (always|after ([0-9]+)|\S+)(?: \[(.*?)\])?(?: ([-~])> (\S+))?(?: / (.*))?\z",text)
            name,trigger,delay,guard,arrow,target,body=matched.captures
            if !haskey(c.names,name); error="unknown state $name"
            elseif c.states[c.names[name]].kind in ("final","history"); error="$name cannot have transitions"
            else
                guardnode=guard===nothing ? nothing : expression(guard); list=body===nothing ? Action[] : actions(body); error=checkexpression(c,guardnode)
                isempty(error) && target!==nothing && !haskey(c.names,target) && (error="unknown state $target")
                isempty(error) && (error=checkactions(c,list))
                if isempty(error)
                    s=c.names[name]; typ=trigger=="always" ? "always" : startswith(trigger,"after ") ? "timer" : "event"; push!(c.transitions,Transition(s,typ,typ=="event" ? String.(split(trigger,'|')) : String[],delay===nothing ? 0 : parse(Int,delay),guardnode,target===nothing ? 0 : c.names[target],arrow=="~",list)); push!(c.states[s].transitions,length(c.transitions))
                end
            end
        end
        !isempty(error) && (errors[line]=error)
    end
    function visit(s); push!(c.order,s); for child in c.states[s].children; visit(child); end; end
    for s in c.states[1].children; visit(s); end
    c,errors
end
struct ChartEvent
    name::String
    value::Int
end
struct Reservation
    due::Int
    number::Int
    transition::Int
    event::ChartEvent
end
mutable struct Engine
    chart::Chart
    config::Set{Int}
    variables::Dict{String,Int}
    data::Int
    queue::Vector{ChartEvent}
    reservations::Vector{Reservation}
    serial::Int
    histories::Dict{Int,Vector{Int}}
    clock::Int
    trace::Bool
    halted::Bool
    macros::Int
    micros::Int
    within::Int
    entered::Vector{Int}
    taken::Vector{Int}
    dwell::Vector{Int}
    entrytime::Vector{Int}
end
Engine(c)=Engine(c,Set{Int}(),copy(c.variables),0,ChartEvent[],Reservation[],0,Dict{Int,Vector{Int}}(),0,false,false,0,0,0,zeros(Int,length(c.states)),zeros(Int,length(c.states)),zeros(Int,length(c.states)),zeros(Int,length(c.states)))
struct EvaluationError <: Exception end
function evaluate(e,node)
    node.kind==:number && return node.value; node.kind==:variable && return e.variables[node.text]; node.kind==:data && return e.data
    node.kind==:state && return Int(e.chart.names[node.text] in e.config)
    if node.kind==:unary; value=evaluate(e,node.children[1]); return node.text=="!" ? Int(value==0) : -value; end
    a=evaluate(e,node.children[1]); op=node.text
    op=="&&" && a==0 && return 0; op=="||" && a!=0 && return 1
    b=evaluate(e,node.children[2]); op in ("&&","||") && return Int(b!=0)
    if op in ("/","%"); b==0 && throw(EvaluationError()); q=div(a,b); return op=="/" ? q : a-q*b; end
    op=="+" && return a+b; op=="-" && return a-b; op=="*" && return a*b
    Int(op=="==" ? a==b : op=="!=" ? a!=b : op=="<" ? a<b : op=="<=" ? a<=b : op==">" ? a>b : a>=b)
end
function reserve!(e,delay,transition,event)
    e.serial+=1; push!(e.reservations,Reservation(e.clock+delay,e.serial,transition,event))
end
function performactions!(e,list)
    try
        for action in list
            value=action.expr===nothing ? 0 : evaluate(e,action.expr)
            if action.kind==:assign; e.variables[action.name]=value
            elseif action.kind==:raise; push!(e.queue,ChartEvent(action.name,value))
            elseif action.kind==:send; reserve!(e,action.delay,0,ChartEvent(action.name,value))
            elseif action.kind==:cancel; filter!(r->r.transition!=0 || r.event.name!=action.name,e.reservations)
            elseif action.kind==:log; println(action.text,action.expr===nothing ? "" : string(value)); end
        end
    catch error; error isa EvaluationError || rethrow(); push!(e.queue,ChartEvent("error.execution",0)); end
end
function closedentries(c,seeds)
    entering=Set(seeds); changed=true
    while changed
        changed=false
        for s in c.order
            s in entering || continue; children=childstates(c,s)
            extra=parallelstate(c,s) ? children : compound(c,s) && all(x->!(x in entering),children) ? [initial(c,s)] : Int[]
            for child in extra; if !(child in entering); push!(entering,child); changed=true; end; end
        end
    end
    entering
end
function complete(e,s)
    c=e.chart
    compound(c,s) && return any(x->c.states[x].kind=="final" && x in e.config,childstates(c,s))
    parallelstate(c,s) && return all(x->complete(e,x),childstates(c,s))
    false
end
function enterstates!(e,entering)
    c=e.chart
    for s in c.order
        s in entering || continue; state=c.states[s]; push!(e.config,s); e.entered[s]+=1; e.entrytime[s]=e.clock
        for t in state.transitions; tr=c.transitions[t]; tr.kind=="timer" && reserve!(e,tr.delay,t,ChartEvent("",0)); end
        for list in state.entries; performactions!(e,list); end
        if state.kind=="final"
            p=state.parent; push!(e.queue,ChartEvent("done.state.$(c.states[p].name)",0)); g=c.states[p].parent
            g!=0 && parallelstate(c,g) && all(x->complete(e,x),childstates(c,g)) && push!(e.queue,ChartEvent("done.state.$(c.states[g].name)",0))
        end
    end
end
effective(e,tr)=tr.target==0 ? Int[] : e.chart.states[tr.target].kind!="history" ? [tr.target] : get(e.histories,tr.target,[defaulttarget(e.chart,tr.target)])
function scope(e,tr)
    tr.target==0 && return 0; c=e.chart; targets=effective(e,tr); s=tr.source
    tr.localtarget && compound(c,s) && all(x->descendant(c,x,s),targets) && return s
    s=c.states[s].parent
    while !(compound(c,s) && all(x->descendant(c,x,s),targets)); s=c.states[s].parent; end
    s
end
exitset(e,tr)=tr.target==0 ? Set{Int}() : Set(s for s in e.config if descendant(e.chart,s,scope(e,tr)))
function matches(tr,kind,event,timer,index)
    kind=="always" && return tr.kind=="always"; kind=="timer" && return index==timer
    tr.kind=="event" && any(d->d=="*" || d==event.name || startswith(event.name,d*"."),tr.descriptors)
end
function selecttransitions!(e,kind,event,timer=0)
    c=e.chart; candidates=Int[]
    for a in c.order
        a in e.config && atomic(c,a) || continue; s=a; found=0
        while s!=1 && found==0
            for t in c.states[s].transitions
                tr=c.transitions[t]; matches(tr,kind,event,timer,t) || continue; accepted=true
                try; accepted=tr.guard===nothing || evaluate(e,tr.guard)!=0
                catch error; error isa EvaluationError || rethrow(); push!(e.queue,ChartEvent("error.execution",0)); accepted=false; end
                if accepted; found=t; break; end
            end
            s=c.states[s].parent
        end
        found!=0 && !(found in candidates) && push!(candidates,found)
    end
    kept=Int[]; exiting=Set{Int}()
    for t in candidates; exits=exitset(e,c.transitions[t]); if isempty(intersect(exiting,exits)); push!(kept,t); union!(exiting,exits); end; end
    kept
end
statenames(c,ids)=isempty(ids) ? "-" : join((c.states[s].name for s in ids),',')
timername(c,t)="after($(c.transitions[t].delay))@$(c.states[c.transitions[t].source].name)"
eventname(event)=event.value==0 ? event.name : "$(event.name)=$(event.value)"
function microstep!(e,selected,display)
    if e.within==1000; println("LIVELOCK t=$(e.clock)"); e.halted=true; return; end
    e.within+=1; e.micros+=1; c=e.chart; scopes=[scope(e,c.transitions[t]) for t in selected]; exiting=Set{Int}()
    for bound in scopes; bound!=0 && union!(exiting,(s for s in e.config if descendant(c,s,bound))); end
    for s in c.order
        s in exiting || continue
        for h in c.states[s].children
            c.states[h].kind=="history" || continue; e.histories[h]=[x for x in c.order if x in e.config && (c.states[h].deep ? atomic(c,x) && descendant(c,x,s) : c.states[x].parent==s)]
        end
    end
    seeds=Int[]
    for (t,bound) in zip(selected,scopes)
        tr=c.transitions[t]; tr.target==0 && continue
        for target in effective(e,tr)
            push!(seeds,target); s=c.states[target].parent
            while s!=bound; push!(seeds,s); s=c.states[s].parent; end
        end
    end
    entering=closedentries(c,seeds)
    e.trace && println("[t=$(e.clock)] $display (",statenames(c,[c.transitions[t].source for t in selected]),"): exit ",statenames(c,[s for s in Iterators.reverse(c.order) if s in exiting]),"; enter ",statenames(c,[s for s in c.order if s in entering]))
    for s in Iterators.reverse(c.order)
        s in exiting || continue
        for list in c.states[s].exits; performactions!(e,list); end
        delete!(e.config,s); e.dwell[s]+=e.clock-e.entrytime[s]; filter!(r->r.transition==0 || c.transitions[r.transition].source!=s,e.reservations)
    end
    for t in selected; tr=c.transitions[t]; performactions!(e,tr.actions); e.taken[tr.source]+=1; end
    enterstates!(e,entering)
end
function macrostep!(e,kind,event=ChartEvent("",0),timer=0)
    e.macros+=1; e.within=0; e.data=event.value
    if kind=="start"; enterstates!(e,closedentries(e.chart,[initial(e.chart,1)]))
    else; selected=selecttransitions!(e,kind,event,timer); !isempty(selected) && microstep!(e,selected,kind=="timer" ? timername(e.chart,timer) : eventname(event)); end
    while !e.halted
        e.data=0; selected=selecttransitions!(e,"always",ChartEvent("",0))
        if !isempty(selected); microstep!(e,selected,"always"); continue; end
        isempty(e.queue) && break; queued=popfirst!(e.queue); e.data=queued.value; selected=selecttransitions!(e,"event",queued)
        !isempty(selected) && microstep!(e,selected,eventname(queued))
    end
end
function warnings(c)
    reached=Set([initial(c,1)]); changed=true
    while changed
        before=length(reached)
        for s in c.order
            s in reached || continue; p=c.states[s].parent; p!=1 && push!(reached,p)
            compound(c,s) && push!(reached,initial(c,s)); parallelstate(c,s) && union!(reached,childstates(c,s))
            for t in c.states[s].transitions; target=c.transitions[t].target; target!=0 && push!(reached,c.states[target].kind=="history" ? defaulttarget(c,target) : target); end
        end
        changed=before!=length(reached)
    end
    for s in c.order; c.states[s].kind!="history" && !(s in reached) && println("warning: unreachable state $(c.states[s].name)"); end
end
function dumpstate(e)
    c=e.chart; println("dump t=$(e.clock)")
    for s in c.order; s in e.config && println(repeat(" ",2*c.states[s].depth),c.states[s].name); end
    for name in sort(collect(keys(e.variables))); println("  var $name = $(e.variables[name])"); end
    for s in c.order; haskey(e.histories,s) && println("  history $(c.states[s].name) = ",statenames(c,e.histories[s])); end
    for r in sort(e.reservations;by=r->(r.due,r.number)); println(r.transition==0 ? "  send $(r.due) $(r.event.name) $(r.event.value)" : "  timer $(r.due) $(timername(c,r.transition))"); end
end
function script!(e,text)
    fields=split(text,' '); command=fields[1]
    if command=="event"; macrostep!(e,"event",ChartEvent(fields[2],length(fields)==3 ? parse(Int,fields[3]) : 0))
    elseif command=="tick"
        finish=e.clock+parse(Int,fields[2])
        while !e.halted && !isempty(e.reservations)
            index=argmin([(r.due,r.number) for r in e.reservations]); r=e.reservations[index]; r.due>finish && break; deleteat!(e.reservations,index); e.clock=r.due; macrostep!(e,r.transition==0 ? "event" : "timer",r.event,r.transition)
        end
        !e.halted && (e.clock=finish)
    elseif command=="set"
        name=fields[2]; if haskey(e.variables,name); e.variables[name]=parse(Int,fields[3]); else; println("error: unknown variable $name"); end
    elseif command=="trace"; e.trace=fields[2]=="on"
    elseif command=="dump"; dumpstate(e)
    elseif command=="eval"
        text=text[6:end]; node=expression(text); error=checkexpression(e.chart,node)
        if !isempty(error); println("error: $error")
        else
            e.data=0
            try; value=evaluate(e,node); println("$text -> $value")
            catch error; error isa EvaluationError || rethrow(); println("error: division by zero"); end
        end
    end
end
function runchart(name,definitions,scripts)
    println("chart $name"); c,errors=buildchart(definitions)
    if !isempty(errors); for line in sort(collect(keys(errors))); println("error line $line: $(errors[line])"); end; return; end
    warnings(c); e=Engine(c); macrostep!(e,"start")
    for text in scripts; e.halted && break; script!(e,text); end
    println("end t=$(e.clock) macrosteps=$(e.macros) microsteps=$(e.micros)")
    for s in c.order
        c.states[s].kind=="history" && continue; total=e.dwell[s]+(s in e.config ? e.clock-e.entrytime[s] : 0); println("  $(c.states[s].name) entered=$(e.entered[s]) taken=$(e.taken[s]) time=$total")
    end
end
function main()
    lines=readlines(); position=2
    for _ in 1:parse(Int,lines[1])
        name=lines[position][7:end]; position+=1; definitions=Tuple{Int,String}[]
        while lines[position]!="RUN"; push!(definitions,(position,lines[position])); position+=1; end
        position+=1; scripts=String[]
        while lines[position]!="END"; push!(scripts,lines[position]); position+=1; end
        position+=1; runchart(name,definitions,scripts)
    end
end
main()
