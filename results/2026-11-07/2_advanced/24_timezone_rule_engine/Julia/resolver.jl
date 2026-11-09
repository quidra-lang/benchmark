struct Period
    start::Int
    offset::Int
    dst::Bool
    abbreviation::String
end
same_state(first::Period, second::Period) = first.offset == second.offset && first.dst == second.dst && first.abbreviation == second.abbreviation
struct Timeline
    periods::Vector{Period}
    starts::Vector{Int}
end
Timeline(periods::Vector{Period}) = Timeline(periods, [period.start for period in periods])
index_at(timeline::Timeline, time::Int) = searchsortedlast(timeline.starts, time)
period_at(timeline::Timeline, time::Int) = timeline.periods[index_at(timeline, time)]
end_of(timeline::Timeline, index::Int) = index < length(timeline.periods) ? timeline.starts[index + 1] : POS_INFINITY
nearby(timeline::Timeline, low::Int, high::Int) = index_at(timeline, low - 57600):index_at(timeline, high + 57600)
function candidates(timeline::Timeline, local_time::Int)
    found = Int[]
    for index in nearby(timeline, local_time, local_time)
        time = local_time - timeline.periods[index].offset
        timeline.starts[index] <= time < end_of(timeline, index) && push!(found, index)
    end
    found
end
function skipping_transition(timeline::Timeline, local_time::Int)
    for index in nearby(timeline, local_time, local_time)
        index == 1 && continue
        time = timeline.starts[index]
        time + timeline.periods[index - 1].offset <= local_time < time + timeline.periods[index].offset && return index
    end
    nothing
end
