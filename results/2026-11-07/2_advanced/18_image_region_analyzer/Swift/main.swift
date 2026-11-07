import Foundation

let symbols = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
let orientations = ["none", "horizontal", "vertical", "falling", "rising"]
let four = [Point(1, 0), Point(0, -1), Point(-1, 0), Point(0, 1)]
let eight = [Point(1, 0), Point(1, -1), Point(0, -1), Point(-1, -1), Point(-1, 0), Point(-1, 1), Point(0, 1), Point(1, 1)]
let csvHeader = "image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border,perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent,depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area,solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,distance2,codes"

struct Setting {
    let connectivity: Int
    let threshold: String
    let polarity: String
    let operations: [String]
    var method: String { threshold == "otsu" || threshold == "isodata" ? threshold : "fixed" }
}
struct Parameters {
    var otsuTop = 0
    var sweepStep = 0
    var isotropy = Rational(0)
    var bayMin = 0
    var elements: [String: [Point]] = [:]
    var settings: [String: Setting] = [:]
}
func parseRational(_ text: String) -> Rational {
    let parts = text.split(separator: "/")
    return Rational(Int64(parts[0])!, parts.count == 1 ? 1 : Int64(parts[1])!)
}
func readLines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map(String.init)
}
func readParameters(_ path: String) throws -> Parameters {
    var result = Parameters()
    for line in try readLines(path) {
        let words = line.split(separator: " ").map(String.init)
        switch words[0] {
        case "otsu_top": result.otsuTop = Int(words[1])!
        case "sweep": result.sweepStep = Int(words[1])!
        case "isotropy": result.isotropy = parseRational(words[1])
        case "bay_min": result.bayMin = Int(words[1])!
        case "element":
            let ox = Int(words[4])!
            let oy = Int(words[5])!
            var offsets: [Point] = []
            for (y, row) in words.dropFirst(6).enumerated() {
                for (x, symbol) in row.enumerated() where symbol == "#" { offsets.append(Point(x - ox, y - oy)) }
            }
            result.elements[words[1]] = offsets
        case "image":
            result.settings[words[1]] = Setting(connectivity: Int(words[2])!, threshold: words[3], polarity: words[4], operations: Array(words.dropFirst(5)))
        default: preconditionFailure()
        }
    }
    return result
}

struct Condition {
    let feature: String
    let comparison: String
    let text: String
    let value: Rational
    init(_ words: [String]) {
        feature = words[0]
        comparison = words[1]
        text = words[2]
        value = words[0] == "orientation" ? Rational(0) : parseRational(words[2])
    }
    func holds(_ region: Region) -> Bool {
        if feature == "orientation" { return comparison == "=" ? region.orientation == text : region.orientation != text }
        let own = region.value(feature)
        switch comparison {
        case "<": return own < value
        case "<=": return own <= value
        case ">": return own > value
        case ">=": return own >= value
        case "=": return own == value
        case "!=": return own != value
        default: preconditionFailure()
        }
    }
    var words: String { "\(feature) \(comparison) \(text)" }
}
struct Rule {
    let name: String
    let conditions: [Condition]
    func matches(_ region: Region) -> Bool { conditions.allSatisfy { $0.holds(region) } }
}
struct Rules {
    var filters: [Condition] = []
    var classes: [Rule] = []
    var flags: [Rule] = []
    var classNames: [String] {
        var names: [String] = []
        for rule in classes where !names.contains(rule.name) { names.append(rule.name) }
        names.append("other")
        return names
    }
}
func readRules(_ path: String) throws -> Rules {
    var result = Rules()
    for line in try readLines(path) {
        let words = line.split(separator: " ").map(String.init)
        if words[0] == "filter" { result.filters.append(Condition(Array(words.dropFirst()))) }
        else {
            let conditions = stride(from: 2, to: words.count, by: 3).map { Condition(Array(words[$0..<($0 + 3)])) }
            let rule = Rule(name: words[1], conditions: conditions)
            if words[0] == "class" { result.classes.append(rule) } else { result.flags.append(rule) }
        }
    }
    return result
}

