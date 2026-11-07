import Foundation

struct Minstd {
    var state: Int64
    mutating func draw() -> Int64 {
        state = 48271 * state % 2147483647
        return state
    }
}

struct Condition {
    let attribute: Int
    var lower: Int64? = nil
    var upper: Int64? = nil
    var equal: Int64? = nil
    var excluded: Set<Int64> = []

    mutating func add(_ split: Split, _ left: Bool, _ attributes: [Attribute]) {
        if attributes[attribute].integer {
            if left { upper = min(upper ?? split.point, split.point) }
            else { lower = max(lower ?? split.point, split.point) }
        } else if left { equal = split.point }
        else { excluded.insert(split.point) }
    }

    func text(_ attributes: [Attribute]) -> String {
        let definition = attributes[attribute]
        if definition.integer {
            if let lower, let upper { return "\(halfText(lower)) < \(definition.name) <= \(halfText(upper))" }
            if let lower { return "\(definition.name) > \(halfText(lower))" }
            return "\(definition.name) <= \(halfText(upper!))"
        }
        if let equal { return "\(definition.name) = \(definition.values[Int(equal)])" }
        let names = excluded.sorted().map { definition.values[Int($0)] }
        if names.count == 1 { return "\(definition.name) != \(names[0])" }
        return "\(definition.name) not in {\(names.joined(separator: ","))}"
    }

    func holds(_ row: Row, _ attributes: [Attribute]) -> Bool {
        guard let value = row.values[attribute] else { return false }
        if attributes[attribute].integer {
            return (lower == nil || 2 * value > lower!) && (upper == nil || 2 * value <= upper!)
        }
        if let equal { return value == equal }
        return !excluded.contains(value)
    }
}

struct Rule {
    let number: Int
    let leaf: Int
    let conditions: [Condition]
    let general: [Condition]
    let removed: [Int]
}

struct DepthResult {
    let depth: Int
    let tree: PrunedTree
    let cvCorrect: Int64
}

struct Bag {
    let tree: PrunedTree
    let distinct: Int
    let outOfBag: Int
    let correct: Int64
}

func countsText(_ counts: [Int64]) -> String { counts.map(String.init).joined(separator: " ") }

func joinSections(_ sections: [[String]]) -> [String] {
    var lines: [String] = []
    for section in sections {
        if !lines.isEmpty { lines.append("") }
        lines += section
    }
    return lines
}

func conditionsText(_ conditions: [Condition], _ attributes: [Attribute]) -> String {
    conditions.isEmpty ? "true" : conditions.map { $0.text(attributes) }.joined(separator: " and ")
}

func coverage(_ conditions: [Condition], _ rows: [Row], _ label: Int, _ attributes: [Attribute]) -> (hits: Int64, covered: Int64) {
    var hits: Int64 = 0
    var covered: Int64 = 0
    for row in rows where conditions.allSatisfy({ $0.holds(row, attributes) }) {
        covered += 1
        if row.label == label { hits += 1 }
    }
    return (hits, covered)
}

func laplace(_ conditions: [Condition], _ rows: [Row], _ label: Int, _ attributes: [Attribute], _ classes: Int) -> Fraction {
    let value = coverage(conditions, rows, label, attributes)
    return Fraction(numerator: value.hits + 1, denominator: value.covered + Int64(classes))
}

func generalize(_ conditions: [Condition], _ rows: [Row], _ label: Int, _ attributes: [Attribute], _ classes: Int) -> (conditions: [Condition], removed: [Int]) {
    var current = conditions
    var removed: [Int] = []
    while !current.isEmpty {
        let estimate = laplace(current, rows, label, attributes, classes)
        var best: Fraction?
        var bestIndex = 0
        for index in current.indices {
            var trial = current
            trial.remove(at: index)
            let value = laplace(trial, rows, label, attributes, classes)
            if best == nil || value.compare(best!) > 0 {
                best = value
                bestIndex = index
            }
        }
        if estimate.compare(best!) > 0 { break }
        removed.append(current.remove(at: bestIndex).attribute)
    }
    return (current, removed)
}

