function predict_height(model,time)
    result = model.mean_level
    for c in model.selected
        constant = model.constants[c.name]
        theta = tide_angle(c.speed,time)
        result += constant.a*cos(theta)+constant.b*sin(theta)
    end
    result
end
predict_hours(model,start,n) = [predict_height(model,start+i) for i in 0:n]
function find_extrema(model,start,hours,grid_minutes)
    n = hours*60÷grid_minutes
    minutes = [60start+j*grid_minutes for j in 0:n]
    heights = [predict_height(model,m/60) for m in minutes]
    extrema = NamedTuple[]
    for j in 2:n
        left,center,right = heights[j-1:j+1]
        kind = left<center>right ? "high" : left>center<right ? "low" : ""
        isempty(kind) && continue
        delta = (left-right)/(2*(left-2center+right))
        minute = minutes[j]+delta*grid_minutes
        push!(extrema,(kind=kind,minute=minute,height=center-(left-right)*delta/4))
    end
    extrema
end
