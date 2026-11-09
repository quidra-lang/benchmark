import java.io.File
import kotlin.math.abs

val penCommands = setOf("LINE", "RECT", "CIRCLE", "ELLIPSE", "POLYLINE", "POLYGON", "PATH")
val brushCommands = setOf("FILLRECT", "FILLCIRCLE", "FILLELLIPSE", "FILLPOLYGON", "FILLPATH", "FLOOD", "TEXT")
val stateCommands = setOf("TRANSLATE", "SCALE", "ROTATE", "SAVE", "RESTORE", "CLIP", "NOCLIP", "USE")
val errorNames = listOf("unknown_command", "bad_arguments", "unknown_style", "unknown_symbol", "unknown_glyph", "bad_value", "stack_empty")
val pathArities = mapOf("M" to 2, "m" to 2, "L" to 2, "l" to 2, "H" to 1, "h" to 1, "V" to 1, "v" to 1, "Q" to 4, "q" to 4, "C" to 6, "c" to 6, "Z" to 0, "z" to 0)
data class Pen(val width: Int, val color: String, val on: Int, val off: Int)
data class Brush(val colors: List<String>, val axis: String, val rule: String)
class Styles { val colors = mutableMapOf<String, Color>(); val pens = mutableMapOf<String, Pen>(); val brushes = mutableMapOf<String, Brush>() }
data class Font(val width: Int, val height: Int, val glyphs: Map<Char, List<Point>>)
sealed interface Instruction
data class Command(val line: Int, val keyword: String, val arguments: List<String>) : Instruction { fun n(index: Int): Int = arguments[index].toInt() }
data class Repeat(val count: Int, val dx: Int, val dy: Int, val body: List<Instruction>) : Instruction
data class LayerBlock(val name: String, val opacity: Int, val mode: String, val body: List<Instruction>)
data class Symbol(val body: List<Instruction>, val endLine: Int)
data class Scene(val width: Int, val height: Int, val background: String, val layers: List<LayerBlock>, val symbols: Map<String, Symbol>)
data class SourceLine(val number: Int, val words: List<String>)
data class Probe(val kind: String, val values: List<Int>)
data class PathCommand(val letter: String, val values: List<Int>)
class Subpath(start: Point) { val points = mutableListOf(start); var closed = false }
data class Execution(val layer: Int, val command: Command, val kind: String, val error: String = "", val pixels: Int = 0, val box: String = "none")
class KeywordTally { var executed = 0; var errors = 0; var pixels = 0 }
fun readStyles(): Styles {
    val styles = Styles()
    for (line in File("input/styles.txt").readLines()) {
        if (line.isEmpty() || line.startsWith('#')) continue
        val words = line.split(' ')
        when (words[0]) {
            "color" -> styles.colors[words[1]] = Color(words.drop(2).map(String::toInt))
            "pen" -> styles.pens[words[1]] = Pen(words[2].toInt(), words[3], words[4].toInt(), words[5].toInt())
            "brush" -> styles.brushes[words[1]] = Brush(listOf(words[2]), "", words[3])
            "gradient" -> styles.brushes[words[1]] = Brush(listOf(words[2], words[3]), words[4], words[5])
        }
    }
    return styles
}
fun readFont(): Font {
    val lines = File("input/font.txt").readLines(); val header = lines.first().split(' '); val width = header[1].toInt(); val height = header[2].toInt()
    val glyphs = mutableMapOf<Char, List<Point>>(); var position = 1
    while (position < lines.size) { val character = lines[position++].last(); val points = mutableListOf<Point>(); for (row in 0 until height) for ((column, value) in lines[position + row].withIndex()) if (value == '#') points += Point(column, row); position += height; glyphs[character] = points }
    return Font(width, height, glyphs)
}
fun readScene(): Scene {
    val lines = File("input/scene.txt").readLines().mapIndexedNotNull { index, line -> val words = line.split(' ').filter { it.isNotEmpty() }; if (words.isEmpty() || words.first().startsWith('#')) null else SourceLine(index + 1, words) }
    val header = lines.first().words; var position = 1; val layers = mutableListOf<LayerBlock>(); val symbols = mutableMapOf<String, Symbol>()
    fun body(terminator: String): Pair<List<Instruction>, Int> {
        val result = mutableListOf<Instruction>()
        while (lines[position].words[0] != terminator) {
            val source = lines[position++]; val words = source.words
            if (words[0] == "REPEAT") { val (nested, _) = body("ENDREPEAT"); result += Repeat(words[1].toInt(), words[2].toInt(), words[3].toInt(), nested) }
            else result += Command(source.number, words[0], words.drop(1))
        }
        val end = lines[position++].number
        return result to end
    }
    while (position < lines.size) { val words = lines[position++].words; val (contents, end) = body("END"); if (words[0] == "LAYER") layers += LayerBlock(words[1], words[2].toInt(), words[3], contents) else symbols[words[1]] = Symbol(contents, end) }
    return Scene(header[1].toInt(), header[2].toInt(), header[3], layers, symbols)
}
fun readProbes(): List<Probe> = File("input/probes.txt").readLines().drop(1).map { val words = it.split(' '); Probe(words[0], words.drop(1).map(String::toInt)) }
fun integerWord(text: String): Boolean { val digits = if (text.startsWith('-')) text.drop(1) else text; return digits.isNotEmpty() && digits.all { it in '0'..'9' } }
fun parsePath(words: List<String>): List<PathCommand>? {
    val result = mutableListOf<PathCommand>(); var position = 0
    while (position < words.size) {
        val letter = words[position]; val count = pathArities[letter] ?: return null
        if (position + count >= words.size) return null
        val values = words.subList(position + 1, position + count + 1)
        if (values.any { !integerWord(it) } || (result.isEmpty() || result.last().letter in listOf("Z", "z")) && letter !in listOf("M", "m")) return null
        result += PathCommand(letter, values.map(String::toInt)); position += count + 1
    }
    return result.takeIf { it.isNotEmpty() }
}
data class Matrix(val a: Int = 1, val b: Int = 0, val c: Int = 0, val d: Int = 1, val e: Int = 0, val f: Int = 0) {
    fun point(x: Int, y: Int): Point = Point(a * x + b * y + e, c * x + d * y + f)
    fun rectangle(x0: Int, y0: Int, x1: Int, y1: Int): Rectangle { val p = point(x0, y0); val q = point(x1, y1); return Rectangle(minOf(p.x, q.x), minOf(p.y, q.y), maxOf(p.x, q.x), maxOf(p.y, q.y)) }
    fun radii(rx: Int, ry: Int): Point = Point(abs(a) * rx + abs(b) * ry, abs(c) * rx + abs(d) * ry)
    fun translate(dx: Int, dy: Int): Matrix = copy(e = e + a * dx + b * dy, f = f + c * dx + d * dy)
    fun scale(sx: Int, sy: Int): Matrix = copy(a = a * sx, c = c * sx, b = b * sy, d = d * sy)
    fun rotate(count: Int): Matrix { var result = this; repeat((count % 4 + 4) % 4) { result = Matrix(result.b, -result.a, result.d, -result.c, result.e, result.f) }; return result }
}
data class Frame(val matrix: Matrix, val clip: Rectangle)
data class DrawingState(var clip: Rectangle, var matrix: Matrix = Matrix(), var stack: List<Frame> = emptyList()) { fun restore(saved: DrawingState) { matrix = saved.matrix; clip = saved.clip; stack = saved.stack } }
fun boundingBox(pixels: Set<Point>): Rectangle? = if (pixels.isEmpty()) null else Rectangle(pixels.minOf { it.x }, pixels.minOf { it.y }, pixels.maxOf { it.x }, pixels.maxOf { it.y })
fun boxText(box: Rectangle?): String = box?.let { "${it.x0} ${it.y0} ${it.x1} ${it.y1}" } ?: "none"
fun segments(points: List<Point>, closed: Boolean): List<Pair<Point, Point>> = points.zipWithNext() + if (closed) listOf(points.last() to points.first()) else emptyList()
fun subpaths(commands: List<PathCommand>, matrix: Matrix, count: Int): List<Subpath> {
    val result = mutableListOf<Subpath>(); var current = Point(0, 0); var start = current
    for (command in commands) {
        val kind = command.letter.uppercase(); val relative = command.letter == command.letter.lowercase(); val values = command.values
        if (kind == "Z") { result.last().closed = true; current = start; continue }
        val ox = if (relative) current.x else 0; val oy = if (relative) current.y else 0
        val points = if (kind == "H") listOf(Point(values[0] + ox, current.y)) else if (kind == "V") listOf(Point(current.x, values[0] + oy)) else (values.indices step 2).map { Point(values[it] + ox, values[it + 1] + oy) }
        if (kind == "M") { start = points.first(); result += Subpath(matrix.point(start.x, start.y)) }
        else if (kind == "Q" || kind == "C") { val controls = listOf(result.last().points.last()) + points.map { matrix.point(it.x, it.y) }; result.last().points += bezierPoints(controls, count).drop(1) }
        else result.last().points += matrix.point(points.first().x, points.first().y)
        current = points.last()
    }
    return result
}
fun rankColors(counts: Map<Color, Int>): List<Pair<Color, Int>> = counts.entries.sortedWith(compareByDescending<Map.Entry<Color, Int>> { it.value }.thenBy { it.key.red }.thenBy { it.key.green }.thenBy { it.key.blue }.thenBy { it.key.alpha }).map { it.key to it.value }
fun colorCounts(values: List<Color>): Map<Color, Int> = values.groupingBy { it }.eachCount()
class Renderer(val styles: Styles, val font: Font, val scene: Scene, val probes: List<Probe>) {
    val layers = scene.layers.map { Layer(scene.width, scene.height, it.opacity, it.mode) }
    val fullScreen = Rectangle(0, 0, scene.width - 1, scene.height - 1)
    val executions = mutableListOf<Execution>()
    val usedPens = mutableSetOf<String>(); val usedBrushes = mutableSetOf<String>(); val symbolUses = mutableMapOf<String, Int>()
    fun validForm(command: Command): Boolean {
        val a = command.arguments; val name = command.keyword
        val fixed = mapOf("LINE" to (5 to 1), "RECT" to (5 to 1), "FILLRECT" to (5 to 1), "CIRCLE" to (4 to 1), "FILLCIRCLE" to (4 to 1), "ELLIPSE" to (5 to 1), "FILLELLIPSE" to (5 to 1), "FLOOD" to (3 to 1), "ERASE" to (4 to 0), "TRANSLATE" to (2 to 0), "SCALE" to (2 to 0), "ROTATE" to (1 to 0), "SAVE" to (0 to 0), "RESTORE" to (0 to 0), "NOCLIP" to (0 to 0), "CLIP" to (4 to 0), "USE" to (3 to 1))
        fixed[name]?.let { (count, start) -> return a.size == count && a.drop(start).all(::integerWord) }
        if (name in listOf("POLYLINE", "POLYGON", "FILLPOLYGON")) return a.size >= 2 && a.drop(1).all(::integerWord) && a.size == 2 + 2 * command.n(1)
        if (name == "PATH" || name == "FILLPATH") return a.size >= 2 && integerWord(a[1]) && parsePath(a.drop(2)) != null
        return a.size == 5 && integerWord(a[1]) && integerWord(a[2])
    }
    fun error(command: Command, state: DrawingState): String? {
        val name = command.keyword; val a = command.arguments
        if (name !in penCommands && name !in brushCommands && name !in stateCommands && name != "ERASE") return "unknown_command"
        if (!validForm(command)) return "bad_arguments"
        if (name in penCommands && a[0] !in styles.pens || name in brushCommands && a[0] !in styles.brushes) return "unknown_style"
        if (name == "USE" && (a[0] !in scene.symbols || scene.symbols.getValue(a[0]).endLine > command.line)) return "unknown_symbol"
        if (name == "TEXT" && a[4].any { it != '_' && it !in font.glyphs }) return "unknown_glyph"
        when (name) {
            "CIRCLE", "FILLCIRCLE" -> if (command.n(3) < 1) return "bad_value"
            "ELLIPSE", "FILLELLIPSE" -> if (command.n(3) < 1 || command.n(4) < 1) return "bad_value"
            "POLYLINE" -> if (command.n(1) < 2) return "bad_value"
            "POLYGON", "FILLPOLYGON" -> if (command.n(1) < 3) return "bad_value"
            "PATH", "FILLPATH" -> if (command.n(1) !in 1..32) return "bad_value"
            "FLOOD" -> if (!state.clip.contains(state.matrix.point(command.n(1), command.n(2)))) return "bad_value"
            "TEXT" -> if (a[3] !in listOf("left", "center", "right")) return "bad_value"
            "SCALE" -> if (command.n(0) == 0 || command.n(1) == 0) return "bad_value"
            "CLIP" -> if (state.clip.intersection(state.matrix.rectangle(command.n(0), command.n(1), command.n(2), command.n(3))).isEmpty) return "bad_value"
            "RESTORE" -> if (state.stack.isEmpty()) return "stack_empty"
        }
        return null
    }

