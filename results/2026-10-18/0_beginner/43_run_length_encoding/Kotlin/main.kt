fun main() {
    val values = listOf("AAABBBCCCD", "W".repeat(12) + "B" + "W".repeat(12) + "BBB", "ALGORITHM", "MISSISSIPPI", "X".repeat(10) + "Y".repeat(21) + "Z")
    val runs = Regex("(.)\\1*")
    val counts = Regex("(\\d+)([A-Z])")
    for (text in values) {
        val encoded = runs.replace(text) { "${it.value.length}${it.value[0]}" }
        val decoded = counts.replace(encoded) { it.groupValues[2].repeat(it.groupValues[1].toInt()) }
        println("$text -> $encoded -> $decoded")
    }
}
