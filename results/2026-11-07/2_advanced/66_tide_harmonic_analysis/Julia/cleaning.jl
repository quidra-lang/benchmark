function median_value(values)
    ordered = sort(values)
    n = length(ordered)
    isodd(n) ? ordered[(n+1)÷2] : (ordered[n÷2]+ordered[n÷2+1])/2
end
function prepare_record(record,minimum_run)
    values = record.values
    numeric = sort!([t for (t,v) in values if !isnothing(v)])
    first,last = numeric[1],numeric[end]
    reasons = Dict{Int,String}()
    for t in first:last
        !haskey(values,t) ? (reasons[t]="absent") : isnothing(values[t]) ? (reasons[t]="na") : nothing
    end
    runs,cursor = NamedTuple[],1
    while cursor<=length(numeric)
        start = stop = numeric[cursor]
        while cursor<length(numeric) && numeric[cursor+1]==stop+1 && values[numeric[cursor+1]]==values[start]
            cursor += 1
            stop = numeric[cursor]
        end
        if stop-start+1>=minimum_run
            push!(runs,(start=start,stop=stop,value=values[start]))
            for t in start+1:stop
                reasons[t] = "flat"
            end
        end
        cursor += 1
    end
    (
        first=first,
        last=last,
        record_length=last-first,
        numeric_times=numeric,
        reasons=reasons,
        flat_runs=runs,
        candidates=[t for t in numeric if !haskey(reasons,t)],
        values=values,
        rows=record.rows
    )
end
function list_gaps(cleaning)
    gaps,start = NamedTuple[],cleaning.first
    while start<=cleaning.last
        if !haskey(cleaning.reasons,start)
            start += 1
            continue
        end
        stop = start
        while stop<cleaning.last && haskey(cleaning.reasons,stop+1)
            stop += 1
        end
        causes = unique([cleaning.reasons[t] for t in start:stop])
        push!(gaps,(start=start,stop=stop,cause=length(causes)==1 ? causes[1] : "mixed"))
        start = stop+1
    end
    gaps
end
function detect_spikes(cleaning,residuals,settings)
    tested,spikes = 0,NamedTuple[]
    for t in cleaning.candidates
        neighbors = [residuals[u] for u in cleaning.candidates if abs(u-t)<=settings.spike_window]
        length(neighbors)<settings.spike_minimum && continue
        tested += 1
        center = median_value(neighbors)
        mad = median_value(abs.(neighbors.-center))
        limit = max(settings.spike_factor*1.4826*mad,settings.spike_floor)
        if abs(residuals[t]-center)>limit
            cleaning.reasons[t] = "spike"
            push!(
                spikes,
                (time=t,value=cleaning.values[t],residual=residuals[t],median=center,mad=mad,limit=limit)
            )
        end
    end
    (
        ;cleaning...,
        tested=tested,
        spikes=spikes,
        usable=[t for t in cleaning.candidates if !haskey(cleaning.reasons,t)],
        gaps=list_gaps(cleaning)
    )
end
