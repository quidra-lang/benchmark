include("signal_io.jl")
include("fft.jl")
include("windows.jl")
include("spectral.jl")
include("report.jl")
mean_square(values) = ordered_sum(value*value for value in values)/length(values)
rms(values) = sqrt(mean_square(values))
db(value,factor=20) = factor*log10(value)
phase_degrees(value) = atan(imag(value),real(value))*180/PI
function detrend(samples,fs)
    n = length(samples)
    center,average = (n-1)/2,ordered_sum(samples)/n
    slope = ordered_sum((i-center)*(samples[i+1]-average) for i in 0:n-1)/ordered_sum((i-center)^2 for i in 0:n-1)
    residual = [samples[i+1]-average-slope*(i-center) for i in 0:n-1]
    level = rms(residual)
    residual,(mean=average,slope=slope*fs,rms=level,min=minimum(samples),max=maximum(samples),crest=maximum(abs,residual)/level,
        skewness=(ordered_sum(v^3 for v in residual)/n)/level^3,kurtosis=(ordered_sum(v^4 for v in residual)/n)/level^4)
end
function level_history(x,y,block_length)
    history = NamedTuple[]
    for g in 0:length(x)÷block_length-1
        indices = g*block_length+1:(g+1)*block_length
        push!(history,(number=g,rms1=rms(x[indices]),rms2=rms(y[indices]),peak1=maximum(abs,x[indices])))
    end
    history,argmax([row.rms1 for row in history])-1
end
function strongest_local_maxima(values,limit)
    candidates = [k for k in 1:length(values)-2 if local_maximum(values,k)]
    sort!(candidates;by=k->(-values[k+1],k))
    candidates[1:min(limit,length(candidates))]
end
function amplitude_bandwidth(amplitudes,k)
    last = length(amplitudes)-1
    cutoff = amplitudes[k+1]/sqrt(2)
    right,left = Float64(last),0.0
    for j in k+1:last
        if amplitudes[j+1]<=cutoff
            right = j-1+(amplitudes[j]-cutoff)/(amplitudes[j]-amplitudes[j+1])
            break
        end
    end
    for j in k-1:-1:0
        if amplitudes[j+1]<=cutoff
            left = j+1-(amplitudes[j+2]-cutoff)/(amplitudes[j+2]-amplitudes[j+1])
            break
        end
    end
    right-left
end
function label_peak(peak,peaks,params,fs)
    nominal,width = params.fundamental
    notch,notch_width = params.notch
    for h in 1:10
        abs(peak.position-h*nominal*params.main_length/fs)<=width && return "h$h"
    end
    frequency = peak.position*fs/params.main_length
    multiple = floor(Int,frequency/notch+0.5)
    multiple>=1 && abs(frequency-multiple*notch)<=notch_width && return "mains"
    for pivot in peaks
        pivot.rank==peak.rank && continue
        pivot.bin_amplitude>peak.bin_amplitude || continue
        for other in peaks
            other.rank in (peak.rank,pivot.rank) && continue
            if pivot.bin_amplitude>other.bin_amplitude && abs(peak.position+other.position-2pivot.position)<=1
                return "sideband$(pivot.rank)"
            end
        end
    end
    "other"
end
function main_peaks(amplitudes,transformed,params,fs,welch)
    m,L = params.main_length,params.welch[1]
    largest,noise = maximum(amplitudes),median(amplitudes[2:end-1])
    candidates = [k for k in strongest_local_maxima(
        amplitudes,
        length(amplitudes)
    ) if db(amplitudes[k+1]/largest)>=params.peak_threshold_db]
    peaks = NamedTuple[]
    for (rank,k) in enumerate(candidates[1:min(params.peak_count,length(candidates))])
        position,amplitude = interpolate(amplitudes,k)
        j = (2k*L+m)÷(2m)
        push!(peaks,(rank=rank,bin=k,position=position,bin_amplitude=amplitudes[k+1],frequency=k*fs/m,refined=position*fs/m,amplitude=amplitude,
            level_db=db(amplitudes[k+1]/largest),phase=phase_degrees(transformed[k+1]),bandwidth=amplitude_bandwidth(
                amplitudes,
                k
            )*fs/m,
            snr_db=db(amplitudes[k+1]/noise),coherence=welch.coherence[j+1]))
    end
    [(;peak...,label=label_peak(peak,peaks,params,fs)) for peak in peaks],largest,noise
