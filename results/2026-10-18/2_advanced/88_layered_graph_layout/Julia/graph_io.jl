const SETTING_NAMES = ["layering","width","promotion","heuristic","sweeps","node_sep","dummy_sep",
    "layer_gap","direction","sifting","reduce","restarts","seed"]
const DEFAULTS = Dict{String,Any}(zip(SETTING_NAMES,["longest",4,"off","barycenter",12,2,1,3,"TB","off","off",0,1]))
const CHOICES = Dict("layering"=>["longest","coffman"],"promotion"=>["on","off"],
    "heuristic"=>["barycenter","median"],"direction"=>["TB","BT","LR","RL"],
    "sifting"=>["on","off"],"reduce"=>["on","off"])
const RANGES = Dict("width"=>(1,40),"sweeps"=>(0,50),"node_sep"=>(1,9),"dummy_sep"=>(1,9),
    "layer_gap"=>(2,9),"restarts"=>(0,9),"seed"=>(1,2147483646))
mutable struct InputGraph
    name::String
    settings::Dict{String,Any}
    nodes::Dict{Int,String}
    edges::Vector{Tuple{Int,Int}}
    edge_set::Set{Tuple{Int,Int}}
    path::Union{Nothing,Tuple{Int,Int}}
    self_loops::Int
    duplicates::Int
    error::Union{Nothing,Tuple{String,Int}}
end
function setting_value(name,word)
    haskey(CHOICES,name) && return word in CHOICES[name] ? String(word) : nothing
    if haskey(RANGES,name) && occursin(r"^[0-9]{1,10}$",word)
        value = parse(Int,word)
        low,high = RANGES[name]
        low <= value <= high && return value
    end
    nothing
end
function input_lines(name)
    [(number=i,fields=String.(split(text))) for (i,text) in enumerate(readlines(joinpath("input",name)))
        if !isempty(text) && !startswith(text,"#")]
end
function read_defaults()
    settings = copy(DEFAULTS)
    for record in input_lines("params.txt")
        name,word = record.fields
        settings[name] = setting_value(name,word)
    end
    settings
end
function accept_line!(graph,fields)
    kind = fields[1]
    if kind == "OPTION"
        value = setting_value(fields[2],fields[3])
        value === nothing && return "bad_option"
        graph.settings[fields[2]] = value
    elseif kind == "NODE"
        id = parse(Int,fields[2])
        haskey(graph.nodes,id) && return "duplicate_node"
        length(graph.nodes) == 40 && return "too_many_nodes"
        graph.nodes[id] = fields[3]
    else
        a,b = parse.(Int,fields[2:3])
        (haskey(graph.nodes,a) && haskey(graph.nodes,b)) || return "unknown_node"
        if kind == "PATH"
            graph.path = (a,b)
        elseif a == b
            graph.self_loops += 1
        elseif (a,b) in graph.edge_set
            graph.duplicates += 1
        else
            push!(graph.edges,(a,b))
            push!(graph.edge_set,(a,b))
        end
    end
    ""
end
function read_graphs(defaults)
    graphs = InputGraph[]
    graph = nothing
    for record in input_lines("graphs.txt")
        fields = record.fields
        if fields[1] == "GRAPH"
            graph = InputGraph(fields[2],copy(defaults),Dict{Int,String}(),Tuple{Int,Int}[],
                Set{Tuple{Int,Int}}(),nothing,0,0,nothing)
            push!(graphs,graph)
        elseif fields[1] == "END"
            graph.error === nothing && isempty(graph.nodes) && (graph.error = ("no_nodes",record.number))
        elseif graph.error === nothing
            error = accept_line!(graph,fields)
            isempty(error) || (graph.error = (error,record.number))
        end
    end
    graphs
end
