mutable struct RandomGenerator
    state::Int
end
function draw!(generator)
    generator.state = (48271generator.state)%2147483647
end
factor!(generator) = ((draw!(generator)%2001)-1000)/10000
dot_product(a,b) = sequential_sum(x*y for (x,y) in zip(a,b))
factor_prediction(model,u,i) = ((model.mean+model.user_bias[u])+model.item_bias[i])+dot_product(
    model.users[u,:],
    model.items[i,:]
)
function train_svd(data)
    params = data.params
    random = RandomGenerator(Int(params["SEED"][1]))
    f = Int(params["FACTORS"][1])
    users,items = zeros(length(data.users),f),zeros(length(data.items),f)
    for u in axes(users,1),a in 1:f
        users[u,a] = factor!(random)
    end
    for i in axes(items,1),a in 1:f
        items[i,a] = factor!(random)
    end
    user_bias,item_bias = zeros(length(data.users)),zeros(length(data.items))
    model = (mean=data.mean,users=users,items=items,user_bias=user_bias,item_bias=item_bias)
    order = collect(eachindex(data.training))
    rate,regularization = params["LEARNING_RATE"][1],params["REGULARIZATION"][1]
    log = Tuple{String,Int,Float64}[]
    for epoch in 1:Int(params["EPOCHS"][1])
        for position in length(order):-1:2
            other = draw!(random)%position+1
            order[position],order[other] = order[other],order[position]
        end
        for position in order
            r = data.training[position]
            u,i = r.u,r.i
            error = r.rating-factor_prediction(model,u,i)
            user_bias[u] += rate*(error-regularization*user_bias[u])
            item_bias[i] += rate*(error-regularization*item_bias[i])
            for a in 1:f
                x,y = users[u,a],items[i,a]
                users[u,a],items[i,a] = x+rate*(error*y-regularization*x),y+rate*(error*x-regularization*y)
            end
        end
        push!(log,("SVD",epoch,training_rmse(data.training,(u,i)->factor_prediction(model,u,i))))
    end
    model,log
end
function cholesky_solve(matrix,target)
    n = length(target)
    lower = zeros(n,n)
    for a in 1:n,b in 1:a
        value = matrix[a,b]-sequential_sum(lower[a,t]*lower[b,t] for t in 1:b-1)
        lower[a,b] = a==b ? sqrt(value) : value/lower[b,b]
    end
    z = zeros(n)
    for a in 1:n
        z[a] = (target[a]-sequential_sum(lower[a,t]*z[t] for t in 1:a-1))/lower[a,a]
    end
    x = zeros(n)
    for a in n:-1:1
        x[a] = (z[a]-sequential_sum(lower[t,a]*x[t] for t in a+1:n))/lower[a,a]
    end
    x
end
function fit_vector(observations,f,regularization)
    matrix,target = zeros(f,f),zeros(f)
    for (vector,residual) in observations
        for a in 1:f
            target[a] += residual*vector[a]
            for b in 1:f
                matrix[a,b] += vector[a]*vector[b]
            end
        end
    end
    for a in 1:f
        matrix[a,a] += regularization*length(observations)
    end
    cholesky_solve(matrix,target)
end
function train_als(data,user_bias,item_bias)
    params = data.params
    f = Int(params["FACTORS"][1])
    random = RandomGenerator(Int(params["SEED"][1]))
    users,items = zeros(length(data.users),f),zeros(length(data.items),f)
    for i in axes(items,1),a in 1:f
        items[i,a] = factor!(random)
    end
    model = (mean=data.mean,users=users,items=items,user_bias=user_bias,item_bias=item_bias)
    residuals = [
        data.ratings[u,i]-((data.mean+user_bias[u])+item_bias[i]) for u in eachindex(data.users),
        i in eachindex(data.items)
    ]
    log = Tuple{String,Int,Float64}[]
    for iteration in 1:Int(params["ALS_ITERATIONS"][1])
        for u in eachindex(data.users)
            users[u,:] = fit_vector(
                [(items[i,:],residuals[u,i]) for i in data.by_user[u]],
                f,
                params["ALS_REG"][1]
            )
        end
        for i in eachindex(data.items)
            items[i,:] = fit_vector(
                [(users[u,:],residuals[u,i]) for u in data.by_item[i]],
                f,
                params["ALS_REG"][1]
            )
        end
        push!(log,("ALS",iteration,training_rmse(data.training,(u,i)->factor_prediction(model,u,i))))
    end
    model,log
end
