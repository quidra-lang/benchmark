include("dataset.jl")
include("variable_charts.jl")
include("attribute_charts.jl")
include("run_rules.jl")
include("capability.jl")
include("plot.jl")
using .Dataset
using .VariableCharts
using .AttributeCharts
using .RunRules
using .ProcessCapability
using .Plot
using Printf

const CHARTS = ("XBAR_R","R","XBAR_S","S","I","MR","CUSUM","EWMA","MA")
const FAMILIES = ("XBAR_R","XBAR_S","I_MR")
const LABELS = (("XBAR","R"),("XBAR","S"),("I","MR"))
const ATTRIBUTES = ("p","np","c","u")
const TYPES = ("SHIFT_UP","SHIFT_DOWN","SPREAD_UP","SPREAD_DOWN","PATTERN")
const STANDARD = Limits(-3.0,0.0,3.0)
function realtext(v)
    result = @sprintf("%.4f",v)
    result == "-0.0000" ? "0.0000" : result
end
numlist(values) = isempty(values) ? "none" : join(values," ")
status(converged) = converged ? "converged" : "stopped"
ruletext(r) = r == 9 ? "UPPER" : r == 10 ? "LOWER" : string(r)
directiontext(d) = d == 1 ? "UP" : d == -1 ? "DOWN" : "NONE"
limittext(label,l) = "$label lcl $(realtext(l.lcl)) cl $(realtext(l.cl)) ucl $(realtext(l.ucl))"
pairtext(family,pair) = limittext(LABELS[family][1],pair[1])*" "*limittext(LABELS[family][2],pair[2])
signalgroup(signal,n) = signal.chart in (5,6) ? div(signal.last-1,n)+1 : signal.last
has_signal(signals,chart,last,rule=0) = any(s -> s.chart == chart && s.last == last && (rule == 0 || s.rule == rule),signals)
eventnumber(events,i) = something(findfirst(e -> e.first <= i <= e.last,events),0)
function estimatefamily(family,s,groups,values,c)
    initial = collect(1:(family == 3 ? s.m*s.n : s.m))
    retained = copy(initial)
    passes = NamedTuple[]
    converged = false
    limits = (STANDARD,STANDARD)
    for p in 1:s.passes
        limits = familylimits(family,retained,groups,values,s.n,c)
        out = Int[]
        for ((numbers,sequence),l) in zip(familyseries(family,retained,groups,values),limits)
            for (i,v) in zip(numbers,sequence)
                outside(l,v) && push!(out,i)
            end
        end
        sort!(unique!(out))
        push!(passes,(points=length(retained),limits=limits,out=out))
        if isempty(out)
            converged = true
            break
        end
        p == s.passes && break
        filter!(i -> i ∉ out,retained)
    end
    (retained=retained,removed=setdiff(initial,retained),passes=passes,converged=converged,limits=limits)
end
function monitor(s,groups,values,c,estimates)
    count = length(groups)
    signals = Signal[]
    for chart in 1:6
        if chart >= 5
            numbers = collect(s.m*s.n+1:length(values))
            sequence = chart == 5 ? Float64.(values[numbers]) : Float64[abs(values[i]-values[i-1]) for i in numbers]
        else
            numbers = collect(s.m+1:count)
            sequence = chart in (1,3) ? [groups[i].mean for i in numbers] : chart == 2 ? Float64[groups[i].range for i in numbers] : [groups[i].sd for i in numbers]
        end
        limits = estimates[div(chart-1,2)+1].limits[isodd(chart) ? 1 : 2]
        append!(signals,checkrules(chart,numbers,sequence,limits,s.rules[chart]))
    end
    mu = estimates[1].limits[1].cl
    sigma = estimates[1].limits[2].cl/c.d2/sqrt(s.n)
    reference,threshold = s.k*sigma,s.h*sigma
    decay = (1-s.lambda)*(1-s.lambda)
    rho = s.lambda/(2-s.lambda)
    ewmascale = s.e*sigma*sqrt(rho)
    mascale = 3*sigma/sqrt(s.span)
    upper,lower,smoothed,factor = 0.0,0.0,mu,1.0
    uprun,downrun = 0,0
    cusum = fill((upper=0.0,lower=0.0),count)
    ewma = fill((value=0.0,width=0.0),count)
    ma = fill((value=0.0,width=0.0),count)
    for i in s.m+1:count
        mean = groups[i].mean
        upper = max(0.0,upper+(mean-mu-reference))
        lower = max(0.0,lower+(mu-mean-reference))
        uprun = upper > 0 ? uprun+1 : 0
        downrun = lower > 0 ? downrun+1 : 0
        cusum[i] = (upper=upper,lower=lower)
        if upper > threshold
            push!(signals,Signal(7,9,i-uprun+1,i,upper,1))
            upper,uprun = 0.0,0
        end
        if lower > threshold
            push!(signals,Signal(7,10,i-downrun+1,i,lower,-1))
            lower,downrun = 0.0,0
        end
        smoothed = s.lambda*mean+(1-s.lambda)*smoothed
        factor *= decay
        width = s.e*sigma*sqrt(rho*(1-factor))
        ewma[i] = (value=smoothed,width=width)
        first = max(s.m+1,i-s.span+1)
        average = sum(groups[j].total for j in first:i)/(s.n*(i-first+1))
        ma[i] = (value=average,width=3*sigma/sqrt(i-first+1))
        for (chart,point,start) in ((8,ewma[i],i),(9,ma[i],first))
            if point.value > mu+point.width
                push!(signals,Signal(chart,9,start,i,point.value,1))
            elseif point.value < mu-point.width
                push!(signals,Signal(chart,10,start,i,point.value,-1))
            end
        end
    end
    sort!(signals,by=x -> (x.chart,x.last,x.rule))
    (signals=signals,mu=mu,sigma=sigma,reference=reference,threshold=threshold,ewmascale=ewmascale,mascale=mascale,cusum=cusum,ewma=ewma,ma=ma)
