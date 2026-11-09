struct Mixture
    weights::Vector{Float64}
    means::Vector{Tuple{Float64,Float64}}
    covariances::Vector{NTuple{3,Float64}}
    type::String
end
function read_all()
    points = [(
        id=String(row[1]),
        x=parse(Float64,row[2]),
        y=parse(Float64,row[3])
    ) for row in (split(line,',') for line in readlines("input/points.csv")[2:end])]
    lines = readlines("input/init.txt")
    initial = Dict{Int,Mixture}()
    cursor = 1
    while cursor<=length(lines)
        if isempty(lines[cursor])
            cursor += 1
            continue
        end
        k = parse(Int,split(lines[cursor],' ')[2])
        weights = parse.(Float64,split(lines[cursor+1],' ')[2:end])
        means,covariances = Tuple{Float64,Float64}[],NTuple{3,Float64}[]
        for j in 1:k
            values = parse.(Float64,split(lines[cursor+1+j],' ')[3:end])
            push!(means,(values[1],values[2]))
            push!(covariances,(values[3],values[4],values[5]))
        end
        initial[k] = Mixture(weights,means,covariances,"")
        cursor += k+2
    end
    raw = Dict(String(row[1])=>String.(row[2:end]) for row in (split(
        line,
        ' '
    ) for line in readlines("input/params.txt")))
    settings = (ks=parse.(Int,raw["K"]),types=raw["TYPES"],iterations=parse(Int,raw["ITERATIONS"][1]),epsilon=parse(Float64,raw["REGULARIZATION"][1]),
        settle=parse(Float64,raw["SETTLE_TOLERANCE"][1]),kmeans_iterations=parse(
            Int,
            raw["KMEANS_MAX_ITERATIONS"][1]
        ),cv_folds=parse(Int,raw["CV_FOLDS"][1]),
        uncertain=parse(Float64,raw["UNCERTAIN_THRESHOLD"][1]),low_density=parse(
            Float64,
            raw["LOW_DENSITY_THRESHOLD"][1]
        ),gof_edges=parse.(Float64,raw["GOF_EDGES"]),
        map_x=parse.(Float64,raw["MAP_X"]),map_y=parse.(
            Float64,
            raw["MAP_Y"]
        ),map_size=parse.(Int,raw["MAP_SIZE"]))
    points,initial,settings
end
