class Expander(private val profile: Profile) {
    private val results = mutableMapOf<String, String?>()
    private val stack = mutableListOf<String>()
    private val cycleKeys = mutableSetOf<String>()

    fun expandAll(): Map<String, String?> {
        for (key in profile.configuration.keys.sortedWith(keyOrder)) expand(key)
        return results
    }
    private fun expand(key: String): String? {
        if (key in results) return results[key]
        stack += key
        val result = evaluate(key)
        stack.removeAt(stack.lastIndex)
        results[key] = result
        return result
    }
    private fun evaluate(key: String): String? {
        val definition = profile.configuration.getValue(key)
        val text = definition.value
        val result = StringBuilder()
        var position = 0
        while (position < text.length) {
            if (!text.startsWith("\${", position)) {
                val c = text[position++]
                result.append(if (c == LITERAL_DOLLAR) '$' else c)
                continue
            }
            val close = text.indexOf('}', position + 2)
            if (close < 0 || !isSectionName(text.substring(position + 2, close))) {
                profile.report(definition.origin, "E_BAD_REF", "$key: invalid reference")
                return null
            }
            val reference = text.substring(position + 2, close)
            val target = if ('.' in reference) reference else "${sectionOf(key)}.$reference"
            if (target !in profile.configuration) {
                profile.report(definition.origin, "E_UNDEFINED", "$key: undefined reference $target")
                return null
            }
            val cycle = stack.indexOf(target)
            val expanded = if (cycle >= 0) {
                val path = stack.drop(cycle) + target
                profile.report(profile.configuration.getValue(target).origin, "E_CYCLE", "interpolation cycle " + path.joinToString(" -> "))
                cycleKeys.addAll(path)
                null
            } else expand(target)
            if (expanded == null) {
                if (key !in cycleKeys) profile.report(definition.origin, "E_DEPENDENCY", "$key: depends on failed key $target")
                return null
            }
            result.append(expanded)
            position = close + 1
        }
        return result.toString()
    }
}