end
function buildevents(s,groups,monitoring,estimates)
    numbers = sort!(unique([signalgroup(x,s.n) for x in monitoring.signals]))
    bounds = Tuple{Int,Int}[]
    for i in numbers
        if !isempty(bounds) && i-bounds[end][2]-1 <= s.gap
            bounds[end] = (bounds[end][1],i)
        else
            push!(bounds,(i,i))
        end
    end
    events = NamedTuple[]
    for (first,last) in bounds
        signals = [x for x in monitoring.signals if first <= signalgroup(x,s.n) <= last]
        counts = zeros(Int,5)
        detection = zeros(Int,9)
        starts = Int[]
        for signal in signals
            bucket = signal.direction == 0 ? 5 : signal.chart in (2,4,6) ? (signal.direction == 1 ? 3 : 4) : (signal.direction == 1 ? 1 : 2)
            counts[bucket] += 1
            g = signalgroup(signal,s.n)
            detection[signal.chart] = detection[signal.chart] == 0 ? g : min(detection[signal.chart],g)
            signal.chart == 7 && push!(starts,signal.first)
        end
        covered = groups[first:last]
        mean = sum(g.total for g in covered)/(s.n*(last-first+1))
        spread = (realsum(g.sd for g in covered)/(last-first+1))/estimates[2].limits[2].cl
        out = count(v -> v < s.lsl || v > s.usl,[v for g in covered for v in g.values])
        push!(events,(first=first,last=last,signals=signals,counts=counts,detection=detection,onset=isempty(starts) ? first : minimum(starts),shift=(mean-monitoring.mu)/monitoring.sigma,spread=spread,out=out,kind=TYPES[argmax(counts)]))
    end
    events
end
function limitslines(s,groups,values,c,estimates,monitoring,events)
    lines = ["characteristic $(s.characteristic)","subgroup_size $(s.n)","subgroups $(length(groups))","samples $(length(values))","phase1_subgroups $(s.m)"]
    for family in 1:3
        e = estimates[family]
        push!(lines,"family $(FAMILIES[family])")
        for (p,record) in enumerate(e.passes)
            push!(lines,"pass $p points $(record.points) $(pairtext(family,record.limits)) out $(numlist(record.out))")
        end
        push!(lines,"result $(status(e.converged)) passes $(length(e.passes)) retained $(length(e.retained)) removed $(numlist(e.removed))")
    end
    for family in 1:3
        e = estimates[family]
        for (index,(numbers,sequence)) in enumerate(familyseries(family,e.retained,groups,values))
            chart = 2*(family-1)+index
            signals = checkrules(chart,numbers,sequence,e.limits[index],s.rules[chart])
            for signal in signals
                push!(lines,"phase1_signal $(CHARTS[chart]) $(signal.rule) $(signal.first) $(signal.last) $(realtext(signal.value))")
            end
            push!(lines,"phase1_check $(CHARTS[chart]) points $(length(sequence)) signals $(length(signals))")
        end
    end
    free = [i for i in s.m+1:length(groups) if eventnumber(events,i) == 0]
    for family in 1:3
        added = family == 3 ? [j for i in free for j in (i-1)*s.n+1:i*s.n] : free
        numbers = vcat(estimates[family].retained,added)
        limits = familylimits(family,numbers,groups,values,s.n,c)
        push!(lines,"proposed $(FAMILIES[family]) points $(length(numbers)) $(pairtext(family,limits))")
    end
    a = monitoring
    target = "target $(realtext(a.mu)) sigma $(realtext(a.sigma))"
    push!(lines,"cusum $target k $(realtext(a.reference)) h $(realtext(a.threshold))")
    push!(lines,"ewma $target lcl $(realtext(a.mu-a.ewmascale)) ucl $(realtext(a.mu+a.ewmascale))")
    push!(lines,"ma $target span $(s.span) lcl $(realtext(a.mu-a.mascale)) ucl $(realtext(a.mu+a.mascale))")
    for chart in 1:9
        signals = [x for x in a.signals if x.chart == chart]
        ends = unique([x.last for x in signals])
        first = isempty(ends) ? "none" : string(minimum(ends))
        rules = chart <= 6 ? s.rules[chart] : [9,10]
        counts = join(["$(ruletext(r)):$(count(x -> x.rule == r,signals))" for r in rules]," ")
        points = chart in (5,6) ? length(values)-s.m*s.n : length(groups)-s.m
        push!(lines,"phase2 $(CHARTS[chart]) points $points signals $(length(signals)) signalled $(length(ends)) first $first by_rule $counts")
    end
    lines
