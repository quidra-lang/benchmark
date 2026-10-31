local M = {}
local steps = {{0, 1}, {1, 0}}

local function starts_run(grid, row, column, step)
    return grid:is_open(row, column) and not grid:is_open(row - step[1], column - step[2])
end

local function run_length(grid, row, column, step)
    local length = 0
    while grid:is_open(row + length * step[1], column + length * step[2]) do length = length + 1 end
    return length
end

function M.find_short_run(grid)
    for row = 0, grid.height - 1 do
        for column = 0, grid.width - 1 do
            for direction, step in ipairs(steps) do
                if starts_run(grid, row, column, step) and run_length(grid, row, column, step) == 2 then
                    return grid:cell(row, column), direction == 1 and "across" or "down"
                end
            end
        end
    end
    return nil
end

local Layout = {}
Layout.__index = Layout

function Layout.new(grid)
    local self = setmetatable({grid = grid, numbers = {}, slots = {}, across_slot = {}, down_slot = {}}, Layout)
    local number = 0
    for row = 0, grid.height - 1 do
        for column = 0, grid.width - 1 do
            for direction, step in ipairs(steps) do
                if starts_run(grid, row, column, step) then
                    local length = run_length(grid, row, column, step)
                    if length >= 3 then
                        local start = grid:cell(row, column)
                        if not self.numbers[start] then number = number + 1 self.numbers[start] = number end
                        local cells, index = {}, #self.slots + 1
                        for offset = 0, length - 1 do cells[#cells + 1] = grid:cell(row + offset * step[1], column + offset * step[2]) end
                        local slot = {index = index, number = self.numbers[start], across = direction == 1,
                            cells = cells, length = length, label = self.numbers[start] .. (direction == 1 and "A" or "D"), crossings = {}}
                        self.slots[index] = slot
                        local owners = slot.across and self.across_slot or self.down_slot
                        for _, cell in ipairs(cells) do owners[cell] = index end
                    end
                end
            end
        end
    end
    for _, slot in ipairs(self.slots) do
        local owners = slot.across and self.down_slot or self.across_slot
        for _, cell in ipairs(slot.cells) do
            if owners[cell] then slot.crossings[#slot.crossings + 1] = owners[cell] end
        end
        table.sort(slot.crossings)
    end
    return self
end

function Layout:owner_count(cell)
    return (self.across_slot[cell] and 1 or 0) + (self.down_slot[cell] and 1 or 0)
end

function Layout:orphan_cell()
    for _, cell in ipairs(self.grid:white_cells()) do if self:owner_count(cell) == 0 then return cell end end
    return nil
end

M.Layout = Layout
return M
