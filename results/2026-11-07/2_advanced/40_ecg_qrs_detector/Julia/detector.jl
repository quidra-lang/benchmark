mutable struct Peak
    time::Int
    r::Int
    peak_i::Int
    peak_f::Int
    slope::Int
    thr_i::Int
    thr_f::Int
    kind::String
end
function find_peaks(signals)
    integrated,band,derivative = signals.integrated,signals.bandpass,signals.derivative
    peaks = Peak[]
    for i in eachindex(integrated)
        value = integrated[i]
        value > 0 || continue
        all(integrated[j] < value for j in max(1,i-20):i-1) || continue
        all(integrated[j] <= value for j in i+1:min(length(integrated),i+20)) || continue
        candidates = max(1,i-30):i
        r = candidates[argmax(abs.(band[candidates]))]
        slope = maximum(abs,derivative[max(1,i-29):i])
        push!(peaks,Peak(i-1,r-1,value,abs(band[r]),slope,0,0,""))
    end
    peaks
end
function initial_levels(signals)
    integrated = signals.integrated[1:400]
    band = abs.(signals.bandpass[1:400])
    Dict(:spki=>maximum(integrated)÷3,:npki=>sum(integrated)÷800,
         :spkf=>maximum(band)÷3,:npkf=>sum(band)÷800)
end
function width_ms(band,r)
    positions = [j for j in max(0,r-25):min(length(band)-1,r+25)
                 if 4abs(band[j+1]) >= abs(band[r+1])]
    5*(positions[end]-positions[1]+1)
end
