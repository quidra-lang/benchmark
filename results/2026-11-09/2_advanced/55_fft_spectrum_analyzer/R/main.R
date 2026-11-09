for (module in c("signal_io","fft","windows","spectral","report")) source(paste0(module,".R"))
mean_square <- function(values) ordered_sum(values*values)/length(values)
rms <- function(values) sqrt(mean_square(values))
db <- function(value,factor=20) factor*log10(value)
phase_degrees <- function(value) Arg(value)*180/PI
row_fields <- function(row) do.call(fields,row)
detrend <- function(samples,fs) {
  n <- length(samples)
  center <- (n-1L)/2
  average <- ordered_sum(samples)/n
  indices <- seq_len(n)-1L
  slope <- ordered_sum((indices-center)*(samples-average))/ordered_sum((indices-center)^2)
  residual <- samples-average-slope*(indices-center)
  level <- rms(residual)
  list(values=residual,stats=list(mean=average,slope=slope*fs,rms=level,min=min(samples),max=max(samples),crest=max(abs(residual))/level,
    skewness=(ordered_sum(residual^3)/n)/level^3,kurtosis=(ordered_sum(residual^4)/n)/level^4))
}
level_history <- function(x,y,block_length) {
  history <- list()
  for (g in seq_len(length(x) %/% block_length)-1L) {
    indices <- seq.int(g*block_length+1L,(g+1L)*block_length)
    history[[g+1L]] <- list(number=g,rms1=rms(x[indices]),rms2=rms(y[indices]),peak1=max(abs(x[indices])))
  }
  list(history=history,loudest=which.max(vapply(history,function(row) row$rms1,numeric(1)))-1L)
}
strongest_local_maxima <- function(values,limit) {
  candidates <- Filter(function(k) local_maximum(values,k),seq.int(1L,length(values)-2L))
  candidates <- candidates[order(-values[candidates+1L],candidates)]
  head(candidates,limit)
}
amplitude_bandwidth <- function(amplitudes,k) {
  last <- length(amplitudes)-1L
  cutoff <- amplitudes[k+1L]/sqrt(2)
  right <- as.numeric(last)
  left <- 0
  for (j in seq.int(k+1L,last)) if (amplitudes[j+1L] <= cutoff) {
    right <- j-1L+(amplitudes[j]-cutoff)/(amplitudes[j]-amplitudes[j+1L])
    break
  }
  for (j in seq.int(k-1L,0L)) if (amplitudes[j+1L] <= cutoff) {
    left <- j+1L-(amplitudes[j+2L]-cutoff)/(amplitudes[j+2L]-amplitudes[j+1L])
    break
  }
  right-left
}
label_peak <- function(peak,peaks,params,fs) {
  nominal <- params$fundamental[[1L]]
  width <- params$fundamental[[2L]]
  notch <- params$notch[1L]
  notch_width <- params$notch[2L]
  for (h in seq_len(10L)) if (abs(peak$position-h*nominal*params$main_length/fs) <= width) return(paste0(
      "h",
      h
  ))
  frequency <- peak$position*fs/params$main_length
  multiple <- floor(frequency/notch+0.5)
  if (multiple >= 1 && abs(frequency-multiple*notch) <= notch_width) return("mains")
  for (pivot in peaks) {
    if (pivot$rank == peak$rank || pivot$bin_amplitude <= peak$bin_amplitude) next
    for (other in peaks) {
      if (other$rank %in% c(peak$rank,pivot$rank)) next
      if (pivot$bin_amplitude > other$bin_amplitude && abs(peak$position+other$position-2*pivot$position) <= 1) return(paste0(
          "sideband",
          pivot$rank
      ))
    }
  }
  "other"
}
main_peaks <- function(amplitudes,transformed,params,fs,welch) {
  m <- params$main_length
  L <- params$welch[[1L]]
  largest <- max(amplitudes)
  noise <- median_value(amplitudes[-c(1L,length(amplitudes))])
  candidates <- strongest_local_maxima(amplitudes,length(amplitudes))
  candidates <- head(
      candidates[db(amplitudes[candidates+1L]/largest) >= params$peak_threshold_db],
      params$peak_count
  )
  peaks <- list()
  for (rank in seq_along(candidates)) {
    k <- candidates[rank]
    fitted <- interpolate(amplitudes,k)
    position <- fitted[1L]
    j <- (2L*k*L+m) %/% (2L*m)
    peaks[[rank]] <- list(rank=rank,bin=k,position=position,bin_amplitude=amplitudes[k+1L],frequency=k*fs/m,refined=position*fs/m,amplitude=fitted[2L],
      level_db=db(amplitudes[k+1L]/largest),phase=phase_degrees(transformed[k+1L]),bandwidth=amplitude_bandwidth(
          amplitudes,
          k
      )*fs/m,
      snr_db=db(amplitudes[k+1L]/noise),coherence=welch$coherence[j+1L])
  }
  for (rank in seq_along(peaks)) peaks[[rank]]$label <- label_peak(peaks[[rank]],peaks,params,fs)
  list(peaks=peaks,largest=largest,noise=noise)
}
harmonic_analysis <- function(amplitudes,params,fs) {
  m <- params$main_length
  nominal <- params$fundamental[[1L]]
  width <- params$fundamental[[2L]]
  harmonics <- list()
  for (h in seq_len(10L)) {
    center <- h*nominal*m/fs
    indices <- seq.int(1L,m %/% 2L-1L)
    indices <- indices[abs(indices-center) <= width]
    k <- indices[which.max(amplitudes[indices+1L])]
    fitted <- interpolate(amplitudes,k)
    harmonics[[h]] <- list(
        number=h,
        target=h*nominal,
        bin=k,
        position=fitted[1L],
        frequency=fitted[1L]*fs/m,
        amplitude=fitted[2L]
    )
  }
  primary <- harmonics[[1L]]$amplitude
  for (h in seq_along(harmonics)) harmonics[[h]]$level_db <- db(harmonics[[h]]$amplitude/primary)
  thd <- sqrt(ordered_sum(vapply(harmonics[-1L],function(row) row$amplitude^2,numeric(1))))/primary
  list(harmonics=harmonics,thd=list(thd_percent=100*thd,thd_db=db(thd)))
}
power_analysis <- function(amplitudes,params,fs,harmonics,enbw) {
  m <- params$main_length
  half <- m %/% 2L
  power <- amplitudes^2/2
  indices <- seq.int(1L,half-1L)
  total <- ordered_sum(power[indices+1L])
  total_power <- total/enbw
  primary <- ordered_sum(power[indices[abs(indices-harmonics[[1L]]$bin) <= params$fundamental[[2L]]]+1L])/enbw
  thdn <- sqrt((total_power-primary)/primary)
  centroid <- ordered_sum(indices*fs/m*power[indices+1L])/total
  spread <- sqrt(ordered_sum((indices*fs/m-centroid)^2*power[indices+1L])/total)
  cumulative <- rolloff <- 0
  for (k in indices) {
    cumulative <- cumulative+power[k+1L]
    if (cumulative >= 0.85*total) {
      rolloff <- k*fs/m
      break
    }
  }
  flatness <- db(exp(ordered_sum(log(power[indices+1L]))/(half-1L))/(total/(half-1L)),10)
  list(
      power=power,
      summary=list(
          total_power=total_power,
          centroid=centroid,
          spread=spread,
          rolloff=rolloff,
          flatness_db=flatness,
          thdn_percent=100*thdn,
          thdn_db=db(thdn)
      )
  )
}
calculate_bands <- function(power,params,fs,enbw,total_power) {
  m <- params$main_length
  bands <- octaves <- list()
  interior <- seq.int(1L,m %/% 2L-1L)
  for (i in seq_len(length(params$bands)-1L)) {
    low <- params$bands[i]
    high <- params$bands[i+1L]
    indices <- interior[low*m <= interior*fs & interior*fs < high*m]
    value <- ordered_sum(power[indices+1L])/enbw
    bands[[i]] <- list(range=paste0(low,"-",high),power=value,percent=100*value/total_power)
  }
  for (b in seq.int(params$third_octave[1L],params$third_octave[2L])) {
    center <- 1000*2^(b/3)
    low <- 1000*2^((2*b-1)/6)
    high <- 1000*2^((2*b+1)/6)
    indices <- interior[low <= interior*fs/m & interior*fs/m < high]
    value <- ordered_sum(power[indices+1L])/enbw
    octaves[[length(octaves)+1L]] <- list(
        band=b,
        center=center,
        lower=low,
        upper=high,
        bins=length(indices),
        level_db=db(value,10)
    )
  }
  list(bands=bands,octaves=octaves)
}
compare_windows <- function(signal,params,fs) {
  m <- params$main_length
  nominal <- params$fundamental[[1L]]
  width <- params$fundamental[[2L]]
  rows <- list()
  for (name in WINDOW_ORDER) {
    calibration <- figures(window(name,m),fs)
    amplitudes <- amplitude_spectrum(signal,name,m)$amplitudes
    indices <- seq.int(1L,m %/% 2L-1L)
    indices <- indices[abs(indices-nominal*m/fs) <= width]
    k <- indices[which.max(amplitudes[indices+1L])]
    refined <- interpolate(amplitudes,k)[2L]
    rows[[length(rows)+1L]] <- list(name=name,coherent_gain=calibration$coherent_gain,enbw_bins=calibration$enbw_bins,enbw_hz=calibration$enbw_hz,
      scalloping_db=calibration$scalloping_db,fundamental_bin=k,bin_amplitude=amplitudes[k+1L],refined_amplitude=refined,floor_db=db(median_value(amplitudes[-c(
          1L,
          length(amplitudes)
      )])) )
  }
  rows
}
analyze_welch <- function(x,y,params,fs) {
  n <- params$welch[[1L]]
  name <- params$welch[[2L]]
  result <- welch_spectra(x,y,fs,n,name)
  integrated <- ordered_sum(result$psd)*fs/n
  variance <- mean_square(x)
  peaks <- list()
  candidates <- strongest_local_maxima(result$psd,5L)
  for (rank in seq_along(candidates)) {
    k <- candidates[rank]
    transfer <- result$transfer[k+1L]
    peaks[[rank]] <- list(
        peak=rank,
        frequency=k*fs/n,
        psd_db=db(result$psd[k+1L],10),
        coherence=result$coherence[k+1L],
        gain=Mod(transfer),
        phase=phase_degrees(transfer)
    )
  }
  c(
      result,
      list(
          length=n,
          window=name,
          integrated_power=integrated,
          variance=variance,
          ratio=integrated/variance,
          peaks=peaks
      )
  )
}
analyze_spectrogram <- function(signal,params,fs) {
  n <- params$spectrogram[[1L]]
  hop <- params$spectrogram[[2L]]
  band_db <- params$spectrogram[[3L]]
  name <- params$spectrogram[[4L]]
  transformed <- spectrogram_magnitudes(signal,n,hop,name)
  grid <- transformed$grid
  frames <- length(grid)
  largest <- max(unlist(grid,use.names=FALSE))
  dominant <- list()
  for (t in seq_along(grid)) {
    row <- grid[[t]]
    k <- which.max(row[seq.int(2L,n %/% 2L)])
    dominant[[t]] <- list(frame=t-1L,time=(t-1L)*hop/fs,frequency=k*fs/n,level_db=db(row[k+1L]/largest))
  }
  flux <- numeric(frames)
  for (t in seq.int(2L,frames)) flux[t] <- ordered_sum(pmax(0,grid[[t]]-grid[[t-1L]]))
  threshold <- params$onset_factor*median_value(flux[-1L])
  onsets <- Filter(
      function(t) flux[t+1L] > threshold && flux[t+1L] > flux[t] && (t == frames-1L || flux[t+1L] > flux[t+2L]),
      seq_len(frames-1L)
  )
  kurtosis <- vapply(seq_len(n %/% 2L+1L),function(k) {
    values <- vapply(grid,`[`,numeric(1),k)
    frames*ordered_sum(values^4)/ordered_sum(values^2)^2-2
  },numeric(1))
  top <- which.max(kurtosis[seq.int(2L,n %/% 2L)])
  list(grid=grid,frames=frames,maximum=largest,length=n,hop=hop,band_db=band_db,window=name,dominant=dominant,flux=flux,onsets=onsets,
    onset_threshold=threshold,kurtosis=kurtosis,top_kurtosis=top,packing_error=transformed$error)
}
filtered_waveforms <- function(x,y,params,fs) {
  n <- length(x)
  spectrum <- dft(x)
  low <- params$bandpass[1L]
  high <- params$bandpass[2L]
  notch <- params$notch[1L]
  width <- params$notch[2L]
  filtered <- complex(n)
  notched <- spectrum
  kept <- removed <- 0L
  for (k in seq_len(n)-1L) {
    numerator <- min(k,n-k)*fs
    if (low*n <= numerator && numerator <= high*n) {
      filtered[k+1L] <- spectrum[k+1L]
      kept <- kept+1L
    }
    nearest <- (2L*numerator+notch*n) %/% (2L*notch*n)
    if (nearest >= 1L && abs(numerator-nearest*notch*n) <= width*n) {
      notched[k+1L] <- 0
      removed <- removed+1L
    }
  }
  bandpassed <- Re(idft(filtered))
  notch_result <- Re(idft(notched))
  e1 <- params$envelope_band[1L]
  e2 <- params$envelope_band[2L]
  analytic_spectrum <- complex(n)
  for (k in seq_len((n-1L) %/% 2L)) if (e1*n <= k*fs && k*fs <= e2*n) analytic_spectrum[k+1L] <- 2*spectrum[k+1L]
  analytic <- idft(analytic_spectrum)
  envelope <- Mod(analytic)
  mean <- ordered_sum(envelope)/n
  modulation <- 2*Mod(dft(envelope-mean))/n
  stop <- ((e2-e1)*n) %/% (2L*fs)
  k <- which.max(modulation[seq.int(2L,stop+1L)])
  fitted <- interpolate(modulation,k)
  instantaneous <- numeric(n-1L)
  for (i in seq.int(2L,n)) {
    delta <- Arg(analytic[i])-Arg(analytic[i-1L])
    if (delta <= -PI) delta <- delta+2*PI
    if (delta > PI) delta <- delta-2*PI
    instantaneous[i-1L] <- delta*fs/(2*PI)
  }
  frequency_mean <- ordered_sum(instantaneous)/(n-1L)
  frequency_std <- sqrt(ordered_sum((instantaneous-frequency_mean)^2)/(n-1L))
  taps <- params$fir
  smoothed <- convolution(y,taps)
  j <- seq_along(taps)-1L
  gain <- ordered_sum(taps*rot(2*PI*params$fundamental[[1L]]*j/fs))
  direct <- vapply(seq_len(n+length(taps)-1L)-1L,function(i) {
    j <- seq.int(max(0L,i-length(taps)+1L),min(n-1L,i))
    ordered_sum(y[j+1L]*taps[i-j+1L])
  },numeric(1))
  list(bandpassed=bandpassed,notched=notch_result,smoothed=smoothed,envelope=envelope,bins_kept=kept,bins_removed=removed,bandpass_rms=rms(bandpassed),
    notch_rms=rms(notch_result),bandpass_ratio=ordered_sum(bandpassed^2)/ordered_sum(x^2),fir_taps=length(taps),dc_gain=ordered_sum(taps),
    gain_at_fundamental_db=db(Mod(gain)),fir_rms=sqrt(ordered_sum(smoothed[seq_len(n)]^2)/n),fir_error=max(abs(smoothed-direct)),
    envelope_mean=mean,envelope_bin=k,envelope_frequency=fitted[1L]*fs/n,envelope_amplitude=fitted[2L],envelope_depth=fitted[2L]/mean,
    instantaneous_mean=frequency_mean,instantaneous_std=frequency_std)
}
estimate_pitch <- function(amplitudes,bandpassed,params,fs) {
  m <- params$main_length
  n <- length(bandpassed)
  low <- params$pitch_range[1L]
  high <- params$pitch_range[2L]
  lag_min <- (fs+high-1L) %/% high
  lag_max <- fs %/% low
  indices <- seq_len(m %/% 2L)
  indices <- indices[low*m <= indices*fs & indices*fs <= high*m & 5L*indices <= m %/% 2L]
  scores <- vapply(indices,function(k) ordered_sum(log(amplitudes[seq_len(5L)*k+1L])),numeric(1))
  hps <- indices[which.max(scores)]
  q <- pow2(2L*n-1L)
  transformed <- radix2(c(bandpassed,numeric(q-n)))
  acf <- Re(radix2(as.complex(Mod(transformed)^2),TRUE))
  lag <- lag_min+which.max(acf[seq.int(lag_min+1L,lag_max+1L)])-1L
  fitted <- interpolate(acf,lag,FALSE)
  crossings <- sum(head(bandpassed,-1L) < 0 & tail(bandpassed,-1L) >= 0)
  list(lag_min=lag_min,lag_max=lag_max,hps_bin=hps,hps_frequency=hps*fs/m,acf_lag=lag,acf_period=fitted[1L],acf_frequency=fs/fitted[1L],
    acf_strength=fitted[2L]/acf[1L],crossings=crossings,crossing_frequency=crossings*fs/n)
}
analyze_zoom <- function(weighted,s1,params,fs) {
  low <- params$zoom[1L]
  high <- params$zoom[2L]
  points <- params$zoom[3L]
  step <- (high-low)/(points-1L)
  amplitudes <- 2*Mod(chirp_z(weighted,fs,low,high,points))/s1
  peaks <- list()
  candidates <- strongest_local_maxima(amplitudes,3L)
  for (rank in seq_along(candidates)) {
    fitted <- interpolate(amplitudes,candidates[rank])
    peaks[[rank]] <- list(peak=rank,frequency=low+fitted[1L]*step,amplitude=fitted[2L])
  }
  list(low=low,high=high,points=points,step=step,peaks=peaks)
}
choose_lag <- function(sequence,limit) {
  n <- length(sequence)
  lags <- seq.int(-limit,limit)
  lag <- lags[order(-sequence[lags %% n+1L],abs(lags),lags)[1L]]
  neighborhood <- sequence[(lag+seq.int(-1L,1L)) %% n+1L]
  position <- interpolate(neighborhood,1L,FALSE)[1L]
  list(lag=lag,refined=lag+position-1L)
}
analyze_correlation <- function(x,y,limit,fs) {
  n <- length(x)
  q <- pow2(2L*n-1L)
  fx <- radix2(c(x,numeric(q-n)))
  fy <- radix2(c(y,numeric(q-n)))
  cross <- Conj(fx)*fy
  raw <- Re(radix2(cross,TRUE))
  phat <- Re(radix2(cross/Mod(cross),TRUE))
  selected <- choose_lag(raw,limit)
  phased <- choose_lag(phat,limit)
  coefficient <- raw[selected$lag %% q+1L]/sqrt(ordered_sum(x*x)*ordered_sum(y*y))
  list(lag=selected$lag,refined_lag=selected$refined,delay_ms=1000*selected$refined/fs,coefficient=coefficient,
    phat_lag=phased$lag,phat_refined=phased$refined,phat_delay_ms=1000*phased$refined/fs)
}
transform_checks <- function(weighted,transformed,peaks,filters,welch,spectrogram) {
  n <- length(weighted)
  inverse_error <- max(Mod(idft(transformed)-weighted))
  time_energy <- ordered_sum(weighted*weighted)
  frequency_energy <- ordered_sum(Mod(transformed)^2)/n
  spot_error <- 0
  for (peak in peaks) {
    j <- seq_len(n)-1L
    direct <- ordered_sum(weighted*rot(2*PI*((peak$bin*j) %% n)/n))
    spot_error <- max(spot_error,Mod(direct-transformed[peak$bin+1L]))
  }
  list(inverse_roundtrip=inverse_error <= 1e-6,parseval=abs(time_energy-frequency_energy)/time_energy <= 1e-6,
    real_packing=max(
        welch$packing_error,
        spectrogram$packing_error
    ) <= 1e-6,fir_fft_vs_direct=filters$fir_error <= 1e-6,dft_spot_check=spot_error <= 1e-6)
}
render_outputs <- function(fs,x,y,sx,sy,params) {
  m <- params$main_length
  n <- length(x)
  levels <- level_history(x,y,params$block_length)
  history <- levels$history
  main <- amplitude_spectrum(x,params$main_window,m)
  amplitudes <- main$amplitudes
  calibration <- figures(window(params$main_window,m),fs)
  welch <- analyze_welch(x,y,params,fs)
  peak_data <- main_peaks(amplitudes,main$transformed,params,fs,welch)
  peaks <- peak_data$peaks
  harmonic_data <- harmonic_analysis(amplitudes,params,fs)
  harmonics <- harmonic_data$harmonics
  power_data <- power_analysis(amplitudes,params,fs,harmonics,calibration$enbw_bins)
  powers <- power_data$summary
  band_data <- calculate_bands(power_data$power,params,fs,calibration$enbw_bins,powers$total_power)
  comparison <- compare_windows(x,params,fs)
  s <- analyze_spectrogram(x,params,fs)
  filters <- filtered_waveforms(x,y,params,fs)
  pitch <- estimate_pitch(amplitudes,filters$bandpassed,params,fs)
  zoom <- analyze_zoom(main$weighted,calibration$s1,params,fs)
  correlation <- analyze_correlation(x,y,params$max_lag,fs)
  checks <- transform_checks(main$weighted,main$transformed,peaks,filters,welch,s)
  peak_lines <- c(fields(length=m,window=params$main_window,resolution=fs/m,threshold_db=params$peak_threshold_db),
    fields(
        max_amplitude=peak_data$largest,
        noise_floor=peak_data$noise,
        noise_floor_db=db(peak_data$noise)
    ),fields(peaks=length(peaks)))
  for (p in peaks) peak_lines <- c(peak_lines,paste(p$rank,fields(bin=p$bin,frequency=p$frequency,refined=p$refined,amplitude=p$amplitude,level_db=p$level_db,
    phase=p$phase,bandwidth=p$bandwidth,snr_db=p$snr_db,coherence=p$coherence,label=p$label)))
  spec_lines <- c(fields(frames=s$frames,bins=s$length %/% 2L+1L,frame_length=s$length,hop=s$hop,window=s$window,band_db=s$band_db,max_db=db(s$maximum)),
    shade_lines(s$grid,fs,s$length,s$band_db),"track",vapply(s$dominant,row_fields,character(1)),fields(
        onsets=length(s$onsets),
        threshold=s$onset_threshold
    ))
  for (t in s$onsets) spec_lines <- c(spec_lines,fields(frame=t,time=t*s$hop/fs,flux=s$flux[t+1L]))
  k <- s$top_kurtosis
  spec_lines <- c(spec_lines,paste("kurtosis",fields(bin=k,frequency=k*fs/s$length,value=s$kurtosis[k+1L])))
  lines <- c("[signal]",fields(sample_rate=fs,samples=n,duration=n/fs),row_fields(c(list(channel=1L),sx)),row_fields(c(list(channel=2L),sy)),
    "[levels]",fields(block_length=params$block_length,blocks=length(history),loudest=levels$loudest))
  for (row in history) lines <- c(
      lines,
      fields(
          block=row$number,
          time=row$number*params$block_length/fs,
          rms1=row$rms1,
          rms2=row$rms2,
          peak1=row$peak1
      )
  )
  lines <- c(lines,"[windows]",vapply(comparison,row_fields,character(1)),"[main]",
    fields(
        length=m,
        window=params$main_window,
        method=if (is_power_two(m)) "radix2" else "bluestein",
        transform_size=if (is_power_two(m)) m else pow2(2L*m-1L),
        resolution=fs/m
    ),
    fields(
        total_power=powers$total_power,
        centroid=powers$centroid,
        spread=powers$spread,
        rolloff=powers$rolloff,
        flatness_db=powers$flatness_db
    ),
    "[bands]",vapply(band_data$bands,row_fields,character(1)),"[third_octave]",vapply(
        band_data$octaves,
        row_fields,
        character(1)
    ),
    "[harmonics]",fields(fundamental=params$fundamental[[1L]],search=params$fundamental[[2L]]))
  for (h in harmonics) lines <- c(
      lines,
      fields(
          h=h$number,
          target=h$target,
          bin=h$bin,
          refined=h$frequency,
          amplitude=h$amplitude,
          level_db=h$level_db
      )
  )
  lines <- c(lines,row_fields(harmonic_data$thd),fields(thdn_percent=powers$thdn_percent,thdn_db=powers$thdn_db),"[pitch]",
    fields(
        range=paste(params$pitch_range,collapse="-"),
        lags=paste0(pitch$lag_min,"-",pitch$lag_max)
    ),paste("hps",fields(bin=pitch$hps_bin,order=5L,frequency=pitch$hps_frequency)),
    paste(
        "autocorrelation",
        fields(
            lag=pitch$acf_lag,
            period=pitch$acf_period,
            frequency=pitch$acf_frequency,
            strength=pitch$acf_strength
        )
    ),
    paste(
        "zero_crossing",
        fields(count=pitch$crossings,frequency=pitch$crossing_frequency)
    ),"[zoom]",fields(band=paste0(zoom$low,"-",zoom$high),points=zoom$points,step=zoom$step),
    vapply(zoom$peaks,row_fields,character(1)),"[welch]",fields(
        segment_length=welch$length,
        segments=welch$segments,
        window=welch$window,
        resolution=fs/welch$length
    ),
    fields(
        integrated_power=welch$integrated_power,
        variance=welch$variance,
        ratio=welch$ratio
    ),vapply(welch$peaks,row_fields,character(1)),"[filter]",
    fields(
        bandpass=paste(params$bandpass,collapse="-"),
        bins_kept=filters$bins_kept,
        rms=filters$bandpass_rms,
        energy_ratio=filters$bandpass_ratio
    ),
    fields(
        notch=params$notch[1L],
        width=params$notch[2L],
        bins_removed=filters$bins_removed,
        rms=filters$notch_rms
    ),
    fields(
        fir_taps=filters$fir_taps,
        dc_gain=filters$dc_gain,
        gain_at_fundamental_db=filters$gain_at_fundamental_db,
        rms=filters$fir_rms
    ),"[envelope]",
    fields(
        band=paste(params$envelope_band,collapse="-"),
        mean=filters$envelope_mean,
        bin=filters$envelope_bin,
        frequency=filters$envelope_frequency,
        amplitude=filters$envelope_amplitude,
        depth=filters$envelope_depth
    ),
    paste(
        "instantaneous_frequency",
        fields(mean=filters$instantaneous_mean,std=filters$instantaneous_std)
    ),"[correlation]",
    fields(
        max_lag=params$max_lag,
        lag=correlation$lag,
        refined_lag=correlation$refined_lag,
        delay_ms=correlation$delay_ms,
        coefficient=correlation$coefficient
    ),
    fields(
        phat_lag=correlation$phat_lag,
        refined_lag=correlation$phat_refined,
        delay_ms=correlation$phat_delay_ms
    ),"[checks]")
  for (name in names(checks)) {
    line <- paste0(name,"=",if (checks[[name]]) "ok" else "failed")
    if (name == "real_packing") line <- paste0(line," transforms=",2L*welch$segments+s$frames)
    if (name == "dft_spot_check") line <- paste0(line," bins=",length(peaks))
    lines <- c(lines,line)
  }
  ratio <- harmonics[[2L]]$amplitude/harmonics[[1L]]$amplitude
  looseness <- sum(vapply(harmonics[-c(1L,2L)],function(h) h$level_db >= -30,logical(1)))
  mains <- Filter(function(p) p$label == "mains",peaks)
  electrical <- length(mains) > 0L && mains[[1L]]$level_db >= -20
  symptoms <- c(ratio >= 0.5,looseness >= 3L,filters$envelope_depth >= 0.2,electrical,length(s$onsets) > 0L)
  findings <- sum(symptoms)
  yesno <- function(value) if (value) "yes" else "no"
  lines <- c(lines,"[diagnosis]",fields(misalignment=yesno(symptoms[1L]),ratio=ratio),fields(looseness=yesno(symptoms[2L]),harmonics=looseness),
    fields(bearing=yesno(symptoms[3L]),depth=filters$envelope_depth),fields(
        electrical=yesno(electrical),
        level_db=if (!length(mains)) "none" else real_text(mains[[1L]]$level_db)
    ),
    fields(transient=yesno(symptoms[5L]),onsets=length(s$onsets)),fields(
        status=if (findings == 0L) "normal" else if (findings == 1L) "warning" else "alarm",
        findings=findings
    ))
  write_csv(
      "spectrum.csv",
      "frequency,amplitude",
      lapply(seq.int(0L,m %/% 2L),function(k) list(k*fs/m,amplitudes[k+1L]))
  )
  write_lines("peaks.txt",peak_lines)
  write_csv(
      "welch_psd.csv",
      "frequency,psd_db",
      lapply(seq.int(0L,welch$length %/% 2L),function(k) list(k*fs/welch$length,db(welch$psd[k+1L],10)))
  )
  write_lines("spectrogram.txt",spec_lines)
  write_csv(
      "filtered.csv",
      "index,bandpass,notched,smoothed,envelope",
      lapply(
          seq_len(n)-1L,
          function(i) list(
              i,
              filters$bandpassed[i+1L],
              filters$notched[i+1L],
              filters$smoothed[i+1L],
              filters$envelope[i+1L]
          )
      )
  )
  write_lines("report.txt",lines)
}
main <- function() {
  signal <- read_signal()
  params <- read_params()
  x <- detrend(signal$x,signal$fs)
  y <- detrend(signal$y,signal$fs)
  render_outputs(signal$fs,x$values,y$values,x$stats,y$stats,params)
}
main()
