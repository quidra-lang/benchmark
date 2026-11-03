import Foundation

final class Station {
    let code: String
    let x: Int
    let y: Int
    let elevation: Int
    let order: Int
    let start: Int
    let samples: [Int]
    var mean = 0
    var noise = 0.0
    var peak = 0
    var clippedSamples = 0
    var triggers = 0
    var shortTriggers = 0
    var picks: [Pick] = []
    var timeCorrection = 0.0
    init(_ code: String, _ x: Int, _ y: Int, _ elevation: Int, _ order: Int, _ start: Int, _ samples: [Int]) {
        self.code = code; self.x = x; self.y = y; self.elevation = elevation; self.order = order; self.start = start; self.samples = samples
    }
}

struct GridRange {
    let low: Int
    let high: Int
    let step: Int
    var values: [Int] { Array(stride(from: low, through: high, by: step)) }
    init(_ values: [Int]) { low = values[0]; high = values[1]; step = values[2] }
}

struct Parameters {
    let staWindow: Int
    let ltaWindow: Int
    let triggerOn: [Int]
    let triggerOff: [Int]
    let minDuration: Int
    let noiseLevel: Int
    let amplitudeWindow: Int
    let clipLevel: Int
    let associationWindow: Int
    let minStations: Int
    let velocity: Double
    let gridX: GridRange
    let gridY: GridRange
    let gridZ: GridRange
    let residualLimit: Double
    let qualityA: [Double]
    let qualityB: [Double]
    let cluster: [Double]
    let localMagnitude: [Double]
    let durationMagnitude: [Double]
    let mapArea: [Int]
    let mapSize: [Int]
    let section: [Int]
    let timeline: [Int]
}

func readLines(_ path: String) throws -> [String] { try String(contentsOfFile: path, encoding: .ascii).split(separator: "\n").map(String.init) }

func loadInputs() throws -> (stations: [Station], params: Parameters) {
    let geometries = try readLines("input/stations.csv").dropFirst().map { $0.components(separatedBy: ",") }
    let lines = try readLines("input/waveforms.txt")
    var cursor = 0, stations: [Station] = []
    for (index, geometry) in geometries.enumerated() {
        let header = lines[cursor].components(separatedBy: " ")
        let count = Int(header[3])!
        cursor += 1
        var samples: [Int] = []
        while samples.count < count { samples += lines[cursor].components(separatedBy: " ").map { Int($0)! }; cursor += 1 }
        stations.append(Station(geometry[0], Int(geometry[1])!, Int(geometry[2])!, Int(geometry[3])!, index, Int(header[2])!, samples))
    }
    let settings = Dictionary(uniqueKeysWithValues: try readLines("input/params.txt").map { line in
        let fields = line.components(separatedBy: " ")
        return (fields[0], Array(fields.dropFirst()))
    })
    func ints(_ key: String) -> [Int] { settings[key]!.map { Int($0)! } }
    func reals(_ key: String) -> [Double] { settings[key]!.map { Double($0)! } }
    func integer(_ key: String) -> Int { Int(settings[key]![0])! }
    let params = Parameters(staWindow: integer("sta_window"), ltaWindow: integer("lta_window"), triggerOn: ints("trigger_on"), triggerOff: ints("trigger_off"),
                            minDuration: integer("min_duration"), noiseLevel: integer("noise_level"), amplitudeWindow: integer("amplitude_window"), clipLevel: integer("clip_level"),
                            associationWindow: integer("association_window"), minStations: integer("min_stations"), velocity: reals("velocity")[0],
                            gridX: GridRange(ints("grid_x")), gridY: GridRange(ints("grid_y")), gridZ: GridRange(ints("grid_z")), residualLimit: reals("residual_limit")[0],
                            qualityA: reals("quality_a"), qualityB: reals("quality_b"), cluster: reals("cluster"), localMagnitude: reals("local_magnitude"),
                            durationMagnitude: reals("duration_magnitude"), mapArea: ints("map_area"), mapSize: ints("map_size"), section: ints("section"), timeline: ints("timeline"))
    return (stations, params)
}
