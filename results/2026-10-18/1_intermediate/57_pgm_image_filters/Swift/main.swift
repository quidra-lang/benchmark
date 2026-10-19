import Foundation

struct Point: Hashable, Sendable {
    let x: Int
    let y: Int
}

struct Command {
    let name: String
    let numbers: [Int]
    let slot: String
    let fill: Bool
}

struct CommandError: Error {
    let reason: String
}

func require(_ condition: @autoclosure () -> Bool, _ reason: String = "bad value") throws {
    if !condition() {
        throw CommandError(reason: reason)
    }
}

func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
    min(max(value, low), high)
}

func floorDivide(_ value: Int, _ divisor: Int) -> Int {
    value >= 0 ? value / divisor : -((-value + divisor - 1) / divisor)
}

func digits(_ word: String) -> Bool {
    !word.isEmpty && word.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
}

func integerWord(_ word: String) -> Bool {
    if word == "0" { return true }
    let positive = word.first == "-" ? String(word.dropFirst()) : word
    return positive.count >= 1 && positive.count <= 7 &&
        positive.first != "0" && digits(positive)
}

func slotWord(_ word: String) -> Bool {
    word.count >= 1 && word.count <= 8 &&
        word.utf8.allSatisfy { $0 >= 97 && $0 <= 122 }
}

func withinLimit(_ values: [Int]) -> Bool {
    values.allSatisfy { (-1000...1000).contains($0) }
}

let neighbors4 = [Point(x: 0, y: -1), Point(x: -1, y: 0),
                  Point(x: 1, y: 0), Point(x: 0, y: 1)]

let neighbors8 = [
    Point(x: -1, y: -1), Point(x: 0, y: -1), Point(x: 1, y: -1),
    Point(x: -1, y: 0), Point(x: 1, y: 0),
    Point(x: -1, y: 1), Point(x: 0, y: 1), Point(x: 1, y: 1)
]

struct Image {
    let width: Int
    let height: Int
    let maxval: Int
    let pixels: [Int]

    func get(_ x: Int, _ y: Int) -> Int {
        pixels[y * width + x]
    }

