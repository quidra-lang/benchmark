function factor_cholesky(matrix,free)
    n = size(matrix,1)
    lower = zeros(n,n)
    for i in 1:n,j in 1:i
        w = matrix[i,j]
        for h in 1:j-1
            w -= lower[i,h]*lower[j,h]
        end
        if j<i
            lower[i,j] = w/lower[j,j]
        else
            w<=1e-9*matrix[i,i] && return nothing,free[i]
            lower[i,i] = sqrt(w)
        end
    end
    lower,0
end
function solve_cholesky(lower,right)
    n = length(right)
    intermediate,result = zeros(n),zeros(n)
    for i in 1:n
        w = right[i]
        for h in 1:i-1
            w -= lower[i,h]*intermediate[h]
        end
        intermediate[i] = w/lower[i,i]
    end
    for i in n:-1:1
        w = intermediate[i]
        for h in i+1:n
            w -= lower[h,i]*result[h]
        end
        result[i] = w/lower[i,i]
    end
    result
end
