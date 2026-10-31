function domain_point(domains,index)
    result = Dict{String,Any}()
    for (name,values) in reverse(domains)
        result[name] = values[index%length(values)+1]
        index ÷= length(values)
    end
    result
end
domain_points(domains) = (domain_point(domains,i) for i in 0:prod((length(v) for (_,v) in domains);init=1)-1)
function day_notation(days)
    ordered = sort!(collect(days))
    first,last,runs = ordered[1],ordered[1],String[]
    for day in ordered[2:end]
        if day!=last+1
            push!(runs,"$first-$last")
            first = day
        end
        last = day
    end
    push!(runs,"$first-$last")
    join(runs,',')
end
function rule_blocker(rule,elements,standalone)
    for earlier in elements[rule.parent].children
        earlier==rule.index && break
        standalone[earlier]!=NOT_APPLICABLE && return earlier
    end
    0
end
function conflict_winner(policy,earlier,later)
    policy.behavior=="first-applicable" && return earlier.index
    effect = policy.behavior in ("deny-overrides","permit-unless-deny") ? "DENY" : "PERMIT"
    earlier.behavior==effect ? earlier.index : later.index
end
