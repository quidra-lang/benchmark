private val sides = listOf("top", "right", "bottom", "left")

private val initial = linkedMapOf(
    "display" to "block", "position" to "static", "box-sizing" to "content-box",
    "width" to "auto", "height" to "auto", "min-width" to "0", "min-height" to "0",
    "max-width" to "none", "max-height" to "none", "flex-direction" to "row",
    "flex-wrap" to "nowrap", "justify-content" to "start", "align-items" to "stretch",
    "align-self" to "auto", "row-gap" to "0", "column-gap" to "0", "order" to "0",
    "flex-grow" to "0", "flex-shrink" to "1", "flex-basis" to "auto",
    "grid-template-columns" to "none", "grid-template-rows" to "none",
    "grid-column" to "auto", "grid-row" to "auto"
).apply {
    for (side in sides) {
        put(side, "auto")
        for (kind in listOf("margin", "padding", "border")) put("$kind-$side", "0")
    }
}

private val shorthands = setOf("margin", "padding", "border", "gap")

private fun natural(s: String) = s.length in 1..3 && s.all {
    it in '0'..'9'
}

private fun positive(s: String) = natural(s) && s.toInt() > 0

private fun signed(s: String) = natural(s.removePrefix("-"))

private fun percent(s: String) = s.endsWith('%') && natural(s.dropLast(1))

private fun fraction(s: String) = s.endsWith("fr") && positive(s.dropLast(2))

private fun gridValue(t: List<String>): Boolean = when {
    t == listOf("auto") -> true
    t.size == 1 -> positive(t[0])
    t.size == 2 -> t[0] == "span" && positive(t[1])
    t.size == 3 -> positive(t[0]) && t[1] == "/" && positive(t[2]) && t[0].toInt() < t[2].toInt()
    t.size == 4 -> positive(t[0]) && t[1] == "/" && t[2] == "span" && positive(t[3])
    else -> false
}

private fun valid(prop: String, t: List<String>): Boolean {
    if (prop.startsWith("grid-template-")) return t == listOf("none") || t.all {
        it == "auto" || natural(it) || fraction(it)
    }
    if (prop == "grid-column" || prop == "grid-row") return gridValue(t)
    if (t.size != 1) return false
    val v = t[0]
    return when (prop) {
        "display" -> v in setOf("block", "flex", "grid", "none")
        "position" -> v in setOf("static", "relative", "absolute")
        "box-sizing" -> v in setOf("content-box", "border-box")
        "width", "height", "flex-basis" -> v == "auto" || natural(v) || percent(v)
        "min-width", "min-height" -> natural(v) || percent(v)
        "max-width", "max-height" -> v == "none" || natural(v) || percent(v)
        "top", "right", "bottom", "left" -> v == "auto" || signed(v)
        "order" -> signed(v)
        "flex-direction" -> v in setOf("row", "row-reverse", "column", "column-reverse")
        "flex-wrap" -> v == "nowrap" || v == "wrap"
        "justify-content" -> v in setOf("start", "end", "center", "space-between", "space-around", "space-evenly")
        "align-items" -> v in setOf("stretch", "start", "end", "center")
        "align-self" -> v in setOf("auto", "stretch", "start", "end", "center")
        else -> if (prop.startsWith("border-")) v == "0" || v == "1" else natural(v)
    }
}

private fun declaration(prop: String, value: String): List<Pair<String, String>>? {
    val t = value.split(' ')
    if (prop in initial) return if (valid(prop, t)) listOf(prop to value) else null
    if (prop == "gap") {
        if (t.size !in 1..2 || !t.all(::natural)) return null
        return listOf("row-gap" to t[0], "column-gap" to t.last())
    }
    if (prop in shorthands && t.size in 1..4 && t.all {
        valid("$prop-top", listOf(it))
    }) {
        val pick = when (t.size) {
            1 -> listOf(0, 0, 0, 0)
            2 -> listOf(0, 1, 0, 1)
            3 -> listOf(0, 1, 2, 1)
            else -> listOf(0, 1, 2, 3)
        }
        return sides.indices.map {
            "$prop-${sides[it]}" to t[pick[it]]
        }
    }
    return null
}

