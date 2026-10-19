import java.util.ArrayDeque

private class CommandError(message: String) : RuntimeException(message)

private fun check(ok: Boolean, reason: String = "bad value") {
    if (!ok) throw CommandError(reason)
}

private data class Point(val x: Int, val y: Int)

private data class Command(
    val name: String, val args: List<Int>, val slot: String, val fill: Boolean
)

private val directions4 = listOf(Point(0, -1), Point(-1, 0), Point(1, 0), Point(0, 1))
private val directions8 = (-1..1).flatMap { dy ->
    (-1..1).mapNotNull { dx -> if (dx == 0 && dy == 0) null else Point(dx, dy) }
}
private val shades = "@#*+=~-:,."

private class Image(
    val width: Int, val height: Int, val maxval: Int, val pixels: IntArray
) {
    fun get(x: Int, y: Int): Int = pixels[y * width + x]
    fun contains(x: Int, y: Int): Boolean = x in 0 until width && y in 0 until height
    fun clamp(value: Int): Int = value.coerceIn(0, maxval)
    fun withPixels(values: IntArray): Image = Image(width, height, maxval, values)
    fun map(change: (Int) -> Int): Image = withPixels(pixels.map(change).toIntArray())

    fun neighborhood(x: Int, y: Int): IntArray {
        val result = IntArray(9)
        var index = 0
        for (dy in -1..1) {
            for (dx in -1..1) {
                result[index++] = get(
                    (x + dx).coerceIn(0, width - 1),
                    (y + dy).coerceIn(0, height - 1)
                )
            }
        }
        return result
    }

    fun summary(): String {
        var checksum = 0L
        for (i in pixels.indices) checksum += (i + 1).toLong() * pixels[i]
        return width.toString() + "x" + height + " maxval " + maxval +
            " checksum " + checksum
    }
}

private fun loadPgm(lines: List<String>): Image {
    val words = lines.flatMap { line ->
        line.substringBefore('#').trim().split(Regex(" +")).filter { it.isNotEmpty() }
    }
    check(words.isNotEmpty() && words[0] == "P2", "bad magic")

    fun header(index: Int, limit: Int, reason: String): Int {
        check(index < words.size, "truncated header")
        check(words[index].all { it in '0'..'9' }, "bad number")
        val number = words[index].toInt()
        check(number in 1..limit, reason)
        return number
    }

    val width = header(1, 64, "bad size")
    val height = header(2, 64, "bad size")
    val maxval = header(3, 255, "bad maxval")
    val count = words.size - 4
    val pixels = IntArray(width * height)
    for (index in pixels.indices) {
        val x = index % width
        val y = index / width
        check(index < count, "too few pixels (" + count + " of " + pixels.size + ")")
        val word = words[index + 4]
        check(word.all { it in '0'..'9' }, "bad pixel at " + x + "," + y)
        val value = word.toInt()
        check(value <= maxval, "pixel out of range at " + x + "," + y)
        pixels[index] = value
    }
    check(count <= pixels.size, "too many pixels (" + count + " of " + pixels.size + ")")
    return Image(width, height, maxval, pixels)
}

private fun transformed(
    image: Image, width: Int = image.width, height: Int = image.height,
    pixel: (Int, Int) -> Int
): Image = Image(width, height, image.maxval, IntArray(width * height) {
    pixel(it % width, it / width)
})

private fun cropped(image: Image, x: Int, y: Int, width: Int, height: Int) =
    transformed(image, width, height) { i, j -> image.get(x + i, y + j) }

private fun translated(
    image: Image, width: Int, height: Int, dx: Int, dy: Int, fill: Int
): Image = transformed(image, width, height) { x, y ->
    if (image.contains(x - dx, y - dy)) image.get(x - dx, y - dy) else fill
}

private fun convolution(image: Image, weights: IntArray, denominator: Int) =
    transformed(image) { x, y ->
        val q = image.neighborhood(x, y)
        var total = 0
        for (i in 0 until 9) total += q[i] * weights[i]
        image.clamp(Math.floorDiv(total, denominator))
    }

