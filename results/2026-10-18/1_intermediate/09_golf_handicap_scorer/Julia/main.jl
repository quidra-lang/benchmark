using Printf
struct GolfCourse
    id::String
    pars::Vector{Int}
    si::Vector{Int}
    tees::Dict{String,Tuple{Int,Int}}
end
struct GolfRound
    day::Int
    course::String
    tee::String
    scores::Vector{String}
    handicap::Union{Nothing,Int}
    adjusted::Vector{Int}
    ags::Int
    diff::Int
    exceptional::Int
    beforeindex::Union{Nothing,Int}
    beforerecords::Int
    beforecalculation::Any
end
Base.@kwdef mutable struct GolfPlayer
    id::String
    name::String
    index::Union{Nothing,Int} = nothing
    rounds::Vector{GolfRound} = GolfRound[]
    records::Vector{Tuple{Int,Int}} = Tuple{Int,Int}[]
    calculation::Any = nothing
end
struct GolfEvent
    id::String
    kind::String
    course::String
    tee::String
    day::Int
    allowance::Int
    players::Vector{String}
end
const COURSES = Dict{String,GolfCourse}()
const PLAYERS = Dict{String,GolfPlayer}()
const EVENTS = Dict{String,GolfEvent}()
const EVENT_ORDER = String[]
fail(message) = throw(ArgumentError(message))
half_up(a,b) = fld(2a+b,2b)
half_away(a,b) = (a < 0 ? -1 : 1)*div(2abs(a)+b,2b)
tenths_text(v) = string(div(abs(v),10),'.',mod(abs(v),10))
index_text(v) = v === nothing ? "none" : (v < 0 ? "+" : "")*tenths_text(v)
signed_text(v) = (v < 0 ? "-" : "")*tenths_text(v)
handicap_text(v) = v === nothing ? "none" : (v < 0 ? "+"*string(-v) : string(v))
hundredths(v) = @sprintf("%d.%02d",div(v,100),mod(v,100))
mean_text(total,n) = n == 0 ? "-" : hundredths(div(total*100,n))
status_text(lead) = lead == 0 ? "AS" : string(abs(lead))*(lead > 0 ? " UP" : " DN")
function get_player(id)
    haskey(PLAYERS,id) || fail("unknown player")
    return PLAYERS[id]
end
function get_course(id)
    haskey(COURSES,id) || fail("unknown course")
    return COURSES[id]
end
function tee_check(course,tee)
    c = get_course(course)
    haskey(c.tees,tee) || fail("unknown tee")
    return c,c.tees[tee]
end
course_handicap(index,c,tee) = half_up(index*tee[2]+113*(tee[1]-10sum(c.pars)),1130)
function stroke_allocation(handicap,si)
    q,r = divrem(abs(handicap),18)
    if handicap >= 0
        return [q+Int(rank <= r) for rank in si]
    end
    return [-q-Int(rank >= 19-r) for rank in si]
end
function low_index(p,day)
    best = nothing
    for record in p.records
        if day-365 <= record[1] < day && (best === nothing || (record[2],record[1]) < (best[2],best[1]))
            best = record
        end
    end
    return best
end
function counting_rule(n)
    n < 3 && return (0,0)
    n == 3 && return (1,-20)
    n == 4 && return (1,-10)
    n == 5 && return (1,0)
    n == 6 && return (2,-10)
    n <= 8 && return (2,0)
    n <= 11 && return (3,0)
    n <= 14 && return (4,0)
    n <= 16 && return (5,0)
    n <= 18 && return (6,0)
    return (n == 19 ? 7 : 8),0
end
function eligible(p)
    result = NamedTuple[]
    reduction = 0
    for i in length(p.rounds):-1:max(1,length(p.rounds)-19)
        r = p.rounds[i]
        reduction += r.exceptional
        push!(result,(number=i,round=r,adjusted=r.diff-reduction))
    end
    reverse!(result)
    return result
end
function counting(items)
    k,a = counting_rule(length(items))
    ordered = sort(items;by=item -> (item.adjusted,-item.number))
    return ordered[1:k]
