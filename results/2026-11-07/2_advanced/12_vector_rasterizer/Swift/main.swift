import Foundation

let penCommands: Set<String> = ["LINE", "RECT", "CIRCLE", "ELLIPSE", "POLYLINE", "POLYGON", "PATH"]
let brushCommands: Set<String> = ["FILLRECT", "FILLCIRCLE", "FILLELLIPSE", "FILLPOLYGON", "FILLPATH", "FLOOD", "TEXT"]
let stateCommands: Set<String> = ["TRANSLATE", "SCALE", "ROTATE", "SAVE", "RESTORE", "CLIP", "NOCLIP", "USE"]
let errorNames = ["unknown_command", "bad_arguments", "unknown_style", "unknown_symbol", "unknown_glyph", "bad_value", "stack_empty"]
let pathArities = ["M": 2, "m": 2, "L": 2, "l": 2, "H": 1, "h": 1, "V": 1, "v": 1, "Q": 4, "q": 4, "C": 6, "c": 6, "Z": 0, "z": 0]
struct Pen { let width: Int; let color: String; let on: Int; let off: Int }
struct Brush { let colors: [String]; let axis: String; let rule: String }
struct Styles { var colors: [String: Color] = [:]; var pens: [String: Pen] = [:]; var brushes: [String: Brush] = [:] }
struct Font { let width: Int; let height: Int; let glyphs: [Character: [Point]] }
struct Command { let line: Int; let keyword: String; let arguments: [String]; func n(_ index: Int) -> Int { Int(arguments[index])! } }
indirect enum Instruction { case command(Command); case repeatBlock(Int, Int, Int, [Instruction]) }
struct LayerBlock { let name: String; let opacity: Int; let mode: String; let body: [Instruction] }
struct Symbol { let body: [Instruction]; let endLine: Int }
struct Scene { let width: Int; let height: Int; let background: String; let layers: [LayerBlock]; let symbols: [String: Symbol] }
struct SourceLine { let number: Int; let words: [String] }
struct Probe { let kind: String; let values: [Int] }
struct PathCommand { let letter: String; let values: [Int] }
struct Subpath { var points: [Point]; var closed = false }
struct Execution { let layer: Int; let command: Command; let kind: String; let error: String; let pixels: Int; let box: String }
struct KeywordTally { var executed = 0; var errors = 0; var pixels = 0 }
func readLines(_ path: String) throws -> [String] { var lines = try String(contentsOfFile: path, encoding: .utf8).components(separatedBy: "\n"); if lines.last == "" { lines.removeLast() }; return lines }
func readStyles() throws -> Styles {
    var styles = Styles()
    for line in try readLines("input/styles.txt") where !line.isEmpty && !line.hasPrefix("#") {
        let words = line.split(separator: " ").map(String.init)
        switch words[0] {
        case "color": styles.colors[words[1]] = Color(words.dropFirst(2).map { Int($0)! })
        case "pen": styles.pens[words[1]] = Pen(width: Int(words[2])!, color: words[3], on: Int(words[4])!, off: Int(words[5])!)
        case "brush": styles.brushes[words[1]] = Brush(colors: [words[2]], axis: "", rule: words[3])
        default: styles.brushes[words[1]] = Brush(colors: [words[2], words[3]], axis: words[4], rule: words[5])
        }
    }
    return styles
}
func readFont() throws -> Font {
    let lines = try readLines("input/font.txt"), header = lines[0].split(separator: " "), width = Int(header[1])!, height = Int(header[2])!
    var glyphs: [Character: [Point]] = [:], position = 1
    while position < lines.count { let character = lines[position].last!; position += 1; var points: [Point] = []; for row in 0..<height { for (column, value) in lines[position + row].enumerated() where value == "#" { points.append(Point(x: column, y: row)) } }; position += height; glyphs[character] = points }
    return Font(width: width, height: height, glyphs: glyphs)
}
func readScene() throws -> Scene {
    let lines = try readLines("input/scene.txt").enumerated().compactMap { index, line -> SourceLine? in let words = line.split(separator: " ").map(String.init); return words.isEmpty || words[0].hasPrefix("#") ? nil : SourceLine(number: index + 1, words: words) }
    let header = lines[0].words
    var position = 1, layers: [LayerBlock] = [], symbols: [String: Symbol] = [:]
    func body(_ terminator: String) -> ([Instruction], Int) {
        var result: [Instruction] = []
        while lines[position].words[0] != terminator {
            let source = lines[position], words = lines[position].words
            position += 1
            if words[0] == "REPEAT" { let (nested, _) = body("ENDREPEAT"); result.append(.repeatBlock(Int(words[1])!, Int(words[2])!, Int(words[3])!, nested)) }
            else { result.append(.command(Command(line: source.number, keyword: words[0], arguments: Array(words.dropFirst())))) }
        }
        let end = lines[position].number; position += 1
        return (result, end)
    }
    while position < lines.count {
        let words = lines[position].words; position += 1
        let (contents, end) = body("END")
        if words[0] == "LAYER" { layers.append(LayerBlock(name: words[1], opacity: Int(words[2])!, mode: words[3], body: contents)) }
        else { symbols[words[1]] = Symbol(body: contents, endLine: end) }
    }
    return Scene(width: Int(header[1])!, height: Int(header[2])!, background: header[3], layers: layers, symbols: symbols)
}
func readProbes() throws -> [Probe] { try readLines("input/probes.txt").dropFirst().map { line in let words = line.split(separator: " ").map(String.init); return Probe(kind: words[0], values: words.dropFirst().map { Int($0)! }) } }
func integerWord(_ text: String) -> Bool { let digits = text.hasPrefix("-") ? text.dropFirst() : text[...]; return !digits.isEmpty && digits.utf8.allSatisfy { (48...57).contains($0) } }
func parsePath(_ words: [String]) -> [PathCommand]? {
    var result: [PathCommand] = [], position = 0
    while position < words.count {
        let letter = words[position]
        guard let count = pathArities[letter], position + count < words.count else { return nil }
        let values = words[(position + 1)..<(position + count + 1)]
        if !values.allSatisfy(integerWord) || ((result.isEmpty || ["Z", "z"].contains(result.last!.letter)) && !["M", "m"].contains(letter)) { return nil }
        result.append(PathCommand(letter: letter, values: values.map { Int($0)! })); position += count + 1
    }
    return result.isEmpty ? nil : result
}
struct Matrix {
    var a = 1, b = 0, c = 0, d = 1, e = 0, f = 0
    func point(_ x: Int, _ y: Int) -> Point { Point(x: a * x + b * y + e, y: c * x + d * y + f) }
    func rectangle(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Rectangle { let p = point(x0, y0), q = point(x1, y1); return Rectangle(x0: min(p.x, q.x), y0: min(p.y, q.y), x1: max(p.x, q.x), y1: max(p.y, q.y)) }
    func radii(_ rx: Int, _ ry: Int) -> Point { Point(x: abs(a) * rx + abs(b) * ry, y: abs(c) * rx + abs(d) * ry) }
    mutating func translate(_ dx: Int, _ dy: Int) { e += a * dx + b * dy; f += c * dx + d * dy }
    mutating func scale(_ sx: Int, _ sy: Int) { a *= sx; c *= sx; b *= sy; d *= sy }
    mutating func rotate(_ count: Int) { for _ in 0..<((count % 4 + 4) % 4) { (a, b, c, d) = (b, -a, d, -c) } }
}
struct Frame { let matrix: Matrix; let clip: Rectangle }
struct DrawingState { var matrix = Matrix(); var clip: Rectangle; var stack: [Frame] = [] }
func boundingBox(_ pixels: Set<Point>) -> Rectangle? { if pixels.isEmpty { return nil }; return Rectangle(x0: pixels.map(\.x).min()!, y0: pixels.map(\.y).min()!, x1: pixels.map(\.x).max()!, y1: pixels.map(\.y).max()!) }
func boxText(_ box: Rectangle?) -> String { box.map { "\($0.x0) \($0.y0) \($0.x1) \($0.y1)" } ?? "none" }
func segments(_ points: [Point], _ closed: Bool) -> [(Point, Point)] { Array(zip(points, points.dropFirst())) + (closed ? [(points.last!, points[0])] : []) }
func subpaths(_ commands: [PathCommand], _ matrix: Matrix, _ count: Int) -> [Subpath] {
    var result: [Subpath] = [], current = Point(x: 0, y: 0), start = current
    for command in commands {
        let kind = command.letter.uppercased(), relative = command.letter == command.letter.lowercased(), values = command.values
        if kind == "Z" { result[result.count - 1].closed = true; current = start; continue }
        let ox = relative ? current.x : 0, oy = relative ? current.y : 0
        let points: [Point]
        if kind == "H" { points = [Point(x: values[0] + ox, y: current.y)] }
        else if kind == "V" { points = [Point(x: current.x, y: values[0] + oy)] }
        else { points = stride(from: 0, to: values.count, by: 2).map { Point(x: values[$0] + ox, y: values[$0 + 1] + oy) } }
        if kind == "M" { start = points[0]; result.append(Subpath(points: [matrix.point(start.x, start.y)])) }
        else if kind == "Q" || kind == "C" { let controls = [result.last!.points.last!] + points.map { matrix.point($0.x, $0.y) }; result[result.count - 1].points += bezierPoints(controls, count).dropFirst() }
        else { result[result.count - 1].points.append(matrix.point(points[0].x, points[0].y)) }
        current = points.last!
    }
    return result
}
func rankColors(_ counts: [Color: Int]) -> [(Color, Int)] { counts.map { ($0.key, $0.value) }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.channels.lexicographicallyPrecedes($1.0.channels) } }
func colorCounts(_ values: [Color]) -> [Color: Int] { values.reduce(into: [:]) { $0[$1, default: 0] += 1 } }