private fun rankFiltered(image: Image, rank: Int) =
    transformed(image) { x, y -> image.neighborhood(x, y).sorted()[rank] }

private fun sobel(image: Image) = transformed(image) { x, y ->
    val q = image.neighborhood(x, y)
    val gx = q[2] + 2 * q[5] + q[8] - q[0] - 2 * q[3] - q[6]
    val gy = q[6] + 2 * q[7] + q[8] - q[0] - 2 * q[1] - q[2]
    image.clamp(kotlin.math.abs(gx) + kotlin.math.abs(gy))
}

private fun linePoints(x0: Int, y0: Int, x1: Int, y1: Int): List<Point> {
    val dx = kotlin.math.abs(x1 - x0)
    val dy = -kotlin.math.abs(y1 - y0)
    val sx = if (x0 < x1) 1 else -1
    val sy = if (y0 < y1) 1 else -1
    var error = dx + dy
    var x = x0
    var y = y0
    val points = mutableListOf<Point>()
    while (true) {
        points.add(Point(x, y))
        if (x == x1 && y == y1) break
        val twice = 2 * error
        if (twice >= dy) { error += dy; x += sx }
        if (twice <= dx) { error += dx; y += sy }
    }
    return points
}

private fun rectanglePoints(
    image: Image, left: Int, top: Int, width: Int, height: Int, fill: Boolean
): List<Point> {
    val right = left + width - 1
    val bottom = top + height - 1
    val points = mutableListOf<Point>()
    for (y in maxOf(0, top)..minOf(bottom, image.height - 1)) {
        for (x in maxOf(0, left)..minOf(right, image.width - 1)) {
            if (fill || x == left || x == right || y == top || y == bottom)
                points.add(Point(x, y))
        }
    }
    return points
}

private fun circlePoints(cx: Int, cy: Int, radius: Int): List<Point> {
    var a = radius
    var b = 0
    var error = 1 - radius
    val points = mutableListOf<Point>()
    while (a >= b) {
        points.addAll(listOf(
            Point(cx + a, cy + b), Point(cx + b, cy + a),
            Point(cx - b, cy + a), Point(cx - a, cy + b),
            Point(cx - a, cy - b), Point(cx - b, cy - a),
            Point(cx + b, cy - a), Point(cx + a, cy - b)
        ))
        b++
        if (error < 0) error += 2 * b + 1
        else { a--; error += 2 * (b - a) + 1 }
    }
    return points
}

private fun discPoints(image: Image, outline: List<Point>): List<Point> {
    val rows = mutableMapOf<Int, Pair<Int, Int>>()
    for ((x, y) in outline) {
        val previous = rows[y]
        rows[y] = if (previous == null) x to x
            else minOf(previous.first, x) to maxOf(previous.second, x)
    }
    return rows.flatMap { (y, bounds) ->
        if (y !in 0 until image.height) emptyList()
        else (maxOf(0, bounds.first)..minOf(bounds.second, image.width - 1))
            .map { x -> Point(x, y) }
    }
}

private fun floodPoints(image: Image, x: Int, y: Int): List<Point> {
    val target = image.get(x, y)
    val stack = ArrayDeque<Point>()
    val visited = mutableSetOf(y * image.width + x)
    val points = mutableListOf<Point>()
    stack.addLast(Point(x, y))
    while (stack.isNotEmpty()) {
        val position = stack.removeLast()
        points.add(position)
        for (direction in directions4) {
            val nx = position.x + direction.x
            val ny = position.y + direction.y
            if (!image.contains(nx, ny) || image.get(nx, ny) != target) continue
            if (visited.add(ny * image.width + nx)) stack.addLast(Point(nx, ny))
        }
    }
    return points
}

