mutable struct MINSTD
    state::Int
end
function draw!(generator)
    generator.state = (48271generator.state)%2147483647
end
function shuffle_order!(generator,values)
    for i in length(values):-1:2
        j = draw!(generator)%i+1
        values[i],values[j] = values[j],values[i]
    end
end
function read_images(name)
    images = NamedTuple[]
    for line in readlines(joinpath("input",name))[2:end]
        id,label,pixels = String.(split(line,','))
        push!(
            images,
            (id=id,label=parse(Int,label),pixels=pixels,vector=[char=='1' ? 1.0 : 0.0 for char in pixels])
        )
    end
    images
end
function load_inputs()
    blocks = split(strip(read(joinpath("input","network.txt"),String)),"\n\n")
    dimensions = split(blocks[1])
    width,height = parse.(Int,dimensions[2:3])
    networks = NamedTuple[]
    for block in blocks[2:end]
        rows = split(block,'\n')
        name = String(split(rows[1])[2])
        layers = NamedTuple[]
        for row in rows[2:end]
            kind,units,activation = String.(split(row))
            push!(layers,(kind=kind,units=parse(Int,units),activation=activation))
        end
        push!(networks,(name=name,layers=layers,width=width,height=height,classes=layers[end].units))
    end
    weights = Dict{String,Vector{Float64}}()
    for block in split(strip(read(joinpath("input","weights.txt"),String)),"\n\n")
        rows = split(block,'\n')
        name = String(split(rows[1])[2])
        theta = Float64[]
        for row in rows[2:end]
            words = split(row)
            words[1] in ("W","B") && append!(theta,parse.(Float64,words[2:end]))
        end
        weights[name] = theta
    end
    settings = Dict{String,Any}("runs"=>NamedTuple[])
    for line in readlines(joinpath("input","params.txt"))
        words = String.(split(line))
        key,values = words[1],words[2:end]
        if key=="RUN"
            push!(
                settings["runs"],
                (
                    name=values[1],
                    network=values[2],
                    optimizer=values[3],
                    rate=parse(Float64,values[4]),
                    decay=parse(Float64,values[5]),
                    extra=parse.(Float64,values[6:end])
                )
            )
        elseif key=="LR_STEP"
            settings["lr_step"],settings["lr_gamma"] = parse(Int,values[1]),parse(Float64,values[2])
        elseif key in ("PRUNE","NOISE")
            settings[lowercase(key)] = parse.(Int,values)
        else
            translated = key=="GRADIENT_CHECK_STRIDE" ? "gradient_stride" : lowercase(key)
            settings[translated] = parse(Int,values[1])
        end
    end
    (
        train=read_images("train.csv"),
        test=read_images("test.csv"),
        networks=networks,
        weights=weights,
        settings=settings
    )
end
