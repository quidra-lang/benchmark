import Foundation

let methodNames = ["sad", "ssd", "census", "sgm", "fusion", "wta_final", "sgm_final"]
let costKinds = [CostKind.sad, .ssd, .census]
enum Check: Int { case valid = 0, textureless = 50, nonunique = 100, outside = 150, mismatch = 200, occluded = 255 }
enum Source: String { case kept, median, background, interpolated, none }
let sources = [Source.kept, .median, .background, .interpolated, .none]
struct Selection { let image: [Int]; let reasons: [Check]; let margins: [Int]; let differences: [Int]; let bounds: Int; let window: Int }
struct Sweep { let kind: CostKind; let window: Int; let metrics: Metrics; let valid: Int }
struct PathProgress { let number: Int; let metrics: Metrics; let valid: Int }
struct Postprocess { let image: [Int]; let sources: [Source]; let speckles: Int; let specklePixels: Int; let medianChanged: Int; let background: Int; let interpolated: Int; let unfilled: Int }
enum Details { case selection(Selection), fusion([Int]), postprocessed(Postprocess) }
struct Method { let name: String; let image: [Int]; let details: Details }
func lowerMedian(_ values: [Int]) -> Int { values.sorted()[(values.count - 1) / 2] }
func neighbors4(_ p: Int, _ width: Int, _ height: Int) -> [Int] { let x = p % width, y = p / width; return [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)].filter { $0.0 >= 0 && $0.0 < width && $0.1 >= 0 && $0.1 < height }.map { $0.1 * width + $0.0 } }
func selectDisparities(_ volume: [[Int]], _ strengths: [Int], _ width: Int, _ height: Int, _ settings: Settings, _ window: Int) -> Selection {
    let minimum = settings.disparityMin, maximum = settings.disparityMax
    var right = Array(repeating: 0, count: volume.count)
    for p in volume.indices { let x = p % width; var cost = Int.max; for disparity in minimum...maximum where x + disparity < width { let value = volume[p + disparity][disparity - minimum]; if value < cost { cost = value; right[p] = disparity } } }
    var image = Array(repeating: 0, count: volume.count), reasons = Array(repeating: Check.valid, count: volume.count), margins = Array(repeating: 0, count: volume.count), differences = [0, 0, 0, 0], bounds = 0
    for p in volume.indices {
        let x = p % width, costs = volume[p]
        var best = minimum
        for disparity in (minimum + 1)...maximum { if costs[disparity - minimum] < costs[best - minimum] { best = disparity } }
        let first = costs[best - minimum], second = (minimum...maximum).filter { abs($0 - best) >= 2 }.map { costs[$0 - minimum] }.min()!
        if best == minimum || best == maximum { bounds += 1 }
        func consistent(_ disparity: Int) -> Bool { x >= disparity && abs(disparity - right[p - disparity]) <= settings.lrMaximumDifference }
        let reason: Check
        if strengths[p] < settings.textureThreshold { reason = .textureless }
        else if 100 * second <= (100 + settings.uniqueness) * first { reason = .nonunique }
        else if x < best { reason = .outside }
        else if !consistent(best) { reason = (minimum...maximum).contains(where: consistent) ? .mismatch : .occluded }
        else { reason = .valid; image[p] = best; margins[p] = second - first }
        reasons[p] = reason
        if reason == .valid || reason == .mismatch || reason == .occluded { differences[min(3, abs(best - right[p - best]))] += 1 }
    }
    return Selection(image: image, reasons: reasons, margins: margins, differences: differences, bounds: bounds, window: window)
}
func chooseWindows(_ left: [Int], _ right: [Int], _ cl: [Int], _ cr: [Int], _ strengths: [Int], _ width: Int, _ height: Int, _ truth: [Int], _ regions: TruthRegions, _ settings: Settings) -> (selections: [Selection], sweeps: [Sweep]) {
    var selections: [Selection] = [], sweeps: [Sweep] = []
    for (index, kind) in costKinds.enumerated() { var best: Selection?, bestMetrics: Metrics?; for window in settings.windows[index] { let volume = costVolume(left, right, cl, cr, width, height, kind, window, settings.disparityMin, settings.disparityMax), selection = selectDisparities(volume, strengths, width, height, settings, window), metrics = evaluate(selection.image, truth, regions.visible); sweeps.append(Sweep(kind: kind, window: window, metrics: metrics, valid: selection.image.filter { $0 != 0 }.count)); if bestMetrics == nil || metrics.bad1 < bestMetrics!.bad1 || (metrics.bad1 == bestMetrics!.bad1 && metrics.bad2 < bestMetrics!.bad2) { best = selection; bestMetrics = metrics } }; selections.append(best!) }
    return (selections, sweeps)
}
func semiGlobal(_ left: [Int], _ right: [Int], _ cl: [Int], _ cr: [Int], _ strengths: [Int], _ width: Int, _ height: Int, _ truth: [Int], _ regions: TruthRegions, _ settings: Settings) -> (selection: Selection, costs: [[Int]], progress: [PathProgress]) {
    let base = costVolume(left, right, cl, cr, width, height, settings.sgmCost, settings.sgmWindow, settings.disparityMin, settings.disparityMax), cumulative = cumulativeCosts(base, left, width, height, settings.sgmPaths, settings.p1, settings.p2, settings.p2Gamma)
    var selected: Selection?, progress: [PathProgress] = []
    for (index, total) in cumulative.enumerated() { let selection = selectDisparities(total, strengths, width, height, settings, settings.sgmWindow); selected = selection; progress.append(PathProgress(number: index + 1, metrics: evaluate(selection.image, truth, regions.visible), valid: selection.image.filter { $0 != 0 }.count)) }
    return (selected!, cumulative.last!, progress)
}
func connectedRegions(_ image: [Int], _ width: Int, _ height: Int, _ maximumDifference: Int) -> [[Int]] {
    var visited = Array(repeating: false, count: image.count), components: [[Int]] = []
    for start in image.indices where image[start] != 0 && !visited[start] { visited[start] = true; var stack = [start], component: [Int] = []; while let p = stack.popLast() { component.append(p); for q in neighbors4(p, width, height) where image[q] != 0 && !visited[q] && abs(image[q] - image[p]) <= maximumDifference { visited[q] = true; stack.append(q) } }; components.append(component) }
    return components
}
func medianFilter(_ image: [Int], _ width: Int, _ height: Int) -> [Int] { var result = Array(repeating: 0, count: image.count); for p in image.indices where image[p] != 0 { let x = p % width, y = p / width; var values: [Int] = []; for yy in max(0, y - 1)...min(height - 1, y + 1) { for xx in max(0, x - 1)...min(width - 1, x + 1) { let value = image[yy * width + xx]; if value != 0 { values.append(value) } } }; result[p] = lowerMedian(values) }; return result }
func rayValues(_ image: [Int], _ width: Int, _ height: Int, _ x: Int, _ y: Int, _ directions: [(Int, Int)]) -> [Int] { var values: [Int] = []; for (dx, dy) in directions { var xx = x + dx, yy = y + dy; while xx >= 0 && xx < width && yy >= 0 && yy < height { let value = image[yy * width + xx]; if value != 0 { values.append(value); break }; xx += dx; yy += dy } }; return values }
func postprocess(_ selection: Selection, _ width: Int, _ height: Int, _ settings: Settings) -> Postprocess {
    let original = selection.image, components = connectedRegions(original, width, height, settings.speckleRange), removed = components.filter { $0.count < settings.speckleSize }
    var filtered = original
    for part in removed { for p in part { filtered[p] = 0 } }
    let medians = medianFilter(filtered, width, height)
    var result = medians, sources = Array(repeating: Source.none, count: original.count)
    for p in original.indices { let x = p % width, y = p / width; if medians[p] != 0 { sources[p] = medians[p] == original[p] ? .kept : .median } else if selection.reasons[p] == .outside || selection.reasons[p] == .occluded { let values = rayValues(medians, width, height, x, y, [(-1, 0), (1, 0)]); if let minimum = values.min() { result[p] = minimum; sources[p] = .background } } else { let values = rayValues(medians, width, height, x, y, directions); if !values.isEmpty { result[p] = lowerMedian(values); sources[p] = .interpolated } } }
    return Postprocess(image: result, sources: sources, speckles: removed.count, specklePixels: removed.reduce(0) { $0 + $1.count }, medianChanged: original.indices.filter { filtered[$0] != medians[$0] }.count, background: sources.filter { $0 == .background }.count, interpolated: sources.filter { $0 == .interpolated }.count, unfilled: sources.filter { $0 == .none }.count)
}
func fuse(_ selections: [Selection], _ minimumVotes: Int) -> (image: [Int], votes: [Int]) { var result = Array(repeating: 0, count: selections[0].image.count), votes = Array(repeating: 0, count: 5); for p in result.indices { let candidates = selections.map { $0.image[p] }.filter { $0 != 0 }; votes[candidates.count] += 1; if !candidates.isEmpty { let median = lowerMedian(candidates); if candidates.filter({ abs($0 - median) <= 1 }).count >= minimumVotes { result[p] = median } } }; return (result, votes) }
struct ObjectMeasurement { let pixels: Int; let box: [Int]; let minimum: Int; let maximum: Int; let median: Int; let mean: String; let depth: String; let width: String; let height: String; let truth: Int?; let hits: Int; let union: Int; let first: Int }
func extractObjects(_ image: [Int], _ truth: [Int], _ width: Int, _ height: Int, _ settings: Settings) -> (objects: [ObjectMeasurement], small: Int, layers: [Int], detected: Set<Int>) {
    let components = connectedRegions(image, width, height, settings.objectRange)
    var trueCounts: [Int: Int] = [:], objects: [ObjectMeasurement] = [], small = 0
    for value in truth where value != 0 { trueCounts[value, default: 0] += 1 }
    for component in components { if component.count < settings.objectMinimumSize { small += 1; continue }; let xs = component.map { $0 % width }, ys = component.map { $0 / width }, disparities = component.map { image[$0] }, median = lowerMedian(disparities), count = component.count, sum = disparities.reduce(0, +), box = [xs.min()!, ys.min()!, xs.max()!, ys.max()!]; var layerCounts: [Int: Int] = [:]; for p in component where truth[p] != 0 { layerCounts[truth[p], default: 0] += 1 }; let layer = layerCounts.keys.sorted { layerCounts[$0]! == layerCounts[$1]! ? $0 < $1 : layerCounts[$0]! > layerCounts[$1]! }.first, hits = layer.map { layerCounts[$0]! } ?? 0, union = layer.map { count + trueCounts[$0]! - hits } ?? 0
        objects.append(ObjectMeasurement(pixels: count, box: box, minimum: disparities.min()!, maximum: disparities.max()!, median: median, mean: twoDecimals(sum, count), depth: twoDecimals(settings.focalLength * settings.baseline * count, sum), width: twoDecimals((box[2] - box[0] + 1) * settings.baseline, median), height: twoDecimals((box[3] - box[1] + 1) * settings.baseline, median), truth: layer, hits: hits, union: union, first: component.min()!))
    }
    objects.sort { first, second in if first.median != second.median { return first.median > second.median }; if first.pixels != second.pixels { return first.pixels > second.pixels }; return first.first < second.first }
    let detected = Set(objects.filter { $0.truth != nil && 2 * $0.hits > $0.union }.compactMap { $0.truth })
    return (objects, small, trueCounts.keys.sorted(), detected)
}
func objectLines(_ result: (objects: [ObjectMeasurement], small: Int, layers: [Int], detected: Set<Int>)) -> [String] {
    var lines = ["objects \(result.objects.count) small \(result.small) pixels \(result.objects.reduce(0) { $0 + $1.pixels })"]
    for (index, item) in result.objects.enumerated() { let truth = item.truth.map { "truth \($0) iou \(ratio(item.hits, item.union))" } ?? "truth - iou -"; lines.append("object \(index + 1) pixels \(item.pixels) box " + item.box.map(String.init).joined(separator: " ") + " disparity \(item.minimum) \(item.maximum) median \(item.median) mean \(item.mean) depth \(item.depth) size \(item.width) \(item.height) \(truth)") }
    let missed = result.layers.filter { !result.detected.contains($0) }
    lines.append("layers \(result.layers.count) detected \(result.detected.count) missed " + (missed.isEmpty ? "-" : missed.map(String.init).joined(separator: " ")))
    return lines
}
func sampleLines(_ methods: [Method], _ summedCosts: [[Int]], _ truth: [Int], _ width: Int, _ settings: Settings) -> [String] {
    var lines = ["x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth"]
    guard case .postprocessed(let post) = methods[6].details else { preconditionFailure() }
    for sample in settings.samples { let p = sample.y * width + sample.x; var values = [String(sample.x), String(sample.y)] + methods.prefix(4).map { $0.image[p] == 0 ? "-" : String($0.image[p]) }; let disparity = methods[6].image[p]; if disparity != 0 { let refined = subpixel(disparity, summedCosts[p], settings.disparityMin, settings.disparityMax, settings.focalLength, settings.baseline); values += [String(disparity), post.sources[p].rawValue, refined.disparity, refined.depth] } else { values += ["-", "none", "-", "-"] }; if truth[p] != 0 { values += [String(truth[p]), twoDecimals(settings.focalLength * settings.baseline, truth[p])] } else { values += ["-", "-"] }; lines.append(values.joined(separator: ",")) }
    return lines
}
func imageSummary(_ name: String, _ image: [Int]) -> String { "\(name) mean \(twoDecimals(image.reduce(0, +), image.count)) min \(image.min()!) max \(image.max()!)" }
func inputSummary(_ left: [Int], _ right: [Int], _ truth: [Int], _ strengths: [Int], _ width: Int, _ height: Int, _ regions: TruthRegions, _ settings: Settings) -> [String] {
    let size = width * height, delta = regions.visible.map { right[$0 - truth[$0]] - left[$0] }, biasSum = delta.reduce(0, +)
    var bias = twoDecimals(abs(biasSum), delta.count)
    if biasSum < 0 && bias != "0.00" { bias = "-" + bias }
    return ["image \(width) \(height)", "disparities \(settings.disparityMin) \(settings.disparityMax)", imageSummary("left", left), imageSummary("right", right), "texture mean \(twoDecimals(strengths.reduce(0, +), size)) textureless \(strengths.filter { $0 < settings.textureThreshold }.count)", "ground_truth known \(regions.known.count) nonocc \(regions.visible.count) occluded \(regions.occluded.count) disc \(regions.discontinuities.count) unknown \(size - regions.known.count)", "photometric pixels \(delta.count) mean_abs \(twoDecimals(delta.map { abs($0) }.reduce(0, +), delta.count)) bias \(bias)"]
}
func sweepLines(_ sweeps: [Sweep], _ progress: [PathProgress]) -> [String] { sweeps.map { "sweep \($0.kind.rawValue) window \($0.window) valid \($0.valid) bad1 \(ratio($0.metrics.bad1, $0.metrics.pixels)) bad2 \(ratio($0.metrics.bad2, $0.metrics.pixels))" } + progress.map { "paths \($0.number) valid \($0.valid) bad1 \(ratio($0.metrics.bad1, $0.metrics.pixels)) bad2 \(ratio($0.metrics.bad2, $0.metrics.pixels))" } }
func disparitySummary(_ method: Method, _ width: Int, _ height: Int) -> [String] {
    let image = method.image, values = image.filter { $0 != 0 }
    var horizontal = 0, vertical = 0
    for p in image.indices where image[p] != 0 { let x = p % width, y = p / width; if x + 1 < width && image[p + 1] != 0 && abs(image[p] - image[p + 1]) >= 2 { horizontal += 1 }; if y + 1 < height && image[p + width] != 0 && abs(image[p] - image[p + width]) >= 2 { vertical += 1 } }
    let distribution = values.isEmpty ? "disparity min - max - median - distinct 0" : "disparity min \(values.min()!) max \(values.max()!) median \(lowerMedian(values)) distinct \(Set(values).count)"
    return ["method \(method.name) valid \(values.count) invalid \(image.count - values.count)", distribution, "jumps horizontal \(horizontal) vertical \(vertical)"]
}
func selectionDetails(_ method: Selection) -> [String] {
    let checks = [Check.textureless, .nonunique, .outside, .mismatch, .occluded], names = ["textureless", "nonunique", "outside", "mismatch", "occluded"], reasons = checks.indices.map { index in "\(names[index]) \(method.reasons.filter { $0 == checks[index] }.count)" }.joined(separator: " "), differences = method.differences
    return ["window \(method.window) bounds \(method.bounds)", "reasons " + reasons, "lr 0 \(differences[0]) 1 \(differences[1]) 2 \(differences[2]) 3+ \(differences[3])"]
}
func postprocessDetails(_ method: Postprocess, _ truth: [Int], _ known: [Int]) -> [String] {
    var lines = ["postprocess speckles \(method.speckles) \(method.specklePixels) median \(method.medianChanged) background \(method.background) interpolated \(method.interpolated) unfilled \(method.unfilled)"]
    for source in sources { let region = known.filter { method.sources[$0] == source }, metrics = evaluate(method.image, truth, region); lines.append("source \(source.rawValue) pixels \(metrics.pixels) bad1 \(ratio(metrics.bad1, metrics.pixels))") }
    return lines
}
func regionLine(_ name: String, _ metrics: Metrics) -> String { "region \(name) pixels \(metrics.pixels) valid \(metrics.valid) bad1 \(ratio(metrics.bad1, metrics.pixels)) bad2 \(ratio(metrics.bad2, metrics.pixels)) mae \(metrics.mae) exact \(metrics.exact)" }
func depthErrorLine(_ image: [Int], _ truth: [Int], _ visible: [Int], _ settings: Settings) -> String { let errors = visible.filter { image[$0] != 0 }.map { abs(depthHundredths(image[$0], settings.focalLength, settings.baseline) - depthHundredths(truth[$0], settings.focalLength, settings.baseline)) }; if errors.isEmpty { return "depth_error pixels 0 mean - max -" }; return "depth_error pixels \(errors.count) mean \(twoDecimals(errors.reduce(0, +), 100 * errors.count)) max \(twoDecimals(errors.max()!, 100))" }
func errorCountsLine(_ image: [Int], _ truth: [Int], _ known: [Int]) -> String { var counts = [0, 0, 0, 0, 0], invalid = 0; for p in known { if image[p] == 0 { invalid += 1 } else { counts[min(abs(image[p] - truth[p]), 4)] += 1 } }; return "errors 0 \(counts[0]) 1 \(counts[1]) 2 \(counts[2]) 3 \(counts[3]) 4+ \(counts[4]) invalid \(invalid)" }
func methodLines(_ method: Method, _ truth: [Int], _ width: Int, _ height: Int, _ regions: TruthRegions, _ metrics: [Metrics], _ settings: Settings) -> [String] {
    var lines = disparitySummary(method, width, height)
    switch method.details { case .selection(let selection): lines += selectionDetails(selection); case .fusion(let votes): lines.append("votes " + (0..<5).map { "\($0) \(votes[$0])" }.joined(separator: " ")); case .postprocessed(let post): lines += postprocessDetails(post, truth, regions.known) }
    for index in regionNames.indices { lines.append(regionLine(regionNames[index], metrics[index])) }
    lines += [depthErrorLine(method.image, truth, regions.visible, settings), errorCountsLine(method.image, truth, regions.known)]
    return lines
}
func rankingLines(_ metrics: [[Metrics]]) -> [String] {
    regionNames.indices.map { region in
        let order = methodNames.indices.sorted { first, second in let a = metrics[first][region], b = metrics[second][region]; if a.bad1 != b.bad1 { return a.bad1 < b.bad1 }; if a.bad2 != b.bad2 { return a.bad2 < b.bad2 }; if (a.valid == 0) != (b.valid == 0) { return a.valid != 0 }; if a.valid != 0 && a.errorSum * b.valid != b.errorSum * a.valid { return a.errorSum * b.valid < b.errorSum * a.valid }; return first < second }
        return "ranking \(regionNames[region]) " + order.map { methodNames[$0] }.joined(separator: " ")
    }
}
func occlusionLines(_ selections: [Selection], _ regions: TruthRegions) -> [String] {
    selections.enumerated().map { index, selection in func detected(_ pixel: Int) -> Bool { selection.reasons[pixel] == .outside || selection.reasons[pixel] == .occluded }; let tp = regions.occluded.filter(detected).count, fp = regions.visible.filter(detected).count, fn = regions.occluded.count - tp; return "occlusion \(methodNames[index]) tp \(tp) fp \(fp) fn \(fn) precision \(ratio(tp, tp + fp)) recall \(ratio(tp, tp + fn))" }
}
func confidenceLines(_ selections: [Selection], _ truth: [Int], _ visible: [Int]) -> [String] {
    var lines: [String] = []
    for (index, method) in selections.enumerated() { let pixels = visible.filter { method.image[$0] != 0 }.sorted { method.margins[$0] == method.margins[$1] ? $0 < $1 : method.margins[$0] > method.margins[$1] }; for percentage in [25, 50, 75, 100] { let count = (pixels.count * percentage + 99) / 100, bad = pixels.prefix(count).filter { abs(method.image[$0] - truth[$0]) > 1 }.count, margin = count == 0 ? "-" : String(method.margins[pixels[count - 1]]); lines.append("confidence \(methodNames[index]) \(percentage) pixels \(count) margin \(margin) bad1 \(ratio(bad, count))") } }
    return lines
}
func layerLines(_ methods: [Method], _ truth: [Int], _ regions: TruthRegions) -> [String] { Set(regions.known.map { truth[$0] }).sorted().map { layer in let visible = regions.visible.filter { truth[$0] == layer }, knownCount = regions.known.filter { truth[$0] == layer }.count, errors = methods.map { evaluate($0.image, truth, visible).bad1 }; return "layer \(layer) pixels \(knownCount) nonocc \(visible.count) bad1 " + errors.map(String.init).joined(separator: " ") } }
func evaluationLines(_ left: [Int], _ right: [Int], _ truth: [Int], _ strengths: [Int], _ width: Int, _ height: Int, _ regions: TruthRegions, _ methods: [Method], _ selections: [Selection], _ sweeps: [Sweep], _ progress: [PathProgress], _ settings: Settings) -> [String] {
    let metrics = methods.map { method in regions.ordered.map { evaluate(method.image, truth, $0) } }
    var lines = inputSummary(left, right, truth, strengths, width, height, regions, settings) + sweepLines(sweeps, progress)
    for (index, method) in methods.enumerated() { lines += methodLines(method, truth, width, height, regions, metrics[index], settings) }
    lines += rankingLines(metrics) + occlusionLines(selections, regions) + confidenceLines(selections, truth, regions.visible) + layerLines(methods, truth, regions)
    for disparity in settings.disparityMin...settings.disparityMax { lines.append("histogram \(disparity) \(methods[6].image.filter { $0 == disparity }.count)") }
    return lines
}
func errorImage(_ image: [Int], _ truth: [Int]) -> [Int] { image.indices.map { truth[$0] == 0 ? 0 : image[$0] == 0 ? 255 : 50 * (min(abs(image[$0] - truth[$0]), 3) + 1) } }
func saveText(_ name: String, _ lines: [String]) throws { try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) }
let leftImage = try readPGM("left.pgm"), rightImage = try readPGM("right.pgm"), truthImage = try readPGM("ground_truth.pgm"), settings = try readParameters(), width = leftImage.width, height = leftImage.height, left = leftImage.pixels, right = rightImage.pixels, truth = truthImage.pixels
let regions = truthRegions(truth, width, height), strengths = texture(left, width, height, settings.textureWindow), censusLeft = census(left, width, height), censusRight = census(right, width, height), chosen = chooseWindows(left, right, censusLeft, censusRight, strengths, width, height, truth, regions, settings), sgm = semiGlobal(left, right, censusLeft, censusRight, strengths, width, height, truth, regions, settings)
let selections = chosen.selections + [sgm.selection], fusion = fuse(selections, settings.fusionVotes), wtaIndex = costKinds.firstIndex(of: settings.wtaCost)!, wtaFinal = postprocess(selections[wtaIndex], width, height, settings), sgmFinal = postprocess(sgm.selection, width, height, settings)
let methods = selections.enumerated().map { Method(name: methodNames[$0.offset], image: $0.element.image, details: .selection($0.element)) } + [Method(name: "fusion", image: fusion.image, details: .fusion(fusion.votes)), Method(name: "wta_final", image: wtaFinal.image, details: .postprocessed(wtaFinal)), Method(name: "sgm_final", image: sgmFinal.image, details: .postprocessed(sgmFinal))]
let objects = extractObjects(sgmFinal.image, truth, width, height, settings)
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
try writePGM("disparity_wta.pgm", width, height, wtaFinal.image.map { 8 * $0 })
try writePGM("disparity_sgm.pgm", width, height, sgmFinal.image.map { 8 * $0 })
try writePGM("occlusion.pgm", width, height, sgm.selection.reasons.map { $0.rawValue })
try writePGM("error_sgm.pgm", width, height, errorImage(sgmFinal.image, truth))
try saveText("depth.csv", sampleLines(methods, sgm.costs, truth, width, settings))
try saveText("evaluation.txt", evaluationLines(left, right, truth, strengths, width, height, regions, methods, selections, chosen.sweeps, sgm.progress, settings))
try saveText("objects.txt", objectLines(objects))