private fun equalized(image: Image): Image {
    val counts = IntArray(image.maxval + 1)
    for (pixel in image.pixels) counts[pixel]++
    var accumulated = 0
    val cumulative = counts.map { accumulated += it; accumulated }
    val size = image.pixels.size
    val first = cumulative[image.pixels.min()]
    if (first == size) return image.withPixels(image.pixels.copyOf())
    val span = size - first
    return image.map { pixel ->
        (2 * (cumulative[pixel] - first) * image.maxval + span) / (2 * span)
    }
}

private fun components(image: Image, threshold: Int): List<List<Point>> {
    val visited = BooleanArray(image.pixels.size)
    val groups = mutableListOf<List<Point>>()
    for (start in image.pixels.indices) {
        if (visited[start] || image.pixels[start] < threshold) continue
        visited[start] = true
        val stack = ArrayDeque<Point>()
        stack.addLast(Point(start % image.width, start / image.width))
        val group = mutableListOf<Point>()
        while (stack.isNotEmpty()) {
            val position = stack.removeLast()
            group.add(position)
            for (direction in directions8) {
                val nx = position.x + direction.x
                val ny = position.y + direction.y
                if (!image.contains(nx, ny)) continue
                val index = ny * image.width + nx
                if (!visited[index] && image.pixels[index] >= threshold) {
                    visited[index] = true
                    stack.addLast(Point(nx, ny))
                }
            }
        }
        groups.add(group)
    }
    return groups
}

private fun componentText(image: Image, threshold: Int, group: List<Point>): String {
    val x = group.map { it.x }
    val y = group.map { it.y }
    val perimeter = group.count { p ->
        directions4.any { d ->
            !image.contains(p.x + d.x, p.y + d.y) ||
                image.get(p.x + d.x, p.y + d.y) < threshold
        }
    }
    return "area " + group.size + " perimeter " + perimeter +
        " box " + x.min() + " " + y.min() + " " + x.max() + " " + y.max() +
        " center " + (x.sum() / group.size) + " " + (y.sum() / group.size)
}

private fun distanceMap(image: Image, threshold: Int): Image {
    if (image.pixels.all { it >= threshold })
        return image.withPixels(IntArray(image.pixels.size) { image.maxval })
    val w = image.width
    val h = image.height
    val distances = IntArray(image.pixels.size) {
        if (image.pixels[it] < threshold) 0 else w + h
    }
    for (y in 0 until h) {
        for (x in 0 until w) {
            val index = y * w + x
            if (x > 0) distances[index] = minOf(distances[index], distances[index - 1] + 1)
            if (y > 0) distances[index] = minOf(distances[index], distances[index - w] + 1)
        }
    }
    for (y in h - 1 downTo 0) {
        for (x in w - 1 downTo 0) {
            val index = y * w + x
            if (x < w - 1) distances[index] = minOf(distances[index], distances[index + 1] + 1)
            if (y < h - 1) distances[index] = minOf(distances[index], distances[index + w] + 1)
        }
    }
    return image.withPixels(distances.map { minOf(it, image.maxval) }.toIntArray())
}

private fun statistics(pixels: IntArray, maxval: Int): String {
    val sorted = pixels.sorted()
    val counts = IntArray(maxval + 1)
    for (pixel in pixels) counts[pixel]++
    var mode = 0
    for (value in 1..maxval) if (counts[value] > counts[mode]) mode = value
    return "min " + sorted.first() + " max " + sorted.last() +
        " mean " + (pixels.sum() / pixels.size) +
        " median " + sorted[(pixels.size - 1) / 2] + " mode " + mode
}

private fun dithered(image: Image): Image {
    val errors = image.pixels.copyOf()
    val pixels = IntArray(errors.size)
    val diffusion = listOf(Point(1, 0) to 7, Point(-1, 1) to 3,
        Point(0, 1) to 5, Point(1, 1) to 1)
    for (y in 0 until image.height) {
        for (x in 0 until image.width) {
            val index = y * image.width + x
            val old = errors[index]
            val value = if (2 * old >= image.maxval) image.maxval else 0
            pixels[index] = value
            val error = old - value
            for ((delta, weight) in diffusion) {
                val nx = x + delta.x
                val ny = y + delta.y
                if (image.contains(nx, ny))
                    errors[ny * image.width + nx] += Math.floorDiv(error * weight, 16)
            }
        }
    }
    return image.withPixels(pixels)
}

