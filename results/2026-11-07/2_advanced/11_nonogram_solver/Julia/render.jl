module Render
using ..LineSolver, ..Clues
export state_char, char_state, state_string, grid_display, answer_sheet
state_char(state) = state == UNKNOWN ? '?' : state == FILLED ? '#' : '.'
char_state(ch) = ch == '?' ? UNKNOWN : ch == '#' ? FILLED : EMPTY
state_string(cells) = join(state_char(state) for state in cells)
function grid_display(names, grids)
    lines = ["grid " * join(names, " ")]
    for r in axes(grids[1], 1)
        push!(lines, join((state_string(grid[r, :]) for grid in grids), " | "))
    end
    lines
end
function answer_sheet(rows, columns, grid)
    tokens = [split(spaced(clue)) for clue in columns]
    width = maximum(length(token) for column in tokens for token in column)+1
    depth = maximum(length, tokens)
    margin = maximum(length(spaced(clue)) for clue in rows)
    lines = String[]
    for t in 1:depth
        text = repeat(" ", margin)
        for column in tokens
            skipped = depth-length(column)
            text *= t > skipped ? lpad(column[t-skipped], width) : repeat(" ", width)
        end
        push!(lines, rstrip(text, ' '))
    end
    for r in eachindex(rows)
        text = lpad(spaced(rows[r]), margin) * join(repeat(" ", width-1) * state_char(state) for state in grid[r, :])
        push!(lines, text)
    end
    lines
end
end
