import Foundation

struct Candidate { let text: String; let alpha: Double }
struct Parameters {
    let iterations: Int
    let pseudocount: Double
    let candidates: [Candidate]
    let folds: Int
    let minimumSequence: Int
    let maximumMissing: Int
    let segmentState: Int
    let mergeGap: Int
    let minimumSegment: Int
    let firstMotif: Int
    let secondMotif: Int
    let richSymbols: Set<Int>
    let minimumRich: Int
    let minimumMotif: Int
    let confidence: Double
    let boundaryTolerance: Int
    let posteriorSeed: Int
    let posteriorSamples: Int
    let sampleSeed: Int
    let sampleCount: Int
    let sampleLength: Int
    init(_ rows: [[String]], _ model: Model) {
        let raw = Dictionary(uniqueKeysWithValues: rows.map { ($0[0], Array($0.dropFirst())) })
        func integer(_ key: String) -> Int { Int(raw[key]![0])! }
        func number(_ key: String) -> Double { Double(raw[key]![0])! }
        iterations = integer("iterations"); pseudocount = number("pseudocount"); candidates = raw["smoothing"]!.map { Candidate(text: $0, alpha: Double($0)!) }; folds = integer("folds")
        minimumSequence = integer("min_sequence_length"); maximumMissing = integer("max_missing_percent"); segmentState = model.states.firstIndex(of: raw["segment_state"]![0])!
        mergeGap = integer("merge_gap"); minimumSegment = integer("min_segment_length"); firstMotif = model.symbols.firstIndex(of: raw["motif"]![0])!; secondMotif = model.symbols.firstIndex(of: raw["motif"]![1])!
        richSymbols = Set(raw["rich_symbols"]!.map { model.symbols.firstIndex(of: $0)! }); minimumRich = integer("min_rich_percent"); minimumMotif = integer("min_motif_percent"); confidence = number("confidence"); boundaryTolerance = integer("boundary_tolerance")
        posteriorSeed = integer("posterior_seed"); posteriorSamples = integer("posterior_samples"); sampleSeed = integer("sample_seed"); sampleCount = integer("sample_count"); sampleLength = integer("sample_length")
    }
}
struct Record {
    let name: String
    let observations: [Int]
    let path: [Int]?
    var pair: LabeledPair { LabeledPair(observations: observations, path: path!) }
}
struct ValidatedInputs { let sequences: [Record]; let training: [Record]; let testing: [Record]; let rejections: [String] }
func rejectionReason(_ name: String, _ observations: [String], _ labels: [String]?, _ seen: inout Set<String>, _ model: Model, _ params: Parameters) -> String? {
    if !seen.insert(name).inserted { return "duplicate name" }
    for (i, symbol) in observations.enumerated() where !model.symbols.contains(symbol) && symbol != model.missing { return "invalid symbol \(symbol) at position \(i + 1)" }
    if let labels {
        for (i, label) in labels.enumerated() where !model.states.contains(label) { return "invalid label \(label) at position \(i + 1)" }
        if observations.count != labels.count { return "length mismatch \(observations.count) \(labels.count)" }
    }
    if observations.count < params.minimumSequence { return "too short \(observations.count)" }
    let missing = observations.filter { $0 == model.missing }.count
    if 100 * missing > params.maximumMissing * observations.count { return "too many missing \(missing)" }
    return nil
}
func validateInputs(_ raw: RawInputs, _ params: Parameters) -> ValidatedInputs {
    let model = raw.model
    var sequences: [Record] = [], training: [Record] = [], testing: [Record] = [], rejections: [String] = [], seen = Set<String>()
    func encode(_ characters: [String]) -> [Int] { characters.map { $0 == model.missing ? -1 : model.symbols.firstIndex(of: $0)! } }
    for (i, row) in raw.sequences.enumerated() {
        let name = row[0], observations = row[1].uppercased().map(String.init)
        if let reason = rejectionReason(name, observations, nil, &seen, model, params) { rejections.append("REJECT sequences.txt line \(i + 1) \(name) \(reason)"); continue }
        sequences.append(Record(name: name, observations: encode(observations), path: nil))
    }
    seen = []
    for offset in stride(from: 0, to: raw.labeled.count, by: 2) {
        let row = raw.labeled[offset], name = row[0], observations = row[2].uppercased().map(String.init), labels = raw.labeled[offset + 1][0].map(String.init)
        if let reason = rejectionReason(name, observations, labels, &seen, model, params) { rejections.append("REJECT labeled.txt line \(offset + 1) \(name) \(reason)"); continue }
        let record = Record(name: name, observations: encode(observations), path: labels.map { model.states.firstIndex(of: $0)! })
        if row[1] == "TRAIN" { training.append(record) } else { testing.append(record) }
    }
    return ValidatedInputs(sequences: sequences, training: training, testing: testing, rejections: rejections)
}
func maximumChange(_ previous: Model, _ current: Model) -> Double {
    let old = [previous.initial] + previous.transition + previous.emission, new = [current.initial] + current.transition + current.emission
    var difference = 0.0
    for row in old.indices { for col in old[row].indices { difference = max(difference, abs(old[row][col] - new[row][col])) } }
    return difference
}
struct BaumWelchTraining { let model: Model; let trace: [String]; let initialLogLikelihood: Double; let finalLogLikelihood: Double; let violations: Int; let bestHeldoutIteration: Int }
func trainBaumWelch(_ initial: Model, _ observations: [[Int]], _ heldout: [[Int]], _ params: Parameters) -> BaumWelchTraining {
    var current = initial, previous = totalLogLikelihood(initial, observations), bestHeldout = totalLogLikelihood(initial, heldout), bestIteration = 0, violations = 0
    let first = previous
    var trace = ["iteration,loglik,heldout,change,max_change,status", "0,\(real(previous)),\(real(bestHeldout)),,,"]
    for iteration in 1...params.iterations {
        let updated = baumWelchStep(current, observations, params.pseudocount), likelihood = totalLogLikelihood(updated, observations), heldoutLikelihood = totalLogLikelihood(updated, heldout), violation = likelihood < previous - 0.000001 * abs(previous)
        if violation { violations += 1 }
        if heldoutLikelihood > bestHeldout { bestHeldout = heldoutLikelihood; bestIteration = iteration }
        trace.append("\(iteration),\(real(likelihood)),\(real(heldoutLikelihood)),\(real(likelihood - previous)),\(real(maximumChange(current, updated), 6)),\(violation ? "violation" : "ok")")
        current = updated; previous = likelihood
    }
    return BaumWelchTraining(model: current, trace: trace, initialLogLikelihood: first, finalLogLikelihood: previous, violations: violations, bestHeldoutIteration: bestIteration)
}
func viterbiPaths(_ model: Model, _ observations: [[Int]]) -> (paths: [[Int]], logProbability: Double) {
    var paths: [[Int]] = [], total = 0.0
    for sequence in observations { let result = viterbi(model, sequence); paths.append(result.path); total += result.logProbability }
    return (paths, total)
}
struct ViterbiTraining { let model: Model; let trace: [String]; let iterations: Int; let converged: Bool }
func trainViterbi(_ initial: Model, _ observations: [[Int]], _ params: Parameters) -> ViterbiTraining {
    var current = initial, decoded = viterbiPaths(initial, observations), iterations = 0, changed = 0
    var trace = ["iteration,logprob,loglik,changed", "0,\(real(decoded.logProbability)),\(real(totalLogLikelihood(initial, observations))),"]
    for iteration in 1...params.iterations {
        let pairs = observations.indices.map { LabeledPair(observations: observations[$0], path: decoded.paths[$0]) }
        current = estimateByCounting(initial, pairs, params.pseudocount, "VITERBI_TRAINING")
        let next = viterbiPaths(current, observations)
        changed = observations.indices.reduce(0) { $0 + observations[$1].count - correctCount(decoded.paths[$1], next.paths[$1]) }; iterations = iteration
        trace.append("\(iteration),\(real(next.logProbability)),\(real(totalLogLikelihood(current, observations))),\(changed)")
        decoded = next
        if changed == 0 { break }
    }
    return ViterbiTraining(model: current, trace: trace, iterations: iterations, converged: changed == 0)
}
struct FoldResult { let records: Int; let positions: Int; let correct: Int }
struct CandidateResult { let candidate: Candidate; let correct: Int; let folds: [FoldResult]; let matrix: [[Int]] }
struct SupervisedTraining { let model: Model; let selected: Candidate; let lines: [String] }
func crossValidate(_ initial: Model, _ records: [Record], _ params: Parameters) -> SupervisedTraining {
    var results: [CandidateResult] = []
    for candidate in params.candidates {
        var matrix = confusionMatrix(initial.count), foldResults: [FoldResult] = [], total = 0
        for f in 0..<params.folds {
            let fitting = records.enumerated().filter { $0.offset % params.folds != f }.map { $0.element.pair }, validating = records.enumerated().filter { $0.offset % params.folds == f }.map { $0.element }
            let model = estimateByCounting(initial, fitting, candidate.alpha)
            var positions = 0, correct = 0
            for record in validating { let path = viterbi(model, record.observations).path; positions += path.count; correct += correctCount(record.path!, path); accumulateConfusion(&matrix, record.path!, path) }
            total += correct; foldResults.append(FoldResult(records: validating.count, positions: positions, correct: correct))
        }
        results.append(CandidateResult(candidate: candidate, correct: total, folds: foldResults, matrix: matrix))
    }
    let selected = results[maximumIndex(results.map { Double($0.correct) })], positions = records.reduce(0) { $0 + $1.observations.count }
    var lines = ["CROSS_VALIDATION folds \(params.folds)"] + results.map { "SMOOTHING \($0.candidate.text) positions \(positions) correct \($0.correct) accuracy \(fraction($0.correct, positions))" } + ["SELECTED \(selected.candidate.text)"]
    for (f, result) in selected.folds.enumerated() { lines.append("FOLD \(f + 1) records \(result.records) positions \(result.positions) correct \(result.correct) accuracy \(fraction(result.correct, result.positions))") }
    lines += matrixLines(initial.states, selected.matrix) + metricLines(initial.states, selected.matrix)
    return SupervisedTraining(model: estimateByCounting(initial, records.map { $0.pair }, selected.candidate.alpha), selected: selected.candidate, lines: lines)
}
func learningCurve(_ initial: Model, _ training: [Record], _ testing: [Record], _ alpha: Double) -> [String] {
    let positions = testing.reduce(0) { $0 + $1.observations.count }
    return ["LEARNING_CURVE"] + (1...training.count).map { count in
        let model = estimateByCounting(initial, training.prefix(count).map { $0.pair }, alpha), correct = testing.reduce(0) { $0 + correctCount($1.path!, viterbi(model, $1.observations).path) }
        return "RECORDS \(count) correct \(correct) accuracy \(fraction(correct, positions))"
    }
}
func extractSegments(_ path: [Int], _ params: Parameters) -> [Segment] {
    var segments: [Segment] = []
    for run in runs(path) where run.state == params.segmentState {
        if let previous = segments.last, run.segment.start - previous.end - 1 <= params.mergeGap { segments[segments.count - 1] = Segment(start: previous.start, end: run.segment.end) } else { segments.append(run.segment) }
    }
    return segments.filter { $0.length >= params.minimumSegment }
}
struct Composition { let richFraction: Double?; let pairRatio: Double?; let island: Bool }
func composition(_ observations: [Int], _ segment: Segment, _ params: Parameters) -> Composition {
    var observed = 0, rich = 0, first = 0, second = 0, pairs = 0
    for t in (segment.start - 1)..<segment.end {
        let symbol = observations[t]
        if symbol != -1 { observed += 1; if params.richSymbols.contains(symbol) { rich += 1 }; if symbol == params.firstMotif { first += 1 }; if symbol == params.secondMotif { second += 1 } }
        if t + 1 < segment.end && symbol == params.firstMotif && observations[t + 1] == params.secondMotif { pairs += 1 }
    }
    let denominator = first * second, island = denominator > 0 && 100 * rich >= params.minimumRich * observed && 100 * pairs * observed >= params.minimumMotif * first * second
    return Composition(richFraction: observed > 0 ? Double(rich) / Double(observed) : nil, pairRatio: denominator > 0 ? Double(pairs * observed) / Double(denominator) : nil, island: island)
}
struct EvaluationResult { let blocks: [[String]]; let correct: [Int] }
func evaluateModel(_ model: Model, _ records: [Record], _ params: Parameters) -> EvaluationResult {
    let decoded = records.map { decode(model, $0.observations) }
    var blocks: [[String]] = [], totals: [Int] = []
    for decoder in 0..<2 {
        var matrix = confusionMatrix(model.count), regions = MatchCounts(), boundaries = MatchCounts(), calibration = Array(repeating: [0, 0], count: 10), recordLines: [String] = [], total = 0
        for (i, record) in records.enumerated() {
            let result = decoded[i], path = decoder == 0 ? result.viterbi : result.posterior, truth = record.path!, correct = correctCount(truth, path)
            total += correct; accumulateConfusion(&matrix, truth, path)
            regions.add(regionCounts(extractSegments(path, params), runs(truth).filter { $0.state == params.segmentState }.map { $0.segment }))
            boundaries.add(boundaryCounts(path, truth, params.boundaryTolerance))
            if decoder == 1 { for t in path.indices { let bucket = min(9, Int(floor(10 * result.confidence[t]))); calibration[bucket][0] += 1; if path[t] == truth[t] { calibration[bucket][1] += 1 } } }
            recordLines.append("RECORD \(record.name) length \(path.count) correct \(correct)")
        }
        var lines = ["EVALUATION \(model.name) \(decoder == 0 ? "VITERBI" : "POSTERIOR")"] + matrixLines(model.states, matrix) + metricLines(model.states, matrix) + ["REGIONS \(model.states[params.segmentState]) \(regions.text)", "BOUNDARIES \(boundaries.text)"]
        if decoder == 1 { for b in 0..<10 where calibration[b][0] > 0 { let range = b == 9 ? "0.9-1.0" : "0.\(b)-0.\(b + 1)"; lines.append("CALIBRATION \(range) positions \(calibration[b][0]) correct \(calibration[b][1]) accuracy \(fraction(calibration[b][1], calibration[b][0]))") } }
        blocks.append(lines + recordLines); totals.append(total)
    }
    return EvaluationResult(blocks: blocks, correct: totals)
}