end
function eventlines(events)
    lines = ["events $(length(events))"]
    for (i,e) in enumerate(events)
        charts = join([CHARTS[j] for j in 1:9 if e.detection[j] > 0],",")
        a,b,c,d,p = e.counts
        push!(lines,"event $i start $(e.first) end $(e.last) length $(e.last-e.first+1) signals $(length(e.signals)) charts $charts location_up $a location_down $b spread_up $c spread_down $d pattern $p onset $(e.onset) shift $(realtext(e.shift)) spread $(realtext(e.spread)) out_of_spec $(e.out) type $(e.kind)")
        detection = join(["$(CHARTS[j]):$(e.detection[j] == 0 ? "-" : string(e.detection[j]))" for j in 1:9]," ")
        push!(lines,"detection $i $detection")
    end
    lines
end
function subgrouplines(s,groups,estimates,a,events)
    lines = ["subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event"]
    for g in groups
        i = g.number
        phase = i > s.m ? "phase2" : i in estimates[1].removed ? "excluded" : "phase1"
        monitored = i > s.m ? realtext.((a.cusum[i].upper,a.cusum[i].lower,a.ewma[i].value,a.ma[i].value)) : ("-","-","-","-")
        event = eventnumber(events,i)
        fields = [string(i),phase,realtext(g.mean),zonename(estimates[1].limits[1],g.mean),string(g.range),realtext(g.sd),monitored...,string(count(x -> signalgroup(x,s.n) == i,a.signals)),event == 0 ? "-" : string(event)]
        push!(lines,join(fields,","))
    end
    lines
end
function attributeanalysis(s,lots)
    lines = String[]
    results = Vector{NamedTuple}[]
    for chart in 1:4
        push!(lines,"chart $(ATTRIBUTES[chart])")
        retained = collect(eachindex(lots))
        converged = false
        passes = 0
        center = centerline(chart,lots)
        for p in 1:s.passes
            passes = p
            center = centerline(chart,lots[retained])
            out = [i for i in retained if lotpoint(chart,lots[i],center).status != "ok"]
            push!(lines,"pass $p lots $(length(retained)) center $(realtext(center.value)) out $(numlist(out))")
            if isempty(out)
                converged = true
                break
            end
            p == s.passes && break
            filter!(i -> i ∉ out,retained)
        end
        removed = setdiff(collect(eachindex(lots)),retained)
        push!(lines,"result $(status(converged)) passes $passes retained $(length(retained)) removed $(numlist(removed))")
        points = NamedTuple[lotpoint(chart,l,center) for l in lots]
        push!(results,points)
        for (lot,p) in zip(lots,points)
            value = chart in (2,3) ? string(Int(p.value)) : realtext(p.value)
            push!(lines,"lot $(lot.number) size $(lot.inspected) value $value lcl $(realtext(p.lcl)) ucl $(realtext(p.ucl)) z $(realtext(p.z)) status $(p.status)")
        end
        signals = checkrules(chart,collect(eachindex(lots)),[p.z for p in points],STANDARD,s.rules[7])
        for x in signals
            push!(lines,"signal $(x.rule) $(x.first) $(x.last) $(realtext(x.value))")
        end
        push!(lines,"signals $(length(signals))")
    end
    lines,results
