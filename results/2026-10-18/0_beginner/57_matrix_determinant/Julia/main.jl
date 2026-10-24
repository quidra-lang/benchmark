function laplace(matrix)
    n = size(matrix,1)
    n == 1 && return matrix[1,1]
    total = 0
    for j in 1:n
        columns = [k for k in 1:n if k != j]
        term = matrix[1,j] * laplace(matrix[2:end,columns])
        total += isodd(j) ? term : -term
    end
    return total
end
matrices = [[2 -3 1; 5 4 -2; -1 6 3], [3 0 -2 5; 1 4 7 -3; -6 2 1 8; 9 -5 3 2], [4 -1 7 0 -3; 2 8 -5 6 1; -9 3 2 -4 5; 6 0 -7 3 -2; 1 -6 4 9 8]]
for matrix in matrices
    n = size(matrix,1)
    println("det(",n,"x",n,") = ",laplace(matrix))
end
