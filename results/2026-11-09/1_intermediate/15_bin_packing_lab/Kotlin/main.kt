import java.io.BufferedReader
import java.io.InputStreamReader

private class CommandError(message: String) : RuntimeException(message)
private fun fail(message: String): Nothing = throw CommandError(message)
private fun ceil(a: Long, b: Long) = (a + b - 1) / b

private data class Item(val number: Int, val size: Int) {
    override fun toString() = "$number:$size"
}

private fun descending(items: List<Item>) =
    items.sortedWith(compareByDescending<Item> { it.size }.thenBy { it.number })

private class Bin(val category: Int = 0) {
    val items = mutableListOf<Item>()
    var load = 0

    fun put(item: Item) {
        items.add(item)
        load += item.size
    }

    fun copy() = Bin(category).also {
        it.items.addAll(items)
        it.load = load
    }
}

private data class Step(
    val item: Item, val bin: Int, val inspected: Int,
    val opened: Boolean, val closed: Int, val category: Int
)

private class Packing(val method: String, val parameter: Int) {
    val bins = mutableListOf<Bin>()
    val steps = mutableListOf<Step>()
    var inspections = 0
    var closes = 0

    fun name() = method + if (method == "HARMONIC" || method == "KBOUNDED")
        " k=$parameter" else ""

    fun header(capacity: Int, total: Long): String {
        val line = "${name()} bins=${bins.size} inspections=$inspections " +
            "waste=${bins.size.toLong() * capacity - total}"
        return line + if (method == "KBOUNDED") " closes=$closes" else ""
    }
}

private fun pack(items: List<Item>, capacity: Int, method: String, parameter: Int = 0): Packing {
    val result = Packing(method, parameter)
    val order = if (method in listOf("FFD", "BFD", "WFD")) descending(items) else items
    val active = mutableListOf<Int>()
    val current = mutableMapOf<Int, Int>()
    for (item in order) {
        val before = result.inspections
        var chosen = -1
        var closed = -1
        var category = 0
        when (method) {
            "NEXTFIT" -> {
                if (result.bins.isNotEmpty()) {
                    result.inspections++
                    val last = result.bins.lastIndex
                    if (result.bins[last].load + item.size <= capacity) chosen = last
                }
            }
            "FIRSTFIT", "FFD", "KBOUNDED" -> {
                val candidates = if (method == "KBOUNDED") active else result.bins.indices.toList()
                for (index in candidates) {
                    result.inspections++
                    if (result.bins[index].load + item.size <= capacity) {
                        chosen = index
                        break
                    }
                }
            }
            "HARMONIC" -> {
                category = minOf(capacity / item.size, parameter)
                val index = current[category]
                if (index != null) {
                    result.inspections++
                    if (result.bins[index].load + item.size <= capacity) chosen = index
                }
            }
            else -> {
                result.inspections += result.bins.size
                val fitting = result.bins.indices
                    .filter { result.bins[it].load + item.size <= capacity }
                if (fitting.isNotEmpty()) {
                    chosen = if (method == "BESTFIT" || method == "BFD")
                        fitting.sortedWith(compareByDescending<Int> { result.bins[it].load }
                            .thenBy { it }).first()
                    else {
                        val ordered = fitting.sortedWith(compareBy<Int> { result.bins[it].load }
                            .thenBy { it })
                        if (method == "ALMOSTWORST" && ordered.size >= 2) ordered[1] else ordered[0]
                    }
                }
            }
        }
        val opened = chosen < 0
        if (opened) {
            if (method == "KBOUNDED" && active.size == parameter) {
                closed = active.sortedWith(compareByDescending<Int> { result.bins[it].load }
                    .thenBy { it }).first()
                active.remove(closed)
                result.closes++
            }
            chosen = result.bins.size
            result.bins.add(Bin(category))
            if (method == "KBOUNDED") active.add(chosen)
            if (method == "HARMONIC") current[category] = chosen
        }
        result.bins[chosen].put(item)
        result.steps.add(Step(item, chosen, result.inspections - before,
            opened, closed, category))
    }
    return result
}

