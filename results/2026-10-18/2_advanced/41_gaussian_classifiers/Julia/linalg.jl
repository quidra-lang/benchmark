function ordered_sum(values)
    total = 0.0
    for value in values
        total += value
    end
    total
end
dot_product(a,b) = ordered_sum(x*y for (x,y) in zip(a,b))
function cholesky_factor(matrix)
    n = size(matrix,1)
    lower = zeros(n,n)
    for i in 1:n,j in 1:i
        value = matrix[i,j]-ordered_sum(lower[i,k]*lower[j,k] for k in 1:j-1)
        lower[i,j] = i==j ? sqrt(value) : value/lower[j,j]
    end
    lower
end
function forward(lower,right)
    n = length(right)
    result = zeros(n)
    for i in 1:n
        result[i] = (right[i]-ordered_sum(lower[i,k]*result[k] for k in 1:i-1))/lower[i,i]
    end
    result
end
function backward(lower,right)
    n = length(right)
    result = zeros(n)
    for i in n:-1:1
        result[i] = (right[i]-ordered_sum(lower[k,i]*result[k] for k in i+1:n))/lower[i,i]
    end
    result
end
log_determinant(lower) = 2ordered_sum(log(lower[i,i]) for i in axes(lower,1))
function quadratic_form(lower,difference)
    transformed = forward(lower,difference)
    dot_product(transformed,transformed)
end
function jacobi(matrix)
    n = size(matrix,1)
    current = copy(matrix)
    vectors = zeros(n,n)
    for i in 1:n
        vectors[i,i] = 1.0
    end
    sweeps = 0
    while true
        off = sqrt(ordered_sum(current[a,b]^2 for a in 1:n-1 for b in a+1:n))
        (off<1e-12 || sweeps==50) && break
        for a in 1:n-1,b in a+1:n
            current[a,b]==0 && continue
            theta = (current[b,b]-current[a,a])/(2current[a,b])
            sign = theta>=0 ? 1.0 : -1.0
            t = sign/(abs(theta)+sqrt(theta*theta+1))
            co = 1/sqrt(t*t+1)
            si = t*co
            for k in 1:n
                k in (a,b) && continue
                x,y = current[k,a],current[k,b]
                current[k,a] = current[a,k] = co*x-si*y
                current[k,b] = current[b,k] = si*x+co*y
            end
            w = current[a,b]
            current[a,a] -= t*w
            current[b,b] += t*w
            current[a,b] = current[b,a] = 0.0
            for k in 1:n
                x,y = vectors[k,a],vectors[k,b]
                vectors[k,a],vectors[k,b] = co*x-si*y,si*x+co*y
            end
        end
        sweeps += 1
    end
    ([current[i,i] for i in 1:n],vectors,sweeps)
end