end
function update_index!(p,day)
    items = eligible(p)
    k,adjustment = counting_rule(length(items))
    if k == 0
        p.calculation = nothing
        return
    end
    average = half_away(sum(item.adjusted for item in counting(items)),k)
    value = average+adjustment
    low = low_index(p,day)
    soft,hard,maximum = false,false,false
    if low !== nothing
        l = low[2]
        if value-l > 30
            newvalue = l+30+div(value-l-30,2)
            soft = newvalue != value
            value = newvalue
        end
        if value-l > 50
            value = l+50
            hard = true
        end
    end
    if value > 540
        value = 540
        maximum = true
    end
    p.index = value
    p.calculation = (k=k,average=average,adjustment=adjustment,low=low === nothing ? nothing : low[2],hard=hard,soft=soft,maximum=maximum)
end
function hole_values(r,strokes,c)
    nets = Union{Nothing,Int}[]
    points = Int[]
    for (h,score) in enumerate(r.scores)
        raw = tryparse(Int,score)
        net = raw === nothing ? nothing : raw-strokes[h]
        push!(nets,net)
        push!(points,net === nothing ? 0 : max(0,c.pars[h]+2-net))
    end
    return nets,points
end
countback(values,larger=false) = Tuple(sum(values[start:end])*(larger ? -1 : 1) for start in (1,10,13,16,18))
function event_context(e)
    c,tee = tee_check(e.course,e.tee)
    rounds = Dict{String,GolfRound}()
    ph = Dict{String,Int}()
    for id in e.players
        found = findfirst(r -> r.course == e.course && r.tee == e.tee && r.day == e.day,PLAYERS[id].rounds)
        found === nothing && fail("missing round")
        r = PLAYERS[id].rounds[found]
        r.handicap === nothing && fail("no index")
        rounds[id] = r
        ph[id] = half_up(r.handicap*e.allowance,100)
    end
    minimum = e.kind in ("MATCH","NASSAU","FOURBALL") ? min(values(ph)...) : 0
    nets = Dict{String,Vector{Union{Nothing,Int}}}()
    points = Dict{String,Vector{Int}}()
    for id in e.players
        nets[id],points[id] = hole_values(rounds[id],stroke_allocation(ph[id]-minimum,c.si),c)
    end
    return (course=c,rounds=rounds,ph=ph,minimum=minimum,nets=nets,points=points)
end
function par_values(nets,pars)
    return map(nets,pars) do net,par
        net === nothing ? -1 : sign(par-net)
    end
end
function ranking(e,ctx)
    ranked = String[]
    sortkeys = Dict{String,Tuple}()
    for id in e.players
        if e.kind == "STROKE"
            any(isnothing,ctx.nets[id]) && continue
            values = something.(ctx.nets[id],0)
        elseif e.kind == "STABLEFORD"
            values = ctx.points[id]
        else
            values = par_values(ctx.nets[id],ctx.course.pars)
        end
        push!(ranked,id)
        sortkeys[id] = (countback(values,e.kind != "STROKE")...,id)
    end
    return sort!(ranked;by=id -> sortkeys[id])
end
function play_match(wins,names,firsthole,lasthole)
    lead,remaining = 0,0
    statuses = String[]
    for h in firsthole:lasthole
        lead += wins[h]
        push!(statuses,status_text(lead))
        remaining = lasthole-h
        abs(lead) > remaining && break
    end
    result = "AS"
    if lead != 0
        name = names[lead > 0 ? 1 : 2]
        margin = remaining > 0 ? "$(abs(lead))&$remaining" : "$(abs(lead)) UP"
        result = "$name $margin"
    end
    return statuses,result
