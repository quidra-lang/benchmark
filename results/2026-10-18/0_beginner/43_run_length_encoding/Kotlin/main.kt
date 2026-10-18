import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    val values = listOf("AAABBBCCCD", "W".repeat(12) + "B" + "W".repeat(12) + "BBB", "ALGORITHM", "MISSISSIPPI", "X".repeat(10) + "Y".repeat(21) + "Z")
    for (text in values) {
        val encoded = StringBuilder(); var i = 0
        while (i < text.length) { var j = i + 1; while (j < text.length && text[j] == text[i]) j++; encoded.append(j - i).append(text[i]); i = j }
        val decoded = StringBuilder(); i = 0
        while (i < encoded.length) { var count = 0; while (encoded[i] in '0'..'9') { count = count * 10 + (encoded[i] - '0'); i++ }; decoded.append(encoded[i].toString().repeat(count)); i++ }
        println("$text -> $encoded -> $decoded")
    }
}
