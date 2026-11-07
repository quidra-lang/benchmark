import Foundation

let methods = ["GLOBAL", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS"]
let rankingMethods = ["POPULAR", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS"]
let knnMethods = ["USER_KNN", "ITEM_KNN"]

struct Prediction {
    let value: Double
    var fallback = false
    var neighbors = 0
    var similarity = 0.0
    var top: Int? = nil
}

struct ErrorMetrics {
    let rmse: Double
    let mae: Double
    let clipped: Int
    let fallback: Int
}

func separateSections(_ sections: [[String]]) -> [String] { sections.enumerated().flatMap { $0.offset == 0 ? $0.element : [""] + $0.element } }
func groupIndex(_ count: Int, _ boundaries: [Int]) -> Int { boundaries.filter { count >= $0 }.count }

func countSummary(_ counts: [Int]) -> String {
    let ordered = counts.sorted(), middle = counts.count / 2
    let median = counts.count % 2 == 1 ? Double(ordered[middle]) : Double(ordered[middle - 1] + ordered[middle]) / 2
    return "min \(ordered[0]) median \(real(median)) max \(ordered.last!)"
}

final class Recommender {
    let data: Ratings
    let neighborhood: Neighborhood
    var userBias: [Int: Double]
    var itemBias: [Int: Double]
    let popularity: [Int]
    let head: Int
    let popularItems: Set<Int>
    var log: [TrainingEntry] = []
    var trainErrors: [String: Double] = [:]
    var predictions: [String: [Prediction]] = Dictionary(uniqueKeysWithValues: methods.map { ($0, []) })
    var clipped: [String: [Double]] = Dictionary(uniqueKeysWithValues: methods.map { ($0, []) })
    var errors: [String: [Double]] = Dictionary(uniqueKeysWithValues: methods.map { ($0, []) })
    var metrics: [String: ErrorMetrics] = [:]
    var relevant: [Int: Set<Int>] = [:]
    var rankings: [Int: [String: [Int]]] = [:]
    var rankingPredictions: [Int: [String: [Int: Prediction]]] = [:]
    var svd: FactorModel?
    var als: FactorModel?
    var params: Parameters { data.params }
    var evaluatedUsers: [Int] { relevant.keys.sorted() }

    init(_ data: Ratings) {
        let popularity = data.items.sorted {
            if data.itemCounts[$0]! != data.itemCounts[$1]! { return data.itemCounts[$0]! > data.itemCounts[$1]! }
            if data.itemMeans[$0]! != data.itemMeans[$1]! { return data.itemMeans[$0]! > data.itemMeans[$1]! }
            return $0 < $1
        }
        self.data = data
        neighborhood = Neighborhood(data, data.params.shrinkage)
        userBias = Dictionary(uniqueKeysWithValues: data.users.map { ($0, 0) })
        itemBias = Dictionary(uniqueKeysWithValues: data.items.map { ($0, 0) })
        self.popularity = popularity
        head = data.items.count / 5
        popularItems = Set(popularity.prefix(data.items.count / 5))
    }

    func baseline(_ user: Int, _ item: Int) -> Double { (data.mean + userBias[user]!) + itemBias[item]! }

    func train() {
        trainErrors["GLOBAL"] = trainingRMSE(data.training) { _, _ in self.data.mean }
        for sweep in 1...10 {
            for i in data.items {
                let total = sequentialSum(data.itemUsers[i]!.map { Double(data.byItem[i]![$0]!) - data.mean - userBias[$0]! })
                itemBias[i] = total / (params.itemBiasRegularization + Double(data.itemCounts[i]!))
            }
            for u in data.users {
                let total = sequentialSum(data.userItems[u]!.map { Double(data.byUser[u]![$0]!) - data.mean - itemBias[$0]! })
                userBias[u] = total / (params.userBiasRegularization + Double(data.userCounts[u]!))
            }
            log.append(TrainingEntry(method: "BASELINE", epoch: sweep, error: trainingRMSE(data.training, baseline)))
        }
        trainErrors["BASELINE"] = log.last!.error
        let svdResult = trainSVD(data)
        svd = svdResult.model
        log += svdResult.log
        trainErrors["SVD"] = svdResult.log.last!.error
        let alsResult = trainALS(data, userBias, itemBias)
        als = alsResult.model
        log += alsResult.log
        trainErrors["ALS"] = alsResult.log.last!.error
    }

    func userPrediction(_ user: Int, _ item: Int, _ size: Int) -> Prediction {
        let candidates: [Neighbor] = data.itemUsers[item]!.compactMap { other in
            guard let similarity = neighborhood.userSimilarity(user, other), similarity.value > params.minSimilarity else { return nil }
            return (other, similarity.value)
        }
        let selected = largestNeighbors(candidates, size)
        if selected.isEmpty { return Prediction(value: baseline(user, item), fallback: true) }
        let numerator = sequentialSum(selected.map { $0.similarity * (Double(data.byItem[item]![$0.id]!) - data.userMeans[$0.id]!) })
        let denominator = sequentialSum(selected.map { $0.similarity })
        return Prediction(value: data.userMeans[user]! + numerator / denominator, neighbors: selected.count,
                          similarity: denominator / Double(selected.count), top: selected[0].id)
    }

    func itemPrediction(_ user: Int, _ item: Int, _ size: Int) -> Prediction {
        let candidates: [Neighbor] = data.userItems[user]!.compactMap { other in
            guard let similarity = neighborhood.itemSimilarity(item, other), similarity.value > params.minSimilarity else { return nil }
            return (other, similarity.value)
        }
        let selected = largestNeighbors(candidates, size)
        if selected.isEmpty { return Prediction(value: baseline(user, item), fallback: true) }
        let numerator = sequentialSum(selected.map { $0.similarity * (Double(data.byUser[user]![$0.id]!) - data.itemMeans[$0.id]!) })
        let denominator = sequentialSum(selected.map { $0.similarity })
        return Prediction(value: data.itemMeans[item]! + numerator / denominator, neighbors: selected.count,
                          similarity: denominator / Double(selected.count), top: selected[0].id)
    }

    func slopePrediction(_ user: Int, _ item: Int) -> Prediction {
        var numerator = 0.0, denominator = 0
        for other in data.userItems[user]! {
            let count = neighborhood.commonCount(item, other)
            if count > 0 {
                numerator = numerator + (neighborhood.deviation(item, other) + Double(data.byUser[user]![other]!)) * Double(count)
                denominator += count
            }
        }
        return denominator == 0 ? Prediction(value: baseline(user, item), fallback: true) : Prediction(value: numerator / Double(denominator))
    }

    func predict(_ method: String, _ user: Int, _ item: Int, size: Int? = nil) -> Prediction {
        let size = size ?? params.neighbors
        switch method {
        case "GLOBAL": return Prediction(value: data.mean)
        case "BASELINE": return Prediction(value: baseline(user, item))
        case "USER_KNN": return userPrediction(user, item, size)
        case "ITEM_KNN": return itemPrediction(user, item, size)
        case "SLOPE_ONE": return slopePrediction(user, item)
        case "SVD": return Prediction(value: svd!.predict(user, item))
        default: return Prediction(value: als!.predict(user, item))
        }
    }

    func predictTests() -> [String] {
        var lines = ["user,item,actual," + methods.joined(separator: ",")]
        for row in data.test {
            var fields = [String(row.user), String(row.item), String(row.rating)]
            for method in methods {
                let prediction = predict(method, row.user, row.item), clippedValue = clip(prediction.value)
                predictions[method]!.append(prediction)
                clipped[method]!.append(clippedValue)
                errors[method]!.append(clippedValue - Double(row.rating))
                fields.append(real(clippedValue))
            }
            lines.append(fields.joined(separator: ","))
        }
        for method in methods {
            let values = predictions[method]!
            metrics[method] = ErrorMetrics(rmse: rmse(errors[method]!)!, mae: mae(errors[method]!)!,
                                           clipped: values.filter { $0.value < 1 || $0.value > 5 }.count, fallback: values.filter { $0.fallback }.count)
        }
        return lines
    }

    func prepareRankings() {
        for row in data.test where row.rating >= 4 { relevant[row.user, default: []].insert(row.item) }
        let requested = Set(params.recommendUsers).intersection(data.users)
        for user in Set(relevant.keys).union(requested).sorted() {
            let rated = data.byUser[user]!
            let candidates = data.items.filter { rated[$0] == nil }
            var lists = ["POPULAR": popularity.filter { rated[$0] == nil }]
            var predictions: [String: [Int: Prediction]] = [:]
            for method in methods.dropFirst() {
                let values = Dictionary(uniqueKeysWithValues: candidates.map { ($0, predict(method, user, $0)) })
                predictions[method] = values
                lists[method] = candidates.sorted { values[$0]!.value == values[$1]!.value ? $0 < $1 : values[$0]!.value > values[$1]!.value }
            }
            rankings[user] = lists
            rankingPredictions[user] = predictions
        }
    }

    func dataSummary() -> [String] {
        var histogram = Array(repeating: 0, count: 5)
        for row in data.training { histogram[row.rating - 1] += 1 }
        let timestamps = data.training.map { $0.timestamp }
        let userUsable = neighborhood.user.values.filter { $0.value > params.minSimilarity }.count
        let itemUsable = neighborhood.item.values.filter { $0.value > params.minSimilarity }.count
        return ["data users \(data.users.count) items \(data.items.count) catalog \(data.titles.count) ratings \(data.training.count) test \(data.test.count)",
                "density \(real(Double(data.training.count) / Double(data.users.count * data.items.count))) global_mean \(real(data.mean))",
                "histogram " + histogram.map(String.init).joined(separator: " "),
                "user_ratings " + countSummary(Array(data.userCounts.values)), "item_ratings " + countSummary(Array(data.itemCounts.values)),
                "timestamps first \(timestamps.min()!) last \(timestamps.max()!)", "cold_items \(data.titles.count - data.items.count)",
                "similarities user_pairs \(neighborhood.user.count) usable \(userUsable) item_pairs \(neighborhood.item.count) usable \(itemUsable) slope_pairs \(neighborhood.counts.count)"]
    }

    func genreSummary() -> [String] {
        let genres = Set(data.items.flatMap { data.genres[$0]! }).sorted()
        var lines = ["genre_stats"]
        for genre in genres {
            let items = data.items.filter { data.genres[$0]!.contains(genre) }
            let ratings = items.reduce(0) { $0 + data.itemCounts[$1]! }
            let high = items.reduce(0) { $0 + data.byItem[$1]!.values.filter { $0 >= 4 }.count }
            lines.append("genre \(genre) items \(items.count) ratings \(ratings) high \(high)")
        }
        return lines
    }

    func timeSummary() -> [String] {
        let buckets = params.timeBuckets
        var counts = Array(repeating: 0, count: buckets), totals = counts
        var users = Array(repeating: Set<Int>(), count: buckets)
        let first = data.training.map { $0.timestamp }.min()!, last = data.training.map { $0.timestamp }.max()!
        for row in data.training {
            let bucket = (row.timestamp - first) * buckets / (last - first + 1)
            counts[bucket] += 1; totals[bucket] += row.rating; users[bucket].insert(row.user)
        }
        return ["time_buckets \(buckets)"] + (0..<buckets).map { b in
            "bucket \(b + 1) ratings \(counts[b]) users \(users[b].count) mean \(real(counts[b] > 0 ? Double(totals[b]) / Double(counts[b]) : nil))"
        }
    }

    func ratingMetrics() -> [String] {
        ["rating_metrics"] + methods.map { method in
            let value = metrics[method]!
            return "\(method) rmse \(real(value.rmse)) mae \(real(value.mae)) clipped \(value.clipped) fallback \(value.fallback)"
        }
    }

    func generalization() -> [String] {
        ["generalization"] + ["GLOBAL", "BASELINE", "SVD", "ALS"].map { method in
            let train = trainErrors[method]!, test = metrics[method]!.rmse
            return "\(method) train \(real(train)) test \(real(test)) gap \(real(test - train))"
        }
    }

    func neighborhoodUsage() -> [String] {
        ["neighborhoods k \(params.neighbors)"] + knnMethods.map { method in
            let used = predictions[method]!.filter { !$0.fallback }, count = used.count
            let meanCount = count > 0 ? Double(used.reduce(0) { $0 + $1.neighbors }) / Double(count) : nil
            let similarity = count > 0 ? sequentialSum(used.map { $0.similarity }) / Double(count) : nil
            return "\(method) predictions \(data.test.count) with_neighbors \(count) mean_neighbors \(real(meanCount)) mean_similarity \(real(similarity))"
        }
    }

    func predictionStatistics() -> [String] {
        let actual = data.test.map { Double($0.rating) }, count = Double(actual.count)
        let meanActual = Double(data.test.reduce(0) { $0 + $1.rating }) / count
        let variationActual = sequentialSum(actual.map { ($0 - meanActual) * ($0 - meanActual) })
        var lines = ["prediction_stats actual mean \(real(meanActual)) std \(real(sqrt(variationActual / count)))"]
        for method in methods {
            let values = clipped[method]!, mean = sequentialSum(values) / count
            let variation = sequentialSum(values.map { ($0 - mean) * ($0 - mean) })
            var correlation: Double?
            if values.min()! != values.max()! && actual.min()! != actual.max()! {
                let covariance = sequentialSum(values.indices.map { (values[$0] - mean) * (actual[$0] - meanActual) })
                correlation = covariance / sqrt(variation * variationActual)
            }
            lines.append("\(method) mean \(real(mean)) std \(real(sqrt(variation / count))) correlation \(real(correlation))")
        }
        return lines
    }

    func errorBins() -> [String] {
        ["error_bins edges 0.5 1.0 1.5 2.0"] + methods.map { method in
            var bins = Array(repeating: 0, count: 5)
            for error in errors[method]! { bins[[0.5, 1, 1.5, 2].filter { abs(error) >= $0 }.count] += 1 }
            return method + " " + bins.map(String.init).joined(separator: " ")
        }
    }

    func comparison() -> [String] {
        var lines = ["comparison"]
        for a in 0..<(methods.count - 1) {
            for b in (a + 1)..<methods.count {
                var wins = 0, ties = 0, losses = 0
                for (left, right) in zip(errors[methods[a]]!, errors[methods[b]]!) {
                    if abs(left) < abs(right) { wins += 1 } else if abs(left) == abs(right) { ties += 1 } else { losses += 1 }
                }
                lines.append("\(methods[a]) \(methods[b]) wins \(wins) ties \(ties) losses \(losses)")
            }
        }
        return lines
    }

    func errorsFor(_ indices: [Int], absolute: Bool = false) -> String {
        methods.map { method in
            let values = indices.map { errors[method]![$0] }
            return method + " " + real(absolute ? mae(values) : rmse(values))
        }.joined(separator: " ")
    }

    func groupErrors(_ userGroups: Bool) -> [String] {
        let kind = userGroups ? "user" : "item", bounds = userGroups ? params.userGroups : params.itemGroups
        let counts = userGroups ? data.userCounts : data.itemCounts
        var groups = Array(repeating: [Int](), count: bounds.count + 1)
        for (index, row) in data.test.enumerated() { groups[groupIndex(counts[userGroups ? row.user : row.item]!, bounds)].append(index) }
        var lines = [kind + "_groups bounds " + bounds.map(String.init).joined(separator: " ")]
        for (index, indices) in groups.enumerated() {
            let lower = index == 0 ? 1 : bounds[index - 1], upper = index < bounds.count ? bounds[index] - 1 : nil
            lines.append("group \(index + 1) from \(lower) to \(optional(upper)) pairs \(indices.count) " + errorsFor(indices))
        }
        return lines
    }

    func ratingErrors() -> [String] {
        ["by_rating"] + (1...5).map { rating in
            let indices = data.test.indices.filter { data.test[$0].rating == rating }
            return "rating \(rating) pairs \(indices.count) " + errorsFor(indices, absolute: true)
        }
    }

    func genreErrors() -> [String] {
        let genres = Set(data.test.flatMap { data.genres[$0.item]! }).sorted()
        return ["genres"] + genres.map { genre in
            let indices = data.test.indices.filter { data.genres[data.test[$0].item]!.contains(genre) }
            return "genre \(genre) pairs \(indices.count) " + errorsFor(indices)
        }
    }

    func userRankingMetrics(_ method: String, _ user: Int, _ cutoff: Int) -> RankingMetrics {
        rankingMetrics(rankings[user]![method]!, relevant[user]!, cutoff)
    }

    func rankingEvaluation() -> [String] {
        let users = evaluatedUsers, count = users.count
        let relevantCount = users.reduce(0) { $0 + relevant[$1]!.count }
        var lines = ["ranking users \(count) relevant \(relevantCount)"]
        for cutoff in params.cutoffs {
            lines.append("cutoff \(cutoff)")
            for method in rankingMethods {
                let values = users.map { userRankingMetrics(method, $0, cutoff) }
                let precision = Double(values.reduce(0) { $0 + $1.hits }) / Double(cutoff * count)
                let recall = sequentialSum(values.map { $0.recall }) / Double(count)
                let ndcg = sequentialSum(values.map { $0.ndcg }) / Double(count)
                let averagePrecision = sequentialSum(values.map { $0.averagePrecision }) / Double(count)
                let reciprocalRank = sequentialSum(values.map { $0.reciprocalRank }) / Double(count)
                let hitRate = Double(values.filter { $0.hits >= 1 }.count) / Double(count)
                lines.append("  \(method) precision \(real(precision)) recall \(real(recall)) ndcg \(real(ndcg)) map \(real(averagePrecision)) mrr \(real(reciprocalRank)) hit_rate \(real(hitRate))")
            }
        }
        return lines
    }

    func beyondAccuracy() -> [String] {
        let size = params.topN, users = evaluatedUsers, count = users.count, pairCount = size * (size - 1) / 2
        var lines = ["beyond_accuracy top_n \(size) head \(head)"]
        for method in rankingMethods {
            var distinct = Set<Int>()
            var diversity = 0, popularityTotal = 0, longTail = 0
            var novelty = 0.0, similarity = 0.0
            for user in users {
                let ranked = Array(rankings[user]![method]!.prefix(size))
                distinct.formUnion(ranked)
                diversity += Set(ranked.flatMap { data.genres[$0]! }).count
                novelty = novelty + sequentialSum(ranked.map { log2(Double(data.users.count) / Double(data.itemCounts[$0]!)) }) / Double(size)
                popularityTotal += ranked.reduce(0) { $0 + data.itemCounts[$1]! }
                longTail += ranked.filter { !popularItems.contains($0) }.count
                var pairSimilarity = 0.0
                for a in 0..<(size - 1) {
                    for b in (a + 1)..<size { pairSimilarity = pairSimilarity + (neighborhood.itemSimilarity(ranked[a], ranked[b])?.value ?? 0) }
                }
                similarity = similarity + pairSimilarity / Double(pairCount)
            }
            lines.append("\(method) coverage \(real(Double(distinct.count) / Double(data.items.count))) diversity \(real(Double(diversity) / Double(count))) novelty \(real(novelty / Double(count))) popularity \(real(Double(popularityTotal) / Double(size * count))) long_tail \(real(Double(longTail) / Double(size * count))) similarity \(real(similarity / Double(count)))")
        }
        return lines
    }

    func rankingGroups() -> [String] {
        let size = params.topN, bounds = params.userGroups
        var groups = Array(repeating: [Int](), count: bounds.count + 1)
        for user in evaluatedUsers { groups[groupIndex(data.userCounts[user]!, bounds)].append(user) }
        var lines = ["ranking_groups top_n \(size) bounds " + bounds.map(String.init).joined(separator: " ")]
        for (index, users) in groups.enumerated() {
            var fields = ["group \(index + 1) users \(users.count)"]
            for method in rankingMethods {
                let mean = users.isEmpty ? nil : sequentialSum(users.map { userRankingMetrics(method, $0, size).ndcg }) / Double(users.count)
                fields.append(method + " " + real(mean))
            }
            lines.append(fields.joined(separator: " "))
        }
        return lines
    }

    func agreement() -> [String] {
        let size = params.topN, users = evaluatedUsers
        var lines = ["agreement top_n \(size)"]
        for a in 0..<(rankingMethods.count - 1) {
            for b in (a + 1)..<rankingMethods.count {
                let total = sequentialSum(users.map { user -> Double in
                    let left = Set(rankings[user]![rankingMethods[a]]!.prefix(size)), right = Set(rankings[user]![rankingMethods[b]]!.prefix(size))
                    return Double(left.intersection(right).count) / Double(left.union(right).count)
                })
                lines.append("\(rankingMethods[a]) \(rankingMethods[b]) jaccard \(real(total / Double(users.count)))")
            }
        }
        return lines
    }

    func neighborGrid() -> [String] {
        var lines = ["neighbor_grid"]
        var errors: [String: [Int: Double]] = ["USER_KNN": [:], "ITEM_KNN": [:]]
        for size in params.neighborGrid {
            var fields = ["k \(size)"]
            for method in knnMethods {
                let residuals = data.test.map { clip(predict(method, $0.user, $0.item, size: size).value) - Double($0.rating) }
                let error = rmse(residuals)!
                errors[method]![size] = error
                fields.append(method + " " + real(error))
            }
            lines.append(fields.joined(separator: " "))
        }
        var fields = ["best"]
        for method in knnMethods {
            let best = params.neighborGrid.min { errors[method]![$0]! == errors[method]![$1]! ? $0 < $1 : errors[method]![$0]! < errors[method]![$1]! }!
            fields.append(method + " " + String(best))
        }
        lines.append(fields.joined(separator: " "))
        return lines
    }

    func biasLists() -> [String] {
        var lines = ["biases"]
        for kind in ["item", "user"] {
            let ids = kind == "item" ? data.items : data.users, biases = kind == "item" ? itemBias : userBias
            let counts = kind == "item" ? data.itemCounts : data.userCounts, means = kind == "item" ? data.itemMeans : data.userMeans
            for label in ["high", "low"] {
                let ordered = ids.sorted {
                    if biases[$0]! == biases[$1]! { return $0 < $1 }
                    return label == "high" ? biases[$0]! > biases[$1]! : biases[$0]! < biases[$1]!
                }
                for id in ordered.prefix(params.listSize) {
                    var line = "\(kind)_\(label) \(id) bias \(real(biases[id]!)) count \(counts[id]!) mean \(real(means[id]!))"
                    if kind == "item" { line += " " + data.titles[id]! }
                    lines.append(line)
                }
            }
        }
        return lines
    }

    func evaluationReport() -> [String] {
        separateSections([dataSummary(), genreSummary(), timeSummary(), ratingMetrics(), generalization(), neighborhoodUsage(),
                          predictionStatistics(), errorBins(), comparison(), groupErrors(true), groupErrors(false), ratingErrors(),
                          genreErrors(), rankingEvaluation(), beyondAccuracy(), rankingGroups(), agreement(), neighborGrid(), biasLists()])
    }

    func preferredGenres(_ user: Int, liked: Bool) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in data.userItems[user]! {
            let rating = data.byUser[user]![item]!
            if liked ? rating >= 4 : rating <= 2 {
                for genre in data.genres[item]! { counts[genre, default: 0] += 1 }
            }
        }
        let ordered = counts.keys.sorted { counts[$0]! == counts[$1]! ? $0 < $1 : counts[$0]! > counts[$1]! }
        return ordered.prefix(3).map { ($0, counts[$0]!) }
    }

    func popularityLine(_ rank: Int, _ item: Int) -> String {
        "  \(rank) \(item) count \(data.itemCounts[item]!) mean \(real(data.itemMeans[item]!)) \(data.titles[item]!)"
    }

    func recommendationLine(_ user: Int, _ method: String, _ rank: Int, _ item: Int) -> String {
        if method == "POPULAR" { return popularityLine(rank, item) }
        let prediction = rankingPredictions[user]![method]![item]!
        var line = "  \(rank) \(item) \(real(prediction.value))"
        if knnMethods.contains(method) { line += " via " + optional(prediction.top) }
        return line + " " + data.titles[item]!
    }

    func knownUserRecommendations(_ user: Int) -> [String] {
        var lines = ["user \(user) ratings \(data.userCounts[user]!) mean \(real(data.userMeans[user]!)) bias \(real(userBias[user]!))"]
        let liked = preferredGenres(user, liked: true), disliked = preferredGenres(user, liked: false)
        for (label, genres) in [("liked_genres", liked), ("disliked_genres", disliked)] {
            let entries = genres.map { "\($0.name) \($0.count)" }.joined(separator: " ")
            lines.append(label + " " + (entries.isEmpty ? "-" : entries))
        }
        let recent = data.training.filter { $0.user == user }.sorted { $0.timestamp == $1.timestamp ? $0.item < $1.item : $0.timestamp > $1.timestamp }
        lines.append("recent " + recent.prefix(3).map { "\($0.item) \($0.rating)" }.joined(separator: " "))
        let candidates: [Neighbor] = data.users.compactMap { other in
            guard let value = neighborhood.userSimilarity(user, other), value.value > params.minSimilarity else { return nil }
            return (other, value.value)
        }
        for neighbor in largestNeighbors(candidates, params.listSize) {
            lines.append("neighbor \(neighbor.id) similarity \(real(neighbor.similarity)) common \(neighborhood.userSimilarity(user, neighbor.id)!.common)")
        }
        for (index, row) in data.test.enumerated() where row.user == user {
            let values = methods.map { real(clipped[$0]![index]) }.joined(separator: " ")
            lines.append("heldout \(row.item) actual \(row.rating) \(values)")
        }
        let likedNames = Set(liked.map { $0.name })
        for method in rankingMethods {
            let ranked = Array(rankings[user]![method]!.prefix(params.topN))
            let matched = ranked.filter { data.genres[$0]!.contains { likedNames.contains($0) } }.count
            lines.append("list \(method) genre_match \(matched)")
            for (index, item) in ranked.enumerated() { lines.append(recommendationLine(user, method, index + 1, item)) }
        }
        return lines
    }

    func recommendations() -> [String] {
        separateSections(params.recommendUsers.map { user in
            if data.byUser[user] != nil { return knownUserRecommendations(user) }
            return ["user \(user) unknown", "list POPULAR"] + popularity.prefix(params.topN).enumerated().map { popularityLine($0.offset + 1, $0.element) }
        })
    }

    func similarItems() -> [String] {
        let factors = svd!.items
        let norms = Dictionary(uniqueKeysWithValues: data.items.map { ($0, dot(factors[$0]!, factors[$0]!)) })
        var sections: [[String]] = []
        for item in params.similarItems {
            var lines = ["item \(item) ratings \(data.itemCounts[item]!) mean \(real(data.itemMeans[item]!)) bias \(real(itemBias[item]!)) genres \(data.genreText[item]!) title \(data.titles[item]!)", "cosine"]
            let candidates: [Neighbor] = data.items.compactMap { other in
                neighborhood.itemSimilarity(item, other).map { (other, $0.value) }
            }
            for (index, neighbor) in largestNeighbors(candidates, params.listSize).enumerated() {
                let common = neighborhood.itemSimilarity(item, neighbor.id)!.common
                lines.append("  \(index + 1) \(neighbor.id) similarity \(real(neighbor.similarity)) common \(common) \(data.titles[neighbor.id]!)")
            }
            let factorCandidates: [Neighbor] = data.items.filter { $0 != item }.map { other in
                (other, dot(factors[item]!, factors[other]!) / sqrt(norms[item]! * norms[other]!))
            }
            lines.append("factors")
            for (index, neighbor) in largestNeighbors(factorCandidates, params.listSize).enumerated() {
                lines.append("  \(index + 1) \(neighbor.id) similarity \(real(neighbor.similarity)) \(data.titles[neighbor.id]!)")
            }
            let commonItems = data.items.filter { neighborhood.commonCount(item, $0) >= 1 }
            let ordered = commonItems.sorted { neighborhood.commonCount(item, $0) == neighborhood.commonCount(item, $1) ? $0 < $1 : neighborhood.commonCount(item, $0) > neighborhood.commonCount(item, $1) }
            lines.append("co_rated")
            for (index, other) in ordered.prefix(params.listSize).enumerated() {
                lines.append("  \(index + 1) \(other) common \(neighborhood.commonCount(item, other)) \(data.titles[other]!)")
            }
            let slopeOrdered = commonItems.sorted {
                let left = neighborhood.deviation($0, item), right = neighborhood.deviation($1, item)
                if left != right { return left > right }
                let leftCount = neighborhood.commonCount($0, item), rightCount = neighborhood.commonCount($1, item)
                return leftCount == rightCount ? $0 < $1 : leftCount > rightCount
            }
            lines.append("slope_one")
            for (index, other) in slopeOrdered.prefix(params.listSize).enumerated() {
                lines.append("  \(index + 1) \(other) difference \(neighborhood.difference(other, item)) common \(neighborhood.commonCount(other, item)) \(data.titles[other]!)")
            }
            sections.append(lines)
        }
        return separateSections(sections)
    }

    func trainingLog() -> [String] { ["method,epoch,train_rmse"] + log.map { "\($0.method),\($0.epoch),\(real($0.error))" } }
}

let recommender = try Recommender(readInputs())
recommender.train()
let predictionLines = recommender.predictTests()
recommender.prepareRankings()
try writeLines("predictions.csv", predictionLines)
try writeLines("evaluation.txt", recommender.evaluationReport())
try writeLines("recommendations.txt", recommender.recommendations())
try writeLines("similar_items.txt", recommender.similarItems())
try writeLines("training_log.csv", recommender.trainingLog())