end
function capabilitylines(s,groups,c,estimates)
    lines = String[]
    measures = (:mean,:sigma_within,:sigma_sbar,:sigma_overall,:cp,:cpu,:cpl,:cpk,:pp,:ppu,:ppl,:ppk,:cpm)
    for (name,chosen) in (("phase1",groups[estimates[1].retained]),("phase2",groups[s.m+1:end]))
        a = assess(chosen,s,c)
        push!(lines,"group $name subgroups $(length(chosen)) values $(a.count)")
        for key in measures
            push!(lines,"$key $(realtext(getproperty(a,key)))")
        end
        for key in (:cpk_ci,:ppk_ci)
            lower,upper = getproperty(a,key)
            push!(lines,"$key $(realtext(lower)) $(realtext(upper))")
        end
        append!(lines,["below_lsl $(a.below)","above_usl $(a.above)","ppm $(realtext(a.ppm))"])
        for g in chosen, (j,value) in enumerate(g.values)
            if value < s.lsl || value > s.usl
                side = value < s.lsl ? "low" : "high"
                push!(lines,"out_of_spec sample $((g.number-1)*s.n+j) subgroup $(g.number) value $value side $side")
            end
        end
        push!(lines,"verdict $(a.verdict)")
        append!(lines,histogram(chosen,s))
    end
    for first in s.m+1:s.step:length(groups)-s.window+1
        last = first+s.window-1
        a = assess(groups[first:last],s,c)
        push!(lines,"rolling $first $last mean $(realtext(a.mean)) sigma_within $(realtext(a.sigma_within)) sigma_overall $(realtext(a.sigma_overall)) cpk $(realtext(a.cpk)) ppk $(realtext(a.ppk)) verdict $(a.verdict)")
    end
    lines
end
function chartlines(s,groups,estimates,a,attributes)
    lines = String[]
    for (name,chart,family,index) in (("XBAR",1,1,1),("R",2,1,2),("S",4,2,2))
        l = estimates[family].limits[index]
        push!(lines,limittext("chart $name",l))
        for g in groups
            i = g.number
            mark = i > s.m ? "2" : i in estimates[family].removed ? "x" : "1"
            value = chart == 1 ? g.mean : chart == 2 ? Float64(g.range) : g.sd
            band = limitsband(l,value,i > s.m && has_signal(a.signals,chart,i))
            push!(lines,"$(lpad(i,3)) $mark $band $(realtext(value))")
        end
    end
    push!(lines,"chart CUSUM h $(realtext(a.threshold))")
    for i in s.m+1:length(groups)
        p = a.cusum[i]
        band = cusumband(p.upper,p.lower,a.threshold,has_signal(a.signals,7,i,9),has_signal(a.signals,7,i,10))
        push!(lines,"$(lpad(i,3)) $band $(realtext(p.upper)) $(realtext(p.lower))")
    end
    for (chart,points,scale) in ((8,a.ewma,a.ewmascale),(9,a.ma,a.mascale))
        push!(lines,limittext("chart $(CHARTS[chart])",Limits(a.mu-scale,a.mu,a.mu+scale)))
        for i in s.m+1:length(groups)
            p = points[i]
            band = widthband(scale,p.width,p.value,a.mu,has_signal(a.signals,chart,i))
            push!(lines,"$(lpad(i,3)) $band $(realtext(p.value)) $(realtext(a.mu-p.width)) $(realtext(a.mu+p.width))")
        end
    end
    for (name,points) in zip(("P_STD","NP_STD","C_STD","U_STD"),attributes)
        push!(lines,limittext("chart $name",STANDARD))
        for (i,p) in enumerate(points)
            push!(lines,"$(lpad(i,3)) $(standardband(p.z,p.status == "ok")) $(realtext(p.z))")
        end
    end
    lines
end
function main()
    s,values,lots = readsettings(),readmeasurements(),readattributes()
    c = controlconstants(s.n)
    groups = statistics(values,s.n)
    estimates = [estimatefamily(f,s,groups,values,c) for f in 1:3]
    a = monitor(s,groups,values,c,estimates)
    events = buildevents(s,groups,a,estimates)
    attribute_lines,attributes = attributeanalysis(s,lots)
    signals = ["chart,rule,start,end,value,direction"]
    append!(signals,["$(CHARTS[x.chart]),$(ruletext(x.rule)),$(x.first),$(x.last),$(realtext(x.value)),$(directiontext(x.direction))" for x in a.signals])
    outputs = [("limits.txt",limitslines(s,groups,values,c,estimates,a,events)),("signals.csv",signals),("events.txt",eventlines(events)),("subgroups.csv",subgrouplines(s,groups,estimates,a,events)),("attribute_charts.txt",attribute_lines),("capability.txt",capabilitylines(s,groups,c,estimates)),("charts.txt",chartlines(s,groups,estimates,a,attributes))]
    mkpath("output")
    for (name,lines) in outputs
        write("output/"*name,join(lines,"\n")*"\n")
    end
end
main()