end
function harmonic_analysis(amplitudes,params,fs)
    m = params.main_length
    nominal,width = params.fundamental
    harmonics = NamedTuple[]
    for h in 1:10
        center = h*nominal*m/fs
        indices = [k for k in 1:m÷2-1 if abs(k-center)<=width]
        k = indices[argmax(amplitudes[indices.+1])]
        position,amplitude = interpolate(amplitudes,k)
        push!(
            harmonics,
            (number=h,target=h*nominal,bin=k,position=position,frequency=position*fs/m,amplitude=amplitude)
        )
    end
    primary = harmonics[1].amplitude
    rows = [(;row...,level_db=db(row.amplitude/primary)) for row in harmonics]
    thd = sqrt(ordered_sum(row.amplitude^2 for row in rows[2:end]))/primary
    rows,(thd_percent=100thd,thd_db=db(thd))
end
function power_analysis(amplitudes,params,fs,harmonics,enbw)
    m = params.main_length
    half = m÷2
    power = amplitudes.^2 ./2
    total = ordered_sum(power[k+1] for k in 1:half-1)
    total_power = total/enbw
    primary = ordered_sum(power[k+1] for k in 1:half-1 if abs(k-harmonics[1].bin)<=params.fundamental[2])/enbw
    thdn = sqrt((total_power-primary)/primary)
    centroid = ordered_sum(k*fs/m*power[k+1] for k in 1:half-1)/total
    spread = sqrt(ordered_sum((k*fs/m-centroid)^2*power[k+1] for k in 1:half-1)/total)
    cumulative,rolloff = 0.0,0.0
    for k in 1:half-1
        cumulative += power[k+1]
        if cumulative>=0.85total
            rolloff = k*fs/m
            break
        end
    end
    flatness = db(exp(ordered_sum(log(power[k+1]) for k in 1:half-1)/(half-1))/(total/(half-1)),10)
    power,(
        total_power=total_power,
        centroid=centroid,
        spread=spread,
        rolloff=rolloff,
        flatness_db=flatness,
        thdn_percent=100thdn,
        thdn_db=db(thdn)
    )
end
function calculate_bands(power,params,fs,enbw,total_power)
    m = params.main_length
    bands,octaves = NamedTuple[],NamedTuple[]
    for (low,high) in zip(params.bands,params.bands[2:end])
        value = ordered_sum(power[k+1] for k in 1:m÷2-1 if low*m<=k*fs<high*m)/enbw
        push!(bands,(range="$low-$high",power=value,percent=100value/total_power))
    end
    for b in params.third_octave[1]:params.third_octave[2]
        center,low,high = 1000*2^(b/3),1000*2^((2b-1)/6),1000*2^((2b+1)/6)
        indices = [k for k in 1:m÷2-1 if low<=k*fs/m<high]
        value = ordered_sum(power[k+1] for k in indices)/enbw
        push!(octaves,(band=b,center=center,lower=low,upper=high,bins=length(indices),level_db=db(value,10)))
    end
    bands,octaves
end
function compare_windows(signal,params,fs)
    m = params.main_length
    nominal,width = params.fundamental
    rows = NamedTuple[]
    for name in WINDOW_ORDER
        calibration = figures(window(name,m),fs)
        _,_,amplitudes = amplitude_spectrum(signal,name,m)
        indices = [k for k in 1:m÷2-1 if abs(k-nominal*m/fs)<=width]
        k = indices[argmax(amplitudes[indices.+1])]
        _,refined = interpolate(amplitudes,k)
        push!(rows,(name=name,coherent_gain=calibration.coherent_gain,enbw_bins=calibration.enbw_bins,enbw_hz=calibration.enbw_hz,
            scalloping_db=calibration.scalloping_db,fundamental_bin=k,bin_amplitude=amplitudes[k+1],refined_amplitude=refined,floor_db=db(median(amplitudes[2:end-1]))))
    end
    rows
end
function analyze_welch(x,y,params,fs)
    n,name = params.welch
    result = welch_spectra(x,y,fs,n,name)
    integrated,variance = ordered_sum(result.psd)*fs/n,mean_square(x)
    peaks = NamedTuple[]
    for (rank,k) in enumerate(strongest_local_maxima(result.psd,5))
        transfer = result.transfer[k+1]
        push!(
            peaks,
            (
                peak=rank,
                frequency=k*fs/n,
                psd_db=db(result.psd[k+1],10),
                coherence=result.coherence[k+1],
                gain=abs(transfer),
                phase=phase_degrees(transfer)
            )
        )
    end
    (
        ;result...,
        length=n,
        window=name,
        integrated_power=integrated,
        variance=variance,
        ratio=integrated/variance,
        peaks=peaks
    )