private data class Rule(val selectors: List<String>, val values: List<Pair<String, String>>)

private data class Rect(val x: Int, val y: Int, val w: Int, val h: Int) {
    override fun toString() = "$x $y $w $h"
    fun contains(x: Int, y: Int) = x >= this.x && x < this.x + w && y >= this.y && y < this.y + h
    fun contains(r: Rect) = r.x >= x && r.y >= y && r.x + r.w <= x + w && r.y + r.h <= y + h
}

private class Element(val type: String, val id: String, val classes: Set<String>, val text: String?, val parent: Element?, val index: Int) {
    val depth: Int = parent?.let {
        it.depth + 1
    }?: 0
    val children = mutableListOf<Element>()
    val overrides = mutableMapOf<String, String>()
    var style = initial.toMutableMap()
    var displayed = false
    var cw = 0
    var ch = 0
    var rx = 0
    var ry = 0
    var x = 0
    var y = 0
    var lines = listOf<String>()
    fun s(p: String) = style.getValue(p)
    fun n(p: String) = s(p).toInt()
    fun edge(kind: String, i: Int) = n("$kind-${sides[i]}")
    fun frame(horizontal: Boolean) = if (horizontal) edge("padding", 1) + edge("padding", 3) + edge("border", 1) + edge("border", 3) else edge("padding", 0) + edge("padding", 2) + edge("border", 0) + edge("border", 2)
    fun margin(horizontal: Boolean) = if (horizontal) edge("margin", 1) + edge("margin", 3) else edge("margin", 0) + edge("margin", 2)
    fun borderWidth() = cw + frame(true)
    fun borderHeight() = ch + frame(false)
    fun border() = Rect(x, y, borderWidth(), borderHeight())
    fun content() = Rect(x + edge("border", 3) + edge("padding", 3), y + edge("border", 0) + edge("padding", 0), cw, ch)
    fun padding() = Rect(x + edge("border", 3), y + edge("border", 0), cw + edge("padding", 1) + edge("padding", 3), ch + edge("padding", 0) + edge("padding", 2))
    fun marginBox() = Rect(x - edge("margin", 3), y - edge("margin", 0), borderWidth() + margin(true), borderHeight() + margin(false))
    fun flow() = children.filter {
        it.displayed && it.s("position") != "absolute"
    }
    fun items() = flow().sortedWith(compareBy<Element> {
        it.n("order")
    }.thenBy {
        it.index
    })
    fun align(child: Element) = child.s("align-self").let {
        if (it == "auto") s("align-items") else it
    }
    fun resolve(prop: String, reference: Int?, horizontal: Boolean): Int? {
        val v = s(prop)
        if (v == "auto" || v == "none") return null
        val r = if (v.endsWith('%')) reference?.let {
            it * v.dropLast(1).toInt() / 100
        }?: return null else v.toInt()
        return if (s("box-sizing") == "border-box") maxOf(0, r - frame(horizontal)) else r
    }
    fun clamp(v: Int, reference: Int?, horizontal: Boolean): Int {
        val axis = if (horizontal) "width" else "height"
        val lo = resolve("min-$axis", reference, horizontal) ?: 0
        val hi = resolve("max-$axis", reference, horizontal)
        return maxOf(lo, if (hi == null) v else minOf(v, hi))
    }
    fun place(child: Element, x: Int, y: Int) {
        child.rx = x + edge("border", 3) + edge("padding", 3)
        child.ry = y + edge("border", 0) + edge("padding", 0)
    }
}

private data class Area(var row: Int, var col: Int, val rows: Int, val cols: Int)

private data class Grid(val items: List<Element>, val areas: List<Area>, val columns: List<String>, val rows: List<String>, val nc: Int, val nr: Int)