private data class BoundRow(val alpha: Int, val j1: Int, val j2: Int, val j3: Int, val bound: Int)
private data class Bounds(val l1: Long, val l2: Int, val rows: List<BoundRow>)

private fun bounds(items: List<Item>, capacity: Int): Bounds {
    val total = items.sumOf { it.size.toLong() }
    val thresholds = sortedSetOf(0)
    for (item in items) if (2 * item.size <= capacity) thresholds.add(item.size)
    val rows = mutableListOf<BoundRow>()
    var lower = 0
    for (alpha in thresholds) {
        var j1 = 0
        var j2 = 0
        var j3 = 0
        var sum2 = 0L
        var sum3 = 0L
        for (item in items) {
            when {
                item.size > capacity - alpha -> j1++
                2 * item.size > capacity -> { j2++; sum2 += item.size }
                item.size >= alpha -> { j3++; sum3 += item.size }
            }
        }
        val excess = sum3 - (j2.toLong() * capacity - sum2)
        val bound = j1 + j2 + if (excess > 0) ceil(excess, capacity.toLong()).toInt() else 0
        lower = maxOf(lower, bound)
        rows.add(BoundRow(alpha, j1, j2, j3, bound))
    }
    return Bounds(ceil(total, capacity.toLong()), lower, rows)
}

private class ExactSearch(
    items: List<Item>, val capacity: Int, val limit: Int, val lower: Int,
    incumbent: List<Bin>, val emit: (String) -> Unit
) {
    private val order = descending(items)
    private val live = mutableListOf<Bin>()
    private val remaining = LongArray(order.size + 1)
    var best = incumbent.map { it.copy() }
    var nodes = 0
    var status: String? = null

    init {
        for (i in order.lastIndex downTo 0)
            remaining[i] = remaining[i + 1] + order[i].size
    }

    fun visit(index: Int) {
        if (nodes == limit) { status = "limit"; return }
        nodes++
        val count = live.size
        val used = remaining[0] - remaining[index]
        val free = count.toLong() * capacity - used
        val excess = remaining[index] - free
        val minimum = count.toLong() +
            (if (excess > 0) ceil(excess, capacity.toLong()) else 0L)
        if (minimum >= best.size) return
        if (index == order.size) {
            best = live.map { it.copy() }
            emit("IMPROVE bins=$count nodes=$nodes")
            if (count == lower) status = "bound"
            return
        }
        val item = order[index]
        val seen = mutableSetOf<Int>()
        for (bin in live) {
            val oldLoad = bin.load
            if (!seen.add(oldLoad) || oldLoad + item.size > capacity) continue
            bin.put(item)
            visit(index + 1)
            bin.items.removeAt(bin.items.lastIndex)
            bin.load = oldLoad
            if (status != null) return
        }
        if (count + 1 < best.size) {
            val bin = Bin()
            bin.put(item)
            live.add(bin)
            visit(index + 1)
            live.removeAt(live.lastIndex)
        }
    }
}

private data class Rect(val number: Int, val width: Int, val height: Int) {
    val letter: Char get() = ('A'.code + number - 1).toChar()
    val area: Int get() = width * height
}

private data class Placement(
    val rect: Rect, val x: Int, val y: Int, val width: Int, val height: Int,
    val rotated: Boolean = false
)

private class Shelf(val bottom: Int, val height: Int) {
    var used = 0
    val placements = mutableListOf<Placement>()
}

private data class FreeRect(val x: Int, val y: Int, val width: Int, val height: Int) {
    val area: Int get() = width * height
    override fun toString() = "$x,$y,${width}x$height"
}

private class Sheet(width: Int, height: Int) {
    val free = mutableListOf(FreeRect(0, 0, width, height))
    val placed = mutableListOf<Placement>()
    var area = 0
}

private data class Piece(val length: Int, val demand: Int)
private data class Pattern(val counts: List<Int>, val trim: Int)

private class Lab {
    private val output = StringBuilder()
    private var items: List<Item>? = null
    private var capacity = 0
    override fun toString() = output.toString()
    fun emit(line: String) { output.appendLine(line) }