end
function result_lines(e)
    ctx = event_context(e)
    c = ctx.course
    out = ["results $(e.id): $(e.kind) $(e.course) $(e.tee) day $(e.day) allowance $(e.allowance)"]
    if e.kind in ("STROKE","STABLEFORD","PAR")
        ranked = ranking(e,ctx)
        for (rank,id) in enumerate(ranked)
            if e.kind == "STROKE"
                text = "net $(sum(something.(ctx.nets[id],0))) gross $(sum(parse.(Int,ctx.rounds[id].scores)))"
            elseif e.kind == "STABLEFORD"
                text = "points $(sum(ctx.points[id]))"
            else
                text = status_text(sum(par_values(ctx.nets[id],c.pars)))
            end
            push!(out,"$rank $id $text hcp $(handicap_text(ctx.ph[id]))")
        end
        if e.kind == "STROKE"
            nr = sort(setdiff(e.players,ranked))
            for id in nr
                push!(out,"NR $id hcp $(handicap_text(ctx.ph[id]))")
            end
            if !isempty(ranked)
                sort!(ranked;by=id -> (countback(parse.(Int,ctx.rounds[id].scores))...,id))
                id = ranked[1]
                push!(out,"gross $id $(sum(parse.(Int,ctx.rounds[id].scores)))")
            end
        end
    elseif e.kind in ("MATCH","NASSAU","FOURBALL")
        sidesize = e.kind == "FOURBALL" ? 2 : 1
        sides = [e.players[1:sidesize],e.players[sidesize+1:2sidesize]]
        names = [join(ids,"+") for ids in sides]
        wins = Int[]
        for h in 1:18
            scores = Union{Nothing,Int}[]
            for ids in sides
                values = [ctx.nets[id][h] for id in ids if ctx.nets[id][h] !== nothing]
                push!(scores,isempty(values) ? nothing : min(values...))
            end
            if scores[1] === nothing
                push!(wins,scores[2] === nothing ? 0 : -1)
            elseif scores[2] === nothing
                push!(wins,1)
            else
                push!(wins,sign(scores[2]-scores[1]))
            end
        end
        parts = ["strokes"]
        for id in e.players
            append!(parts,[id,string(ctx.ph[id]-ctx.minimum)])
        end
        push!(out,join(parts," "))
        if e.kind == "NASSAU"
            for (label,firsthole,lasthole) in (("front",1,9),("back",10,18),("total",1,18))
                statuses,result = play_match(wins,names,firsthole,lasthole)
                push!(out,"$label $result")
            end
        else
            statuses,result = play_match(wins,names,1,18)
            push!(out,"status "*join(statuses,", "))
            push!(out,"result $result")
        end
    elseif e.kind == "BETTERBALL"
        teams = NamedTuple[]
        for i in 1:2:length(e.players)
            a,b = e.players[i:i+1]
            values = max.(ctx.points[a],ctx.points[b])
            push!(teams,(a=a,b=b,values=values,key=(countback(values,true)...,a)))
        end
        sort!(teams;by=team -> team.key)
        for (rank,team) in enumerate(teams)
            a,b = team.a,team.b
            push!(out,"$rank $a+$b points $(sum(team.values)) hcp $(handicap_text(ctx.ph[a])) $(handicap_text(ctx.ph[b]))")
        end
    else
        totals = Dict(id=>0 for id in e.players)
        carry = 0
        winners = String[]
        for h in 1:18
            carry += 1
            minimum = nothing
            winners = String[]
            for id in e.players
                net = ctx.nets[id][h]
                net === nothing && continue
                if minimum === nothing || net < minimum
                    minimum = net
                    winners = [id]
                elseif net == minimum
                    push!(winners,id)
                end
            end
            if length(winners) == 1
                id = winners[1]
                totals[id] += 100carry
                push!(out,"hole $h $id $carry")
                carry = 0
            end
        end
        if carry > 0
            isempty(winners) && (winners = copy(e.players))
            sort!(winners)
            share = div(100carry,length(winners))
            for id in winners
                totals[id] += share
            end
            push!(out,"carry $carry "*join(winners," "))
        end
        for id in sort(e.players;by=id -> (-totals[id],id))
            push!(out,"$id $(hundredths(totals[id]))")
        end
    end
    return out
