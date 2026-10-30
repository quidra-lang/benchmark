import java.io.File
fun display(kind: String, value: String, references: Map<String, String>): String =
if (kind == "command") Lexer.symbol(value.drop(1))!!.first else if (kind == "eqref") references[value] ?: "(??)" else value
fun typeset(node: Node, script: Boolean, p: Params, references: Map<String, String>): Box {
    return when (node) {
        is Node.Atom -> {
            val description = (if (node.kind == "text") "text" else if (node.kind == "eqref") "eqref" else "atom") + " \"${node.value}\""
            if (!script && node.kind == "command" && node.value in listOf("\\sum", "\\prod", "\\int")) {
                val glyph = Boxes.large(node.value.drop(1))
                val result = Box(glyph[0].length, 3, 1, description)
                for ((y, line) in glyph.withIndex()) result.string(0, y, line)
                result
            } else Box.text(display(node.kind, node.value, references), description)
        }
        is Node.Row -> Layout.row(node.elements.map {
            typeset(it, script, p, references)
        }, Layout.spacing(node.elements, script, p).gaps, "row")
        is Node.Script -> {
            val b = typeset(node.base, script, p, references)
            val s = node.sub?.let {
                typeset(it, true, p, references)
            }
            val u = node.sup?.let {
                typeset(it, true, p, references)
            }
            val sw = s?.width ?: 0
            val sh = s?.height ?: 0
            val uw = u?.width ?: 0
            val uh = u?.height ?: 0
            val stacked = !script && when (val base = node.base) {
                is Node.Atom -> base.kind == "command" && base.value in listOf("\\sum", "\\prod", "\\lim", "\\max", "\\min")
                is Node.Accent -> base.name in listOf("overbrace", "underbrace")
                else -> false
            }
            if (stacked) {
                val width = maxOf(b.width, sw, uw)
                val result = Box(width, uh + b.height + sh, uh + b.baseline, "limits")
                result.child(b, (width - b.width) / 2, uh, "base: ")
                if (s != null) result.child(s, (width - sw) / 2, uh + b.height, "sub: ")
                if (u != null) result.child(u, (width - uw) / 2, 0, "sup: ")
                result
            } else {
                val tp = (if (b.baseline == 0) -1 else 0) - uh + 1
                val ts = if (b.height - 1 - b.baseline == 0) b.height else b.height - 1
                val top = if (u == null) 0 else minOf(0, tp)
                val bottom = if (s == null) b.height - 1 else maxOf(b.height - 1, ts + sh - 1)
                val shift = -top
                val result = Box(b.width + maxOf(sw, uw), bottom - top + 1, b.baseline + shift, "scripts")
                result.child(b, 0, shift, "base: ")
                if (s != null) result.child(s, b.width, ts + shift, "sub: ")
                if (u != null) result.child(u, b.width, tp + shift, "sup: ")
                result
            }
        }
        is Node.Binary -> {
            if (node.name == "frac" && script) {
                fun part(n: Node): Box {
                    val wrap = n is Node.Row || n is Node.Binary && n.name == "frac"
                    return typeset(if (wrap) Node.Delimited("(", ")", n, 0) else n, true, p, references)
                }
                Layout.row(listOf(part(node.first), Box.text("/", "atom \"/\""), part(node.second)), listOf(0, 0), "slash", listOf("num: ", "", "den: "))
            } else {
                val a = typeset(node.first, if (node.name in listOf("overset", "underset")) true else script, p, references)
                val b = typeset(node.second, script, p, references)
                val width = maxOf(a.width, b.width)
                when (node.name) {
                    "frac" -> {
                        val result = Box(width + 2, a.height + 1 + b.height, a.height, "frac")
                        result.string(0, a.height, "-".repeat(width + 2)); result.child(a, (width + 2 - a.width) / 2, 0, "num: "); result.child(b, (width + 2 - b.width) / 2, a.height + 1, "den: ")
                        result
                    }
                    "binom" -> {
                        val result = Box(width + 2, a.height + 1 + b.height, a.height, "binom")
                        result.delimiter("(", 0); result.delimiter(")", width + 1); result.child(a, 1 + (width - a.width) / 2, 0, "upper: "); result.child(b, 1 + (width - b.width) / 2, a.height + 1, "lower: ")
                        result
                    }
                    "overset" -> {
                        val result = Box(width, a.height + b.height, a.height + b.baseline, "overset")
                        result.child(a, (width - a.width) / 2, 0, "over: "); result.child(b, (width - b.width) / 2, a.height, "base: ")
                        result
                    }
                    else -> {
                        val result = Box(width, a.height + b.height, b.baseline, "underset")
                        result.child(b, (width - b.width) / 2, 0, "base: "); result.child(a, (width - a.width) / 2, b.height, "under: ")
                        result
                    }
                }
            }
        }
        is Node.Root -> {
            val body = typeset(node.body, script, p, references)
            val index = node.index?.let {
                typeset(it, true, p, references)
            }
            val k = body.height
            val extra = maxOf(0, (index?.width ?: 0) - 1)
            val top = maxOf(0, (index?.height ?: 0) - k)
            val result = Box(extra + k + 1 + body.width, k + 1 + top, body.baseline + 1 + top, if (index == null) "sqrt" else "root")
            result.string(extra + k + 1, top, "_".repeat(body.width)); result.string(extra, k + top, "\\")
            for (r in 1..k) result.string(extra + k - r + 1, r + top, "/")
            if (index != null) {
                result.child(index, 0, k + top - index.height, "index: "); result.child(body, extra + k + 1, 1 + top, "body: ")
            }
            else result.child(body, extra + k + 1, 1 + top)
            result
        }
        is Node.Delimited -> {
            val body = typeset(node.body, script, p, references)
            val wl = if (node.left == ".") 0 else 1
            val wr = if (node.right == ".") 0 else 1
            val result = Box(wl + body.width + wr, body.height, body.baseline, "delim ${node.left} ${node.right}")
            result.delimiter(node.left, 0); result.delimiter(node.right, wl + body.width); result.child(body, wl, 0)
            result
        }
        is Node.Matrix -> {
            val cells = node.rows.map {
                row -> row.map {
                    typeset(it, script, p, references)
                }
            }
            val columns = node.rows[0].size
            val widths = (0 until columns).map {
                j -> cells.maxOf {
                    it[j].width
                }
            }
            val ascents = cells.map {
                row -> row.maxOf {
                    it.baseline
                }
            }
            val descents = cells.map {
                row -> row.maxOf {
                    it.height - 1 - it.baseline
                }
            }
            val heights = ascents.zip(descents).map {
                it.first + it.second + 1
            }
            val bodyWidth = widths.sum() + p.colGap * (columns - 1)
            val bodyHeight = heights.sum() + p.rowGap * (cells.size - 1)
            val shift = if (node.name == "matrix") 0 else 2
            val width = bodyWidth + if (node.name == "matrix") 0 else if (node.name == "cases") 2 else 4
            val result = Box(width, bodyHeight, (bodyHeight - 1) / 2, "${node.name} rows=${cells.size} cols=$columns")
            when (node.name) {
                "pmatrix" -> {
                    result.delimiter("(", 0); result.delimiter(")", bodyWidth + 3)
                }
                "bmatrix" -> {
                    result.delimiter("[", 0); result.delimiter("]", bodyWidth + 3)
                }
                "vmatrix" -> {
                    result.delimiter("|", 0); result.delimiter("|", bodyWidth + 3)
                }
                "cases" -> result.delimiter("\\{", 0)
            }
            var y = 0
            for ((i, row) in cells.withIndex()) {
                var x = shift
                for ((j, box) in row.withIndex()) {
                    val offset = if (node.name == "cases") 0 else (widths[j] - box.width) / 2
                    result.child(box, x + offset, y + ascents[i] - box.baseline, "cell ${i + 1},${j + 1}: "); x += widths[j] + p.colGap
                }
                y += heights[i] + p.rowGap
            }
            result
        }
        is Node.Accent -> {
            val body = typeset(node.body, script, p, references)
            val width = when (node.name) {
                "hat", "dot", "tilde" -> maxOf(body.width, 1); "vec" -> maxOf(body.width, 2); "overbrace", "underbrace" -> body.width + 2; else -> body.width
            }
            val result = Box(width, body.height + 1, if (node.name == "underbrace") body.baseline else body.baseline + 1, node.name)
            when (node.name) {
                "overline" -> result.string(0, 0, "_".repeat(width))
                "hat", "dot", "tilde" -> result.string((width - 1) / 2, 0, if (node.name == "hat") "^" else if (node.name == "dot") "." else "~")
                "vec" -> result.string(0, 0, "-".repeat(width - 1) + ">")
                "overbrace" -> result.string(0, 0, "/" + "-".repeat(body.width) + "\\")
                else -> result.string(0, body.height, "\\" + "-".repeat(body.width) + "/")
            }
            result.child(body, if (node.name in listOf("overbrace", "underbrace")) 1 else 0, if (node.name == "underbrace") 0 else 1)
            result
        }
    }
}
fun tree(node: Node): String = when (node) {
    is Node.Atom -> when (node.kind) {
        "symbol" -> "'${node.value}'"; "text" -> "\"${node.value}\""; "eqref" -> "(eqref \"${node.value}\")"; else -> node.value
    }
    is Node.Row -> "(row" + node.elements.joinToString("") {
        " " + tree(it)
    } + ")"
    is Node.Binary -> "(${node.name} ${tree(node.first)} ${tree(node.second)})"
    is Node.Root -> node.index?.let {
        "(root ${tree(it)} ${tree(node.body)})"
    } ?: "(sqrt ${tree(node.body)})"
    is Node.Script -> if (node.sub != null && node.sup != null) "(subsup ${tree(node.base)} ${tree(node.sub)} ${tree(node.sup)})" else if (node.sub != null) "(sub ${tree(node.base)} ${tree(node.sub)})" else "(sup ${tree(node.base)} ${tree(node.sup!!)})"
    is Node.Delimited -> {
        fun delimiter(text: String): String = if (text.length == 1) "'$text'" else text
        "(delim ${delimiter(node.left)} ${delimiter(node.right)} ${tree(node.body)})"
    }
    is Node.Matrix -> "(" + node.name + node.rows.joinToString("") {
        row -> " [" + row.joinToString(" ") {
            tree(it)
        } + "]"
    } + ")"
    is Node.Accent -> "(${node.name} ${tree(node.body)})"
}
fun linear(node: Node, script: Boolean, p: Params, references: Map<String, String>): String {
    fun child(n: Node): String = linear(n, script, p, references)
    fun parenthesize(n: Node, style: Boolean, base: Boolean = false): String {
        val text = linear(n, style, p, references)
        return if (n is Node.Row || n is Node.Binary && n.name == "frac" || base && n is Node.Script) "($text)" else text
    }
    return when (node) {
        is Node.Atom -> display(node.kind, node.value, references)
        is Node.Row -> {
            val gaps = Layout.spacing(node.elements, script, p).gaps
            node.elements.mapIndexed {
                i, n -> (if (i > 0) " ".repeat(gaps[i - 1]) else "") + child(n)
            }.joinToString("")
        }
        is Node.Binary -> if (node.name == "frac") parenthesize(node.first, script) + "/" + parenthesize(node.second, script)
        else if (node.name == "binom") "binom(${child(node.first)}, ${child(node.second)})" else "${node.name}(${linear(node.first, true, p, references)}, ${child(node.second)})"
        is Node.Root -> node.index?.let {
            "root(${linear(it, true, p, references)}, ${child(node.body)})"
        } ?: "sqrt(${child(node.body)})"
        is Node.Script -> parenthesize(node.base, script, true) + (node.sub?.let {
            "_" + parenthesize(it, true)
        } ?: "") + (node.sup?.let {
            "^" + parenthesize(it, true)
        } ?: "")
        is Node.Delimited -> {
            fun delimiter(text: String): String = if (text == ".") "" else if (text == "\\{") "{" else if (text == "\\}") "}" else text
            delimiter(node.left) + child(node.body) + delimiter(node.right)
        }
        is Node.Matrix -> node.name + "[" + node.rows.joinToString("; ") {
            row -> row.joinToString(", ") {
                child(it)
            }
        } + "]"
        is Node.Accent -> "${node.name}(${child(node.body)})"
    }
}
fun warnings(node: Node, references: Map<String, String>, out: MutableList<Pair<Int, String>>) {
    when (node) {
        is Node.Atom -> {
            if (node.kind == "identifier" && Lexer.commandName(node.value)) out.add(Pair(node.column, "${node.value} is a command name; write \\${node.value}"))
            if (node.kind == "eqref" && node.value !in references) out.add(Pair(node.column, "undefined reference \"${node.value}\""))
        }
        is Node.Row -> for (n in node.elements) warnings(n, references, out)
        is Node.Binary -> {
            warnings(node.first, references, out); warnings(node.second, references, out)
        }
        is Node.Root -> {
            node.index?.let {
                warnings(it, references, out)
            }; warnings(node.body, references, out)
        }
        is Node.Script -> {
            warnings(node.base, references, out); node.sub?.let {
                warnings(it, references, out)
            }; node.sup?.let {
                warnings(it, references, out)
            }
        }
        is Node.Delimited -> {
            if (node.left != "." && node.right != "." && Pair(node.left, node.right) !in listOf(Pair("(", ")"), Pair("[", "]"), Pair("|", "|"), Pair("\\{", "\\}"))) out.add(Pair(node.column, "\\left${node.left} closed by \\right${node.right}"))
            warnings(node.body, references, out)
        }
        is Node.Matrix -> for (n in node.rows.flatten()) warnings(n, references, out)
        is Node.Accent -> warnings(node.body, references, out)
    }
}
data class Line(val start: Int, val end: Int, val indent: Int, val width: Int)
fun buildLines(nodes: List<Node>, boxes: List<Box>, types: List<Pair<Int, Int>>, gaps: List<Int>, p: Params, stage: Int): List<Line> {
    val breaks = mutableListOf<Int>()
    for (i in 1 until nodes.size) {
        val node = nodes[i]
        val binary = stage >= 1 && types[i].first == 2 && node is Node.Atom && node.kind == "symbol" && node.value in listOf("+", "-")
        if (types[i].first == 3 || binary || stage >= 2 && types[i - 1].second == 6) breaks.add(i)
    }
    breaks.add(nodes.size)
    val lines = mutableListOf<Line>()
    var start = 0
    var alignment: Pair<Int, Int>? = null
    while (start < nodes.size) {
        val indent = if (start == 0) 0 else alignment?.let {
            if (types[start].first == 3) it.first else it.first + it.second + p.rel
        } ?: p.indent
        fun width(end: Int): Int = boxes.subList(start, end).sumOf {
            it.width
        } + gaps.subList(start, end - 1).sum()
        val candidates = breaks.filter {
            it > start
        }
        val end = candidates.lastOrNull {
            indent + width(it) <= p.width
        } ?: candidates[0]
        if (start == 0) {
            val relation = (start until end).firstOrNull {
                types[it].first == 3
            }
            if (relation != null) alignment = Pair(boxes.take(relation).sumOf {
                it.width
            } + gaps.take(relation).sum(), boxes[relation].width)
        }
        lines.add(Line(start, end, indent, width(end))); start = end
    }
    return lines
}
data class Composition(val placed: List<Child>, val width: Int, val height: Int, val lines: Int, val overfull: List<Pair<Int, Int>>)
fun compose(elements: List<Node>, tag: String?, p: Params, references: Map<String, String>): Composition {
    val spacing = Layout.spacing(elements, false, p)
    val boxes = elements.map {
        typeset(it, false, p, references)
    }
    var lines = emptyList<Line>()
    for (stage in 0..2) {
        lines = buildLines(elements, boxes, spacing.types, spacing.gaps, p, stage); if (lines.all {
            it.indent + it.width <= p.width
        }) break
    }
    val placed = mutableListOf<Child>()
    val overfull = mutableListOf<Pair<Int, Int>>()
    var width = 0
    var y = 0
    for ((k, line) in lines.withIndex()) {
        if (line.indent + line.width > p.width) overfull.add(Pair(k + 1, line.indent + line.width))
        val box = Layout.row(boxes.subList(line.start, line.end), spacing.gaps.subList(line.start, line.end - 1), "line ${k + 1}")
        width = maxOf(width, line.indent + box.width); placed.add(Child("", line.indent, y, box)); y += box.height
    }
    if (tag != null) {
        val x = p.width - tag.length
        val last = placed.last()
        val tagY: Int
        if (x >= last.x + last.node.width + 2) tagY = last.y + last.node.baseline else {
            tagY = y; y++
        }
        val box = Box.text(tag, "tag \"$tag\"")
        width = maxOf(width, x + box.width); placed.add(Child("", x, tagY, box))
    }
    return Composition(placed, width, y, lines.size, overfull)
}
class Record(val text: String) {
    val formula: Formula?
    val error: FormulaError?
    var tag: String? = null
    val warnings = mutableListOf<Pair<Int, String>>()
    init {
        val parsed: Pair<Formula?, FormulaError?> = try {
            Pair(Parser.parse(Lexer.lex(text), text.length + 1), null)
        } catch (failure: FormulaError) {
            Pair(null, failure)
        }
        formula = parsed.first
        error = parsed.second
    }
}
fun readParams(): Params {
    val values = File("input/params.txt").readLines().associate {
        val a = it.split(' '); a[0] to a[1].toInt()
    }
    return Params(values.getValue("width"), values.getValue("indent"), values.getValue("rel_space"), values.getValue("bin_space"), values.getValue("punct_space"), values.getValue("col_gap"), values.getValue("row_gap"))
}
fun diagnostic(number: Int, text: String, column: Int, message: String, out: MutableList<String>) {
    out.addAll(listOf("formula $number, column $column: $message", "  $text", " ".repeat(column + 1) + "^"))
}
fun write(name: String, lines: List<String>) {
    File("output").mkdirs()
    File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n")
}
fun main() {
    val params = readParams()
    val records = File("input/formulas.txt").readLines().map(::Record)
    var counter = 0
    val references = mutableMapOf<String, String>()
    for (record in records) {
        val formula = record.formula ?: continue
        if (formula.tag != null) record.tag = "(${formula.tag.first})"
        else if (formula.label != null) {
            counter++; record.tag = "($counter)"
        }
    }
    for (record in records) {
        val label = record.formula?.label ?: continue
        if (label.first in references) record.warnings.add(Pair(label.second, "duplicate label \"${label.first}\"")) else references[label.first] = record.tag!!
    }
    val rendered = mutableListOf<String>()
    val boxes = mutableListOf<String>()
    val trees = mutableListOf<String>()
    val errors = mutableListOf<String>()
    val kinds = sortedMapOf<String, Int>()
    var valid = 0
    var totalBoxes = 0
    var maxDepth = 0
    var warningCount = 0
    var overfullCount = 0
    for ((i, record) in records.withIndex()) {
        val number = i + 1
        if (i > 0) rendered.add("")
        rendered.add("formula $number")
        val error = record.error
        if (error != null) {
            rendered.add("(error)"); boxes.add("formula $number: error"); trees.add("formula $number: error")
            diagnostic(number, record.text, error.column, error.reason, errors); continue
        }
        val formula = record.formula!!
        valid++
        for (node in formula.elements) warnings(node, references, record.warnings)
        record.warnings.sortBy {
            it.first
        }
        warningCount += record.warnings.size
        for ((column, message) in record.warnings) diagnostic(number, record.text, column, "warning: $message", errors)
        val composition = compose(formula.elements, record.tag, params, references)
        overfullCount += composition.overfull.size
        for ((line, width) in composition.overfull) errors.add("formula $number: line $line is overfull (width $width > ${params.width})")
        val grid = Array(composition.height) {
            CharArray(composition.width) {
                ' '
            }
        }
        for (placed in composition.placed) Canvas.paint(placed.node, placed.x, placed.y, grid)
        val description = Canvas.describe(composition.placed)
        for ((kind, count) in description.kinds) kinds[kind] = kinds.getOrDefault(kind, 0) + count
        totalBoxes += description.lines.size; maxDepth = maxOf(maxDepth, description.depth)
        boxes.add("formula $number: lines=${composition.lines} width=${composition.width} height=${composition.height} boxes=${description.lines.size} depth=${description.depth}"); boxes.addAll(description.lines)
        rendered.addAll(Canvas.lines(grid))
        val treeText = formula.elements.joinToString(" ") {
            tree(it)
        }
        trees.add("formula $number:" + if (treeText.isEmpty()) "" else " $treeText")
        val text = linear(Node.Row(formula.elements), false, params, references).trimEnd(' ')
        trees.add("  linear:" + if (text.isEmpty()) "" else " $text")
        record.tag?.let {
            trees.add("  tag: $it")
        }
    }
    boxes.add("summary: boxes=$totalBoxes max_depth=$maxDepth")
    for ((kind, count) in kinds) boxes.add("  $kind: $count")
    errors.add("formulas=${records.size} rendered=$valid errors=${records.size - valid} warnings=$warningCount overfull=$overfullCount")
    write("rendered.txt", rendered); write("boxes.txt", boxes); write("trees.txt", trees); write("errors.txt", errors)
}
