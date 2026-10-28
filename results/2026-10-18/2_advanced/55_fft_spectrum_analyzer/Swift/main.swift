import Foundation

func meanSquare(_ values: [Double]) -> Double { values.reduce(0) { $0 + $1 * $1 } / Double(values.count) }
func rms(_ values: [Double]) -> Double { sqrt(meanSquare(values)) }
func db(_ value: Double, _ factor: Double = 20) -> Double { factor * log10(value) }
func phase(_ value: Complex) -> Double { value.argument * 180 / pi }
func strongest(_ values: [Double], _ candidates: [Int]) -> Int { var best = candidates[0]; for k in candidates.dropFirst() { if values[k] > values[best] { best = k } }; return best }
func localPeaks(_ values: [Double], _ limit: Int) -> [Int] { Array(values.indices.filter { localMaximum(values, $0) }.sorted { values[$0] == values[$1] ? $0 < $1 : values[$0] > values[$1] }.prefix(limit)) }
struct ChannelStatistics {
    let mean: Double
    let slope: Double
    let rms: Double
    let minimum: Double
    let maximum: Double
    let crest: Double
    let skewness: Double
    let kurtosis: Double
    var text: String { "mean=\(real(mean)) slope=\(real(slope)) rms=\(real(rms)) min=\(real(minimum)) max=\(real(maximum)) crest=\(real(crest)) skewness=\(real(skewness)) kurtosis=\(real(kurtosis))" }
}
func detrend(_ samples: [Double], _ sampleRate: Double) -> (values: [Double], statistics: ChannelStatistics) {
    let count = Double(samples.count), center = (count - 1) / 2, mean = samples.reduce(0, +) / count
    let numerator = samples.indices.reduce(0.0) { $0 + (Double($1) - center) * (samples[$1] - mean) }, denominator = samples.indices.reduce(0.0) { let d = Double($1) - center; return $0 + d * d }, slope = numerator / denominator
    let values = samples.indices.map { samples[$0] - mean - slope * (Double($0) - center) }, level = rms(values)
    return (values, ChannelStatistics(mean: mean, slope: slope * sampleRate, rms: level, minimum: samples.min()!, maximum: samples.max()!, crest: values.map { abs($0) }.max()! / level, skewness: (values.reduce(0) { $0 + $1 * $1 * $1 } / count) / (level * level * level), kurtosis: (values.reduce(0) { $0 + $1 * $1 * $1 * $1 } / count) / (level * level * level * level)))
}
struct LevelBlock { let number: Int; let rms1: Double; let rms2: Double; let peak1: Double }
func levelHistory(_ x: [Double], _ y: [Double], _ length: Int) -> [LevelBlock] {
    (0..<(x.count / length)).map { g in let first = Array(x[(g * length)..<((g + 1) * length)]), second = Array(y[(g * length)..<((g + 1) * length)]); return LevelBlock(number: g, rms1: rms(first), rms2: rms(second), peak1: first.map { abs($0) }.max()!) }
}
func bandwidth(_ amplitudes: [Double], _ k: Int) -> Double {
    let last = amplitudes.count - 1, cutoff = amplitudes[k] / sqrt(2)
    var right = Double(last), left = 0.0
    for j in (k + 1)...last { if amplitudes[j] <= cutoff { right = Double(j - 1) + (amplitudes[j - 1] - cutoff) / (amplitudes[j - 1] - amplitudes[j]); break } }
    for j in (0..<k).reversed() { if amplitudes[j] <= cutoff { left = Double(j + 1) - (amplitudes[j + 1] - cutoff) / (amplitudes[j + 1] - amplitudes[j]); break } }
    return right - left
}
struct Peak {
    let rank: Int
    let bin: Int
    let position: Double
    let binAmplitude: Double
    let amplitude: Double
    let levelDB: Double
    let phase: Double
    let bandwidth: Double
    let snrDB: Double
    let coherence: Double
    var label = "other"
}
func peakLabel(_ peak: Peak, _ peaks: [Peak], _ params: Parameters, _ sampleRate: Double) -> String {
    for h in 1...10 { if abs(peak.position - Double(h) * params.fundamental * Double(params.mainLength) / sampleRate) <= Double(params.search) { return "h\(h)" } }
    let frequency = peak.position * sampleRate / Double(params.mainLength), multiple = Int(floor(frequency / Double(params.notch) + 0.5))
    if multiple >= 1 && abs(frequency - Double(multiple * params.notch)) <= Double(params.notchWidth) { return "mains" }
    for pivot in peaks where pivot.rank != peak.rank && pivot.binAmplitude > peak.binAmplitude {
        for other in peaks where other.rank != peak.rank && other.rank != pivot.rank && pivot.binAmplitude > other.binAmplitude { if abs(peak.position + other.position - 2 * pivot.position) <= 1 { return "sideband\(pivot.rank)" } }
    }
    return "other"
}
func mainPeaks(_ spectrum: AmplitudeSpectrum, _ params: Parameters, _ sampleRate: Double, _ welch: WelchSpectra) -> (peaks: [Peak], maximum: Double, noise: Double) {
    let amplitudes = spectrum.amplitudes, maximum = amplitudes.max()!, noise = median(Array(amplitudes.dropFirst().dropLast()))
    let candidates = localPeaks(amplitudes, amplitudes.count).filter { db(amplitudes[$0] / maximum) >= params.threshold }.prefix(params.peakCount)
    var peaks = candidates.enumerated().map { rank, k -> Peak in
        let refined = interpolate(amplitudes, k), coherenceBin = (2 * k * params.welchLength + params.mainLength) / (2 * params.mainLength)
        return Peak(rank: rank + 1, bin: k, position: refined.position, binAmplitude: amplitudes[k], amplitude: refined.value, levelDB: db(amplitudes[k] / maximum), phase: phase(spectrum.transformed[k]), bandwidth: bandwidth(amplitudes, k) * sampleRate / Double(params.mainLength), snrDB: db(amplitudes[k] / noise), coherence: welch.coherence[coherenceBin])
    }
    let original = peaks
    for i in peaks.indices { peaks[i].label = peakLabel(original[i], original, params, sampleRate) }
    return (peaks, maximum, noise)
}
struct Harmonic { let number: Int; let target: Double; let bin: Int; let frequency: Double; let amplitude: Double; let levelDB: Double }
func harmonicAnalysis(_ amplitudes: [Double], _ params: Parameters, _ sampleRate: Double) -> [Harmonic] {
    var found: [(bin: Int, position: Double, amplitude: Double)] = []
    for h in 1...10 {
        let center = Double(h) * params.fundamental * Double(params.mainLength) / sampleRate, candidates = (1..<(params.mainLength / 2)).filter { abs(Double($0) - center) <= Double(params.search) }, k = strongest(amplitudes, candidates), refined = interpolate(amplitudes, k)
        found.append((k, refined.position, refined.value))
    }
    return found.enumerated().map { i, value in Harmonic(number: i + 1, target: Double(i + 1) * params.fundamental, bin: value.bin, frequency: value.position * sampleRate / Double(params.mainLength), amplitude: value.amplitude, levelDB: db(value.amplitude / found[0].amplitude)) }
}
struct PowerAnalysis { let bins: [Double]; let total: Double; let centroid: Double; let spread: Double; let rolloff: Double; let flatnessDB: Double; let thdn: Double }
func powerAnalysis(_ amplitudes: [Double], _ params: Parameters, _ sampleRate: Double, _ fundamentalBin: Int, _ enbw: Double) -> PowerAnalysis {
    let power = amplitudes.map { $0 * $0 / 2 }, interior = 1..<(params.mainLength / 2), total = interior.reduce(0) { $0 + power[$1] }, fundamental = interior.filter { abs($0 - fundamentalBin) <= params.search }.reduce(0) { $0 + power[$1] } / enbw
    let centroid = interior.reduce(0.0) { $0 + Double($1) * sampleRate / Double(params.mainLength) * power[$1] } / total
    let spread = sqrt(interior.reduce(0.0) { let d = Double($1) * sampleRate / Double(params.mainLength) - centroid; return $0 + d * d * power[$1] } / total)
    var cumulative = 0.0, rolloff = 0.0
    for k in interior { cumulative += power[k]; if cumulative >= 0.85 * total { rolloff = Double(k) * sampleRate / Double(params.mainLength); break } }
    let average = total / Double(interior.count), flatness = 10 * log10(exp(interior.reduce(0) { $0 + log(power[$1]) } / Double(interior.count)) / average)
    return PowerAnalysis(bins: power, total: total / enbw, centroid: centroid, spread: spread, rolloff: rolloff, flatnessDB: flatness, thdn: sqrt((total / enbw - fundamental) / fundamental))
}
struct BandPower { let lower: Int; let upper: Int; let power: Double; let percent: Double }
struct Octave { let band: Int; let center: Double; let lower: Double; let upper: Double; let bins: Int; let levelDB: Double }
func calculateBands(_ powers: PowerAnalysis, _ params: Parameters, _ sampleRate: Int, _ enbw: Double) -> (bands: [BandPower], octaves: [Octave]) {
    let interior = 1..<(params.mainLength / 2)
    let bands = (0..<(params.bands.count - 1)).map { i -> BandPower in
        let low = params.bands[i], high = params.bands[i + 1], power = interior.filter { low * params.mainLength <= $0 * sampleRate && $0 * sampleRate < high * params.mainLength }.reduce(0) { $0 + powers.bins[$1] } / enbw
        return BandPower(lower: low, upper: high, power: power, percent: 100 * power / powers.total)
    }
    let octaves = (params.octaveLow...params.octaveHigh).map { band -> Octave in
        let center = 1000 * pow(2, Double(band) / 3), lower = 1000 * pow(2, Double(2 * band - 1) / 6), upper = 1000 * pow(2, Double(2 * band + 1) / 6)
        let bins = interior.filter { let frequency = Double($0 * sampleRate) / Double(params.mainLength); return lower <= frequency && frequency < upper }, power = bins.reduce(0) { $0 + powers.bins[$1] } / enbw
        return Octave(band: band, center: center, lower: lower, upper: upper, bins: bins.count, levelDB: db(power, 10))
    }
    return (bands, octaves)
}
struct WindowComparison { let name: String; let figures: WindowFigures; let bin: Int; let amplitude: Double; let refined: Double; let floorDB: Double }
func compareWindows(_ signal: [Double], _ params: Parameters, _ sampleRate: Double) -> [WindowComparison] {
    let center = params.fundamental * Double(params.mainLength) / sampleRate, candidates = (1..<(params.mainLength / 2)).filter { abs(Double($0) - center) <= Double(params.search) }
    return windowOrder.map { name in
        let calibration = figures(window(name, params.mainLength), sampleRate), amplitudes = amplitudeSpectrum(signal, name, params.mainLength).amplitudes, bin = strongest(amplitudes, candidates)
        return WindowComparison(name: name, figures: calibration, bin: bin, amplitude: amplitudes[bin], refined: interpolate(amplitudes, bin).value, floorDB: db(median(Array(amplitudes.dropFirst().dropLast()))))
    }
}
struct Spectrogram {
    let grid: [[Double]]
    let packingError: Double
    let maximum: Double
    let dominant: [Int]
    let flux: [Double]
    let threshold: Double
    let onsets: [Int]
    let kurtosis: [Double]
    let topKurtosis: Int
}
func analyzeSpectrogram(_ signal: [Double], _ params: Parameters) -> Spectrogram {
    let transformed = spectrogramMagnitudes(signal, params.frameLength, params.hop, params.frameWindow), grid = transformed.grid, frames = grid.count, count = params.frameLength / 2 + 1
    let dominant = grid.map { strongest($0, Array(1..<(count - 1))) }
    var flux = [0.0]
    for t in 1..<frames { flux.append((0..<count).reduce(0) { $0 + max(0, grid[t][$1] - grid[t - 1][$1]) }) }
    let threshold = params.onsetFactor * median(Array(flux.dropFirst())), onsets = (1..<frames).filter { flux[$0] > threshold && flux[$0] > flux[$0 - 1] && ($0 == frames - 1 || flux[$0] > flux[$0 + 1]) }
    let kurtosis = (0..<count).map { k -> Double in let second = grid.reduce(0) { $0 + $1[k] * $1[k] }, fourth = grid.reduce(0) { $0 + $1[k] * $1[k] * $1[k] * $1[k] }; return Double(frames) * fourth / (second * second) - 2 }
    return Spectrogram(grid: grid, packingError: transformed.error, maximum: grid.flatMap { $0 }.max()!, dominant: dominant, flux: flux, threshold: threshold, onsets: onsets, kurtosis: kurtosis, topKurtosis: strongest(kurtosis, Array(1..<(count - 1))))
}