private class Editor {
    private val patterns = mapOf(
        "NEW" to "iiii", "OUTPUT" to "", "INVERT" to "", "BRIGHTNESS" to "i",
        "CONTRAST" to "ii", "THRESHOLD" to "i", "LEVELS" to "ii",
        "POSTERIZE" to "i", "MAXVAL" to "i", "FLIPH" to "", "FLIPV" to "",
        "ROTATE" to "i", "CROP" to "iiii", "PAD" to "ii", "SCALE" to "ii",
        "SHIFT" to "iii", "TILE" to "ii", "BLUR" to "", "GAUSS" to "",
        "SHARPEN" to "", "CONVOLVE" to "iiiiiiiiii", "SOBEL" to "",
        "MEDIAN" to "", "ERODE" to "", "DILATE" to "", "OPEN" to "",
        "CLOSE" to "", "GRADIENT" to "", "LINE" to "iiiii",
        "RECT" to "iiiii", "CIRCLE" to "iiii", "FLOOD" to "iii",
        "HISTOGRAM" to "", "EQUALIZE" to "", "LABEL" to "i",
        "DISTANCE" to "i", "STATS" to "", "REGION" to "iiii",
        "DITHER" to "", "ASCIIART" to "", "STORE" to "n",
        "RECALL" to "n", "DROP" to "n", "BLEND" to "nii", "DIFF" to "n",
        "PASTE" to "nii", "SLOTS" to "", "INFO" to "", "UNDO" to "", "REDO" to ""
    )
    private val imageless = setOf("NEW", "RECALL", "DROP", "SLOTS", "INFO", "UNDO", "REDO")
    private val needsSlot = setOf("RECALL", "DROP", "BLEND", "DIFF", "PASTE")
    private val kernels = mapOf(
        "BLUR" to (intArrayOf(1, 1, 1, 1, 1, 1, 1, 1, 1) to 9),
        "GAUSS" to (intArrayOf(1, 2, 1, 2, 4, 2, 1, 2, 1) to 16),
        "SHARPEN" to (intArrayOf(0, -1, 0, -1, 5, -1, 0, -1, 0) to 1)
    )
    private var current: Image? = null
    private val undo = mutableListOf<Image>()
    private val redo = mutableListOf<Image>()
    private val slots = mutableMapOf<String, Image>()
    val output = mutableListOf<String>()

    private fun emit(line: String) { output.add(line) }

    private fun parse(words: List<String>): Command {
        val name = words.first()
        val pattern = patterns[name] ?: throw CommandError("unknown command " + name)
        var given = words.drop(1)
        val fill = name in setOf("RECT", "CIRCLE") &&
            given.size == pattern.length + 1 && given.last() == "FILL"
        if (fill) given = given.dropLast(1)
        check(given.size == pattern.length, "bad arguments")
        val numbers = mutableListOf<Int>()
        var slot = ""
        for ((i, word) in given.withIndex()) {
            if (pattern[i] == 'i') {
                check(Regex("""(?:0|-?[1-9][0-9]{0,6})""").matches(word), "bad arguments")
                numbers.add(word.toInt())
            } else {
                check(Regex("""[a-z]{1,8}""").matches(word), "bad arguments")
                slot = word
            }
        }
        return Command(name, numbers, slot, fill)
    }

    fun execute(words: List<String>) {
        try {
            val cmd = parse(words)
            if (cmd.name !in imageless) check(current != null, "no image")
            if (cmd.name in needsSlot) check(slots.containsKey(cmd.slot), "no slot " + cmd.slot)
            run(cmd)
        } catch (error: CommandError) {
            emit("error: " + error.message)
        }
    }

