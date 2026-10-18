import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    for (phrase in listOf("Never odd or even", "Race a car", "Was it a car or a cat I saw?", "Hello, World!", "Step on no pets.", "No lemon, no melon")) {
        val normalized = phrase.filter { it in 'A'..'Z' || it in 'a'..'z' }.lowercase()
        println("$phrase -> ${if (normalized == normalized.reversed()) "yes" else "no"}")
    }
}