final class Analysis {
    let data: Dataset
    let builder: TreeBuilder
    let grown: PrunedTree
    let pruned: PrunedTree
    let decisions: [Decision]
    var rules: [Rule] = []
    var bounds: [Int] = []
    var foldTrees: [PrunedTree] = []
    var depths: [DepthResult] = []
    var selectedDepth = 0
    var sequence: [SequenceTree] = []
    var selectedIndex = 0
    var bags: [Bag] = []
    var oobVotes: [[Int64]] = []
    var testVotes: [[Int64]] = []
    var predictions: [String: [Int]] = [:]

    init(_ data: Dataset) {
        self.data = data
        let builder = TreeBuilder(attributes: data.attributes, classes: data.classes.count, settings: data.settings)
        self.builder = builder
        let grown = PrunedTree(nodes: builder.grow(data.train))
        self.grown = grown
        let reduced = reducedErrorPruning(grown.nodes, data.validation, data.attributes)
        pruned = reduced.tree
        decisions = reduced.decisions
        collectRules(0, [])
        bounds = (0...data.settings.folds).map { $0 * data.train.count / data.settings.folds }
        for fold in 0..<data.settings.folds {
            let training = data.train.enumerated().filter { $0.offset < bounds[fold] || $0.offset >= bounds[fold + 1] }.map { $0.element }
            foldTrees.append(PrunedTree(nodes: builder.grow(training)))
        }
        for depth in 0...data.settings.maxDepth {
            var cvCorrect: Int64 = 0
            for (fold, tree) in foldTrees.enumerated() {
                cvCorrect += tree.limited(depth).correctCount(Array(data.train[bounds[fold]..<bounds[fold + 1]]), data.attributes)
            }
            depths.append(DepthResult(depth: depth, tree: grown.limited(depth), cvCorrect: cvCorrect))
            if cvCorrect > depths[selectedDepth].cvCorrect { selectedDepth = depth }
        }
        sequence = costComplexitySequence(grown.nodes)
        for index in sequence.indices {
            if validationErrors(sequence[index].tree) <= validationErrors(sequence[selectedIndex].tree) { selectedIndex = index }
        }
        bagging()
        let models = [("grown", grown), ("pruned", pruned), ("depth", depths[selectedDepth].tree), ("cost_complexity", sequence[selectedIndex].tree)]
        for (name, tree) in models { predictions[name] = data.test.map { tree.predict($0, data.attributes) } }
        predictions["bagging"] = testVotes.map { majority($0) }
    }

    func accuracy(_ tree: PrunedTree, _ rows: [Row]) -> String {
        ratioText(tree.correctCount(rows, data.attributes), Int64(rows.count))
    }

    func validationErrors(_ tree: PrunedTree) -> Int64 {
        Int64(data.validation.count) - tree.correctCount(data.validation, data.attributes)
    }

    func collectRules(_ index: Int, _ steps: [(split: Split, left: Bool)]) {
        if pruned.isLeaf(index) {
            var conditions: [Condition] = []
            for attribute in data.attributes.indices {
                let related = steps.filter { $0.split.attribute == attribute }
                if related.isEmpty { continue }
                var condition = Condition(attribute: attribute)
                for step in related { condition.add(step.split, step.left, data.attributes) }
                conditions.append(condition)
            }
            let label = pruned.nodes[index].prediction
            let generalized = generalize(conditions, data.validation, label, data.attributes, data.classes.count)
            rules.append(Rule(number: rules.count + 1, leaf: index, conditions: conditions,
                general: generalized.conditions, removed: generalized.removed))
            return
        }
        let node = pruned.nodes[index]
        collectRules(node.children!.left, steps + [(node.split!, true)])
        collectRules(node.children!.right, steps + [(node.split!, false)])
    }

