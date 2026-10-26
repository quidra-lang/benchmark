fun main() {
    val numbers = listOf(
        "688126340316", "0128469655154", "92181914514156", "177332430060552", "7982377590420309",
        "9884593615513906",
    )
    for (number in numbers) {
        var sum = 0
        for ((index, ch) in number.reversed().withIndex()) {
            var digit = ch - '0'
            if (index % 2 == 1) {
                digit *= 2
                if (digit > 9) digit -= 9
            }
            sum += digit
        }
        val expected = (10 - (sum - (number.last() - '0')) % 10) % 10
        println(number + ": " + if (sum % 10 == 0) "valid" else "invalid (expected check digit $expected)")
    }
}
