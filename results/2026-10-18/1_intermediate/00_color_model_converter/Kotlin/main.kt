import java.util.Locale

class Invalid : RuntimeException()
data class Entry(val name: String, val color: IntArray)
data class Cluster(val color: IntArray, val count: Int)

class Converter {
    private val names = listOf(
        "black", "maroon", "green", "olive", "navy", "purple", "teal", "silver",
        "gray", "red", "lime", "yellow", "blue", "magenta", "cyan", "white",
        "orange", "pink", "brown", "gold", "coral", "salmon", "violet", "indigo"
    )
    private val rgb = intArrayOf(
        0x000000, 0x800000, 0x008000, 0x808000, 0x000080, 0x800080, 0x008080, 0xC0C0C0,
        0x808080, 0xFF0000, 0x00FF00, 0xFFFF00, 0x0000FF, 0xFF00FF, 0x00FFFF, 0xFFFFFF,
        0xFFA500, 0xFFC0CB, 0xA52A2A, 0xFFD700, 0xFF7F50, 0xFA8072, 0xEE82EE, 0x4B0082
    )
    private val integerPattern = Regex("-?[0-9]{1,9}")
    private val namePattern = Regex("[a-z]{1,12}")
    private val hexPattern = Regex("#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?")
    private val rgbPattern = Regex("rgb\\(([0-9]{1,3}),([0-9]{1,3}),([0-9]{1,3})\\)")
    private val registered = mutableListOf<Entry>()

