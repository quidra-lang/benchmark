using Dates
const DATETIME_FORMAT = dateformat"yyyy-mm-dd HH:MM"
parse_datetime(text) = DateTime(text,DATETIME_FORMAT)
epoch_hours(epoch,instant) = Dates.value(instant-epoch)÷3600000
datetime_at_hour(epoch,hour) = Dates.format(epoch+Hour(hour),DATETIME_FORMAT)
datetime_at_minute(epoch,minute) = Dates.format(epoch+Minute(minute),DATETIME_FORMAT)
date_at_day(epoch,day) = string(Date(epoch)+Day(day))
function read_all_inputs()
    lines = readlines("input/params.txt")
    epoch = parse_datetime(lines[1][7:end])
    stations,cursor = NamedTuple[],2
    while startswith(lines[cursor],"station ")
        fields = split(lines[cursor],' ';limit=3)
        push!(stations,(code=String(fields[2]),name=String(fields[3])))
        cursor += 1
    end
    values = Dict(String(fields[1])=>String(fields[2]) for fields in (split(
        line,
        ' ';limit=2
    ) for line in lines[cursor:end]))
    spike,surge,prediction,plot = split(values["spike"]),split(values["surge"]),split(values["predict"]),split(values["plot"])
    settings = (
        epoch=epoch,
        stations=stations,
        reference=values["reference"],
        flat_run=parse(Int,values["flat_run"]),
        spike_window=parse(Int,spike[1]),
        spike_minimum=parse(Int,spike[2]),
        spike_factor=parse(Float64,spike[3]),
        spike_floor=parse(Float64,spike[4]),
        rayleigh=parse(Float64,values["rayleigh"]),
        snr_min=parse(Float64,values["snr_min"]),
        top_residuals=parse(Int,values["top_residuals"]),
        surge_threshold=parse(Float64,surge[1]),
        surge_hours=parse(Int,surge[2]),
        prediction_start=parse_datetime(join(prediction[1:2]," ")),
        prediction_hours=parse(Int,prediction[3]),
        grid_minutes=parse(Int,values["grid_minutes"]),
        min_range=parse(Float64,values["min_range"]),
        correlation_lag=parse(Int,values["correlation_lag"]),
        plot_code=String(plot[1]),
        plot_hours=parse(Int,plot[2]),
        plot_top=parse(Int,plot[3]),
        plot_bottom=parse(Int,plot[4]),
        plot_step=parse(Int,plot[5])
    )
    constituents = [(
        name=String(fields[1]),
        speed=parse(Float64,fields[2])
    ) for fields in split.(readlines("input/constituents.txt")[2:end])]
    observations = Dict(station.code=>(values=Dict{Int,Union{Nothing,Float64}}(),) for station in stations)
    for line in readlines("input/observations.csv")[2:end]
        code,text,value = split(line,',')
        t = epoch_hours(epoch,parse_datetime(text))
        observations[code].values[t] = value=="NA" ? nothing : parse(Float64,value)
    end
    (
        settings=settings,
        constituents=constituents,
        observations=Dict(code=>(
            values=record.values,
            rows=length(record.values)
        ) for (code,record) in observations)
    )
end
