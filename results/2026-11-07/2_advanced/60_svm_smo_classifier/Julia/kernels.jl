struct SVMKernel
    name::String
    kind::String
    degree::Int
    gamma::Float64
    coef0::Float64
end
function kernel_value(kernel,first,second)
    if kernel.kind=="rbf"
        e1,e2 = first[1]-second[1],first[2]-second[2]
        return exp(-kernel.gamma*(e1*e1+e2*e2))
    end
    product = first[1]*second[1]+first[2]*second[2]
    kernel.kind=="linear" && return product
    factor = kernel.gamma*product+kernel.coef0
    value = 1.0
    for _ in 1:kernel.degree
        value *= factor
    end
    value
end
function kernel_description(kernel)
    kernel.kind=="linear" && return "linear"
    kernel.kind=="rbf" && return "rbf gamma $(fixed_text(kernel.gamma))"
    "poly degree $(kernel.degree) gamma $(fixed_text(kernel.gamma)) coef0 $(fixed_text(kernel.coef0))"
end
kernel_matrix(kernel,points) = [kernel_value(kernel,first,second) for first in points,second in points]
submatrix(matrix,indices) = matrix[indices,indices]
