import Foundation

struct Signal { let sampleRate: Int; let first: [Double]; let second: [Double] }
struct Parameters {
    let mainLength: Int
    let mainWindow: String
    let threshold: Double
    let peakCount: Int
    let fundamental: Double
    let search: Int
    let welchLength: Int
    let welchWindow: String
    let frameLength: Int
    let hop: Int
    let bandDB: Int
    let frameWindow: String
    let onsetFactor: Double
    let pitchLow: Int
    let pitchHigh: Int
    let bandpassLow: Int
    let bandpassHigh: Int
    let notch: Int
    let notchWidth: Int
    let envelopeLow: Int
    let envelopeHigh: Int
    let zoomLow: Int
    let zoomHigh: Int
    let zoomPoints: Int
    let taps: [Double]
    let maximumLag: Int
    let bands: [Int]
    let octaveLow: Int
    let octaveHigh: Int
    let blockLength: Int
}
func readLines(_ filename: String) throws -> [String] { try String(contentsOfFile: "input/" + filename, encoding: .ascii).split(separator: "\n").map(String.init) }
func readSignal() throws -> Signal {
    let rows = try readLines("signal.csv").map { $0.components(separatedBy: ",") }
    return Signal(sampleRate: Int(rows[0][0])!, first: rows.dropFirst().map { Double($0[0])! }, second: rows.dropFirst().map { Double($0[1])! })
}
func readParameters() throws -> Parameters {
    let fields = Dictionary(uniqueKeysWithValues: try readLines("params.txt").map { line in let values = line.components(separatedBy: " "); return (values[0], Array(values.dropFirst())) })
    func integer(_ name: String, _ index: Int = 0) -> Int { Int(fields[name]![index])! }
    func number(_ name: String) -> Double { Double(fields[name]![0])! }
    return Parameters(mainLength: integer("main_length"), mainWindow: fields["main_window"]![0], threshold: number("peak_threshold_db"), peakCount: integer("peak_count"), fundamental: number("fundamental"), search: integer("fundamental", 1), welchLength: integer("welch"), welchWindow: fields["welch"]![1], frameLength: integer("spectrogram"), hop: integer("spectrogram", 1), bandDB: integer("spectrogram", 2), frameWindow: fields["spectrogram"]![3], onsetFactor: number("onset_factor"), pitchLow: integer("pitch_range"), pitchHigh: integer("pitch_range", 1), bandpassLow: integer("bandpass"), bandpassHigh: integer("bandpass", 1), notch: integer("notch"), notchWidth: integer("notch", 1), envelopeLow: integer("envelope_band"), envelopeHigh: integer("envelope_band", 1), zoomLow: integer("zoom"), zoomHigh: integer("zoom", 1), zoomPoints: integer("zoom", 2), taps: fields["fir"]!.map { Double($0)! }, maximumLag: integer("max_lag"), bands: fields["bands"]!.map { Int($0)! }, octaveLow: integer("third_octave"), octaveHigh: integer("third_octave", 1), blockLength: integer("block_length"))
}