    fun penPixels(parts: List<Pair<Point, Point>>, pen: Pen, clip: Rectangle): Set<Point> {
        val points = parts.flatMap { (start, end) -> clipSegment(start, end, clip)?.let { bresenham(it.first, it.second) } ?: emptyList() }
        return points.filterIndexed { index, _ -> pen.off == 0 || index % (pen.on + pen.off) < pen.on }.flatMap { expandSquare(it, pen.width) }.filter { clip.contains(it) }.toSet()
    }
    fun textPixels(command: Command, state: DrawingState): Set<Point> {
        val a = command.arguments; val extent = a[4].length * (font.width + 1) - 1; val x = command.n(1); val y = command.n(2)
        val left = if (a[3] == "center") x - extent / 2 else if (a[3] == "right") x - extent + 1 else x
        val pixels = mutableSetOf<Point>()
        for ((index, character) in a[4].withIndex()) if (character != '_') {
            val origin = left + index * (font.width + 1)
            for (point in font.glyphs.getValue(character)) { val box = state.matrix.rectangle(origin + point.x, y + point.y, origin + point.x + 1, y + point.y + 1); pixels += Rectangle(box.x0, box.y0, box.x1 - 1, box.y1 - 1).intersection(state.clip).pixels }
        }
        return pixels
    }
    fun coverage(command: Command, state: DrawingState, layer: Layer): Set<Point> {
        val name = command.keyword; val a = command.arguments; val matrix = state.matrix; val clip = state.clip
        if (name == "ERASE") return matrix.rectangle(command.n(0), command.n(1), command.n(2), command.n(3)).intersection(clip).pixels.filter { layer.colorAt(it) != null }.toSet()
        if (name == "FLOOD") return floodFill(layer, matrix.point(command.n(1), command.n(2)), clip)
        if (name == "TEXT") return textPixels(command, state)
        if (name == "FILLRECT") return matrix.rectangle(command.n(1), command.n(2), command.n(3), command.n(4)).intersection(clip).pixels
        if (name in listOf("CIRCLE", "FILLCIRCLE", "ELLIPSE", "FILLELLIPSE")) {
            val center = matrix.point(command.n(1), command.n(2)); val radii = matrix.radii(command.n(3), if (name.endsWith("CIRCLE")) command.n(3) else command.n(4))
            val points = if (name.endsWith("CIRCLE") && radii.x == radii.y) circlePoints(radii.x) else ellipsePoints(radii.x, radii.y)
            if (name.startsWith("FILL")) return fillShape(center, points, clip)
            val pen = styles.pens.getValue(a[0])
            return points.flatMap { expandSquare(Point(center.x + it.x, center.y + it.y), pen.width) }.filter { clip.contains(it) }.toSet()
        }
        if (name == "PATH" || name == "FILLPATH") {
            val paths = subpaths(parsePath(a.drop(2))!!, matrix, command.n(1))
            if (name == "FILLPATH") return fillPolygons(paths.map { clipPolygon(it.points, clip) }, styles.brushes.getValue(a[0]).rule, clip)
            return penPixels(paths.flatMap { segments(it.points, it.closed) }, styles.pens.getValue(a[0]), clip)
        }
        val vertices = if (name == "RECT") { val box = matrix.rectangle(command.n(1), command.n(2), command.n(3), command.n(4)); listOf(Point(box.x0, box.y0), Point(box.x1, box.y0), Point(box.x1, box.y1), Point(box.x0, box.y1)) }
            else if (name == "LINE") listOf(matrix.point(command.n(1), command.n(2)), matrix.point(command.n(3), command.n(4)))
            else (2 until a.size step 2).map { matrix.point(command.n(it), command.n(it + 1)) }
        if (name == "FILLPOLYGON") return fillPolygons(listOf(clipPolygon(vertices, clip)), styles.brushes.getValue(a[0]).rule, clip)
        return penPixels(segments(vertices, name == "RECT" || name == "POLYGON"), styles.pens.getValue(a[0]), clip)
    }
    fun paint(pixels: Set<Point>, command: Command, layer: Layer) {
        if (command.keyword == "ERASE") { pixels.forEach { layer.erase(it) }; return }
        if (command.keyword in penCommands) { val pen = styles.pens.getValue(command.arguments[0]); usedPens += command.arguments[0]; pixels.forEach { layer.paint(it, styles.colors.getValue(pen.color), command.line) }; return }
        val brush = styles.brushes.getValue(command.arguments[0]); usedBrushes += command.arguments[0]
        val box = boundingBox(pixels) ?: return
        val first = styles.colors.getValue(brush.colors[0])
        for (point in pixels) {
            val color = if (brush.colors.size == 1) first else { val second = styles.colors.getValue(brush.colors[1]); val offset = if (brush.axis == "x") point.x - box.x0 else point.y - box.y0; val length = if (brush.axis == "x") box.x1 - box.x0 else box.y1 - box.y0; if (length == 0) first else Color(first.channels.zip(second.channels).map { (a, b) -> a + roundRatio((b - a) * offset, length) }) }
            layer.paint(point, color, command.line)
        }
    }
    fun execute(command: Command, layerIndex: Int, state: DrawingState) {
        val problem = error(command, state)
        if (problem != null) { executions += Execution(layerIndex, command, "error", problem); return }
        if (command.keyword !in stateCommands) { val pixels = coverage(command, state, layers[layerIndex]); paint(pixels, command, layers[layerIndex]); executions += Execution(layerIndex, command, "drawing", pixels = pixels.size, box = boxText(boundingBox(pixels))); return }
        executions += Execution(layerIndex, command, "state")
        when (command.keyword) {
            "TRANSLATE" -> state.matrix = state.matrix.translate(command.n(0), command.n(1))
            "SCALE" -> state.matrix = state.matrix.scale(command.n(0), command.n(1))
            "ROTATE" -> state.matrix = state.matrix.rotate(command.n(0))
            "SAVE" -> state.stack = state.stack + Frame(state.matrix, state.clip)
            "RESTORE" -> { val saved = state.stack.last(); state.stack = state.stack.dropLast(1); state.matrix = saved.matrix; state.clip = saved.clip }
            "CLIP" -> state.clip = state.clip.intersection(state.matrix.rectangle(command.n(0), command.n(1), command.n(2), command.n(3)))
            "NOCLIP" -> state.clip = fullScreen
            "USE" -> { val saved = state.copy(); val symbol = command.arguments[0]; symbolUses[symbol] = (symbolUses[symbol] ?: 0) + 1; state.matrix = state.matrix.translate(command.n(1), command.n(2)); executeBlock(scene.symbols.getValue(symbol).body, layerIndex, state); state.restore(saved) }
        }
    }
    fun executeBlock(body: List<Instruction>, layerIndex: Int, state: DrawingState) {
        for (instruction in body) when (instruction) {
            is Command -> execute(instruction, layerIndex, state)
            is Repeat -> { val saved = state.copy(); repeat(instruction.count) { index -> state.restore(saved); state.matrix = state.matrix.translate(index * instruction.dx, index * instruction.dy); executeBlock(instruction.body, layerIndex, state) }; state.restore(saved) }
        }
    }
    fun run() { for ((index, block) in scene.layers.withIndex()) executeBlock(block.body, index, DrawingState(fullScreen)) }
    fun commandLines(): List<String> = executions.mapIndexed { index, entry -> val prefix = "cmd ${index + 1} line ${entry.command.line} ${entry.command.keyword}"; prefix + if (entry.kind == "error") " error ${entry.error}" else if (entry.kind == "state") " ok" else " pixels ${entry.pixels} box ${entry.box}" }
    fun layerLines(): List<String> {
        val lines = mutableListOf("layers ${layers.size}")
        for ((index, layer) in layers.withIndex()) {
            val painted = layer.colors.indices.filter { layer.colors[it] != null }.map { Point(it % scene.width, it / scene.width) }.toSet()
            val colors = colorCounts(layer.colors.filterNotNull()); val entries = executions.filter { it.layer == index }
            val visible = painted.count { point -> layer.alphaAt(point) > 0 && layers.drop(index + 1).all { it.alphaAt(point) < 255 } }
            lines += "layer ${index + 1} ${scene.layers[index].name} opacity ${layer.opacity} mode ${layer.mode} commands ${entries.size} errors ${entries.count { it.kind == "error" }} pixels ${painted.size} box ${boxText(boundingBox(painted))} visible $visible colors ${colors.size}"
            lines += rankColors(colors).take(5).map { (color, count) -> "color ${color.text} pixels $count" }
        }
        return lines
    }
    fun summaryLines(image: List<Color>): List<String> {
        val background = styles.colors.getValue(scene.background); val errors = executions.filter { it.kind == "error" }; val drawing = executions.filter { it.kind == "drawing" }; val colors = colorCounts(image)
        val lines = mutableListOf("canvas ${scene.width} ${scene.height}", "background ${background.rgbText}", "layers ${layers.size}", "symbols ${scene.symbols.size}", "commands ${executions.size}", "drawing ${drawing.size}", "state ${executions.count { it.kind == "state" }}", "errors ${errors.size}")
        lines += errorNames.map { name -> "error $name ${errors.count { it.error == name }}" }
        lines += listOf("painted ${drawing.filter { it.command.keyword != "ERASE" }.sumOf { it.pixels }}", "erased ${drawing.filter { it.command.keyword == "ERASE" }.sumOf { it.pixels }}", "colors ${colors.size}")
        lines += rankColors(colors).take(8).mapIndexed { index, (color, count) -> "top ${index + 1} ${color.rgbText} pixels $count" }
        lines += scene.symbols.keys.sorted().map { "symbol $it uses ${symbolUses[it] ?: 0}" }
        val keywords = mutableMapOf<String, KeywordTally>()
        for (entry in executions) { val tally = keywords.getOrPut(entry.command.keyword) { KeywordTally() }; tally.executed++; if (entry.kind == "error") tally.errors++; tally.pixels += entry.pixels }
        lines += keywords.keys.sorted().map { name -> val tally = keywords.getValue(name); "keyword $name executed ${tally.executed} errors ${tally.errors} pixels ${tally.pixels}" }
        val usedColors = mutableSetOf(scene.background)
        for (name in usedPens) usedColors += styles.pens.getValue(name).color
        for (name in usedBrushes) usedColors += styles.brushes.getValue(name).colors
        val unused = mutableListOf<String>()
        for ((kind, names, used) in listOf(Triple("color", styles.colors.keys, usedColors), Triple("pen", styles.pens.keys, usedPens), Triple("brush", styles.brushes.keys, usedBrushes), Triple("symbol", scene.symbols.keys, symbolUses.keys))) unused += names.filter { it !in used }.sorted().map { "unused $kind $it" }
        return lines + "unused ${unused.size}" + unused
    }
    fun probeLines(image: List<Color>): List<String> = probes.mapIndexed { index, probe ->
        val values = probe.values
        if (probe.kind == "point") { val point = Point(values[0], values[1]); val stack = layers.mapIndexedNotNull { number, layer -> if (layer.alphaAt(point) > 0) "${number + 1}:${layer.lines[point.y * scene.width + point.x]}" else null }; "point ${index + 1} ${point.x} ${point.y} rgb ${image[point.y * scene.width + point.x].rgbText} layers ${stack.size} stack ${if (stack.isEmpty()) "none" else stack.joinToString(" ")}" }
        else {
            val points = Rectangle(values[0], values[1], values[2], values[3]).pixels; val colors = points.map { image[it.y * scene.width + it.x] }
            val means = (0 until 3).joinToString(" ") { channel -> (colors.sumOf { it.channels[channel] } / points.size).toString() }
            val cover = layers.joinToString(" ") { layer -> points.count { layer.alphaAt(it) > 0 }.toString() }
            "area ${index + 1} ${values.joinToString(" ")} pixels ${points.size} mean $means colors ${colors.toSet().size} cover $cover"
        }
    }
    fun write() {
        val image = composite(layers, styles.colors.getValue(scene.background), scene.width, scene.height)
        File("output").mkdirs(); writePPM("output/image.ppm", image, scene.width, scene.height); writePreview("output/preview.txt", image, scene.width, scene.height)
        for ((name, lines) in listOf("commands.txt" to commandLines(), "layers.txt" to layerLines(), "summary.txt" to summaryLines(image), "probes.txt" to probeLines(image))) File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n", postfix = "\n"))
    }
}
fun main() { val renderer = Renderer(readStyles(), readFont(), readScene(), readProbes()); renderer.run(); renderer.write() }