    private fun total() = items!!.sumOf { it.size.toLong() }
    private fun parameter(method: String, words: List<String>, index: Int): Int {
        if (method != "HARMONIC" && method != "KBOUNDED") return 0
        return words[index].toInt().also { if (it == 0) fail("BAD PARAMETER") }
    }

    private fun binLine(number: Int, bin: Bin, cap: Int, classes: Boolean = false, over: Boolean = false) {
        var line = "BIN $number load=${bin.load}/$cap items=${bin.items.joinToString(" ")}"
        if (classes) line += " class=${bin.category}"
        if (over) line += " OVER"
        emit(line)
    }

    private fun binLines(bins: List<Bin>, classes: Boolean = false) {
        for ((i, bin) in bins.withIndex()) binLine(i + 1, bin, capacity, classes)
    }

    private fun itemsCommand(words: List<String>) {
        val cap = words[1].toInt()
        if (cap == 0) fail("BAD CAPACITY")
        val next = words.drop(2).mapIndexed { index, text ->
            val size = text.toInt()
            if (size == 0 || size > cap) fail("BAD ITEM ${index + 1}")
            Item(index + 1, size)
        }
        items = next
        capacity = cap
        emit("ITEMS count=${next.size} capacity=$cap total=${total()}")
    }

    private fun random(words: List<String>) {
        val count = words[1].toInt()
        val cap = words[2].toInt()
        var seed = words[3].toLong()
        if (count == 0 || count > 40) fail("BAD COUNT")
        if (cap == 0) fail("BAD CAPACITY")
        if (seed == 0L || seed >= 2147483647L) fail("BAD SEED")
        val next = (1..count).map { number ->
            seed = 48271L * seed % 2147483647L
            Item(number, (seed % cap).toInt() + 1)
        }
        items = next
        capacity = cap
        emit("RANDOM count=$count capacity=$cap total=${total()}")
        emit("SIZES " + next.joinToString(" ") { it.size.toString() })
    }

    private fun runMethod(method: String, k: Int) {
        val result = pack(items!!, capacity, method, k)
        emit(result.header(capacity, total()))
        binLines(result.bins, method == "HARMONIC")
    }

    private fun trace(method: String, k: Int) {
        val result = pack(items!!, capacity, method, k)
        emit("TRACE " + result.header(capacity, total()))
        for ((index, step) in result.steps.withIndex()) {
            var line = "STEP ${index + 1} item=${step.item} bin=${step.bin + 1} " +
                "inspected=${step.inspected}"
            if (step.opened) line += " new"
            if (step.closed >= 0) line += " closed=${step.closed + 1}"
            if (method == "HARMONIC") line += " class=${step.category}"
            emit(line)
        }
    }

    private fun reduce(method: String, k: Int) {
        val result = pack(items!!, capacity, method, k)
        val bins = result.bins
        val before = bins.size
        val events = mutableListOf<String>()
        while (true) {
            var eliminated = false
            val sources = bins.indices.sortedWith(compareBy<Int> { bins[it].load }.thenBy { it })
            for (source in sources) {
                val loads = bins.map { it.load }.toMutableList()
                val moves = mutableListOf<Pair<Item, Int>>()
                var possible = true
                for (item in descending(bins[source].items)) {
                    val target = bins.indices.filter {
                        it != source && loads[it] + item.size <= capacity
                    }.sortedWith(compareByDescending<Int> { loads[it] }.thenBy { it }).firstOrNull()
                    if (target == null) { possible = false; break }
                    loads[target] += item.size
                    moves.add(item to target)
                }
                if (!possible) continue
                val descriptions = moves.joinToString(" ") { "${it.first}->${it.second + 1}" }
                events.add("ELIMINATE bin=${source + 1} load=${bins[source].load} moves=$descriptions")
                for ((item, target) in moves) bins[target].put(item)
                bins.removeAt(source)
                eliminated = true
                break
            }
            if (!eliminated) break
        }
        emit("REDUCE ${result.name()} before=$before after=${bins.size} eliminated=${before - bins.size}")
        for (event in events) emit(event)
        binLines(bins, method == "HARMONIC")
    }

