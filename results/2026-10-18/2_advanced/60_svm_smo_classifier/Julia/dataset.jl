function read_binary(name)
    examples = NamedTuple[]
    for line in readlines(joinpath("input",name))[2:end]
        words = String.(split(line,','))
        push!(
            examples,
            (id=words[1],point=(parse(Float64,words[2]),parse(Float64,words[3])),label=parse(Int,words[4]))
        )
    end
    examples
end
function read_inputs()
    training,testing = read_binary("train.csv"),read_binary("test.csv")
    multi_training,multi_testing = NamedTuple[],NamedTuple[]
    for line in readlines(joinpath("input","multiclass.csv"))[2:end]
        words = String.(split(line,','))
        example = (
            id=words[1],
            point=(parse(Float64,words[2]),parse(Float64,words[3])),
            class_number=parse(Int,words[4]),
            role=words[5]
        )
        push!(words[5]=="train" ? multi_training : multi_testing,example)
    end
    settings = Dict{String,Any}("kernels"=>SVMKernel[])
    for line in readlines(joinpath("input","params.txt"))
        words = String.(split(line))
        key,values = lowercase(words[1]),words[2:end]
        if key=="kernel"
            kind = values[2]
            degree = kind=="poly" ? parse(Int,values[3]) : 0
            gamma = kind=="poly" ? parse(Float64,values[4]) : kind=="rbf" ? parse(Float64,values[3]) : 0.0
            coef0 = kind=="poly" ? parse(Float64,values[5]) : 0.0
            push!(settings["kernels"],SVMKernel(values[1],kind,degree,gamma,coef0))
        elseif key in ("max_passes","folds","newton_iterations")
            settings[key] = parse(Int,values[1])
        elseif key in ("learning_curve","plot_size")
            settings[key] = parse.(Int,values)
        elseif key=="multiclass"
            settings[key] = (values[1],parse(Float64,values[2]))
        elseif key=="pegasos"
            settings[key] = (parse(Float64,values[1]),parse(Int,values[2]),parse(Int,values[3]))
        elseif key in ("c_grid","plot_x","plot_y")
            settings[key] = parse.(Float64,values)
        else
            settings[key] = parse(Float64,values[1])
        end
    end
    training,testing,multi_training,multi_testing,settings
end
