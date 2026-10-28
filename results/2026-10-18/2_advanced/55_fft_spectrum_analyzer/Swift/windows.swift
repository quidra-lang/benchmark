import Foundation

let windowOrder = ["rectangular", "hann", "hamming", "blackman", "flattop"]
let windowCoefficients: [String: [Double]] = ["rectangular": [1], "hann": [0.5, 0.5], "hamming": [0.54, 0.46], "blackman": [0.42, 0.5, 0.08], "flattop": [0.21557895, 0.41663158, 0.277263158, 0.083578947, 0.006947368]]
func window(_ name: String, _ length: Int) -> [Double] {
    let coefficients = windowCoefficients[name]!
    return (0..<length).map { n in coefficients.enumerated().reduce(0) { total, item in total + (item.offset % 2 == 0 ? 1.0 : -1.0) * item.element * cos(2 * pi * Double(item.offset) * Double(n) / Double(length)) } }
}
struct WindowFigures { let sum: Double; let energy: Double; let coherentGain: Double; let enbwBins: Double; let enbwHz: Double; let scallopingDB: Double }
func figures(_ values: [Double], _ sampleRate: Double) -> WindowFigures {
    let count = Double(values.count), sum = values.reduce(0, +), energy = values.reduce(0) { $0 + $1 * $1 }, enbw = count * energy / (sum * sum)
    let offset = values.indices.reduce(Complex()) { $0 + rotation(pi * Double($1) / count) * values[$1] }
    return WindowFigures(sum: sum, energy: energy, coherentGain: sum / count, enbwBins: enbw, enbwHz: enbw * sampleRate / count, scallopingDB: -20 * log10(offset.magnitude / sum))
}
