fun reflect(words: List<String>, post: Map<String, List<String>>) = words.flatMap { post[it] ?: listOf(it) }
fun binding(bindings: List<List<String>>, number: Int): List<String> = bindings.getOrNull(number - 1).orEmpty()

fun buildReply(template: String, bindings: List<List<String>>, post: Map<String, List<String>>): String {
    val text = StringBuilder()
    var index = 0
    while (index < template.length) {
        if (index + 3 <= template.length && isReference(template.substring(index, index + 3))) {
            text.append(reflect(binding(bindings, template[index + 1] - '0'), post).joinToString(" "))
            index += 3
        } else text.append(template[index++])
    }
    val reply = text.toString().split(' ').filter { it.isNotEmpty() }.joinToString(" ")
    return if (reply.isNotEmpty() && reply[0] in 'a'..'z') reply[0].uppercaseChar() + reply.drop(1) else reply
}

fun restatedWords(arguments: List<String>, bindings: List<List<String>>) = arguments.flatMap { if (isReference(it)) binding(bindings, it[1] - '0') else listOf(it) }

fun elizaLines(text: String): List<String> {
    val words = text.split(' ').filter { it.isNotEmpty() }
    val lines = mutableListOf("ELIZA: ${words.first()}")
    for (word in words.drop(1)) {
        if (lines.last().length + 1 + word.length <= 72) lines[lines.lastIndex] += " $word"
        else lines += "       $word"
    }
    return lines
}