final class Renderer {
    let styles: Styles
    let font: Font
    let scene: Scene
    let probes: [Probe]
    let layers: [Layer]
    let fullScreen: Rectangle
    var executions: [Execution] = []
    var usedPens: Set<String> = [], usedBrushes: Set<String> = []
    var symbolUses: [String: Int] = [:]
    init(_ styles: Styles, _ font: Font, _ scene: Scene, _ probes: [Probe]) { self.styles = styles; self.font = font; self.scene = scene; self.probes = probes; layers = scene.layers.map { Layer(scene.width, scene.height, $0.opacity, $0.mode) }; fullScreen = Rectangle(x0: 0, y0: 0, x1: scene.width - 1, y1: scene.height - 1) }
    func validForm(_ command: Command) -> Bool {
        let a = command.arguments, name = command.keyword
        let fixed = ["LINE": (5, 1), "RECT": (5, 1), "FILLRECT": (5, 1), "CIRCLE": (4, 1), "FILLCIRCLE": (4, 1), "ELLIPSE": (5, 1), "FILLELLIPSE": (5, 1), "FLOOD": (3, 1), "ERASE": (4, 0), "TRANSLATE": (2, 0), "SCALE": (2, 0), "ROTATE": (1, 0), "SAVE": (0, 0), "RESTORE": (0, 0), "NOCLIP": (0, 0), "CLIP": (4, 0), "USE": (3, 1)]
        if let (count, start) = fixed[name] { return a.count == count && a.dropFirst(start).allSatisfy(integerWord) }
        if ["POLYLINE", "POLYGON", "FILLPOLYGON"].contains(name) { return a.count >= 2 && a.dropFirst().allSatisfy(integerWord) && a.count == 2 + 2 * command.n(1) }
        if name == "PATH" || name == "FILLPATH" { return a.count >= 2 && integerWord(a[1]) && parsePath(Array(a.dropFirst(2))) != nil }
        return a.count == 5 && integerWord(a[1]) && integerWord(a[2])
    }
    func error(_ command: Command, _ state: DrawingState) -> String? {
        let name = command.keyword, a = command.arguments
        if !penCommands.contains(name) && !brushCommands.contains(name) && !stateCommands.contains(name) && name != "ERASE" { return "unknown_command" }
        if !validForm(command) { return "bad_arguments" }
        if penCommands.contains(name) && styles.pens[a[0]] == nil || brushCommands.contains(name) && styles.brushes[a[0]] == nil { return "unknown_style" }
        if name == "USE" && (scene.symbols[a[0]] == nil || scene.symbols[a[0]]!.endLine > command.line) { return "unknown_symbol" }
        if name == "TEXT" && a[4].contains(where: { $0 != "_" && font.glyphs[$0] == nil }) { return "unknown_glyph" }
        switch name {
        case "CIRCLE", "FILLCIRCLE": if command.n(3) < 1 { return "bad_value" }
        case "ELLIPSE", "FILLELLIPSE": if command.n(3) < 1 || command.n(4) < 1 { return "bad_value" }
        case "POLYLINE": if command.n(1) < 2 { return "bad_value" }
        case "POLYGON", "FILLPOLYGON": if command.n(1) < 3 { return "bad_value" }
        case "PATH", "FILLPATH": if !(1...32).contains(command.n(1)) { return "bad_value" }
        case "FLOOD": if !state.clip.contains(state.matrix.point(command.n(1), command.n(2))) { return "bad_value" }
        case "TEXT": if !["left", "center", "right"].contains(a[3]) { return "bad_value" }
        case "SCALE": if command.n(0) == 0 || command.n(1) == 0 { return "bad_value" }
        case "CLIP": if state.clip.intersection(state.matrix.rectangle(command.n(0), command.n(1), command.n(2), command.n(3))).isEmpty { return "bad_value" }
        case "RESTORE": if state.stack.isEmpty { return "stack_empty" }
        default: break
        }
        return nil
    }

