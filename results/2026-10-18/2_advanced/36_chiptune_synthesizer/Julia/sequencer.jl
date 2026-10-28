samples_per_tick(rate,tempo) = rate*5÷(tempo*2)
function next_row(song,position,row)
    jump,pattern_break = nothing,nothing
    for cell in song_cells(song,position,row)
        effect = cell.effect
        isnothing(effect) && continue
        effect.name == "F" && effect.value == 0 && return nothing
        if effect.name == "B"
            jump = effect.value
        elseif effect.name == "D"
            pattern_break = effect.value
        end
    end
    if isnothing(jump) && isnothing(pattern_break)
        return row < ROWS_PER_PATTERN-1 ? (position,row+1) : (position+1,0)
    end
    (
        isnothing(jump) ? position+1 : jump,
        isnothing(pattern_break) || pattern_break >= ROWS_PER_PATTERN ? 0 : pattern_break
    )
end
function reachable_rows(song)
    reached = Set{Tuple{Int,Int}}()
    current = (0,0)
    while !isnothing(current) && !(current in reached)
        push!(reached,current)
        current = next_row(song,current...)
        !isnothing(current) && current[1] >= length(song.order) && (current=nothing)
    end
    reached
end
