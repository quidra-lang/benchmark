import Foundation

typealias Image = [[Int]]
struct Pixel: Hashable, Comparable {
    let x: Int
    let y: Int
    static func < (a: Pixel, b: Pixel) -> Bool { a.y == b.y ? a.x < b.x : a.y < b.y }
    static func + (a: Pixel, b: Pixel) -> Pixel { Pixel(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Pixel, b: Pixel) -> Pixel { Pixel(x: a.x - b.x, y: a.y - b.y) }
    var text: String { "\(x) \(y)" }
}
struct TrigValue { let cosine: Int; let sine: Int }

struct Parameters {
    let gaussSize: Int
    let gaussKernel: [Int]
    let gaussDivisor: Int
    let cannyLow: Int
    let cannyHigh: Int
    let circleMinRadius: Int
    let circleMaxRadius: Int
    let circleMinPercent: Int
    let circleMaxCount: Int
    let houghRhoStep: Int
    let houghThreshold: Int
    let houghMaxLines: Int
    let segmentTolerance: Int
    let segmentMaxGap: Int
    let segmentMinLength: Int
    let junctionDistance: Int
    let junctionMinAngle: Int
    let angleTolerance: Int
    let squareTolerance: Int
    let contrastMargin: Int
    let harrisWindow: Int
    let harrisThreshold: Int
    let harrisMaxCount: Int
    let cornerMatchDistance: Int
    let overlayDivisor: Int
}

func readLines(_ path: String) throws -> [String] { try String(contentsOfFile: path, encoding: .ascii).split(separator: "\n").map(String.init) }
func readPGM() throws -> Image { try readLines("input/image.pgm").dropFirst(3).map { $0.components(separatedBy: " ").map { Int($0)! } } }
func readTrig() throws -> [TrigValue] {
    try readLines("input/trig.txt").map { line in let fields = line.components(separatedBy: " "); return TrigValue(cosine: Int(fields[1])!, sine: Int(fields[2])!) }
}

func readParameters() throws -> Parameters {
    let values = Dictionary(uniqueKeysWithValues: try readLines("input/params.txt").map { line in
        let fields = line.components(separatedBy: " ")
        return (fields[0], fields.dropFirst().map { Int($0)! })
    })
    func value(_ key: String) -> Int { values[key]![0] }
    return Parameters(gaussSize: value("gauss_size"), gaussKernel: values["gauss_kernel"]!, gaussDivisor: value("gauss_divisor"), cannyLow: value("canny_low"), cannyHigh: value("canny_high"),
                      circleMinRadius: value("circle_min_radius"), circleMaxRadius: value("circle_max_radius"), circleMinPercent: value("circle_min_percent"), circleMaxCount: value("circle_max_count"),
                      houghRhoStep: value("hough_rho_step"), houghThreshold: value("hough_threshold"), houghMaxLines: value("hough_max_lines"), segmentTolerance: value("segment_tolerance"),
                      segmentMaxGap: value("segment_max_gap"), segmentMinLength: value("segment_min_length"), junctionDistance: value("junction_distance"), junctionMinAngle: value("junction_min_angle"),
                      angleTolerance: value("angle_tolerance"), squareTolerance: value("square_tolerance"), contrastMargin: value("contrast_margin"), harrisWindow: value("harris_window"),
                      harrisThreshold: value("harris_threshold"), harrisMaxCount: value("harris_max_count"), cornerMatchDistance: value("corner_match_distance"), overlayDivisor: value("overlay_divisor"))
}

func writeLines(_ name: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) }
func writePGM(_ name: String, _ image: Image) throws { try writeLines(name, ["P2", "\(image[0].count) \(image.count)", "255"] + image.map { $0.map(String.init).joined(separator: " ") }) }
