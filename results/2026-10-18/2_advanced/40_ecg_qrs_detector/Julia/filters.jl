function filter_ecg(ecg)
    n = length(ecg)
    c,low,band,derivative,squared,integrated = [zeros(Int,n) for _ in 1:6]
    at(values,i) = i >= 1 ? values[i] : 0
    high_sum = 0
    window_sum = 0
    for i in 1:n
        c[i] = 2at(c,i-1)-at(c,i-2)+ecg[i]-2at(ecg,i-6)+at(ecg,i-12)
        low[i] = fld(c[i],32)
        high_sum += low[i]-at(low,i-32)
        band[i] = at(low,i-16)-fld(high_sum,32)
        derivative[i] = fld(2band[i]+at(band,i-1)-at(band,i-3)-2at(band,i-4),8)
        squared[i] = derivative[i]^2
        window_sum += squared[i]-at(squared,i-30)
        integrated[i] = fld(window_sum,30)
    end
    (lowpass=low,bandpass=band,derivative=derivative,squared=squared,integrated=integrated)
end
