local M = {}
function M.cell(mesh, row, column) return row * mesh.width + column + 1 end
function M.coordinates(mesh, point) return (point - 1) // mesh.width, (point - 1) % mesh.width end
function M.read()
    local input = assert(io.open('input/plate.txt', 'r'))
    local w, h, dx, d = input:read('*l'):match('(%S+) (%S+) (%S+) (%S+)')
    local mesh = {width = tonumber(w), height = tonumber(h), dx = tonumber(dx) + 0.0, thickness = tonumber(d) + 0.0, codes = {}, neighbors = {}}
    mesh.count = mesh.width * mesh.height
    for line in input:lines() do for i = 1, #line do mesh.codes[#mesh.codes + 1] = line:sub(i, i) end end
    input:close()
    for row = 0, mesh.height - 1 do
        for column = 0, mesh.width - 1 do
            local point = M.cell(mesh, row, column)
            mesh.neighbors[point] = {column > 0 and point - 1 or 0, column + 1 < mesh.width and point + 1 or 0,
                row > 0 and point - mesh.width or 0, row + 1 < mesh.height and point + mesh.width or 0}
        end
    end
    return mesh
end
function M.segment_faces(mesh, edge, first, last)
    local result = {}
    for coordinate = first, last do
        if edge == 'top' then result[#result + 1] = {M.cell(mesh, 0, coordinate), 3}
        elseif edge == 'bottom' then result[#result + 1] = {M.cell(mesh, mesh.height - 1, coordinate), 4}
        elseif edge == 'left' then result[#result + 1] = {M.cell(mesh, coordinate, 0), 1}
        else result[#result + 1] = {M.cell(mesh, coordinate, mesh.width - 1), 2} end
    end
    return result
end
function M.source_cells(mesh, first_row, first_column, last_row, last_column)
    local result = {}
    for row = first_row, last_row do
        for column = first_column, last_column do result[#result + 1] = M.cell(mesh, row, column) end
    end
    return result
end
return M
