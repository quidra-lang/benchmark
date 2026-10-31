load 'signal_io.ijs'
load 'fft.ijs'
load 'windows.ijs'
load 'spectral.ijs'
load 'report.ijs'
total =: 3 : 0
    result =. 0.0
    for_value. y do.
        result =. result+value
    end.
    result
)
energy =: 3 : 0
    result =. 0.0
    for_value. y do.
        result =. result+value*value
    end.
    result
)
rms =: 3 : '%:(energy y)%#y'
decibels =: 3 : '(20.0*^.y)%2.302585092994046'
power_db =: 3 : '(10.0*^.y)%2.302585092994046'
phase =: 3 : '((12 o.y)*180.0)%Pi'
maximum_index =: 4 : 0
    'first last' =. x
    best =. first
    for_j. (first+1)+i.last-first do.
        if. (j{y)>best{y do.
            best =. j
        end.
    end.
    best
)
strongest =: 4 : 0
    indices =. i.0
    for_j. 1+i.(#y)-2 do.
        if. y local_maximum j do.
            indices =. indices,j
        end.
    end.
    keys =. (-indices{y),.indices
    (x<.#indices){.indices /: keys
)
detrend =: 4 : 0
    sample_rate =. x
    count =. #y
    average =. (total y)%count
    center =. (count-1)%2.0
    numerator =. 0.0
    denominator =. 0.0
    for_i. i.count do.
        offset =. i-center
        numerator =. numerator+offset*(i{y)-average
        denominator =. denominator+offset*offset
    end.
    slope =. numerator%denominator
    residual =. i.0
    peak =. 0.0
    third =. 0.0
    fourth =. 0.0
    for_i. i.count do.
        value =. ((i{y)-average)-slope*(i-center)
        residual =. residual,value
        peak =. peak>.|value
        third =. third+value^3
        fourth =. fourth+value^4
    end.
    level =. rms residual
    statistics =. average,(slope*sample_rate),level,(<./y),(>./y),(peak%level),((third%count)%level^3),(fourth%count)%level^4
    (<residual),<statistics
)
bandwidth =: 4 : 0
    index =. x
    cutoff =. (index{y)%%:2.0
    left =. 0.0
    right =. 0.0+(#y)-1
    for_j. (index+1)+i.(#y)-(index+1) do.
        if. (j{y)<:cutoff do.
            right =. (j-1)+(((j-1){y)-cutoff)%((j-1){y)-j{y
            break.
        end.
    end.
    for_j. |.i.index do.
        if. (j{y)<:cutoff do.
            left =. (j+1)-(((j+1){y)-cutoff)%((j+1){y)-j{y
            break.
        end.
    end.
    right-left
)
target_index =: 4 : 0
    'length center width' =. x
    best =. _1
    for_k. 1+i.(<.length%2)-1 do.
        if. (|k-center)<:width do.
            if. best<0 do.
                best =. k
            elseif. (k{y)>best{y do.
                best =. k
            end.
        end.
    end.
    best
)
analyze_peaks =: 3 : 0
    MaximumAmplitude =: >./Amplitudes
    NoiseFloor =: median }.}:Amplitudes
    PeakBins =: i.0
    PeakData =: 0 9$0.0
    for_k. (#Amplitudes)strongest Amplitudes do.
        if. ((decibels (k{Amplitudes)%MaximumAmplitude)<PeakThreshold)+.(#PeakBins)>:PeakCount do.
            continue.
        end.
        'position amplitude' =. (k,1)interpolate Amplitudes
        coherence_bin =. ((2*k*WelchLength)+MainLength)intdiv 2*MainLength
        row =. position,amplitude,((k*Fs)%MainLength),((position*Fs)%MainLength),(decibels (k{Amplitudes)%MaximumAmplitude),(phase k{Transformed),(((k bandwidth Amplitudes)*Fs)%MainLength),(decibels (k{Amplitudes)%NoiseFloor),coherence_bin{2{::Welch
        PeakBins =: PeakBins,k
        PeakData =: PeakData,row
    end.
    PeakLabels =: (#PeakBins)$<'other'
    for_index. i.#PeakBins do.
        k =. index{PeakBins
        position =. (<index,0){PeakData
        label =. 'other'
        for_h. 1+i.10 do.
            target =. ((h*Fundamental)*MainLength)%Fs
            if. (|position-target)<:SearchWidth do.
                label =. 'h',integer h
                break.
            end.
        end.
        if. label-:'other' do.
            frequency =. (position*Fs)%MainLength
            multiple =. <.0.5+frequency%NotchFrequency
            if. (multiple>:1)*.(|frequency-multiple*NotchFrequency)<:NotchWidth do.
                label =. 'mains'
            end.
        end.
        if. label-:'other' do.
            for_pivot. i.#PeakBins do.
                kp =. pivot{PeakBins
                if. (kp=k)+.(kp{Amplitudes)<:k{Amplitudes do.
                    continue.
                end.
                for_other. i.#PeakBins do.
                    kr =. other{PeakBins
                    if. (kr=k)+.kr=kp do.
                        continue.
                    end.
                    if. ((kp{Amplitudes)>kr{Amplitudes)*.(|((position+(<other,0){PeakData)-2.0*(<pivot,0){PeakData))<:1.0 do.
                        label =. 'sideband',integer pivot+1
                        break.
                    end.
                end.
                if. -.label-:'other' do.
                    break.
                end.
            end.
        end.
        PeakLabels =: (<label)index}PeakLabels
    end.
    i.0
)
analyze_filters =: 3 : 0
    count =. #X
    transformed =. dft X
    band =. count$0j0
    notch =. band
    analytic_spectrum =. band
    kept =. 0
    removed =. 0
    for_k. i.count do.
        frequency =. (k<.count-k)*Fs
        if. ((BandLow*count)<:frequency)*.frequency<:BandHigh*count do.
            band =. (k{transformed)k}band
            kept =. kept+1
        end.
        multiple =. ((2*frequency)+NotchFrequency*count)intdiv 2*NotchFrequency*count
        if. (multiple>:1)*.(|frequency-(multiple*NotchFrequency)*count)<:NotchWidth*count do.
            removed =. removed+1
        else.
            notch =. (k{transformed)k}notch
        end.
        if. (k>:1)*.(k<:<.(count-1)%2)*.((EnvelopeLow*count)<:k*Fs)*.(k*Fs)<:EnvelopeHigh*count do.
            analytic_spectrum =. (2.0*k{transformed)k}analytic_spectrum
        end.
    end.
    bandpassed =. 9 o.idft band
    notched =. 9 o.idft notch
    analytic =. idft analytic_spectrum
    envelope =. |analytic
    envelope_mean =. (total envelope)%count
    modulation =. (2.0*|dft envelope-envelope_mean)%count
    stop =. ((EnvelopeHigh-EnvelopeLow)*count)intdiv 2*Fs
    envelope_bin =. (1,stop)maximum_index modulation
    'position amplitude' =. (envelope_bin,1)interpolate modulation
    instantaneous =. i.0
    for_i. 1+i.count-1 do.
        delta =. (12 o.i{analytic)-12 o.(i-1){analytic
        if. delta<:-Pi do.
            delta =. delta+2.0*Pi
        end.
        if. delta>Pi do.
            delta =. delta-2.0*Pi
        end.
        instantaneous =. instantaneous,(delta*Fs)%2.0*Pi
    end.
    frequency_mean =. (total instantaneous)%#instantaneous
    variance =. 0.0
    for_value. instantaneous do.
        variance =. variance+(value-frequency_mean)^2
    end.
    smoothed =. Y convolution Fir
    gain =. 0j0
    for_j. i.#Fir do.
        angle =. (((2.0*Pi)*Fundamental)*j)%Fs
        gain =. gain+(j{Fir)*rot angle
    end.
    fir_error =. 0.0
    for_i. i.count+(#Fir)-1 do.
        direct =. 0.0
        low =. 0>.i-((#Fir)-1)
        high =. (count-1)<.i
        for_j. low+i.1+high-low do.
            direct =. direct+(j{Y)*(i-j){Fir
        end.
        fir_error =. fir_error>.|(i{smoothed)-direct
    end.
    metrics =. (rms bandpassed),(rms notched),((energy bandpassed)%energy X),(total Fir),(decibels |gain),(rms count{.smoothed),fir_error,envelope_mean,((position*Fs)%count),amplitude,(amplitude%envelope_mean),frequency_mean,%:variance%#instantaneous
    FilterResult =: (<bandpassed),(<notched),(<envelope),(<smoothed),(<metrics),<kept,removed,envelope_bin
    i.0
)
choose_lag =: 4 : 0
    limit =. x
    size =. #y
    best =. -limit
    for_lag. (-limit)+i.1+2*limit do.
        value =. (size|lag){y
        previous =. (size|best){y
        if. (value>previous)+.(value=previous)*.((|lag)<|best)+.((|lag)=|best)*.lag<best do.
            best =. lag
        end.
    end.
    neighborhood =. (size|best+_1 0 1){y
    'position value' =. 1 0 interpolate neighborhood
    (<best),<(best+position)-1.0
)
analyze_correlation =: 3 : 0
    size =. pow2 (2*#X)-1
    fx =. 0 radix2 size{.X
    fy =. 0 radix2 size{.Y
    cross =. (+fx)*fy
    raw =. 9 o.1 radix2 cross
    phat =. 9 o.1 radix2 cross%|cross
    'lag refined' =. MaximumLag choose_lag raw
    'phat_lag phat_refined' =. MaximumLag choose_lag phat
    coefficient =. ((size|lag){raw)%%:(energy X)*energy Y
    Correlation =: (<lag),(<refined),(<(1000.0*refined)%Fs),(<coefficient),(<phat_lag),(<phat_refined),<(1000.0*phat_refined)%Fs
    i.0
)
analyze_pitch =: 3 : 0
    hps_bin =. _1
    hps_value =. __
    half =. <.MainLength%2
    for_k. 1+i.half do.
        if. ((PitchLow*MainLength)<:k*Fs)*.((k*Fs)<:PitchHigh*MainLength)*.(5*k)<:half do.
            value =. 0.0
            for_r. 1+i.5 do.
                value =. value+^.(r*k){Amplitudes
            end.
            if. value>hps_value do.
                hps_value =. value
                hps_bin =. k
            end.
        end.
    end.
    bandpassed =. 0{::FilterResult
    size =. pow2 (2*#bandpassed)-1
    transformed =. 0 radix2 size{.bandpassed
    acf =. 9 o.1 radix2 *:|transformed
    lag_min =. (Fs+PitchHigh-1)intdiv PitchHigh
    lag_max =. Fs intdiv PitchLow
    lag =. (lag_min,lag_max)maximum_index acf
    'period strength' =. (lag,0)interpolate acf
    crossings =. +/((}:bandpassed)<0.0)*.(}.bandpassed)>:0.0
    Pitch =: (<lag_min),(<lag_max),(<hps_bin),(<(hps_bin*Fs)%MainLength),(<lag),(<period),(<Fs%period),(<strength%0{acf),(<crossings),<(crossings*Fs)%#bandpassed
    i.0
)
run =: 3 : 0
    'Fs RawX RawY Params' =: read_inputs ''
    MainLength =: ".0{::0{::Params
    MainWindow =: 0{::1{::Params
    PeakThreshold =: ".0{::2{::Params
    PeakCount =: ".0{::3{::Params
    Fundamental =: ".0{::4{::Params
    SearchWidth =: ".1{::4{::Params
    WelchLength =: ".0{::5{::Params
    WelchWindow =: 1{::5{::Params
    FrameLength =: ".0{::6{::Params
    Hop =: ".1{::6{::Params
    BandDb =: ".2{::6{::Params
    FrameWindow =: 3{::6{::Params
    OnsetFactor =: ".0{::7{::Params
    'PitchLow PitchHigh' =: ".&>8{::Params
    'BandLow BandHigh' =: ".&>9{::Params
    'NotchFrequency NotchWidth' =: ".&>10{::Params
    'EnvelopeLow EnvelopeHigh' =: ".&>11{::Params
    'ZoomLow ZoomHigh ZoomCount' =: ".&>12{::Params
    Fir =: ".&>13{::Params
    MaximumLag =: ".0{::14{::Params
    Bands =: ".&>15{::Params
    'ThirdLow ThirdHigh' =: ".&>16{::Params
    BlockLength =: ".0{::17{::Params
    'X FirstStats' =: Fs detrend RawX
    'Y SecondStats' =: Fs detrend RawY
    'Weighted Transformed Amplitudes' =: ((<MainWindow),<MainLength)amplitude_spectrum X
    Figures =: Fs window_figures MainWindow window MainLength
    Welch =: welch_spectra (<X),(<Y),(<Fs),(<WelchLength),<WelchWindow
    analyze_peaks ''
    half =. <.MainLength%2
    HarmonicBins =: i.0
    Harmonics =: 0 5$0.0
    harmonic_energy =. 0.0
    for_h. 1+i.10 do.
        center =. ((h*Fundamental)*MainLength)%Fs
        k =. (MainLength,center,SearchWidth)target_index Amplitudes
        'position amplitude' =. (k,1)interpolate Amplitudes
        HarmonicBins =: HarmonicBins,k
        Harmonics =: Harmonics,position,amplitude,((position*Fs)%MainLength),0.0,h*Fundamental
        if. h>1 do.
            harmonic_energy =. harmonic_energy+amplitude*amplitude
        end.
    end.
    primary =. (<0,1){Harmonics
    for_h. i.10 do.
        Harmonics =: (decibels ((<h,1){Harmonics)%primary)(<h,3)}Harmonics
    end.
    thd =. (%:harmonic_energy)%primary
    power =. (half+1)$0.0
    sum_power =. 0.0
    first_power =. 0.0
    weighted_frequency =. 0.0
    log_power =. 0.0
    for_k. 1+i.half-1 do.
        value =. (*:k{Amplitudes)%2.0
        power =. value k}power
        sum_power =. sum_power+value
        if. (|k-{.HarmonicBins)<:SearchWidth do.
            first_power =. first_power+value
        end.
        weighted_frequency =. weighted_frequency+((k*Fs)%MainLength)*value
        log_power =. log_power+^.value
    end.
    total_power =. sum_power%3{Figures
    p1 =. first_power%3{Figures
    thdn =. %:(total_power-p1)%p1
    centroid =. weighted_frequency%sum_power
    spread_sum =. 0.0
    cumulative =. 0.0
    rolloff =. _1.0
    for_k. 1+i.half-1 do.
        spread_sum =. spread_sum+(*:((k*Fs)%MainLength)-centroid)*k{power
        cumulative =. cumulative+k{power
        if. (rolloff<0.0)*.cumulative>:0.85*sum_power do.
            rolloff =. (k*Fs)%MainLength
        end.
    end.
    spread =. %:spread_sum%sum_power
    flatness =. power_db (^log_power%(half-1))%(sum_power%(half-1))
    'Grid FrameError' =: ((<FrameLength),(<Hop),<FrameWindow)spectrogram_magnitudes X
    gmax =. >./,Grid
    dominant =. i.0
    flux =. ,0.0
    for_t. i.#Grid do.
        dominant =. dominant,(1,(<.FrameLength%2)-1)maximum_index t{Grid
        if. t do.
            value =. 0.0
            for_k. i.1+<.FrameLength%2 do.
                value =. value+0.0>.((<t,k){Grid)-(<(t-1),k){Grid
            end.
            flux =. flux,value
        end.
    end.
    onset_threshold =. OnsetFactor*median }.flux
    onsets =. i.0
    for_t. 1+i.<:#Grid do.
        if. ((t{flux)>onset_threshold)*.(t{flux)>(t-1){flux do.
            keep =. t=(#Grid)-1
            if. -.keep do.
                keep =. (t{flux)>(t+1){flux
            end.
            if. keep do.
                onsets =. onsets,t
            end.
        end.
    end.
    kurtosis =. i.0
    for_k. i.1+<.FrameLength%2 do.
        second_moment =. 0.0
        fourth_moment =. 0.0
        for_row. Grid do.
            second_moment =. second_moment+(k{row)^2
            fourth_moment =. fourth_moment+(k{row)^4
        end.
        kurtosis =. kurtosis,(((#Grid)*fourth_moment)%(second_moment*second_moment))-2.0
    end.
    top_kurtosis =. (1,(<.FrameLength%2)-1)maximum_index kurtosis
    analyze_filters ''
    analyze_pitch ''
    analyze_correlation ''
    zoom_step =. (ZoomHigh-ZoomLow)%(ZoomCount-1)
    zoom_transform =. (Fs,ZoomLow,ZoomHigh,ZoomCount)chirp_z Weighted
    zoom =. (2.0*|zoom_transform)%0{Figures
    inverse =. idft Transformed
    inverse_error =. >./|inverse-Weighted
    time_energy =. energy Weighted
    frequency_energy =. 0.0
    for_value. Transformed do.
        frequency_energy =. frequency_energy+*:|value
    end.
    parseval_error =. (|time_energy-frequency_energy%MainLength)%time_energy
    spot_error =. 0.0
    for_k. PeakBins do.
        direct =. 0j0
        for_n. i.MainLength do.
            angle =. ((2.0*Pi)*(MainLength|k*n))%MainLength
            direct =. direct+(n{Weighted)*rot angle
        end.
        spot_error =. spot_error>.|direct-k{Transformed
    end.
    spectrum_rows =. 0$a:
    for_k. i.half+1 do.
        spectrum_rows =. spectrum_rows,<(<real_text (k*Fs)%MainLength),<real_text k{Amplitudes
    end.
    'spectrum.csv'write_csv (<'frequency,amplitude'),<spectrum_rows
    psd_rows =. 0$a:
    psd =. 1{::Welch
    for_k. i.#psd do.
        psd_rows =. psd_rows,<(<real_text (k*Fs)%WelchLength),<real_text power_db k{psd
    end.
    'welch_psd.csv'write_csv (<'frequency,psd_db'),<psd_rows
    'bandpassed notched envelope smoothed metrics filter_counts' =. FilterResult
    filtered_rows =. 0$a:
    for_i. i.#X do.
        filtered_rows =. filtered_rows,<(<integer i),(<real_text i{bandpassed),(<real_text i{notched),(<real_text i{smoothed),<real_text i{envelope
    end.
    'filtered.csv'write_csv (<'index,bandpass,notched,smoothed,envelope'),<filtered_rows
    peak_lines =. (<'length=',(integer MainLength),' window=',MainWindow,' resolution=',(real_text Fs%MainLength),' threshold_db=',real_text PeakThreshold),(<'max_amplitude=',(real_text MaximumAmplitude),' noise_floor=',(real_text NoiseFloor),' noise_floor_db=',real_text decibels NoiseFloor),<'peaks=',integer #PeakBins
    for_rank. i.#PeakBins do.
        row =. rank{PeakData
        peak_lines =. peak_lines,<(integer rank+1),' bin=',(integer rank{PeakBins),' frequency=',(real_text 2{row),' refined=',(real_text 3{row),' amplitude=',(real_text 1{row),' level_db=',(real_text 4{row),' phase=',(real_text 5{row),' bandwidth=',(real_text 6{row),' snr_db=',(real_text 7{row),' coherence=',(real_text 8{row),' label=',rank{::PeakLabels
    end.
    'peaks.txt'write_lines peak_lines
    spectrogram_lines =. <'frames=',(integer #Grid),' bins=',(integer 1+<.FrameLength%2),' frame_length=',(integer FrameLength),' hop=',(integer Hop),' window=',FrameWindow,' band_db=',(integer BandDb),' max_db=',real_text decibels gmax
    spectrogram_lines =. spectrogram_lines,((Fs,FrameLength,BandDb,gmax)shade_lines Grid),<'track'
    for_t. i.#Grid do.
        k =. t{dominant
        spectrogram_lines =. spectrogram_lines,<'frame=',(integer t),' time=',(real_text (t*Hop)%Fs),' frequency=',(real_text (k*Fs)%FrameLength),' level_db=',real_text decibels ((<t,k){Grid)%gmax
    end.
    spectrogram_lines =. spectrogram_lines,<'onsets=',(integer #onsets),' threshold=',real_text onset_threshold
    for_t. onsets do.
        spectrogram_lines =. spectrogram_lines,<'frame=',(integer t),' time=',(real_text (t*Hop)%Fs),' flux=',real_text t{flux
    end.
    spectrogram_lines =. spectrogram_lines,<'kurtosis bin=',(integer top_kurtosis),' frequency=',(real_text (top_kurtosis*Fs)%FrameLength),' value=',real_text top_kurtosis{kurtosis
    'spectrogram.txt'write_lines spectrogram_lines
    rows =. (<'[signal]'),<'sample_rate=',(integer Fs),' samples=',(integer #X),' duration=',real_text (#X)%Fs
    stat_names =. ;:'mean slope rms min max crest skewness kurtosis'
    statistics =. (<FirstStats),<SecondStats
    for_channel. i.2 do.
        stats =. channel{::statistics
        line =. 'channel=',integer channel+1
        for_j. i.#stat_names do.
            line =. line,' ',(j{::stat_names),'=',real_text j{stats
        end.
        rows =. rows,<line
    end.
    history =. 0 3$0.0
    loudest =. 0
    for_block. i.(#X)intdiv BlockLength do.
        indices =. (block*BlockLength)+i.BlockLength
        left =. indices{X
        right =. indices{Y
        history =. history,(rms left),(rms right),>./|left
        if. ((<block,0){history)>(<loudest,0){history do.
            loudest =. block
        end.
    end.
    rows =. rows,(<'[levels]'),<'block_length=',(integer BlockLength),' blocks=',(integer #history),' loudest=',integer loudest
    for_j. i.#history do.
        'rms1 rms2 peak1' =. j{history
        rows =. rows,<'block=',(integer j),' time=',(real_text (j*BlockLength)%Fs),' rms1=',(real_text rms1),' rms2=',(real_text rms2),' peak1=',real_text peak1
    end.
    rows =. rows,<'[windows]'
    for_name. WindowNames do.
        name =. >name
        calibration =. Fs window_figures name window MainLength
        'windowed transform aw' =. ((<name),<MainLength)amplitude_spectrum X
        index =. (MainLength,((Fundamental*MainLength)%Fs),SearchWidth)target_index aw
        'position fitted' =. (index,1)interpolate aw
        floor_db =. decibels median }.}:aw
        rows =. rows,<'name=',name,' coherent_gain=',(real_text 2{calibration),' enbw_bins=',(real_text 3{calibration),' enbw_hz=',(real_text 4{calibration),' scalloping_db=',(real_text 5{calibration),' fundamental_bin=',(integer index),' bin_amplitude=',(real_text index{aw),' refined_amplitude=',(real_text fitted),' floor_db=',real_text floor_db
    end.
    power_two =. MainLength=pow2 MainLength
    method =. 'bluestein'
    transform_size =. pow2 (2*MainLength)-1
    if. power_two do.
        method =. 'radix2'
        transform_size =. MainLength
    end.
    rows =. rows,(<'[main]'),(<'length=',(integer MainLength),' window=',MainWindow,' method=',method,' transform_size=',(integer transform_size),' resolution=',real_text Fs%MainLength),(<'total_power=',(real_text total_power),' centroid=',(real_text centroid),' spread=',(real_text spread),' rolloff=',(real_text rolloff),' flatness_db=',real_text flatness),<'[bands]'
    for_j. i.<:#Bands do.
        low =. j{Bands
        high =. (j+1){Bands
        value =. 0.0
        for_k. 1+i.half-1 do.
            if. ((low*MainLength)<:k*Fs)*.(k*Fs)<high*MainLength do.
                value =. value+k{power
            end.
        end.
        value =. value%3{Figures
        rows =. rows,<'range=',(integer low),'-',(integer high),' power=',(real_text value),' percent=',real_text (100.0*value)%total_power
    end.
    rows =. rows,<'[third_octave]'
    for_band. ThirdLow+i.1+ThirdHigh-ThirdLow do.
        center =. 1000.0*2.0^band%3.0
        low =. 1000.0*2.0^((2*band)-1)%6.0
        high =. 1000.0*2.0^((2*band)+1)%6.0
        value =. 0.0
        bins =. 0
        for_k. 1+i.half-1 do.
            frequency =. (k*Fs)%MainLength
            if. (low<:frequency)*.frequency<high do.
                value =. value+k{power
                bins =. bins+1
            end.
        end.
        rows =. rows,<'band=',(integer band),' center=',(real_text center),' lower=',(real_text low),' upper=',(real_text high),' bins=',(integer bins),' level_db=',real_text power_db value%3{Figures
    end.
    rows =. rows,(<'[harmonics]'),<'fundamental=',(real_text Fundamental),' search=',integer SearchWidth
    for_h. i.10 do.
        row =. h{Harmonics
        rows =. rows,<'h=',(integer h+1),' target=',(real_text 4{row),' bin=',(integer h{HarmonicBins),' refined=',(real_text 2{row),' amplitude=',(real_text 1{row),' level_db=',real_text 3{row
    end.
    rows =. rows,(<'thd_percent=',(real_text 100.0*thd),' thd_db=',real_text decibels thd),(<'thdn_percent=',(real_text 100.0*thdn),' thdn_db=',real_text decibels thdn),(<'[pitch]'),(<'range=',(integer PitchLow),'-',(integer PitchHigh),' lags=',(integer 0{::Pitch),'-',integer 1{::Pitch),(<'hps bin=',(integer 2{::Pitch),' order=5 frequency=',real_text 3{::Pitch),(<'autocorrelation lag=',(integer 4{::Pitch),' period=',(real_text 5{::Pitch),' frequency=',(real_text 6{::Pitch),' strength=',real_text 7{::Pitch),(<'zero_crossing count=',(integer 8{::Pitch),' frequency=',real_text 9{::Pitch),(<'[zoom]'),<'band=',(integer ZoomLow),'-',(integer ZoomHigh),' points=',(integer ZoomCount),' step=',real_text zoom_step
    zoom_peaks =. 3 strongest zoom
    for_rank. i.#zoom_peaks do.
        'position amplitude' =. ((rank{zoom_peaks),1)interpolate zoom
        rows =. rows,<'peak=',(integer rank+1),' frequency=',(real_text ZoomLow+position*zoom_step),' amplitude=',real_text amplitude
    end.
    integrated =. ((total psd)*Fs)%WelchLength
    variance =. (energy X)%#X
    rows =. rows,(<'[welch]'),(<'segment_length=',(integer WelchLength),' segments=',(integer 0{::Welch),' window=',WelchWindow,' resolution=',real_text Fs%WelchLength),<'integrated_power=',(real_text integrated),' variance=',(real_text variance),' ratio=',real_text integrated%variance
    welch_peaks =. 5 strongest psd
    coherence =. 2{::Welch
    transfer =. 3{::Welch
    for_rank. i.#welch_peaks do.
        k =. rank{welch_peaks
        rows =. rows,<'peak=',(integer rank+1),' frequency=',(real_text (k*Fs)%WelchLength),' psd_db=',(real_text power_db k{psd),' coherence=',(real_text k{coherence),' gain=',(real_text |k{transfer),' phase=',real_text phase k{transfer
    end.
    rows =. rows,(<'[filter]'),(<'bandpass=',(integer BandLow),'-',(integer BandHigh),' bins_kept=',(integer 0{filter_counts),' rms=',(real_text 0{metrics),' energy_ratio=',real_text 2{metrics),(<'notch=',(integer NotchFrequency),' width=',(integer NotchWidth),' bins_removed=',(integer 1{filter_counts),' rms=',real_text 1{metrics),(<'fir_taps=',(integer #Fir),' dc_gain=',(real_text 3{metrics),' gain_at_fundamental_db=',(real_text 4{metrics),' rms=',real_text 5{metrics),(<'[envelope]'),(<'band=',(integer EnvelopeLow),'-',(integer EnvelopeHigh),' mean=',(real_text 7{metrics),' bin=',(integer 2{filter_counts),' frequency=',(real_text 8{metrics),' amplitude=',(real_text 9{metrics),' depth=',real_text 10{metrics),(<'instantaneous_frequency mean=',(real_text 11{metrics),' std=',real_text 12{metrics),(<'[correlation]'),(<'max_lag=',(integer MaximumLag),' lag=',(integer 0{::Correlation),' refined_lag=',(real_text 1{::Correlation),' delay_ms=',(real_text 2{::Correlation),' coefficient=',real_text 3{::Correlation),(<'phat_lag=',(integer 4{::Correlation),' refined_lag=',(real_text 5{::Correlation),' delay_ms=',real_text 6{::Correlation),<'[checks]'
    check_names =. ;:'inverse_roundtrip parseval real_packing fir_fft_vs_direct dft_spot_check'
    errors =. inverse_error,parseval_error,((4{::Welch)>.FrameError),(6{metrics),spot_error
    for_j. i.#check_names do.
        status =. 'failed'
        if. (j{errors)<:0.000001 do.
            status =. 'ok'
        end.
        line =. (j{::check_names),'=',status
        if. j=2 do.
            line =. line,' transforms=',integer (2*0{::Welch)+#Grid
        elseif. j=4 do.
            line =. line,' bins=',integer #PeakBins
        end.
        rows =. rows,<line
    end.
    ratio =. ((<1,1){Harmonics)%primary
    loose =. +/_30.0<:2}.3{"1 Harmonics
    has_electrical =. 0
    electrical_level =. 0.0
    for_j. i.#PeakBins do.
        if. 'mains'-:j{::PeakLabels do.
            has_electrical =. 1
            electrical_level =. (<j,4){PeakData
            break.
        end.
    end.
    symptoms =. (ratio>:0.5),(loose>:3),((10{metrics)>:0.2),(has_electrical*.electrical_level>:_20.0),(0<#onsets)
    findings =. +/symptoms
    status =. findings{::;:'normal warning alarm alarm alarm alarm'
    electrical_text =. 'none'
    if. has_electrical do.
        electrical_text =. real_text electrical_level
    end.
    rows =. rows,(<'[diagnosis]'),(<'misalignment=',(yes_no 0{symptoms),' ratio=',real_text ratio),(<'looseness=',(yes_no 1{symptoms),' harmonics=',integer loose),(<'bearing=',(yes_no 2{symptoms),' depth=',real_text 10{metrics),(<'electrical=',(yes_no 3{symptoms),' level_db=',electrical_text),(<'transient=',(yes_no 4{symptoms),' onsets=',integer #onsets),<'status=',status,' findings=',integer findings
    'report.txt'write_lines rows
    i.0
)
yes_no =: 3 : 'y{::;:''no yes'''
run ''