end
function analyze_spectrogram(signal,params,fs)
    n,hop,band_db,name = params.spectrogram
    grid,error = spectrogram_magnitudes(signal,n,hop,name)
    frames = length(grid)
    largest = maximum(maximum(row) for row in grid)
    dominant = NamedTuple[]
    for (t,row) in enumerate(grid)
        k = argmax(row[2:n÷2])
        push!(dominant,(frame=t-1,time=(t-1)*hop/fs,frequency=k*fs/n,level_db=db(row[k+1]/largest)))
    end
    flux = vcat([0.0],[ordered_sum(max(0.0,grid[t][k]-grid[t-1][k]) for k in 1:n÷2+1) for t in 2:frames])
    threshold = params.onset_factor*median(flux[2:end])
    onsets = [t for t in 1:frames-1 if flux[t+1]>threshold && flux[t+1]>flux[t] && (t==frames-1 || flux[t+1]>flux[t+2])]
    kurtosis = [frames*ordered_sum(row[k]^4 for row in grid)/ordered_sum(row[k]^2 for row in grid)^2-2 for k in 1:n÷2+1]
    top = argmax(kurtosis[2:n÷2])
    (grid=grid,frames=frames,maximum=largest,length=n,hop=hop,band_db=band_db,window=name,dominant=dominant,flux=flux,onsets=onsets,
        onset_threshold=threshold,kurtosis=kurtosis,top_kurtosis=top,packing_error=error)
end
function filtered_waveforms(x,y,params,fs)
    n = length(x)
    spectrum = dft(x)
    low,high = params.bandpass
    notch,width = params.notch
    filtered,notched = zeros(ComplexF64,n),copy(spectrum)
    kept,removed = 0,0
    for k in 0:n-1
        numerator = min(k,n-k)*fs
        if low*n<=numerator<=high*n
            filtered[k+1] = spectrum[k+1]
            kept += 1
        end
        nearest = (2numerator+notch*n)÷(2notch*n)
        if nearest>=1 && abs(numerator-nearest*notch*n)<=width*n
            notched[k+1] = 0
            removed += 1
        end
    end
    bandpassed,notch_result = real.(idft(filtered)),real.(idft(notched))
    e1,e2 = params.envelope_band
    analytic_spectrum = zeros(ComplexF64,n)
    for k in 1:(n-1)÷2
        e1*n<=k*fs<=e2*n && (analytic_spectrum[k+1]=2spectrum[k+1])
    end
    analytic = idft(analytic_spectrum)
    envelope = abs.(analytic)
    mean = ordered_sum(envelope)/n
    modulation = 2abs.(dft(envelope.-mean))./n
    stop = ((e2-e1)*n)÷(2fs)
    k = argmax(modulation[2:stop+1])
    position,amplitude = interpolate(modulation,k)
    instantaneous = Float64[]
    for i in 2:n
        delta = angle(analytic[i])-angle(analytic[i-1])
        delta<=-PI && (delta+=2PI)
        delta>PI && (delta-=2PI)
        push!(instantaneous,delta*fs/(2PI))
    end
    frequency_mean = ordered_sum(instantaneous)/(n-1)
    frequency_std = sqrt(ordered_sum((v-frequency_mean)^2 for v in instantaneous)/(n-1))
    taps = params.fir
    smoothed = convolution(y,taps)
    gain = ordered_sum(taps[j+1]*rot(2PI*params.fundamental[1]*j/fs) for j in 0:length(taps)-1)
    direct = [ordered_sum(y[j+1]*taps[i-j+1] for j in max(
        0,
        i-length(taps)+1
    ):min(n-1,i)) for i in 0:n+length(taps)-2]
    (bandpassed=bandpassed,notched=notch_result,smoothed=smoothed,envelope=envelope,bins_kept=kept,bins_removed=removed,bandpass_rms=rms(bandpassed),
        notch_rms=rms(notch_result),bandpass_ratio=ordered_sum(v*v for v in bandpassed)/ordered_sum(v*v for v in x),fir_taps=length(taps),dc_gain=ordered_sum(taps),
        gain_at_fundamental_db=db(abs(gain)),fir_rms=sqrt(ordered_sum(smoothed[i]^2 for i in 1:n)/n),fir_error=maximum(abs.(smoothed.-direct)),
        envelope_mean=mean,envelope_bin=k,envelope_frequency=position*fs/n,envelope_amplitude=amplitude,envelope_depth=amplitude/mean,
        instantaneous_mean=frequency_mean,instantaneous_std=frequency_std)
