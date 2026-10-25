module TrafficSignals
export Phase, Junction, green, plan_lines
struct Phase
    duration::Int
    token::String
    greens::Set{String}
end
function Phase(token)
    duration, greens = split(token, ':')
    Phase(parse(Int, duration), String(greens), greens == "-" ? Set{String}() : Set(String.(split(greens, ','))))
end
struct Junction
    node::String
    offset::Int
    phases::Vector{Phase}
    cycle::Int
    incoming::Vector{Int}
end
function Junction(node, offset, tokens)
    phases = Phase[Phase(token) for token in tokens]
    Junction(node, offset, phases, sum((p.duration for p in phases); init=0), Int[])
end
function green(junction, id, step)
    isempty(junction.phases) && return true
    tau = mod(step-1+junction.offset, junction.cycle)
    for phase in junction.phases
        tau < phase.duration && return id in phase.greens
        tau -= phase.duration
    end
    false
end
function plan_lines(j)
    isempty(j.phases) && return ["JUNCTION $(j.node) unsignalized"]
    lines = ["JUNCTION $(j.node) signal cycle $(j.cycle) offset $(j.offset)"]
    first = 0
    for (i, phase) in enumerate(j.phases)
        last = first+phase.duration-1
        push!(lines, "  PHASE $i $first-$last $(phase.token)")
        first = last+1
    end
    lines
end
end
