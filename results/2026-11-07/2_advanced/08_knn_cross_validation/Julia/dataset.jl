module Dataset
export Row, Settings, readdataset
struct Row
    id::String
    values::Vector{Float64}
    label::Int
    target::Union{Nothing,Float64}
    index::Int
end
struct Settings
    scalings::Vector{Symbol}
    ks::Vector{Int}
    metrics::Vector{Symbol}
    weightings::Vector{Symbol}
    folds::Int
    edit::Int
    curve::Vector{Int}
    bins::Vector{Float64}
    top::Int
end
function rawrows(name)
    lines = readlines("input/"*name)
    fields = [String.(split(line,',';keepempty=true)) for line in lines[2:end]]
    String.(split(lines[1],','))[2:end-2],fields
end
function readdataset()
    features,rawtrain = rawrows("train.csv")
    _,rawtest = rawrows("test.csv")
    labels = sort!(unique([f[end-1] for f in rawtrain]))
    index = Dict(name => i for (i,name) in enumerate(labels))
    rows(raw) = [Row(f[1],parse.(Float64,f[2:end-2]),isempty(f[end-1]) ? 0 : index[f[end-1]],isempty(f[end]) ? nothing : parse(Float64,f[end]),i) for (i,f) in enumerate(raw)]
    p = Dict{String,Vector{String}}()
    for line in eachline("input/params.txt")
        f = String.(split(line,' '))
        p[f[1]] = f[2:end]
    end
    settings = Settings(Symbol.(p["SCALINGS"]),parse.(Int,p["K_VALUES"]),Symbol.(p["METRICS"]),Symbol.(p["WEIGHTINGS"]),parse(Int,only(p["FOLDS"])),parse(Int,only(p["EDIT_K"])),parse.(Int,p["CURVE"]),parse.(Float64,p["BINS"]),parse(Int,only(p["TOP"])))
    (features=features,labels=labels,train=rows(rawtrain),queries=rows(rawtest),settings=settings)
end
end
