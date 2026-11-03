import Foundation

func median(_ values: [Double]) -> Double { let ordered = values.sorted(), count = values.count; return count % 2 == 1 ? ordered[count / 2] : (ordered[count / 2 - 1] + ordered[count / 2]) / 2 }
func localMaximum(_ values: [Double], _ index: Int) -> Bool { index > 0 && index + 1 < values.count && values[index] > values[index - 1] && values[index] > values[index + 1] }
func interpolate(_ values: [Double], _ index: Int, logarithmic: Bool = true) -> (position: Double, value: Double) {
    if !localMaximum(values, index) { return (Double(index), values[index]) }
    let a = logarithmic ? log(values[index - 1]) : values[index - 1], b = logarithmic ? log(values[index]) : values[index], c = logarithmic ? log(values[index + 1]) : values[index + 1]
    let delta = (a - c) / (2 * (a - 2 * b + c)), fitted = b - (a - c) * delta / 4
    return (Double(index) + delta, logarithmic ? exp(fitted) : fitted)
}
struct AmplitudeSpectrum { let weighted: [Double]; let transformed: [Complex]; let amplitudes: [Double] }
func amplitudeSpectrum(_ signal: [Double], _ name: String, _ length: Int) -> AmplitudeSpectrum {
    let weights = window(name, length), weighted = (0..<length).map { signal[$0] * weights[$0] }, transformed = dft(weighted), sum = weights.reduce(0, +)
    return AmplitudeSpectrum(weighted: weighted, transformed: transformed, amplitudes: (0...(length / 2)).map { ( $0 == 0 || 2 * $0 == length ? 1.0 : 2.0) * transformed[$0].magnitude / sum })
}
func packedAndError(_ values: [Double]) -> (values: [Complex], error: Double) {
    let packed = packedReal(values), reference = radix2(complexValues(values)), error = packed.indices.map { (packed[$0] - reference[$0]).magnitude }.max()!
    return (packed, error)
}
struct WelchSpectra { let segments: Int; let psd: [Double]; let coherence: [Double]; let transfer: [Complex]; let packingError: Double }
func welchSpectra(_ x: [Double], _ y: [Double], _ sampleRate: Double, _ length: Int, _ name: String) -> WelchSpectra {
    let weights = window(name, length), energy = weights.reduce(0) { $0 + $1 * $1 }, step = length / 2, segments = (x.count - length) / step + 1, count = length / 2 + 1
    var xx = Array(repeating: 0.0, count: count), yy = xx, xy = Array(repeating: Complex(), count: count), packingError = 0.0
    for block in 0..<segments {
        let start = block * step, first = packedAndError((0..<length).map { x[start + $0] * weights[$0] }), second = packedAndError((0..<length).map { y[start + $0] * weights[$0] })
        packingError = max(packingError, max(first.error, second.error))
        for k in 0..<count { xx[k] += first.values[k].squaredMagnitude; yy[k] += second.values[k].squaredMagnitude; xy[k] = xy[k] + first.values[k].conjugate * second.values[k] }
    }
    let psd = (0..<count).map { ($0 == 0 || $0 == length / 2 ? 1.0 : 2.0) * xx[$0] / (Double(segments) * sampleRate * energy) }
    return WelchSpectra(segments: segments, psd: psd, coherence: (0..<count).map { xy[$0].squaredMagnitude / (xx[$0] * yy[$0]) }, transfer: (0..<count).map { xy[$0] / xx[$0] }, packingError: packingError)
}
func spectrogramMagnitudes(_ signal: [Double], _ length: Int, _ hop: Int, _ name: String) -> (grid: [[Double]], error: Double) {
    let weights = window(name, length), frames = (signal.count - length) / hop + 1
    var grid: [[Double]] = [], error = 0.0
    for t in 0..<frames { let result = packedAndError((0..<length).map { signal[t * hop + $0] * weights[$0] }); grid.append(result.values.map { $0.magnitude }); error = max(error, result.error) }
    return (grid, error)
}