struct Hole {
    let number: Int
    let pixels: [Point]
    let owner: Int
}
final class Region {
    let number: Int
    let pixels: [Point]
    var features: [String: Rational] = [:]
    var orientation = "none"
    var codes: [Int] = []
    var skeleton: Set<Point> = []
    var hullDoubled: Int64 = 0
    var parent: Int? = nil
    var depth = 0
    var children: [Int] = []
    var kept = false
    var droppedBy: Int? = nil
    var className = "other"
    var flags: [String] = []
    var neighbor: Int? = nil
    var distance: Int64 = 0

    init(_ number: Int, _ pixels: [Point]) { self.number = number; self.pixels = pixels }
    func value(_ name: String) -> Rational { features[name]! }
    func integer(_ name: String) -> Int64 { let feature = value(name); return feature.numerator / feature.denominator }
    func set(_ name: String, _ value: Rational) { features[name] = value }
    func setInt<T: BinaryInteger>(_ name: String, _ value: T) { features[name] = Rational(Int64(value)) }
}

func directions(_ connectivity: Int) -> [Point] { connectivity == 4 ? four : eight }
func countForeground(_ mask: Mask) -> Int { mask.reduce(0) { $0 + $1.filter { $0 }.count } }
func groupPixels(_ labels: [[Int]], _ count: Int) -> [[Point]] {
    var groups = Array(repeating: [Point](), count: count + 1)
    for (y, row) in labels.enumerated() { for (x, label) in row.enumerated() { groups[label].append(Point(x, y)) } }
    return groups
}
func enclosedComponents(_ mask: Mask, _ connectivity: Int) -> [[Point]] {
    let background = mask.map { $0.map { !$0 } }
    let result = labelComponents(background, connectivity)
    return groupPixels(result.labels, result.count).dropFirst().filter { pixels in
        !pixels.contains { $0.x == 0 || $0.y == 0 || $0.x == mask[0].count - 1 || $0.y == mask.count - 1 }
    }
}
func fillHoles(_ mask: Mask, _ connectivity: Int) -> Mask {
    var filled = mask
    for pixels in enclosedComponents(mask, connectivity) { for point in pixels { filled[point.y][point.x] = true } }
    return filled
}
func cross(_ a: Point, _ b: Point, _ point: Point) -> Int64 {
    Int64(b.x - a.x) * Int64(point.y - a.y) - Int64(b.y - a.y) * Int64(point.x - a.x)
}
func squaredDistance(_ a: Point, _ b: Point) -> Int64 {
    let dx = Int64(a.x - b.x)
    let dy = Int64(a.y - b.y)
    return dx * dx + dy * dy
}
func halfHull<S: Sequence>(_ points: S) -> [Point] where S.Element == Point {
    var chain: [Point] = []
    for point in points {
        while chain.count >= 2 && cross(chain[chain.count - 2], chain[chain.count - 1], point) <= 0 { chain.removeLast() }
        chain.append(point)
    }
    return chain
}
func convexHull(_ pixels: [Point]) -> [Point] {
    var corners: Set<Point> = []
    for point in pixels {
        corners.formUnion([point, Point(point.x + 1, point.y), Point(point.x, point.y + 1), Point(point.x + 1, point.y + 1)])
    }
    let ordered = corners.sorted()
    return Array(halfHull(ordered).dropLast()) + Array(halfHull(ordered.reversed()).dropLast())
}
func hullEdges(_ hull: [Point]) -> [(Point, Point)] { hull.indices.map { (hull[$0], hull[($0 + 1) % hull.count]) } }
func containsCenter(_ hull: [Point], _ x: Int, _ y: Int) -> Bool {
    hullEdges(hull).allSatisfy { a, b in cross(Point(2 * a.x, 2 * a.y), Point(2 * b.x, 2 * b.y), Point(2 * x + 1, 2 * y + 1)) >= 0 }
}
func boxBounds(_ pixels: [Point]) -> (x0: Int, y0: Int, x1: Int, y1: Int) {
    (pixels.map(\.x).min()!, pixels.map(\.y).min()!, pixels.map(\.x).max()!, pixels.map(\.y).max()!)
}
func boxDistance(_ first: Region, _ second: Region) -> Int64 {
    let dx = first.integer("x0") + first.integer("x1") - second.integer("x0") - second.integer("x1")
    let dy = first.integer("y0") + first.integer("y1") - second.integer("y0") - second.integer("y1")
    return dx * dx + dy * dy
}
func meanText(_ sum: Int64, _ count: Int) -> String { count == 0 ? "-" : decimal(Rational(sum, Int64(count)), 2) }
func orientationLine(_ regions: [Region]) -> String {
    var parts = ["orientations"]
    for name in orientations { parts += [name, String(regions.filter { $0.orientation == name }.count)] }
    return parts.joined(separator: " ")
}