    func penPixels(_ parts: [(Point, Point)], _ pen: Pen, _ clip: Rectangle) -> Set<Point> {
        var points: [Point] = []
        for (start, end) in parts { if let (p, q) = clipSegment(start, end, clip) { points += bresenham(p, q) } }
        var pixels: Set<Point> = []
        for (index, point) in points.enumerated() where pen.off == 0 || index % (pen.on + pen.off) < pen.on { for expanded in expandSquare(point, pen.width) where clip.contains(expanded) { pixels.insert(expanded) } }
        return pixels
    }
    func textPixels(_ command: Command, _ state: DrawingState) -> Set<Point> {
        let a = command.arguments, count = a[4].count, extent = count * (font.width + 1) - 1, x = command.n(1), y = command.n(2)
        let left = a[3] == "center" ? x - extent / 2 : a[3] == "right" ? x - extent + 1 : x
        var pixels: Set<Point> = []
        for (index, character) in a[4].enumerated() where character != "_" {
            let origin = left + index * (font.width + 1)
            for point in font.glyphs[character]! { let box = state.matrix.rectangle(origin + point.x, y + point.y, origin + point.x + 1, y + point.y + 1); pixels.formUnion(Rectangle(x0: box.x0, y0: box.y0, x1: box.x1 - 1, y1: box.y1 - 1).intersection(state.clip).pixels) }
        }
        return pixels
    }
    func coverage(_ command: Command, _ state: DrawingState, _ layer: Layer) -> Set<Point> {
        let name = command.keyword, a = command.arguments, matrix = state.matrix, clip = state.clip
        if name == "ERASE" { return Set(matrix.rectangle(command.n(0), command.n(1), command.n(2), command.n(3)).intersection(clip).pixels.filter { layer.colorAt($0) != nil }) }
        if name == "FLOOD" { return floodFill(layer, matrix.point(command.n(1), command.n(2)), clip) }
        if name == "TEXT" { return textPixels(command, state) }
        if name == "FILLRECT" { return matrix.rectangle(command.n(1), command.n(2), command.n(3), command.n(4)).intersection(clip).pixels }
        if ["CIRCLE", "FILLCIRCLE", "ELLIPSE", "FILLELLIPSE"].contains(name) {
            let center = matrix.point(command.n(1), command.n(2)), radii = matrix.radii(command.n(3), name.hasSuffix("CIRCLE") ? command.n(3) : command.n(4))
            let points = name.hasSuffix("CIRCLE") && radii.x == radii.y ? circlePoints(radii.x) : ellipsePoints(radii.x, radii.y)
            if name.hasPrefix("FILL") { return fillShape(center, points, clip) }
            let pen = styles.pens[a[0]]!
            return Set(points.flatMap { expandSquare(Point(x: center.x + $0.x, y: center.y + $0.y), pen.width) }.filter { clip.contains($0) })
        }
        if name == "PATH" || name == "FILLPATH" {
            let paths = subpaths(parsePath(Array(a.dropFirst(2)))!, matrix, command.n(1))
            if name == "FILLPATH" { return fillPolygons(paths.map { clipPolygon($0.points, clip) }, styles.brushes[a[0]]!.rule, clip) }
            return penPixels(paths.flatMap { segments($0.points, $0.closed) }, styles.pens[a[0]]!, clip)
        }
        let vertices: [Point]
        if name == "RECT" { let box = matrix.rectangle(command.n(1), command.n(2), command.n(3), command.n(4)); vertices = [Point(x: box.x0, y: box.y0), Point(x: box.x1, y: box.y0), Point(x: box.x1, y: box.y1), Point(x: box.x0, y: box.y1)] }
        else if name == "LINE" { vertices = [matrix.point(command.n(1), command.n(2)), matrix.point(command.n(3), command.n(4))] }
        else { vertices = stride(from: 2, to: a.count, by: 2).map { matrix.point(command.n($0), command.n($0 + 1)) } }
        if name == "FILLPOLYGON" { return fillPolygons([clipPolygon(vertices, clip)], styles.brushes[a[0]]!.rule, clip) }
        return penPixels(segments(vertices, name == "RECT" || name == "POLYGON"), styles.pens[a[0]]!, clip)
    }
    func paint(_ pixels: Set<Point>, _ command: Command, _ layer: Layer) {
        if command.keyword == "ERASE" { for point in pixels { _ = layer.erase(point) }; return }
        if penCommands.contains(command.keyword) { let pen = styles.pens[command.arguments[0]]!; usedPens.insert(command.arguments[0]); for point in pixels { layer.paint(point, styles.colors[pen.color]!, command.line) }; return }
        let brush = styles.brushes[command.arguments[0]]!
        usedBrushes.insert(command.arguments[0])
        guard let box = boundingBox(pixels) else { return }
        let first = styles.colors[brush.colors[0]]!
        for point in pixels {
            let color: Color
            if brush.colors.count == 1 { color = first }
            else { let second = styles.colors[brush.colors[1]]!, offset = brush.axis == "x" ? point.x - box.x0 : point.y - box.y0, length = brush.axis == "x" ? box.x1 - box.x0 : box.y1 - box.y0; color = length == 0 ? first : Color(zip(first.channels, second.channels).map { $0.0 + roundRatio(($0.1 - $0.0) * offset, length) }) }
            layer.paint(point, color, command.line)
        }
    }
    func execute(_ command: Command, _ layerIndex: Int, _ state: inout DrawingState) {
        if let problem = error(command, state) { executions.append(Execution(layer: layerIndex, command: command, kind: "error", error: problem, pixels: 0, box: "none")); return }
        if !stateCommands.contains(command.keyword) {
            let pixels = coverage(command, state, layers[layerIndex]); paint(pixels, command, layers[layerIndex]); executions.append(Execution(layer: layerIndex, command: command, kind: "drawing", error: "", pixels: pixels.count, box: boxText(boundingBox(pixels)))); return
        }
        executions.append(Execution(layer: layerIndex, command: command, kind: "state", error: "", pixels: 0, box: "none"))
        switch command.keyword {
        case "TRANSLATE": state.matrix.translate(command.n(0), command.n(1))
        case "SCALE": state.matrix.scale(command.n(0), command.n(1))
        case "ROTATE": state.matrix.rotate(command.n(0))
        case "SAVE": state.stack.append(Frame(matrix: state.matrix, clip: state.clip))
        case "RESTORE": let saved = state.stack.removeLast(); state.matrix = saved.matrix; state.clip = saved.clip
        case "CLIP": state.clip = state.clip.intersection(state.matrix.rectangle(command.n(0), command.n(1), command.n(2), command.n(3)))
        case "NOCLIP": state.clip = fullScreen
        default:
            let saved = state, symbol = command.arguments[0]; symbolUses[symbol, default: 0] += 1; state.matrix.translate(command.n(1), command.n(2)); executeBlock(scene.symbols[symbol]!.body, layerIndex, &state); state = saved
        }
    }
    func executeBlock(_ body: [Instruction], _ layerIndex: Int, _ state: inout DrawingState) {
        for instruction in body {
            switch instruction {
            case .command(let command): execute(command, layerIndex, &state)
            case .repeatBlock(let count, let dx, let dy, let nested):
                let saved = state
                for index in 0..<count { state = saved; state.matrix.translate(index * dx, index * dy); executeBlock(nested, layerIndex, &state) }
                state = saved
            }
        }
    }
    func run() { for (index, block) in scene.layers.enumerated() { var state = DrawingState(clip: fullScreen); executeBlock(block.body, index, &state) } }
    func commandLines() -> [String] { executions.enumerated().map { index, entry in let prefix = "cmd \(index + 1) line \(entry.command.line) \(entry.command.keyword)"; return prefix + (entry.kind == "error" ? " error \(entry.error)" : entry.kind == "state" ? " ok" : " pixels \(entry.pixels) box \(entry.box)") } }
    func layerLines() -> [String] {
        var lines = ["layers \(layers.count)"]
        for (index, layer) in layers.enumerated() {
            let painted = Set(layer.colors.indices.filter { layer.colors[$0] != nil }.map { Point(x: $0 % scene.width, y: $0 / scene.width) })
            let colors = colorCounts(layer.colors.compactMap { $0 }), entries = executions.filter { $0.layer == index }
            let visible = painted.filter { point in layer.alphaAt(point) > 0 && layers.dropFirst(index + 1).allSatisfy { $0.alphaAt(point) < 255 } }.count
            lines.append("layer \(index + 1) \(scene.layers[index].name) opacity \(layer.opacity) mode \(layer.mode) commands \(entries.count) errors \(entries.filter { $0.kind == "error" }.count) pixels \(painted.count) box \(boxText(boundingBox(painted))) visible \(visible) colors \(colors.count)")
            lines += rankColors(colors).prefix(5).map { "color \($0.0.text) pixels \($0.1)" }
        }
        return lines
    }
    func summaryLines(_ image: [Color]) -> [String] {
        let background = styles.colors[scene.background]!, errors = executions.filter { $0.kind == "error" }, drawing = executions.filter { $0.kind == "drawing" }, colors = colorCounts(image)
        var lines = ["canvas \(scene.width) \(scene.height)", "background \(background.rgbText)", "layers \(layers.count)", "symbols \(scene.symbols.count)", "commands \(executions.count)", "drawing \(drawing.count)", "state \(executions.filter { $0.kind == "state" }.count)", "errors \(errors.count)"]
        lines += errorNames.map { name in "error \(name) \(errors.filter { $0.error == name }.count)" }
        lines += ["painted \(drawing.filter { $0.command.keyword != "ERASE" }.reduce(0) { $0 + $1.pixels })", "erased \(drawing.filter { $0.command.keyword == "ERASE" }.reduce(0) { $0 + $1.pixels })", "colors \(colors.count)"]
        lines += rankColors(colors).prefix(8).enumerated().map { "top \($0.offset + 1) \($0.element.0.rgbText) pixels \($0.element.1)" }
        lines += scene.symbols.keys.sorted().map { "symbol \($0) uses \(symbolUses[$0] ?? 0)" }
        var keywords: [String: KeywordTally] = [:]
        for entry in executions { let name = entry.command.keyword; keywords[name, default: KeywordTally()].executed += 1; if entry.kind == "error" { keywords[name]!.errors += 1 }; keywords[name]!.pixels += entry.pixels }
        lines += keywords.keys.sorted().map { name in let tally = keywords[name]!; return "keyword \(name) executed \(tally.executed) errors \(tally.errors) pixels \(tally.pixels)" }
        var usedColors: Set<String> = [scene.background]
        for name in usedPens { usedColors.insert(styles.pens[name]!.color) }
        for name in usedBrushes { usedColors.formUnion(styles.brushes[name]!.colors) }
        var unused: [String] = []
        for (kind, names, used) in [("color", Array(styles.colors.keys), usedColors), ("pen", Array(styles.pens.keys), usedPens), ("brush", Array(styles.brushes.keys), usedBrushes), ("symbol", Array(scene.symbols.keys), Set(symbolUses.keys))] { unused += names.filter { !used.contains($0) }.sorted().map { "unused \(kind) \($0)" } }
        return lines + ["unused \(unused.count)"] + unused
    }
    func probeLines(_ image: [Color]) -> [String] {
        probes.enumerated().map { index, probe in
            let values = probe.values
            if probe.kind == "point" { let point = Point(x: values[0], y: values[1]), stack = layers.enumerated().compactMap { number, layer in layer.alphaAt(Point(x: values[0], y: values[1])) > 0 ? "\(number + 1):\(layer.lines[values[1] * scene.width + values[0]])" : nil }; return "point \(index + 1) \(point.x) \(point.y) rgb \(image[point.y * scene.width + point.x].rgbText) layers \(stack.count) stack \(stack.isEmpty ? "none" : stack.joined(separator: " "))" }
            let points = Rectangle(x0: values[0], y0: values[1], x1: values[2], y1: values[3]).pixels, colors = points.map { image[$0.y * scene.width + $0.x] }
            let means = (0..<3).map { channel in String(colors.reduce(0) { $0 + $1.channels[channel] } / points.count) }.joined(separator: " ")
            let cover = layers.map { layer in String(points.filter { layer.alphaAt($0) > 0 }.count) }.joined(separator: " ")
            return "area \(index + 1) \(values.map(String.init).joined(separator: " ")) pixels \(points.count) mean \(means) colors \(Set(colors).count) cover \(cover)"
        }
    }
    func write() throws {
        let image = composite(layers, styles.colors[scene.background]!, scene.width, scene.height)
        try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
        try writePPM("output/image.ppm", image, scene.width, scene.height); try writePreview("output/preview.txt", image, scene.width, scene.height)
        for (name, lines) in [("commands.txt", commandLines()), ("layers.txt", layerLines()), ("summary.txt", summaryLines(image)), ("probes.txt", probeLines(image))] { try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/\(name)", atomically: true, encoding: .utf8) }
    }
}
let renderer = try Renderer(readStyles(), readFont(), readScene(), readProbes())
renderer.run()
try renderer.write()