    func bagging() {
        var generator = Minstd(state: data.settings.bagSeed)
        let size = data.train.count
        oobVotes = Array(repeating: Array(repeating: 0, count: data.classes.count), count: size)
        testVotes = Array(repeating: Array(repeating: 0, count: data.classes.count), count: data.test.count)
        for _ in 0..<data.settings.bagTrees {
            let indices = (0..<size).map { _ in Int(generator.draw() % Int64(size)) }
            let sample = indices.map { data.train[$0] }
            let tree = PrunedTree(nodes: builder.grow(sample))
            let sampled = Set(indices)
            var correct: Int64 = 0
            for index in 0..<size where !sampled.contains(index) {
                let row = data.train[index]
                let prediction = tree.predict(row, data.attributes)
                oobVotes[index][prediction] += 1
                if prediction == row.label { correct += 1 }
            }
            for (index, row) in data.test.enumerated() { testVotes[index][tree.predict(row, data.attributes)] += 1 }
            bags.append(Bag(tree: tree, distinct: sampled.count, outOfBag: size - sampled.count, correct: correct))
        }
    }

    func nodeLines(_ tree: PrunedTree, _ index: Int, _ condition: String, _ lines: inout [String]) {
        let node = tree.nodes[index]
        var line = "\(String(repeating: " ", count: 2 * node.depth))\(node.number) \(condition) n \(node.size) counts \(countsText(node.counts))"
        if tree.isLeaf(index) { line += " leaf \(data.classes[node.prediction])" }
        lines.append(line)
        if !tree.isLeaf(index) {
            let split = node.split!
            nodeLines(tree, node.children!.left, split.condition(true, data.attributes), &lines)
            nodeLines(tree, node.children!.right, split.condition(false, data.attributes), &lines)
        }
    }

    func treeLines(_ tree: PrunedTree) -> [String] {
        var lines: [String] = []
        nodeLines(tree, 0, "root", &lines)
        lines.append("")
        let nodes = tree.preorder()
        let leaves = tree.leaves()
        let depth = tree.depth
        lines.append("nodes \(nodes.count) leaves \(leaves.count) depth \(depth) errors \(ratioText(tree.trainingErrors, Int64(data.train.count)))")
        for level in 0...depth {
            let levelNodes = nodes.filter { tree.nodes[$0].depth == level }
            let levelLeaves = leaves.map { tree.nodes[$0] }.filter { $0.depth == level }
            let rows = levelLeaves.reduce(Int64(0)) { $0 + $1.size }
            let errors = levelLeaves.reduce(Int64(0)) { $0 + $1.errors }
            lines.append("level \(level) nodes \(levelNodes.count) leaves \(levelLeaves.count) rows \(rows) errors \(errors)")
        }
        return lines
    }

    func treeFile() -> [String] {
        let counts = grown.nodes[0].counts
        let size = Int64(data.train.count)
        var found = data.attributes.indices.compactMap { builder.bestSplit(data.train, [$0]) }
        found.sort {
            let order = $0.value.compare($1.value)
            return order == 0 ? $0.split.attribute < $1.split.attribute : order > 0
        }
        var rootLines = ["root candidates n \(size) counts \(countsText(counts))"]
        for (index, candidate) in found.enumerated() {
            let gain = candidate.value.real / Double(size) - Double(squareSum(counts)) / Double(size * size)
            rootLines.append("\(index + 1) \(candidate.split.condition(true, data.attributes)) left \(candidate.leftSize) right \(candidate.rightSize) gain \(realText(gain, 6))")
        }
        var surrogates = ["surrogates"]
        for index in grown.internalNodes() {
            let node = grown.nodes[index]
            let listed = node.surrogates.map {
                "\($0.split.condition(true, data.attributes)) \($0.forward ? "left" : "right") \($0.score)/\(node.size)"
            }
            let text = listed.isEmpty ? "none" : listed.joined(separator: " ; ")
            surrogates.append("node \(node.number) split \(node.split!.condition(true, data.attributes)) default \(node.defaultLeft ? "left" : "right") surrogates \(text)")
        }
        return joinSections([rootLines, treeLines(grown), surrogates])
    }