struct FilteredSignals {
    let bandpassed: [Double]
    let notched: [Double]
    let smoothed: [Double]
    let envelope: [Double]
    let binsKept: Int
    let binsRemoved: Int
    let firError: Double
    let firGainDB: Double
    let dcGain: Double
    let envelopeMean: Double
    let envelopeBin: Int
    let envelopeFrequency: Double
    let envelopeAmplitude: Double
    let envelopeDepth: Double
    let instantaneousMean: Double
    let instantaneousStd: Double
}
func filteredWaveforms(_ x: [Double], _ y: [Double], _ params: Parameters, _ sampleRate: Int) -> FilteredSignals {
    let count = x.count, n = Double(count), fs = Double(sampleRate), spectrum = dft(x)
    var passed: [Complex] = [], notched: [Complex] = [], kept = 0, removed = 0
    for k in spectrum.indices {
        let frequency = min(k, count - k) * sampleRate, inBand = params.bandpassLow * count <= frequency && frequency <= params.bandpassHigh * count
        if inBand { kept += 1 }; passed.append(inBand ? spectrum[k] : Complex())
        let nearest = (2 * frequency + params.notch * count) / (2 * params.notch * count), inNotch = nearest >= 1 && abs(frequency - nearest * params.notch * count) <= params.notchWidth * count
        if inNotch { removed += 1 }; notched.append(inNotch ? Complex() : spectrum[k])
    }
    let bandpassed = idft(passed).map { $0.real }, notchResult = idft(notched).map { $0.real }
    var analyticSpectrum = Array(repeating: Complex(), count: count)
    for k in 1...((count - 1) / 2) where params.envelopeLow * count <= k * sampleRate && k * sampleRate <= params.envelopeHigh * count { analyticSpectrum[k] = spectrum[k] * 2 }
    let analytic = idft(analyticSpectrum), envelope = analytic.map { $0.magnitude }, mean = envelope.reduce(0, +) / n
    let modulation = dft(envelope.map { $0 - mean }).map { 2 * $0.magnitude / n }, stop = (params.envelopeHigh - params.envelopeLow) * count / (2 * sampleRate), envelopeBin = strongest(modulation, Array(1...stop)), envelopePeak = interpolate(modulation, envelopeBin)
    var instantaneous: [Double] = []
    for i in 1..<count { var difference = analytic[i].argument - analytic[i - 1].argument; if difference <= -pi { difference += 2 * pi }; if difference > pi { difference -= 2 * pi }; instantaneous.append(difference * fs / (2 * pi)) }
    let frequencyMean = instantaneous.reduce(0, +) / Double(instantaneous.count), frequencyStd = sqrt(instantaneous.reduce(0) { let difference = $1 - frequencyMean; return $0 + difference * difference } / Double(instantaneous.count))
    let smoothed = convolution(y, params.taps), gain = params.taps.indices.reduce(Complex()) { $0 + rotation(2 * pi * params.fundamental * Double($1) / fs) * params.taps[$1] }
    var error = 0.0
    for i in smoothed.indices {
        let direct = (max(0, i - params.taps.count + 1)...min(count - 1, i)).reduce(0.0) { $0 + y[$1] * params.taps[i - $1] }
        error = max(error, abs(smoothed[i] - direct))
    }
    return FilteredSignals(bandpassed: bandpassed, notched: notchResult, smoothed: smoothed, envelope: envelope, binsKept: kept, binsRemoved: removed, firError: error, firGainDB: db(gain.magnitude), dcGain: params.taps.reduce(0, +), envelopeMean: mean, envelopeBin: envelopeBin, envelopeFrequency: envelopePeak.position * fs / n, envelopeAmplitude: envelopePeak.value, envelopeDepth: envelopePeak.value / mean, instantaneousMean: frequencyMean, instantaneousStd: frequencyStd)
}
struct Pitch {
    let minimumLag: Int
    let maximumLag: Int
    let hpsBin: Int
    let hpsFrequency: Double
    let acfLag: Int
    let period: Double
    let frequency: Double
    let strength: Double
    let crossings: Int
    let crossingFrequency: Double
}
func estimatePitch(_ amplitudes: [Double], _ bandpassed: [Double], _ params: Parameters, _ sampleRate: Int) -> Pitch {
    let count = bandpassed.count, half = params.mainLength / 2, minimum = (sampleRate + params.pitchHigh - 1) / params.pitchHigh, maximum = sampleRate / params.pitchLow
    let candidates = (1...half).filter { params.pitchLow * params.mainLength <= $0 * sampleRate && $0 * sampleRate <= params.pitchHigh * params.mainLength && 5 * $0 <= half }
    let hps = candidates.map { k in (1...5).reduce(0.0) { $0 + log(amplitudes[$1 * k]) } }, best = strongest(hps, Array(hps.indices)), hpsBin = candidates[best]
    let size = powerOfTwo(2 * count - 1), transformed = radix2(complexValues(bandpassed) + Array(repeating: Complex(), count: size - count)), correlation = radix2(transformed.map { Complex($0.squaredMagnitude) }, inverse: true).map { $0.real }
    let lag = strongest(correlation, Array(minimum...maximum)), refined = interpolate(correlation, lag, logarithmic: false), crossings = (1..<count).filter { bandpassed[$0 - 1] < 0 && bandpassed[$0] >= 0 }.count
    return Pitch(minimumLag: minimum, maximumLag: maximum, hpsBin: hpsBin, hpsFrequency: Double(hpsBin * sampleRate) / Double(params.mainLength), acfLag: lag, period: refined.position, frequency: Double(sampleRate) / refined.position, strength: refined.value / correlation[0], crossings: crossings, crossingFrequency: Double(crossings * sampleRate) / Double(count))
}
struct ZoomPeak { let rank: Int; let frequency: Double; let amplitude: Double }
func analyzeZoom(_ weighted: [Double], _ coherentSum: Double, _ params: Parameters, _ sampleRate: Double) -> [ZoomPeak] {
    let step = Double(params.zoomHigh - params.zoomLow) / Double(params.zoomPoints - 1), spectrum = chirpZ(weighted, sampleRate, params.zoomLow, params.zoomHigh, params.zoomPoints), amplitudes = spectrum.map { 2 * $0.magnitude / coherentSum }
    return localPeaks(amplitudes, 3).enumerated().map { rank, k in let refined = interpolate(amplitudes, k); return ZoomPeak(rank: rank + 1, frequency: Double(params.zoomLow) + refined.position * step, amplitude: refined.value) }
}
func chooseLag(_ values: [Double], _ limit: Int) -> (lag: Int, refined: Double) {
    let count = values.count
    func index(_ lag: Int) -> Int { lag < 0 ? lag + count : lag }
    var best = -limit
    for lag in (-limit)...limit {
        let a = values[index(lag)], b = values[index(best)]
        if a > b || (a == b && (abs(lag) < abs(best) || (abs(lag) == abs(best) && lag < best))) { best = lag }
    }
    let neighbors = (-1...1).map { values[index(best + $0)] }, position = interpolate(neighbors, 1, logarithmic: false).position
    return (best, Double(best) + position - 1)
}
struct Correlation { let lag: Int; let refined: Double; let delay: Double; let coefficient: Double; let phatLag: Int; let phatRefined: Double; let phatDelay: Double }
func analyzeCorrelation(_ x: [Double], _ y: [Double], _ limit: Int, _ sampleRate: Double) -> Correlation {
    let count = x.count, size = powerOfTwo(2 * count - 1), zeros = Array(repeating: Complex(), count: size - count), fx = radix2(complexValues(x) + zeros), fy = radix2(complexValues(y) + zeros)
    let cross = (0..<size).map { fx[$0].conjugate * fy[$0] }, raw = radix2(cross, inverse: true).map { $0.real }, phat = radix2(cross.map { $0 / $0.magnitude }, inverse: true).map { $0.real }
    let chosen = chooseLag(raw, limit), phased = chooseLag(phat, limit), energyX = x.reduce(0) { $0 + $1 * $1 }, energyY = y.reduce(0) { $0 + $1 * $1 }
    return Correlation(lag: chosen.lag, refined: chosen.refined, delay: 1000 * chosen.refined / sampleRate, coefficient: raw[chosen.lag < 0 ? chosen.lag + size : chosen.lag] / sqrt(energyX * energyY), phatLag: phased.lag, phatRefined: phased.refined, phatDelay: 1000 * phased.refined / sampleRate)
}
struct TransformChecks { let inverse: Bool; let parseval: Bool; let packing: Bool; let fir: Bool; let spots: Bool }
func verifyTransforms(_ spectrum: AmplitudeSpectrum, _ peaks: [Peak], _ filters: FilteredSignals, _ welch: WelchSpectra, _ spectrogram: Spectrogram) -> TransformChecks {
    let weighted = spectrum.weighted, transformed = spectrum.transformed, count = weighted.count, inverse = idft(transformed), inverseError = weighted.indices.map { (inverse[$0] - Complex(weighted[$0])).magnitude }.max()!
    let timeEnergy = weighted.reduce(0) { $0 + $1 * $1 }, frequencyEnergy = transformed.reduce(0) { $0 + $1.squaredMagnitude } / Double(count)
    var spotError = 0.0
    for peak in peaks {
        let direct = weighted.indices.reduce(Complex()) { $0 + rotation(2 * pi * Double((peak.bin * $1) % count) / Double(count)) * weighted[$1] }
        spotError = max(spotError, (direct - transformed[peak.bin]).magnitude)
    }
    return TransformChecks(inverse: inverseError <= 1e-6, parseval: abs(timeEnergy - frequencyEnergy) / timeEnergy <= 1e-6, packing: max(welch.packingError, spectrogram.packingError) <= 1e-6, fir: filters.firError <= 1e-6, spots: spotError <= 1e-6)
}
func renderPeaks(_ peaks: [Peak], _ maximum: Double, _ noise: Double, _ params: Parameters, _ sampleRate: Double) -> [String] {
    let length = Double(params.mainLength)
    return ["length=\(params.mainLength) window=\(params.mainWindow) resolution=\(real(sampleRate / length)) threshold_db=\(real(params.threshold))", "max_amplitude=\(real(maximum)) noise_floor=\(real(noise)) noise_floor_db=\(real(db(noise)))", "peaks=\(peaks.count)"] + peaks.map { "\($0.rank) bin=\($0.bin) frequency=\(real(Double($0.bin) * sampleRate / length)) refined=\(real($0.position * sampleRate / length)) amplitude=\(real($0.amplitude)) level_db=\(real($0.levelDB)) phase=\(real($0.phase)) bandwidth=\(real($0.bandwidth)) snr_db=\(real($0.snrDB)) coherence=\(real($0.coherence)) label=\($0.label)" }
}
func renderSpectrogram(_ data: Spectrogram, _ params: Parameters, _ sampleRate: Double) -> [String] {
    let length = params.frameLength
    var lines = ["frames=\(data.grid.count) bins=\(length / 2 + 1) frame_length=\(length) hop=\(params.hop) window=\(params.frameWindow) band_db=\(params.bandDB) max_db=\(real(db(data.maximum)))"] + shadeLines(data.grid, sampleRate, length, params.bandDB) + ["track"]
    for t in data.grid.indices { let k = data.dominant[t]; lines.append("frame=\(t) time=\(real(Double(t * params.hop) / sampleRate)) frequency=\(real(Double(k) * sampleRate / Double(length))) level_db=\(real(db(data.grid[t][k] / data.maximum)))") }
    lines.append("onsets=\(data.onsets.count) threshold=\(real(data.threshold))")
    for t in data.onsets { lines.append("frame=\(t) time=\(real(Double(t * params.hop) / sampleRate)) flux=\(real(data.flux[t]))") }
    let k = data.topKurtosis
    lines.append("kurtosis bin=\(k) frequency=\(real(Double(k) * sampleRate / Double(length))) value=\(real(data.kurtosis[k]))")
    return lines
}