private fun distribution(total: Int, weights: List<Int>): List<Int> {
    val sum = weights.sum()
    if (sum == 0) return List(weights.size) {
        0
    }
    val out = weights.map {
        (total.toLong() * it / sum).toInt()
    }.toMutableList()
    var rest = total - out.sum()
    for (i in weights.indices) if (rest > 0 && weights[i] > 0) {
        out[i]++
        rest--
    }
    return out
}

private fun placement(value: String): Pair<Int, Int> {
    val t = value.split(' ')
    return when {
        t[0] == "auto" -> 0 to 1
        t[0] == "span" -> 0 to t[1].toInt()
        t.size == 1 -> t[0].toInt() to 1
        t.size == 3 -> t[0].toInt() to (t[2].toInt() - t[0].toInt())
        else -> t[0].toInt() to t[3].toInt()
    }
}

private fun grid(e: Element): Grid {
    val items = e.items()
    val columns = if (e.s("grid-template-columns") == "none") listOf("auto") else e.s("grid-template-columns").split(' ')
    val rows = if (e.s("grid-template-rows") == "none") emptyList() else e.s("grid-template-rows").split(' ')
    val areas = items.map {
        val (c, cs) = placement(it.s("grid-column"))
        val (r, rs) = placement(it.s("grid-row"))
        Area(r, c, rs, cs)
    }
    val nc = maxOf(columns.size, areas.maxOfOrNull {
        if (it.col == 0) it.cols else it.col + it.cols - 1
    }?: 0)
    val occupied = mutableSetOf<Pair<Int, Int>>()
    fun mark(a: Area) {
        for (r in a.row until a.row + a.rows) for (c in a.col until a.col + a.cols) occupied.add(r to c)
    }
    fun overlaps(a: Area, row: Int, col: Int): Boolean = (row until row + a.rows).any {
        r -> (col until col + a.cols).any {
            c -> (r to c) in occupied
        }
    }
    for (a in areas) if (a.row != 0 && a.col != 0) mark(a)
    var cr = 1
    var cc = 1
    for (a in areas) {
        if (a.row != 0 && a.col != 0) continue
        if (a.row != 0) {
            a.col = (1..(nc - a.cols + 1)).firstOrNull {
                !overlaps(a, a.row, it)
            }?: 1
        } else if (a.col != 0) {
            if (a.col < cc) cr++
            var r = cr
            while (overlaps(a, r, a.col)) r++
            a.row = r
            cr = r
            cc = a.col + a.cols
        } else {
            var r = cr
            var c = cc
            while (true) {
                if (c + a.cols - 1 > nc) {
                    r++
                    c = 1
                } else if (overlaps(a, r, c)) c++
                else break
            }
            a.row = r
            a.col = c
            cr = r
            cc = c + a.cols
        }
        mark(a)
    }
    val nr = maxOf(rows.size, areas.maxOfOrNull {
        it.row + it.rows - 1
    }?: 0)
    return Grid(items, areas, columns, rows, nc, nr)
}

private fun tracks(g: Grid, horizontal: Boolean, available: Int?, gap: Int, contributions: List<Int>): List<Int> {
    val count = if (horizontal) g.nc else g.nr
    val explicit = if (horizontal) g.columns else g.rows
    val specs = List(count) {
        explicit.getOrElse(it) {
            "auto"
        }
    }
    val sizes = specs.mapIndexed {
        i, spec ->
        when {
            natural(spec) -> spec.toInt()
            fraction(spec) && available != null -> 0
            else -> g.areas.indices.filter {
                val a = g.areas[it]
                (if (horizontal) a.col else a.row) == i + 1 && (if (horizontal) a.cols else a.rows) == 1
            }.maxOfOrNull {
                contributions[it]
            }?: 0
        }
    }.toMutableList()
    if (available != null) {
        val left = available - sizes.sum() - gap * maxOf(0, count - 1)
        if (left > 0) {
            val hasFr = specs.any(::fraction)
            val weights = specs.map {
                if (hasFr) {
                    if (fraction(it)) it.dropLast(2).toInt() else 0
                } else if (it == "auto") 1 else 0
            }
            val extra = distribution(left, weights)
            for (i in sizes.indices) sizes[i] += extra[i]
        }
    }
    return sizes
}

