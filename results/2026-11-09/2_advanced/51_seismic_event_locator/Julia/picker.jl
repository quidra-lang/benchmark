mutable struct Pick
    station::Int
    sample::Int
    duration::Int
    ratio::Float64
    amplitude::Int
    clipped::Bool
    state::String
    event::Int
    residual::Union{Nothing,Float64}
    first_residual::Union{Nothing,Float64}
    assigned::Bool
end
function detect_station(station,params)
    samples = station.samples
    n = length(samples)
    mean = fld(sum(samples),n)
    detrended = samples.-mean
    energy = detrended.*detrended
    sw,lw = Int(params["sta_window"][1]),Int(params["lta_window"][1])
    on_num,on_den = Int.(params["trigger_on"])
    off_num,off_den = Int.(params["trigger_off"])
    prefix = vcat([0],cumsum(energy))
    picks = Pick[]
    triggers = short_triggers = 0
    on,beginning,peak_ratio = false,0,0.0
    function finish!(ending)
        triggers += 1
        duration = ending-beginning
        if duration<Int(params["min_duration"][1])
            short_triggers += 1
            return
        end
        position = beginning
        while position-1>=beginning-sw+1 && energy[position]>=Int(params["noise_level"][1])
            position -= 1
        end
        last_index = min(position+Int(params["amplitude_window"][1]),n)
        indices = position+1:last_index
        amplitude = maximum(abs(detrended[j]) for j in indices)
        clipped = any(j->abs(samples[j])>=Int(params["clip_level"][1]),indices)
        push!(
            picks,
            Pick(
                station.order,
                station.start+position,
                duration,
                peak_ratio,
                amplitude,
                clipped,
                "unassociated",
                0,
                nothing,
                nothing,
                false
            )
        )
    end
    for i in sw+lw-1:n-1
        sta = prefix[i+2]-prefix[i-sw+2]
        lta = prefix[i-sw+2]-prefix[i-sw-lw+2]
        if !on
            if sta*lw*on_den>=on_num*lta*sw
                on,beginning,peak_ratio = true,i,(sta*lw)/(lta*sw)
            end
        elseif sta*lw*off_den<off_num*lta*sw
            finish!(i)
            on = false
        else
            peak_ratio = max(peak_ratio,(sta*lw)/(lta*sw))
        end
    end
    on && finish!(n)
    stats = (mean=mean,noise=median_value(abs.(detrended)),peak=maximum(abs,detrended),clipped=count(s->abs(s)>=Int(params["clip_level"][1]),samples),
        triggers=triggers,short=short_triggers)
    picks,stats
end
