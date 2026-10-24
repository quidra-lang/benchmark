local a = {{3,-2,5,1},{-4,7,0,6},{2,9,-8,-3}}
local b = {{1,4},{-5,2},{6,-1},{0,7}}
for i = 1, 3 do
    for j = 1, 2 do
        local value = 0
        for k = 1, 4 do value = value + a[i][k]*b[k][j] end
        io.write(string.format("%5d", value))
    end
    io.write("\n")
end
