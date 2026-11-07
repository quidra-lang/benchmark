function sequential_sum(values)
    result = 0.0
    for value in values
        result += value
    end
    result
end
function identity_matrix(n)
    result = zeros(n,n)
    for i in 1:n
        result[i,i] = 1.0
    end
    result
end
dot_product(a,b) = sequential_sum(x*y for (x,y) in zip(a,b))
multiply(matrix,vector) = [dot_product(matrix[i,:],vector) for i in axes(matrix,1)]
vector_length(vector) = sqrt(dot_product(vector,vector))
normalize(vector) = vector./vector_length(vector)
orient(vector) = vector[argmax(abs.(vector))]<0 ? -vector : copy(vector)
max_difference(a,b) = maximum(abs.(a.-b))
function deflate!(matrix,value,vector)
    for i in axes(matrix,1),j in axes(matrix,2)
        matrix[i,j] -= value*vector[i]*vector[j]
    end
end
function gauss_jordan(matrix)
    n = size(matrix,1)
    augmented = hcat(matrix,identity_matrix(n))
    determinant = 1.0
    for k in 1:n
        pivot = augmented[k,k]
        determinant *= pivot
        augmented[k,:] ./= pivot
        for i in 1:n
            i==k && continue
            gamma = augmented[i,k]
            for h in 1:2n
                augmented[i,h] -= gamma*augmented[k,h]
            end
        end
    end
    augmented[:,n+1:2n],determinant
end
