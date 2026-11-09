mutable struct Minstd
    state::Int
end
function draw!(rng)
    rng.state = 48271*rng.state % 2147483647
end
function shuffle_order!(order,rng)
    for i in length(order):-1:2
        k = draw!(rng)%i+1
        order[i],order[k] = order[k],order[i]
    end
    order
end
function gradient_descent(x,y,lambda,rate,iterations)
    w = zeros(length(x[1]))
    checkpoints = [(0,copy(w))]
    for t in 1:iterations
        w = w .- rate .* gradient(w,x,y,lambda)
        t%100 == 0 && push!(checkpoints,(t,copy(w)))
    end
    checkpoints
end
function stochastic_gradient_descent(x,y,lambda,rate,batch_size,epochs,seed)
    rng = Minstd(seed)
    order = collect(eachindex(x))
    w = zeros(length(x[1]))
    checkpoints = [(0,copy(w))]
    for epoch in 1:epochs
        shuffle_order!(order,rng)
        for start in 1:batch_size:length(order)
            batch = order[start:min(start+batch_size-1,length(order))]
            w = w .- rate .* gradient(w,x[batch],y[batch],lambda)
        end
        push!(checkpoints,(epoch,copy(w)))
    end
    checkpoints
end
function cholesky_lower(matrix)
    count = size(matrix,1)
    lower = zeros(count,count)
    for j in 1:count,i in j:count
        total = 0.0
        for k in 1:(j-1)
            total += lower[i,k]*lower[j,k]
        end
        remainder = matrix[i,j]-total
        lower[i,j] = i == j ? sqrt(remainder) : remainder/lower[j,j]
    end
    lower
end
function solve_lower(lower,values)
    count = length(values)
    middle,solution = zeros(count),zeros(count)
    for i in 1:count
        total = 0.0
        for k in 1:(i-1)
            total += lower[i,k]*middle[k]
        end
        middle[i] = (values[i]-total)/lower[i,i]
    end
    for i in count:-1:1
        total = 0.0
        for k in (i+1):count
            total += lower[k,i]*solution[k]
        end
        solution[i] = (middle[i]-total)/lower[i,i]
    end
    solution
end
function newton_direction(w,x,y,lambda)
    g = gradient(w,x,y,lambda)
    g,solve_lower(cholesky_lower(hessian(w,x,lambda)),g)
end
function newton_method(x,y,lambda)
    w = zeros(length(x[1]))
    checkpoints = [(0,copy(w))]
    for t in 1:10
        _,step = newton_direction(w,x,y,lambda)
        w = w .- step
        push!(checkpoints,(t,copy(w)))
    end
    checkpoints
end