final class ImageAnalysis {
    let image: Image
    let setting: Setting
    let histogram: Histogram
    let otsuResult: OtsuResult
    let isodataCutoff: Int
    let isodataIterations: Int
    let cutoff: Int
    var initial: Mask = []
    var finalMask: Mask = []
    var morphCounts: [Int] = []
    var sweep: [(Int, Int, Int)] = []
    var labels: [[Int]] = []
    var provisional = 0
    var regions: [Region] = []
    var fourComponents = 0
    var eightComponents = 0
    var bitQuad = 0
    var holes: [Hole] = []
    var holeOf: [[Int]] = []

    init(_ image: Image, _ setting: Setting, _ parameters: Parameters) {
        self.image = image
        self.setting = setting
        let histogram = Histogram(image)
        self.histogram = histogram
        let otsuResult = otsu(histogram)
        self.otsuResult = otsuResult
        let result = isodata(histogram)
        isodataCutoff = result.cutoff
        isodataIterations = result.iterations
        switch setting.threshold {
        case "otsu": cutoff = otsuResult.cutoff
        case "isodata": cutoff = result.cutoff
        default: cutoff = Int(setting.threshold)!
        }
        initial = binarize(cutoff)
        finalMask = initial
        for operation in setting.operations {
            if operation == "fill" { finalMask = fillHoles(finalMask, 12 - setting.connectivity) }
            else {
                let parts = operation.split(separator: ":").map(String.init)
                let offsets = parameters.elements[parts[1]]!
                switch parts[0] {
                case "erode": finalMask = erode(finalMask, offsets)
                case "dilate": finalMask = dilate(finalMask, offsets)
                case "open": finalMask = opening(finalMask, offsets)
                case "close": finalMask = closing(finalMask, offsets)
                default: preconditionFailure()
                }
            }
            morphCounts.append(countForeground(finalMask))
        }
        for threshold in stride(from: parameters.sweepStep, to: image.maxval, by: parameters.sweepStep) {
            let mask = binarize(threshold)
            sweep.append((threshold, countForeground(mask), labelComponents(mask, setting.connectivity).count))
        }
        let labeled = labelComponents(finalMask, setting.connectivity)
        labels = labeled.labels
        provisional = labeled.provisional
        regions = groupPixels(labels, labeled.count).enumerated().dropFirst().map { Region($0.offset, $0.element) }
        fourComponents = labelComponents(finalMask, 4).count
        eightComponents = labelComponents(finalMask, 8).count
        bitQuad = bitQuadEuler(finalMask, setting.connectivity)
        holeOf = Array(repeating: Array(repeating: 0, count: image.width), count: image.height)
        for pixels in enclosedComponents(finalMask, 12 - setting.connectivity) {
            let first = pixels[0]
            let number = holes.count + 1
            let owner = labels[first.y - 1][first.x]
            for point in pixels { holeOf[point.y][point.x] = number }
            holes.append(Hole(number: number, pixels: pixels, owner: owner))
        }
        for (index, region) in regions.enumerated() {
            let first = region.pixels[0]
            if first.y >= 1 && holeOf[first.y - 1][first.x] > 0 {
                let owner = holes[holeOf[first.y - 1][first.x] - 1].owner - 1
                region.parent = owner
                region.depth = regions[owner].depth + 1
                regions[owner].children.append(index)
            }
        }
        for region in regions { measure(region, parameters) }
    }

