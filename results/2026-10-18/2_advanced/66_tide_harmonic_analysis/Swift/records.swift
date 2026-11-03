import Foundation

let dateFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)!; formatter.dateFormat = "yyyy-MM-dd HH:mm"; formatter.isLenient = false; return formatter }()
struct StationDefinition { let code: String; let name: String }
struct Constituent { let name: String; let speed: Double }
struct Settings {
    let epoch: Date
    var stations: [StationDefinition] = []
    var reference = ""
    var flatRun = 0
    var spikeWindow = 0
    var spikeMinimum = 0
    var spikeFactor = 0.0
    var spikeFloor = 0.0
    var rayleigh = 0.0
    var snrMinimum = 0.0
    var topResiduals = 0
    var surgeThreshold = 0.0
    var surgeHours = 0
    var predictionHour = 0
    var predictionHours = 0
    var gridMinutes = 0
    var minimumRange = 0.0
    var correlationLag = 0
    var plotCode = ""
    var plotHours = 0
    var plotTop = 0
    var plotBottom = 0
    var plotStep = 0
}
struct ObservationSeries { var values: [Int: Double] = [:]; var milli: [Int: Int] = [:]; var missing: Set<Int> = []; var rows = 0 }
struct Inputs { let settings: Settings; let constituents: [Constituent]; let observations: [ObservationSeries] }
func inputLines(_ name: String) throws -> [String] { try String(contentsOfFile: "input/" + name, encoding: .ascii).split(separator: "\n").map(String.init) }
func epochHours(_ epoch: Date, _ text: String) -> Int { Int(dateFormatter.date(from: text)!.timeIntervalSince(epoch) / 3600) }
func datetimeAtMinute(_ epoch: Date, _ minute: Int) -> String { dateFormatter.string(from: epoch.addingTimeInterval(Double(minute) * 60)) }
func datetimeAtHour(_ epoch: Date, _ hour: Int) -> String { datetimeAtMinute(epoch, hour * 60) }
func dateAtDay(_ epoch: Date, _ day: Int) -> String { String(datetimeAtHour(epoch, day * 24).prefix(10)) }
func readInputs() throws -> Inputs {
    let lines = try inputLines("params.txt"), epoch = dateFormatter.date(from: String(lines[0].dropFirst(6)))!
    var settings = Settings(epoch: epoch)
    for line in lines.dropFirst() {
        let fields = line.split(separator: " ").map(String.init)
        switch fields[0] {
        case "station": let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false); settings.stations.append(StationDefinition(code: String(parts[1]), name: String(parts[2])))
        case "reference": settings.reference = fields[1]
        case "flat_run": settings.flatRun = Int(fields[1])!
        case "spike": settings.spikeWindow = Int(fields[1])!; settings.spikeMinimum = Int(fields[2])!; settings.spikeFactor = Double(fields[3])!; settings.spikeFloor = Double(fields[4])!
        case "rayleigh": settings.rayleigh = Double(fields[1])!
        case "snr_min": settings.snrMinimum = Double(fields[1])!
        case "top_residuals": settings.topResiduals = Int(fields[1])!
        case "surge": settings.surgeThreshold = Double(fields[1])!; settings.surgeHours = Int(fields[2])!
        case "predict": settings.predictionHour = epochHours(epoch, fields[1] + " " + fields[2]); settings.predictionHours = Int(fields[3])!
        case "grid_minutes": settings.gridMinutes = Int(fields[1])!
        case "min_range": settings.minimumRange = Double(fields[1])!
        case "correlation_lag": settings.correlationLag = Int(fields[1])!
        default: settings.plotCode = fields[1]; settings.plotHours = Int(fields[2])!; settings.plotTop = Int(fields[3])!; settings.plotBottom = Int(fields[4])!; settings.plotStep = Int(fields[5])!
        }
    }
    let constituents = try inputLines("constituents.txt").dropFirst().map { line -> Constituent in let fields = line.split(separator: " "); return Constituent(name: String(fields[0]), speed: Double(fields[1])!) }, stationIndices = Dictionary(uniqueKeysWithValues: settings.stations.enumerated().map { ($0.element.code, $0.offset) })
    var observations = Array(repeating: ObservationSeries(), count: settings.stations.count)
    for line in try inputLines("observations.csv").dropFirst() { let fields = line.components(separatedBy: ","), index = stationIndices[fields[0]]!, hour = epochHours(epoch, fields[1]); observations[index].rows += 1; if fields[2] == "NA" { observations[index].missing.insert(hour) } else { observations[index].values[hour] = Double(fields[2])!; observations[index].milli[hour] = Int(fields[2].replacingOccurrences(of: ".", with: ""))! } }
    return Inputs(settings: settings, constituents: constituents, observations: observations)
}
