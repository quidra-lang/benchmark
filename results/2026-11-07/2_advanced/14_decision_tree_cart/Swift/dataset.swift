import Foundation

struct Attribute {
    let name: String
    let integer: Bool
    let values: [String]
}

struct Row {
    let id: String
    var values: [Int64?]
    let label: Int
    var missingCount: Int { values.filter { $0 == nil }.count }
}

struct Settings {
    let maxDepth: Int
    let minSplit: Int
    let minLeaf: Int
    let maxSurrogates: Int
    let folds: Int
    let curve: [Int]
    let bagTrees: Int
    let bagSeed: Int64
    let repeats: Int
    let permutationSeed: Int64
}

struct Dataset {
    let attributes: [Attribute]
    let target: String
    let classes: [String]
    let train: [Row]
    let validation: [Row]
    let test: [Row]
    let settings: Settings
}

func readLines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map(String.init)
}

func readRows(_ path: String, _ attributes: [Attribute], _ classes: [String]) throws -> [Row] {
    try readLines(path).dropFirst().map { line in
        let fields = line.split(separator: ",").map(String.init)
        let values: [Int64?] = attributes.enumerated().map { index, attribute in
            let text = fields[index + 1]
            if text == "?" { return nil }
            return attribute.integer ? Int64(text)! : Int64(attribute.values.firstIndex(of: text)!)
        }
        return Row(id: fields[0], values: values, label: classes.firstIndex(of: fields.last!)!)
    }
}

func loadDataset(_ directory: String) throws -> Dataset {
    var attributes: [Attribute] = []
    var target = ""
    var classes: [String] = []
    for line in try readLines("\(directory)/schema.txt") {
        let fields = line.split(separator: " ").map(String.init)
        if fields[0] == "ATTRIBUTE" {
            attributes.append(Attribute(name: fields[1], integer: fields[2] == "INT", values: Array(fields.dropFirst(3))))
        } else {
            target = fields[1]
            classes = Array(fields.dropFirst(2))
        }
    }
    let parameters = try readLines("\(directory)/params.txt").map { line in
        line.split(separator: " ").dropFirst().map { Int64($0)! }
    }
    let settings = Settings(maxDepth: Int(parameters[0][0]), minSplit: Int(parameters[1][0]),
        minLeaf: Int(parameters[2][0]), maxSurrogates: Int(parameters[3][0]), folds: Int(parameters[4][0]),
        curve: parameters[5].map(Int.init), bagTrees: Int(parameters[6][0]), bagSeed: parameters[7][0],
        repeats: Int(parameters[8][0]), permutationSeed: parameters[9][0])
    return Dataset(attributes: attributes, target: target, classes: classes,
        train: try readRows("\(directory)/train.csv", attributes, classes),
        validation: try readRows("\(directory)/validation.csv", attributes, classes),
        test: try readRows("\(directory)/test.csv", attributes, classes), settings: settings)
}
