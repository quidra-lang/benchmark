Base.@kwdef mutable struct Attempt
    courses::Vector{String}
    graph::ConflictGraph
    limit::Int
    candidates::Function
    dead_ends::Int = 0
    dead_end_course::Union{Nothing,String} = nothing
    aborted::Bool = false
    chosen::Vector{Tuple{String,Int}} = Tuple{String,Int}[]
end

saturation(attempt, id, assignment) = length(Set(assignment[other] for other in keys(neighbours(attempt.graph, id)) if haskey(assignment, other)))

function search!(attempt, assignment)
    remaining = [id for id in attempt.courses if !haskey(assignment, id)]
    isempty(remaining) && return true
    id = first(sort(remaining; by=other -> (-saturation(attempt, other, assignment), -degree(attempt.graph, other), other)))
    push!(attempt.chosen, (id, saturation(attempt, id, assignment)))
    for slot in attempt.candidates(id, assignment)
        assignment[id] = slot
        search!(attempt, assignment) && return true
        delete!(assignment, id)
        attempt.aborted && return false
    end
    pop!(attempt.chosen)
    attempt.dead_ends += 1
    attempt.dead_end_course = id
    attempt.aborted = attempt.dead_ends > attempt.limit
    false
end

function greedy_numbering(order, graph)
    numbers = Dict{String,Int}()
    for id in order
        taken = Set(numbers[other] for other in keys(neighbours(graph, id)) if haskey(numbers, other))
        number = 1
        while number in taken
            number += 1
        end
        numbers[id] = number
    end
    maximum(values(numbers); init=0)
end
