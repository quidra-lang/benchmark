local Grid = {}
Grid.__index = Grid

function Grid.new(rows)
    return setmetatable({rows = rows, height = #rows, width = #rows[1], cells = table.concat(rows)}, Grid)
end

function Grid:size() return self.height * self.width end
function Grid:cell(row, column) return row * self.width + column + 1 end
function Grid:location(cell) return (cell - 1) // self.width + 1, (cell - 1) % self.width + 1 end

function Grid:is_open(row, column)
    return row >= 0 and row < self.height and column >= 0 and column < self.width and self.rows[row + 1]:sub(column + 1, column + 1) ~= "#"
end

function Grid:is_given(cell)
    local symbol = self.cells:sub(cell, cell)
    return symbol ~= "#" and symbol ~= "."
end

function Grid:white_cells()
    local cells = {}
    for cell = 1, self:size() do
        if self.cells:sub(cell, cell) ~= "#" then cells[#cells + 1] = cell end
    end
    return cells
end

function Grid:asymmetric_cell(symmetry)
    for row = 0, self.height - 1 do
        for column = 0, self.width - 1 do
            local other_row = symmetry == "rot180" and self.height - 1 - row or row
            local other_column = self.width - 1 - column
            if self:is_open(row, column) ~= self:is_open(other_row, other_column) then return self:cell(row, column) end
        end
    end
    return nil
end

function Grid:component_count()
    local seen, count = {}, 0
    for _, start in ipairs(self:white_cells()) do
        if not seen[start] then
            count = count + 1
            seen[start] = true
            local stack = {start}
            while #stack > 0 do
                local cell = table.remove(stack)
                local row, column = (cell - 1) // self.width, (cell - 1) % self.width
                for _, move in ipairs({{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) do
                    local nr, nc = row + move[1], column + move[2]
                    if self:is_open(nr, nc) then
                        local neighbor = self:cell(nr, nc)
                        if not seen[neighbor] then seen[neighbor] = true stack[#stack + 1] = neighbor end
                    end
                end
            end
        end
    end
    return count
end

return Grid
