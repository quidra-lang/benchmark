mutable struct Resolution <: LinkComponent
    name::String
    entries::Vector{LinkSymbol}
    strong::Vector{LinkSymbol}
    weak::Vector{LinkSymbol}
    commons::Vector{LinkSymbol}
    references::Vector{LinkSymbol}
    referrers::Vector{String}
    strong_definers::Vector{String}
    definition::Union{Nothing,LinkSymbol}
    size::Int
    alignment::Int
    address::Int64
    live::Bool
    unresolved_referrers::Vector{String}
    kind::String
    definer::String
end
function Resolution(name,entries,script=false)
    strong = [e for e in entries if e.kind == "defined" && e.binding == "global"]
    weak = [e for e in entries if e.kind == "defined" && e.binding == "weak"]
    commons = [e for e in entries if e.kind == "common"]
    references = [e for e in entries if e.kind == "undefined"]
    referrers = unique([e.owner.name for e in references])
    strong_definers = [script ? ["*script*"] : String[];[e.owner.name for e in strong]]
    definition,size,alignment = nothing,0,1
    if script
        kind,definer = "script","*script*"
    elseif !isempty(strong)
        kind,definition = "global",strong[1]
        definer = definition.owner.name
    elseif !isempty(commons)
        kind = "common"
        size,alignment = maximum(e.size for e in commons),maximum(e.alignment for e in commons)
        definer = commons[findfirst(e -> e.size == size,commons)].owner.name
    elseif !isempty(weak)
        kind,definition = "weak",weak[1]
        definer = definition.owner.name
    elseif any(e.binding == "global" for e in references)
        kind,definer = "undefined","-"
    else
        kind,definer = "weakundef","-"
    end
    Resolution(name,entries,strong,weak,commons,references,referrers,strong_definers,definition,size,alignment,0,false,String[],kind,definer)
end
function resolve_names(entries,script_names)
    names = sort(collect(union(Set(keys(entries)),script_names)))
    Dict{String,Resolution}(name=>Resolution(name,get(entries,name,LinkSymbol[]),name in script_names) for name in names)
end
