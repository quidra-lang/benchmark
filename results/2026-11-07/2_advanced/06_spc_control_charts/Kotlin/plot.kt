import kotlin.math.floor

fun put(band: CharArray, position: Double, symbol: Char) { band[minOf(60.0, maxOf(0.0, position)).toInt()] = symbol }
fun variableBand(limits: Limits, value: Double, signalled: Boolean): String {
    val band = CharArray(61) { '.' }
    fun position(v: Double) = floor(60.0 * ((v - limits.lcl) / (limits.ucl - limits.lcl)) + 0.5)
    put(band, 0.0, ':'); put(band, 60.0, ':'); put(band, position(limits.cl), '|'); put(band, position(value), if (signalled) '*' else 'o')
    return band.concatToString()
}
fun cusumBand(upper: Double, lower: Double, threshold: Double, highSignal: Boolean, lowSignal: Boolean): String {
    val band = CharArray(61) { '.' }
    put(band, 0.0, ':'); put(band, 60.0, ':'); put(band, 30.0, '|')
    if (lower > 0.0) put(band, 30.0 - minOf(30.0, floor(30.0 * (lower / threshold) + 0.5)), if (lowSignal) '*' else '-')
    if (upper > 0.0) put(band, 30.0 + minOf(30.0, floor(30.0 * (upper / threshold) + 0.5)), if (highSignal) '*' else '+')
    return band.concatToString()
}
fun smoothBand(width: Double, rowWidth: Double, value: Double, center: Double, signalled: Boolean): String {
    val band = CharArray(61) { '.' }
    val edge = minOf(30.0, floor(30.0 * (rowWidth / width) + 0.5))
    put(band, 30.0, '|'); put(band, 30.0 - edge, ':'); put(band, 30.0 + edge, ':')
    put(band, 30.0 + floor(30.0 * ((value - center) / width) + 0.5), if (signalled) '*' else 'o')
    return band.concatToString()
}
fun standardBand(z: Double, okay: Boolean): String {
    val band = CharArray(61) { '.' }
    put(band, 0.0, ':'); put(band, 60.0, ':'); put(band, 30.0, '|'); put(band, 30.0 + floor(10.0 * z + 0.5), if (okay) 'o' else '*')
    return band.concatToString()
}
