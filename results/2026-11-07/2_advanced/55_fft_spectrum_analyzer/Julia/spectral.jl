function median(values)
    ordered = sort(collect(values))
    n = length(ordered)
    isodd(n) ? ordered[n÷2+1] : (ordered[n÷2]+ordered[n÷2+1])/2
end
local_maximum(values,k) = 0<k<length(values)-1 && values[k+1]>values[k] && values[k+1]>values[k+2]
function interpolate(values,k,logarithmic=true)
    local_maximum(values,k) || return (Float64(k),values[k+1])
    left,middle,right = values[k:k+2]
    logarithmic && ((left,middle,right)=log.((left,middle,right)))
    delta = (left-right)/(2*(left-2middle+right))
    fitted = middle-(left-right)*delta/4
    k+delta,logarithmic ? exp(fitted) : fitted
end
function amplitude_spectrum(signal,name,n)
    weights = window(name,n)
    weighted = signal[1:n].*weights
    transformed = dft(weighted)
    s1 = ordered_sum(weights)
    amplitudes = [(k==0 || 2k==n ? 1 : 2)*abs(transformed[k+1])/s1 for k in 0:n÷2]
    weighted,transformed,amplitudes
end
function packed_and_error(samples)
    packed,reference = packed_real(samples),radix2(samples)
    packed,maximum(abs(packed[k]-reference[k]) for k in eachindex(packed))
end
function welch_spectra(x,y,fs,n,name)
    weights = window(name,n)
    energy = ordered_sum(weight*weight for weight in weights)
    segments = (length(x)-n)÷(n÷2)+1
    count = n÷2+1
    pxx,pyy,pxy = zeros(count),zeros(count),zeros(ComplexF64,count)
    packing_error = 0.0
    for block in 0:segments-1
        start = block*(n÷2)
        xf,ex = packed_and_error(x[start+1:start+n].*weights)
        yf,ey = packed_and_error(y[start+1:start+n].*weights)
        packing_error = max(packing_error,ex,ey)
        for k in 1:count
            pxx[k] += abs2(xf[k])
            pyy[k] += abs2(yf[k])
            pxy[k] += conj(xf[k])*yf[k]
        end
    end
    psd = [(k==0 || k==n÷2 ? 1 : 2)*pxx[k+1]/(segments*fs*energy) for k in 0:n÷2]
    (segments=segments,psd=psd,coherence=abs2.(pxy)./(pxx.*pyy),transfer=pxy./pxx,packing_error=packing_error)
end
function spectrogram_magnitudes(signal,n,hop,name)
    weights = window(name,n)
    frames = (length(signal)-n)÷hop+1
    grid = Vector{Float64}[]
    error = 0.0
    for t in 0:frames-1
        transformed,e = packed_and_error(signal[t*hop+1:t*hop+n].*weights)
        push!(grid,abs.(transformed))
        error = max(error,e)
    end
    grid,error
end