    func contains(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    func clamped(_ value: Int) -> Int {
        clamp(value, 0, maxval)
    }

    func withPixels(_ values: [Int]) -> Image {
        Image(width: width, height: height, maxval: maxval, pixels: values)
    }

    func mapped(_ transform: (Int) -> Int) -> Image {
        withPixels(pixels.map(transform))
    }

    func neighborhood(_ x: Int, _ y: Int) -> [Int] {
        var result = [Int]()
        result.reserveCapacity(9)
        for dy in -1...1 {
            for dx in -1...1 {
                result.append(get(clamp(x + dx, 0, width - 1),
                                  clamp(y + dy, 0, height - 1)))
            }
        }
        return result
    }

    func summary() -> String {
        let checksum = pixels.enumerated().reduce(Int64(0)) {
            $0 + Int64($1.offset + 1) * Int64($1.element)
        }
        return "\(width)x\(height) maxval \(maxval) checksum \(checksum)"
    }
}

func parsePGM(_ lines: [String]) throws -> Image {
    var words = [String]()
    for line in lines {
        let uncommented = line.split(separator: "#", maxSplits: 1,
                                     omittingEmptySubsequences: false).first ?? ""
        words.append(contentsOf: uncommented.split(separator: " ").map(String.init))
    }

    try require(!words.isEmpty && words[0] == "P2", "bad magic")

    func header(_ index: Int, _ maximum: Int, _ reason: String) throws -> Int {
        try require(index < words.count, "truncated header")
        try require(digits(words[index]), "bad number")
        let number = Int(words[index])!
        try require(number >= 1 && number <= maximum, reason)
        return number
    }

    let width = try header(1, 64, "bad size")
    let height = try header(2, 64, "bad size")
    let maxval = try header(3, 255, "bad maxval")
    let count = words.count - 4
    let required = width * height
    var pixels = [Int]()
    pixels.reserveCapacity(required)

    for i in 0..<required {
        let x = i % width, y = i / width
        try require(i < count, "too few pixels (\(count) of \(required))")
        let word = words[i + 4]
        try require(digits(word), "bad pixel at \(x),\(y)")
        let value = Int(word)!
        try require(value <= maxval, "pixel out of range at \(x),\(y)")
        pixels.append(value)
    }

    try require(count <= required, "too many pixels (\(count) of \(required))")
    return Image(width: width, height: height, maxval: maxval, pixels: pixels)
}

func transformed(
    _ image: Image, _ width: Int, _ height: Int,
    _ sample: (Int, Int) -> Int
) -> Image {
    var pixels = [Int]()
    pixels.reserveCapacity(width * height)
    for y in 0..<height {
        for x in 0..<width {
            pixels.append(sample(x, y))
        }
    }
    return Image(width: width, height: height, maxval: image.maxval, pixels: pixels)
}

func cropped(_ image: Image, _ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Image {
    transformed(image, w, h) { i, j in image.get(x + i, y + j) }
}

func translated(
    _ image: Image, _ width: Int, _ height: Int,
    _ dx: Int, _ dy: Int, _ fill: Int
) -> Image {
    transformed(image, width, height) { x, y in
        image.contains(x - dx, y - dy) ? image.get(x - dx, y - dy) : fill
    }
}

func convolution(_ image: Image, _ kernel: [Int], _ divisor: Int) -> Image {
    transformed(image, image.width, image.height) { x, y in
        let q = image.neighborhood(x, y)
        var total = 0
        for i in 0..<9 { total += q[i] * kernel[i] }
        return image.clamped(floorDivide(total, divisor))
    }
}

func rankFiltered(_ image: Image, _ index: Int) -> Image {
    transformed(image, image.width, image.height) { x, y in
        image.neighborhood(x, y).sorted()[index]
    }
}

func sobel(_ image: Image) -> Image {
    transformed(image, image.width, image.height) { x, y in
        let q = image.neighborhood(x, y)
        let gx = q[2] + 2 * q[5] + q[8] - q[0] - 2 * q[3] - q[6]
        let gy = q[6] + 2 * q[7] + q[8] - q[0] - 2 * q[1] - q[2]
        return image.clamped(abs(gx) + abs(gy))
    }
}

func linePoints(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> [Point] {
    let dx = abs(x1 - x0), dy = -abs(y1 - y0)
    let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
    var error = dx + dy
    var x = x0, y = y0
    var points = [Point]()
    while true {
        points.append(Point(x: x, y: y))
        if x == x1 && y == y1 { break }
        let twice = 2 * error
        if twice >= dy { error += dy; x += sx }
        if twice <= dx { error += dx; y += sy }
    }
    return points
}

func rectanglePoints(
    _ image: Image, _ left: Int, _ top: Int,
    _ width: Int, _ height: Int, _ fill: Bool
) -> [Point] {
    let right = left + width - 1, bottom = top + height - 1
    var points = [Point]()
    let firstY = max(top, 0), lastY = min(bottom, image.height - 1)
    let firstX = max(left, 0), lastX = min(right, image.width - 1)
    if firstX > lastX || firstY > lastY { return points }
    for y in firstY...lastY {
        for x in firstX...lastX {
            if fill || x == left || x == right || y == top || y == bottom {
                points.append(Point(x: x, y: y))
            }
        }
    }
    return points
}

func circlePoints(_ cx: Int, _ cy: Int, _ radius: Int) -> [Point] {
    var a = radius, b = 0, error = 1 - radius
    var points = [Point]()
    while a >= b {
        points.append(contentsOf: [
            Point(x: cx + a, y: cy + b), Point(x: cx + b, y: cy + a),
            Point(x: cx - b, y: cy + a), Point(x: cx - a, y: cy + b),
            Point(x: cx - a, y: cy - b), Point(x: cx - b, y: cy - a),
            Point(x: cx + b, y: cy - a), Point(x: cx + a, y: cy - b)
        ])
        b += 1
        if error < 0 { error += 2 * b + 1 }
        else { a -= 1; error += 2 * (b - a) + 1 }
    }
    return points
}

func discPoints(_ image: Image, _ outline: [Point]) -> [Point] {
    var rows = [Int: (left: Int, right: Int)]()
    for p in outline {
        if let limits = rows[p.y] {
            rows[p.y] = (min(limits.left, p.x), max(limits.right, p.x))
        } else {
            rows[p.y] = (p.x, p.x)
        }
    }
    var points = [Point]()
    for (y, limits) in rows {
        if y < 0 || y >= image.height { continue }
        let first = max(0, limits.left)
        let last = min(image.width - 1, limits.right)
        if first <= last {
            for x in first...last { points.append(Point(x: x, y: y)) }
        }
    }
    return points
}

func floodPoints(_ image: Image, _ x: Int, _ y: Int) -> [Point] {
    let target = image.get(x, y)
    var stack = [Point(x: x, y: y)]
    var seen: Set<Int> = [y * image.width + x]
    var result = [Point]()
    while let p = stack.popLast() {
        result.append(p)
        for d in neighbors4 {
            let nx = p.x + d.x, ny = p.y + d.y
            if !image.contains(nx, ny) || image.get(nx, ny) != target { continue }
            let index = ny * image.width + nx
            if seen.insert(index).inserted {
                stack.append(Point(x: nx, y: ny))
            }
        }
    }
    return result
}

func equalized(_ image: Image) -> Image {
    var counts = [Int](repeating: 0, count: image.maxval + 1)
    for pixel in image.pixels { counts[pixel] += 1 }
    var accumulated = 0
    let cdf = counts.map { count -> Int in
        accumulated += count
        return accumulated
    }
    let size = image.pixels.count
    let minimum = cdf[image.pixels.min()!]
    if minimum == size { return image.withPixels(image.pixels) }
    let span = size - minimum
    return image.mapped {
        (2 * (cdf[$0] - minimum) * image.maxval + span) / (2 * span)
    }
}

func components(_ image: Image, _ threshold: Int) -> [[Point]] {
    var visited = [Bool](repeating: false, count: image.pixels.count)
    var groups = [[Point]]()
    for start in image.pixels.indices {
        if visited[start] || image.pixels[start] < threshold { continue }
        visited[start] = true
        var stack = [Point(x: start % image.width, y: start / image.width)]
        var group = [Point]()
        while let p = stack.popLast() {
            group.append(p)
            for d in neighbors8 {
                let nx = p.x + d.x, ny = p.y + d.y
                if !image.contains(nx, ny) { continue }
                let index = ny * image.width + nx
                if !visited[index] && image.pixels[index] >= threshold {
                    visited[index] = true
                    stack.append(Point(x: nx, y: ny))
                }
            }
        }
        groups.append(group)
    }
    return groups
}

func componentText(_ image: Image, _ threshold: Int, _ group: [Point]) -> String {
    var minX = group[0].x, maxX = group[0].x
    var minY = group[0].y, maxY = group[0].y
    var sumX = 0, sumY = 0, perimeter = 0
    for p in group {
        minX = min(minX, p.x); maxX = max(maxX, p.x)
        minY = min(minY, p.y); maxY = max(maxY, p.y)
        sumX += p.x; sumY += p.y
        if neighbors4.contains(where: {
            !image.contains(p.x + $0.x, p.y + $0.y) ||
                image.get(p.x + $0.x, p.y + $0.y) < threshold
        }) { perimeter += 1 }
    }
    let area = group.count
    return "area \(area) perimeter \(perimeter) box \(minX) \(minY) \(maxX) \(maxY) " +
           "center \(sumX / area) \(sumY / area)"
}

func distanceMap(_ image: Image, _ threshold: Int) -> Image {
    if image.pixels.allSatisfy({ $0 >= threshold }) {
        return image.withPixels([Int](repeating: image.maxval, count: image.pixels.count))
    }
    let w = image.width, h = image.height, far = w + h
    var distances = image.pixels.map { $0 < threshold ? 0 : far }
    for y in 0..<h {
        for x in 0..<w {
            let index = y * w + x
            if x > 0 { distances[index] = min(distances[index], distances[index - 1] + 1) }
            if y > 0 { distances[index] = min(distances[index], distances[index - w] + 1) }
        }
    }
    for y in stride(from: h - 1, through: 0, by: -1) {
        for x in stride(from: w - 1, through: 0, by: -1) {
            let index = y * w + x
            if x < w - 1 { distances[index] = min(distances[index], distances[index + 1] + 1) }
            if y < h - 1 { distances[index] = min(distances[index], distances[index + w] + 1) }
        }
    }
    return image.withPixels(distances.map { min($0, image.maxval) })
}

func statistics(_ pixels: [Int], _ maxval: Int) -> String {
    let sorted = pixels.sorted()
    var counts = [Int](repeating: 0, count: maxval + 1)
    var total = 0
    for p in pixels { counts[p] += 1; total += p }
    var mode = 0
    for p in 1...maxval {
        if counts[p] > counts[mode] { mode = p }
    }
    return "min \(sorted.first!) max \(sorted.last!) mean \(total / pixels.count) " +
           "median \(sorted[(pixels.count - 1) / 2]) mode \(mode)"
}

func dithered(_ image: Image) -> Image {
    var errors = image.pixels
    var pixels = [Int](repeating: 0, count: errors.count)
    let offsets = [(1, 0, 7), (-1, 1, 3), (0, 1, 5), (1, 1, 1)]
    for y in 0..<image.height {
        for x in 0..<image.width {
            let index = y * image.width + x
            let old = errors[index]
            let value = 2 * old >= image.maxval ? image.maxval : 0
            pixels[index] = value
            let error = old - value
            for (dx, dy, weight) in offsets {
                if image.contains(x + dx, y + dy) {
                    errors[(y + dy) * image.width + x + dx] += floorDivide(error * weight, 16)
                }
            }
        }
    }
    return image.withPixels(pixels)
}

struct Editor {
    private static let patterns: [String: String] = [
        "NEW": "iiii", "OUTPUT": "", "INVERT": "", "BRIGHTNESS": "i",
        "CONTRAST": "ii", "THRESHOLD": "i", "LEVELS": "ii",
        "POSTERIZE": "i", "MAXVAL": "i", "FLIPH": "", "FLIPV": "",
        "ROTATE": "i", "CROP": "iiii", "PAD": "ii", "SCALE": "ii",
        "SHIFT": "iii", "TILE": "ii", "BLUR": "", "GAUSS": "",
        "SHARPEN": "", "CONVOLVE": "iiiiiiiiii", "SOBEL": "",
        "MEDIAN": "", "ERODE": "", "DILATE": "", "OPEN": "",
        "CLOSE": "", "GRADIENT": "", "LINE": "iiiii", "RECT": "iiiii",
        "CIRCLE": "iiii", "FLOOD": "iii", "HISTOGRAM": "",
        "EQUALIZE": "", "LABEL": "i", "DISTANCE": "i",
        "STATS": "", "REGION": "iiii", "DITHER": "", "ASCIIART": "",
        "STORE": "n", "RECALL": "n", "DROP": "n", "BLEND": "nii",
        "DIFF": "n", "PASTE": "nii", "SLOTS": "", "INFO": "",
        "UNDO": "", "REDO": ""
    ]
    private static let imageless: Set<String> = [
        "NEW", "RECALL", "DROP", "SLOTS", "INFO", "UNDO", "REDO"
    ]
    private static let needsSlot: Set<String> = [
        "RECALL", "DROP", "BLEND", "DIFF", "PASTE"
    ]
    private static let kernels: [String: ([Int], Int)] = [
        "BLUR": ([1, 1, 1, 1, 1, 1, 1, 1, 1], 9),
        "GAUSS": ([1, 2, 1, 2, 4, 2, 1, 2, 1], 16),
        "SHARPEN": ([0, -1, 0, -1, 5, -1, 0, -1, 0], 1)
    ]

    private var current: Image?
    private var undo = [Image]()
    private var redo = [Image]()
    private var slots = [String: Image]()
    private(set) var output = [String]()

    private mutating func emit(_ text: String) {
        output.append(text)
    }

    private func parse(_ words: [String]) throws -> Command {
        let name = words[0]
        guard let pattern = Self.patterns[name] else {
            throw CommandError(reason: "unknown command " + name)
        }
        var given = Array(words.dropFirst())
        let fill = (name == "RECT" || name == "CIRCLE") &&
            given.count == pattern.count + 1 && given.last == "FILL"
        if fill { given.removeLast() }
        try require(given.count == pattern.count, "bad arguments")

        let types = Array(pattern)
        var numbers = [Int]()
        var slot = ""
        for (index, word) in given.enumerated() {
            if types[index] == "i" {
                try require(integerWord(word), "bad arguments")
                numbers.append(Int(word)!)
            } else {
                try require(slotWord(word), "bad arguments")
                slot = word
            }
        }
        return Command(name: name, numbers: numbers, slot: slot, fill: fill)
    }

    mutating func execute(_ words: [String]) {
        do {
            let command = try parse(words)
            if !Self.imageless.contains(command.name) {
                try require(current != nil, "no image")
            }
            if Self.needsSlot.contains(command.name) {
                try require(slots[command.slot] != nil, "no slot " + command.slot)
            }
            try run(command)
        } catch let e as CommandError {
            emit("error: " + e.reason)
        } catch {
            fatalError("Unexpected error: \(error)")
        }
    }

    mutating func load(_ lines: [String]) {
        do { replace(try parsePGM(lines), "loaded") }
        catch let e as CommandError { emit("error: load: " + e.reason) }
        catch { fatalError("Unexpected error: \(error)") }
    }

    private mutating func replace(_ image: Image, _ label: String) {
        current = image
        undo.removeAll()
        redo.removeAll()
        emit(label + " " + image.summary())
    }

    private mutating func commit(_ image: Image, _ painted: Int? = nil) {
        undo.append(current!)
        redo.removeAll()
        current = image
        emit("ok " + image.summary() + (painted.map { " painted \($0)" } ?? ""))
    }

    private mutating func paint(_ image: Image, _ points: [Point], _ value: Int) {
        var painted = Set<Int>()
        for p in points where image.contains(p.x, p.y) {
            painted.insert(p.y * image.width + p.x)
        }
        var pixels = image.pixels
        for index in painted { pixels[index] = value }
        commit(image.withPixels(pixels), painted.count)
    }

    private func checkedCrop(_ a: [Int], _ image: Image) throws {
        try require(a[0] >= 0 && a[1] >= 0 && a[2] >= 1 && a[3] >= 1)
        try require(a[0] + a[2] <= image.width && a[1] + a[3] <= image.height)
    }

    private func matchingSlot(_ image: Image, _ name: String) throws -> Image {
        let saved = slots[name]!
        try require(saved.width == image.width && saved.height == image.height,
                    "size mismatch")
        try require(saved.maxval == image.maxval, "maxval mismatch")
        return saved
    }

    private mutating func run(_ command: Command) throws {
        let a = command.numbers
        let name = command.name, slot = command.slot, fill = command.fill

        switch name {
        case "NEW":
            try require(a[0] >= 1 && a[0] <= 64 && a[1] >= 1 && a[1] <= 64)
            try require(a[2] >= 1 && a[2] <= 255 && a[3] >= 0 && a[3] <= a[2])
            replace(Image(width: a[0], height: a[1], maxval: a[2],
                          pixels: [Int](repeating: a[3], count: a[0] * a[1])), "created")
            return
        case "RECALL":
            replace(slots[slot]!, "recalled " + slot)
            return
        case "DROP":
            slots.removeValue(forKey: slot)
            emit("dropped " + slot)
            return
        case "SLOTS":
            if slots.isEmpty { emit("no slots") }
            for key in slots.keys.sorted() { emit(key + " " + slots[key]!.summary()) }
            return
        case "INFO":
            emit("image " + (current?.summary() ?? "none") +
                 " undo \(undo.count) redo \(redo.count) slots \(slots.count)")
            return
        case "UNDO":
            try require(!undo.isEmpty, "nothing to undo")
            redo.append(current!)
            current = undo.removeLast()
            emit("undo " + current!.summary())
            return
        case "REDO":
            try require(!redo.isEmpty, "nothing to redo")
            undo.append(current!)
            current = redo.removeLast()
            emit("redo " + current!.summary())
            return
        default:
            break
        }

        let image = current!
        let w = image.width, h = image.height, m = image.maxval
        switch name {
        case "OUTPUT":
            emit("P2")
            emit("\(w) \(h)")
            emit(String(m))
            for y in 0..<h {
                emit((0..<w).map { String(image.get($0, y)) }.joined(separator: " "))
            }
        case "INVERT":
            commit(image.mapped { m - $0 })
        case "BRIGHTNESS":
            try require((-255...255).contains(a[0]))
            commit(image.mapped { image.clamped($0 + a[0]) })
        case "CONTRAST":
            try require((0...100).contains(a[0]) && (1...100).contains(a[1]))
            let center = (m + 1) / 2
            commit(image.mapped { image.clamped(center + floorDivide(($0 - center) * a[0], a[1])) })
        case "THRESHOLD":
            try require((0...m).contains(a[0]))
            commit(image.mapped { $0 >= a[0] ? m : 0 })
        case "LEVELS":
            try require(a[0] >= 0 && a[0] < a[1] && a[1] <= m)
            commit(image.mapped { image.clamped(floorDivide(($0 - a[0]) * m, a[1] - a[0])) })
        case "POSTERIZE":
            try require((2...(m + 1)).contains(a[0]))
            commit(image.mapped { (($0 * a[0]) / (m + 1)) * m / (a[0] - 1) })
        case "MAXVAL":
            try require((1...255).contains(a[0]))
            commit(Image(width: w, height: h, maxval: a[0],
                         pixels: image.pixels.map { (2 * $0 * a[0] + m) / (2 * m) }))
        case "FLIPH":
            commit(transformed(image, w, h) { x, y in image.get(w - 1 - x, y) })
        case "FLIPV":
            commit(transformed(image, w, h) { x, y in image.get(x, h - 1 - y) })
        case "ROTATE":
            try require([90, 180, 270].contains(a[0]))
            switch a[0] {
            case 90: commit(transformed(image, h, w) { x, y in image.get(y, h - 1 - x) })
            case 180: commit(transformed(image, w, h) {
                x, y in image.get(w - 1 - x, h - 1 - y)
            })
            default: commit(transformed(image, h, w) { x, y in image.get(w - 1 - y, x) })
            }
        case "CROP":
            try checkedCrop(a, image)
            commit(cropped(image, a[0], a[1], a[2], a[3]))
        case "PAD":
            try require(a[0] >= 1 && a[1] >= 0 && a[1] <= m)
            try require(w + 2 * a[0] <= 64 && h + 2 * a[0] <= 64, "too large")
            commit(translated(image, w + 2 * a[0], h + 2 * a[0], a[0], a[0], a[1]))
        case "SCALE":
            try require((1...16).contains(a[0]) && (1...16).contains(a[1]))
            let newWidth = w * a[0] / a[1], newHeight = h * a[0] / a[1]
            try require(newWidth > 0 && newHeight > 0, "too small")
            try require(newWidth <= 64 && newHeight <= 64, "too large")
            commit(transformed(image, newWidth, newHeight) { x, y in
                image.get((2 * x + 1) * a[1] / (2 * a[0]),
                          (2 * y + 1) * a[1] / (2 * a[0]))
            })
        case "SHIFT":
            try require(withinLimit(Array(a.prefix(2))) && a[2] >= 0 && a[2] <= m)
            commit(translated(image, w, h, a[0], a[1], a[2]))
        case "TILE":
            try require(a[0] >= 1 && a[1] >= 1)
            try require(w * a[0] <= 64 && h * a[1] <= 64, "too large")
            commit(transformed(image, w * a[0], h * a[1]) {
                x, y in image.get(x % w, y % h)
            })
        case "BLUR", "GAUSS", "SHARPEN":
            let (kernel, divisor) = Self.kernels[name]!
            commit(convolution(image, kernel, divisor))
        case "CONVOLVE":
            try require(a.prefix(9).allSatisfy { (-16...16).contains($0) } &&
                        (1...256).contains(a[9]))
            commit(convolution(image, Array(a.prefix(9)), a[9]))
        case "SOBEL":
            commit(sobel(image))
        case "MEDIAN":
            commit(rankFiltered(image, 4))
        case "ERODE":
            commit(rankFiltered(image, 0))
        case "DILATE":
            commit(rankFiltered(image, 8))
        case "OPEN":
            commit(rankFiltered(rankFiltered(image, 0), 8))
        case "CLOSE":
            commit(rankFiltered(rankFiltered(image, 8), 0))
        case "GRADIENT":
            let high = rankFiltered(image, 8).pixels
            let low = rankFiltered(image, 0).pixels
            commit(image.withPixels(zip(high, low).map { $0 - $1 }))
        case "LINE":
            try require(withinLimit(Array(a.prefix(4))) && a[4] >= 0 && a[4] <= m)
            paint(image, linePoints(a[0], a[1], a[2], a[3]), a[4])
        case "RECT":
            try require(withinLimit(Array(a.prefix(2))) &&
                        (1...1000).contains(a[2]) && (1...1000).contains(a[3]) &&
                        a[4] >= 0 && a[4] <= m)
            paint(image, rectanglePoints(image, a[0], a[1], a[2], a[3], fill), a[4])
        case "CIRCLE":
            try require(withinLimit(Array(a.prefix(2))) &&
                        (0...1000).contains(a[2]) && a[3] >= 0 && a[3] <= m)
            let outline = circlePoints(a[0], a[1], a[2])
            paint(image, fill ? discPoints(image, outline) : outline, a[3])
        case "FLOOD":
            try require(image.contains(a[0], a[1]) && a[2] >= 0 && a[2] <= m)
            paint(image, floodPoints(image, a[0], a[1]), a[2])
        case "HISTOGRAM":
            var lows = [Int?](repeating: nil, count: 16)
            var highs = [Int](repeating: 0, count: 16)
            var counts = [Int](repeating: 0, count: 16)
            for value in 0...m {
                let bin = value * 16 / (m + 1)
                if lows[bin] == nil { lows[bin] = value }
                highs[bin] = value
            }
            for p in image.pixels { counts[p * 16 / (m + 1)] += 1 }
            let top = counts.max()!
            for bin in 0..<16 {
                if let low = lows[bin] {
                    let hashes = String(repeating: "#", count: counts[bin] * 32 / top)
                    emit(String(format: "%3d-%3d %4d |%@", low, highs[bin], counts[bin], hashes))
                }
            }
        case "EQUALIZE":
            commit(equalized(image))
        case "LABEL":
            try require(a[0] >= 0 && a[0] <= m)
            let groups = components(image, a[0])
            emit("labels \(groups.count)")
            for (index, group) in groups.enumerated() {
                emit("label \(index + 1) " + componentText(image, a[0], group))
            }
        case "DISTANCE":
            try require(a[0] >= 0 && a[0] <= m)
            commit(distanceMap(image, a[0]))
        case "STATS":
            emit(statistics(image.pixels, m))
        case "REGION":
            try checkedCrop(a, image)
            emit(statistics(cropped(image, a[0], a[1], a[2], a[3]).pixels, m))
        case "DITHER":
            commit(dithered(image))
        case "ASCIIART":
            let shades = Array("@#*+=~-:,.")
            for y in 0..<h {
                var line = ""
                for x in 0..<w {
                    line.append(shades[image.get(x, y) * 10 / (m + 1)])
                }
                emit(line)
            }
        case "STORE":
            slots[slot] = image
            emit("stored " + slot + " " + image.summary())
        case "BLEND":
            try require(a[0] >= 0 && a[0] <= a[1] && (1...100).contains(a[1]))
            let saved = try matchingSlot(image, slot)
            commit(image.withPixels(image.pixels.enumerated().map {
                ($0.element * (a[1] - a[0]) + saved.pixels[$0.offset] * a[0]) / a[1]
            }))
        case "DIFF":
            let saved = try matchingSlot(image, slot)
            commit(image.withPixels(image.pixels.enumerated().map {
                abs($0.element - saved.pixels[$0.offset])
            }))
        case "PASTE":
            try require(withinLimit(a))
            let saved = slots[slot]!
            try require(saved.maxval == m, "maxval mismatch")
            var pixels = image.pixels
            var painted = 0
            for y in 0..<saved.height {
                for x in 0..<saved.width {
                    if image.contains(a[0] + x, a[1] + y) {
                        pixels[(a[1] + y) * w + a[0] + x] = saved.get(x, y)
                        painted += 1
                    }
                }
            }
            commit(image.withPixels(pixels), painted)
        default:
            break
        }
    }
}

let text = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)!
let input = text.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
let lines = input.components(separatedBy: "\n")
var position = 0
let commands = Int(lines[position])!
position += 1
var editor = Editor()
for _ in 0..<commands {
    let words = lines[position].split(separator: " ").map(String.init)
    position += 1
    if words[0] == "LOAD" {
        let count = Int(words[1])!
        editor.load(Array(lines[position..<(position + count)]))
        position += count
    } else {
        editor.execute(words)
    }
}
for line in editor.output { print(line) }
