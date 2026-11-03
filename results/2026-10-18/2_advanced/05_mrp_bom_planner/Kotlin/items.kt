data class Item(val id: String, val leadTime: Int, val rule: String, val parameters: List<Long>, val safety: Long, val onHand: Long, val material: Long, val labor: Long, val description: String) {
    fun lotLabel() = when (rule) { "LFL" -> rule; "MIN" -> "MIN ${parameters[0]}/${parameters[1]}"; else -> "$rule ${parameters[0]}" }
}

fun lotParameters(rule: String, text: String): List<Long>? {
    val values = text.split('/').map(String::toLong)
    val valid = when (rule) { "LFL" -> values.size == 1 && values[0] == 0L; "MIN" -> values.size == 2 && values.all { it >= 1L }; else -> values.size == 1 && values[0] >= 1L }
    return if (valid) values else null
}

fun readItems(errors: MutableList<String>): Map<String, Item> {
    val items = sortedMapOf<String, Item>()
    for ((line, fields) in csvRows("items.csv")) {
        val id = fields[0]
        val rule = fields[2]
        val reason = when { id in items -> "duplicate item $id"; rule !in setOf("LFL", "FOQ", "POQ", "MIN") -> "unknown lot rule $rule"; lotParameters(rule, fields[3]) == null -> "bad lot parameter ${fields[3]} for $rule"; else -> null }
        if (reason != null) errors += "items.csv line $line: $reason"
        else items[id] = Item(id, fields[1].toInt(), rule, lotParameters(rule, fields[3])!!, fields[4].toLong(), fields[5].toLong(), fields[6].toLong(), fields[7].toLong(), fields[8])
    }
    return items
}
