import Foundation

struct Point: Equatable {
    let id: Int
    let x: Int
    let y: Int
    var box: Box { Box(x1: x, y1: y, x2: x, y2: y) }
}

struct SpatialObject {
    let id: Int
    let box: Box
    let point: Point?
    init(_ point: Point) { id = point.id; box = point.box; self.point = point }
    init(_ id: Int, _ box: Box) { self.id = id; self.box = box; point = nil }
}

struct Parameters {
    let world: Int
    let bucket: Int
    let maximum: Int
    let minimum: Int
    let cellSize: Int
}

struct Command {
    let name: String
    let values: [Int]
}

struct Dataset {
    let points: [Point]
    let rectangles: [SpatialObject]
    let params: Parameters
    let commands: [Command]
}

func readLines(_ path: String) throws -> [String] { try String(contentsOfFile: path, encoding: .ascii).split(separator: "\n").map(String.init) }

func readDataset() throws -> Dataset {
    let points = try readLines("input/points.csv").dropFirst().map { line -> Point in
        let fields = line.components(separatedBy: ",").map { Int($0)! }
        return Point(id: fields[0], x: fields[1], y: fields[2])
    }
    let rectangles = try readLines("input/rects.csv").dropFirst().map { line -> SpatialObject in
        let fields = line.components(separatedBy: ",").map { Int($0)! }
        return SpatialObject(fields[0], Box(x1: fields[1], y1: fields[2], x2: fields[3], y2: fields[4]))
    }
    let settings = try readLines("input/params.txt").map { $0.components(separatedBy: " ").dropFirst().map { Int($0)! } }
    let params = Parameters(world: settings[0][0], bucket: settings[1][0], maximum: settings[2][0], minimum: settings[2][1], cellSize: settings[3][0])
    let commands = try readLines("input/queries.txt").map { line -> Command in
        let fields = line.components(separatedBy: " ")
        return Command(name: fields[0], values: fields.dropFirst().map { Int($0)! })
    }
    return Dataset(points: points, rectangles: rectangles, params: params, commands: commands)
}
