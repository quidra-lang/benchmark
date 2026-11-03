module LineSolver
export UNKNOWN, FILLED, EMPTY, has_placement, solve_line
const UNKNOWN = 0
const FILLED = 1
const EMPTY = 2
function fit_table(cells, clue)
    n, m = length(cells), length(clue)
    empties = zeros(Int, n+1)
    for i in 1:n
        empties[i+1] = empties[i] + (cells[i] == EMPTY)
    end
    table = falses(n+1, m+1)
    table[1, 1] = true
    for last in 1:n, blocks in 0:m
        fits = cells[last] != FILLED && table[last, blocks+1]
        if !fits && blocks > 0
            first = last-clue[blocks]
            if first >= 0 && empties[last+1] == empties[first+1]
                fits = first == 0 ? blocks == 1 : cells[first] != FILLED && table[first, blocks]
            end
        end
        table[last+1, blocks+1] = fits
    end
    table
end
has_placement(cells, clue) = fit_table(cells, clue)[length(cells)+1, length(clue)+1]
struct Placements
    cells::Vector{Int}
    clue::Vector{Int}
    before::BitMatrix
    after::BitMatrix
end
Placements(cells, clue) = Placements(cells, clue, fit_table(cells, clue), fit_table(reverse(cells), reverse(clue)))
function can_start(p, block, first)
    last = first+p.clue[block]
    any(==(EMPTY), p.cells[first+1:last]) && return false
    left = first == 0 ? block == 1 : p.cells[first] != FILLED && p.before[first, block]
    rest = length(p.clue)-block
    right = last == length(p.cells) ? rest == 0 : p.cells[last+1] != FILLED && p.after[length(p.cells)-last, rest+1]
    left && right
end
starts(p, block) = [first for first in 0:length(p.cells)-p.clue[block] if can_start(p, block, first)]
function can_be_empty(p, index)
    p.cells[index+1] == FILLED && return false
    m, n = length(p.clue), length(p.cells)
    any(blocks -> p.before[index+1, blocks+1] && p.after[n-index, m-blocks+1], 0:m)
end
function solve_line(cells, clue, precise)
    p = Placements(cells, clue)
    p.before[length(cells)+1, length(clue)+1] || return nothing
    solved = copy(cells)
    covered = falses(length(cells))
    for (block, size) in enumerate(clue)
        positions = starts(p, block)
        if precise
            for first in positions, i in first+1:first+size
                covered[i] = true
            end
        else
            low, high = positions[1], positions[end]
            for i in high+1:low+size
                solved[i] == UNKNOWN && (solved[i] = FILLED)
            end
            covered[low+1:high+size] .= true
        end
    end
    for i in eachindex(cells)
        if cells[i] == UNKNOWN
            if precise
                emptiable = can_be_empty(p, i-1)
                covered[i] && !emptiable && (solved[i] = FILLED)
                emptiable && !covered[i] && (solved[i] = EMPTY)
            elseif solved[i] == UNKNOWN && !covered[i]
                solved[i] = EMPTY
            end
        end
    end
    solved
end
end