    func prunedTreeFile() -> [String] {
        var lines = ["reduced_error_pruning validation \(data.validation.count)"]
        for decision in decisions {
            let node = grown.nodes[decision.node]
            lines.append("node \(node.number) depth \(node.depth) rows \(decision.rows) leaf \(decision.leafError) subtree \(decision.subtreeError) \(decision.pruned ? "pruned" : "kept")")
        }
        let cutCount = decisions.filter(\.pruned).count
        lines.append("examined \(decisions.count) pruned \(cutCount) kept \(decisions.count - cutCount)")
        return joinSections([lines, treeLines(pruned)])
    }

    func predictionsFile() -> [String] {
        var lines = ["id,predicted,actual,grown,leaf,path,missing"]
        for row in data.test {
            let route = pruned.route(row, data.attributes)
            let leaf = pruned.nodes[route.path.last!]
            let path = route.path.map { String(pruned.nodes[$0].number) }.joined(separator: "-")
            let missing = route.methods.filter { $0 != .primary }.count
            lines.append("\(row.id),\(data.classes[leaf.prediction]),\(data.classes[row.label]),\(data.classes[grown.predict(row, data.attributes)]),\(leaf.number),\(path),\(missing)")
        }
        return lines
    }

    func rulesFile() -> [String] {
        var ordinary = ["rules \(rules.count)"]
        var generalized = ["generalized \(rules.count)"]
        for rule in rules {
            let leaf = pruned.nodes[rule.leaf]
            let reached = data.test.filter { pruned.leafOf($0, data.attributes) == rule.leaf }
            let hits = Int64(reached.filter { $0.label == leaf.prediction }.count)
            ordinary.append("rule \(rule.number) node \(leaf.number) if \(conditionsText(rule.conditions, data.attributes)) then \(data.classes[leaf.prediction]) train \(ratioText(leaf.counts[leaf.prediction], leaf.size)) test \(ratioText(hits, Int64(reached.count)))")
            let validation = coverage(rule.general, data.validation, leaf.prediction, data.attributes)
            let test = coverage(rule.general, data.test, leaf.prediction, data.attributes)
            let removed = rule.removed.isEmpty ? "none" : rule.removed.map { data.attributes[$0].name }.joined(separator: ",")
            let estimate = fractionText(validation.hits + 1, validation.covered + Int64(data.classes.count))
            generalized.append("general \(rule.number) if \(conditionsText(rule.general, data.attributes)) then \(data.classes[leaf.prediction]) removed \(removed) laplace \(estimate) validation \(validation.hits)/\(validation.covered) test \(test.hits)/\(test.covered)")
        }
        let wrong = data.test.filter { pruned.predict($0, data.attributes) != $0.label }
        var explanations = ["misclassified \(wrong.count)"]
        for row in wrong {
            let route = pruned.route(row, data.attributes)
            let leafIndex = route.path.last!
            let leaf = pruned.nodes[leafIndex]
            let rule = rules.first { $0.leaf == leafIndex }!
            var parts: [String] = []
            for index in route.methods.indices {
                let node = pruned.nodes[route.path[index]]
                let left = node.children!.left == route.path[index + 1]
                parts.append(node.split!.condition(left, data.attributes) + route.methods[index].mark)
            }
            let explanation = parts.isEmpty ? "root" : parts.joined(separator: "; ")
            explanations.append("\(row.id) actual \(data.classes[row.label]) predicted \(data.classes[leaf.prediction]) rule \(rule.number) path \(explanation)")
        }
        return joinSections([ordinary, generalized, explanations])
    }