let signal = try readSignal(), params = try readParameters()
let fs = Double(signal.sampleRate), first = detrend(signal.first, Double(signal.sampleRate)), second = detrend(signal.second, Double(signal.sampleRate))
let x = first.values, y = second.values, n = x.count, length = params.mainLength
let history = levelHistory(x, y, params.blockLength), loudest = strongest(history.map { $0.rms1 }, Array(history.indices))
let spectrum = amplitudeSpectrum(x, params.mainWindow, length), calibration = figures(window(params.mainWindow, length), fs)
let welch = welchSpectra(x, y, fs, params.welchLength, params.welchWindow)
let detected = mainPeaks(spectrum, params, fs, welch), peaks = detected.peaks, harmonics = harmonicAnalysis(spectrum.amplitudes, params, fs)
let powers = powerAnalysis(spectrum.amplitudes, params, fs, harmonics[0].bin, calibration.enbwBins), bands = calculateBands(powers, params, signal.sampleRate, calibration.enbwBins), comparison = compareWindows(x, params, fs)
let spectrogram = analyzeSpectrogram(x, params), filters = filteredWaveforms(x, y, params, signal.sampleRate), pitch = estimatePitch(spectrum.amplitudes, filters.bandpassed, params, signal.sampleRate)
let zoom = analyzeZoom(spectrum.weighted, calibration.sum, params, fs), correlation = analyzeCorrelation(x, y, params.maximumLag, fs), checks = verifyTransforms(spectrum, peaks, filters, welch, spectrogram)
let thd = sqrt(harmonics.dropFirst().reduce(0) { $0 + $1.amplitude * $1.amplitude }) / harmonics[0].amplitude
let integrated = welch.psd.reduce(0, +) * fs / Double(params.welchLength), variance = first.statistics.rms * first.statistics.rms
let amplitudeRatio = harmonics[1].amplitude / harmonics[0].amplitude, looseness = harmonics.dropFirst(2).filter { $0.levelDB >= -30 }.count, electrical = peaks.first { $0.label == "mains" }
let symptoms = [amplitudeRatio >= 0.5, looseness >= 3, filters.envelopeDepth >= 0.2, electrical.map { $0.levelDB >= -20 } ?? false, !spectrogram.onsets.isEmpty], findings = symptoms.filter { $0 }.count
func yes(_ value: Bool) -> String { value ? "yes" : "no" }
func status(_ value: Bool) -> String { value ? "ok" : "failed" }

