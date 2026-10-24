local function laplace(matrix)
    local n = #matrix
    if n == 1 then return matrix[1][1] end
    local total = 0
    for j = 1,n do
        local minor = {}
        for row = 2,n do
            local values = {table.unpack(matrix[row])}
            table.remove(values,j)
            minor[#minor+1] = values
        end
        local term = matrix[1][j]*laplace(minor)
        total = total + (j%2 == 1 and term or -term)
    end
    return total
end
local matrices = {{{2,-3,1},{5,4,-2},{-1,6,3}},{{3,0,-2,5},{1,4,7,-3},{-6,2,1,8},{9,-5,3,2}},{{4,-1,7,0,-3},{2,8,-5,6,1},{-9,3,2,-4,5},{6,0,-7,3,-2},{1,-6,4,9,8}}}
for _, matrix in ipairs(matrices) do io.write(string.format("det(%dx%d) = %d\n",#matrix,#matrix,laplace(matrix))) end