    func dataLines() -> [String] {
        let train = classCounts(data.train, data.classes.count)
        let validation = classCounts(data.validation, data.classes.count)
        let test = classCounts(data.test, data.classes.count)
        var lines = ["data train \(data.train.count) validation \(data.validation.count) test \(data.test.count) attributes \(data.attributes.count) classes \(data.classes.count) target \(data.target)"]
        for index in data.classes.indices {
            lines.append("class \(data.classes[index]) train \(train[index]) validation \(validation[index]) test \(test[index])")
        }
        let validationMissing = data.validation.reduce(0) { $0 + $1.missingCount }
        let testMissing = data.test.reduce(0) { $0 + $1.missingCount }
        lines.append("missing validation \(validationMissing) test \(testMissing)")
        for (index, attribute) in data.attributes.enumerated() {
            let validationMissing = data.validation.filter { $0.values[index] == nil }.count
            let testMissing = data.test.filter { $0.values[index] == nil }.count
            lines.append("missing \(attribute.name) validation \(validationMissing) test \(testMissing)")
        }
        return lines
    }

    func summaryLine(_ name: String, _ tree: PrunedTree) -> String {
        "\(name) nodes \(tree.preorder().count) leaves \(tree.leaves().count) depth \(tree.depth) train \(accuracy(tree, data.train)) validation \(accuracy(tree, data.validation)) test \(accuracy(tree, data.test))"
    }

    func modelEvaluation(_ name: String) -> [String] {
        classificationLines("\(name) test", data.classes, data.test, predictions[name]!)
    }

    func routingLines() -> [String] {
        var tallies = Array(repeating: [0, 0, 0], count: pruned.nodes.count)
        for row in data.test {
            let route = pruned.route(row, data.attributes)
            for (index, method) in zip(route.path, route.methods) { tallies[index][method.rawValue] += 1 }
        }
        var lines = ["routing pruned test"]
        for index in pruned.internalNodes() {
            let counts = tallies[index]
            lines.append("node \(pruned.nodes[index].number) rows \(counts.reduce(0, +)) primary \(counts[0]) surrogate \(counts[1]) default \(counts[2])")
        }
        for (name, complete) in [("complete", true), ("incomplete", false)] {
            let rows = data.test.filter { ($0.missingCount == 0) == complete }
            lines.append("\(name) rows \(rows.count) correct \(accuracy(pruned, rows))")
        }
        return lines
    }

    func crossValidationLines() -> [String] {
        var lines = ["cross_validation folds \(data.settings.folds)"]
        var total: Int64 = 0
        for (fold, tree) in foldTrees.enumerated() {
            let rows = Array(data.train[bounds[fold]..<bounds[fold + 1]])
            let correct = tree.correctCount(rows, data.attributes)
            total += correct
            lines.append("fold \(fold + 1) rows \(bounds[fold] + 1)-\(bounds[fold + 1]) leaves \(tree.leaves().count) correct \(ratioText(correct, Int64(rows.count)))")
        }
        lines.append("cv accuracy \(ratioText(total, Int64(data.train.count)))")
        return lines
    }

    func depthLines() -> [String] {
        var lines = ["depth_selection"]
        for result in depths {
            let tree = result.tree
            lines.append("depth \(result.depth) leaves \(tree.leaves().count) cv \(ratioText(result.cvCorrect, Int64(data.train.count))) train \(accuracy(tree, data.train)) validation \(accuracy(tree, data.validation)) test \(accuracy(tree, data.test))")
        }
        let selected = depths[selectedDepth]
        lines.append("selected depth \(selected.depth) leaves \(selected.tree.leaves().count) test \(accuracy(selected.tree, data.test))")
        return lines
    }

    func costLines() -> [String] {
        var lines = ["cost_complexity"]
        for (index, step) in sequence.enumerated() {
            let alpha = fractionText(step.alpha.numerator, step.alpha.denominator * Int64(data.train.count), 6)
            lines.append("subtree \(index) alpha \(alpha) leaves \(step.tree.leaves().count) train_errors \(step.tree.trainingErrors) validation_errors \(validationErrors(step.tree))")
        }
        let tree = sequence[selectedIndex].tree
        lines.append("selected subtree \(selectedIndex) leaves \(tree.leaves().count) test \(accuracy(tree, data.test))")
        return lines
    }