    private fun boundsCommand() {
        val result = bounds(items!!, capacity)
        emit("BOUNDS total=${total()} L1=${result.l1} L2=${result.l2}")
        for (row in result.rows)
            emit("ALPHA ${row.alpha} j1=${row.j1} j2=${row.j2} j3=${row.j3} bound=${row.bound}")
    }

    private fun compare(k: Int) {
        if (k == 0) fail("BAD PARAMETER")
        val result = bounds(items!!, capacity)
        val methods = listOf("NEXTFIT", "FIRSTFIT", "BESTFIT", "WORSTFIT", "ALMOSTWORST",
            "HARMONIC", "KBOUNDED", "FFD", "BFD", "WFD")
        val packed = methods.map { pack(items!!, capacity, it, k) }
            .sortedWith(compareBy<Packing> { it.bins.size }.thenBy { it.method })
        emit("COMPARE k=$k L1=${result.l1} L2=${result.l2}")
        for (p in packed) {
            val count = p.bins.size
            emit("${p.method} bins=$count gap=${count - result.l2} " +
                "waste=${count.toLong() * capacity - total()} inspections=${p.inspections}")
        }
    }

    private fun exact(limit: Int) {
        if (limit == 0) fail("BAD PARAMETER")
        if (items!!.size >= 21) fail("TOO MANY ITEMS")
        val incumbent = pack(items!!, capacity, "FFD").bins
        val lower = bounds(items!!, capacity).l2
        emit("EXACT ffd=${incumbent.size} L2=$lower")
        val search = ExactSearch(items!!, capacity, limit, lower, incumbent, ::emit)
        if (incumbent.size == lower) search.status = "bound" else search.visit(0)
        emit("RESULT bins=${search.best.size} nodes=${search.nodes} status=${search.status ?: "complete"}")
        binLines(search.best)
    }

    private fun check(words: List<String>) {
        if (words.size - 1 != items!!.size) fail("BAD ASSIGNMENT")
        val labels = words.drop(1).map { it.toInt() }
        if (labels.any { it == 0 }) fail("BAD ASSIGNMENT")
        val assigned = sortedMapOf<Int, Bin>()
        for ((index, item) in items!!.withIndex())
            assigned.getOrPut(labels[index]) { Bin() }.put(item)
        val over = assigned.values.count { it.load > capacity }
        val lower = bounds(items!!, capacity).l2
        emit("CHECK bins=${assigned.size} over=$over L2=$lower " +
            "status=${if (over == 0) "valid" else "invalid"}")
        for ((label, bin) in assigned)
            binLine(label, bin, capacity, over = bin.load > capacity)
    }

    private fun coverLines(name: String, bins: List<Bin>) {
        val covered = bins.filter { it.load >= capacity }
        val rest = bins.firstOrNull { it.load < capacity }
        emit("$name covered=${covered.size} rest=${rest?.load ?: 0}")
        binLines(covered)
        if (rest != null) emit("REST items=${rest.items.joinToString(" ")}")
    }

    private fun cover() {
        emit("COVER total=${total()} upper=${total() / capacity}")
        val sequential = mutableListOf<Bin>()
        for (item in items!!) {
            if (sequential.isEmpty() || sequential.last().load >= capacity)
                sequential.add(Bin())
            sequential.last().put(item)
        }
        coverLines("DNF", sequential)
        val ordered = descending(items!!)
        val paired = mutableListOf<Bin>()
        var first = 0
        var last = ordered.lastIndex
        while (first <= last) {
            val bin = Bin()
            bin.put(ordered[first++])
            while (bin.load < capacity && first <= last) bin.put(ordered[last--])
            paired.add(bin)
        }
        coverLines("BIGSMALL", paired)
    }

    private fun machineLines(bins: List<Bin>) {
        for ((index, bin) in bins.withIndex()) {
            val contents = bin.items.joinToString(" ").ifEmpty { "-" }
            emit("MACHINE ${index + 1} load=${bin.load} items=$contents")
        }
    }