    fun load(lines: List<String>) {
        try {
            replace(loadPgm(lines), "loaded")
        } catch (error: CommandError) {
            emit("error: load: " + error.message)
        }
    }

    private fun replace(image: Image, label: String) {
        current = image
        undo.clear()
        redo.clear()
        emit(label + " " + image.summary())
    }

    private fun commit(image: Image, painted: Int? = null) {
        undo.add(current!!)
        redo.clear()
        current = image
        emit("ok " + image.summary() + (if (painted == null) "" else " painted " + painted))
    }

    private fun paint(image: Image, points: List<Point>, value: Int) {
        val touched = points.filter { image.contains(it.x, it.y) }
            .mapTo(mutableSetOf()) { it.y * image.width + it.x }
        val pixels = image.pixels.copyOf()
        for (index in touched) pixels[index] = value
        commit(image.withPixels(pixels), touched.size)
    }

    private fun checkedCrop(image: Image, args: List<Int>): List<Int> {
        val (x, y, width, height) = args
        check(x >= 0 && y >= 0 && width >= 1 && height >= 1)
        check(x + width <= image.width && y + height <= image.height)
        return args
    }

    private fun matchingSlot(image: Image, slot: String): Image {
        val other = slots.getValue(slot)
        check(other.width == image.width && other.height == image.height, "size mismatch")
        check(other.maxval == image.maxval, "maxval mismatch")
        return other
    }