private fun contribution(e: Element): Int = e.clamp(e.resolve("width", null, true) ?: maxContent(e), null, true) + e.frame(true) + e.margin(true)

private fun maxContent(e: Element): Int {
    e.text?.let {
        return it.length
    }
    val children = e.flow()
    return when {
        e.s("display") == "flex" && e.s("flex-direction").startsWith("row") -> children.sumOf(::contribution) + e.n("column-gap") * maxOf(0, children.size - 1)
        e.s("display") == "grid" -> {
            val g = grid(e)
            tracks(g, true, null, e.n("column-gap"), g.items.map(::contribution)).sum() + e.n("column-gap") * (g.nc - 1)
        } else -> children.maxOfOrNull(::contribution) ?: 0
    }
}

private fun wrap(text: String, width: Int): List<String> {
    val lines = mutableListOf<String>()
    for (word in text.split(' ')) {
        if (lines.isEmpty() || lines.last().length + 1 + word.length > width) lines.add(word)
        else lines[lines.lastIndex] += " $word"
    }
    return lines
}

private fun layout(e: Element, cwRef: Int, chRef: Int?, fw: Int? = null, givenHeight: Int? = null): Int {
    e.cw = fw ?: e.clamp(e.resolve("width", cwRef, true) ?: maxOf(0, cwRef - e.margin(true) - e.frame(true)), cwRef, true)
    val fh = givenHeight ?: e.resolve("height", chRef, false)?.let {
        e.clamp(it, chRef, false)
    }
    val a = when {
        e.text != null -> {
            e.lines = wrap(e.text, e.cw)
            e.lines.size
        }
        e.s("display") == "flex" -> flex(e, fh, chRef)
        e.s("display") == "grid" -> gridLayout(e, fh)
        else -> {
            var bottom = 0
            var previous = 0
            var first = true
            for (child in e.flow()) {
                layout(child, e.cw, fh)
                val y = bottom + if (first) child.edge("margin", 0) else maxOf(previous, child.edge("margin", 0))
                e.place(child, child.edge("margin", 3), y)
                bottom = y + child.borderHeight()
                previous = child.edge("margin", 2)
                first = false
            }
            bottom + previous
        }
    }
    e.ch = fh ?: e.clamp(a, chRef, false)
    return a
}

private fun offset(remaining: Int, align: String) = if (remaining <= 0) 0 else when (align) {
    "end" -> remaining
    "center" -> remaining / 2
    else -> 0
}

