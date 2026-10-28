function read_inputs()
    cases,deaths = Int[],Int[]
    for line in readlines(joinpath("input","cases.csv"))[2:end]
        words = split(line,',')
        push!(cases,parse(Int,words[2]))
        push!(deaths,parse(Int,words[3]))
    end
    groups,rows = NamedTuple[],Vector{Float64}[]
    for line in readlines(joinpath("input","population.txt"))
        words = String.(split(line))
        if words[1]=="group"
            push!(groups,(name=words[2],population=parse(Int,words[3]),fatality=parse(Float64,words[4])))
        else
            push!(rows,parse.(Float64,words[2:end]))
        end
    end
    contacts = [rows[g][h] for g in eachindex(rows),h in eachindex(rows)]
    interventions = [(
        parse(Int,words[1]),
        parse(Float64,words[2])
    ) for words in split.(readlines(joinpath("input","interventions.txt")))]
    params = Dict{String,Any}(
        "scenario"=>Tuple{String,Float64}[],
        "contact_change"=>Tuple{String,String,Float64}[]
    )
    for line in readlines(joinpath("input","params.txt"))
        words = String.(split(line))
        name,values = words[1],words[2:end]
        if name=="scenario"
            push!(params[name],(values[1],parse(Float64,values[2])))
        elseif name=="contact_change"
            push!(params[name],(values[1],values[2],parse(Float64,values[3])))
        elseif name in ("holdout","death_lag","generation","horizon")
            params[name] = parse(Int,values[1])
        elseif name in ("milestones","golden")
            params[name] = parse.(Int,values)
        elseif name in ("beta_grid","rho_grid")
            params[name] = (parse(Float64,values[1]),parse(Float64,values[2]),parse(Int,values[3]))
        elseif name=="nelder_mead"
            params[name] = (parse.(Float64,values[1:4])...,parse(Int,values[5]))
        elseif name in ("initial","simplex")
            params[name] = parse.(Float64,values)
        else
            params[name] = parse(Float64,values[1])
        end
    end
    (cases=cases,deaths=deaths,groups=groups,contacts=contacts,interventions=interventions,params=params)
end
function write_outputs(outputs)
    mkpath("output")
    for (name,lines) in outputs
        open(joinpath("output",name),"w") do io
            for line in lines
                println(io,line)
            end
        end
    end
end
