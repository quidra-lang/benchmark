local function edit_distance(a,b)
    local table_values = {}
    for i = 0,#a do table_values[i] = {[0]=i} end
    for j = 0,#b do table_values[0][j] = j end
    for i = 1,#a do
        for j = 1,#b do
            local cost = a:sub(i,i) == b:sub(j,j) and 0 or 1
            table_values[i][j] = math.min(table_values[i-1][j]+1,table_values[i][j-1]+1,table_values[i-1][j-1]+cost)
        end
    end
    return table_values[#a][#b]
end
for _, pair in ipairs({{"kitten","sitting"},{"flaw","lawn"},{"listen","silent"},{"intention","execution"},{"algorithm","altruistic"}}) do
    io.write(string.format("%s -> %s: %d\n",pair[1],pair[2],edit_distance(pair[1],pair[2])))
end