var report = ["[signal]", "sample_rate=\(signal.sampleRate) samples=\(n) duration=\(real(Double(n) / fs))", "channel=1 " + first.statistics.text, "channel=2 " + second.statistics.text,
              "[levels]", "block_length=\(params.blockLength) blocks=\(history.count) loudest=\(loudest)"]
for block in history { report.append("block=\(block.number) time=\(real(Double(block.number * params.blockLength) / fs)) rms1=\(real(block.rms1)) rms2=\(real(block.rms2)) peak1=\(real(block.peak1))") }
report.append("[windows]")
for item in comparison {
    let figures = item.figures
    report.append("name=\(item.name) coherent_gain=\(real(figures.coherentGain)) enbw_bins=\(real(figures.enbwBins)) enbw_hz=\(real(figures.enbwHz)) scalloping_db=\(real(figures.scallopingDB)) fundamental_bin=\(item.bin) bin_amplitude=\(real(item.amplitude)) refined_amplitude=\(real(item.refined)) floor_db=\(real(item.floorDB))")
}
let isPowerOfTwo = length & (length - 1) == 0
report += ["[main]", "length=\(length) window=\(params.mainWindow) method=\(isPowerOfTwo ? "radix2" : "bluestein") transform_size=\(isPowerOfTwo ? length : powerOfTwo(2 * length - 1)) resolution=\(real(fs / Double(length)))", "total_power=\(real(powers.total)) centroid=\(real(powers.centroid)) spread=\(real(powers.spread)) rolloff=\(real(powers.rolloff)) flatness_db=\(real(powers.flatnessDB))", "[bands]"]
for band in bands.bands { report.append("range=\(band.lower)-\(band.upper) power=\(real(band.power)) percent=\(real(band.percent))") }
report.append("[third_octave]")
for band in bands.octaves { report.append("band=\(band.band) center=\(real(band.center)) lower=\(real(band.lower)) upper=\(real(band.upper)) bins=\(band.bins) level_db=\(real(band.levelDB))") }
report += ["[harmonics]", "fundamental=\(real(params.fundamental)) search=\(params.search)"]
for harmonic in harmonics { report.append("h=\(harmonic.number) target=\(real(harmonic.target)) bin=\(harmonic.bin) refined=\(real(harmonic.frequency)) amplitude=\(real(harmonic.amplitude)) level_db=\(real(harmonic.levelDB))") }
report += ["thd_percent=\(real(100 * thd)) thd_db=\(real(db(thd)))", "thdn_percent=\(real(100 * powers.thdn)) thdn_db=\(real(db(powers.thdn)))",
           "[pitch]", "range=\(params.pitchLow)-\(params.pitchHigh) lags=\(pitch.minimumLag)-\(pitch.maximumLag)", "hps bin=\(pitch.hpsBin) order=5 frequency=\(real(pitch.hpsFrequency))", "autocorrelation lag=\(pitch.acfLag) period=\(real(pitch.period)) frequency=\(real(pitch.frequency)) strength=\(real(pitch.strength))", "zero_crossing count=\(pitch.crossings) frequency=\(real(pitch.crossingFrequency))",
           "[zoom]", "band=\(params.zoomLow)-\(params.zoomHigh) points=\(params.zoomPoints) step=\(real(Double(params.zoomHigh - params.zoomLow) / Double(params.zoomPoints - 1)))"]
