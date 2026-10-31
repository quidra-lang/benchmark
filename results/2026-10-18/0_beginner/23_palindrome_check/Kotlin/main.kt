fun main() {
    val phrases = listOf(
        "Never odd or even", "Race a car", "Was it a car or a cat I saw?", "Hello, World!",
        "Step on no pets.", "No lemon, no melon",
    )
    for (phrase in phrases) {
        val normalized = phrase.filter { it in 'A'..'Z' || it in 'a'..'z' }.lowercase()
        println("$phrase -> ${if (normalized == normalized.reversed()) "yes" else "no"}")
    }
}
