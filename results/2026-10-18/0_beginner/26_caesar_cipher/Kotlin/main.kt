import java.math.BigDecimal
import java.math.RoundingMode

fun cipher(text: String, shift: Int): String = text.map { ch ->
    val base = when (ch) { in 'A'..'Z' -> 'A'.code; in 'a'..'z' -> 'a'.code; else -> -1 }
    if (base < 0) ch else (base + (ch.code - base + shift + 26) % 26).toChar()
}.joinToString("")
fun main() {
    val encrypted = cipher("Zoe, meet Max by the Old Bridge at six!", 3)
    println(encrypted)
    println(cipher(encrypted, -3))
}
