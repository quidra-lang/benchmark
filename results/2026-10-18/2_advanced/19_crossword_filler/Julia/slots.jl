starts_run(grid, row, column, dr, dc) = is_open(grid, row, column) && !is_open(grid, row - dr, column - dc)

function run_length(grid, row, column, dr, dc)
    length = 0
    while is_open(grid, row + length * dr, column + length * dc)
        length += 1
    end
    length
end

function find_short_run(grid)
    for row in 1:grid.height, column in 1:grid.width
        for (dr, dc, direction) in [(0, 1, "across"), (1, 0, "down")]
            starts_run(grid, row, column, dr, dc) && run_length(grid, row, column, dr, dc) == 2 && return (cell(grid, row, column), direction)
        end
    end
    nothing
end

mutable struct Slot
    index::Int
    number::Int
    across::Bool
    cells::Vector{Int}
    label::String
    crossings::Vector{Int}
end

struct Layout
    grid::Grid
    numbers::Dict{Int,Int}
    slots::Vector{Slot}
    across_slot::Vector{Int}
    down_slot::Vector{Int}
end

function Layout(grid::Grid)
    numbers, slots = Dict{Int,Int}(), Slot[]
    across_slot, down_slot = zeros(Int, length(grid.cells)), zeros(Int, length(grid.cells))
    for row in 1:grid.height, column in 1:grid.width
        for (dr, dc, across) in [(0, 1, true), (1, 0, false)]
            starts_run(grid, row, column, dr, dc) || continue
            length = run_length(grid, row, column, dr, dc)
            length >= 3 || continue
            start = cell(grid, row, column)
            number = get!(numbers, start, Base.length(numbers) + 1)
            cells = [cell(grid, row + position * dr, column + position * dc) for position in 0:length-1]
            index = Base.length(slots) + 1
            owners = across ? across_slot : down_slot
            owners[cells] .= index
            push!(slots, Slot(index, number, across, cells, string(number) * (across ? "A" : "D"), Int[]))
        end
    end
    for slot in slots
        owners = slot.across ? down_slot : across_slot
        slot.crossings = sort([owners[index] for index in slot.cells if owners[index] != 0])
    end
    Layout(grid, numbers, slots, across_slot, down_slot)
end

owner_count(layout, cell) = Int(layout.across_slot[cell] != 0) + Int(layout.down_slot[cell] != 0)
orphan_cell(layout) = findfirst(index -> layout.grid.cells[index] != '#' && owner_count(layout, index) == 0, eachindex(layout.grid.cells))
