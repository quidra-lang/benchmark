function smoothing_recurse(name,values,season,parameters)
    alpha = parameters[:alpha]
    beta,phi,gamma = get(parameters,:beta,0.0),get(parameters,:phi,1.0),get(parameters,:gamma,0.0)
    seasonal = name in ("hw_add","hw_mult")
    if seasonal
        level = ordered_sum(values[1:season])/season
        slope = (ordered_sum(values[(season+1):(2*season)])/season-level)/season
        components = name == "hw_add" ? values[1:season] .- level : values[1:season] ./ level
    else
        level = values[1]
        slope = name == "ses" ? 0.0 : (values[season+1]-values[1])/season
        components = nothing
    end
    states = NamedTuple[]
    errors = Float64[]
    for (t,observed) in enumerate(values)
        push!(states,(level=level,slope=slope,components=isnothing(components) ? nothing : copy(components)))
        if name == "ses"
            predicted = level
            next_level = alpha*observed+(1-alpha)*level
            next_slope = slope
        elseif seasonal
            position = (t-1)%season+1
            previous = components[position]
            base = level+slope
            if name == "hw_add"
                predicted = base+previous
                next_level = alpha*(observed-previous)+(1-alpha)*base
                components[position] = gamma*(observed-base)+(1-gamma)*previous
            else
                predicted = base*previous
                next_level = alpha*(observed/previous)+(1-alpha)*base
                components[position] = gamma*(observed/base)+(1-gamma)*previous
            end
            next_slope = beta*(next_level-level)+(1-beta)*slope
        else
            predicted = level+phi*slope
            next_level = alpha*observed+(1-alpha)*predicted
            next_slope = beta*(next_level-level)+(1-beta)*phi*slope
        end
        push!(errors,observed-predicted)
        level,slope = next_level,next_slope
    end
    push!(states,(level=level,slope=slope,components=isnothing(components) ? nothing : copy(components)))
    errors,states
end
function smoothing_forecast(name,state,parameters,origin,steps,season)
    level,slope,components = state.level,state.slope,state.components
    name == "ses" && return fill(level,steps)
    result = Float64[]
    if name in ("holt","damped")
        phi = get(parameters,:phi,1.0)
        power,accumulated = phi,0.0
        for _ in 1:steps
            accumulated += power
            push!(result,level+accumulated*slope)
            power *= phi
        end
    else
        for step in 1:steps
            component = components[(origin+step-1)%season+1]
            base = level+step*slope
            push!(result,name == "hw_add" ? base+component : base*component)
        end
    end
    result
end