end
function estimate_pitch(amplitudes,bandpassed,params,fs)
    m,n = params.main_length,length(bandpassed)
    low,high = params.pitch_range
    lag_min,lag_max = (fs+high-1)÷high,fs÷low
    indices = [k for k in 1:m÷2 if low*m<=k*fs<=high*m && 5k<=m÷2]
    scores = [ordered_sum(log(amplitudes[r*k+1]) for r in 1:5) for k in indices]
    hps = indices[argmax(scores)]
    q = pow2(2n-1)
    transformed = radix2(vcat(bandpassed,zeros(q-n)))
    acf = real.(radix2(ComplexF64.(abs2.(transformed)),true))
    lag = lag_min+argmax(acf[lag_min+1:lag_max+1])-1
    period,strength = interpolate(acf,lag,false)
    crossings = count(i->bandpassed[i-1]<0<=bandpassed[i],2:n)
    (lag_min=lag_min,lag_max=lag_max,hps_bin=hps,hps_frequency=hps*fs/m,acf_lag=lag,acf_period=period,acf_frequency=fs/period,
        acf_strength=strength/acf[1],crossings=crossings,crossing_frequency=crossings*fs/n)
end
function analyze_zoom(weighted,s1,params,fs)
    low,high,points = params.zoom
    step = (high-low)/(points-1)
    amplitudes = 2abs.(chirp_z(weighted,fs,low,high,points))./s1
    peaks = NamedTuple[]
    for (rank,k) in enumerate(strongest_local_maxima(amplitudes,3))
        position,amplitude = interpolate(amplitudes,k)
        push!(peaks,(peak=rank,frequency=low+position*step,amplitude=amplitude))
    end
    (low=low,high=high,points=points,step=step,peaks=peaks)
end
function choose_lag(sequence,limit)
    n = length(sequence)
    lags = collect(-limit:limit)
    sort!(lags;by=lag->(-sequence[mod(lag,n)+1],abs(lag),lag))
    lag = lags[1]
    neighborhood = [sequence[mod(lag+offset,n)+1] for offset in -1:1]
    position,_ = interpolate(neighborhood,1,false)
    lag,lag+position-1
end
function analyze_correlation(x,y,limit,fs)
    n = length(x)
    q = pow2(2n-1)
    fx,fy = radix2(vcat(x,zeros(q-n))),radix2(vcat(y,zeros(q-n)))
    cross = conj.(fx).*fy
    raw = real.(radix2(cross,true))
    phat = real.(radix2(cross./abs.(cross),true))
    lag,refined = choose_lag(raw,limit)
    pl,pr = choose_lag(phat,limit)
    coefficient = raw[mod(lag,q)+1]/sqrt(ordered_sum(v*v for v in x)*ordered_sum(v*v for v in y))
    (
        lag=lag,
        refined_lag=refined,
        delay_ms=1000refined/fs,
        coefficient=coefficient,
        phat_lag=pl,
        phat_refined=pr,
        phat_delay_ms=1000pr/fs
    )
end
function transform_checks(weighted,transformed,peaks,filters,welch,spectrogram)
    n = length(weighted)
    inverse_error = maximum(abs.(idft(transformed).-weighted))
    time_energy = ordered_sum(v*v for v in weighted)
    frequency_energy = ordered_sum(abs2(v) for v in transformed)/n
    spot_error = 0.0
    for peak in peaks
        direct = ordered_sum(weighted[j+1]*rot(2PI*mod(peak.bin*j,n)/n) for j in 0:n-1)
        spot_error = max(spot_error,abs(direct-transformed[peak.bin+1]))
    end
    (inverse_roundtrip=inverse_error<=1e-6,parseval=abs(time_energy-frequency_energy)/time_energy<=1e-6,
        real_packing=max(
            welch.packing_error,
            spectrogram.packing_error
        )<=1e-6,fir_fft_vs_direct=filters.fir_error<=1e-6,dft_spot_check=spot_error<=1e-6)
