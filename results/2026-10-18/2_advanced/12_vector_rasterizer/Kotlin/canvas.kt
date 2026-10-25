data class Point(val x: Int, val y: Int)
data class Rectangle(val x0: Int, val y0: Int, val x1: Int, val y1: Int) {
    val isEmpty: Boolean get() = x0 > x1 || y0 > y1
    fun contains(point: Point): Boolean = point.x in x0..x1 && point.y in y0..y1
    fun intersection(other: Rectangle): Rectangle = Rectangle(maxOf(x0, other.x0), maxOf(y0, other.y0), minOf(x1, other.x1), minOf(y1, other.y1))
    val pixels: Set<Point> get() = (y0..y1).flatMap { y -> (x0..x1).map { Point(it, y) } }.toSet()
}
data class Color(val red: Int, val green: Int, val blue: Int, val alpha: Int = 255) {
    constructor(values: List<Int>) : this(values[0], values[1], values[2], if (values.size == 4) values[3] else 255)
    val channels: List<Int> get() = listOf(red, green, blue, alpha)
    val rgbText: String get() = "$red $green $blue"
    val text: String get() = "$rgbText $alpha"
}
fun floorDivide(numerator: Int, denominator: Int): Int = Math.floorDiv(numerator, denominator)
fun roundRatio(numerator: Int, denominator: Int): Int { val n = if (denominator < 0) -numerator else numerator; val d = kotlin.math.abs(denominator); return floorDivide(2 * n + d, 2 * d) }
fun effectiveAlpha(alpha: Int, opacity: Int): Int = roundRatio(alpha * opacity, 255)
class Layer(val width: Int, val height: Int, val opacity: Int, val mode: String) {
    val colors = arrayOfNulls<Color>(width * height)
    val lines = IntArray(width * height)
    fun index(point: Point): Int = point.y * width + point.x
    fun paint(point: Point, color: Color, line: Int) { val index = index(point); colors[index] = color; lines[index] = line }
    fun erase(point: Point): Boolean { val index = index(point); val painted = colors[index] != null; colors[index] = null; return painted }
    fun colorAt(point: Point): Color? = colors[index(point)]
    fun alphaAt(point: Point): Int = colorAt(point)?.let { effectiveAlpha(it.alpha, opacity) } ?: 0
    fun blend(point: Point, current: Color): Color {
        val color = colorAt(point) ?: return current
        val alpha = effectiveAlpha(color.alpha, opacity)
        return Color(color.channels.take(3).zip(current.channels.take(3)).map { (source, value) -> val blended = if (mode == "multiply") roundRatio(source * value, 255) else if (mode == "screen") 255 - roundRatio((255 - source) * (255 - value), 255) else source; roundRatio(alpha * blended + (255 - alpha) * value, 255) })
    }
}
fun composite(layers: List<Layer>, background: Color, width: Int, height: Int): List<Color> = List(width * height) { index -> layers.fold(background) { value, layer -> layer.blend(Point(index % width, index / width), value) } }
