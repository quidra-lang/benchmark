parse_hex(text) = occursin(r"^[0-9a-f]{8}$",text) ? parse(Int,text;base=16) : nothing
parse_register(text) = occursin(r"^r(?:[0-9]|[12][0-9]|3[01])$",text) ? parse(Int,text[2:end]) : -1
function read_inputs()
    config = Dict{String,Any}("predictors"=>NamedTuple[],"variants"=>NamedTuple[])
    for line in readlines(joinpath("input","config.txt"))
        row = String.(split(line,' '))
        key,values = row[1],row[2:end]
        if key in ("BTB","RAS","TOP","INTERVAL")
            config[lowercase(key)] = parse(Int,values[1])
        elseif key=="PREDICTOR"
            push!(config["predictors"],(name=values[1],scheme=values[2],parameters=parse.(Int,values[3:end])))
        elseif key=="VARIANT"
            push!(
                config["variants"],
                (name=values[1],forwarding=values[2]=="ON",stage=values[3],latency=parse(Int,values[4]))
            )
        elseif key=="PRIMARY"
            config["primary"] = Tuple(values)
        else
            config["window"] = parse.(Int,values)
        end
    end
    readlines(joinpath("input","trace.txt")),config
end
