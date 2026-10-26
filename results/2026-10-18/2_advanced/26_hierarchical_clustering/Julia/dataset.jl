struct Observation
    id::String
    label::String
    values::Vector{Float64}
end

struct Settings
    distance::Symbol
    standardize::Bool
    linkages::Vector{Symbol}
    cut_heights::Vector{Float64}
    cut_counts::Vector{Int}
    inconsistency_depth::Int
    inconsistency_depth_text::String
    inconsistency_count::Int
    gap_max_k::Int
    list_size::Int
    width::Int
    compare_linkage::Symbol
    replicates::Int
    percent::Int
    seed::Int
    refine_iterations::Int
end

function read_observations()
    lines = readlines("input/data.csv")
    features = String.(split(lines[1], ',')[3:end])
    observations = Observation[]
    for line in lines[2:end]
        fields = split(line, ',')
        push!(observations, Observation(String(fields[1]), String(fields[2]), parse.(Float64, fields[3:end])))
    end
    features, observations
end

function read_settings()
    rows = [split(line, ' ')[2:end] for line in readlines("input/params.txt")]
    Settings(Symbol(rows[1][1]), rows[2][1] == "yes", Symbol.(rows[3]), parse.(Float64, rows[4]),
        parse.(Int, rows[5]), foldl((value, digit) -> min(120, value * 10 + Int(digit - 0x30)), codeunits(rows[6][1]); init=0), String(rows[6][1]), parse(Int, rows[6][2]), parse(Int, rows[7][1]),
        parse(Int, rows[8][1]), parse(Int, rows[9][1]), Symbol(rows[10][1]), parse(Int, rows[11][1]),
        parse(Int, rows[11][2]), parse(Int, rows[11][3]), parse(Int, rows[12][1]))
end

function write_lines(name, lines)
    open(joinpath("output", name), "w") do file
        for line in lines
            write(file, line, "\n")
        end
    end
end
