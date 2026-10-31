fun main() {
    val texts = listOf(
        "(a + b) * [c - d]", "{x = [1, 2, (3 + 4)]}", "f(a[i] + g(b)}", "(1 + 2)) * 3",
        "if (a < b) { c = d[0]; }", "((a + b] * c", "[{(x * y) - z}",
    )
    for (text in texts) {
        val stack = ArrayDeque<Char>()
        var error = -1
        for ((i, ch) in text.withIndex()) {
            val close = ")]}".indexOf(ch)
            if (ch in "([{") {
                stack.add(ch)
            } else if (close >= 0) {
                if (stack.isEmpty() || stack.last() != "([{"[close]) {
                    error = i
                    break
                }
                stack.removeLast()
            }
        }
        if (error < 0 && stack.isNotEmpty()) error = text.length
        println(text + " -> " + if (error < 0) "balanced" else "error at index $error")
    }
}
