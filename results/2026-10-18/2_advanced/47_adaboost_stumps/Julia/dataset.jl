function read_inputs()
    function binary(path)
        lines = split.(readlines(path),',')
        features = String.(lines[1][2:end-1])
        rows = [(id=String(r[1]),x=parse.(Float64,r[2:end-1]),label=parse(Int,r[end])) for r in lines[2:end]]
        features,rows
    end
    features,train = binary("input/train.csv")
    _,test = binary("input/test.csv")
    lines = split.(readlines("input/multiclass.csv"),',')
    multi_features = String.(lines[1][2:end-2])
    multi_train,multi_test = NamedTuple[],NamedTuple[]
    for r in lines[2:end]
        row = (id=String(r[1]),x=parse.(Float64,r[2:end-2]),label=parse(Int,r[end-1]))
        push!(r[end]=="train" ? multi_train : multi_test,row)
    end
    params = Dict{String,Any}()
    for line in readlines("input/params.txt")
        words = split(line)
        key = String(words[1])
        params[key] = key=="VARIANTS" ? String.(words[2:end]) : parse.(Float64,words[2:end])
    end
    (
        features=features,
        train=train,
        test=test,
        multi_features=multi_features,
        multi_train=multi_train,
        multi_test=multi_test,
        params=params
    )
end
