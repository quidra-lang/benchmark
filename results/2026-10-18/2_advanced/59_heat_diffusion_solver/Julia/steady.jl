function g_value(system,field,p)
    terms = Float64[]
    for face in system.faces[p]
        if face.neighbor!=0
            push!(terms,face.g*field[face.neighbor])
        elseif !isnothing(face.theta)
            push!(terms,face.g*face.theta)
        end
    end
    ordered_sum(terms)+system.source_all[p]
end
function iterate_steady(system,initial,tolerance,maximum_iterations,method,omega=1.0)
    field = fill(initial,system.mesh.count)
    changes = Float64[]
    for iteration in 1:maximum_iterations
        previous = copy(field)
        if method=="jacobi"
            field = [g_value(system,previous,p)/system.diagonal[p] for p in eachindex(field)]
        else
            for p in eachindex(field)
                value = g_value(system,field,p)/system.diagonal[p]
                field[p] = method=="gauss_seidel" ? value : field[p]+omega*(value-field[p])
            end
        end
        change = maximum(abs.(field.-previous))
        push!(changes,change)
        change<tolerance && break
    end
    (
        method=method,
        field=field,
        changes=changes,
        iterations=length(changes),
        converged=changes[end]<tolerance,
        omega=omega
    )
end
function band_solve(system,right_hand_sides)
    n,width = system.mesh.count,system.mesh.width
    matrix = zeros(n,n)
    for (p,faces) in enumerate(system.faces)
        matrix[p,p] = system.diagonal[p]
        for face in faces
            face.neighbor!=0 && (matrix[p,face.neighbor]=-face.g)
        end
    end
    vectors = copy.(right_hand_sides)
    for k in 1:n
        stop = min(n,k+width)
        for i in k+1:stop
            factor = matrix[i,k]/matrix[k,k]
            matrix[i,k] = 0.0
            for j in k+1:stop
                matrix[i,j] -= factor*matrix[k,j]
            end
            for values in vectors
                values[i] -= factor*values[k]
            end
        end
    end
    solutions = Vector{Float64}[]
    for values in vectors
        field = zeros(n)
        for i in n:-1:1
            value = values[i]
            for j in i+1:min(n,i+width)
                value -= matrix[i,j]*field[j]
            end
            field[i] = value/matrix[i,i]
        end
        push!(solutions,field)
    end
    solutions
end
function maximum_residual(system,field,rhs)
    largest = 0.0
    for (p,faces) in enumerate(system.faces)
        residual = rhs[p]
        for face in faces
            face.neighbor!=0 && (residual+=face.g*field[face.neighbor])
        end
        residual -= system.diagonal[p]*field[p]
        largest = max(largest,abs(residual))
    end
    largest
end