    func baggingLines() -> [String] {
        var lines = ["bagging trees \(data.settings.bagTrees) seed \(data.settings.bagSeed)"]
        for (index, bag) in bags.enumerated() {
            lines.append("bag \(index + 1) distinct \(bag.distinct) leaves \(bag.tree.leaves().count) oob \(ratioText(bag.correct, Int64(bag.outOfBag)))")
        }
        var voted: Int64 = 0
        var hits: Int64 = 0
        for (row, votes) in zip(data.train, oobVotes) where votes.reduce(0, +) > 0 {
            voted += 1
            if majority(votes) == row.label { hits += 1 }
        }
        lines.append("oob accuracy \(ratioText(hits, voted)) unvoted \(Int64(data.train.count) - voted)")
        lines += modelEvaluation("bagging")
        return lines
    }

    func mcnemarLines() -> [String] {
        var lines = ["mcnemar pruned test"]
        for name in ["grown", "depth", "cost_complexity", "bagging"] {
            var firstOnly: Int64 = 0
            var secondOnly: Int64 = 0
            for (index, row) in data.test.enumerated() {
                let first = predictions["pruned"]![index] == row.label
                let second = predictions[name]![index] == row.label
                if first && !second { firstOnly += 1 }
                if second && !first { secondOnly += 1 }
            }
            let value = max(0, abs(firstOnly - secondOnly) - 1)
            let squared = value * value
            let disagreements = firstOnly + secondOnly
            let statistic = disagreements == 0 ? "0/1 0.0000" : fractionText(squared, disagreements)
            let significant = 1000 * squared > 3841 * disagreements ? "yes" : "no"
            lines.append("versus \(name) b \(firstOnly) c \(secondOnly) statistic \(statistic) significant \(significant)")
        }
        return lines
    }

    func scores(_ model: String) -> [[Fraction]] {
        if model == "bagging" {
            return testVotes.map { votes in votes.map { Fraction(numerator: $0, denominator: Int64(data.settings.bagTrees)) } }
        }
        let tree = model == "grown" ? grown : pruned
        return data.test.map { row in
            let leaf = tree.nodes[tree.leafOf(row, data.attributes)]
            return leaf.counts.map { Fraction(numerator: $0, denominator: leaf.size) }
        }
    }

    func aucLines() -> [String] {
        var lines: [String] = []
        for model in ["grown", "pruned", "bagging"] {
            let scores = self.scores(model)
            var parts = ["auc", model]
            var sum = 0.0
            var count = 0
            for (label, name) in data.classes.enumerated() {
                let positives = data.test.indices.filter { data.test[$0].label == label }.map { scores[$0][label] }
                let negatives = data.test.indices.filter { data.test[$0].label != label }.map { scores[$0][label] }
                var wins: Int64 = 0
                for first in positives {
                    for second in negatives {
                        let order = first.compare(second)
                        wins += order > 0 ? 2 : order == 0 ? 1 : 0
                    }
                }
                let pairs = 2 * Int64(positives.count) * Int64(negatives.count)
                parts += [name, fractionText(wins, pairs)]
                if pairs > 0 {
                    sum += Double(wins) / Double(pairs)
                    count += 1
                }
            }
            parts += ["macro", count == 0 ? "-" : realText(sum / Double(count))]
            lines.append(parts.joined(separator: " "))
        }
        return lines
    }

    func learningLines() -> [String] {
        var lines = ["learning_curve"]
        for size in data.settings.curve {
            let grown = PrunedTree(nodes: builder.grow(Array(data.train.prefix(size))))
            let pruned = reducedErrorPruning(grown.nodes, data.validation, data.attributes).tree
            lines.append("size \(size) grown leaves \(grown.leaves().count) test \(accuracy(grown, data.test)) pruned leaves \(pruned.leaves().count) test \(accuracy(pruned, data.test))")
        }
        return lines
    }

