function ordered_sum(values)
    total = 0.0
    for value in values
        total += value
    end
    total
end
function heat_flow(system,field,point,directions)
    total = 0.0
    for direction in directions
        face = system.faces[point][direction]
        if face.neighbor!=0
            total += face.g*(field[face.neighbor]-field[point])
        elseif !isnothing(face.theta)
            total += face.g*(face.theta-field[point])
        end
    end
    total
end
horizontal_flow(system,field,p) = heat_flow(system,field,p,(LEFT,RIGHT))
vertical_flow(system,field,p) = heat_flow(system,field,p,(TOP,BOTTOM))
total_flow(system,field,p) = heat_flow(system,field,p,(LEFT,RIGHT,TOP,BOTTOM))
function thomas(lower,diagonal,upper,rhs)
    n = length(diagonal)
    upper_prime,rhs_prime = zeros(n),zeros(n)
    upper_prime[1],rhs_prime[1] = upper[1]/diagonal[1],rhs[1]/diagonal[1]
    for i in 2:n
        pivot = diagonal[i]-lower[i]*upper_prime[i-1]
        upper_prime[i] = upper[i]/pivot
        rhs_prime[i] = (rhs[i]-lower[i]*rhs_prime[i-1])/pivot
    end
    result = zeros(n)
    result[end] = rhs_prime[end]
    for i in n-1:-1:1
        result[i] = rhs_prime[i]-upper_prime[i]*result[i+1]
    end
    result
end
function sweep(system,tau,right_hand_side,horizontal)
    plate = system.mesh
    line_count,line_length = horizontal ? (plate.height,plate.width) : (plate.width,plate.height)
    first_face,second_face = horizontal ? (LEFT,RIGHT) : (TOP,BOTTOM)
    field = zeros(plate.count)
    for line in 0:line_count-1
        cells = [horizontal ? cell(plate,line,i) : cell(plate,i,line) for i in 0:line_length-1]
        lower,diagonal,upper,rhs = zeros(line_length),zeros(line_length),zeros(line_length),zeros(line_length)
        for (i,p) in enumerate(cells)
            first,second = system.faces[p][first_face],system.faces[p][second_face]
            lower[i] = first.neighbor!=0 ? -first.g : 0.0
            diagonal[i] = system.capacity[p]/tau+first.g+second.g
            upper[i] = second.neighbor!=0 ? -second.g : 0.0
            value = right_hand_side[p]
            isnothing(first.theta) || (value+=first.g*first.theta)
            isnothing(second.theta) || (value+=second.g*second.theta)
            rhs[i] = value
        end
        field[cells] = thomas(lower,diagonal,upper,rhs)
    end
    field
end
horizontal_sweep(system,tau,rhs) = sweep(system,tau,rhs,true)
vertical_sweep(system,tau,rhs) = sweep(system,tau,rhs,false)
function advance_field(method,system,field,source,dt)
    n = system.mesh.count
    if method=="ftcs"
        return [field[p]+dt*(total_flow(system,field,p)+source[p])/system.capacity[p] for p in 1:n],nothing
    elseif method=="backward_euler"
        vertical = [vertical_flow(system,field,p) for p in 1:n]
        rhs = [system.capacity[p]/dt*field[p]+vertical[p]+source[p] for p in 1:n]
        intermediate = horizontal_sweep(system,dt,rhs)
        rhs = [system.capacity[p]/dt*intermediate[p]-vertical[p] for p in 1:n]
        return vertical_sweep(system,dt,rhs),intermediate
    end
    tau = dt/2
    rhs = [system.capacity[p]/tau*field[p]+vertical_flow(system,field,p)+source[p] for p in 1:n]
    intermediate = horizontal_sweep(system,tau,rhs)
    rhs = [system.capacity[p]/tau*intermediate[p]+horizontal_flow(
        system,
        intermediate,
        p
    )+source[p] for p in 1:n]
    vertical_sweep(system,tau,rhs),intermediate
end
