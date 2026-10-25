module PuzzleSearch
using ..LineSolver, ..Propagation
export Guess, SearchResult, guess_cell, search!
struct Guess
    number::Int
    depth::Int
    row::Int
    column::Int
    value::Int
    solves::Int
    known::Int
    result::String
end
Base.@kwdef mutable struct SearchResult
    guesses::Vector{Guess} = Guess[]
    solutions::Vector{Matrix{Int}} = Matrix{Int}[]
    backtracks::Int = 0
    max_depth::Int = 0
    line_solves::Int = 0
end
function guess_cell(grid)
    h, w = size(grid)
    rows = [count(==(UNKNOWN), grid[r, :]) for r in 1:h]
    columns = [count(==(UNKNOWN), grid[:, c]) for c in 1:w]
    best = nothing
    score = 0
    for r in 1:h, c in 1:w
        grid[r, c] == UNKNOWN || continue
        value = rows[r]+columns[c]
        if best === nothing || value < score
            best, score = (r, c), value
        end
    end
    best
end
function search!(result, grid, rows, columns, depth=1)
    r, c = guess_cell(grid)
    h, w = size(grid)
    for value in (FILLED, EMPTY)
        child = copy(grid)
        child[r, c] = value
        row_marks, column_marks = falses(h), falses(w)
        row_marks[r] = column_marks[c] = true
        propagation = propagate!(child, rows, columns, true, row_marks, column_marks)
        known = determined_count(child)
        if propagation.conflict !== nothing
            step = propagation.conflict
            text = "contradiction at=" * line_label(step.is_row, step.index)
            result.backtracks += 1
        elseif known == h*w
            push!(result.solutions, child)
            text = "solution$(length(result.solutions))"
        else
            text = "open"
        end
        push!(result.guesses, Guess(length(result.guesses)+1, depth, r, c, value, length(propagation.steps), known, text))
        result.max_depth = max(result.max_depth, depth)
        result.line_solves += length(propagation.steps)
        if text == "open"
            search!(result, child, rows, columns, depth+1) && return true
        elseif length(result.solutions) == 2
            return true
        end
    end
    false
end
end
