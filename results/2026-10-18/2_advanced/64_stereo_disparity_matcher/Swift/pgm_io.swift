import Foundation

enum CostKind: String { case sad, ssd, census }
struct Image { let width: Int; let height: Int; let pixels: [Int] }
struct Sample { let x: Int; let y: Int }
struct Settings {
    var disparityMin = 0
    var disparityMax = 0
    var windows: [[Int]] = [[], [], []]
    var textureWindow = 0
    var textureThreshold = 0
    var uniqueness = 0
    var lrMaximumDifference = 0
    var wtaCost = CostKind.sad
    var sgmCost = CostKind.sad
    var sgmWindow = 0
    var sgmPaths = 0
    var p1 = 0
    var p2 = 0
    var p2Gamma = 0
    var speckleSize = 0
    var speckleRange = 0
    var fusionVotes = 0
    var objectRange = 0
    var objectMinimumSize = 0
    var focalLength = 0
    var baseline = 0
    var samples: [Sample] = []
}
func readPGM(_ name: String) throws -> Image { let lines = try String(contentsOfFile: "input/" + name, encoding: .ascii).split(separator: "\n"), dimensions = lines[1].split(separator: " "); return Image(width: Int(dimensions[0])!, height: Int(dimensions[1])!, pixels: lines.dropFirst(3).flatMap { $0.split(separator: " ").map { Int($0)! } }) }
func readParameters() throws -> Settings {
    var settings = Settings()
    for line in try String(contentsOfFile: "input/params.txt", encoding: .ascii).split(separator: "\n") {
        let fields = line.split(separator: " ").map(String.init)
        switch fields[0] {
        case "disparity_min": settings.disparityMin = Int(fields[1])!
        case "disparity_max": settings.disparityMax = Int(fields[1])!
        case "sad_windows": settings.windows[0] = fields.dropFirst().map { Int($0)! }
        case "ssd_windows": settings.windows[1] = fields.dropFirst().map { Int($0)! }
        case "census_windows": settings.windows[2] = fields.dropFirst().map { Int($0)! }
        case "texture_window": settings.textureWindow = Int(fields[1])!
        case "texture_threshold": settings.textureThreshold = Int(fields[1])!
        case "uniqueness": settings.uniqueness = Int(fields[1])!
        case "lr_max_diff": settings.lrMaximumDifference = Int(fields[1])!
        case "wta_cost": settings.wtaCost = CostKind(rawValue: fields[1])!
        case "sgm_cost": settings.sgmCost = CostKind(rawValue: fields[1])!
        case "sgm_window": settings.sgmWindow = Int(fields[1])!
        case "sgm_paths": settings.sgmPaths = Int(fields[1])!
        case "p1": settings.p1 = Int(fields[1])!
        case "p2": settings.p2 = Int(fields[1])!
        case "p2_gamma": settings.p2Gamma = Int(fields[1])!
        case "speckle_size": settings.speckleSize = Int(fields[1])!
        case "speckle_range": settings.speckleRange = Int(fields[1])!
        case "fusion_min_votes": settings.fusionVotes = Int(fields[1])!
        case "object_range": settings.objectRange = Int(fields[1])!
        case "object_min_size": settings.objectMinimumSize = Int(fields[1])!
        case "focal_length": settings.focalLength = Int(fields[1])!
        case "baseline": settings.baseline = Int(fields[1])!
        case "sample": settings.samples.append(Sample(x: Int(fields[1])!, y: Int(fields[2])!))
        default: break
        }
    }
    return settings
}
func writePGM(_ name: String, _ width: Int, _ height: Int, _ pixels: [Int]) throws { let lines = ["P2", "\(width) \(height)", "255"] + (0..<height).map { row in pixels[(row * width)..<((row + 1) * width)].map(String.init).joined(separator: " ") }; try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) }
