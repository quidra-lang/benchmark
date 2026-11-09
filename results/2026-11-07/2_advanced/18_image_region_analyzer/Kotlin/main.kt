import kotlin.math.abs

class Rational(originalNumerator: Long, originalDenominator: Long = 1) : Comparable<Rational> {
    val numerator: Long
    val denominator: Long
    init {
        var n = originalNumerator
        var d = originalDenominator
        if (d < 0) { n = -n; d = -d }
        var first = abs(n)
        var second = d
        while (second != 0L) { val remainder = first % second; first = second; second = remainder }
        numerator = n / first
        denominator = d / first
    }
    override operator fun compareTo(other: Rational) = (numerator * other.denominator).compareTo(other.numerator * denominator)
}
private const val SYMBOLS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
private val ORIENTATIONS = listOf("none", "horizontal", "vertical", "falling", "rising")
private const val CSV_HEADER = "image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border,perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent,depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area,solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,distance2,codes"
private val FOUR = listOf(Pixel(1, 0), Pixel(0, -1), Pixel(-1, 0), Pixel(0, 1))
private val EIGHT = listOf(Pixel(1, 0), Pixel(1, -1), Pixel(0, -1), Pixel(-1, -1), Pixel(-1, 0), Pixel(-1, 1), Pixel(0, 1), Pixel(1, 1))
private data class Setting(val name: String, val connectivity: Int, val threshold: String, val polarity: String, val operations: List<String>) {
    fun method() = if (threshold == "otsu" || threshold == "isodata") threshold else "fixed"
}
private class Parameters {
    var otsuTop = 0
    var sweepStep = 0
    var bayMin = 0
    var isotropy = Rational(0)
    val elements = mutableMapOf<String, List<Pixel>>()
    val settings = mutableMapOf<String, Setting>()
}
private data class Condition(val feature: String, val comparison: String, val text: String) {
    fun holds(region: Region): Boolean {
        val result = if (feature == "orientation") region.orientation.compareTo(text) else region.features.getValue(feature).compareTo(parseRational(text))
        return when (comparison) { "<" -> result < 0; "<=" -> result <= 0; ">" -> result > 0; ">=" -> result >= 0; "=" -> result == 0; "!=" -> result != 0; else -> error("Unknown comparison") }
    }
    fun words() = "$feature $comparison $text"
}
private data class Rule(val name: String, val conditions: List<Condition>) {
    fun matches(region: Region) = conditions.all { it.holds(region) }
}
private class Rules {
    val filters = mutableListOf<Condition>()
    val classes = mutableListOf<Rule>()
    val flags = mutableListOf<Rule>()
    fun classNames() = classes.map { it.name }.distinct() + "other"
}
private data class Hole(val number: Int, val pixels: List<Pixel>, val owner: Int)
private class Region(val number: Int, val pixels: List<Pixel>) {
    val features = mutableMapOf<String, Rational>()
    var codes = listOf<Int>()
    var skeleton = setOf<Pixel>()
    var hullDoubled = 0L
    var distance = 0L
    var parent: Region? = null
    var depth = 0
    var droppedBy = -1
    var neighbor = -1
    val children = mutableListOf<Region>()
    var kept = false
    var className = "other"
    var orientation = "none"
    val flags = mutableListOf<String>()
    fun put(name: String, value: Long) { features[name] = Rational(value) }
    fun put(name: String, value: Int) = put(name, value.toLong())
    fun put(name: String, numerator: Long, denominator: Long) { features[name] = Rational(numerator, denominator) }
    fun put(name: String, numerator: Int, denominator: Long) = put(name, numerator.toLong(), denominator)
    fun integer(name: String) = features.getValue(name).numerator
}
private fun parseRational(text: String): Rational {
    val parts = text.split('/')
    return Rational(parts[0].toLong(), if (parts.size == 1) 1L else parts[1].toLong())
}
private fun readParameters(path: String): Parameters {
    val result = Parameters()
    for (line in PgmReader.lines(path)) {
        val words = line.split(' ')
        when (words[0]) {
            "otsu_top" -> result.otsuTop = words[1].toInt()
            "sweep" -> result.sweepStep = words[1].toInt()
            "isotropy" -> result.isotropy = parseRational(words[1])
            "bay_min" -> result.bayMin = words[1].toInt()
            "element" -> {
                val ox = words[4].toInt()
                val oy = words[5].toInt()
                val offsets = mutableListOf<Pixel>()
                for (y in 6 until words.size) for (x in words[y].indices) if (words[y][x] == '#') offsets.add(Pixel(x - ox, y - 6 - oy))
                result.elements[words[1]] = offsets
            }
            "image" -> result.settings[words[1]] = Setting(words[1], words[2].toInt(), words[3], words[4], words.drop(5))
        }
    }
    return result
}
private fun readRules(path: String): Rules {
    val result = Rules()
    for (line in PgmReader.lines(path)) {
        val words = line.split(' ')
        if (words[0] == "filter") result.filters.add(Condition(words[1], words[2], words[3]))
        else {
            val conditions = words.drop(2).chunked(3).map { Condition(it[0], it[1], it[2]) }
            (if (words[0] == "class") result.classes else result.flags).add(Rule(words[1], conditions))
        }
    }
    return result
}
private fun count(mask: Array<BooleanArray>) = mask.sumOf { row -> row.count { it } }
private fun groups(labels: Array<IntArray>, count: Int): List<List<Pixel>> {
    val groups = List(count + 1) { mutableListOf<Pixel>() }
    for (y in labels.indices) for (x in labels[0].indices) groups[labels[y][x]].add(Pixel(x, y))
    return groups
}
private fun enclosed(mask: Array<BooleanArray>, connectivity: Int): List<List<Pixel>> {
    val height = mask.size
    val width = mask[0].size
    val background = Array(height) { y -> BooleanArray(width) { x -> !mask[y][x] } }
    val result = Labeling.label(background, connectivity)
    return groups(result.labels, result.count).drop(1).filter { pixels -> pixels.none { it.x == 0 || it.y == 0 || it.x == width - 1 || it.y == height - 1 } }
}
private fun fill(mask: Array<BooleanArray>, connectivity: Int): Array<BooleanArray> {
    val filled = Array(mask.size) { mask[it].copyOf() }
    for (pixels in enclosed(mask, connectivity)) for (point in pixels) filled[point.y][point.x] = true
    return filled
}
private fun cross(a: Pixel, b: Pixel, p: Pixel) = (b.x - a.x).toLong() * (p.y - a.y) - (b.y - a.y).toLong() * (p.x - a.x)
private fun distance(a: Pixel, b: Pixel): Long {
    val dx = (a.x - b.x).toLong()
    val dy = (a.y - b.y).toLong()
    return dx * dx + dy * dy
}
private fun halfHull(points: List<Pixel>): List<Pixel> {
    val chain = mutableListOf<Pixel>()
    for (point in points) {
        while (chain.size >= 2 && cross(chain[chain.size - 2], chain.last(), point) <= 0) chain.removeLast()
        chain.add(point)
    }
    return chain
}
private fun convexHull(pixels: List<Pixel>): List<Pixel> {
    val corners = mutableSetOf<Pixel>()
    for (point in pixels) corners.addAll(listOf(point, Pixel(point.x + 1, point.y), Pixel(point.x, point.y + 1), Pixel(point.x + 1, point.y + 1)))
    val ordered = corners.sortedWith(compareBy<Pixel> { it.x }.thenBy { it.y })
    return halfHull(ordered).dropLast(1) + halfHull(ordered.reversed()).dropLast(1)
}
private fun containsCenter(hull: List<Pixel>, x: Int, y: Int): Boolean {
    val center = Pixel(2 * x + 1, 2 * y + 1)
    for (i in hull.indices) {
        val a = hull[i]
        val b = hull[(i + 1) % hull.size]
        if (cross(Pixel(2 * a.x, 2 * a.y), Pixel(2 * b.x, 2 * b.y), center) < 0) return false
    }
    return true
}
private fun meanText(total: Long, count: Int) = if (count == 0) "-" else Report.decimal(Rational(total, count.toLong()), 2)
private fun orientationLine(regions: List<Region>): String {
    val parts = mutableListOf("orientations")
    for (name in ORIENTATIONS) { parts.add(name); parts.add(regions.count { it.orientation == name }.toString()) }
    return parts.joinToString(" ")
}
private class Analysis(val image: Image, val setting: Setting, val parameters: Parameters) {
    val width = image.width
    val height = image.height
    val connectivity = setting.connectivity
    val complement = 12 - connectivity
    val histogram = Histogram(image)
    val otsu = Threshold.otsu(histogram)
    val isodata = Threshold.isodata(histogram)
    val cutoff = when (setting.threshold) { "otsu" -> otsu.cutoff; "isodata" -> isodata.cutoff; else -> setting.threshold.toInt() }
    val initial = binarize(cutoff)
    val mask: Array<BooleanArray>
    val morphCounts = mutableListOf<Int>()
    val sweep = mutableListOf<IntArray>()
    val labels: Array<IntArray>
    val holeOf = Array(height) { IntArray(width) }
    val provisional: Int
    val fourComponents: Int
    val eightComponents: Int
    val bitQuad: Int
    val regions = mutableListOf<Region>()
    val holes = mutableListOf<Hole>()
    init {
        var current = initial
        for (operation in setting.operations) { current = this.operation(current, operation); morphCounts.add(count(current)) }
        mask = current
        for (t in parameters.sweepStep until image.maxval step parameters.sweepStep) {
            val binary = binarize(t)
            sweep.add(intArrayOf(t, count(binary), Labeling.label(binary, connectivity).count))
        }
        val labeled = Labeling.label(mask, connectivity)
        labels = labeled.labels
        provisional = labeled.provisional
        val pixels = groups(labels, labeled.count)
        for (j in 1..labeled.count) regions.add(Region(j, pixels[j]))
        fourComponents = Labeling.label(mask, 4).count
        eightComponents = Labeling.label(mask, 8).count
        bitQuad = Labeling.bitQuad(mask, connectivity)
        for (holePixels in enclosed(mask, complement)) {
            val first = holePixels[0]
            val hole = Hole(holes.size + 1, holePixels, labels[first.y - 1][first.x])
            holes.add(hole)
            for (point in holePixels) holeOf[point.y][point.x] = hole.number
        }
        for (region in regions) {
            val first = region.pixels[0]
            if (first.y >= 1 && holeOf[first.y - 1][first.x] > 0) {
                val owner = holes[holeOf[first.y - 1][first.x] - 1].owner
                val parent = regions[owner - 1]
                region.parent = parent
                region.depth = parent.depth + 1
                parent.children.add(region)
            }
        }
        for (region in regions) measure(region)
    }
    fun binarize(threshold: Int) = Array(height) { y -> BooleanArray(width) { x ->
        if (setting.polarity == "bright") image.pixels[y][x] > threshold else image.pixels[y][x] <= threshold
    } }
    fun operation(source: Array<BooleanArray>, operation: String): Array<BooleanArray> {
        if (operation == "fill") return fill(source, complement)
        val words = operation.split(':')
        val offsets = parameters.elements.getValue(words[1])
        return when (words[0]) { "erode" -> Morphology.erode(source, offsets); "dilate" -> Morphology.dilate(source, offsets);
            "open" -> Morphology.opening(source, offsets); "close" -> Morphology.closing(source, offsets); else -> error("Unknown operation") }
    }
    fun labelAt(x: Int, y: Int) = if (x in 0 until width && y in 0 until height) labels[y][x] else -1
    fun measure(region: Region) {
        val area = region.pixels.size.toLong()
        var sumI = 0L
        var sumII = 0L
        var sumX = 0L
        var sumY = 0L
        var sumXX = 0L
        var sumYY = 0L
        var sumXY = 0L
        var x0 = width
        var y0 = height
        var x1 = -1
        var y1 = -1
        var minimum = image.maxval
        var maximum = 0
        var perimeter = 0
        var runs = 0
        val surrounding = mutableSetOf<Pixel>()
        val neighbors = if (complement == 4) FOUR else EIGHT
        for (point in region.pixels) {
            val x = point.x
            val y = point.y
            val value = image.pixels[y][x]
            x0 = minOf(x0, x); y0 = minOf(y0, y); x1 = maxOf(x1, x); y1 = maxOf(y1, y)
            minimum = minOf(minimum, value); maximum = maxOf(maximum, value)
            sumI += value; sumII += value.toLong() * value; sumX += x; sumY += y; sumXX += x * x; sumYY += y * y; sumXY += x * y
            for (offset in EIGHT) if (labelAt(x + offset.x, y + offset.y) == 0) surrounding.add(Pixel(x + offset.x, y + offset.y))
            if (neighbors.any { labelAt(x + it.x, y + it.y) != region.number }) perimeter++
            if (labelAt(x - 1, y) != region.number) runs++
        }
        region.put("area", area); region.put("x0", x0); region.put("y0", y0); region.put("x1", x1); region.put("y1", y1)
        region.put("width", x1 - x0 + 1); region.put("height", y1 - y0 + 1)
        region.put("border", if (x0 == 0 || y0 == 0 || x1 == width - 1 || y1 == height - 1) 1 else 0)
        region.put("mean", sumI, area); region.put("variance", area * sumII - sumI * sumI, area * area)
        region.put("min", minimum); region.put("max", maximum)
        val sumSurrounding = surrounding.sumOf { image.pixels[it.y][it.x].toLong() }
        if (surrounding.isEmpty()) region.put("contrast", 0) else region.put("contrast", sumI * surrounding.size - sumSurrounding * area, area * surrounding.size)
        region.put("perimeter", perimeter); region.put("runs", runs); region.codes = chainCode(region)
        val straight = if (connectivity == 4) region.codes.size else region.codes.count { it % 2 == 0 }
        val diagonal = region.codes.size - straight
        val turns = region.codes.indices.count { region.codes[it] != region.codes[(it + region.codes.size - 1) % region.codes.size] }
        region.put("chain", region.codes.size); region.put("straight", straight); region.put("diagonal", diagonal); region.put("turns", turns)
        val length = 5L * straight + 7L * diagonal
        region.put("compactness", length * length, 25 * area)
        val owned = holes.filter { it.owner == region.number }
        region.put("holes", owned.size); region.put("hole_area", owned.sumOf { it.pixels.size }); region.put("euler", 1 - owned.size); region.put("depth", region.depth)
        val m20 = area * sumXX - sumX * sumX
        val m02 = area * sumYY - sumY * sumY
        val m11 = area * sumXY - sumX * sumY
        region.put("cx", sumX, area); region.put("cy", sumY, area); region.put("var_x", m20, area * area); region.put("var_y", m02, area * area)
        region.put("cov_xy", m11, area * area); region.put("hu1", m20 + m02, area * area * area)
        val anisotropy = if (m20 + m02 == 0L) Rational(0) else Rational(abs(m20 - m02) + 2 * abs(m11), m20 + m02)
        region.features["anisotropy"] = anisotropy
        val u = m20 - m02
        val v = 2 * m11
        if (anisotropy > parameters.isotropy) region.orientation = if (abs(v) >= abs(u)) { if (v > 0) "falling" else "rising" } else { if (u > 0) "horizontal" else "vertical" }
        region.put("extent", area, (x1 - x0 + 1).toLong() * (y1 - y0 + 1))
        val lr = region.pixels.count { labelAt(x0 + x1 - it.x, it.y) == region.number }
        val tb = region.pixels.count { labelAt(it.x, y0 + y1 - it.y) == region.number }
        region.put("mirror_lr", lr, area); region.put("mirror_tb", tb, area)
        measureHull(region, x0, y0, x1, y1)
        region.skeleton = Morphology.thin(region.pixels)
        val crossings = region.skeleton.map { Morphology.crossing(region.skeleton, it) }
        region.put("skeleton", region.skeleton.size); region.put("endpoints", crossings.count { it == 1 }); region.put("branches", crossings.count { it >= 3 })
    }
    fun chainCode(region: Region): List<Int> {
        val directions = if (connectivity == 4) FOUR else EIGHT
        val visited = mutableListOf(region.pixels[0])
        val codes = mutableListOf<Int>()
        var heading = directions.size - 1
        while (true) {
            val point = visited.last()
            val start = if (connectivity == 4) (heading + 3) % 4 else (heading + if (heading % 2 == 0) 7 else 6) % 8
            var chosen = -1
            for (offset in directions.indices) {
                val direction = (start + offset) % directions.size
                val delta = directions[direction]
                if (labelAt(point.x + delta.x, point.y + delta.y) == region.number) { chosen = direction; break }
            }
            if (chosen < 0) return emptyList()
            val delta = directions[chosen]
            visited.add(Pixel(point.x + delta.x, point.y + delta.y)); codes.add(chosen); heading = chosen
            val moves = codes.size
            if (moves >= 2 && visited[moves] == visited[1] && visited[moves - 1] == visited[0]) return codes.dropLast(1)
        }
    }
    fun measureHull(region: Region, x0: Int, y0: Int, x1: Int, y1: Int) {
        val hull = convexHull(region.pixels)
        var doubled = 0L
        var feret = 0L
        var width2: Rational? = null
        for (i in hull.indices) {
            val a = hull[i]
            val b = hull[(i + 1) % hull.size]
            doubled += a.x.toLong() * b.y - b.x.toLong() * a.y
            var reach = 0L
            for (point in hull) { reach = maxOf(reach, abs(cross(a, b, point))); feret = maxOf(feret, distance(a, point)) }
            val trial = Rational(reach * reach, distance(a, b))
            if (width2 == null || trial < width2) width2 = trial
        }
        val width = requireNotNull(width2)
        region.hullDoubled = abs(doubled)
        region.put("solidity", 2L * region.pixels.size, region.hullDoubled); region.put("feret2", feret); region.features["width2"] = width
        region.put("elongation", feret * width.denominator, width.numerator)
        val bayMask = Array(y1 - y0 + 1) { yy -> BooleanArray(x1 - x0 + 1) { xx ->
            val x = x0 + xx
            val y = y0 + yy
            labels[y][x] == 0 && holeOf[y][x] == 0 && containsCenter(hull, x, y)
        } }
        val bays = Labeling.label(bayMask, complement)
        val sizes = IntArray(bays.count + 1)
        for (row in bays.labels) for (label in row) sizes[label]++
        region.put("bays", sizes.drop(1).count { it >= parameters.bayMin }); region.put("bay_area", sizes.drop(1).sum())
    }
    fun kept() = regions.filter { it.kept }
    fun applyRules(rules: Rules) {
        for (region in regions) {
            for ((i, condition) in rules.filters.withIndex()) if (!condition.holds(region)) { region.droppedBy = i; break }
            if (region.droppedBy >= 0) continue
            region.kept = true
            for (rule in rules.classes) if (rule.matches(region)) { region.className = rule.name; break }
            for (rule in rules.flags) if (rule.matches(region)) region.flags.add(rule.name)
        }
        val kept = kept()
        for (region in kept) for (other in kept) if (other !== region) {
            val dx = region.integer("x0") + region.integer("x1") - other.integer("x0") - other.integer("x1")
            val dy = region.integer("y0") + region.integer("y1") - other.integer("y0") - other.integer("y1")
            val distance = dx * dx + dy * dy
            if (region.neighbor < 0 || distance < region.distance) { region.neighbor = other.number; region.distance = distance }
        }
    }
    fun tree(region: Region): String = if (region.children.isEmpty()) region.number.toString() else "${region.number}(${region.children.joinToString(" ") { tree(it) }})"
    fun thresholdLines(): List<String> {
        val lines = mutableListOf("image ${image.name} size $width $height maxval ${image.maxval}",
            "histogram pixels ${histogram.pixels} min ${histogram.minimum} max ${histogram.maximum} mean ${meanText(histogram.total, histogram.pixels)} median ${histogram.median} mode ${histogram.mode} levels ${histogram.levels}")
        lines.add("bins ${histogram.binWidth} ${histogram.bins.joinToString(" ")}")
        lines.add("otsu threshold ${otsu.cutoff} upper ${otsu.upper} candidates ${otsu.candidates.size}")
        for ((i, candidate) in otsu.candidates.take(parameters.otsuTop).withIndex()) {
            val split = candidate.split
            val gap = Rational(split.sumAbove * split.below - split.sumBelow * split.above, split.below.toLong() * split.above)
            lines.add("rank ${i + 1} t ${candidate.cutoff} below ${split.below} above ${split.above} mean_below ${meanText(split.sumBelow, split.below)} mean_above ${meanText(split.sumAbove, split.above)} gap ${Report.decimal(gap, 2)}")
        }
        lines.add("isodata threshold ${isodata.cutoff} iterations ${isodata.iterations}")
        lines.add("threshold $cutoff ${setting.method()} ${setting.polarity} foreground ${count(initial)}")
        for (i in morphCounts.indices) lines.add("morph ${setting.operations[i]} foreground ${morphCounts[i]}")
        for (result in sweep) lines.add("sweep ${result[0]} foreground ${result[1]} regions ${result[2]}")
        return lines
    }
    fun symbol(x: Int, y: Int, skeletonOnly: Boolean): Char {
        val label = labels[y][x]
        if (label == 0) return if (holeOf[y][x] > 0) ':' else '.'
        val region = regions[label - 1]
        if (skeletonOnly && Pixel(x, y) !in region.skeleton) return '+'
        return if (region.kept) SYMBOLS[label % 62] else '#'
    }
    fun mapLines(): List<String> {
        val size = "${image.name} $width $height"
        val lines = mutableListOf("morphology $size")
        for (y in 0 until height) lines.add((0 until width).map { x -> if (mask[y][x]) { if (initial[y][x]) '#' else '+' } else { if (initial[y][x]) '-' else '.' } }.joinToString(""))
        for (skeletonOnly in listOf(false, true)) {
            lines.add((if (skeletonOnly) "skeleton " else "labels ") + size)
            for (y in 0 until height) lines.add((0 until width).map { symbol(it, y, skeletonOnly) }.joinToString(""))
        }
        return lines
    }
    fun csv(region: Region): String {
        val fields = CSV_HEADER.split(',').map { field -> when (field) {
            "image" -> image.name
            "label" -> region.number.toString()
            "class" -> region.className
            "flags" -> if (region.flags.isEmpty()) "-" else region.flags.joinToString("+")
            "parent" -> region.parent?.number?.toString() ?: "-"
            "orientation" -> region.orientation
            "hull_area" -> Report.hullArea(region.hullDoubled)
            "neighbor" -> if (region.neighbor < 0) "-" else region.neighbor.toString()
            "distance2" -> if (region.neighbor < 0) "-" else Report.decimal(Rational(region.distance, 4), 2)
            "codes" -> if (region.codes.isEmpty()) "-" else region.codes.joinToString("")
            "cx", "cy", "compactness", "var_x", "var_y", "cov_xy", "anisotropy", "extent", "mirror_lr", "mirror_tb", "solidity", "width2", "elongation" -> Report.decimal(region.features.getValue(field), 3)
            "mean", "variance", "contrast" -> Report.decimal(region.features.getValue(field), 2)
            "hu1" -> Report.decimal(region.features.getValue(field), 4)
            else -> region.integer(field).toString()
        } }
        return fields.joinToString(",")
    }
    fun intensity(foreground: Boolean): String {
        var total = 0L
        var count = 0
        for (y in 0 until height) for (x in 0 until width) if (mask[y][x] == foreground) { total += image.pixels[y][x]; count++ }
        return meanText(total, count)
    }
    fun summary(rules: Rules): List<String> {
        val kept = kept()
        val holePixels = holes.sumOf { it.pixels.size }
        val lines = mutableListOf("image ${image.name}", "threshold $cutoff ${setting.method()} ${setting.polarity} conn $connectivity",
            "foreground ${count(initial)} ${count(mask)}", "regions ${regions.size} provisional $provisional kept ${kept.size} dropped ${regions.size - kept.size}",
            "connectivity four $fourComponents eight $eightComponents", "holes ${holes.size} hole_pixels $holePixels euler ${regions.size - holes.size} bitquad $bitQuad")
        for (hole in holes) {
            val x0 = hole.pixels.minOf { it.x }; val y0 = hole.pixels.minOf { it.y }; val x1 = hole.pixels.maxOf { it.x }; val y1 = hole.pixels.maxOf { it.y }
            lines.add("hole ${hole.number} owner ${hole.owner} area ${hole.pixels.size} box $x0 $y0 $x1 $y1")
        }
        lines.add("depth_max ${regions.maxOfOrNull { it.depth } ?: 0}")
        val roots = regions.filter { it.parent == null }.map { tree(it) }
        lines.add(if (roots.isEmpty()) "tree" else "tree ${roots.joinToString(" ")}")
        lines.add("intensity foreground ${intensity(true)} background ${intensity(false)}")
        if (kept.isEmpty()) lines.add("area total 0 mean - largest - smallest -")
        else {
            val largest = kept.maxBy { it.integer("area") }
            val smallest = kept.minBy { it.integer("area") }
            val total = kept.sumOf { it.integer("area") }
            lines.add("area total $total mean ${meanText(total, kept.size)} largest ${largest.number} ${largest.integer("area")} smallest ${smallest.number} ${smallest.integer("area")}")
        }
        val classes = mutableListOf("classes")
        for (name in rules.classNames()) { classes.add(name); classes.add(kept.count { it.className == name }.toString()) }
        lines.add(classes.joinToString(" ")); lines.add(orientationLine(kept))
        val flags = mutableListOf("flags")
        for (rule in rules.flags) { flags.add(rule.name); flags.add(kept.count { rule.name in it.flags }.toString()) }
        lines.add(flags.joinToString(" "))
        return lines
    }
}
private fun overall(analyses: List<Analysis>, rules: Rules): List<String> {
    val regions = analyses.flatMap { it.regions }
    val kept = regions.filter { it.kept }
    val holeCount = analyses.sumOf { it.holes.size }
    val lines = mutableListOf("overall", "images ${analyses.size}", "regions ${regions.size} kept ${kept.size} dropped ${regions.size - kept.size}", "holes $holeCount euler ${regions.size - holeCount}")
    for ((i, condition) in rules.filters.withIndex()) lines.add("filter ${i + 1} ${condition.words()} dropped ${regions.count { it.droppedBy == i }}")
    for (name in rules.classNames()) {
        val members = kept.filter { it.className == name }
        val total = members.sumOf { it.integer("area") }
        lines.add("class $name count ${members.size} area $total mean ${meanText(total, members.size)}")
    }
    for (rule in rules.flags) lines.add("flag ${rule.name} count ${kept.count { rule.name in it.flags }}")
    lines.add(orientationLine(kept))
    var largest: Region? = null
    var imageName = ""
    for (analysis in analyses) for (region in analysis.kept()) {
        val previous = largest
        if (previous == null || region.integer("area") > previous.integer("area")) { largest = region; imageName = analysis.image.name }
    }
    val finalLargest = largest
    lines.add(if (finalLargest == null) "largest -" else "largest $imageName ${finalLargest.number} ${finalLargest.integer("area")}")
    return lines
}
fun main() {
    val parameters = readParameters("input/params.txt")
    val rules = readRules("input/rules.txt")
    val analyses = PgmReader.read("input/images.txt").map { image ->
        Analysis(image, parameters.settings.getValue(image.name), parameters).also { it.applyRules(rules) }
    }
    val thresholds = mutableListOf<String>()
    val maps = mutableListOf<String>()
    val rows = mutableListOf(CSV_HEADER)
    val summary = mutableListOf<String>()
    for (analysis in analyses) {
        thresholds.addAll(analysis.thresholdLines()); maps.addAll(analysis.mapLines()); rows.addAll(analysis.kept().map { analysis.csv(it) }); summary.addAll(analysis.summary(rules))
    }
    summary.addAll(overall(analyses, rules))
    Report.write(linkedMapOf("thresholds.txt" to thresholds, "labels.txt" to maps, "regions.csv" to rows, "summary.txt" to summary))
}