    private fun multifit(m: Int) {
        if (m == 0) fail("BAD PARAMETER")
        val largest = items!!.maxOf { it.size }
        var low = maxOf(ceil(total(), m.toLong()).toInt(), largest)
        var high = maxOf(ceil(2 * total(), m.toLong()).toInt(), largest)
        emit("MULTIFIT m=$m lower=$low upper=$high")
        while (low < high) {
            val mid = low + (high - low) / 2
            val count = pack(items!!, mid, "FFD").bins.size
            val ok = count <= m
            emit("TRY cap=$mid bins=$count ${if (ok) "ok" else "fail"}")
            if (ok) high = mid else low = mid + 1
        }
        val machines = pack(items!!, high, "FFD").bins
        while (machines.size < m) machines.add(Bin())
        emit("RESULT cap=$high makespan=${machines.maxOf { it.load }}")
        machineLines(machines)
        val lpt = MutableList(m) { Bin() }
        for (item in descending(items!!))
            lpt.minBy { it.load }.put(item)
        emit("LPT makespan=${lpt.maxOf { it.load }}")
        machineLines(lpt)
    }

    private fun cutstock(words: List<String>) {
        val length = words[1].toInt()
        if (length == 0) fail("BAD CAPACITY")
        val pieces = mutableListOf<Piece>()
        val seen = mutableSetOf<Int>()
        for ((index, word) in words.drop(2).withIndex()) {
            val (sizeText, demandText) = word.split(":")
            val size = sizeText.toInt()
            val demand = demandText.toInt()
            if (size == 0 || size > length || demand == 0)
                fail("BAD PIECE ${index + 1}")
            if (!seen.add(size)) fail("DUPLICATE PIECE ${index + 1}")
            pieces.add(Piece(size, demand))
        }
        pieces.sortByDescending { it.length }
        val patterns = mutableListOf<Pattern>()
        val counts = IntArray(pieces.size)
        fun enumerate(index: Int, remaining: Int) {
            val maximum = remaining / pieces[index].length
            if (index == pieces.lastIndex) {
                counts[index] = maximum
                patterns.add(Pattern(counts.toList(), remaining - maximum * pieces[index].length))
                return
            }
            for (c in maximum downTo 0) {
                counts[index] = c
                enumerate(index + 1, remaining - c * pieces[index].length)
            }
        }
        enumerate(0, length)
        emit("CUTSTOCK L=$length pieces=${pieces.size} patterns=${patterns.size}")
        for ((index, pattern) in patterns.withIndex()) {
            val breakdown = pattern.counts.mapIndexedNotNull { i, c ->
                if (c > 0) "${c}x${pieces[i].length}" else null
            }.joinToString("+")
            emit("PATTERN ${index + 1} $breakdown rest=${pattern.trim}")
        }
        val remaining = pieces.map { it.demand }.toMutableList()
        val cut = IntArray(pieces.size)
        val used = IntArray(patterns.size)
        while (remaining.any { it > 0 }) {
            val chosen = patterns.indices.maxBy { index ->
                patterns[index].counts.indices.sumOf { i ->
                    minOf(patterns[index].counts[i], remaining[i])
                }
            }
            used[chosen]++
            for (i in pieces.indices) {
                val count = patterns[chosen].counts[i]
                cut[i] += count
                remaining[i] = maxOf(0, remaining[i] - count)
            }
        }
        var bars = 0
        var trim = 0
        for (i in patterns.indices) {
            if (used[i] == 0) continue
            emit("USE ${i + 1} bars=${used[i]}")
            bars += used[i]
            trim += used[i] * patterns[i].trim
        }
        val quantity = pieces.sumOf { it.length.toLong() * it.demand }
        val stock = mutableListOf<Item>()
        for ((index, piece) in pieces.withIndex()) {
            emit("PIECE ${piece.length} demand=${piece.demand} cut=${cut[index]}")
            repeat(piece.demand) { stock.add(Item(stock.size + 1, piece.length)) }
        }
        emit("TOTAL bars=$bars trim=$trim surplus=${cut.sum() - pieces.sumOf { it.demand }} " +
            "waste=${bars.toLong() * length - quantity}")
        val ffd = pack(stock, length, "FIRSTFIT").bins.size
        emit("FFD bars=$ffd waste=${ffd.toLong() * length - quantity}")
        emit("LOWER bars=${ceil(quantity, length.toLong())}")
    }