func stateString(_ model: Model, _ path: [Int]) -> String { path.map { model.states[$0] }.joined() }
func imputedString(_ model: Model, _ observations: [Int], _ posterior: [[Double]]) -> String {
    observations.enumerated().map { t, symbol in
        if symbol != -1 { return model.symbols[symbol] }
        let probabilities = model.symbols.indices.map { c in (0..<model.count).reduce(0) { $0 + posterior[t][$1] * model.emission[$1][c] } }
        return model.symbols[maximumIndex(probabilities)].lowercased()
    }.joined()
}
func segmentLine(_ record: Record, _ decoder: String, _ segment: Segment, _ result: Decoding, _ samples: [[Int]], _ params: Parameters) -> String {
    let positions = (segment.start - 1)..<segment.end, total = positions.reduce(0) { $0 + result.fb.posterior[$1][params.segmentState] }
    let support = samples.filter { path in 2 * positions.filter { path[$0] == params.segmentState }.count > segment.length }.count, measured = composition(record.observations, segment, params)
    return [record.name, decoder, String(segment.start), String(segment.end), String(segment.length), real(total / Double(segment.length)), String(support), real(measured.richFraction), real(measured.pairRatio), measured.island ? "yes" : "no"].joined(separator: ",")
}
func annotateSequences(_ model: Model, _ records: [Record], _ decoded: [Decoding], _ params: Parameters) -> (decodings: [String], segments: [String]) {
    var generator = MINSTD(state: params.posteriorSeed), decodingLines: [String] = [], segmentLines = ["sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island"]
    for (i, record) in records.enumerated() {
        let result = decoded[i], length = record.observations.count
        var samples: [[Int]] = [], sampleSegments = 0
        for _ in 0..<params.posteriorSamples { let path = posteriorPath(model, result.fb.forward, &generator); samples.append(path); sampleSegments += extractSegments(path, params).count }
        let confident = result.posterior.indices.map { result.confidence[$0] < params.confidence ? "." : model.states[result.posterior[$0]] }.joined()
        decodingLines += ["SEQUENCE \(record.name) length \(length) loglik \(real(result.fb.logLikelihood)) viterbi \(real(result.viterbiLogProbability)) differences \(length - correctCount(result.viterbi, result.posterior)) uncertain \(result.confidence.filter { $0 < params.confidence }.count) expected_segments \(real(Double(sampleSegments) / Double(params.posteriorSamples)))",
                          "VITERBI " + stateString(model, result.viterbi), "POSTERIOR " + stateString(model, result.posterior), "CONFIDENT " + confident, "IMPUTED " + imputedString(model, record.observations, result.fb.posterior)]
        for (decoder, path) in [("viterbi", result.viterbi), ("posterior", result.posterior)] { for segment in extractSegments(path, params) { segmentLines.append(segmentLine(record, decoder, segment, result, samples, params)) } }
    }
    return (decodingLines, segmentLines)
}
func syntheticOutput(_ model: Model, _ params: Parameters) -> [String] {
    var generator = MINSTD(state: params.sampleSeed), lines: [String] = [], positions = 0, viterbiTotal = 0, posteriorTotal = 0
    for number in 1...params.sampleCount {
        let sample = syntheticSequence(model, params.sampleLength, &generator), result = decode(model, sample.observations), viterbiCorrect = correctCount(sample.path, result.viterbi), posteriorCorrect = correctCount(sample.path, result.posterior)
        positions += sample.path.count; viterbiTotal += viterbiCorrect; posteriorTotal += posteriorCorrect
        lines += ["SAMPLE \(number) loglik \(real(result.fb.logLikelihood)) viterbi \(real(result.viterbiLogProbability)) viterbi_correct \(viterbiCorrect) posterior_correct \(posteriorCorrect)", "STATES " + stateString(model, sample.path), "SYMBOLS " + sample.observations.map { model.symbols[$0] }.joined(), "VITERBI " + stateString(model, result.viterbi), "POSTERIOR " + stateString(model, result.posterior)]
    }
    lines.append("TOTAL positions \(positions) viterbi_accuracy \(fraction(viterbiTotal, positions)) posterior_accuracy \(fraction(posteriorTotal, positions))")
    return lines
}
struct PathStatistics { let counts: [Int]; let runCounts: [Int]; let total: Int }
func pathStatistics(_ paths: [[Int]], _ count: Int) -> PathStatistics {
    var counts = Array(repeating: 0, count: count), runCounts = counts, total = 0
    for path in paths { total += path.count; for run in runs(path) { counts[run.state] += run.segment.length; runCounts[run.state] += 1 } }
    return PathStatistics(counts: counts, runCounts: runCounts, total: total)
}
func stationaryDistribution(_ model: Model) -> [Double] {
    let count = model.count
    var matrix = (0..<(count - 1)).map { equation in (0..<count).map { model.transition[$0][equation] - ($0 == equation ? 1.0 : 0.0) } + [0] }
    matrix.append(Array(repeating: 1, count: count + 1))
    for column in 0..<count {
        var pivot = column
        for row in (column + 1)..<count { if abs(matrix[row][column]) > abs(matrix[pivot][column]) { pivot = row } }
        matrix.swapAt(column, pivot)
        let divisor = matrix[column][column]
        for j in column...count { matrix[column][j] /= divisor }
        for row in 0..<count where row != column {
            let factor = matrix[row][column]
            for j in column...count { let value = matrix[column][j]; matrix[row][j] -= factor * value }
        }
    }
    return (0..<count).map { matrix[$0][count] }
}
func stateAlignment(_ model: Model, _ records: [Record]) -> String {
    var matrix = confusionMatrix(model.count), positions = 0
    for record in records { let path = viterbi(model, record.observations).path; accumulateConfusion(&matrix, record.path!, path); positions += path.count }
    var best: [Int] = [], bestCorrect = -1
    func visit(_ permutation: [Int], _ remaining: [Int]) {
        if remaining.isEmpty { let correct = permutation.enumerated().reduce(0) { $0 + matrix[$1.element][$1.offset] }; if correct > bestCorrect { bestCorrect = correct; best = permutation }; return }
        for next in remaining { visit(permutation + [next], remaining.filter { $0 != next }) }
    }
    visit([], Array(0..<model.count))
    return "ALIGNMENT " + best.enumerated().map { model.states[$0.offset] + "=" + model.states[$0.element] }.joined(separator: " ") + " agreement " + fraction(bestCorrect, positions)
}
func modelDiagnostics(_ model: Model, _ records: [Record], _ decoded: [Decoding], _ training: [Record], _ testing: [Record], _ params: Parameters) -> [String] {
    var likelihood = 0.0, observed = 0, segmentCount = 0, segmentLength = 0, islands = 0
    for (i, record) in records.enumerated() {
        let result = decoded[i]
        likelihood += result.fb.logLikelihood; observed += record.observations.filter { $0 != -1 }.count
        for segment in extractSegments(result.viterbi, params) { segmentCount += 1; segmentLength += segment.length; if composition(record.observations, segment, params).island { islands += 1 } }
    }
    let statistics = pathStatistics(decoded.map { $0.viterbi }, model.count), stationary = stationaryDistribution(model), testLikelihood = totalLogLikelihood(model, testing.map { $0.observations }), meanLength: Double? = segmentCount > 0 ? Double(segmentLength) / Double(segmentCount) : nil
    var lines = ["MODEL " + model.name, "LOGLIK unlabeled \(real(likelihood)) per_symbol \(real(likelihood / Double(observed))) test \(real(testLikelihood))", "SEGMENTS count \(segmentCount) mean_length \(real(meanLength)) islands \(islands)", stateAlignment(model, training)]
    for i in 0..<model.count {
        let meanRun: Double? = statistics.runCounts[i] > 0 ? Double(statistics.counts[i]) / Double(statistics.runCounts[i]) : nil
        lines.append("STATE \(model.states[i]) stationary \(real(stationary[i])) duration \(real(1 / (1 - model.transition[i][i]))) occupancy \(real(Double(statistics.counts[i]) / Double(statistics.total))) mean_run \(real(meanRun))")
    }
    return lines
}
func inputReport(_ raw: RawInputs, _ inputs: ValidatedInputs) -> [String] {
    let model = raw.model, sequences = inputs.sequences, labeled = inputs.training + inputs.testing
    let positions = sequences.reduce(0) { $0 + $1.observations.count }, missing = sequences.reduce(0) { $0 + $1.observations.filter { $0 == -1 }.count }, labeledPositions = labeled.reduce(0) { $0 + $1.observations.count }, labeledMissing = labeled.reduce(0) { $0 + $1.observations.filter { $0 == -1 }.count }
    var lines = ["INPUT", "SEQUENCES accepted \(sequences.count) rejected \(raw.sequences.count - sequences.count) positions \(positions) missing \(missing)", "LABELED train \(inputs.training.count) test \(inputs.testing.count) rejected \(raw.labeled.count / 2 - labeled.count) positions \(labeledPositions) missing \(labeledMissing)"] + inputs.rejections
    var symbols = Array(repeating: 0, count: model.symbols.count)
    for record in sequences { for symbol in record.observations where symbol != -1 { symbols[symbol] += 1 } }
    lines.append("COMPOSITION " + model.symbols.indices.map { "\(model.symbols[$0]) \(real(Double(symbols[$0]) / Double(positions - missing)))" }.joined(separator: " "))
    for (role, records) in [("TRAIN", inputs.training), ("TEST", inputs.testing)] {
        let statistics = pathStatistics(records.map { $0.path! }, model.count)
        for i in 0..<model.count {
            let meanRun: Double? = statistics.runCounts[i] > 0 ? Double(statistics.counts[i]) / Double(statistics.runCounts[i]) : nil
            lines.append("TRUTH \(role) \(model.states[i]) occupancy \(real(Double(statistics.counts[i]) / Double(statistics.total))) mean_run \(real(meanRun))")
        }
    }
    return lines
}
func trainingReport(_ models: [Model], _ baum: BaumWelchTraining, _ hard: ViterbiTraining, _ supervised: SupervisedTraining, _ decoded: [[Decoding]], _ evaluations: [EvaluationResult], _ testPositions: Int, _ params: Parameters) -> [String] {
    var lines = ["TRAINING BAUM_WELCH iterations \(params.iterations) initial_loglik \(real(baum.initialLogLikelihood)) final_loglik \(real(baum.finalLogLikelihood)) violations \(baum.violations) best_heldout_iteration \(baum.bestHeldoutIteration)", "TRAINING VITERBI_TRAINING iterations \(hard.iterations) converged \(hard.converged ? "yes" : "no")", "TRAINING SUPERVISED smoothing \(supervised.selected.text)"]
    var preferences = Array(repeating: 0, count: models.count)
    for sequence in decoded[0].indices { let likelihoods = decoded.map { $0[sequence].fb.logLikelihood }; preferences[maximumIndex(likelihoods)] += 1 }
    lines.append("PREFERENCE " + models.indices.map { "\(models[$0].name) \(preferences[$0])" }.joined(separator: " "))
    let positions = decoded[0].reduce(0) { $0 + $1.viterbi.count }
    for first in models.indices { for second in (first + 1)..<models.count { let correct = decoded[first].indices.reduce(0) { $0 + correctCount(decoded[first][$1].viterbi, decoded[second][$1].viterbi) }; lines.append("AGREEMENT \(models[first].name) \(models[second].name) \(fraction(correct, positions))") } }
    for (decoder, name) in ["VITERBI", "POSTERIOR"].enumerated() { let best = maximumIndex(evaluations.map { Double($0.correct[decoder]) }); lines.append("BEST \(name) \(models[best].name) accuracy \(fraction(evaluations[best].correct[decoder], testPositions))") }
    return lines
}
func joinBlocks(_ blocks: [[String]]) -> [String] { var lines: [String] = []; for (i, block) in blocks.enumerated() { if i > 0 { lines.append("") }; lines += block }; return lines }

