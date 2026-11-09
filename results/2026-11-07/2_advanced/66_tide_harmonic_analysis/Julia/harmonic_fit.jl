const TIDE_PI = 3.141592653589793
function tide_angle(speed,time)
    degrees = speed*time
    reduced = degrees-360*floor(degrees/360)
    reduced*TIDE_PI/180
end
function regressors(time,selected)
    vector = [1.0]
    for constituent in selected
        theta = tide_angle(constituent.speed,time)
        append!(vector,[cos(theta),sin(theta)])
    end
    vector
end
function solve_with_inverse(matrix,right)
    n = length(right)
    unit = [i==j ? 1.0 : 0.0 for i in 1:n,j in 1:n]
    augmented = [matrix right unit]
    for column in 1:n
        pivot = argmax(i->abs(augmented[i,column]),column:n)
        if pivot!=column
            augmented[[column,pivot],:] = augmented[[pivot,column],:]
        end
        for row in column+1:n
            factor = augmented[row,column]/augmented[column,column]
            for c in column:2n+1
                augmented[row,c] -= factor*augmented[column,c]
            end
        end
    end
    solutions = Vector{Float64}[]
    for column in n+1:2n+1
        solution = zeros(n)
        for i in n:-1:1
            current = augmented[i,column]
            for j in i+1:n
                current -= augmented[i,j]*solution[j]
            end
            solution[i] = current/augmented[i,i]
        end
        push!(solutions,solution)
    end
    solutions[1],[solutions[column+1][row] for row in 1:n,column in 1:n]
end
function fit(values,times,selected)
    n = 2length(selected)+1
    matrix,right = zeros(n,n),zeros(n)
    for t in times
        vector = regressors(t,selected)
        observed = values[t]
        for i in 1:n
            right[i] += vector[i]*observed
            for j in 1:n
                matrix[i,j] += vector[i]*vector[j]
            end
        end
    end
    coefficients,inverse = solve_with_inverse(matrix,right)
    constants = Dict{String,NamedTuple}()
    for (k,c) in enumerate(selected)
        a,b = coefficients[2k],coefficients[2k+1]
        amplitude = sqrt(a*a+b*b)
        phase = atan(b,a)*180/TIDE_PI
        phase<0 && (phase+=360)
        constants[c.name] = (speed=c.speed,a=a,b=b,amplitude=amplitude,phase=phase,index_a=2k,index_b=2k+1)
    end
    (
        selected=selected,
        coefficients=coefficients,
        inverse=inverse,
        mean_level=coefficients[1],
        constants=constants,
        unknowns=n
    )
end
