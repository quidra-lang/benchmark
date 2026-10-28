ordered_total(values) = foldl(+,values;init=0.0)
function diagonal_matrix(values)
    result = zeros(length(values),length(values))
    for i in eachindex(values)
        result[i,i] = values[i]
    end
    result
end
identity_matrix(n) = diagonal_matrix(ones(n))
function matrix_product(a,b)
    [ordered_total(a[i,k]*b[k,j] for k in axes(a,2)) for i in axes(a,1),j in axes(b,2)]
end
matrix_vector(a,vector) = [ordered_total(a[i,k]*vector[k] for k in axes(a,2)) for i in axes(a,1)]
function matrix_inverse(a)
    n = size(a,1)
    augmented = [a identity_matrix(n)]
    for column in 1:n
        pivot = augmented[column,column]
        for j in 1:2n
            augmented[column,j] /= pivot
        end
        for row in 1:n
            row==column && continue
            factor = augmented[row,column]
            for j in 1:2n
                augmented[row,j] -= factor*augmented[column,j]
            end
        end
    end
    augmented[:,n+1:end]
end
determinant2(a) = a[1,1]*a[2,2]-a[1,2]*a[2,1]
quadratic2(v,a) = v[1]*(a[1,1]*v[1]+a[1,2]*v[2])+v[2]*(a[2,1]*v[1]+a[2,2]*v[2])
