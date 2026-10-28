import Foundation

struct ReferenceText {
    let references: [Reference]
    let offsets: [Int]
    let sequence: [UInt8]
    let reverse: [UInt8]
    init(_ references: [Reference]) { var offsets: [Int] = [], sequence: [UInt8] = []; for (index, reference) in references.enumerated() { if index > 0 { sequence.append(35) }; offsets.append(sequence.count); sequence += reference.bases }; let reverse = Array(sequence.reversed()) + [UInt8(36)]; sequence.append(36); self.references = references; self.offsets = offsets; self.sequence = sequence; self.reverse = reverse }
    func position(_ position: Int) -> (reference: Int, offset: Int)? { var low = 0, high = offsets.count; while low < high { let middle = (low + high) / 2; if offsets[middle] <= position { low = middle + 1 } else { high = middle } }; let reference = low - 1, offset = position - offsets[reference]; return offset < references[reference].bases.count ? (reference, offset) : nil }
    func label(_ position: Int) -> String { guard let value = self.position(position) else { return "*" }; return references[value.reference].name + ":" + String(value.offset + 1) }
}
struct OperationRun { let operation: UInt8; var count: Int }
func runs(_ operations: [UInt8]) -> [OperationRun] { var result: [OperationRun] = []; for operation in operations { if result.last?.operation == operation { result[result.count - 1].count += 1 } else { result.append(OperationRun(operation: operation, count: 1)) } }; return result }
struct AlignedPair { let read: Int; let reference: Int }
struct Alignment { let reference: Int; let position: Int; let strand: Int; let operations: [UInt8]; let oriented: [UInt8]; let pairs: [AlignedPair]; let cigar: String; let nm: Int; let md: String }
struct MappingResult {
    let read: Read
    let core: [UInt8]
    let qualities: [Int]
    let length: Int
    let trimmed: Int
    var reason = "SHORT"
    var primary: Alignment?
    var others: [Alignment] = []
    var method = ""
    var score = 0
    var mapq = 0
    var x0 = 0
    var x1 = 0
    var targets: [Int] = []
}
func describe(_ reference: Int, _ position: Int, _ strand: Int, _ operations: [UInt8], _ result: MappingResult, _ references: [Reference]) -> Alignment {
    let oriented = strand == 0 ? result.core : reverseComplement(result.core), sequence = references[reference].bases
    var cigar: [String] = [], md: [String] = [], pairs: [AlignedPair] = [], readOffset = 0, referenceOffset = position, matches = 0, nm = 0
    for run in runs(operations) { cigar.append("\(run.count)\(String(UnicodeScalar(run.operation)))"); switch run.operation { case 73: readOffset += run.count; nm += run.count; case 68: md.append("\(matches)^" + text(Array(sequence[referenceOffset..<(referenceOffset + run.count)]))); matches = 0; referenceOffset += run.count; nm += run.count; default: for _ in 0..<run.count { pairs.append(AlignedPair(read: readOffset, reference: referenceOffset)); if oriented[readOffset] == sequence[referenceOffset] { matches += 1 } else { md.append("\(matches)\(String(UnicodeScalar(sequence[referenceOffset])))"); matches = 0; nm += 1 }; readOffset += 1; referenceOffset += 1 } } }
    md.append(String(matches))
    if result.trimmed > 0 { if strand == 0 { cigar.append("\(result.trimmed)S") } else { cigar.insert("\(result.trimmed)S", at: 0) } }
    return Alignment(reference: reference, position: position, strand: strand, operations: operations, oriented: oriented, pairs: pairs, cigar: cigar.joined(), nm: nm, md: md.joined())
}
struct Cell: Hashable { let row: Int; let column: Int; init(_ row: Int, _ column: Int) { self.row = row; self.column = column } }
struct BandAlignment { let score: Int; let position: Int; let operations: [UInt8] }
func subtract(_ value: Int?, _ penalty: Int) -> Int? { value.map { $0 - penalty } }
func reachableMaximum(_ values: Int?...) -> Int? { values.compactMap { $0 }.max() }
func bandedAlignment(_ oriented: [UInt8], _ sequence: [UInt8], _ center: Int, _ settings: Settings) -> BandAlignment? {
    let length = oriented.count, size = sequence.count, width = settings.bandWidth, gapOpen = settings.gapOpen, gapExtend = settings.gapExtend
    var h: [Cell: Int] = [:], e: [Cell: Int] = [:], f: [Cell: Int] = [:]
    let first = max(0, center - width), last = min(size, center + width)
    if first <= last { for column in first...last { h[Cell(0, column)] = 0 } }
    for row in 1...length { let first = max(0, row + center - width), last = min(size, row + center + width); if first > last { continue }; for column in first...last { let cell = Cell(row, column); f[cell] = reachableMaximum(subtract(h[Cell(row - 1, column)], gapOpen + gapExtend), subtract(f[Cell(row - 1, column)], gapExtend)); var diagonal: Int?; if column >= 1 { e[cell] = reachableMaximum(subtract(h[Cell(row, column - 1)], gapOpen + gapExtend), subtract(e[Cell(row, column - 1)], gapExtend)); diagonal = h[Cell(row - 1, column - 1)].map { $0 + (oriented[row - 1] == sequence[column - 1] ? settings.match : -settings.mismatch) } }; h[cell] = reachableMaximum(diagonal, e[cell], f[cell]) } }
    let endpoints = h.filter { $0.key.row == length }.sorted { $0.value == $1.value ? $0.key.column < $1.key.column : $0.value > $1.value }
    guard let endpoint = endpoints.first else { return nil }
    let score = endpoint.value
    var row = length, column = endpoint.key.column, state: UInt8 = 72, backward: [UInt8] = []
    while true { let cell = Cell(row, column); if state == 72 { if row == 0 { break }; if column >= 1, let previous = h[Cell(row - 1, column - 1)] { let delta = oriented[row - 1] == sequence[column - 1] ? settings.match : -settings.mismatch; if h[cell]! == previous + delta { backward.append(77); row -= 1; column -= 1; continue } }; state = f[cell] != nil && h[cell] == f[cell] ? 73 : 68 } else if state == 73 { backward.append(73); let previous = f[Cell(row - 1, column)]; state = previous != nil && f[cell]! == previous! - gapExtend ? 73 : 72; row -= 1 } else { backward.append(68); let previous = e[Cell(row, column - 1)]; state = previous != nil && e[cell]! == previous! - gapExtend ? 68 : 72; column -= 1 } }
    return BandAlignment(score: score, position: column, operations: Array(backward.reversed()))
}
struct Hit { let mismatches: Int; let reference: Int; let position: Int; let strand: Int }
struct Candidate: Hashable { let strand: Int; let reference: Int; let center: Int }
struct AlignmentKey: Hashable { let reference: Int; let position: Int; let strand: Int }
struct AcceptedAlignment { let key: AlignmentKey; let score: Int; let operations: [UInt8] }
final class Mapper {
    let referenceText: ReferenceText
    let forward: FMIndex
    let reverse: FMIndex
    let settings: Settings
    var searchCounts = ["calls": 0, "nodes": 0, "leaves": 0, "positions": 0]
    var seedCounts = ["reads": 0, "seeds": 0, "with_n": 0, "repetitive": 0, "without_hit": 0, "candidates": 0, "passing": 0]
    init(_ referenceText: ReferenceText, _ forward: FMIndex, _ reverse: FMIndex, _ settings: Settings) { self.referenceText = referenceText; self.forward = forward; self.reverse = reverse; self.settings = settings }
    func locate(_ row: Int) -> (reference: Int, offset: Int) { referenceText.position(forward.locate(row).position)! }
    func alignment(_ reference: Int, _ position: Int, _ strand: Int, _ operations: [UInt8], _ result: MappingResult) -> Alignment { describe(reference, position, strand, operations, result, referenceText.references) }
    func mapRead(_ read: Read) -> MappingResult {
        let qualities = read.quality.map { Int($0) - 33 }
        var length = read.bases.count
        while length > 0 && qualities[length - 1] < settings.trimQuality { length -= 1 }
        let core = Array(read.bases.prefix(length))
        var result = MappingResult(read: read, core: core, qualities: qualities, length: length, trimmed: read.bases.count - length)
        if length < settings.minimumLength { return result }
        let oriented = [core, reverseComplement(core)], exact = oriented.map { forward.backwardSearch($0) }, maximum = exact.contains { !$0.isEmpty } ? 1 : settings.maximumMismatches
        var hits: [Hit] = []
        for strand in 0..<2 { let search = backtrack(oriented[strand], maximum, forward, reverse); searchCounts["calls"]! += 1; searchCounts["nodes"]! += search.nodes; searchCounts["leaves"]! += search.leaves.count; searchCounts["positions"]! += search.positions; for leaf in search.leaves { for row in leaf.range.lower..<leaf.range.upper { let position = locate(row); hits.append(Hit(mismatches: leaf.mismatches, reference: position.reference, position: position.offset, strand: strand)) } } }
        if hits.isEmpty { seedAndExtend(&result, oriented) } else { hits.sort { first, second in if first.mismatches != second.mismatches { return first.mismatches < second.mismatches }; if first.reference != second.reference { return first.reference < second.reference }; if first.position != second.position { return first.position < second.position }; return first.strand < second.strand }; finishSearch(&result, hits) }
        return result
    }
    func finishSearch(_ result: inout MappingResult, _ hits: [Hit]) {
        let best = hits[0].mismatches, n1 = hits.filter { $0.mismatches == best }.count, n2 = hits.filter { $0.mismatches == best + 1 }.count, operations = Array(repeating: UInt8(77), count: result.length), alignments = hits.filter { $0.mismatches <= best + 1 }.map { alignment($0.reference, $0.position, $0.strand, operations, result) }
        result.primary = alignments[0]; result.others = Array(alignments.dropFirst()); result.method = best == 0 ? "EXACT" : "MISMATCH"; result.score = (result.length - best) * settings.match - best * settings.mismatch; result.mapq = n1 >= 2 ? 0 : n2 == 0 ? 60 - 12 * best : max(30 - 12 * best - 3 * n2, 1); result.x0 = n1; result.x1 = n2; result.targets = Set(hits.filter { $0.mismatches == best }.map { $0.reference }).sorted()
    }
    func makeCandidates(_ oriented: [[UInt8]]) -> [Candidate] { var candidates: Set<Candidate> = []; for strand in 0..<2 { let sequence = oriented[strand]; for offset in stride(from: 0, through: sequence.count - settings.seedLength, by: settings.seedStep) { seedCounts["seeds"]! += 1; let seed = Array(sequence[offset..<(offset + settings.seedLength)]); if seed.contains(78) { seedCounts["with_n"]! += 1; continue }; let range = forward.backwardSearch(seed); if range.count > settings.maximumSeedHits { seedCounts["repetitive"]! += 1 } else if range.isEmpty { seedCounts["without_hit"]! += 1 } else { for row in range.lower..<range.upper { let position = locate(row); candidates.insert(Candidate(strand: strand, reference: position.reference, center: position.offset - offset)) } } } }; seedCounts["candidates"]! += candidates.count; return candidates.sorted { first, second in if first.strand != second.strand { return first.strand < second.strand }; if first.reference != second.reference { return first.reference < second.reference }; return first.center < second.center } }
    func seedAndExtend(_ result: inout MappingResult, _ oriented: [[UInt8]]) {
        result.reason = "NOHIT"
        if result.length < settings.seedLength { return }
        seedCounts["reads"]! += 1
        var accepted: [AlignmentKey: AcceptedAlignment] = [:]
        let threshold = settings.minimumScore * settings.match * result.length
        for candidate in makeCandidates(oriented) { guard let alignment = bandedAlignment(oriented[candidate.strand], referenceText.references[candidate.reference].bases, candidate.center, settings), 100 * alignment.score >= threshold else { continue }; let key = AlignmentKey(reference: candidate.reference, position: alignment.position, strand: candidate.strand); if accepted[key] == nil || alignment.score > accepted[key]!.score { accepted[key] = AcceptedAlignment(key: key, score: alignment.score, operations: alignment.operations) } }
        seedCounts["passing"]! += accepted.count
        if accepted.isEmpty { return }
        let ordered = accepted.values.sorted { first, second in if first.score != second.score { return first.score > second.score }; if first.key.reference != second.key.reference { return first.key.reference < second.key.reference }; if first.key.position != second.key.position { return first.key.position < second.key.position }; return first.key.strand < second.key.strand }, best = ordered[0].score, n1 = ordered.filter { $0.score == best }.count, second = ordered.filter { $0.score < best }.map { $0.score }.max() ?? 0, alignments = ordered.map { alignment($0.key.reference, $0.key.position, $0.key.strand, $0.operations, result) }
        result.primary = alignments[0]; result.others = Array(alignments.dropFirst()); result.method = "SEED"; result.score = best; result.mapq = n1 >= 2 ? 0 : 60 * (best - second) / best; result.x0 = n1; result.x1 = ordered.count - n1; result.targets = Set(ordered.filter { $0.score == best }.map { $0.key.reference }).sorted()
    }
}
func indexStatistics(_ referenceText: ReferenceText, _ suffixes: SuffixArray, _ forward: FMIndex, _ reverseSuffixes: SuffixArray, _ reverse: FMIndex, _ settings: Settings) -> [String] {
    let sequence = referenceText.sequence, references = referenceText.references, size = sequence.count
    var lines = ["text length \(size) sequences \(references.count)"], frequencies = Array(repeating: 0, count: symbols.count)
    for (number, reference) in references.enumerated() { let gc = reference.bases.filter { $0 == 67 || $0 == 71 }.count; lines.append("sequence \(reference.name) length \(reference.bases.count) offset \(referenceText.offsets[number]) gc \(ratio(gc, reference.bases.count)) masked \(reference.masked)") }
    for symbol in sequence { frequencies[symbolNumber(symbol)] += 1 }
    lines += ["symbols " + symbols.indices.map { "\(String(UnicodeScalar(symbols[$0]))) \(frequencies[$0])" }.joined(separator: " "), "", "forward_index", "suffix_array rounds \(suffixes.classes.count - 1)"]
    for (round, count) in suffixes.classes.enumerated() { lines.append("round \(round) prefix_length \(1 << round) classes \(count)") }
    let check = adjacentCheck(sequence, suffixes.order)
    lines += ["sa_check pairs \(size - 1) ordered \(check.ordered) lcp_sum \(check.sum) mean_lcp \(ratio(check.sum, size - 1)) max_lcp \(check.maximum)", "longest_repeat \(check.maximum) \(referenceText.label(suffixes.order[check.row - 1])) \(referenceText.label(suffixes.order[check.row]))"]
    var kmers: [String: Int] = [:]
    for reference in references where reference.bases.count >= settings.seedLength { for position in 0...(reference.bases.count - settings.seedLength) { kmers[text(Array(reference.bases[position..<(position + settings.seedLength)])), default: 0] += 1 } }
    let occurrences = kmers.values.reduce(0, +), unique = kmers.values.filter { $0 == 1 }.count
    lines += ["kmers length \(settings.seedLength) occurrences \(occurrences) distinct \(kmers.count) unique \(unique) max_occurrence \(kmers.values.max()!) unique_fraction \(ratio(unique, occurrences))", "bwt runs \(runs(forward.bwt).count) head \(text(Array(forward.bwt.prefix(60))))", "c_array " + symbols.indices.map { "\(String(UnicodeScalar(symbols[$0]))) \(forward.cumulative[$0])" }.joined(separator: " "), "occ interval \(forward.interval) checkpoints \(forward.checkpoints.count)", "sa_sample interval \(settings.sampleInterval) samples \(forward.samples.count)"]
    var correct = 0, totalSteps = 0, maximumSteps = 0
    for (row, position) in suffixes.order.enumerated() { let value = forward.locate(row); if value.position == position { correct += 1 }; totalSteps += value.steps; maximumSteps = max(maximumSteps, value.steps) }
    let reverseCheck = adjacentCheck(referenceText.reverse, reverseSuffixes.order)
    lines += ["locate rows \(size) correct \(correct) total_steps \(totalSteps) max_steps \(maximumSteps) mean_steps \(ratio(totalSteps, size))", "inverse_bwt identical \(forward.inverse() == sequence ? "yes" : "no")", "", "reverse_index", "suffix_array rounds \(reverseSuffixes.classes.count - 1)", "sa_check pairs \(size - 1) ordered \(reverseCheck.ordered)", "bwt runs \(runs(reverse.bwt).count) head \(text(Array(reverse.bwt.prefix(60))))", "inverse_bwt identical \(reverse.inverse() == referenceText.reverse ? "yes" : "no")", "", "direct_sort"]
    var checks = 0
    for reference in references where reference.bases.count <= settings.directLimit { let sequence = reference.bases + [UInt8(36)], doubled = buildSuffixArray(sequence); lines.append("\(reference.name) length \(sequence.count) rounds \(doubled.classes.count - 1) identical \(doubled.order == directSort(sequence) ? "yes" : "no")"); checks += 1 }
    if checks == 0 { lines.append("none") }
    let occurrenceBytes = 24 * forward.checkpoints.count, sampleBytes = 4 * forward.samples.count, bitmapBytes = (size + 7) / 8, totalBytes = size + occurrenceBytes + sampleBytes + bitmapBytes
    lines += ["", "index_size bwt_bytes \(size) occ_bytes \(occurrenceBytes) sample_bytes \(sampleBytes) bitmap_bytes \(bitmapBytes) total_bytes \(totalBytes) full_bytes \(5 * size) ratio \(ratio(totalBytes, 5 * size))"]
    return lines
}
func coverageAndVariants(_ results: [MappingResult], _ references: [Reference], _ settings: Settings) -> (coverage: [String], variants: [String]) {
    var depths = references.map { Array(repeating: 0, count: $0.bases.count) }, starts = depths, pileups = references.map { Array(repeating: Array(repeating: 0, count: 8), count: $0.bases.count) }
    for result in results { guard let alignment = result.primary else { continue }; let reference = alignment.reference, strand = alignment.strand; if result.mapq == 0 { starts[reference][alignment.position] += 1 }; if result.mapq < settings.coverageMapq { continue }; for pair in alignment.pairs { depths[reference][pair.reference] += 1; let base = alignment.oriented[pair.read], cycle = strand == 0 ? pair.read + 1 : result.length - pair.read; if base != 78 && result.qualities[cycle - 1] >= settings.variantQuality { pileups[reference][pair.reference][bases.firstIndex(of: base)! * 2 + strand] += 1 } } }
    var coverage = ["window \(settings.coverageWindow) min_mapq \(settings.coverageMapq)"], variants = ["min_depth \(settings.variantDepth) min_base_quality \(settings.variantQuality) min_alt_percent \(settings.variantPercent) hom_percent \(settings.homozygousPercent)"], callable = 0, variantCount = 0, heterozygous = 0, homozygous = 0
    for (number, reference) in references.enumerated() {
        let length = reference.bases.count, depth = depths[number], maximum = depth.max()!, covered = depth.filter { $0 >= 1 }.count
        var histogram = Array(repeating: 0, count: maximum + 1)
        for value in depth { histogram[value] += 1 }
        coverage += ["reference \(reference.name) length \(length) covered \(covered) breadth \(ratio(covered, length)) mean_depth \(ratio(depth.reduce(0, +), length)) max_depth \(maximum)", "depth_histogram " + histogram.indices.map { "\($0):\(histogram[$0])" }.joined(separator: " ")]
        for first in stride(from: 0, to: length, by: settings.coverageWindow) { let last = min(first + settings.coverageWindow, length), size = last - first, values = depth[first..<last], gc = reference.bases[first..<last].filter { $0 == 67 || $0 == 71 }.count, total = values.reduce(0, +), zero = values.filter { $0 == 0 }.count, mapqZero = starts[number][first..<last].reduce(0, +); coverage.append("\(reference.name) \(first + 1) \(last) gc \(ratio(gc, size)) sum \(total) mean \(ratio(total, size)) max \(values.max()!) zero \(zero) mapq0 \(mapqZero) |" + String(repeating: "#", count: 10 * total / size)) }
        for (offset, strandCounts) in pileups[number].enumerated() { let counts = (0..<4).map { strandCounts[2 * $0] + strandCounts[2 * $0 + 1] }, callDepth = counts.reduce(0, +); if callDepth < settings.variantDepth { continue }; callable += 1; let referenceBase = reference.bases[offset], alternative = (0..<4).filter { bases[$0] != referenceBase }.sorted { counts[$0] == counts[$1] ? $0 < $1 : counts[$0] > counts[$1] }[0], count = counts[alternative]; if count < 2 || 100 * count < settings.variantPercent * callDepth { continue }; let homo = 100 * count >= settings.homozygousPercent * callDepth; if homo { homozygous += 1 } else { heterozygous += 1 }; variantCount += 1; variants.append("\(reference.name) \(offset + 1) \(String(UnicodeScalar(referenceBase)))>\(String(UnicodeScalar(bases[alternative]))) depth \(callDepth) alt \(count) fraction \(ratio(count, callDepth)) genotype \(homo ? "1/1" : "0/1") strands \(strandCounts[2 * alternative]) \(strandCounts[2 * alternative + 1]) counts " + counts.map(String.init).joined(separator: " ")) }
    }
    variants.append("callable \(callable) variants \(variantCount) heterozygous \(heterozygous) homozygous \(homozygous)")
    return (coverage, variants)
}
struct ErrorTally { var aligned = 0; var mismatches = 0 }
func errorStatistics(_ results: [MappingResult], _ references: [Reference]) -> [String] {
    let maximumCycle = results.map { $0.read.bases.count }.max()!
    var cycles = Array(repeating: ErrorTally(), count: maximumCycle + 1), substitutions = Array(repeating: Array(repeating: 0, count: 5), count: 4), qualityCounts = [0, 0], qualitySums = [0, 0], qualityBins = Array(repeating: ErrorTally(), count: 5), operationCounts: [UInt8: Int] = [:], events: [UInt8: Int] = [:], indelBases: [UInt8: Int] = [:]
    for result in results { guard let alignment = result.primary else { continue }; for operation in alignment.operations { operationCounts[operation, default: 0] += 1 }; operationCounts[83, default: 0] += result.trimmed; if result.x0 != 1 { continue }; let sequence = references[alignment.reference].bases; for pair in alignment.pairs { let observed = alignment.oriented[pair.read], reference = sequence[pair.reference], mismatch = observed == reference ? 0 : 1, cycle = alignment.strand == 0 ? pair.read + 1 : result.length - pair.read, quality = result.qualities[cycle - 1], bin = min(quality / 10, 4); cycles[cycle].aligned += 1; cycles[cycle].mismatches += mismatch; substitutions[bases.firstIndex(of: reference)!][observed == 78 ? 4 : bases.firstIndex(of: observed)!] += 1; qualityCounts[mismatch] += 1; qualitySums[mismatch] += quality; qualityBins[bin].aligned += 1; qualityBins[bin].mismatches += mismatch }; for run in runs(alignment.operations) where run.operation == 73 || run.operation == 68 { events[run.operation, default: 0] += 1; indelBases[run.operation, default: 0] += run.count } }
    let aligned = qualityCounts.reduce(0, +), mismatches = qualityCounts[1]
    var lines = ["error_profile aligned_bases \(aligned) mismatches \(mismatches) rate \(ratio(mismatches, aligned))", "substitutions", "ref A C G T N"]
    for base in bases.indices { lines.append(String(UnicodeScalar(bases[base])) + " " + substitutions[base].map(String.init).joined(separator: " ")) }
    lines.append("mismatch_by_cycle")
    for cycle in 1...maximumCycle { let value = cycles[cycle]; lines.append("cycle \(cycle) aligned \(value.aligned) mismatches \(value.mismatches) rate \(ratio(value.mismatches, value.aligned))") }
    lines += ["quality matched \(qualityCounts[0]) mean \(ratio(qualitySums[0], qualityCounts[0])) mismatched \(qualityCounts[1]) mean \(ratio(qualitySums[1], qualityCounts[1]))", "quality_bins"]
    let ranges = ["0-9", "10-19", "20-29", "30-39", "40-"]
    for index in qualityBins.indices { let value = qualityBins[index]; lines.append("\(ranges[index]) aligned \(value.aligned) mismatches \(value.mismatches) rate \(ratio(value.mismatches, value.aligned))") }
    lines += ["cigar " + Array("MIDS".utf8).map { "\(String(UnicodeScalar($0))) \(operationCounts[$0, default: 0])" }.joined(separator: " "), "indels insertions \(events[73, default: 0]) \(indelBases[73, default: 0]) deletions \(events[68, default: 0]) \(indelBases[68, default: 0])"]
    return lines
}
func mappingStatistics(_ results: [MappingResult], _ references: [Reference], _ searchCounts: [String: Int], _ seedCounts: [String: Int]) -> [String] {
    let total = results.count, mapped = results.filter { $0.primary != nil }, unique = mapped.filter { $0.x0 == 1 }.count, short = results.filter { $0.primary == nil && $0.reason == "SHORT" }.count, nohit = results.filter { $0.primary == nil && $0.reason == "NOHIT" }.count
    var lines = ["reads total \(total) trimmed \(results.filter { $0.trimmed > 0 }.count) trimmed_bases \(results.map { $0.trimmed }.reduce(0, +)) short \(short)", "mapped \(mapped.count) rate \(ratio(mapped.count, total)) unique \(unique) multi \(mapped.count - unique) unmapped \(total - mapped.count)", "unmapped short \(short) nohit \(nohit)", "method exact \(mapped.filter { $0.method == "EXACT" }.count) mismatch \(mapped.filter { $0.method == "MISMATCH" }.count) seed \(mapped.filter { $0.method == "SEED" }.count)", "strand forward \(mapped.filter { $0.primary!.strand == 0 }.count) reverse \(mapped.filter { $0.primary!.strand == 1 }.count)"]
    for (number, reference) in references.enumerated() { let onReference = mapped.filter { $0.primary!.reference == number }, unique = onReference.filter { $0.x0 == 1 }.count, forward = onReference.filter { $0.primary!.strand == 0 }.count; lines.append("reference \(reference.name) mapped \(onReference.count) unique \(unique) forward \(forward) reverse \(onReference.count - forward)") }
    lines.append("length_bins")
    let minimum = results.map { $0.length }.min()! / 10 * 10, maximum = results.map { $0.length }.max()! / 10 * 10
    for lower in stride(from: minimum, through: maximum, by: 10) { let bin = results.filter { $0.length >= lower && $0.length <= lower + 9 }, mapped = bin.filter { $0.primary != nil }; lines.append("\(lower)-\(lower + 9) reads \(bin.count) mapped \(mapped.count) unique \(mapped.filter { $0.x0 == 1 }.count)") }
    let withN = results.filter { $0.read.bases.contains(78) }
    lines += ["n_reads \(withN.count) n_bases \(withN.map { $0.read.bases.filter { $0 == 78 }.count }.reduce(0, +)) mapped \(withN.filter { $0.primary != nil }.count)", "multi_targets"]
    var targets: [String: Int] = [:], mapq: [Int: Int] = [:], nm: [Int: Int] = [:]
    for result in mapped { if result.x0 >= 2 { targets[result.targets.map { references[$0].name }.joined(separator: "+"), default: 0] += 1 }; mapq[result.mapq, default: 0] += 1; nm[result.primary!.nm, default: 0] += 1 }
    if targets.isEmpty { lines.append("none") } else { for target in targets.keys.sorted() { lines.append("\(target) \(targets[target]!)") } }
    lines.append("mapq_histogram")
    for value in mapq.keys.sorted(by: >) { lines.append("\(value) \(mapq[value]!)") }
    lines.append("nm_histogram")
    for value in nm.keys.sorted() { lines.append("\(value) \(nm[value]!)") }
    lines += errorStatistics(results, references)
    lines.append("search dfs_calls \(searchCounts["calls"]!) dfs_nodes \(searchCounts["nodes"]!) dfs_leaves \(searchCounts["leaves"]!) dfs_positions \(searchCounts["positions"]!)")
    lines.append("seeds " + ["reads", "seeds", "with_n", "repetitive", "without_hit", "candidates", "passing"].map { "\($0) \(seedCounts[$0]!)" }.joined(separator: " "))
    return lines
}
let input = try readInputs(), referenceText = ReferenceText(input.references), suffixes = buildSuffixArray(referenceText.sequence), reverseSuffixes = buildSuffixArray(referenceText.reverse), forward = FMIndex(referenceText.sequence, suffixes.order, input.settings.occurrenceInterval, input.settings.sampleInterval), reverse = FMIndex(referenceText.reverse, reverseSuffixes.order, input.settings.occurrenceInterval)
let indexLines = indexStatistics(referenceText, suffixes, forward, reverseSuffixes, reverse, input.settings), mapper = Mapper(referenceText, forward, reverse, input.settings), results = input.reads.map { mapper.mapRead($0) }, samLines = samHeader(input.references) + results.map { samRecord($0, input.references, input.settings.maximumAlternatives) }, coverage = coverageAndVariants(results, input.references, input.settings), summary = mappingStatistics(results, input.references, mapper.searchCounts, mapper.seedCounts)
for (name, lines) in [("alignments.sam", samLines), ("coverage.txt", coverage.coverage), ("variants.txt", coverage.variants), ("index_stats.txt", indexLines), ("summary.txt", summary)] { try writeLines(name, lines) }