    func evaluationFile() -> [String] {
        joinSections([dataLines(), [summaryLine("grown", grown), summaryLine("pruned", pruned)],
            modelEvaluation("grown"), modelEvaluation("pruned"), routingLines(), crossValidationLines(),
            depthLines(), costLines(), baggingLines(), mcnemarLines(), aucLines(), learningLines()])
    }

    func impurityLines(_ title: String, _ tree: PrunedTree) -> [String] {
        var importance = Array(repeating: 0.0, count: data.attributes.count)
        var splits = Array(repeating: 0, count: data.attributes.count)
        for index in tree.internalNodes() {
            let node = tree.nodes[index]
            let attribute = node.split!.attribute
            let children = node.children!
            importance[attribute] += impurityDecrease(node.counts, tree.nodes[children.left].counts, tree.nodes[children.right].counts)
            splits[attribute] += 1
        }
        let total = importance.reduce(0, +)
        let shares = importance.map { total == 0 ? 0 : $0 / total }
        let order = data.attributes.indices.sorted {
            let first = (shares[$0] * 10000).rounded()
            let second = (shares[$1] * 10000).rounded()
            return first == second ? $0 < $1 : first > second
        }
        var lines = ["impurity \(title)"]
        for (rank, index) in order.enumerated() {
            lines.append("\(rank + 1) \(data.attributes[index].name) decrease \(realText(importance[index] / Double(data.train.count))) share \(realText(shares[index])) splits \(splits[index])")
        }
        return lines
    }

    func permutationLines() -> [String] {
        let settings = data.settings
        var generator = Minstd(state: settings.permutationSeed)
        let base = pruned.correctCount(data.test, data.attributes)
        var results: [(attribute: Int, counts: [Int64], drop: Int64)] = []
        for attribute in data.attributes.indices {
            var counts: [Int64] = []
            for _ in 0..<settings.repeats {
                var values = data.test.map { $0.values[attribute] }
                if values.count >= 2 {
                    for position in stride(from: values.count, through: 2, by: -1) {
                        let other = Int(generator.draw() % Int64(position))
                        values.swapAt(position - 1, other)
                    }
                }
                let rows = zip(data.test, values).map { row, value -> Row in
                    var changed = row
                    changed.values[attribute] = value
                    return changed
                }
                counts.append(pruned.correctCount(rows, data.attributes))
            }
            results.append((attribute, counts, Int64(settings.repeats) * base - counts.reduce(0, +)))
        }
        results.sort { $0.drop == $1.drop ? $0.attribute < $1.attribute : $0.drop > $1.drop }
        var lines = ["permutation pruned test repeats \(settings.repeats) seed \(settings.permutationSeed) base \(ratioText(base, Int64(data.test.count)))"]
        for (rank, result) in results.enumerated() {
            lines.append("\(rank + 1) \(data.attributes[result.attribute].name) correct \(countsText(result.counts)) drop \(fractionText(result.drop, Int64(settings.repeats * data.test.count)))")
        }
        return lines
    }

    func importanceFile() -> [String] {
        joinSections([impurityLines("grown", grown), impurityLines("pruned", pruned), permutationLines()])
    }
}

let analysis = Analysis(try loadDataset("input"))
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
for (name, lines) in [("tree.txt", analysis.treeFile()), ("pruned_tree.txt", analysis.prunedTreeFile()),
    ("predictions.csv", analysis.predictionsFile()), ("rules.txt", analysis.rulesFile()),
    ("evaluation.txt", analysis.evaluationFile()), ("importance.txt", analysis.importanceFile())] {
    try (lines.joined(separator: "\n") + "\n").write(toFile: "output/\(name)", atomically: true, encoding: .utf8)
}
