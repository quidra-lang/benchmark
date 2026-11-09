mutable struct Group
    number::Int
    name::String
    values::Vector{Int}
end

struct PairedSample
    before::Vector{Int}
    after::Vector{Int}
    differences::Vector{Int}
end

struct Settings
    seed::Int
    bootstrap::Int
    permutations::Int
    confidence::Int
    pilot::Int
    power_sims::Int
    power_perms::Int
    bins::Int
end

struct Dataset
    groups::Vector{Group}
    paired::PairedSample
    settings::Settings
    pairs::Vector{Tuple{Int,Int}}
end

function hundredths(text)
    fields = split(text, '.')
    parse(Int, fields[1]) * 100 + (length(fields) == 1 ? 0 : parse(Int, rpad(fields[2], 2, '0')))
end

function load_dataset(directory)
    groups = Group[]
    positions = Dict{String,Int}()
    for line in readlines(joinpath(directory, "samples.csv"))[2:end]
        name, value = split(line, ',')
        if !haskey(positions, name)
            positions[name] = length(groups) + 1
            push!(groups, Group(length(groups) + 1, name, Int[]))
        end
        push!(groups[positions[name]].values, hundredths(value))
    end
    before, after = Int[], Int[]
    for line in readlines(joinpath(directory, "paired.csv"))[2:end]
        _, first, second = split(line, ',')
        push!(before, hundredths(first))
        push!(after, hundredths(second))
    end
    entries, pairs = Dict{String,Vector{Int}}(), Tuple{Int,Int}[]
    for line in readlines(joinpath(directory, "params.txt"))
        fields = split(line)
        if fields[1] == "compare"
            push!(pairs, (positions[fields[2]], positions[fields[3]]))
        else
            entries[fields[1]] = parse.(Int, fields[2:end])
        end
    end
    settings = Settings(entries["seed"][1], entries["bootstrap"][1], entries["permutations"][1], entries["confidence"][1],
        entries["pilot"][1], entries["power"]..., entries["bins"][1])
    Dataset(groups, PairedSample(before, after, after - before), settings, pairs)
end
