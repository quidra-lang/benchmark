local M = {}
function M.queens(n)
    local clauses = {}
    for row = 0, n - 1 do
        local clause = {}
        for column = 1, n do
            clause[#clause + 1] = row * n + column
        end
        clauses[#clauses + 1] = clause
    end
    for a = 1, n * n do
        local ra, ca = (a - 1) // n, (a - 1) % n
        for b = a + 1, n * n do
            local rb, cb = (b - 1) // n, (b - 1) % n
            if ra == rb or ca == cb or math.abs(ra - rb) == math.abs(ca - cb) then
                clauses[#clauses + 1] = {-a, -b}
            end
        end
    end
    return n * n, clauses
end
function M.pigeon(pigeons, holes)
    local clauses = {}
    for pigeon = 0, pigeons - 1 do
        local clause = {}
        for hole = 1, holes do
            clause[#clause + 1] = pigeon * holes + hole
        end
        clauses[#clauses + 1] = clause
    end
    for pigeon = 0, pigeons - 1 do
        for first = 1, holes do
            for second = first + 1, holes do
                clauses[#clauses + 1] = {-(pigeon * holes + first), -(pigeon * holes + second)}
            end
        end
    end
    for hole = 1, holes do
        for first = 0, pigeons - 1 do
            for second = first + 1, pigeons - 1 do
                clauses[#clauses + 1] = {-(first * holes + hole), -(second * holes + hole)}
            end
        end
    end
    return pigeons * holes, clauses
end
function M.coloring(vertices, edges, colors)
    local clauses = {}
    for vertex = 0, vertices - 1 do
        local clause = {}
        for color = 1, colors do
            clause[#clause + 1] = vertex * colors + color
        end
        clauses[#clauses + 1] = clause
    end
    for vertex = 0, vertices - 1 do
        for first = 1, colors do
            for second = first + 1, colors do
                clauses[#clauses + 1] = {-(vertex * colors + first), -(vertex * colors + second)}
            end
        end
    end
    for _, edge in ipairs(edges) do
        for color = 1, colors do
            clauses[#clauses + 1] = {-((edge[1] - 1) * colors + color), -((edge[2] - 1) * colors + color)}
        end
    end
    return vertices * colors, clauses
end
function M.positions(model, rows, width)
    local positions = {}
    for row = 0, rows - 1 do
        for column = 1, width do
            if model[row * width + column] then
                positions[#positions + 1] = column
                break
            end
        end
    end
    return positions
end
return M
