fun main() {
    val paragraph = "Good software is written for people first and for machines second. A clear program explains its purpose " +
        "through careful names, small functions and honest tests. When a team agrees on shared rules for " +
        "internationalization, documentation and code review, every newcomer can read the code quickly, change it " +
        "safely and ship new improvements with confidence instead of fear, week after week."
    val lines = mutableListOf<List<String>>()
    var current = mutableListOf<String>()
    var letters = 0
    for (word in paragraph.split(' ')) {
        if (current.isNotEmpty() && letters + current.size + word.length > 30) {
            lines.add(current)
            current = mutableListOf()
            letters = 0
        }
        current.add(word)
        letters += word.length
    }
    if (current.isNotEmpty()) lines.add(current)
    for ((i,words) in lines.withIndex()) {
        val text = if (i == lines.lastIndex || words.size == 1) words.joinToString(" ").padEnd(30)
        else buildString {
            val spaces = 30 - words.sumOf { it.length }
            val gaps = words.size - 1
            append(words[0])
            for (j in 1 until words.size) {
                append(" ".repeat(spaces / gaps + if (j - 1 < spaces % gaps) 1 else 0))
                append(words[j])
            }
        }
        println("|$text|")
    }
}
