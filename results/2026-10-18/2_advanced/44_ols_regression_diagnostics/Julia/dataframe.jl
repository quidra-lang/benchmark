function read_table(path,kinds=nothing)
    records = split.(readlines(path),',')
    columns = String.(records[1])
    records = records[2:end]
    if isnothing(kinds)
        kinds = Dict(name=>any(r->r[j]!="NA" && 'A'<=r[j][1]<='Z',records) for (j,name) in enumerate(columns))
    end
    rows = [Dict{String,Any}(name=>(r[j]=="NA" ? nothing : kinds[name] ? String(r[j]) : parse(Float64,r[j]))
                            for (j,name) in enumerate(columns)) for r in records]
    (columns=columns,kinds=kinds,rows=rows)
end
function read_params()
    Dict(String(words[1])=>parse.(Float64,words[2:end]) for words in split.(readlines("input/params.txt")))
end