    func binarize(_ threshold: Int) -> Mask {
        image.pixels.map { row in row.map { setting.polarity == "bright" ? $0 > Int64(threshold) : $0 <= Int64(threshold) } }
    }
    func labelAt(_ x: Int, _ y: Int) -> Int {
        x >= 0 && x < image.width && y >= 0 && y < image.height ? labels[y][x] : -1
    }
    func chainCode(_ region: Region) -> [Int] {
        let steps = directions(setting.connectivity)
        var visited = [region.pixels[0]]
        var codes: [Int] = []
        var heading = steps.count - 1
        while true {
            let point = visited.last!
            let start = steps.count == 4 ? (heading + 3) % 4 : (heading + (heading % 2 == 0 ? 7 : 6)) % 8
            guard let direction = (0..<steps.count).map({ (start + $0) % steps.count }).first(where: {
                labelAt(point.x + steps[$0].x, point.y + steps[$0].y) == region.number
            }) else { return [] }
            let offset = steps[direction]
            visited.append(Point(point.x + offset.x, point.y + offset.y))
            codes.append(direction)
            heading = direction
            let moves = codes.count
            if moves >= 2 && visited[moves] == visited[1] && visited[moves - 1] == visited[0] { return Array(codes.dropLast()) }
        }
    }
    func measure(_ region: Region, _ parameters: Parameters) {
        let area = Int64(region.pixels.count)
        let box = boxBounds(region.pixels)
        let x0 = box.x0
        let y0 = box.y0
        let x1 = box.x1
        let y1 = box.y1
        for (name, value) in [("area", Int(area)), ("x0", x0), ("y0", y0), ("x1", x1), ("y1", y1),
            ("width", x1 - x0 + 1), ("height", y1 - y0 + 1)] { region.setInt(name, value) }
        let touches = x0 == 0 || y0 == 0 || x1 == image.width - 1 || y1 == image.height - 1
        region.setInt("border", touches ? 1 : 0)
        let values = region.pixels.map { image.pixels[$0.y][$0.x] }
        let sumValues = values.reduce(0, +)
        let sumSquares = values.reduce(Int64(0)) { $0 + $1 * $1 }
        region.set("mean", Rational(sumValues, area))
        region.set("variance", Rational(area * sumSquares - sumValues * sumValues, area * area))
        region.setInt("min", values.min()!)
        region.setInt("max", values.max()!)
        var surrounding: Set<Point> = []
        for point in region.pixels { for offset in eight {
            if labelAt(point.x + offset.x, point.y + offset.y) == 0 { surrounding.insert(Point(point.x + offset.x, point.y + offset.y)) }
        } }
        let count = Int64(surrounding.count)
        let sumSurrounding = surrounding.reduce(Int64(0)) { $0 + image.pixels[$1.y][$1.x] }
        let contrast = count == 0 ? Rational(0) : Rational(sumValues * count - sumSurrounding * area, area * count)
        region.set("contrast", contrast)
        let perimeter = region.pixels.filter { point in
            directions(12 - setting.connectivity).contains { labelAt(point.x + $0.x, point.y + $0.y) != region.number }
        }.count
        region.setInt("perimeter", perimeter)
        region.codes = chainCode(region)
        let straight = setting.connectivity == 4 ? region.codes.count : region.codes.filter { $0 % 2 == 0 }.count
        let diagonal = region.codes.count - straight
        let turns = region.codes.indices.filter { region.codes[$0] != region.codes[($0 + region.codes.count - 1) % region.codes.count] }.count
        for (name, value) in [("chain", region.codes.count), ("straight", straight), ("diagonal", diagonal), ("turns", turns)] { region.setInt(name, value) }
        let length = Int64(5 * straight + 7 * diagonal)
        region.set("compactness", Rational(length * length, 25 * area))
        region.setInt("runs", region.pixels.filter { labelAt($0.x - 1, $0.y) != region.number }.count)
        let owned = holes.filter { $0.owner == region.number }
        region.setInt("holes", owned.count)
        region.setInt("hole_area", owned.reduce(0) { $0 + $1.pixels.count })
        region.setInt("euler", 1 - owned.count)
        region.setInt("depth", region.depth)
        let sumX = region.pixels.reduce(Int64(0)) { $0 + Int64($1.x) }
        let sumY = region.pixels.reduce(Int64(0)) { $0 + Int64($1.y) }
        let sumXX = region.pixels.reduce(Int64(0)) { $0 + Int64($1.x) * Int64($1.x) }
        let sumYY = region.pixels.reduce(Int64(0)) { $0 + Int64($1.y) * Int64($1.y) }
        let sumXY = region.pixels.reduce(Int64(0)) { $0 + Int64($1.x) * Int64($1.y) }
        let m20 = area * sumXX - sumX * sumX
        let m02 = area * sumYY - sumY * sumY
        let m11 = area * sumXY - sumX * sumY
        region.set("cx", Rational(sumX, area))
        region.set("cy", Rational(sumY, area))
        region.set("var_x", Rational(m20, area * area))
        region.set("var_y", Rational(m02, area * area))
        region.set("cov_xy", Rational(m11, area * area))
        region.set("hu1", Rational(m20 + m02, area * area * area))
        let anisotropy = m20 + m02 > 0 ? Rational(abs(m20 - m02) + 2 * abs(m11), m20 + m02) : Rational(0)
        region.set("anisotropy", anisotropy)
        let u = m20 - m02
        let v = 2 * m11
        if anisotropy <= parameters.isotropy { region.orientation = "none" }
        else if abs(v) >= abs(u) { region.orientation = v > 0 ? "falling" : "rising" }
        else { region.orientation = u > 0 ? "horizontal" : "vertical" }
        region.set("extent", Rational(area, Int64((x1 - x0 + 1) * (y1 - y0 + 1))))
        let mirroredLR = region.pixels.filter { labelAt(x0 + x1 - $0.x, $0.y) == region.number }.count
        let mirroredTB = region.pixels.filter { labelAt($0.x, y0 + y1 - $0.y) == region.number }.count
        region.set("mirror_lr", Rational(Int64(mirroredLR), area))
        region.set("mirror_tb", Rational(Int64(mirroredTB), area))
        let hull = convexHull(region.pixels)
        region.hullDoubled = abs(hullEdges(hull).reduce(Int64(0)) { sum, edge in
            sum + Int64(edge.0.x) * Int64(edge.1.y) - Int64(edge.1.x) * Int64(edge.0.y)
        })
        let feret2 = hull.flatMap { a in hull.map { squaredDistance(a, $0) } }.max()!
        let width2 = hullEdges(hull).map { a, b in
            let reach = hull.map { abs(cross(a, b, $0)) }.max()!
            return Rational(reach * reach, squaredDistance(a, b))
        }.min()!
        region.set("solidity", Rational(2 * area, region.hullDoubled))
        region.setInt("feret2", feret2)
        region.set("width2", width2)
        region.set("elongation", Rational(feret2 * width2.denominator, width2.numerator))
        let bayMask: Mask = (y0...y1).map { y in (x0...x1).map { x in
            labels[y][x] == 0 && holeOf[y][x] == 0 && containsCenter(hull, x, y)
        } }
        let bays = labelComponents(bayMask, 12 - setting.connectivity)
        let sizes = groupPixels(bays.labels, bays.count).dropFirst().map(\.count)
        region.setInt("bays", sizes.filter { $0 >= parameters.bayMin }.count)
        region.setInt("bay_area", sizes.reduce(0, +))
        region.skeleton = thin(region.pixels)
        let crossings = region.skeleton.map { crossingNumber(region.skeleton, $0) }
        region.setInt("skeleton", region.skeleton.count)
        region.setInt("endpoints", crossings.filter { $0 == 1 }.count)
        region.setInt("branches", crossings.filter { $0 >= 3 }.count)
    }

