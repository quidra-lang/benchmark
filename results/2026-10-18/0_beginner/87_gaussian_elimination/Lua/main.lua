local function solve_system(matrix)
    local n = #matrix
    for k = 1,n do
        local pivot = k
        for i = k+1,n do
            if math.abs(matrix[i][k]) > math.abs(matrix[pivot][k]) then pivot = i end
        end
        matrix[k],matrix[pivot] = matrix[pivot],matrix[k]
        for i = k+1,n do
            local factor = matrix[i][k]/matrix[k][k]
            for j = k,n+1 do matrix[i][j] = matrix[i][j]-factor*matrix[k][j] end
        end
    end
    local solution = {}
    for i = n,1,-1 do
        local subtotal = matrix[i][n+1]
        for j = i+1,n do subtotal = subtotal-matrix[i][j]*solution[j] end
        solution[i] = subtotal/matrix[i][i]
    end
    return solution
end
local systems = {{{2.0,-1.0,3.0,7.0},{4.0,1.0,-2.0,3.0},{-3.0,5.0,1.0,-4.0}},{{1.0,3.0,-2.0,4.0,6.0},{5.0,-2.0,1.0,3.0,-7.0},{-2.0,4.0,6.0,-1.0,9.0},{3.0,1.0,-4.0,2.0,5.0}}}
for number,matrix in ipairs(systems) do
    io.write(string.format("system %d:\n",number))
    for i,value in ipairs(solve_system(matrix)) do
        io.write(string.format("x%d = %.4f\n",i,value))
    end
end
