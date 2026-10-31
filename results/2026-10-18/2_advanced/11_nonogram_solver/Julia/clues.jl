module Clues
using ..LineSolver
export is_clue_line, parse_clue, run_clue, spaced, comma_separated, span, fits
is_clue_line(text) = !isempty(text) && all(c -> c == ' ' || '0' <= c <= '9', text)
function parse_clue(text)
    text == "0" && return Int[]
    tokens = split(text, ' '; keepempty=true)
    all(t -> 1 <= length(t) <= 2 && '1' <= t[1] <= '9' && all(c -> '0' <= c <= '9', t), tokens) || return nothing
    parse.(Int, tokens)
end
function run_clue(cells)
    clue = Int[]
    count = 0
    for state in cells
        if state == FILLED
            count += 1
        elseif count > 0
            push!(clue, count)
            count = 0
        end
    end
    count > 0 && push!(clue, count)
    clue
end
spaced(clue) = isempty(clue) ? "0" : join(clue, " ")
comma_separated(clue) = isempty(clue) ? "0" : join(clue, ",")
span(clue) = sum(clue)+length(clue)-1
fits(clue, count) = span(clue) <= count
end