    func applyRules(_ rules: Rules) {
        for region in regions {
            region.droppedBy = rules.filters.firstIndex { !$0.holds(region) }
            if region.droppedBy != nil { continue }
            region.kept = true
            if let rule = rules.classes.first(where: { $0.matches(region) }) { region.className = rule.name }
            region.flags = rules.flags.filter { $0.matches(region) }.map(\.name)
        }
        for region in kept {
            let candidates = kept.filter { $0.number != region.number }
            if let neighbor = candidates.min(by: { first, second in
                let a = boxDistance(region, first)
                let b = boxDistance(region, second)
                return a == b ? first.number < second.number : a < b
            }) {
                region.neighbor = neighbor.number
                region.distance = boxDistance(region, neighbor)
            }
        }
    }
    var kept: [Region] { regions.filter(\.kept) }
    func treeText(_ index: Int) -> String {
        let region = regions[index]
        if region.children.isEmpty { return String(region.number) }
        return "\(region.number)(" + region.children.map { treeText($0) }.joined(separator: " ") + ")"
    }
    func thresholdLines(_ top: Int) -> [String] {
        let h = histogram
        var lines = ["image \(image.name) size \(image.width) \(image.height) maxval \(image.maxval)",
            "histogram pixels \(h.pixels) min \(h.minimum) max \(h.maximum) mean \(meanText(h.total, Int(h.pixels))) median \(h.median) mode \(h.mode) levels \(h.levels)",
            "bins " + ([Int64(h.binWidth)] + h.bins).map(String.init).joined(separator: " "),
            "otsu threshold \(otsuResult.cutoff) upper \(otsuResult.upper) candidates \(otsuResult.candidates.count)"]
        for (position, candidate) in otsuResult.candidates.prefix(top).enumerated() {
            let gap = Rational(candidate.sumAbove * candidate.below - candidate.sumBelow * candidate.above, candidate.below * candidate.above)
            lines.append("rank \(position + 1) t \(candidate.cutoff) below \(candidate.below) above \(candidate.above) mean_below \(meanText(candidate.sumBelow, Int(candidate.below))) mean_above \(meanText(candidate.sumAbove, Int(candidate.above))) gap \(decimal(gap, 2))")
        }
        lines.append("isodata threshold \(isodataCutoff) iterations \(isodataIterations)")
        lines.append("threshold \(cutoff) \(setting.method) \(setting.polarity) foreground \(countForeground(initial))")
        for (operation, count) in zip(setting.operations, morphCounts) { lines.append("morph \(operation) foreground \(count)") }
        for (threshold, foreground, regions) in sweep { lines.append("sweep \(threshold) foreground \(foreground) regions \(regions)") }
        return lines
    }
    func regionSymbol(_ x: Int, _ y: Int, _ skeletonOnly: Bool) -> Character {
        let label = labels[y][x]
        if label == 0 { return holeOf[y][x] > 0 ? ":" : "." }
        let region = regions[label - 1]
        if skeletonOnly && !region.skeleton.contains(Point(x, y)) { return "+" }
        return region.kept ? symbols[label % symbols.count] : "#"
    }
    func mapLines() -> [String] {
        let size = "\(image.name) \(image.width) \(image.height)"
        var lines = ["morphology " + size]
        for (initialRow, finalRow) in zip(initial, finalMask) {
            let row: [Character] = zip(initialRow, finalRow).map { before, after in
                if before && after { return "#" }
                if after { return "+" }
                return before ? "-" : "."
            }
            lines.append(String(row))
        }
        for (heading, skeletonOnly) in [("labels", false), ("skeleton", true)] {
            lines.append(heading + " " + size)
            for y in 0..<image.height { lines.append(String((0..<image.width).map { regionSymbol($0, y, skeletonOnly) })) }
        }
        return lines
    }
    func csvRow(_ region: Region) -> String {
        var fields = [image.name, String(region.number), region.className, region.flags.isEmpty ? "-" : region.flags.joined(separator: "+")]
        for name in ["area", "x0", "y0", "x1", "y1"] { fields.append(String(region.integer(name))) }
        for (name, digits) in [("cx", 3), ("cy", 3), ("mean", 2), ("variance", 2)] { fields.append(decimal(region.value(name), digits)) }
        fields += [String(region.integer("min")), String(region.integer("max")), decimal(region.value("contrast"), 2)]
        for name in ["border", "perimeter", "chain", "straight", "diagonal", "turns"] { fields.append(String(region.integer(name))) }
        fields.append(decimal(region.value("compactness"), 3))
        for name in ["runs", "holes", "hole_area", "euler"] { fields.append(String(region.integer(name))) }
        fields.append(region.parent.map { String($0 + 1) } ?? "-")
        fields.append(String(region.depth))
        for (name, digits) in [("var_x", 3), ("var_y", 3), ("cov_xy", 3), ("hu1", 4)] { fields.append(decimal(region.value(name), digits)) }
        fields.append(region.orientation)
        for name in ["anisotropy", "extent", "mirror_lr", "mirror_tb"] { fields.append(decimal(region.value(name), 3)) }
        fields += [hullAreaText(region.hullDoubled), decimal(region.value("solidity"), 3), String(region.integer("feret2")),
            decimal(region.value("width2"), 3), decimal(region.value("elongation"), 3)]
        for name in ["bays", "bay_area", "skeleton", "endpoints", "branches"] { fields.append(String(region.integer(name))) }
        fields.append(region.neighbor.map(String.init) ?? "-")
        fields.append(region.neighbor == nil ? "-" : decimal(Rational(region.distance, 4), 2))
        fields.append(region.codes.isEmpty ? "-" : region.codes.map(String.init).joined())
        return fields.joined(separator: ",")
    }
    func intensityText(_ foreground: Bool) -> String {
        var sum: Int64 = 0
        var count = 0
        for (pixels, mask) in zip(image.pixels, finalMask) {
            for (value, flag) in zip(pixels, mask) where flag == foreground { sum += value; count += 1 }
        }
        return meanText(sum, count)
    }
    func areaLine() -> String {
        let kept = self.kept
        if kept.isEmpty { return "area total 0 mean - largest - smallest -" }
        let area = kept.reduce(Int64(0)) { $0 + $1.integer("area") }
        let largest = kept.min { $0.integer("area") == $1.integer("area") ? $0.number < $1.number : $0.integer("area") > $1.integer("area") }!
        let smallest = kept.min { $0.integer("area") == $1.integer("area") ? $0.number < $1.number : $0.integer("area") < $1.integer("area") }!
        return "area total \(area) mean \(meanText(area, kept.count)) largest \(largest.number) \(largest.integer("area")) smallest \(smallest.number) \(smallest.integer("area"))"
    }
    func summaryLines(_ rules: Rules) -> [String] {
        let kept = self.kept
        let count = regions.count
        let holePixels = holes.reduce(0) { $0 + $1.pixels.count }
        var lines = ["image \(image.name)", "threshold \(cutoff) \(setting.method) \(setting.polarity) conn \(setting.connectivity)",
            "foreground \(countForeground(initial)) \(countForeground(finalMask))",
            "regions \(count) provisional \(provisional) kept \(kept.count) dropped \(count - kept.count)",
            "connectivity four \(fourComponents) eight \(eightComponents)",
            "holes \(holes.count) hole_pixels \(holePixels) euler \(count - holes.count) bitquad \(bitQuad)"]
        for hole in holes {
            let box = boxBounds(hole.pixels)
            lines.append("hole \(hole.number) owner \(hole.owner) area \(hole.pixels.count) box \(box.x0) \(box.y0) \(box.x1) \(box.y1)")
        }
        lines.append("depth_max \(regions.map(\.depth).max() ?? 0)")
        let roots = regions.indices.filter { regions[$0].parent == nil }
        lines.append((["tree"] + roots.map { treeText($0) }).joined(separator: " "))
        lines.append("intensity foreground \(intensityText(true)) background \(intensityText(false))")
        lines.append(areaLine())
        var classes = ["classes"]
        for name in rules.classNames { classes += [name, String(kept.filter { $0.className == name }.count)] }
        lines.append(classes.joined(separator: " "))
        lines.append(orientationLine(kept))
        var flags = ["flags"]
        for rule in rules.flags { flags += [rule.name, String(kept.filter { $0.flags.contains(rule.name) }.count)] }
        lines.append(flags.joined(separator: " "))
        return lines
    }
}