private fun flex(e: Element, k: Int?, heightReference: Int?): Int {
    val items = e.items()
    val horizontal = e.s("flex-direction").startsWith("row")
    val reverse = e.s("flex-direction").endsWith("reverse")
    val gap = e.n(if (horizontal) "column-gap" else "row-gap")
    val lineGap = e.n("row-gap")
    val reference = if (horizontal) e.cw else k
    val cross = IntArray(items.size)
    val base = IntArray(items.size)
    val hypothetical = IntArray(items.size)
    val outer = items.map {
        it.frame(horizontal) + it.margin(horizontal)
    }
    for ((i, child) in items.withIndex()) {
        if (!horizontal) {
            val r = maxOf(0, e.cw - child.margin(true) - child.frame(true))
            cross[i] = child.clamp(child.resolve("width", e.cw, true) ?: if (e.align(child) == "stretch") r else minOf(maxContent(child), r), e.cw, true)
        }
        base[i] = child.resolve("flex-basis", reference, horizontal) ?: child.resolve(if (horizontal) "width" else "height", reference, horizontal) ?: if (horizontal) maxContent(child) else layout(child, e.cw, k, cross[i])
        hypothetical[i] = child.clamp(base[i], reference, horizontal)
    }
    val length = if (horizontal) e.cw else k ?: e.clamp(items.indices.sumOf {
        hypothetical[it] + outer[it]
    }+ gap * maxOf(0, items.size - 1), heightReference, false)
    val lines = mutableListOf<MutableList<Int>>()
    var used = 0
    for (i in items.indices) {
        val size = hypothetical[i] + outer[i]
        if (lines.isEmpty() || (horizontal && e.s("flex-wrap") == "wrap" && used + gap + size > length)) {
            lines.add(mutableListOf(i))
            used = size
        } else {
            if (lines.last().isNotEmpty()) used += gap
            lines.last().add(i)
            used += size
        }
    }
    var lineStart = 0
    for (line in lines) {
        val totalGap = gap * (line.size - 1)
        val grow = line.sumOf {
            hypothetical[it] + outer[it]
        }+ totalGap < length
        val weights = line.map {
            if (grow) items[it].n("flex-grow") else items[it].n("flex-shrink") * base[it]
        }
        val target = line.map {
            hypothetical[it]
        }.toMutableList()
        val frozen = line.mapIndexed {
            j, i -> weights[j] == 0 || if (grow) base[i] > hypothetical[i] else base[i] < hypothetical[i]
        }.toMutableList()
        while (frozen.any {
            !it
        }) {
            val free = length - totalGap - line.indices.sumOf {
                j -> (if (frozen[j]) target[j] else base[line[j]]) + outer[line[j]]
            }
            val assignments = distribution(maxOf(0, if (grow) free else -free), line.indices.map {
                if (frozen[it]) 0 else weights[it]
            })
            val violations = IntArray(line.size)
            for (j in line.indices) if (!frozen[j]) {
                val tentative = base[line[j]] + if (grow) assignments[j] else -assignments[j]
                target[j] = items[line[j]].clamp(tentative, reference, horizontal)
                violations[j] = target[j] - tentative
            }
            val violation = violations.sum()
            for (j in line.indices) if (violation == 0 || violation > 0 && violations[j] > 0 || violation < 0 && violations[j] < 0) frozen[j] = true
        }
        if (horizontal) for (j in line.indices) {
            val i = line[j]
            layout(items[i], e.cw, k, target[j])
            cross[i] = items[i].ch
        }
        var lineCross = if (!horizontal) e.cw else line.maxOf {
            cross[it] + items[it].frame(false) + items[it].margin(false)
        }
        if (horizontal && lines.size == 1) lineCross = k ?: e.clamp(lineCross, heightReference, false)
        val remaining = length - line.indices.sumOf {
            target[it] + outer[line[it]]
        } - totalGap
        val spaces = MutableList(line.size) {
            0
        }
        if (remaining > 0) when (e.s("justify-content")) {
            "end" -> spaces[0] = remaining
            "center" -> spaces[0] = remaining / 2
            "space-between", "space-around", "space-evenly" -> {
                val mode = e.s("justify-content")
                val w = List(line.size + 1) {
                    j -> if (mode == "space-evenly") 1 else if (j == 0 || j == line.size) {
                        if (mode == "space-between") 0 else 1
                    } else if (mode == "space-around") 2 else 1
                }
                val assigned = distribution(remaining, w)
                for (j in spaces.indices) spaces[j] = assigned[j]
            }
        }
        var cursor = 0
        for (j in line.indices) {
            val i = line[j]
            val child = items[i]
            val align = e.align(child)
            if (horizontal) {
                if (align == "stretch" && child.s("height") == "auto") {
                    cross[i] = child.clamp(maxOf(0, lineCross - child.margin(false) - child.frame(false)), k, false)
                    layout(child, e.cw, k, target[j], cross[i])
                } else {
                    layout(child, e.cw, k, target[j])
                    cross[i] = child.ch
                }
            } else layout(child, e.cw, k, cross[i], target[j])
            cursor += spaces[j]
            val main = if (reverse) length - cursor - target[j] - outer[i] else cursor
            val crossPosition = lineStart + offset(lineCross - cross[i] - child.frame(!horizontal) - child.margin(!horizontal), align)
            if (horizontal) e.place(child, main + child.edge("margin", 3), crossPosition + child.edge("margin", 0))
            else e.place(child, crossPosition + child.edge("margin", 3), main + child.edge("margin", 0))
            cursor += target[j] + outer[i] + gap
        }
        lineStart += lineCross + lineGap
    }
    return if (horizontal) {
        if (lines.isEmpty()) 0 else lineStart - lineGap
    } else length
}

