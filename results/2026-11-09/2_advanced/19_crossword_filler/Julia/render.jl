function decimal_text(numerator, denominator, places)
    scale = 10^places
    rounded = div(2 * numerator * scale + denominator, 2 * denominator)
    string(div(rounded, scale)) * "." * lpad(string(mod(rounded, scale)), places, '0')
end
grid_lines(grid, letters) = [join(letters[(row - 1) * grid.width + 1:row * grid.width]) for row in 1:grid.height]
function number_lines(layout)
    grid = layout.grid
    lines = String[]
    for row in 1:grid.height
        marks = String[]
        for column in 1:grid.width
            index = cell(grid, row, column)
            push!(marks, grid.cells[index] == '#' ? "##" : haskey(layout.numbers, index) ? lpad(string(layout.numbers[index]), 2, ' ') : " .")
        end
        push!(lines, join(marks, " "))
    end
    lines
end
list_line(slot, clue, entry, score, theme) = "$(slot.number). $clue ($(length(slot.cells))) $entry $score" * (theme ? " theme" : "")
