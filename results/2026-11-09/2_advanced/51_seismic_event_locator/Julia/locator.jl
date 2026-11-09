const PI_VALUE = 3.141592653589793
function ordered_sum(values)
    total = 0.0
    for value in values
        total += value
    end
    total
end
function distance(solution,station)
    x,y,z = solution[1:3]
    sqrt((x-station.x)^2+(y-station.y)^2+(z+station.elevation)^2)
end
residuals(
    solution,
    observations,
    velocity
) = [o.time-solution[4]-distance(solution,o.station)/velocity for o in observations]
function location_rms(solution,observations,velocity)
    errors = residuals(solution,observations,velocity)
    sqrt(ordered_sum(r*r for r in errors)/length(errors))
end
function grid_search(observations,params)
    velocity = params["velocity"][1]
    ranges = [Int(values[1]):Int(values[3]):Int(values[2]) for values in (
        params["grid_x"],
        params["grid_y"],
        params["grid_z"]
    )]
    best,best_error = zeros(4),Inf
    profile = Dict(z=>Inf for z in ranges[3])
    for x in ranges[1],y in ranges[2],z in ranges[3]
        solution = Float64[x,y,z,0]
        deltas = [o.time-distance(solution,o.station)/velocity for o in observations]
        origin = ordered_sum(deltas)/length(deltas)
        error = ordered_sum((value-origin)*(value-origin) for value in deltas)
        if error<best_error
            best,best_error = Float64[x,y,z,origin],error
        end
        error<profile[z] && (profile[z]=error)
    end
    (
        solution=best,
        rms=sqrt(best_error/length(observations)),
        profile=[sqrt(profile[z]/length(observations)) for z in ranges[3]]
    )
end
function cholesky_lower(matrix)
    n = size(matrix,1)
    lower = zeros(n,n)
    for a in 1:n,c in 1:a
        total = ordered_sum(lower[a,j]*lower[c,j] for j in 1:c-1)
        value = matrix[a,c]-total
        lower[a,c] = a==c ? sqrt(value) : value/lower[c,c]
    end
    lower
end
function cholesky_solve(lower,right)
    n = length(right)
    forward,solution = zeros(n),zeros(n)
    for a in 1:n
        forward[a] = (right[a]-ordered_sum(lower[a,j]*forward[j] for j in 1:a-1))/lower[a,a]
    end
    for a in n:-1:1
        solution[a] = (forward[a]-ordered_sum(lower[j,a]*solution[j] for j in a+1:n))/lower[a,a]
    end
    solution
end
function normals(solution,observations,velocity)
    matrix,right = zeros(4,4),zeros(4)
    errors = residuals(solution,observations,velocity)
    x,y,z = solution[1:3]
    for (o,error) in zip(observations,errors)
        station = o.station
        d = distance(solution,station)
        g = [(x-station.x)/(velocity*d),(y-station.y)/(velocity*d),(z+station.elevation)/(velocity*d),1.0]
        for a in 1:4
            right[a] += g[a]*error
            for c in 1:4
                matrix[a,c] += g[a]*g[c]
            end
        end
    end
    matrix,right
end
function geiger(initial,observations,velocity)
    solution,trace = copy(initial),NamedTuple[]
    for iteration in 1:8
        matrix,right = normals(solution,observations,velocity)
        delta = cholesky_solve(cholesky_lower(matrix),right)
        for a in 1:4
            solution[a] += delta[a]
        end
        solution[3] = max(solution[3],0.0)
        push!(
            trace,
            (number=iteration,solution=copy(solution),rms=location_rms(solution,observations,velocity))
        )
    end
    (
        solution=solution,
        trace=trace,
        residuals=residuals(solution,observations,velocity),
        rms=location_rms(solution,observations,velocity)
    )
end
function run_location(observations,params)
    grid = grid_search(observations,params)
    refined = geiger(grid.solution,observations,params["velocity"][1])
    (;refined...,grid=grid)
end
function error_ellipse(solution,observations,velocity)
    matrix,_ = normals(solution,observations,velocity)
    lower = cholesky_lower(matrix)
    inverse = zeros(4,4)
    for c in 1:4
        right = [a==c ? 1.0 : 0.0 for a in 1:4]
        inverse[:,c] = cholesky_solve(lower,right)
    end
    variance = ordered_sum(r*r for r in residuals(solution,observations,velocity))/(length(observations)-4)
    covariance = variance.*inverse
    xx,yy,xy = covariance[1,1],covariance[2,2],covariance[1,2]
    midpoint = (xx+yy)/2
    radius = sqrt(((xx-yy)/2)^2+xy*xy)
    theta = atan(2xy,xx-yy)/2*180/PI_VALUE
    azimuth = 90-theta
    azimuth>=180 && (azimuth-=180)
    (
        smaj=sqrt(midpoint+radius),
        smin=sqrt(midpoint-radius),
        az=azimuth,
        erz=sqrt(covariance[3,3]),
        ert=sqrt(covariance[4,4])
    )
end