private fun gridLayout(e: Element, k: Int?): Int {
    val g = grid(e)
    val colGap = e.n("column-gap")
    val rowGap = e.n("row-gap")
    val columns = tracks(g, true, e.cw, colGap, g.items.map(::contribution))
    val widths = IntArray(g.items.size)
    val areas = IntArray(g.items.size)
    val contributions = g.items.indices.map {
        i ->
        val a = g.areas[i]
        val child = g.items[i]
        val aw = columns.subList(a.col - 1, a.col - 1 + a.cols).sum() + colGap * (a.cols - 1)
        areas[i] = aw
        widths[i] = child.clamp(child.resolve("width", aw, true) ?: maxOf(0, aw - child.margin(true) - child.frame(true)), aw, true)
        layout(child, aw, null, widths[i])
        child.borderHeight() + child.margin(false)
    }
    val rows = tracks(g, false, k, rowGap, contributions)
    for (i in g.items.indices) {
        val a = g.areas[i]
        val child = g.items[i]
        val align = e.align(child)
        val ah = rows.subList(a.row - 1, a.row - 1 + a.rows).sum() + rowGap * (a.rows - 1)
        val ax = columns.take(a.col - 1).sum() + colGap * (a.col - 1)
        val ay = rows.take(a.row - 1).sum() + rowGap * (a.row - 1)
        val fh = if (align == "stretch" && child.s("height") == "auto") child.clamp(maxOf(0, ah - child.margin(false) - child.frame(false)), ah, false) else null
        layout(child, areas[i], ah, widths[i], fh)
        val dy = offset(ah - child.borderHeight() - child.margin(false), align)
        e.place(child, ax + child.edge("margin", 3), ay + dy + child.edge("margin", 0))
    }
    return rows.sum() + rowGap * maxOf(0, g.nr - 1)
}

