import Foundation

struct Polygon {
    let number: Int
    let line: Int
    let group: String
    let vertices: [Int]
}

struct Face {
    let triangle: Int?
    let polygon: Int?
    let line: Int?
    let group: String
    var vertices: [Int]
}

struct OBJError {
    let line: Int
    let kind: String
}

struct OBJSource {
    let lineCount: Int
    let vertices: [Vector3]
    let polygons: [Polygon]
    let errors: [OBJError]
    let ignored: Int
}

func integerWord(_ word: String) -> Bool {
    let digits = word.hasPrefix("-") ? word.dropFirst() : word[...]
    return !digits.isEmpty && digits.allSatisfy { $0 >= "0" && $0 <= "9" }
}

func readLines(_ path: String) throws -> [String] {
    var lines = try String(contentsOfFile: path, encoding: .ascii).components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    return lines
}

func readOBJ() throws -> OBJSource {
    let lines = try readLines("input/model.obj")
    var vertices: [Vector3] = [.zero]
    var polygons: [Polygon] = []
    var errors: [OBJError] = []
    var ignored = 0
    var group = "default"
    for (index, line) in lines.enumerated() where !line.isEmpty && !line.hasPrefix("#") {
        let words = line.split(separator: " ").map(String.init)
        let arguments = Array(words.dropFirst())
        switch words[0] {
        case "v":
            if arguments.count != 3 || !arguments.allSatisfy(integerWord) {
                errors.append(OBJError(line: index + 1, kind: "bad_vertex"))
            } else { vertices.append(Vector3(x: Int(arguments[0])!, y: Int(arguments[1])!, z: Int(arguments[2])!)) }
        case "f":
            if arguments.count < 3 {
                errors.append(OBJError(line: index + 1, kind: "short_face"))
                continue
            }
            var resolved: [Int] = []
            var error: String?
            for argument in arguments {
                let part = String(argument.prefix(while: { $0 != "/" }))
                if !integerWord(part) || Int(part)! == 0 { error = "bad_index"; break }
                let value = Int(part)!
                let number = value > 0 ? value : vertices.count + value
                if number < 1 || number >= vertices.count { error = "out_of_range"; break }
                resolved.append(number)
            }
            if let error { errors.append(OBJError(line: index + 1, kind: error)) }
            else { polygons.append(Polygon(number: polygons.count + 1, line: index + 1, group: group, vertices: resolved)) }
        case "g": group = arguments.first ?? "default"
        case "vt", "vn", "s", "o", "usemtl", "mtllib": ignored += 1
        default: errors.append(OBJError(line: index + 1, kind: "unknown_keyword"))
        }
    }
    return OBJSource(lineCount: lines.count, vertices: vertices, polygons: polygons, errors: errors, ignored: ignored)
}

func repairedOBJ(_ points: [Vector3], _ faces: [Face]) -> [String] {
    var lines = ["# vertices \(points.count - 1) faces \(faces.count)"]
    lines += points.dropFirst().map { "v " + $0.text }
    var group: String?
    for face in faces {
        if group != face.group {
            lines.append("g " + face.group)
            group = face.group
        }
        lines.append("f " + face.vertices.map(String.init).joined(separator: " "))
    }
    return lines
}
