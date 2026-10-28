import Foundation

struct Subject {
    let id: Int
    let group: String
    let time: Int
    var event: Int
    let age: Int
    let sex: String
    let stage: Int

    func level(_ variable: String) -> String { variable == "sex" ? sex : String(stage) }
}

struct Parameters {
    let groups: [String]
    let reportTimes: [Int]
    let tau: Int
    let lifeWidth: Int
    let lifeCount: Int
    let strata: String
    let subgroups: [String]
    let landmark: Int
    let covariates: [String]
    let residuals: Int
    let plotWidth: Int
    let plotHeight: Int
    let plotTime: Int
    let plotDivisions: Int
}

func inputLines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .ascii).split(separator: "\n").map(String.init)
}

func readDataset() throws -> (subjects: [Subject], parameters: Parameters) {
    let subjects = try inputLines("input/subjects.csv").dropFirst().map { line -> Subject in
        let fields = line.components(separatedBy: ",")
        return Subject(id: Int(fields[0])!, group: fields[1], time: Int(fields[2])!, event: Int(fields[3])!,
                        age: Int(fields[4])!, sex: fields[5], stage: Int(fields[6])!)
    }.sorted { $0.id < $1.id }
    let settings = Dictionary(uniqueKeysWithValues: try inputLines("input/params.txt").map { line in
        let words = line.split(separator: " ").map(String.init)
        return (words[0], Array(words.dropFirst()))
    })
    let parameters = Parameters(groups: settings["GROUPS"]!, reportTimes: settings["REPORT_TIMES"]!.map { Int($0)! },
                                 tau: Int(settings["TAU"]![0])!, lifeWidth: Int(settings["LIFE_TABLE"]![0])!,
                                 lifeCount: Int(settings["LIFE_TABLE"]![1])!, strata: settings["STRATA"]![0],
                                 subgroups: settings["SUBGROUPS"]!, landmark: Int(settings["LANDMARK"]![0])!,
                                 covariates: settings["COX"]!, residuals: Int(settings["RESIDUALS"]![0])!,
                                 plotWidth: Int(settings["PLOT"]![0])!, plotHeight: Int(settings["PLOT"]![1])!,
                                 plotTime: Int(settings["PLOT"]![2])!, plotDivisions: Int(settings["PLOT"]![3])!)
    return (subjects, parameters)
}
