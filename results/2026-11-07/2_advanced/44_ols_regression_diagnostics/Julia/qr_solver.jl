function ordered_sum(values)
    result = 0.0
    for value in values
        result += value
    end
    result
end
function fit_ols(matrix,response,weights,tolerance)
    n,p = size(matrix)
    roots = sqrt.(weights)
    weighted = [roots[i]*matrix[i,j] for i in 1:n,j in 1:p]
    lengths = [sqrt(ordered_sum(weighted[i,j]*weighted[i,j] for i in 1:n)) for j in 1:p]
    work = copy(weighted)
    transformed = roots.*response
    triangular = zeros(p,p)
    accepted,aliases = Int[],Int[]
    for j in 1:p
        k = length(accepted)+1
        eta = sqrt(ordered_sum(work[i,j]*work[i,j] for i in k:n))
        if eta<=tolerance*lengths[j]
            push!(aliases,j)
            continue
        end
        push!(accepted,j)
        alpha = work[k,j]>=0 ? -eta : eta
        vector = vcat([work[k,j]-alpha],work[k+1:n,j])
        squared = ordered_sum(value*value for value in vector)
        for l in 1:k-1
            triangular[l,k] = work[l,j]
        end
        triangular[k,k] = alpha
        for l in j+1:p
            delta = 2ordered_sum(vector[i-k+1]*work[i,l] for i in k:n)/squared
            for i in k:n
                work[i,l] -= delta*vector[i-k+1]
            end
        end
        delta = 2ordered_sum(vector[i-k+1]*transformed[i] for i in k:n)/squared
        for i in k:n
            transformed[i] -= delta*vector[i-k+1]
        end
    end
    rank = length(accepted)
    triangular = triangular[1:rank,1:rank]
    effects = transformed[1:rank]
    beta = Union{Nothing,Float64}[nothing for _ in 1:p]
    for k in rank:-1:1
        tail = ordered_sum(triangular[k,l]*beta[accepted[l]] for l in k+1:rank)
        beta[accepted[k]] = (effects[k]-tail)/triangular[k,k]
    end
    inverse = zeros(rank,rank)
    for m in 1:rank,l in rank:-1:1
        diagonal = l==m ? 1.0 : 0.0
        tail = ordered_sum(triangular[l,q]*inverse[q,m] for q in l+1:rank)
        inverse[l,m] = (diagonal-tail)/triangular[l,l]
    end
    variance = [ordered_sum(inverse[k,m]*inverse[k,m] for m in 1:rank) for k in 1:rank]
    u = [ordered_sum(weighted[i,accepted[m]]*inverse[m,k] for m in 1:rank) for i in 1:n,k in 1:rank]
    leverage = [ordered_sum(u[i,k]*u[i,k] for k in 1:rank) for i in 1:n]
    g = [ordered_sum(inverse[k,m]*u[i,m] for m in 1:rank) for i in 1:n,k in 1:rank]
    fitted = [ordered_sum(matrix[i,accepted[k]]*beta[accepted[k]] for k in 1:rank) for i in 1:n]
    residual = response.-fitted
    eps = roots.*residual
    rss = ordered_sum(value*value for value in eps)
    (matrix=matrix,response=response,weights=weights,n=n,p=p,accepted=accepted,aliases=aliases,rank=rank,
     triangular=triangular,effects=effects,beta=beta,inverse=inverse,variance=variance,u=u,g=g,
     leverage=leverage,fitted=fitted,residual=residual,eps=eps,rss=rss)
end
