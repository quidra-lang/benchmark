using Printf
csv_rows(name) = [String.(split(line,',')) for line in readlines(joinpath("input",name))[2:end]]
function read_inputs()
    names = String[]
    periods = Dict{String,Vector{String}}()
    raw = Dict{String,Vector{Union{Nothing,Int}}}()
    for row in csv_rows("series.csv")
        name,period,value = row
        if !haskey(periods,name)
            push!(names,name)
            periods[name] = String[]
            raw[name] = Union{Nothing,Int}[]
        end
        push!(periods[name],period)
        push!(raw[name],value == "NA" ? nothing : parse(Int,value))
    end
    events = Dict(name=>Dict{String,String}() for name in names)
    for (name,period,kind) in csv_rows("events.csv")
        events[name][period] = kind
    end
    policies = Dict{String,NamedTuple}()
    for (name,on_hand,lead,review,service) in csv_rows("inventory.csv")
        policies[name] = (
            on_hand=parse(Int,on_hand),
            lead_time=parse(Int,lead),
            review=parse(Int,review),
            service=parse(Float64,service)
        )
    end
    settings = Dict{Symbol,Any}()
    for line in readlines("input/params.txt")
        key,values... = split(line)
        symbol = Symbol(key)
        settings[symbol] = key in (
            "alpha",
            "beta",
            "gamma",
            "phi",
            "interval"
        ) ? parse.(Float64,values) : key == "ljung_box" ? parse.(Int,values) : key == "outlier" ? parse(
            Float64,
            only(values)
        ) : parse(Int,only(values))
    end
    records = [(
        name=name,
        periods=periods[name],
        raw=raw[name],
        events=events[name],
        policy=policies[name]
    ) for name in names]
    records,(;settings...)
end
function next_month(period)
    year,month = parse.(Int,split(period,'-'))
    year += month÷12
    month = month%12+1
    @sprintf("%04d-%02d",year,month)
end
function real_format(value)
    isnothing(value) && return "NA"
    text = @sprintf("%.4f",value)
    text == "-0.0000" ? "0.0000" : text
end
function write_lines(name,lines)
    mkpath("output")
    open(joinpath("output",name),"w") do io
        foreach(line->println(io,line),lines)
    end
end
