hundredths(text) = parse(Int,replace(text,"."=>""))
function read_dataset()
    names = String[]
    series = Dict{String,Vector{Tuple{Int,Int}}}()
    for line in readlines(joinpath("input","series.csv"))[2:end]
        name,x,y = split(line,',')
        if !haskey(series,name)
            push!(names,name)
            series[name] = Tuple{Int,Int}[]
        end
        push!(series[name],(hundredths(x),hundredths(y)))
    end
    for points in values(series)
        sort!(points,by=first)
    end
    tests = Tuple{String,Int}[]
    for line in readlines(joinpath("input","test_points.csv"))[2:end]
        name,x = split(line,',')
        push!(tests,(name,hundredths(x)))
    end
    settings = Dict{String,Any}()
    for line in readlines(joinpath("input","params.txt"))
        parts = split(line)
        settings[parts[1]] = String.(parts[2:end])
    end
    for key in ("ROBUST_ITERATIONS","CV_FOLDS","GRID_POINTS")
        settings[key] = parse(Int,only(settings[key]))
    end
    for key in ("BAND_Z","OUTLIER_THRESHOLD")
        settings[key] = parse(Float64,only(settings[key]))
    end
    for key in ("BOOTSTRAP","PLOT_SIZE")
        settings[key] = parse.(Int,settings[key])
    end
    names,series,tests,settings
end