end
function render_outputs(fs,x,y,sx,sy,params)
    m,n = params.main_length,length(x)
    history,loudest = level_history(x,y,params.block_length)
    weighted,transformed,amplitudes = amplitude_spectrum(x,params.main_window,m)
    calibration = figures(window(params.main_window,m),fs)
    welch = analyze_welch(x,y,params,fs)
    peaks,largest,noise = main_peaks(amplitudes,transformed,params,fs,welch)
    harmonics,thd = harmonic_analysis(amplitudes,params,fs)
    power,powers = power_analysis(amplitudes,params,fs,harmonics,calibration.enbw_bins)
    bands,octaves = calculate_bands(power,params,fs,calibration.enbw_bins,powers.total_power)
    comparison = compare_windows(x,params,fs)
    spectrogram = analyze_spectrogram(x,params,fs)
    filters = filtered_waveforms(x,y,params,fs)
    pitch = estimate_pitch(amplitudes,filters.bandpassed,params,fs)
    zoom = analyze_zoom(weighted,calibration.s1,params,fs)
    correlation = analyze_correlation(x,y,params.max_lag,fs)
    checks = transform_checks(weighted,transformed,peaks,filters,welch,spectrogram)
    peak_lines = [
        fields(length=m,window=params.main_window,resolution=fs/m,threshold_db=params.peak_threshold_db),
        fields(max_amplitude=largest,noise_floor=noise,noise_floor_db=db(noise)),
        fields(peaks=length(peaks))
    ]
    for p in peaks
        push!(
            peak_lines,
            "$(p.rank) "*fields(
                bin=p.bin,
                frequency=p.frequency,
                refined=p.refined,
                amplitude=p.amplitude,
                level_db=p.level_db,
                phase=p.phase,
                bandwidth=p.bandwidth,
                snr_db=p.snr_db,
                coherence=p.coherence,
                label=p.label
            )
        )
    end
    s = spectrogram
    spec_lines = [fields(
        frames=s.frames,
        bins=s.length÷2+1,
        frame_length=s.length,
        hop=s.hop,
        window=s.window,
        band_db=s.band_db,
        max_db=db(s.maximum)
    )]
    append!(spec_lines,shade_lines(s.grid,fs,s.length,s.band_db))
    push!(spec_lines,"track")
    append!(spec_lines,[fields(;row...) for row in s.dominant])
    push!(spec_lines,fields(onsets=length(s.onsets),threshold=s.onset_threshold))
    for t in s.onsets
        push!(spec_lines,fields(frame=t,time=t*s.hop/fs,flux=s.flux[t+1]))
    end
    k = s.top_kurtosis
    push!(spec_lines,"kurtosis "*fields(bin=k,frequency=k*fs/s.length,value=s.kurtosis[k+1]))
    lines = [
        "[signal]",
        fields(sample_rate=fs,samples=n,duration=n/fs),
        fields(;channel=1,sx...),
        fields(;channel=2,sy...),
        "[levels]",
        fields(block_length=params.block_length,blocks=length(history),loudest=loudest)
    ]
    for row in history
        push!(
            lines,
            fields(
                block=row.number,
                time=row.number*params.block_length/fs,
                rms1=row.rms1,
                rms2=row.rms2,
                peak1=row.peak1
            )
        )
    end
    push!(lines,"[windows]")
    append!(lines,[fields(;row...) for row in comparison])
    push!(lines,"[main]",fields(length=m,window=params.main_window,method=ispow2(m) ? "radix2" : "bluestein",transform_size=ispow2(m) ? m : pow2(2m-1),resolution=fs/m),
        fields(
            total_power=powers.total_power,
            centroid=powers.centroid,
            spread=powers.spread,
            rolloff=powers.rolloff,
            flatness_db=powers.flatness_db
        ),"[bands]")
    append!(lines,[fields(;row...) for row in bands])
    push!(lines,"[third_octave]")
    append!(lines,[fields(;row...) for row in octaves])
    push!(lines,"[harmonics]",fields(fundamental=params.fundamental[1],search=params.fundamental[2]))
    for h in harmonics
        push!(
            lines,
            fields(
                h=h.number,
                target=h.target,
                bin=h.bin,
                refined=h.frequency,
                amplitude=h.amplitude,
                level_db=h.level_db
            )
        )
    end
    push!(lines,fields(;thd...),fields(thdn_percent=powers.thdn_percent,thdn_db=powers.thdn_db),"[pitch]",
        fields(
            range=join(params.pitch_range,"-"),
            lags="$(pitch.lag_min)-$(pitch.lag_max)"
        ),"hps "*fields(bin=pitch.hps_bin,order=5,frequency=pitch.hps_frequency),
        "autocorrelation "*fields(
            lag=pitch.acf_lag,
            period=pitch.acf_period,
            frequency=pitch.acf_frequency,
            strength=pitch.acf_strength
        ),
        "zero_crossing "*fields(count=pitch.crossings,frequency=pitch.crossing_frequency),"[zoom]",fields(
            band="$(zoom.low)-$(zoom.high)",
            points=zoom.points,
            step=zoom.step
        ))
    append!(lines,[fields(;row...) for row in zoom.peaks])
    push!(
        lines,
        "[welch]",
        fields(
            segment_length=welch.length,
            segments=welch.segments,
            window=welch.window,
            resolution=fs/welch.length
        ),
        fields(integrated_power=welch.integrated_power,variance=welch.variance,ratio=welch.ratio)
    )
    append!(lines,[fields(;row...) for row in welch.peaks])
    push!(lines,"[filter]",fields(bandpass=join(params.bandpass,"-"),bins_kept=filters.bins_kept,rms=filters.bandpass_rms,energy_ratio=filters.bandpass_ratio),
        fields(notch=params.notch[1],width=params.notch[2],bins_removed=filters.bins_removed,rms=filters.notch_rms),fields(
            fir_taps=filters.fir_taps,
            dc_gain=filters.dc_gain,
            gain_at_fundamental_db=filters.gain_at_fundamental_db,
            rms=filters.fir_rms
        ),
        "[envelope]",fields(
            band=join(params.envelope_band,"-"),
            mean=filters.envelope_mean,
            bin=filters.envelope_bin,
            frequency=filters.envelope_frequency,
            amplitude=filters.envelope_amplitude,
            depth=filters.envelope_depth
        ),
        "instantaneous_frequency "*fields(mean=filters.instantaneous_mean,std=filters.instantaneous_std),"[correlation]",fields(
            max_lag=params.max_lag,
            lag=correlation.lag,
            refined_lag=correlation.refined_lag,
            delay_ms=correlation.delay_ms,
            coefficient=correlation.coefficient
        ),
        fields(
            phat_lag=correlation.phat_lag,
            refined_lag=correlation.phat_refined,
            delay_ms=correlation.phat_delay_ms
        ),"[checks]")
    for (name,value) in pairs(checks)
        line = "$name=$(value ? "ok" : "failed")"
        name==:real_packing && (line*=" transforms=$(2welch.segments+s.frames)")
        name==:dft_spot_check && (line*=" bins=$(length(peaks))")
        push!(lines,line)
    end
    ratio = harmonics[2].amplitude/harmonics[1].amplitude
    looseness = count(h->h.level_db>=-30,harmonics[3:end])
    mains = findfirst(p->p.label=="mains",peaks)
    electrical = !isnothing(mains) && peaks[mains].level_db>=-20
    symptoms = (ratio>=0.5,looseness>=3,filters.envelope_depth>=0.2,electrical,!isempty(s.onsets))
    findings = sum(symptoms)
    yesno(value) = value ? "yes" : "no"
    push!(lines,"[diagnosis]",fields(misalignment=yesno(symptoms[1]),ratio=ratio),fields(looseness=yesno(symptoms[2]),harmonics=looseness),
        fields(bearing=yesno(symptoms[3]),depth=filters.envelope_depth),fields(
            electrical=yesno(electrical),
            level_db=isnothing(mains) ? "none" : real_text(peaks[mains].level_db)
        ),
        fields(transient=yesno(symptoms[5]),onsets=length(s.onsets)),fields(
            status=findings==0 ? "normal" : findings==1 ? "warning" : "alarm",
            findings=findings
        ))
    write_csv("spectrum.csv","frequency,amplitude",[(k*fs/m,amplitudes[k+1]) for k in 0:m÷2])
    write_lines("peaks.txt",peak_lines)
    write_csv(
        "welch_psd.csv",
        "frequency,psd_db",
        [(k*fs/welch.length,db(value,10)) for (k,value) in zip(0:welch.length÷2,welch.psd)]
    )
    write_lines("spectrogram.txt",spec_lines)
    write_csv(
        "filtered.csv",
        "index,bandpass,notched,smoothed,envelope",
        [(
            i,
            filters.bandpassed[i+1],
            filters.notched[i+1],
            filters.smoothed[i+1],
            filters.envelope[i+1]
        ) for i in 0:n-1]
    )
    write_lines("report.txt",lines)
end
function main()
    fs,raw_x,raw_y = read_signal()
    params = read_params()
    x,sx = detrend(raw_x,fs)
    y,sy = detrend(raw_y,fs)
    render_outputs(fs,x,y,sx,sy,params)
end
main()
