import Foundation

struct Rating {
    let user: Int
    let item: Int
    let rating: Int
    let timestamp: Int
}

struct Parameters {
    let neighbors: Int
    let shrinkage: Int
    let minSimilarity: Double
    let itemBiasRegularization: Double
    let userBiasRegularization: Double
    let factors: Int
    let learningRate: Double
    let regularization: Double
    let epochs: Int
    let alsRegularization: Double
    let alsIterations: Int
    let seed: Int64
    let topN: Int
    let cutoffs: [Int]
    let neighborGrid: [Int]
    let userGroups: [Int]
    let itemGroups: [Int]
    let timeBuckets: Int
    let listSize: Int
    let recommendUsers: [Int]
    let similarItems: [Int]
}

struct Ratings {
    let training: [Rating]
    let test: [Rating]
    let titles: [Int: String]
    let genreText: [Int: String]
    let genres: [Int: [String]]
    let params: Parameters
    let users: [Int]
    let items: [Int]
    let byUser: [Int: [Int: Int]]
    let byItem: [Int: [Int: Int]]
    let userItems: [Int: [Int]]
    let itemUsers: [Int: [Int]]
    let userCounts: [Int: Int]
    let itemCounts: [Int: Int]
    let userMeans: [Int: Double]
    let itemMeans: [Int: Double]
    let mean: Double

    init(_ training: [Rating], _ test: [Rating], _ titles: [Int: String], _ genreText: [Int: String], _ params: Parameters) {
        var byUser: [Int: [Int: Int]] = [:], byItem: [Int: [Int: Int]] = [:]
        for row in training { byUser[row.user, default: [:]][row.item] = row.rating; byItem[row.item, default: [:]][row.user] = row.rating }
        self.training = training
        self.test = test
        self.titles = titles
        self.genreText = genreText
        genres = genreText.mapValues { $0.components(separatedBy: "|") }
        self.params = params
        users = byUser.keys.sorted()
        items = byItem.keys.sorted()
        self.byUser = byUser
        self.byItem = byItem
        userItems = byUser.mapValues { $0.keys.sorted() }
        itemUsers = byItem.mapValues { $0.keys.sorted() }
        userCounts = byUser.mapValues { $0.count }
        itemCounts = byItem.mapValues { $0.count }
        userMeans = byUser.mapValues { Double($0.values.reduce(0, +)) / Double($0.count) }
        itemMeans = byItem.mapValues { Double($0.values.reduce(0, +)) / Double($0.count) }
        mean = Double(training.reduce(0) { $0 + $1.rating }) / Double(training.count)
    }
}

func readLines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .ascii).split(separator: "\n").map(String.init)
}

func readParameters() throws -> Parameters {
    let values = Dictionary(uniqueKeysWithValues: try readLines("input/params.txt").map { line in
        let fields = line.components(separatedBy: " ")
        return (fields[0], Array(fields.dropFirst()))
    })
    func integer(_ key: String) -> Int { Int(values[key]![0])! }
    func real(_ key: String) -> Double { Double(values[key]![0])! }
    func integers(_ key: String) -> [Int] { values[key]!.map { Int($0)! } }
    return Parameters(neighbors: integer("NEIGHBORS"), shrinkage: integer("SHRINKAGE"), minSimilarity: real("MIN_SIMILARITY"),
                      itemBiasRegularization: Double(values["BIAS_REG"]![0])!, userBiasRegularization: Double(values["BIAS_REG"]![1])!,
                      factors: integer("FACTORS"), learningRate: real("LEARNING_RATE"), regularization: real("REGULARIZATION"),
                      epochs: integer("EPOCHS"), alsRegularization: real("ALS_REG"), alsIterations: integer("ALS_ITERATIONS"),
                      seed: Int64(values["SEED"]![0])!, topN: integer("TOP_N"), cutoffs: integers("CUTOFFS"),
                      neighborGrid: integers("NEIGHBOR_GRID"), userGroups: integers("USER_GROUPS"), itemGroups: integers("ITEM_GROUPS"),
                      timeBuckets: integer("TIME_BUCKETS"), listSize: integer("LIST_SIZE"), recommendUsers: integers("RECOMMEND_USERS"), similarItems: integers("SIMILAR_ITEMS"))
}

func readRatings(_ path: String, training: Bool) throws -> [Rating] {
    try readLines(path).dropFirst().map { line in
        let fields = line.components(separatedBy: ",").map { Int($0)! }
        return Rating(user: fields[0], item: fields[1], rating: fields[2], timestamp: training ? fields[3] : 0)
    }
}

func readInputs() throws -> Ratings {
    var titles: [Int: String] = [:], genres: [Int: String] = [:]
    for line in try readLines("input/items.csv").dropFirst() {
        let fields = line.components(separatedBy: ","), id = Int(fields[0])!
        titles[id] = fields[1]
        genres[id] = fields[2]
    }
    return try Ratings(readRatings("input/ratings.csv", training: true), readRatings("input/test.csv", training: false), titles, genres, readParameters())
}