    private fun rectangles(words: List<String>, start: Int, width: Int, height: Int, rotate: Boolean): List<Rect> {
        return words.drop(start).mapIndexed { index, text ->
            val (wText, hText) = text.split("x")
            val w = wText.toInt()
            val h = hText.toInt()
            val fits = if (height == 0) w <= width
                else (w <= width && h <= height) || (rotate && h <= width && w <= height)
            if (w == 0 || h == 0 || !fits) fail("BAD RECT ${index + 1}")
            Rect(index + 1, w, h)
        }
    }

    private fun draw(width: Int, height: Int, placements: List<Placement>) {
        val grid = Array(height) { CharArray(width) { '.' } }
        for (p in placements) {
            for (y in p.y until p.y + p.height)
                for (x in p.x until p.x + p.width)
                    grid[y][x] = p.rect.letter
        }
        for (y in height - 1 downTo 0) emit(grid[y].concatToString())
    }

    private fun shelf(words: List<String>) {
        val width = words[1].toInt()
        if (width == 0) fail("BAD CAPACITY")
        val source = rectangles(words, 2, width, 0, false)
        val area = source.sumOf { it.area }
        emit("SHELF W=$width rects=${source.size} area=$area")
        val order = source.sortedWith(compareByDescending<Rect> { it.height }
            .thenByDescending { it.width }.thenBy { it.number })
        for (method in listOf("NFDH", "FFDH", "BFDH")) {
            val shelves = mutableListOf<Shelf>()
            val placements = mutableListOf<Placement>()
            for (rect in order) {
                var chosen: Shelf? = null
                if (method == "NFDH") {
                    if (shelves.isNotEmpty() && shelves.last().used + rect.width <= width)
                        chosen = shelves.last()
                } else {
                    val fitting = shelves.filter { it.used + rect.width <= width }
                    chosen = if (method == "FFDH") fitting.firstOrNull()
                        else fitting.maxByOrNull { it.used }
                }
                if (chosen == null) {
                    val bottom = if (shelves.isEmpty()) 0 else shelves.last().bottom + shelves.last().height
                    chosen = Shelf(bottom, rect.height)
                    shelves.add(chosen)
                }
                val p = Placement(rect, chosen.used, chosen.bottom, rect.width, rect.height)
                chosen.placements.add(p)
                placements.add(p)
                chosen.used += rect.width
            }
            val height = shelves.last().bottom + shelves.last().height
            emit("$method height=$height shelves=${shelves.size} util=${area.toLong() * 100 / (width * height)}")
            for ((i, shelf) in shelves.withIndex()) {
                val content = shelf.placements.joinToString(" ") { "${it.rect.letter}@${it.x}" }
                emit("LEVEL ${i + 1} y=${shelf.bottom} h=${shelf.height} used=${shelf.used} items=$content")
            }
            draw(width, height, placements)
        }
        val columns = IntArray(width)
        val skyline = mutableListOf<Placement>()
        for (rect in order) {
            var bestX = 0
            var bestY = Int.MAX_VALUE
            for (x in 0..width - rect.width) {
                val top = (x until x + rect.width).maxOf { columns[it] }
                if (top < bestY) { bestX = x; bestY = top }
            }
            skyline.add(Placement(rect, bestX, bestY, rect.width, rect.height))
            for (x in bestX until bestX + rect.width) columns[x] = bestY + rect.height
        }
        val height = columns.max()
        emit("SKYLINE height=$height util=${area.toLong() * 100 / (width * height)}")
        for (p in skyline)
            emit("PLACE ${p.rect.letter} x=${p.x} y=${p.y} w=${p.width} h=${p.height}")
        draw(width, height, skyline)
    }

    private fun fits(rect: Rect, free: FreeRect, rotate: Boolean) =
        (rect.width <= free.width && rect.height <= free.height) ||
            (rotate && rect.height <= free.width && rect.width <= free.height)

