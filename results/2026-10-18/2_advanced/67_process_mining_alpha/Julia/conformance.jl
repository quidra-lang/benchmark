struct PetriNet
    places::Vector{String}
    transitions::Vector{String}
    arcs::Set{Tuple{String,String}}
    initial::Int
    final::Int
    inputs::Dict{String,Vector{Int}}
    outputs::Dict{String,Vector{Int}}
    routes::Vector{Vector{String}}
    initial_marking::Tuple
    final_marking::Tuple
end
function PetriNet(places,transitions,arcs,initial,final)
    transitions = sort!(collect(transitions))
    arcs = Set(arcs)
    inputs = Dict(t=>[i for (i,p) in enumerate(places) if (p,t) in arcs] for t in transitions)
    outputs = Dict(t=>[i for (i,p) in enumerate(places) if (t,p) in arcs] for t in transitions)
    routes = [[t for t in transitions if (p,t) in arcs] for p in places]
    first,last = findfirst(==(initial),places),findfirst(==(final),places)
    PetriNet(
        collect(places),
        transitions,
        arcs,
        first,
        last,
        inputs,
        outputs,
        routes,
        Tuple(Int(i==first) for i in eachindex(places)),
        Tuple(Int(i==last) for i in eachindex(places))
    )
end
enabled(net,marking,t) = all(i->marking[i]>=1,net.inputs[t])
enabled_transitions(net,marking) = [t for t in net.transitions if enabled(net,marking,t)]
function fire(net,marking,t)
    result = collect(marking)
    result[net.inputs[t]] .-= 1
    result[net.outputs[t]] .+= 1
    Tuple(result)
end
function read_model()
    places,transitions,arcs,initial,final = String[],String[],Tuple{String,String}[],"",""
    for line in readlines("input/model.txt")
        words = String.(split(line))
        if words[1]=="PLACE"
            push!(places,words[2])
        elseif words[1]=="TRANSITION"
            push!(transitions,words[2])
        elseif words[1]=="ARC"
            push!(arcs,(words[2],words[3]))
        elseif words[1]=="INITIAL"
            initial = words[2]
        else
            final = words[2]
        end
    end
    PetriNet(places,transitions,arcs,initial,final)
end
Base.@kwdef mutable struct ReplayTotals
    missing::Int = 0
    remaining::Int = 0
    consumed::Int = 0
    produced::Int = 0
    skipped::Int = 0
    place_missing::Vector{Int}
    place_remaining::Vector{Int}
    deviating::Vector{Int}
    waiting::Vector{Vector{Int}}
    routes::Vector{Dict{String,Int}}
end
ReplayTotals(n) = ReplayTotals(
    place_missing=zeros(Int,n),
    place_remaining=zeros(Int,n),
    deviating=zeros(Int,n),
    waiting=[Int[] for _ in 1:n],
    routes=[Dict{String,Int}() for _ in 1:n]
)
fitness(r) = (1-r.missing//r.consumed)/2+(1-r.remaining//r.produced)/2