let raw = try readInputs()
let initial = raw.model, params = Parameters(raw.parameters, raw.model)
let inputs = validateInputs(raw, params), observations = inputs.sequences.map { $0.observations }, heldout = (inputs.training + inputs.testing).map { $0.observations }
let baum = trainBaumWelch(initial, observations, heldout, params), hard = trainViterbi(initial, observations, params), supervised = crossValidate(initial, inputs.training, params)
let models = [initial, baum.model, hard.model, supervised.model]
let evaluations = models.map { evaluateModel($0, inputs.testing, params) }, decoded = models.map { model in inputs.sequences.map { decode(model, $0.observations) } }
let annotated = annotateSequences(baum.model, inputs.sequences, decoded[1], params)
let testPositions = inputs.testing.reduce(0) { $0 + $1.observations.count }
let evaluationBlocks = evaluations.flatMap { $0.blocks } + [supervised.lines, learningCurve(initial, inputs.training, inputs.testing, supervised.selected.alpha)]
var reportBlocks = [inputReport(raw, inputs), trainingReport(models, baum, hard, supervised, decoded, evaluations, testPositions, params)]
for i in models.indices { reportBlocks.append(modelDiagnostics(models[i], inputs.sequences, decoded[i], inputs.training, inputs.testing, params)) }
for (name, lines) in [("trained_model.txt", joinBlocks(models.dropFirst().map { modelLines($0) })), ("loglik_trace.csv", baum.trace), ("viterbi_trace.csv", hard.trace), ("decodings.txt", annotated.decodings), ("segments.csv", annotated.segments), ("samples.txt", syntheticOutput(baum.model, params)), ("evaluation.txt", joinBlocks(evaluationBlocks)), ("report.txt", joinBlocks(reportBlocks))] { try writeLines(name, lines) }