func overallLines(_ analyses: [ImageAnalysis], _ rules: Rules) -> [String] {
    let regions = analyses.flatMap(\.regions)
    let kept = regions.filter(\.kept)
    let holes = analyses.reduce(0) { $0 + $1.holes.count }
    var lines = ["overall", "images \(analyses.count)", "regions \(regions.count) kept \(kept.count) dropped \(regions.count - kept.count)",
        "holes \(holes) euler \(regions.count - holes)"]
    for (index, condition) in rules.filters.enumerated() {
        lines.append("filter \(index + 1) \(condition.words) dropped \(regions.filter { $0.droppedBy == index }.count)")
    }
    for name in rules.classNames {
        let members = kept.filter { $0.className == name }
        let area = members.reduce(Int64(0)) { $0 + $1.integer("area") }
        lines.append("class \(name) count \(members.count) area \(area) mean \(meanText(area, members.count))")
    }
    for rule in rules.flags { lines.append("flag \(rule.name) count \(kept.filter { $0.flags.contains(rule.name) }.count)") }
    lines.append(orientationLine(kept))
    var largest: (name: String, region: Region)? = nil
    for analysis in analyses { for region in analysis.kept {
        if largest == nil || region.integer("area") > largest!.region.integer("area") { largest = (analysis.image.name, region) }
    } }
    if let largest { lines.append("largest \(largest.name) \(largest.region.number) \(largest.region.integer("area"))") }
    else { lines.append("largest -") }
    return lines
}

let parameters = try readParameters("input/params.txt")
let rules = try readRules("input/rules.txt")
var analyses: [ImageAnalysis] = []
for image in try readImages("input/images.txt") {
    let analysis = ImageAnalysis(image, parameters.settings[image.name]!, parameters)
    analysis.applyRules(rules)
    analyses.append(analysis)
}
var thresholds: [String] = []
var maps: [String] = []
var rows = [csvHeader]
var summary: [String] = []
for analysis in analyses {
    thresholds += analysis.thresholdLines(parameters.otsuTop)
    maps += analysis.mapLines()
    rows += analysis.kept.map { analysis.csvRow($0) }
    summary += analysis.summaryLines(rules)
}
summary += overallLines(analyses, rules)
try writeFiles("output", [("thresholds.txt", thresholds), ("labels.txt", maps), ("regions.csv", rows), ("summary.txt", summary)])
