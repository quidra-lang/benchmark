function ordered_sum(values)
    total = 0.0
    for value in values
        total += value
    end
    total
end
score(weights,vector) = ordered_sum(w*x for (w,x) in zip(weights,vector))
function probability(u)
    u >= 0 && return 1.0/(1.0+exp(-u))
    e = exp(u)
    e/(1.0+e)
end
logistic_loss(u,y) = max(u,0.0)-y*u+log(1.0+exp(-abs(u)))
average_loss(w,x,y) = ordered_sum(logistic_loss(score(w,v),t) for (v,t) in zip(x,y))/length(x)
penalty(w) = ordered_sum(v*v for v in w[2:end])
objective(w,x,y,lambda) = average_loss(w,x,y)+lambda*penalty(w)/2
function gradient(w,x,y,lambda)
    totals = zeros(length(w))
    for (v,t) in zip(x,y)
        error = probability(score(w,v))-t
        for j in eachindex(w)
            totals[j] += error*v[j]
        end
    end
    [totals[j]/length(x)+(j == 1 ? 0.0 : lambda*w[j]) for j in eachindex(w)]
end
function hessian(w,x,lambda)
    size = length(w)
    totals = zeros(size,size)
    for v in x
        pi = probability(score(w,v))
        variance = pi*(1.0-pi)
        for j in 1:size,k in 1:j
            totals[j,k] += variance*v[j]*v[k]
        end
    end
    matrix = zeros(size,size)
    for j in 1:size,k in 1:j
        value = totals[j,k]/length(x)
        j == k && j >= 2 && (value+=lambda)
        matrix[j,k] = matrix[k,j] = value
    end
    matrix
end