end
function execute(line)
    t = String.(split(line,' '))
    cmd = t[1]
    out = String[]
    if cmd == "COURSE"
        haskey(COURSES,t[2]) && fail("duplicate course")
        pars,si = parse.(Int,t[3:20]),parse.(Int,t[21:38])
        all(par -> par in (3,4,5),pars) && sort(si) == collect(1:18) || fail("invalid course")
        COURSES[t[2]] = GolfCourse(t[2],pars,si,Dict{String,Tuple{Int,Int}}())
    elseif cmd == "TEE"
        c = get_course(t[2])
        haskey(c.tees,t[3]) && fail("duplicate tee")
        rating,slope = parse.(Int,t[4:5])
        500 <= rating <= 900 && 55 <= slope <= 155 || fail("invalid tee")
        c.tees[t[3]] = (rating,slope)
    elseif cmd == "PLAYER"
        haskey(PLAYERS,t[2]) && fail("duplicate player")
        index = length(t) == 4 ? parse(Int,t[4]) : nothing
        index !== nothing && !(-100 <= index <= 540) && fail("invalid index")
        PLAYERS[t[2]] = GolfPlayer(id=t[2],name=t[3],index=index)
    elseif cmd == "ROUND"
        p = get_player(t[2])
        c,tee = tee_check(t[3],t[4])
        day = parse(Int,t[5])
        !isempty(p.rounds) && day < p.rounds[end].day && fail("invalid day")
        scores = t[6:end]
        count(==("-"),scores) < 5 || fail("too few holes")
        hcp = p.index === nothing ? nothing : course_handicap(p.index,c,tee)
        strokes = stroke_allocation(something(hcp,0),c.si)
        adjusted = Int[]
        for (h,score) in enumerate(scores)
            limit = c.pars[h]+(p.index === nothing ? 5 : 2+strokes[h])
            if score == "X"
                push!(adjusted,limit)
            elseif score == "-"
                push!(adjusted,c.pars[h]+strokes[h])
            else
                push!(adjusted,min(parse(Int,score),limit))
            end
        end
        ags = sum(adjusted)
        diff = half_away(113*(10ags-tee[1]),tee[2])
        exceptional = 0
        if p.index !== nothing && p.index-diff >= 70
            exceptional = p.index-diff >= 100 ? 20 : 10
        end
        r = GolfRound(day,c.id,t[4],scores,hcp,adjusted,ags,diff,exceptional,p.index,length(p.records),p.calculation)
        push!(p.rounds,r)
        update_index!(p,day)
        p.index !== nothing && push!(p.records,(day,p.index))
        extra = exceptional == 0 ? "" : " exceptional $(signed_text(-exceptional))"
        push!(out,"round $(p.id) $(length(p.rounds)): ags $ags diff $(signed_text(diff))$extra index $(index_text(p.index))")
    elseif cmd == "REMOVE"
        p = get_player(t[2])
        isempty(p.rounds) && fail("no rounds")
        number = length(p.rounds)
        r = pop!(p.rounds)
        p.index = r.beforeindex
        resize!(p.records,r.beforerecords)
        p.calculation = r.beforecalculation
        push!(out,"removed $(p.id) $number: index $(index_text(p.index))")
    elseif cmd in ("INDEX","HISTORY","LOWINDEX","COURSEHCP","CARD","STATS")
        p = get_player(t[2])
        if cmd == "INDEX"
            text = "index $(p.id): $(index_text(p.index)) rounds $(length(p.rounds))"
            calc = p.calculation
            if calc !== nothing
                text *= " lowest $(calc.k) average $(signed_text(calc.average)) adjustment $(signed_text(calc.adjustment))"
                calc.low !== nothing && (text *= " low $(index_text(calc.low))")
                if calc.hard
                    text *= " hard cap"
                elseif calc.soft
                    text *= " soft cap"
                end
                calc.maximum && (text *= " maximum")
            end
            push!(out,text)
        elseif cmd == "HISTORY"
            push!(out,"history $(p.id): rounds $(length(p.rounds))")
            items = eligible(p)
            counted = Set(item.number for item in counting(items))
            for item in items
                r = item.round
                text = "$(item.number) day $(r.day) $(r.course) $(r.tee) ags $(r.ags) diff $(signed_text(r.diff))"
                item.adjusted != r.diff && (text *= " adjusted $(signed_text(item.adjusted))")
                item.number in counted && (text *= " *")
                push!(out,text)
            end
        elseif cmd == "LOWINDEX"
            low = low_index(p,parse(Int,t[3]))
            value = low === nothing ? "none" : "$(index_text(low[2])) day $(low[1])"
            push!(out,"lowindex $(p.id) $(t[3]): $value")
        elseif cmd == "COURSEHCP"
            c,tee = tee_check(t[3],t[4])
            p.index !== nothing || fail("no index")
            hcp = course_handicap(p.index,c,tee)
            push!(out,"coursehcp $(p.id) $(c.id) $(t[4]): $(handicap_text(hcp)) strokes "*join(stroke_allocation(hcp,c.si)," "))
        elseif cmd == "CARD"
            number = parse(Int,t[3])
            number <= length(p.rounds) || fail("unknown round")
            r = p.rounds[number]
            c = COURSES[r.course]
            strokes = stroke_allocation(something(r.handicap,0),c.si)
            nets,points = hole_values(r,strokes,c)
            push!(out,"card $(p.id) $number: $(r.course) $(r.tee) day $(r.day) handicap $(handicap_text(r.handicap))")
            for h in 1:18
                net = nets[h] === nothing ? "-" : string(nets[h])
                push!(out,"$h $(c.pars[h]) $(c.si[h]) $(r.scores[h]) $(r.adjusted[h]) $(strokes[h]) $net $(points[h])")
                if h == 9
                    ranges = [("OUT",1:9)]
                elseif h == 18
                    ranges = [("IN",10:18),("TOTAL",1:18)]
                else
                    ranges = Tuple{String,UnitRange{Int}}[]
                end
                for (label,range) in ranges
                    complete = !any(isnothing,nets[range])
                    raw = complete ? string(sum(parse.(Int,r.scores[range]))) : "-"
                    net = complete ? string(sum(something.(nets[range],0))) : "-"
                    push!(out,"$label $(sum(c.pars[range])) $raw $(sum(r.adjusted[range])) $(sum(strokes[range])) $net $(sum(points[range]))")
                end
            end
            push!(out,"ags $(r.ags) diff $(signed_text(r.diff))")
        else
            counts = Dict(key=>0 for key in ("eagles","birdies","pars","bogeys","doubles","others","pickups"))
            sums,numbers = Dict(par=>0 for par in 3:5),Dict(par=>0 for par in 3:5)
            totals = Int[]
            for r in p.rounds
                c = COURSES[r.course]
                total,complete = 0,true
                for (h,score) in enumerate(r.scores)
                    value = tryparse(Int,score)
                    if value === nothing
                        complete = false
                        score == "X" && (counts["pickups"] += 1)
                        continue
                    end
                    par = c.pars[h]
                    relative = value-par
                    if relative <= -2
                        category = "eagles"
                    elseif relative == -1
                        category = "birdies"
                    elseif relative == 0
                        category = "pars"
                    elseif relative == 1
                        category = "bogeys"
                    elseif relative == 2
                        category = "doubles"
                    else
                        category = "others"
                    end
                    counts[category] += 1
                    sums[par] += value
                    numbers[par] += 1
                    total += value
                end
                complete && push!(totals,total)
            end
            best = isempty(totals) ? "-" : string(min(totals...))
            push!(out,"stats $(p.id): rounds $(length(p.rounds)) best $best average $(mean_text(sum(totals),length(totals))) eagles $(counts["eagles"]) birdies $(counts["birdies"]) pars $(counts["pars"]) bogeys $(counts["bogeys"]) doubles $(counts["doubles"]) others $(counts["others"]) pickups $(counts["pickups"]) par3 $(mean_text(sums[3],numbers[3])) par4 $(mean_text(sums[4],numbers[4])) par5 $(mean_text(sums[5],numbers[5]))")
        end
    elseif cmd == "HCPTABLE"
        c,tee = tee_check(t[2],t[3])
        firstindex,lastindex = parse.(Int,t[4:5])
        -100 <= firstindex <= lastindex <= 540 || fail("invalid index")
        push!(out,"hcptable $(c.id) $(t[3]): $(index_text(firstindex)) to $(index_text(lastindex))")
        start,hcp = firstindex,course_handicap(firstindex,c,tee)
        for i in firstindex+1:lastindex+1
            next = i <= lastindex ? course_handicap(i,c,tee) : nothing
            if next != hcp
                push!(out,"$(index_text(start)) to $(index_text(i-1)): $(handicap_text(hcp))")
                start,hcp = i,next
            end
        end
    elseif cmd == "HOLESTATS"
        c = get_course(t[2])
        sums,numbers = zeros(Int,18),zeros(Int,18)
        rounds = 0
        for p in values(PLAYERS)
            for r in p.rounds
                r.course == c.id || continue
                rounds += 1
                for (h,score) in enumerate(r.scores)
                    value = tryparse(Int,score)
                    if value !== nothing
                        sums[h] += value
                        numbers[h] += 1
                    end
                end
            end
        end
        holes = collect(1:18)
        sort!(holes;lt=(a,b) -> begin
            if numbers[a] == 0 || numbers[b] == 0
                return (numbers[a] == 0,a) < (numbers[b] == 0,b)
            end
            left = (sums[a]-c.pars[a]*numbers[a])*numbers[b]
            right = (sums[b]-c.pars[b]*numbers[b])*numbers[a]
            return left == right ? a < b : left > right
        end)
        ranks = invperm(holes)
        push!(out,"holestats $(c.id): rounds $rounds")
        for h in 1:18
            push!(out,"$h par $(c.pars[h]) si $(c.si[h]) scores $(numbers[h]) avg $(mean_text(sums[h],numbers[h])) rank $(ranks[h])")
        end
    elseif cmd == "PLAYERS"
        allplayers = sort(collect(values(PLAYERS));by=p -> (p.index === nothing,something(p.index,0),p.id))
        push!(out,"players $(length(allplayers))")
        for p in allplayers
            push!(out,"$(p.id) $(p.name) $(index_text(p.index)) rounds $(length(p.rounds))")
        end
    elseif cmd == "EVENT"
        haskey(EVENTS,t[2]) && fail("duplicate event")
        tee_check(t[4],t[5])
        allowance = parse(Int,t[7])
        1 <= allowance <= 100 || fail("invalid allowance")
        ids = t[8:end]
        foreach(get_player,ids)
        n = length(ids)
        if t[3] in ("MATCH","NASSAU")
            valid = n == 2
        elseif t[3] == "FOURBALL"
            valid = n == 4
        elseif t[3] == "BETTERBALL"
            valid = n in (4,6,8)
        else
            valid = 2 <= n <= 8
        end
        valid && length(unique(ids)) == n || fail("invalid players")
        EVENTS[t[2]] = GolfEvent(t[2],t[3],t[4],t[5],parse(Int,t[6]),allowance,ids)
        push!(EVENT_ORDER,t[2])
    elseif cmd == "RESULTS"
        haskey(EVENTS,t[2]) || fail("unknown event")
        out = result_lines(EVENTS[t[2]])
    elseif cmd == "MERIT"
        totals = Dict{String,Vector{Int}}()
        counted = 0
        for id in EVENT_ORDER
            e = EVENTS[id]
            e.kind in ("STROKE","STABLEFORD","PAR") || continue
            try
                ctx = event_context(e)
                counted += 1
                for player in e.players
                    get!(totals,player,[0,0,0])[3] += 1
                end
                for (rank,player) in enumerate(ranking(e,ctx))
                    totals[player][1] += [10,8,6,5,4,3,2,1][rank]
                    rank == 1 && (totals[player][2] += 1)
                end
            catch exception
                exception isa ArgumentError || rethrow()
            end
        end
        ids = sort(collect(keys(totals));by=id -> (-totals[id][1],-totals[id][2],id))
        push!(out,"merit: events $counted")
        for (rank,id) in enumerate(ids)
            push!(out,"$rank $id $(totals[id][1]) wins $(totals[id][2]) played $(totals[id][3])")
        end
    end
    return out
end
function main()
    for i in 1:parse(Int,readline())
        line = readline()
        try
            foreach(println,execute(line))
        catch exception
            exception isa ArgumentError || rethrow()
            println("ERROR ",exception.msg)
        end
    end
end
main()
