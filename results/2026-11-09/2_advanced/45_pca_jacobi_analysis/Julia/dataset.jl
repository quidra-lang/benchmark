function read_table(path)
    lines = split.(readlines(path),',')
    names = String.(lines[1][2:end])
    ids = String[line[1] for line in lines[2:end]]
    values = Union{Nothing,Float64}[
        lines[i+1][j+1]=="NA" ? nothing : parse(Float64,lines[i+1][j+1]) for i in eachindex(ids),
        j in eachindex(names)
    ]
    (names=names,ids=ids,values=values)
end
function load_dataset()
    settings = Dict{String,Any}()
    for line in readlines("input/params.txt")
        words = split(line)
        key = String(words[1])
        settings[key] = key in (
            "MISSING",
            "SCALING",
            "COMPONENTS"
        ) ? String(words[2]) : parse.(Float64,words[2:end])
    end
    (data=read_table("input/data.csv"),supplementary=read_table("input/supplementary.csv"),settings=settings)
end
