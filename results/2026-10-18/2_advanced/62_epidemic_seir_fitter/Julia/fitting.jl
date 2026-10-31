const PHI = 0.6180339887498949
function golden(objective,a,b,iterations)
    c,d = b-PHI*(b-a),a+PHI*(b-a)
    fc,fd = objective(c),objective(d)
    records = [(a,b,c,d,fc,fd)]
    for _ in 1:iterations
        if fc<fd
            b,d,fd = d,c,fc
            c = b-PHI*(b-a)
            fc = objective(c)
        else
            a,c,fc = c,d,fd
            d = a+PHI*(b-a)
            fd = objective(d)
        end
        push!(records,(a,b,c,d,fc,fd))
    end
    point,value = fc<fd ? (c,fc) : (d,fd)
    (point=point,value=value,records=records)
end
function nelder_mead(objective,beta,gamma,delta_beta,delta_gamma,alpha,chi,psi,omega,iterations)
    vertices = [(
        number=i-1,
        beta=point[1],
        gamma=point[2],
        value=objective(point...)
    ) for (i,point) in enumerate(((beta,gamma),(beta+delta_beta,gamma),(beta,gamma+delta_gamma)))]
    initial,serial,records = copy(vertices),3,NamedTuple[]
    vertex_key(vertex) = (vertex.value,vertex.number)
    toward(origin,target,factor) = ntuple(axis->origin[axis]+factor*(target[axis]-origin[axis]),2)
    for _ in 1:iterations
        sort!(vertices;by=vertex_key)
        first,second,third = vertices
        centroid = ((first.beta+second.beta)/2,(first.gamma+second.gamma)/2)
        reflected = (centroid[1]+alpha*(centroid[1]-third.beta),centroid[2]+alpha*(centroid[2]-third.gamma))
        fr = objective(reflected...)
        accepted,value,operation = nothing,0.0,"shrink"
        if fr<first.value
            expanded = toward(centroid,reflected,chi)
            fe = objective(expanded...)
            accepted,value,operation = fe<fr ? (expanded,fe,"expand") : (reflected,fr,"reflect")
        elseif fr<second.value
            accepted,value,operation = reflected,fr,"reflect"
        elseif fr<third.value
            contracted = toward(centroid,reflected,psi)
            fc = objective(contracted...)
            fc<=fr && ((accepted,value,operation)=(contracted,fc,"contract_out"))
        else
            contracted = toward(centroid,(third.beta,third.gamma),psi)
            fc = objective(contracted...)
            fc<third.value && ((accepted,value,operation)=(contracted,fc,"contract_in"))
        end
        if isnothing(accepted)
            vertices = [first]
            for vertex in (second,third)
                point = toward((first.beta,first.gamma),(vertex.beta,vertex.gamma),omega)
                push!(vertices,(number=serial,beta=point[1],gamma=point[2],value=objective(point...)))
                serial += 1
            end
        else
            vertices = [first,second,(number=serial,beta=accepted[1],gamma=accepted[2],value=value)]
            serial += 1
        end
        sort!(vertices;by=vertex_key)
        push!(records,(operation=operation,vertex=vertices[1]))
    end
    (initial=initial,records=records,vertices=vertices)
end