    private fun guillotine(words: List<String>) {
        val width = words[1].toInt()
        val height = words[2].toInt()
        if (width == 0 || height == 0) fail("BAD CAPACITY")
        val rotate = words[3] == "ROTATE"
        val best = words[4] == "BEST"
        val order = rectangles(words, 5, width, height, rotate)
            .sortedWith(compareByDescending<Rect> { it.area }.thenBy { it.number })
        val area = order.sumOf { it.area }
        val sheets = mutableListOf<Sheet>()
        var rotated = 0
        for (rect in order) {
            var chosenSheet: Sheet? = null
            var chosenIndex = -1
            var chosenArea = Int.MAX_VALUE
            for (sheet in sheets) {
                for ((index, free) in sheet.free.withIndex()) {
                    if (!fits(rect, free, rotate)) continue
                    if (chosenSheet == null || (best && free.area < chosenArea)) {
                        chosenSheet = sheet
                        chosenIndex = index
                        chosenArea = free.area
                    }
                    if (!best) break
                }
                if (chosenSheet != null && !best) break
            }
            if (chosenSheet == null) {
                chosenSheet = Sheet(width, height)
                sheets.add(chosenSheet)
                chosenIndex = 0
            }
            val sheet = chosenSheet
            val free = sheet.free.removeAt(chosenIndex)
            val turned = rect.width > free.width || rect.height > free.height
            val w = if (turned) rect.height else rect.width
            val h = if (turned) rect.width else rect.height
            if (turned) rotated++
            sheet.placed.add(Placement(rect, free.x, free.y, w, h, turned))
            sheet.area += rect.area
            val rw = free.width - w
            val rh = free.height - h
            val top = if (rw <= rh) FreeRect(free.x, free.y + h, free.width, rh)
                else FreeRect(free.x, free.y + h, w, rh)
            val right = if (rw <= rh) FreeRect(free.x + w, free.y, rw, h)
                else FreeRect(free.x + w, free.y, rw, free.height)
            if (top.width > 0 && top.height > 0) sheet.free.add(top)
            if (right.width > 0 && right.height > 0) sheet.free.add(right)
        }
        emit("GUILLOTINE W=$width H=$height mode=${words[3]} rule=${words[4]} " +
            "rects=${order.size} sheets=${sheets.size} rotated=$rotated " +
            "util=${area.toLong() * 100 / (sheets.size * width * height)}")
        for ((index, sheet) in sheets.withIndex()) {
            emit("SHEET ${index + 1} placed=${sheet.placed.size} area=${sheet.area}")
            for (p in sheet.placed) {
                val rotation = if (p.rotated) " rotated" else ""
                emit("PLACE ${p.rect.letter} x=${p.x} y=${p.y} w=${p.width} h=${p.height}$rotation")
            }
            emit(if (sheet.free.isEmpty()) "FREE none" else "FREE ${sheet.free.joinToString(" ")}")
            draw(width, height, sheet.placed)
        }
    }

    fun process(words: List<String>) {
        try {
            when (val command = words[0]) {
                "ITEMS" -> itemsCommand(words)
                "RANDOM" -> random(words)
                "CUTSTOCK" -> cutstock(words)
                "SHELF" -> shelf(words)
                "GUILLOTINE" -> guillotine(words)
                else -> {
                    if (items == null) fail("NO ITEMS")
                    when (command) {
                        "NEXTFIT", "FIRSTFIT", "BESTFIT", "WORSTFIT", "ALMOSTWORST",
                        "HARMONIC", "KBOUNDED", "FFD", "BFD", "WFD" ->
                            runMethod(command, parameter(command, words, 1))
                        "TRACE" -> trace(words[1], parameter(words[1], words, 2))
                        "REDUCE" -> reduce(words[1], parameter(words[1], words, 2))
                        "BOUNDS" -> boundsCommand()
                        "COMPARE" -> compare(words[1].toInt())
                        "EXACT" -> exact(words[1].toInt())
                        "CHECK" -> check(words)
                        "COVER" -> cover()
                        "MULTIFIT" -> multifit(words[1].toInt())
                    }
                }
            }
        } catch (error: CommandError) {
            emit("ERROR ${error.message}")
        }
    }
}

fun main() {
    val input = BufferedReader(InputStreamReader(System.`in`))
    val count = input.readLine()?.toInt() ?: return
    val lab = Lab()
    repeat(count) { lab.process(input.readLine().split(" ")) }
    print(lab)
}