private class Document(var width: Int, var height: Int, val rules: List<Rule>, val elements: List<Element>) {
    val byId = elements.associateBy {
        it.id
    }
    fun containing(e: Element): Element? {
        var p = e.parent
        while (p != null) {
            if (p.s("position") != "static") return p
            p = p.parent
        }
        return null
    }
    fun reflow() {
        for (e in elements) {
            e.style = initial.toMutableMap()
            val specificity = mutableMapOf<String, Int>()
            for (rule in rules) {
                val best = rule.selectors.mapNotNull {
                    s -> when {
                        s.startsWith('#') -> if (s.drop(1) == e.id) 2 else null
                        s.startsWith('.') -> if (s.drop(1) in e.classes) 1 else null
                        else -> if (s == e.type) 0 else null
                    }
                }.maxOrNull() ?: continue
                for ((p, v) in rule.values) if (best >= (specificity[p] ?: -1)) {
                    e.style[p] = v
                    specificity[p] = best
                }
            }
            e.style.putAll(e.overrides)
            e.displayed = e.s("display") != "none" && (e.parent?.displayed ?: true)
        }
        val root = elements[0]
        if (root.displayed && root.s("position") != "absolute") {
            layout(root, width, height)
            root.rx = root.edge("margin", 3)
            root.ry = root.edge("margin", 0)
        }
        for (e in elements) if (e.displayed && e.s("position") == "absolute") {
            val block = containing(e)
            val cbw = block?.let {
                it.cw + it.edge("padding", 1) + it.edge("padding", 3)
            }?: width
            val cbh = block?.let {
                it.ch + it.edge("padding", 0) + it.edge("padding", 2)
            }?: height
            fun side(s: String) = e.s(s).let {
                if (it == "auto") null else it.toInt()
            }
            val left = side("left")
            val right = side("right")
            val top = side("top")
            val bottom = side("bottom")
            val r = maxOf(0, cbw - (left ?: 0) - (right ?: 0) - e.margin(true) - e.frame(true))
            val w = e.resolve("width", cbw, true) ?: if (left != null && right != null) r else minOf(maxContent(e), r)
            val fw = e.clamp(w, cbw, true)
            val fh = if (e.s("height") == "auto" && top != null && bottom != null) e.clamp(maxOf(0, cbh - top - bottom - e.margin(false) - e.frame(false)), cbh, false) else null
            layout(e, cbw, cbh, fw, fh)
            e.rx = if (left != null) left + e.edge("margin", 3) else if (right != null) cbw - right - e.edge("margin", 1) - e.borderWidth() else e.edge("margin", 3)
            e.ry = if (top != null) top + e.edge("margin", 0) else if (bottom != null) cbh - bottom - e.edge("margin", 2) - e.borderHeight() else e.edge("margin", 0)
        }
        for (e in elements) if (e.displayed) {
            val ref = if (e.s("position") == "absolute") containing(e) else e.parent
            val bx = if (e.s("position") == "absolute") ref?.let {
                it.x + it.edge("border", 3)
            }?: 0 else ref?.x ?: 0
            val by = if (e.s("position") == "absolute") ref?.let {
                it.y + it.edge("border", 0)
            }?: 0 else ref?.y ?: 0
            var dx = 0
            var dy = 0
            if (e.s("position") == "relative") {
                dx = if (e.s("left") != "auto") e.n("left") else if (e.s("right") != "auto") -e.n("right") else 0
                dy = if (e.s("top") != "auto") e.n("top") else if (e.s("bottom") != "auto") -e.n("bottom") else 0
            }
            e.x = bx + e.rx + dx
            e.y = by + e.ry + dy
        }
    }
    fun snapshot() = elements.map {
        if (it.displayed) it.border() else null
    }
    fun changed(old: List<Rect?>): String = elements.indices.filter {
        old[it] != if (elements[it].displayed) elements[it].border() else null
    }.joinToString(" ") {
        elements[it].id
    }.ifEmpty {
        "no change"
    }
    fun render(): List<String> {
        val screen = Array(height) {
            CharArray(width) {
                '.'
            }
        }
        for (e in elements) if (e.displayed) {
            val b = e.border()
            for (y in maxOf(0, b.y) until minOf(height, b.y + b.h)) for (x in maxOf(0, b.x) until minOf(width, b.x + b.w)) {
                val horizontal = e.edge("border", 0) == 1 && y == b.y || e.edge("border", 2) == 1 && y == b.y + b.h - 1
                val vertical = e.edge("border", 3) == 1 && x == b.x || e.edge("border", 1) == 1 && x == b.x + b.w - 1
                screen[y][x] = if (horizontal && vertical) '+' else if (horizontal) '-' else if (vertical) '|' else ' '
            }
            if (e.text != null) {
                val c = e.content()
                for ((i, line) in e.lines.withIndex()) for ((j, ch) in line.withIndex()) {
                    val x = c.x + j
                    val y = c.y + i
                    if (x in 0 until width && y in 0 until height) screen[y][x] = ch
                }
            }
        }
        val frame = "#".repeat(width + 2)
        return listOf("render ${width}x$height", frame) + screen.map {
            "#${it.concatToString()}#"
        }+ frame
    }
    fun command(line: String): List<String> {
        val a = line.split(' ')
        return when (a[0]) {
            "LAYOUT" -> listOf("layout ${width}x$height") + elements.map {
                "  ".repeat(it.depth) + it.id + if (it.displayed) " ${it.border()}" else " none"
            }
            "BOX" -> {
                val e = byId[a[1]] ?: return listOf("error: unknown element ${a[1]}")
                if (!e.displayed) listOf("box ${e.id}: none") else listOf("box ${e.id}", "margin ${e.marginBox()}", "border ${e.border()}", "padding ${e.padding()}", "content ${e.content()}")
            }
            "RENDER" -> render()
            "HIT" -> {
                val x = a[1].toInt()
                val y = a[2].toInt()
                if (x >= width || y >= height) listOf("error: point $x $y outside viewport")
                else {
                    var e = elements.lastOrNull {
                        it.displayed && it.border().contains(x, y)
                    }
                    val path = mutableListOf<String>()
                    while (e != null) {
                        path.add(e.id)
                        e = e.parent
                    }
                    listOf("hit $x $y: " + if (path.isEmpty()) "none" else path.reversed().joinToString(" > "))
                }
            }
            "SET" -> {
                val id = a[1]
                val p = a[2]
                val value = a.drop(3).joinToString(" ")
                val e = byId[id] ?: return listOf("error: unknown element $id")
                if (p !in initial && p !in shorthands) return listOf("error: unknown property $p")
                val values = declaration(p, value) ?: return listOf("error: invalid value for $p: $value")
                val old = snapshot()
                e.overrides.putAll(values)
                reflow()
                listOf("set $id $p $value: ${changed(old)}")
            }
            "VIEWPORT" -> {
                val w = a[1].toInt()
                val h = a[2].toInt()
                if (w !in 1..80 || h !in 1..40) listOf("error: invalid viewport $w $h")
                else {
                    val old = snapshot()
                    width = w
                    height = h
                    reflow()
                    listOf("viewport $w $h: ${changed(old)}")
                }
            }
            "OVERFLOW" -> {
                val ids = elements.filter {
                    e -> e.displayed && if (e.text != null) e.lines.any {
                        it.length > e.cw
                    } || e.lines.size > e.ch else e.flow().any {
                        !e.content().contains(it.marginBox())
                    }
                }.joinToString(" ") {
                    it.id
                }
                listOf("overflow: " + ids.ifEmpty {
                    "none"
                })
            } else -> listOf("error: unknown command ${a[0]}")
        }
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val size = input.readLine().split(' ').map(String::toInt)
    val rules = mutableListOf<Rule>()
    while (true) {
        val line = input.readLine()
        if (line == "---") break
        val at = line.indexOf(" { ")
        val selectors = line.take(at).split(", ")
        val values = line.substring(at + 3, line.length - 2).split("; ").flatMap {
            d -> val colon = d.indexOf(": ")
            declaration(d.take(colon), d.substring(colon + 2)) ?: emptyList()
        }
        rules.add(Rule(selectors, values))
    }
    val elements = mutableListOf<Element>()
    val ancestors = mutableListOf<Element>()
    while (true) {
        val line = input.readLine()
        if (line == "===") break
        val spaces = line.takeWhile {
            it == ' '
        }.length
        val depth = spaces / 2
        val body = line.drop(spaces)
        val at = body.indexOf(' ')
        val head = if (at < 0) body else body.take(at)
        val text = if (at < 0) null else body.substring(at + 2, body.length - 1)
        val hash = head.indexOf('#')
        val parts = head.substring(hash + 1).split('.')
        val e = Element(head.take(hash), parts[0], parts.drop(1).toSet(), text, if (depth == 0) null else ancestors[depth - 1], elements.size)
        e.parent?.children?.add(e)
        elements.add(e)
        while (ancestors.size > depth) ancestors.removeAt(ancestors.lastIndex)
        ancestors.add(e)
    }
    val document = Document(size[0], size[1], rules, elements)
    document.reflow()
    val output = StringBuilder()
    while (true) {
        val line = input.readLine() ?: break
        if (line == "END") break
        for (result in document.command(line)) output.append(result).append('\n')
    }
    print(output)
}
