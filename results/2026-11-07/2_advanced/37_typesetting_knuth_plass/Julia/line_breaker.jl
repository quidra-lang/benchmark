line_class(slack,last) = last ? 1 : slack <= 1 ? 0 : slack <= 3 ? 1 : slack <= 6 ? 2 : 3
function line_cost(metrics,start,stop,previous_class,params)
    slack = metrics_slack(metrics,start,stop)
    last = stop == metrics.count
    current_class = line_class(slack,last)
    cost = params["line_penalty"]+(slack < 0 ? params["overfull_penalty"] : last ? 0 : slack*slack)
    if metrics.breaks[stop+1].midword
        cost += params["hyphen_penalty"]
        metrics.breaks[start+1].midword && (cost += params["double_hyphen_demerit"])
    end
    last && metrics.breaks[start+1].midword && (cost += params["final_hyphen_demerit"])
    abs(current_class-previous_class) >= 2 && (cost += params["fitness_demerit"])
    cost
end
function breaking_cost(metrics,breaking,params)
    total,start,previous_class = 0,0,1
    for stop in breaking
        total += line_cost(metrics,start,stop,previous_class,params)
        previous_class = line_class(metrics_slack(metrics,start,stop),stop == metrics.count)
        start = stop
    end
    total
end
function knuth_plass(metrics,params)
    states = [Dict{Int,Tuple{Int,Int,Int}}() for _ in 0:metrics.count]
    states[1][1] = (0,0,0)
    for stop in 1:metrics.count
        for start in stop-1:-1:0
            slack = metrics_slack(metrics,start,stop)
            slack < 0 && stop != start+1 && break
            current_class = line_class(slack,stop == metrics.count)
            for (previous_class,previous) in states[start+1]
                cost = previous[1]+line_cost(metrics,start,stop,previous_class,params)
                candidate = (cost,start,previous_class)
                best = get(states[stop+1],current_class,nothing)
                (isnothing(best) || candidate < best) && (states[stop+1][current_class]=candidate)
            end
        end
    end
    breaking = Int[]
    position,current_class = metrics.count,1
    cost = states[position+1][current_class][1]
    while position > 0
        push!(breaking,position)
        _,position,current_class = states[position+1][current_class]
    end
    reverse(breaking),cost
end
function greedy(metrics,params)
    breaking = Int[]
    start = 0
    while start < metrics.count
        chosen = start+1
        if metrics_slack(metrics,start,chosen) >= 0
            for stop in chosen+1:metrics.count
                metrics_slack(metrics,start,stop) < 0 && break
                chosen = stop
            end
        end
        push!(breaking,chosen)
        start = chosen
    end
    breaking,breaking_cost(metrics,breaking,params)
end
break_text(metrics,method,params) = method == "kp" ? knuth_plass(metrics,params) : greedy(metrics,params)