    private fun run(cmd: Command) {
        val a = cmd.args
        val name = cmd.name
        val slot = cmd.slot
        val fill = cmd.fill
        when (name) {
            "NEW" -> {
                val (w, h, maxval, value) = a
                check(w in 1..64 && h in 1..64)
                check(maxval in 1..255 && value in 0..maxval)
                replace(Image(w, h, maxval, IntArray(w * h) { value }), "created")
                return
            }
            "RECALL" -> { replace(slots.getValue(slot), "recalled " + slot); return }
            "DROP" -> { slots.remove(slot); emit("dropped " + slot); return }
            "SLOTS" -> {
                if (slots.isEmpty()) emit("no slots")
                for (key in slots.keys.sorted()) emit(key + " " + slots.getValue(key).summary())
                return
            }
            "INFO" -> {
                emit("image " + (current?.summary() ?: "none") +
                    " undo " + undo.size + " redo " + redo.size + " slots " + slots.size)
                return
            }
            "UNDO" -> {
                check(undo.isNotEmpty(), "nothing to undo")
                redo.add(current!!)
                current = undo.removeAt(undo.lastIndex)
                emit("undo " + current!!.summary())
                return
            }
            "REDO" -> {
                check(redo.isNotEmpty(), "nothing to redo")
                undo.add(current!!)
                current = redo.removeAt(redo.lastIndex)
                emit("redo " + current!!.summary())
                return
            }
        }

        val image = current!!
        val m = image.maxval
        when (name) {
            "OUTPUT" -> {
                emit("P2")
                emit(image.width.toString() + " " + image.height)
                emit(m.toString())
                for (y in 0 until image.height)
                    emit((0 until image.width).joinToString(" ") { x -> image.get(x, y).toString() })
            }
            "INVERT" -> commit(image.map { m - it })
            "BRIGHTNESS" -> {
                check(a[0] in -255..255)
                commit(image.map { image.clamp(it + a[0]) })
            }
            "CONTRAST" -> {
                val (num, den) = a
                check(num in 0..100 && den in 1..100)
                val center = (m + 1) / 2
                commit(image.map { image.clamp(center + Math.floorDiv((it - center) * num, den)) })
            }
            "THRESHOLD" -> {
                check(a[0] in 0..m)
                commit(image.map { if (it >= a[0]) m else 0 })
            }
            "LEVELS" -> {
                val (low, high) = a
                check(low >= 0 && low < high && high <= m)
                commit(image.map { image.clamp(Math.floorDiv((it - low) * m, high - low)) })
            }
            "POSTERIZE" -> {
                val levels = a[0]
                check(levels in 2..(m + 1))
                commit(image.map { ((it * levels) / (m + 1)) * m / (levels - 1) })
            }
            "MAXVAL" -> {
                val maximum = a[0]
                check(maximum in 1..255)
                commit(Image(image.width, image.height, maximum,
                    image.pixels.map { (2 * it * maximum + m) / (2 * m) }.toIntArray()))
            }
            "FLIPH" -> commit(transformed(image) { x, y -> image.get(image.width - 1 - x, y) })
            "FLIPV" -> commit(transformed(image) { x, y -> image.get(x, image.height - 1 - y) })
            "ROTATE" -> {
                val angle = a[0]
                check(angle in listOf(90, 180, 270))
                val w = image.width
                val h = image.height
                commit(when (angle) {
                    90 -> transformed(image, h, w) { x, y -> image.get(y, h - 1 - x) }
                    180 -> transformed(image, w, h) { x, y -> image.get(w - 1 - x, h - 1 - y) }
                    else -> transformed(image, h, w) { x, y -> image.get(w - 1 - y, x) }
                })
            }
            "CROP" -> {
                checkedCrop(image, a)
                commit(cropped(image, a[0], a[1], a[2], a[3]))
            }
            "PAD" -> {
                val (n, fillValue) = a
                check(n >= 1 && fillValue in 0..m)
                val w = image.width + 2 * n
                val h = image.height + 2 * n
                check(w <= 64 && h <= 64, "too large")
                commit(translated(image, w, h, n, n, fillValue))
            }
            "SCALE" -> {
                val (num, den) = a
                check(num in 1..16 && den in 1..16)
                val w = image.width * num / den
                val h = image.height * num / den
                check(w >= 1 && h >= 1, "too small")
                check(w <= 64 && h <= 64, "too large")
                commit(transformed(image, w, h) { x, y ->
                    image.get((2 * x + 1) * den / (2 * num),
                        (2 * y + 1) * den / (2 * num))
                })
            }
            "SHIFT" -> {
                val (dx, dy, fillValue) = a
                check(withinLimit(dx, dy) && fillValue in 0..m)
                commit(translated(image, image.width, image.height, dx, dy, fillValue))
            }
            "TILE" -> {
                val (nx, ny) = a
                check(nx >= 1 && ny >= 1)
                val w = image.width * nx
                val h = image.height * ny
                check(w <= 64 && h <= 64, "too large")
                commit(transformed(image, w, h) { x, y ->
                    image.get(x % image.width, y % image.height)
                })
            }
            "BLUR", "GAUSS", "SHARPEN" -> {
                val (weights, den) = kernels.getValue(name)
                commit(convolution(image, weights, den))
            }
            "CONVOLVE" -> {
                check(a.take(9).all { it in -16..16 } && a[9] in 1..256)
                commit(convolution(image, a.take(9).toIntArray(), a[9]))
            }
            "SOBEL" -> commit(sobel(image))
            "MEDIAN" -> commit(rankFiltered(image, 4))
            "ERODE" -> commit(rankFiltered(image, 0))
            "DILATE" -> commit(rankFiltered(image, 8))
            "OPEN" -> commit(rankFiltered(rankFiltered(image, 0), 8))
            "CLOSE" -> commit(rankFiltered(rankFiltered(image, 8), 0))
            "GRADIENT" -> {
                val high = rankFiltered(image, 8).pixels
                val low = rankFiltered(image, 0).pixels
                commit(image.withPixels(IntArray(high.size) { high[it] - low[it] }))
            }
            "LINE" -> {
                check(withinLimit(*a.take(4).toIntArray()) && a[4] in 0..m)
                paint(image, linePoints(a[0], a[1], a[2], a[3]), a[4])
            }
            "RECT" -> {
                val (x, y, w, h, value) = a
                check(withinLimit(x, y) && w in 1..1000 && h in 1..1000 && value in 0..m)
                paint(image, rectanglePoints(image, x, y, w, h, fill), value)
            }
            "CIRCLE" -> {
                val (x, y, radius, value) = a
                check(withinLimit(x, y) && radius in 0..1000 && value in 0..m)
                val outline = circlePoints(x, y, radius)
                paint(image, if (fill) discPoints(image, outline) else outline, value)
            }
            "FLOOD" -> {
                val (x, y, value) = a
                check(image.contains(x, y) && value in 0..m)
                paint(image, floodPoints(image, x, y), value)
            }
            "HISTOGRAM" -> {
                val low = IntArray(16) { -1 }
                val high = IntArray(16)
                val counts = IntArray(16)
                for (value in 0..m) {
                    val index = value * 16 / (m + 1)
                    if (low[index] < 0) low[index] = value
                    high[index] = value
                }
                for (value in image.pixels) counts[value * 16 / (m + 1)]++
                val top = counts.max()
                for (index in low.indices) {
                    if (low[index] < 0) continue
                    emit(low[index].toString().padStart(3) + "-" +
                        high[index].toString().padStart(3) + " " +
                        counts[index].toString().padStart(4) + " |" +
                        "#".repeat(counts[index] * 32 / top))
                }
            }
            "EQUALIZE" -> commit(equalized(image))
            "LABEL" -> {
                check(a[0] in 0..m)
                val groups = components(image, a[0])
                emit("labels " + groups.size)
                for ((index, group) in groups.withIndex())
                    emit("label " + (index + 1) + " " + componentText(image, a[0], group))
            }
            "DISTANCE" -> {
                check(a[0] in 0..m)
                commit(distanceMap(image, a[0]))
            }
            "STATS" -> emit(statistics(image.pixels, m))
            "REGION" -> {
                checkedCrop(image, a)
                emit(statistics(cropped(image, a[0], a[1], a[2], a[3]).pixels, m))
            }
            "DITHER" -> commit(dithered(image))
            "ASCIIART" -> {
                for (y in 0 until image.height)
                    emit((0 until image.width).map { x ->
                        shades[image.get(x, y) * 10 / (m + 1)]
                    }.joinToString(""))
            }
            "STORE" -> {
                slots[slot] = image
                emit("stored " + slot + " " + image.summary())
            }
            "BLEND" -> {
                val (num, den) = a
                check(num >= 0 && num <= den && den in 1..100)
                val other = matchingSlot(image, slot)
                commit(image.withPixels(IntArray(image.pixels.size) { i ->
                    (image.pixels[i] * (den - num) + other.pixels[i] * num) / den
                }))
            }
            "DIFF" -> {
                val other = matchingSlot(image, slot)
                commit(image.withPixels(IntArray(image.pixels.size) { i ->
                    kotlin.math.abs(image.pixels[i] - other.pixels[i])
                }))
            }
            "PASTE" -> {
                val (x, y) = a
                check(withinLimit(x, y))
                val other = slots.getValue(slot)
                check(other.maxval == m, "maxval mismatch")
                val pixels = image.pixels.copyOf()
                var painted = 0
                for (j in 0 until other.height) for (i in 0 until other.width) {
                    if (image.contains(x + i, y + j)) {
                        pixels[(y + j) * image.width + x + i] = other.get(i, j)
                        painted++
                    }
                }
                commit(image.withPixels(pixels), painted)
            }
        }
    }

    private fun withinLimit(vararg values: Int): Boolean = values.all { it in -1000..1000 }
}

fun main() {
    val count = readLine()!!.toInt()
    val editor = Editor()
    repeat(count) {
        val words = readLine()!!.split(' ')
        if (words[0] == "LOAD") {
            editor.load(List(words[1].toInt()) { readLine()!! })
        } else {
            editor.execute(words)
        }
    }
    if (editor.output.isNotEmpty()) print(editor.output.joinToString("\n", postfix = "\n"))
}