    private fun check(condition: Boolean) {
        if (!condition) throw Invalid()
    }
    private fun arity(tokens: List<String>, count: Int) {
        check(tokens.size == count + 1)
    }
    private fun number(text: String, low: Int, high: Int): Int {
        check(integerPattern.matches(text))
        val value = text.toInt()
        check(value in low..high)
        return value
    }
    private fun round(n: Long, d: Long): Int = Math.floorDiv(2 * n + d, 2 * d).toInt()
    private fun round(n: Long, d: Int): Int = round(n, d.toLong())
    private fun round(n: Int, d: Int): Int = round(n.toLong(), d.toLong())
    private fun away(n: Long, d: Int): Int = if (n < 0) -round(-n,d) else round(n,d)
    private fun percent(a: Int, b: Int): Int = round(100L*a,b)
    private fun mod(value: Int, modulus: Int): Int = Math.floorMod(value,modulus)
    private fun clamp(value: Int): Int = value.coerceIn(0,255)
    private fun root(numerator: Long, scale: Long): Int {
        val value = numerator / scale
        var low = 0L
        var high = value + 1
        while (low + 1 < high) {
            val middle = (low + high) / 2
            if (middle * middle <= value) low = middle else high = middle
        }
        return low.toInt()
    }
    private fun unpack(value: Int): IntArray = intArrayOf(value shr 16, (value shr 8) and 255, value and 255)
    private fun hex(color: IntArray): String = String.format(Locale.ROOT,"#%02X%02X%02X",color[0],color[1],color[2])
    private fun table(): List<Entry> = names.indices.map { Entry(names[it],unpack(rgb[it])) } + registered
    private fun color(text: String): IntArray {
        if (hexPattern.matches(text)) {
            var digits = text.substring(1)
            if (digits.length == 3) digits = digits.map { "$it$it" }.joinToString("")
            return unpack(digits.toInt(16))
        }
        val match = rgbPattern.matchEntire(text)
        if (match != null) {
            val result = IntArray(3) { match.groupValues[it + 1].toInt() }
            check(result.all { it <= 255 })
            return result
        }
        return table().firstOrNull { it.name == text }?.color ?: throw Invalid()
    }
    private fun maximum(c: IntArray): Int = c.max()
    private fun minimum(c: IntArray): Int = c.min()
    private fun hue(c: IntArray): Int {
        val largest = maximum(c)
        val difference = largest - minimum(c)
        if (difference == 0) return 0
        var numerator = when (largest) {
            c[0] -> 60L * (c[1] - c[2])
            c[1] -> 60L * (c[2] - c[0]) + 120L * difference
            else -> 60L * (c[0] - c[1]) + 240L * difference
        }
        if (numerator < 0) numerator += 360L * difference
        return round(numerator,difference) % 360
    }
    private fun hsl(c: IntArray): IntArray {
        val largest = maximum(c)
        val smallest = minimum(c)
        val difference = largest - smallest
        val saturation = if (difference == 0) 0 else percent(difference,255 - kotlin.math.abs(largest + smallest - 255))
        return intArrayOf(hue(c),saturation,percent(largest + smallest,510))
    }
    private fun fromHue(h: Int, chroma: Long, offset: Long, denominator: Long): IntArray {
        val sector = h / 60
        val f = h % 60
        val x = if (sector % 2 == 0) f else 60 - f
        val factors = arrayOf(intArrayOf(60,x,0),intArrayOf(x,60,0),intArrayOf(0,60,x),
            intArrayOf(0,x,60),intArrayOf(x,0,60),intArrayOf(60,0,x))
        return IntArray(3) { round(255 * (chroma * factors[sector][it] + 60 * offset),60 * denominator) }
    }
    private fun fromHsl(h: Int, s: Int, l: Int): IntArray {
        val c = (100 - kotlin.math.abs(2 * l - 100)).toLong() * s
        return fromHue(h,2*c,200L*l-c,20000)
    }
    private fun distance(a: IntArray, b: IntArray): Long = (0..2).sumOf {
        (a[it] - b[it]).toLong() * (a[it] - b[it])
    }
    private fun model(command: String, c: IntArray): String {
        val r = c[0]
        val g = c[1]
        val b = c[2]
        val m = maximum(c)
        val n = minimum(c)
        val d = m - n
        return when (command) {
            "HSL" -> {
                val v = hsl(c)
                "hsl(${v[0]},${v[1]}%,${v[2]}%)"
            }
            "HSV" -> "hsv(${hue(c)},${if (m == 0) 0 else percent(d,m)}%,${percent(m,255)}%)"
            "HWB" -> "hwb(${hue(c)},${percent(n,255)}%,${percent(255-m,255)}%)"
            "CMYK" -> if (m == 0) "cmyk(0%,0%,0%,100%)" else
                "cmyk(${percent(m-r,m)}%,${percent(m-g,m)}%,${percent(m-b,m)}%,${percent(255-m,255)}%)"
            "YCBCR" -> "ycbcr(${clamp(round(299L*r+587L*g+114L*b,1000))}," +
                "${clamp(round(128000L-169L*r-331L*g+500L*b,1000))},${clamp(round(128000L+500L*r-419L*g-81L*b,1000))})"
            "YIQ" -> "yiq(${round(299L*r+587L*g+114L*b,1000)}," +
                "${round(596L*r-274L*g-322L*b,1000)},${round(211L*r-523L*g+312L*b,1000)})"
            else -> throw Invalid()
        }
    }
    private fun ansi(number: Int): IntArray {
        if (number < 16) return unpack(rgb[number])
        if (number >= 232) return IntArray(3) { 8 + 10 * (number - 232) }
        val values = intArrayOf(0,95,135,175,215,255)
        val v = number - 16
        return intArrayOf(values[v / 36],values[v / 6 % 6],values[v % 6])
    }
    private fun gradient(a: IntArray, b: IntArray, index: Int, denominator: Int): IntArray =
        IntArray(3) { a[it] + away((b[it]-a[it]).toLong()*index,denominator) }
    private fun luminance(c: IntArray): Long = 2126L*c[0]*c[0] + 7152L*c[1]*c[1] + 722L*c[2]*c[2]
    private fun contrast(a: IntArray, b: IntArray): LongArray {
        val first = luminance(a)
        val second = luminance(b)
        return longArrayOf(maxOf(first,second)+32512500,minOf(first,second)+32512500)
    }
    private fun ratio(a: IntArray, b: IntArray): Int {
        val values = contrast(a,b)
        return round(100*values[0],values[1])
    }
    private fun readable(a: IntArray, b: IntArray): Boolean {
        val values = contrast(a,b)
        return 2*values[0] >= 9*values[1]
    }
    private fun contrastText(a: IntArray, b: IntArray): String {
        val values = contrast(a,b)
        val ratio = round(100*values[0],values[1])
        val verdict = if (values[0] >= 7*values[1]) "AAA" else if (2*values[0] >= 9*values[1]) "AA" else "FAIL"
        return "${ratio / 100}.${(ratio % 100).toString().padStart(2,'0')} $verdict"
    }
    private fun blendComponent(mode: String, x: Int, y: Int): Int {
        val multiply = x*y/255
        val screen = 255-(255-x)*(255-y)/255
        return when (mode) {
            "MULTIPLY" -> multiply
            "SCREEN" -> screen
            "OVERLAY" -> if (x < 128) 2*x*y/255 else 255-2*(255-x)*(255-y)/255
            "HARDLIGHT" -> if (y < 128) 2*x*y/255 else 255-2*(255-x)*(255-y)/255
            "SOFTLIGHT" -> ((255-x)*multiply+x*screen)/255
            "DARKEN" -> minOf(x,y)
            "LIGHTEN" -> maxOf(x,y)
            "DIFFERENCE" -> kotlin.math.abs(x-y)
            "EXCLUSION" -> x+y-2*x*y/255
            "ADD" -> minOf(255,x+y)
            "SUBTRACT" -> maxOf(0,x-y)
            "COLORDODGE" -> if (y == 255) 255 else minOf(255,255*x/(255-y))
            "COLORBURN" -> if (y == 0) 0 else maxOf(0,255-255*(255-x)/y)
            else -> throw Invalid()
        }
    }
    private fun blend(mode: String, base: IntArray, top: IntArray): IntArray {
        if (mode in setOf("HUE","SATURATION","COLOR","LUMINOSITY")) {
            val a = hsl(base)
            val b = hsl(top)
            return fromHsl(if (mode == "HUE" || mode == "COLOR") b[0] else a[0],
                if (mode == "SATURATION" || mode == "COLOR") b[1] else a[1],if (mode == "LUMINOSITY") b[2] else a[2])
        }
        return IntArray(3) { blendComponent(mode,base[it],top[it]) }
    }
    private fun mean(colors: List<IntArray>): IntArray = IntArray(3) { component ->
        round(colors.sumOf { it[component] },colors.size)
    }
    private fun ranges(colors: List<IntArray>): IntArray = IntArray(3) { component ->
        colors.maxOf { it[component] } - colors.minOf { it[component] }
    }
    private fun palette(k: Int, colors: List<IntArray>): List<Cluster> {
        val boxes = mutableListOf(colors.toMutableList())
        while (boxes.size < k) {
            var selected = -1
            var width = -1
            for (i in boxes.indices) {
                if (boxes[i].size < 2) continue
                val candidate = ranges(boxes[i]).max()
                if (candidate > width) {
                    width = candidate
                    selected = i
                }
            }
            val range = ranges(boxes[selected])
            var component = 0
            for (i in 1..2) {
                if (range[i] > range[component]) component = i
            }
            val axis = component
            val sorted = boxes[selected].sortedBy { it[axis] }
            val middle = sorted.size / 2
            boxes[selected] = sorted.take(middle).toMutableList()
            boxes.add(selected + 1,sorted.drop(middle).toMutableList())
        }
        return boxes.map { Cluster(mean(it),it.size) }
    }
    private fun clusterText(clusters: List<Cluster>): String =
        clusters.joinToString(" ") { "${hex(it.color)}:${it.count}" }
    private fun kmeans(k: Int, colors: List<IntArray>): String {
        var representatives = palette(k,colors).map { it.color }
        var result = emptyList<Cluster>()
        var iteration = 0
        while (iteration < 20) {
            iteration++
            val groups = List(k) { mutableListOf<IntArray>() }
            for (color in colors) {
                var best = 0
                for (j in 1 until k) {
                    if (distance(color,representatives[j]) < distance(color,representatives[best])) best = j
                }
                groups[best].add(color)
            }
            result = groups.indices.map { j ->
                Cluster(if (groups[j].isEmpty()) representatives[j] else mean(groups[j]),groups[j].size)
            }
            val unchanged = result.indices.all { result[it].color.contentEquals(representatives[it]) }
            representatives = result.map { it.color }
            if (unchanged) break
        }
        return "$iteration ${clusterText(result)}"
    }
    private fun colors(tokens: List<String>, start: Int): List<IntArray> = tokens.drop(start).map { color(it) }
    private fun colorsText(colors: List<IntArray>): String = colors.joinToString(" ") { hex(it) }
    fun execute(line: String): String {
        val t = line.split(' ')
        val command = t[0]
        when (command) {
            "DEFINE" -> {
                arity(t,2)
                check(namePattern.matches(t[1]) && t[1] !in names)
                val c = color(t[2])
                val entry = Entry(t[1],c)
                val index = registered.indexOfFirst { it.name == t[1] }
                if (index < 0) registered.add(entry) else registered[index] = entry
                return "${t[1]} ${hex(c)}"
            }
            "UNDEFINE" -> {
                arity(t,1)
                check(namePattern.matches(t[1]))
                val index = registered.indexOfFirst { it.name == t[1] }
                check(index >= 0)
                registered.removeAt(index)
                return "${t[1]} removed"
            }
            "LIST" -> {
                arity(t,0)
                return if (registered.isEmpty()) "NONE" else
                    registered.sortedBy { it.name }.joinToString(" ") { "${it.name}=${hex(it.color)}" }
            }
            "PARSE" -> {
                arity(t,1)
                val c = color(t[1])
                val name = table().firstOrNull { it.color.contentEquals(c) }?.name ?: "-"
                return "${hex(c)} rgb(${c[0]},${c[1]},${c[2]}) " +
                    "${model("HSL",c)} ${model("HSV",c)} ${model("HWB",c)} ${model("CMYK",c)} " +
                    "${model("YCBCR",c)} ${model("YIQ",c)} $name"
            }
            "HSL", "HSV", "HWB", "CMYK", "YCBCR", "YIQ" -> {
                arity(t,1)
                return model(command,color(t[1]))
            }
            "FROMHSL", "FROMHSV", "FROMHWB" -> {
                arity(t,3)
                val h = number(t[1],0,359)
                val s = number(t[2],0,100)
                val third = number(t[3],0,100)
                val c = when {
                    command == "FROMHSL" -> fromHsl(h,s,third)
                    command == "FROMHSV" -> fromHue(h,third.toLong()*s,100L*third-third*s,10000)
                    s + third >= 100 -> IntArray(3) { round(255L*s,s+third) }
                    else -> fromHue(h,(100-s-third).toLong(),s.toLong(),100)
                }
                return hex(c)
            }
            "FROMCMYK" -> {
                arity(t,4)
                val k = number(t[4],0,100)
                return hex(IntArray(3) { round(255L*(100-number(t[it+1],0,100))*(100-k),10000) })
            }
            "FROMYCBCR", "FROMYIQ" -> {
                arity(t,3)
                val y = number(t[1],0,255)
                val iq = command == "FROMYIQ"
                val a = number(t[2],if (iq) -255 else 0,255)
                val b = number(t[3],if (iq) -255 else 0,255)
                val numerators = if (iq) longArrayOf(1000L*y+956L*a+619L*b,
                    1000L*y-272L*a-647L*b,1000L*y-1106L*a+1703L*b)
                else longArrayOf(1000L*y+1402L*(b-128),1000L*y-344L*(a-128)-714L*(b-128),1000L*y+1772L*(a-128))
                return hex(IntArray(3) { clamp(round(numerators[it],1000)) })
            }
            "RGB565" -> {
                arity(t,1)
                val c = color(t[1])
                val value = 2048*round(31L*c[0],255)+32*round(63L*c[1],255)+round(31L*c[2],255)
                return "0x" + value.toString(16).uppercase().padStart(4,'0')
            }
            "FROM565" -> {
                arity(t,1)
                check(Regex("0x[0-9a-fA-F]{4}").matches(t[1]))
                val v = t[1].substring(2).toInt(16)
                return hex(intArrayOf(round(255L*(v/2048),31),round(255L*(v/32%64),63),round(255L*(v%32),31)))
            }
            "FROMANSI" -> {
                arity(t,1)
                return hex(ansi(number(t[1],0,255)))
            }
            "ANSI" -> {
                arity(t,1)
                val c = color(t[1])
                var best = 16
                for (i in 17..255) {
                    if (distance(c,ansi(i)) < distance(c,ansi(best))) best = i
                }
                return "$best ${hex(ansi(best))} ${distance(c,ansi(best))}"
            }
            "WEBSAFE", "INVERT" -> {
                arity(t,1)
                val c = color(t[1])
                return hex(IntArray(3) { if (command == "INVERT") 255-c[it] else 51*round(c[it],51) })
            }
            "GRAY" -> {
                arity(t,2)
                val c = color(t[1])
                val value = when (t[2]) {
                    "LUMA" -> round(299L*c[0]+587L*c[1]+114L*c[2],1000)
                    "AVERAGE" -> round(c.sum(),3)
                    "LIGHTNESS" -> round(maximum(c)+minimum(c),2)
                    "HSP" -> root(299L*c[0]*c[0]+587L*c[1]*c[1]+114L*c[2]*c[2],1000)
                    else -> throw Invalid()
                }
                return hex(IntArray(3) { value })
            }
            "MIX", "MIXHSL" -> {
                arity(t,3)
                val a = color(t[1])
                val b = color(t[2])
                val p = number(t[3],0,100)
                if (command == "MIX") return hex(IntArray(3) { round(a[it].toLong()*(100-p)+b[it].toLong()*p,100) })
                val first = hsl(a)
                val second = hsl(b)
                var e = mod(second[0]-first[0],360)
                if (e > 180) e -= 360
                return hex(fromHsl(mod(first[0]+away(e.toLong()*p,100),360),
                    first[1]+away((second[1]-first[1]).toLong()*p,100),first[2]+away((second[2]-first[2]).toLong()*p,100)))
            }
            "GRADIENT", "TINTS", "SHADES", "TONES" -> {
                arity(t,if (command == "GRADIENT") 3 else 2)
                val a = color(t[1])
                val result: List<IntArray>
                if (command == "GRADIENT") {
                    val b = color(t[2])
                    val n = number(t[3],2,16)
                    result = (0 until n).map { gradient(a,b,it,n-1) }
                } else {
                    val n = number(t[2],1,10)
                    val target = if (command == "TINTS") 255 else if (command == "SHADES") 0 else 128
                    val b = IntArray(3) { target }
                    result = (1..n).map { gradient(a,b,it,n+1) }
                }
                return colorsText(result)
            }
            "BLEND" -> {
                arity(t,3)
                return hex(blend(t[1],color(t[2]),color(t[3])))
            }
            "ALPHA" -> {
                arity(t,4)
                val fg = color(t[1])
                val p = number(t[2],0,100)
                val bg = color(t[3])
                val q = number(t[4],0,100)
                val a = 100*p+q*(100-p)
                val result = IntArray(3) { if (a == 0) 0 else round(100L*p*fg[it]+q.toLong()*(100-p)*bg[it],a) }
                return "${hex(result)} ${round(a,100)}%"
            }
            "SIMULATE" -> {
                arity(t,2)
                val c = color(t[1])
                val coefficients = when (t[2]) {
                    "PROTANOPIA" -> listOf(listOf(567,433,0),listOf(558,442,0),listOf(0,242,758))
                    "DEUTERANOPIA" -> listOf(listOf(625,375,0),listOf(700,300,0),listOf(0,300,700))
                    "TRITANOPIA" -> listOf(listOf(950,50,0),listOf(0,433,567),listOf(0,475,525))
                    "ACHROMATOPSIA" -> List(3) { listOf(299,587,114) }
                    else -> throw Invalid()
                }
                return hex(IntArray(3) { i -> round((0..2).sumOf { coefficients[i][it].toLong()*c[it] },1000) })
            }
            "ROTATE", "COMPLEMENT", "TRIADIC", "TETRADIC", "SPLITCOMP", "ANALOGOUS" -> {
                arity(t,if (command == "ROTATE") 2 else if (command == "ANALOGOUS") 3 else 1)
                val values = hsl(color(t[1]))
                val rotations = when (command) {
                    "ROTATE" -> listOf(number(t[2],-720,720))
                    "COMPLEMENT" -> listOf(180)
                    "TRIADIC" -> listOf(120,240)
                    "TETRADIC" -> listOf(90,180,270)
                    "SPLITCOMP" -> listOf(150,210)
                    else -> {
                        val k = number(t[2],1,6)
                        val step = number(t[3],1,60)
                        (-k..k).filter { it != 0 }.map { it*step }
                    }
                }
                return colorsText(rotations.map { fromHsl(mod(values[0]+it,360),values[1],values[2]) })
            }
            "LIGHTEN", "DARKEN", "SATURATE", "DESATURATE" -> {
                arity(t,2)
                val values = hsl(color(t[1]))
                val p = number(t[2],0,100)
                when (command) {
                    "LIGHTEN" -> values[2] = minOf(100,values[2]+p)
                    "DARKEN" -> values[2] = maxOf(0,values[2]-p)
                    "SATURATE" -> values[1] = minOf(100,values[1]+p)
                    "DESATURATE" -> values[1] = maxOf(0,values[1]-p)
                }
                return hex(fromHsl(values[0],values[1],values[2]))
            }
            "NEAREST" -> {
                arity(t,1)
                val c = color(t[1])
                val entries = table()
                var best = entries.first()
                for (entry in entries) {
                    if (distance(c,entry.color) < distance(c,best.color)) best = entry
                }
                return "${best.name} ${hex(best.color)} ${distance(c,best.color)}"
            }
            "DISTANCE" -> {
                arity(t,2)
                val a = color(t[1])
                val b = color(t[2])
                val dr = (a[0]-b[0]).toLong()
                val dg = (a[1]-b[1]).toLong()
                val db = (a[2]-b[2]).toLong()
                val w = (1024L+a[0]+b[0])*dr*dr+2048*dg*dg+(1534L-a[0]-b[0])*db*db
                return "${distance(a,b)} ${root(w,512)}"
            }
            "CONTRAST" -> {
                arity(t,2)
                return contrastText(color(t[1]),color(t[2]))
            }
            "ACCESSIBLE" -> {
                arity(t,2)
                val fg = color(t[1])
                val bg = color(t[2])
                if (readable(fg,bg)) return "${hex(fg)} ${contrastText(fg,bg)}"
                val values = hsl(fg)
                for (d in 1..100) {
                    for (l in listOf(values[2]-d,values[2]+d)) {
                        if (l !in 0..100) continue
                        val candidate = fromHsl(values[0],values[1],l)
                        if (readable(candidate,bg)) return "${hex(candidate)} ${contrastText(candidate,bg)}"
                    }
                }
                throw Invalid()
            }
            "BEST" -> {
                check(t.size in 3..34)
                val bg = color(t[1])
                val options = colors(t,2)
                var best = options.first()
                for (c in options) {
                    if (ratio(c,bg) > ratio(best,bg)) best = c
                }
                return "${hex(best)} ${contrastText(best,bg)}"
            }
            "DESCRIBE" -> {
                arity(t,1)
                val (h,s,l) = hsl(color(t[1])).toList()
                if (l <= 5) return "black"
                if (l >= 95) return "white"
                val lightness = when {
                    l <= 20 -> "very dark"
                    l <= 40 -> "dark"
                    l <= 60 -> "medium"
                    l <= 80 -> "light"
                    else -> "very light"
                }
                if (s < 10) return "$lightness gray"
                val saturation = if (s < 40) "muted" else if (s < 80) "moderate" else "vivid"
                val hues = listOf("red","orange","yellow","chartreuse","green","spring-green",
                    "cyan","azure","blue","violet","magenta","rose")
                return "$lightness $saturation ${hues[(h+15)%360/30]}"
            }
            "PALETTE", "KMEANS" -> {
                check(t.size in 3..34)
                val k = number(t[1],1,t.size-2)
                val options = colors(t,2)
                return if (command == "PALETTE") clusterText(palette(k,options)) else kmeans(k,options)
            }
            "SORT" -> {
                check(t.size in 2..33)
                val options = colors(t,1).sortedWith(compareBy<IntArray> { hsl(it)[0] }
                    .thenBy { hsl(it)[1] }.thenBy { hsl(it)[2] })
                return colorsText(options)
            }
            "DITHER" -> {
                check(t.size in 2..33)
                val options = colors(t,1)
                val error = IntArray(3)
                val result = mutableListOf<String>()
                for (c in options) {
                    val adjusted = IntArray(3) { clamp(c[it]+error[it]) }
                    var best = 0
                    for (i in 1 until 16) {
                        if (distance(adjusted,unpack(rgb[i])) < distance(adjusted,unpack(rgb[best]))) best = i
                    }
                    result.add(names[best])
                    val chosen = unpack(rgb[best])
                    for (i in 0..2) error[i] = adjusted[i]-chosen[i]
                }
                return result.joinToString(" ")
            }
            "RANDOM" -> {
                arity(t,2)
                var state = number(t[1],1,999999999).toLong()
                val n = number(t[2],1,16)
                val result = mutableListOf<IntArray>()
                repeat(n) {
                    state = state*48271%2147483647
                    val h = (state%360).toInt()
                    state = state*48271%2147483647
                    val s = 40+(state%61).toInt()
                    state = state*48271%2147483647
                    val l = 25+(state%51).toInt()
                    result.add(fromHsl(h,s,l))
                }
                return colorsText(result)
            }
            else -> throw Invalid()
        }
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val count = input.readLine().toInt()
    val converter = Converter()
    val output = System.out.bufferedWriter()
    repeat(count) {
        val line = input.readLine()
        val result = try {
            converter.execute(line)
        } catch (invalid: Invalid) {
            "INVALID"
        }
        output.write(result)
        output.newLine()
    }
    output.flush()
}
