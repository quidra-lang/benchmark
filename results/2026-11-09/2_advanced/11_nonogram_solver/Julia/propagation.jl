module Propagation
using ..LineSolver
export SolveStep, PropagationResult, line_label, line_cells, determined_count, propagate!, step_text
struct SolveStep
    is_row::Bool
    index::Int
    gain::Int
    contradiction::Bool
end
struct PropagationResult
    steps::Vector{SolveStep}
    conflict::Union{Nothing,SolveStep}
end
line_label(is_row, index) = "$(is_row ? "R" : "C")$index"
step_text(step) = line_label(step.is_row, step.index) * (step.contradiction ? "!" : "+$(step.gain)")
line_cells(grid, is_row, index) = is_row ? grid[index, :] : grid[:, index]
determined_count(grid) = count(!=(UNKNOWN), grid)
function propagate!(grid, row_clues, column_clues, precise, row_marks, column_marks)
    steps = SolveStep[]
    while true
        index = findfirst(row_marks)
        is_row = index !== nothing
        !is_row && (index = findfirst(column_marks))
        index === nothing && return PropagationResult(steps, nothing)
        if is_row
            row_marks[index] = false
            clue = row_clues[index]
        else
            column_marks[index] = false
            clue = column_clues[index]
        end
        cells = line_cells(grid, is_row, index)
        solved = solve_line(cells, clue, precise)
        if solved === nothing
            step = SolveStep(is_row, index, 0, true)
            push!(steps, step)
            return PropagationResult(steps, step)
        end
        gain = 0
        for position in eachindex(solved)
            (cells[position] != UNKNOWN || solved[position] == UNKNOWN) && continue
            gain += 1
            if is_row
                grid[index, position] = solved[position]
                column_marks[position] = true
            else
                grid[position, index] = solved[position]
                row_marks[position] = true
            end
        end
        push!(steps, SolveStep(is_row, index, gain, false))
    end
end
end
