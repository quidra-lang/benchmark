const MONTH_DAYS = (31,28,31,30,31,30,31,31,30,31,30,31)
function timestamp_minutes(text)
    month,day,hour,minute = parse(Int,text[6:7]),parse(Int,text[9:10]),parse(Int,text[12:13]),parse(
        Int,
        text[15:16]
    )
    (1<=month<=12 && 1<=day<=MONTH_DAYS[month] && 0<=hour<=23 && 0<=minute<=59) || return nothing
    ((sum(MONTH_DAYS[1:month-1])+day-1)*24+hour)*60+minute
end
function read_inputs()
    rows = [(
        line=i+1,
        case_id=String(f[1]),
        activity=String(f[2]),
        timestamp=String(f[3]),
        resource=String(f[4])
    ) for (i,f) in enumerate(split.(readlines("input/eventlog.csv")[2:end],','))]
    params = Dict{String,String}()
    for line in readlines("input/params.txt")
        name,value = split(line)
        params[name] = value
    end
    rows,params
end
function group_cases(events)
    identifiers = sort!(unique([event.case_id for event in events]))
    [(
        identifier=id,
        events=ordered,
        trace=Tuple(e.activity for e in ordered),
        duration=ordered[end].time-ordered[1].time
    ) for id in identifiers for ordered in (sort!([e for e in events if e.case_id==id];by=e->(e.time,e.line)),)]
end
function integer_median(values)
    ordered = sort(values)
    n = length(values)
    isodd(n) ? ordered[(n+1)÷2]//1 : (ordered[n÷2]+ordered[n÷2+1])//2
end
