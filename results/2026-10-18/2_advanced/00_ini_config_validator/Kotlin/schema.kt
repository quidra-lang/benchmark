class Spec(val line: Int, words: List<String>) {
    val pattern: String = words[0]
    val kind: String = words[1]
    val key: String = keyName(pattern)
    private val parts = sectionOf(pattern).split('.')
    val wildcard: Boolean = "*" in parts
    val attributes: Map<String, String> = words.drop(2).associate {
        it.substringBefore('=') to it.substringAfter('=', "")
    }
    fun has(name: String): Boolean = name in attributes
    operator fun get(name: String): String = attributes.getValue(name)
    val item: String get() = attributes["item"] ?: "string"
    val values: List<String> get() = attributes["values"]?.split(',') ?: emptyList()
    fun matches(section: String): Boolean {
        val actual = section.split('.')
        return parts.size == actual.size && parts.indices.all { parts[it] == "*" || parts[it] == actual[it] }
    }
}

class Schema(path: String) {
    val specs: List<Spec> = readLines(path).mapIndexedNotNull { index, line ->
        if (line.trim(' ').isEmpty() || line.startsWith('#')) null else Spec(index + 1, line.split(' '))
    }
    private val exact = specs.filterNot { it.wildcard }.associateBy { it.pattern }
    fun find(key: String): Spec? = exact[key] ?: specs.firstOrNull {
        it.wildcard && it.key == keyName(key) && it.matches(sectionOf(key))
    }
    fun targets(spec: Spec, sections: Set<String>): List<String> {
        if (!spec.wildcard) return listOf(spec.pattern)
        return sections.map { "$it.${spec.key}" }.filter {
            spec.matches(sectionOf(it)) && find(it) === spec
        }.sortedWith(keyOrder)
    }
}