for peak in zoom { report.append("peak=\(peak.rank) frequency=\(real(peak.frequency)) amplitude=\(real(peak.amplitude))") }
report += ["[welch]", "segment_length=\(params.welchLength) segments=\(welch.segments) window=\(params.welchWindow) resolution=\(real(fs / Double(params.welchLength)))", "integrated_power=\(real(integrated)) variance=\(real(variance)) ratio=\(real(integrated / variance))"]
for (rank, bin) in localPeaks(welch.psd, 5).enumerated() { report.append("peak=\(rank + 1) frequency=\(real(Double(bin) * fs / Double(params.welchLength))) psd_db=\(real(db(welch.psd[bin], 10))) coherence=\(real(welch.coherence[bin])) gain=\(real(welch.transfer[bin].magnitude)) phase=\(real(phase(welch.transfer[bin])))") }
let energyX = x.reduce(0) { $0 + $1 * $1 }, energyPassed = filters.bandpassed.reduce(0) { $0 + $1 * $1 }, firRMS = sqrt(filters.smoothed.prefix(n).reduce(0) { $0 + $1 * $1 } / Double(n))
report += ["[filter]", "bandpass=\(params.bandpassLow)-\(params.bandpassHigh) bins_kept=\(filters.binsKept) rms=\(real(rms(filters.bandpassed))) energy_ratio=\(real(energyPassed / energyX))", "notch=\(params.notch) width=\(params.notchWidth) bins_removed=\(filters.binsRemoved) rms=\(real(rms(filters.notched)))", "fir_taps=\(params.taps.count) dc_gain=\(real(filters.dcGain)) gain_at_fundamental_db=\(real(filters.firGainDB)) rms=\(real(firRMS))",
           "[envelope]", "band=\(params.envelopeLow)-\(params.envelopeHigh) mean=\(real(filters.envelopeMean)) bin=\(filters.envelopeBin) frequency=\(real(filters.envelopeFrequency)) amplitude=\(real(filters.envelopeAmplitude)) depth=\(real(filters.envelopeDepth))", "instantaneous_frequency mean=\(real(filters.instantaneousMean)) std=\(real(filters.instantaneousStd))",
           "[correlation]", "max_lag=\(params.maximumLag) lag=\(correlation.lag) refined_lag=\(real(correlation.refined)) delay_ms=\(real(correlation.delay)) coefficient=\(real(correlation.coefficient))", "phat_lag=\(correlation.phatLag) refined_lag=\(real(correlation.phatRefined)) delay_ms=\(real(correlation.phatDelay))",
           "[checks]", "inverse_roundtrip=\(status(checks.inverse))", "parseval=\(status(checks.parseval))", "real_packing=\(status(checks.packing)) transforms=\(2 * welch.segments + spectrogram.grid.count)", "fir_fft_vs_direct=\(status(checks.fir))", "dft_spot_check=\(status(checks.spots)) bins=\(peaks.count)",
           "[diagnosis]", "misalignment=\(yes(symptoms[0])) ratio=\(real(amplitudeRatio))", "looseness=\(yes(symptoms[1])) harmonics=\(looseness)", "bearing=\(yes(symptoms[2])) depth=\(real(filters.envelopeDepth))", "electrical=\(yes(symptoms[3])) level_db=\(electrical.map { real($0.levelDB) } ?? "none")", "transient=\(yes(symptoms[4])) onsets=\(spectrogram.onsets.count)", "status=\(findings == 0 ? "normal" : findings == 1 ? "warning" : "alarm") findings=\(findings)"]

try writeCSV("spectrum.csv", "frequency,amplitude", spectrum.amplitudes.indices.map { [real(Double($0) * fs / Double(length)), real(spectrum.amplitudes[$0])] })
try writeLines("peaks.txt", renderPeaks(peaks, detected.maximum, detected.noise, params, fs))
try writeCSV("welch_psd.csv", "frequency,psd_db", welch.psd.indices.map { [real(Double($0) * fs / Double(params.welchLength)), real(db(welch.psd[$0], 10))] })
try writeLines("spectrogram.txt", renderSpectrogram(spectrogram, params, fs))
try writeCSV("filtered.csv", "index,bandpass,notched,smoothed,envelope", x.indices.map { [String($0), real(filters.bandpassed[$0]), real(filters.notched[$0]), real(filters.smoothed[$0]), real(filters.envelope[$0])] })
try writeLines("report.txt", report)
