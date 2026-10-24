require_relative 'fft'
require_relative 'windows'
require_relative 'signal_io'
require_relative 'spectral'
require_relative 'report'

module Spectrum
  def mean_square(values)
    ordered_sum(values.map { |v| v * v }) / values.length
  end

  def rms(values)
    Math.sqrt(mean_square(values))
  end

  def decibels(value, factor = 20)
    factor * Math.log10(value)
  end

  def phase_degrees(value)
    Math.atan2(value.imag, value.real) * 180 / PI
  end

  def strongest(values, indices)
    best = indices.first
    indices.each { |k| best = k if values[k] > values[best] }
    best
  end

  def detrend(samples, fs)
    n = samples.length
    center = (n - 1) / 2.0
    average = ordered_sum(samples) / n
    numerator = ordered_sum(samples.each_with_index.map { |v, i| (i - center) * (v - average) })
    denominator = ordered_sum(Array.new(n) { |i| (i - center)**2 })
    slope = numerator / denominator
    residual = samples.each_with_index.map { |v, i| v - average - slope * (i - center) }
    level = rms(residual)
    [residual, {mean: average, slope: slope * fs, rms: level, min: samples.min, max: samples.max,
                crest: residual.map(&:abs).max / level,
                skewness: (ordered_sum(residual.map { |v| v**3 }) / n) / level**3,
                kurtosis: (ordered_sum(residual.map { |v| v**4 }) / n) / level**4}]
  end

  def level_history(x, y, length)
    history = Array.new(x.length / length) do |g|
      left, right = x[g * length, length], y[g * length, length]
      {number: g, rms1: rms(left), rms2: rms(right), peak1: left.map(&:abs).max}
    end
    [history, strongest(history.map { |r| r[:rms1] }, (0...history.length).to_a)]
  end

  def strongest_local_maxima(values, limit)
    (1...values.length - 1).select { |k| local_maximum(values, k) }.sort_by { |k| [-values[k], k] }.first(limit)
  end

  def amplitude_bandwidth(a, k)
    last, cutoff = a.length - 1, a[k] / Math.sqrt(2)
    jr = (k + 1..last).find { |j| a[j] <= cutoff }
    right = jr ? jr - 1 + (a[jr - 1] - cutoff) / (a[jr - 1] - a[jr]) : last.to_f
    jl = (k - 1).downto(0).find { |j| a[j] <= cutoff }
    left = jl ? jl + 1 - (a[jl + 1] - cutoff) / (a[jl + 1] - a[jl]) : 0.0
    right - left
  end

  def label_peak(peak, peaks, p, fs, m)
    nominal, width = p[:fundamental]
    notch, notch_width = p[:notch]
    position = peak[:position]
    1.upto(10) { |h| return "h#{h}" if (position - h * nominal * m / fs).abs <= width }
    frequency = position * fs / m
    multiple = (frequency / notch + 0.5).floor
    return 'mains' if multiple >= 1 && (frequency - multiple * notch).abs <= notch_width
    peaks.each do |pivot|
      next if pivot.equal?(peak) || pivot[:bin_amplitude] <= peak[:bin_amplitude]
      peaks.each do |other|
        next if other.equal?(peak) || other.equal?(pivot) || pivot[:bin_amplitude] <= other[:bin_amplitude]
        return "sideband#{pivot[:rank]}" if (position + other[:position] - 2 * pivot[:position]).abs <= 1
      end
    end
    'other'
  end

  def main_peaks(a, transformed, p, fs, welch)
    m, length = p[:main_length], p[:welch][0]
    maximum, floor = a.max, median(a[1...-1])
    candidates = strongest_local_maxima(a, a.length).select { |k| decibels(a[k] / maximum) >= p[:peak_threshold_db] }.first(p[:peak_count])
    peaks = candidates.each_with_index.map do |k, rank|
      position, amplitude = interpolate(a, k)
      j = (2 * k * length + m) / (2 * m)
      {rank: rank + 1, bin: k, position: position, bin_amplitude: a[k], frequency: k * fs.to_f / m,
       refined: position * fs / m, amplitude: amplitude, level_db: decibels(a[k] / maximum),
       phase: phase_degrees(transformed[k]), bandwidth: amplitude_bandwidth(a, k) * fs / m,
       snr_db: decibels(a[k] / floor), coherence: welch[:coherence][j]}
    end
    peaks.each { |peak| peak[:label] = label_peak(peak, peaks, p, fs, m) }
    [peaks, maximum, floor]
  end

  def harmonic_analysis(a, p, fs)
    m = p[:main_length]
    nominal, width = p[:fundamental]
    harmonics = (1..10).map do |h|
      center = h * nominal * m / fs
      indices = (1...m / 2).select { |k| (k - center).abs <= width }
      k = strongest(a, indices)
      position, amplitude = interpolate(a, k)
      {number: h, target: h * nominal, bin: k, position: position, frequency: position * fs / m, amplitude: amplitude}
    end
    primary = harmonics[0][:amplitude]
    harmonics.each { |h| h[:level_db] = decibels(h[:amplitude] / primary) }
    thd = Math.sqrt(ordered_sum(harmonics.drop(1).map { |h| h[:amplitude]**2 })) / primary
    [harmonics, {thd_percent: 100 * thd, thd_db: decibels(thd)}]
  end

  def power_analysis(a, fs, p, harmonics, enbw)
    m, half = p[:main_length], p[:main_length] / 2
    power = a.map { |v| v * v / 2 }
    interior = (1...half).to_a
    total = ordered_sum(interior.map { |k| power[k] })
    total_power = total / enbw
    k1, width = harmonics[0][:bin], p[:fundamental][1]
    primary = ordered_sum(interior.select { |k| (k - k1).abs <= width }.map { |k| power[k] }) / enbw
    thdn = Math.sqrt((total_power - primary) / primary)
    centroid = ordered_sum(interior.map { |k| k * fs.to_f / m * power[k] }) / total
    spread = Math.sqrt(ordered_sum(interior.map { |k| (k * fs.to_f / m - centroid)**2 * power[k] }) / total)
    cumulative, rolloff = 0.0, 0.0
    interior.each do |k|
      cumulative += power[k]
      if cumulative >= 0.85 * total
        rolloff = k * fs.to_f / m
        break
      end
    end
    flatness = decibels(Math.exp(ordered_sum(interior.map { |k| Math.log(power[k]) }) / (half - 1)) / (total / (half - 1)), 10)
    [power, {total_power: total_power, centroid: centroid, spread: spread, rolloff: rolloff,
             flatness_db: flatness, thdn_percent: 100 * thdn, thdn_db: decibels(thdn)}]
  end

  def calculate_bands(power, p, fs, enbw, total)
    m = p[:main_length]
    interior = (1...m / 2).to_a
    bands = p[:bands].each_cons(2).map do |lower, upper|
      indices = interior.select { |k| lower * m <= k * fs && k * fs < upper * m }
      value = ordered_sum(indices.map { |k| power[k] }) / enbw
      [lower, upper, value, 100 * value / total]
    end
    first, last = p[:third_octave]
    octaves = (first..last).map do |b|
      center = 1000 * 2.0**(b / 3.0)
      lower, upper = 1000 * 2.0**((2 * b - 1) / 6.0), 1000 * 2.0**((2 * b + 1) / 6.0)
      indices = interior.select { |k| lower <= k * fs.to_f / m && k * fs.to_f / m < upper }
      value = ordered_sum(indices.map { |k| power[k] }) / enbw
      {band: b, center: center, lower: lower, upper: upper, bins: indices.length, level_db: decibels(value, 10)}
    end
    [bands, octaves]
  end

  def compare_windows(signal, p, fs)
    m = p[:main_length]
    nominal, width = p[:fundamental]
    center = nominal * m / fs
    COEFFICIENTS.keys.map do |name|
      calibration = figures(window(name, m), fs)
      _, _, a = amplitude_spectrum(signal, name, m)
      indices = (1...m / 2).select { |k| (k - center).abs <= width }
      k = strongest(a, indices)
      _, value = interpolate(a, k)
      {name: name}.merge(calibration).merge(fundamental_bin: k, bin_amplitude: a[k], refined_amplitude: value,
                                          floor_db: decibels(median(a[1...-1])))
    end
  end

  def analyze_welch(x, y, p, fs)
    length, name = p[:welch]
    data = welch_spectra(x, y, fs, length, name)
    psd = data[:psd]
    integrated, variance = ordered_sum(psd) * fs / length, rms(x)**2
    peaks = strongest_local_maxima(psd, 5).each_with_index.map do |k, rank|
      transfer = data[:transfer][k]
      {rank: rank + 1, frequency: k * fs.to_f / length, psd_db: decibels(psd[k], 10),
       coherence: data[:coherence][k], gain: transfer.abs, phase: phase_degrees(transfer)}
    end
    data.merge(length: length, window: name, integrated_power: integrated, variance: variance, ratio: integrated / variance, peaks: peaks)
  end

  def analyze_spectrogram(signal, p, fs)
    length, hop, band_db, name = p[:spectrogram]
    grid, error = spectrogram_magnitudes(signal, length, hop, name)
    frames, maximum = grid.length, grid.flatten.max
    dominant = grid.each_with_index.map do |row, t|
      k = strongest(row, (1...length / 2).to_a)
      {frame: t, time: t * hop.to_f / fs, frequency: k * fs.to_f / length, level_db: decibels(row[k] / maximum)}
    end
    levels = grid.map { |row| row.map { |v| [0, 9 - (-decibels(v / maximum) / band_db).floor].max } }
    flux = [0.0]
    (1...frames).each { |t| flux << ordered_sum(Array.new(length / 2 + 1) { |k| [0.0, grid[t][k] - grid[t - 1][k]].max }) }
    threshold = p[:onset_factor] * median(flux.drop(1))
    onsets = (1...frames).select { |t| flux[t] > threshold && flux[t] > flux[t - 1] && (t == frames - 1 || flux[t] > flux[t + 1]) }
    kurtosis = Array.new(length / 2 + 1) do |k|
      second = ordered_sum(grid.map { |row| row[k]**2 })
      fourth = ordered_sum(grid.map { |row| row[k]**4 })
      frames * fourth / (second * second) - 2
    end
    top = strongest(kurtosis, (1...length / 2).to_a)
    {grid: grid, levels: levels, frames: frames, maximum: maximum, length: length, hop: hop, band_db: band_db,
     window: name, dominant: dominant, flux: flux, onsets: onsets, onset_threshold: threshold,
     kurtosis: kurtosis, top_kurtosis: top, packing_error: error}
  end

  def filtered_waveforms(x, y, p, fs)
    n = x.length
    spectrum = dft(x)
    low, high = p[:bandpass]
    notch, width = p[:notch]
    filtered, notched, kept, removed = [], [], 0, 0
    spectrum.each_with_index do |value, k|
      g = [k, n - k].min * fs
      pass = low * n <= g && g <= high * n
      kept += 1 if pass
      filtered << (pass ? value : Complex(0.0, 0.0))
      j = (2 * g + notch * n) / (2 * notch * n)
      reject = j >= 1 && (g - j * notch * n).abs <= width * n
      removed += 1 if reject
      notched << (reject ? Complex(0.0, 0.0) : value)
    end
    bandpassed, notch_result = idft(filtered).map(&:real), idft(notched).map(&:real)
    e1, e2 = p[:envelope_band]
    ze = Array.new(n, Complex(0.0, 0.0))
    1.upto((n - 1) / 2) { |k| ze[k] = 2 * spectrum[k] if e1 * n <= k * fs && k * fs <= e2 * n }
    analytic = idft(ze)
    envelope = analytic.map(&:abs)
    em = ordered_sum(envelope) / n
    ev = dft(envelope.map { |v| v - em })
    modulation = ev.map { |v| 2 * v.abs / n }
    stop = (e2 - e1) * n / (2 * fs)
    ke = strongest(modulation, (1..stop).to_a)
    qe, be = interpolate(modulation, ke)
    instantaneous = (1...n).map do |i|
      dp = Math.atan2(analytic[i].imag, analytic[i].real) - Math.atan2(analytic[i - 1].imag, analytic[i - 1].real)
      dp += 2 * PI if dp <= -PI
      dp -= 2 * PI if dp > PI
      dp * fs / (2 * PI)
    end
    mean = ordered_sum(instantaneous) / (n - 1)
    std = Math.sqrt(ordered_sum(instantaneous.map { |v| (v - mean)**2 }) / (n - 1))
    taps = p[:fir]
    smoothed = convolution(y, taps)
    gain = ordered_sum(taps.each_with_index.map { |v, j| v * rot(2 * PI * p[:fundamental][0] * j / fs) })
    direct = Array.new(n + taps.length - 1) do |i|
      ordered_sum(([0, i - taps.length + 1].max..[n - 1, i].min).map { |j| y[j] * taps[i - j] })
    end
    {bandpassed: bandpassed, notched: notch_result, smoothed: smoothed, envelope: envelope,
     bins_kept: kept, bins_removed: removed, bandpass_rms: rms(bandpassed), notch_rms: rms(notch_result),
     bandpass_ratio: ordered_sum(bandpassed.map { |v| v * v }) / ordered_sum(x.map { |v| v * v }),
     fir_taps: taps.length, dc_gain: ordered_sum(taps), gain_at_fundamental_db: decibels(gain.abs),
     fir_rms: rms(smoothed.first(n)), fir_error: smoothed.zip(direct).map { |a, b| (a - b).abs }.max,
     envelope_band: [e1, e2], envelope_mean: em, envelope_bin: ke, envelope_frequency: qe * fs / n,
     envelope_amplitude: be, envelope_depth: be / em, instantaneous_mean: mean, instantaneous_std: std}
  end

  def estimate_pitch(a, bandpassed, p, fs)
    m = p[:main_length]
    low, high = p[:pitch_range]
    lam1, lam2 = (fs + high - 1) / high, fs / low
    candidates = (1..m / 2).select { |k| low * m <= k * fs && k * fs <= high * m && 5 * k <= m / 2 }
    hs = Array.new(m / 2 + 1, 0.0)
    candidates.each { |k| hs[k] = ordered_sum((1..5).map { |r| Math.log(a[r * k]) }) }
    kh = strongest(hs, candidates)
    n = bandpassed.length
    q = pow2(2 * n - 1)
    transformed = radix2(bandpassed + Array.new(q - n, 0.0))
    acf = radix2(transformed.map { |v| Complex(v.abs**2, 0.0) }, true).map(&:real)
    lag = strongest(acf, (lam1..lam2).to_a)
    period, value = interpolate(acf, lag, false)
    crossings = (1...n).count { |i| bandpassed[i - 1] < 0 && bandpassed[i] >= 0 }
    {lag_min: lam1, lag_max: lam2, hps_bin: kh, hps_frequency: kh * fs.to_f / m,
     acf_lag: lag, acf_period: period, acf_frequency: fs / period, acf_strength: value / acf[0],
     crossings: crossings, crossing_frequency: crossings * fs.to_f / n}
  end

  def analyze_zoom(weighted, s1, p, fs)
    low, high, points = p[:zoom]
    step = (high - low).to_f / (points - 1)
    amplitudes = chirp_z(weighted, fs, low, high, points).map { |v| 2 * v.abs / s1 }
    peaks = strongest_local_maxima(amplitudes, 3).each_with_index.map do |j, rank|
      position, amplitude = interpolate(amplitudes, j)
      {rank: rank + 1, frequency: low + position * step, amplitude: amplitude}
    end
    {low: low, high: high, points: points, step: step, peaks: peaks}
  end

  def choose_lag(sequence, limit)
    size = sequence.length
    lag = (-limit..limit).max_by { |ell| [sequence[ell % size], -ell.abs, -ell] }
    neighborhood = [-1, 0, 1].map { |offset| sequence[(lag + offset) % size] }
    position, = interpolate(neighborhood, 1, false)
    [lag, lag + (position - 1)]
  end

  def analyze_correlation(x, y, limit, fs)
    n = x.length
    q = pow2(2 * n - 1)
    fx, fy = radix2(x + Array.new(q - n, 0.0)), radix2(y + Array.new(q - n, 0.0))
    cross = Array.new(q) { |k| fx[k].conj * fy[k] }
    raw = radix2(cross, true).map(&:real)
    phat = radix2(cross.map { |v| v / v.abs }, true).map(&:real)
    lag, refined = choose_lag(raw, limit)
    plag, prefined = choose_lag(phat, limit)
    {lag: lag, refined_lag: refined, delay_ms: 1000 * refined / fs,
     coefficient: raw[lag % q] / Math.sqrt(ordered_sum(x.map { |v| v * v }) * ordered_sum(y.map { |v| v * v })),
     phat_lag: plag, phat_refined: prefined, phat_delay_ms: 1000 * prefined / fs}
  end

  def verify_transforms(weighted, transformed, peaks, filters, welch, spectrogram)
    m = weighted.length
    inverse = idft(transformed)
    inverse_error = inverse.each_with_index.map { |v, i| (v - weighted[i]).abs }.max
    time_energy = ordered_sum(weighted.map { |v| v * v })
    frequency_energy = ordered_sum(transformed.map { |v| v.abs**2 }) / m
    parseval_error = (time_energy - frequency_energy).abs / time_energy
    spot_error = 0.0
    peaks.each do |peak|
      k = peak[:bin]
      direct = ordered_sum(Array.new(m) { |n| weighted[n] * rot(2 * PI * ((k * n) % m) / m) })
      spot_error = [spot_error, (direct - transformed[k]).abs].max
    end
    {inverse_roundtrip: inverse_error <= 1e-6, parseval: parseval_error <= 1e-6,
     real_packing: [welch[:packing_error], spectrogram[:packing_error]].max <= 1e-6,
     fir_fft_vs_direct: filters[:fir_error] <= 1e-6, dft_spot_check: spot_error <= 1e-6}
  end

  def diagnosis(peaks, harmonics, filters, spectrogram)
    ratio = harmonics[1][:amplitude] / harmonics[0][:amplitude]
    n3 = harmonics.drop(2).count { |h| h[:level_db] >= -30 }
    mains = peaks.find { |peak| peak[:label] == 'mains' }
    level = mains && mains[:level_db]
    symptoms = {misalignment: ratio >= 0.5, looseness: n3 >= 3, bearing: filters[:envelope_depth] >= 0.2,
                electrical: !level.nil? && level >= -20, transient: !spectrogram[:onsets].empty?}
    findings = symptoms.values.count(true)
    {symptoms: symptoms, findings: findings, status: findings.zero? ? 'normal' : findings == 1 ? 'warning' : 'alarm',
     amplitude_ratio: ratio, looseness_count: n3, electrical_level: level}
  end

  def render_peaks(peaks, maximum, floor, p, fs)
    m = p[:main_length]
    lines = [fields(length: m, window: p[:main_window], resolution: fs.to_f / m, threshold_db: p[:peak_threshold_db]),
             fields(max_amplitude: maximum, noise_floor: floor, noise_floor_db: decibels(floor)), fields(peaks: peaks.length)]
    peaks.each do |r|
      lines << r[:rank].to_s + ' ' + fields(bin: r[:bin], frequency: r[:frequency], refined: r[:refined], amplitude: r[:amplitude],
                                           level_db: r[:level_db], phase: r[:phase], bandwidth: r[:bandwidth], snr_db: r[:snr_db],
                                           coherence: r[:coherence], label: r[:label])
    end
    lines
  end

  def render_spectrogram(data, fs)
    length = data[:length]
    lines = [fields(frames: data[:frames], bins: length / 2 + 1, frame_length: length, hop: data[:hop],
                    window: data[:window], band_db: data[:band_db], max_db: decibels(data[:maximum]))]
    lines.concat(shade_lines(data[:levels], fs, length))
    lines << 'track'
    data[:dominant].each { |row| lines << fields(**row) }
    lines << fields(onsets: data[:onsets].length, threshold: data[:onset_threshold])
    data[:onsets].each { |t| lines << fields(frame: t, time: t * data[:hop].to_f / fs, flux: data[:flux][t]) }
    k = data[:top_kurtosis]
    lines << 'kurtosis ' + fields(bin: k, frequency: k * fs.to_f / length, value: data[:kurtosis][k])
  end

  def render_report(fs, n, stats, history, loudest, comparison, powers, bands, octaves, harmonics, thd,
                    pitch, zoom, welch, spectrogram, filters, correlation, checks, diagnostic, peaks, p)
    m = p[:main_length]
    lines = ['[signal]', fields(sample_rate: fs, samples: n, duration: n.to_f / fs)]
    stats.each_with_index { |values, i| lines << fields(channel: i + 1, **values) }
    lb = p[:block_length]
    lines.concat(['[levels]', fields(block_length: lb, blocks: history.length, loudest: loudest)])
    history.each { |r| lines << fields(block: r[:number], time: r[:number] * lb.to_f / fs, rms1: r[:rms1], rms2: r[:rms2], peak1: r[:peak1]) }
    lines << '[windows]'
    comparison.each do |r|
      lines << fields(name: r[:name], coherent_gain: r[:coherent_gain], enbw_bins: r[:enbw_bins], enbw_hz: r[:enbw_hz],
                      scalloping_db: r[:scalloping_db], fundamental_bin: r[:fundamental_bin], bin_amplitude: r[:bin_amplitude],
                      refined_amplitude: r[:refined_amplitude], floor_db: r[:floor_db])
    end
    radix = (m & (m - 1)).zero?
    lines.concat(['[main]', fields(length: m, window: p[:main_window], method: radix ? 'radix2' : 'bluestein',
                                  transform_size: radix ? m : pow2(2 * m - 1), resolution: fs.to_f / m),
                  fields(total_power: powers[:total_power], centroid: powers[:centroid], spread: powers[:spread],
                         rolloff: powers[:rolloff], flatness_db: powers[:flatness_db]), '[bands]'])
    bands.each { |low, high, power, percent| lines << fields(range: "#{low}-#{high}", power: power, percent: percent) }
    lines << '[third_octave]'
    octaves.each { |r| lines << fields(**r) }
    nominal, width = p[:fundamental]
    lines.concat(['[harmonics]', fields(fundamental: nominal, search: width)])
    harmonics.each { |r| lines << fields(h: r[:number], target: r[:target], bin: r[:bin], refined: r[:frequency], amplitude: r[:amplitude], level_db: r[:level_db]) }
    lines << fields(**thd)
    lines << fields(thdn_percent: powers[:thdn_percent], thdn_db: powers[:thdn_db])
    low, high = p[:pitch_range]
    lines.concat(['[pitch]', fields(range: "#{low}-#{high}", lags: "#{pitch[:lag_min]}-#{pitch[:lag_max]}"),
                  'hps ' + fields(bin: pitch[:hps_bin], order: 5, frequency: pitch[:hps_frequency]),
                  'autocorrelation ' + fields(lag: pitch[:acf_lag], period: pitch[:acf_period], frequency: pitch[:acf_frequency], strength: pitch[:acf_strength]),
                  'zero_crossing ' + fields(count: pitch[:crossings], frequency: pitch[:crossing_frequency]), '[zoom]',
                  fields(band: "#{zoom[:low]}-#{zoom[:high]}", points: zoom[:points], step: zoom[:step])])
    zoom[:peaks].each { |r| lines << fields(peak: r[:rank], frequency: r[:frequency], amplitude: r[:amplitude]) }
    lines.concat(['[welch]', fields(segment_length: welch[:length], segments: welch[:segments], window: welch[:window], resolution: fs.to_f / welch[:length]),
                  fields(integrated_power: welch[:integrated_power], variance: welch[:variance], ratio: welch[:ratio])])
    welch[:peaks].each { |r| lines << fields(peak: r[:rank], frequency: r[:frequency], psd_db: r[:psd_db], coherence: r[:coherence], gain: r[:gain], phase: r[:phase]) }
    b1, b2 = p[:bandpass]
    fn, wn = p[:notch]
    e1, e2 = filters[:envelope_band]
    lines.concat(['[filter]', fields(bandpass: "#{b1}-#{b2}", bins_kept: filters[:bins_kept], rms: filters[:bandpass_rms], energy_ratio: filters[:bandpass_ratio]),
                  fields(notch: fn, width: wn, bins_removed: filters[:bins_removed], rms: filters[:notch_rms]),
                  fields(fir_taps: filters[:fir_taps], dc_gain: filters[:dc_gain], gain_at_fundamental_db: filters[:gain_at_fundamental_db], rms: filters[:fir_rms]),
                  '[envelope]', fields(band: "#{e1}-#{e2}", mean: filters[:envelope_mean], bin: filters[:envelope_bin], frequency: filters[:envelope_frequency], amplitude: filters[:envelope_amplitude], depth: filters[:envelope_depth]),
                  'instantaneous_frequency ' + fields(mean: filters[:instantaneous_mean], std: filters[:instantaneous_std]), '[correlation]',
                  fields(max_lag: p[:max_lag], lag: correlation[:lag], refined_lag: correlation[:refined_lag], delay_ms: correlation[:delay_ms], coefficient: correlation[:coefficient]),
                  fields(phat_lag: correlation[:phat_lag], refined_lag: correlation[:phat_refined], delay_ms: correlation[:phat_delay_ms]), '[checks]'])
    checks.each do |name, ok|
      items = {name => ok ? 'ok' : 'failed'}
      items[:transforms] = 2 * welch[:segments] + spectrogram[:frames] if name == :real_packing
      items[:bins] = peaks.length if name == :dft_spot_check
      lines << fields(**items)
    end
    symptoms = diagnostic[:symptoms].transform_values { |value| value ? 'yes' : 'no' }
    lines.concat(['[diagnosis]', fields(misalignment: symptoms[:misalignment], ratio: diagnostic[:amplitude_ratio]),
                  fields(looseness: symptoms[:looseness], harmonics: diagnostic[:looseness_count]),
                  fields(bearing: symptoms[:bearing], depth: filters[:envelope_depth]),
                  fields(electrical: symptoms[:electrical], level_db: diagnostic[:electrical_level].nil? ? 'none' : real(diagnostic[:electrical_level])),
                  fields(transient: symptoms[:transient], onsets: spectrogram[:onsets].length),
                  fields(status: diagnostic[:status], findings: diagnostic[:findings])])
    lines
  end

  def main
    fs, raw_x, raw_y = read_signal
    p = read_params
    n, m = raw_x.length, p[:main_length]
    x, stats_x = detrend(raw_x, fs)
    y, stats_y = detrend(raw_y, fs)
    history, loudest = level_history(x, y, p[:block_length])
    weighted, transformed, amplitudes = amplitude_spectrum(x, p[:main_window], m)
    calibration = figures(window(p[:main_window], m), fs)
    welch = analyze_welch(x, y, p, fs)
    peaks, maximum, floor = main_peaks(amplitudes, transformed, p, fs, welch)
    harmonics, thd = harmonic_analysis(amplitudes, p, fs)
    bin_power, powers = power_analysis(amplitudes, fs, p, harmonics, calibration[:enbw_bins])
    bands, octaves = calculate_bands(bin_power, p, fs, calibration[:enbw_bins], powers[:total_power])
    comparison = compare_windows(x, p, fs)
    spectrogram = analyze_spectrogram(x, p, fs)
    filters = filtered_waveforms(x, y, p, fs)
    pitch = estimate_pitch(amplitudes, filters[:bandpassed], p, fs)
    zoom = analyze_zoom(weighted, calibration[:s1], p, fs)
    correlation = analyze_correlation(x, y, p[:max_lag], fs)
    checks = verify_transforms(weighted, transformed, peaks, filters, welch, spectrogram)
    diagnostic = diagnosis(peaks, harmonics, filters, spectrogram)
    write_csv('spectrum.csv', 'frequency,amplitude', amplitudes.each_with_index.map { |v, k| [k * fs.to_f / m, v] })
    write_lines('peaks.txt', render_peaks(peaks, maximum, floor, p, fs))
    write_csv('welch_psd.csv', 'frequency,psd_db', welch[:psd].each_with_index.map { |v, k| [k * fs.to_f / welch[:length], decibels(v, 10)] })
    write_lines('spectrogram.txt', render_spectrogram(spectrogram, fs))
    write_csv('filtered.csv', 'index,bandpass,notched,smoothed,envelope', Array.new(n) { |i| [i, filters[:bandpassed][i], filters[:notched][i], filters[:smoothed][i], filters[:envelope][i]] })
    write_lines('report.txt', render_report(fs, n, [stats_x, stats_y], history, loudest, comparison, powers, bands, octaves,
                                           harmonics, thd, pitch, zoom, welch, spectrogram, filters, correlation, checks, diagnostic, peaks, p))
  end
end

Spectrum.main if $PROGRAM_NAME == __FILE__
