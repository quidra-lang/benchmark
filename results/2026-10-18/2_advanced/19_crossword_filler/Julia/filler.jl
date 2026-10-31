mutable struct GridState
    letters::Vector{Char}
    words::Vector{Int}
    used::Set{Int}
end
GridState(letters, count) = GridState(copy(letters), zeros(Int, count), Set{Int}())
copy_state(state) = GridState(copy(state.letters), copy(state.words), copy(state.used))
pattern(state, slot) = state.letters[slot.cells]
function assign!(state, slot, id, index)
    filled = Int[]
    for (cell, letter) in zip(slot.cells, index.words[id].letters)
        if state.letters[cell] == '.'
            state.letters[cell] = letter
            push!(filled, cell)
        end
    end
    state.words[slot.index] = id
    push!(state.used, id)
    filled
end
function unassign!(state, slot, filled)
    state.letters[filled] .= '.'
    delete!(state.used, state.words[slot.index])
    state.words[slot.index] = 0
end

mutable struct Attempt
    state::GridState
    minimum::Int
    budget::Int
    nodes::Int
    backtracks::Int
    prunes::Int
    dead_ends::Int
    sequence::Vector{Int}
    max_depth::Int
    best::GridState
    failures::Vector{Int}
    trace::Vector{String}
    outcome::String
end
Attempt(initial, minimum, budget) = Attempt(copy_state(initial), minimum, budget, 0, 0, 0, 0, Int[], 0, copy_state(initial), zeros(Int, length(initial.words)), String[], "")
attempt_candidates(attempt, slot, index) = candidates(index, pattern(attempt.state, slot), attempt.minimum, attempt.state.used)

function search!(attempt, layout, index)
    chosen, words = 0, Int[]
    for slot in layout.slots
        attempt.state.words[slot.index] != 0 && continue
        options = attempt_candidates(attempt, slot, index)
        if chosen == 0 || length(options) < length(words)
            chosen, words = slot.index, options
        end
    end
    chosen == 0 && return "complete"
    if isempty(words)
        attempt.dead_ends += 1
        attempt.failures[chosen] += 1
        return "fail"
    end
    slot = layout.slots[chosen]
    for word in words
        attempt.nodes == attempt.budget && return "abort"
        attempt.nodes += 1
        filled = assign!(attempt.state, slot, word, index)
        push!(attempt.sequence, chosen)
        wiped = findfirst(other -> attempt.state.words[other] == 0 && isempty(attempt_candidates(attempt, layout.slots[other], index)), slot.crossings)
        attempt.nodes <= 10 && push!(attempt.trace, slot.label * "=" * index.words[word].text * (isnothing(wiped) ? "" : "!"))
        if !isnothing(wiped)
            attempt.prunes += 1
            attempt.failures[slot.crossings[wiped]] += 1
            result = "fail"
        else
            if length(attempt.sequence) > attempt.max_depth
                attempt.max_depth = length(attempt.sequence)
                attempt.best = copy_state(attempt.state)
            end
            result = search!(attempt, layout, index)
        end
        result != "fail" && return result
        unassign!(attempt.state, slot, filled)
        pop!(attempt.sequence)
        attempt.backtracks += 1
    end
    "fail"
end
function run_attempt!(attempt, layout, index)
    result = search!(attempt, layout, index)
    attempt.outcome = result == "complete" ? "filled" : result == "fail" ? "unfillable" : "budget"
end
final_state(attempt) = attempt.outcome == "filled" ? attempt.state : attempt.best
