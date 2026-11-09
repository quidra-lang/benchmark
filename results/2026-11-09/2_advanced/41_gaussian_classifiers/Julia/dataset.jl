function read_inputs()
    function table(path)
        rows = split.(readlines(path),',')
        features = String.(rows[1][2:end-1])
        records = [(
            id=parse(Int,r[1]),
            x=parse.(Float64,r[2:end-1]),
            label=String(r[end])
        ) for r in rows[2:end]]
        features,records
    end
    features,train = table("input/train.csv")
    _,test = table("input/test.csv")
    classes = sort(unique(r.label for r in train))
    index = Dict(name=>i for (i,name) in enumerate(classes))
    train = [(;r...,y=index[r.label]) for r in train]
    test = [(;r...,y=index[r.label]) for r in test]
    lines = split.(readlines("input/costs.csv"),',')
    columns = String.(lines[1][2:end])
    cost_rows = Dict(String(r[1])=>parse.(Float64,r[2:end]) for r in lines[2:end])
    costs = [cost_rows[a][findfirst(==(b),columns)] for a in classes,b in classes]
    params = Dict{String,Any}()
    subsets = Tuple{String,Vector{Int}}[]
    pairs = Vector{Int}[]
    feature_index = Dict(name=>i for (i,name) in enumerate(features))
    for line in readlines("input/params.txt")
        words = split(line)
        key,args = String(words[1]),words[2:end]
        if key == "SUBSET"
            push!(subsets,(String(args[1]),[feature_index[name] for name in args[2:end]]))
        elseif key == "PAIR"
            push!(pairs,[feature_index[name] for name in args])
        elseif key == "PRIOR"
            params[key] = String(args[1])
        else
            params[key] = parse.(Float64,args)
        end
    end
    (
        features=features,
        classes=classes,
        train=train,
        test=test,
        costs=costs,
        params=params,
        subsets=subsets,
        pairs=pairs
    )
end
