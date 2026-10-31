using Printf

function solve_system(matrix)
    n = size(matrix, 1)
    for k = 1:n
        pivot = k-1 + argmax(abs.(matrix[k:n, k]))
        if pivot != k
            matrix[k, :], matrix[pivot, :] = matrix[pivot, :], matrix[k, :]
        end
        for i = (k+1):n
            factor = matrix[i, k]/matrix[k, k]
            for j = k:(n+1)
                matrix[i, j] = matrix[i, j]-factor*matrix[k, j]
            end
        end
    end
    solution = zeros(Float64, n)
    for i = n:-1:1
        subtotal = matrix[i, n+1]
        for j = (i+1):n
            subtotal = subtotal-matrix[i, j]*solution[j]
        end
        solution[i] = subtotal/matrix[i, i]
    end
    return solution
end

systems = [
    [2.0 -1 3 7; 4 1 -2 3; -3 5 1 -4],
    [1.0 3 -2 4 6; 5 -2 1 3 -7; -2 4 6 -1 9; 3 1 -4 2 5],
]
for (number, matrix) in enumerate(systems)
    println("system ", number, ":")
    for (i, value) in enumerate(solve_system(matrix))
        @printf("x%d = %.4f\n", i, value)
    end
end
