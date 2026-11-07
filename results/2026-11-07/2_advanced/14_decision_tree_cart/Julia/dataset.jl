struct Attribute
    index::Int
    name::String
    integer::Bool
    values::Vector{String}
end

struct Row
    id::String
    values::Vector{Union{Nothing,Int}}
    label::Int
end

struct Settings
    max_depth::Int
    min_samples_split::Int
    min_samples_leaf::Int
    max_surrogates::Int
    folds::Int
    curve::Vector{Int}
    bag_trees::Int
    bag_seed::Int
    permutation_repeats::Int
    permutation_seed::Int
end

struct Dataset
    attributes::Vector{Attribute}
    target::String
    classes::Vector{String}
    train::Vector{Row}
    validation::Vector{Row}
    test::Vector{Row}
    settings::Settings
end

function read_rows(path, attributes, classes)
    rows = Row[]
    for line in readlines(path)[2:end]
        fields = split(line, ',')
        values = Union{Nothing,Int}[]
        for attribute in attributes
            text = fields[attribute.index + 1]
            value = text == "?" ? nothing : attribute.integer ? parse(Int, text) : findfirst(==(text), attribute.values)
            push!(values, value)
        end
        push!(rows, Row(fields[1], values, findfirst(==(fields[end]), classes)))
    end
    rows
end

function load_dataset(directory)
    attributes = Attribute[]
    schema = readlines(joinpath(directory, "schema.txt"))
    for line in schema[1:end-1]
        fields = split(line)
        push!(attributes, Attribute(length(attributes) + 1, fields[2], fields[3] == "INT", String.(fields[4:end])))
    end
    target_fields = split(schema[end])
    target, classes = String(target_fields[2]), String.(target_fields[3:end])
    settings = Dict(first(fields) => parse.(Int, fields[2:end]) for fields in split.(readlines(joinpath(directory, "params.txt"))))
    options = Settings(settings["MAX_DEPTH"][1], settings["MIN_SAMPLES_SPLIT"][1], settings["MIN_SAMPLES_LEAF"][1],
        settings["MAX_SURROGATES"][1], settings["FOLDS"][1], settings["CURVE"], settings["BAG_TREES"][1],
        settings["BAG_SEED"][1], settings["PERMUTATION_REPEATS"][1], settings["PERMUTATION_SEED"][1])
    Dataset(attributes, target, classes, read_rows(joinpath(directory, "train.csv"), attributes, classes),
        read_rows(joinpath(directory, "validation.csv"), attributes, classes), read_rows(joinpath(directory, "test.csv"), attributes, classes), options)
end
