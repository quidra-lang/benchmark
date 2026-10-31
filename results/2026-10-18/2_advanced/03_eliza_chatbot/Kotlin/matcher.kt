fun isWildcard(element: String) = element == "*" || element == "#" || element.startsWith("@")

fun matchPattern(pattern: List<String>, words: List<String>, groups: Map<String, Set<String>>): List<List<String>>? {
    val ends = mutableListOf<Int>()
    fun search(position: Int, start: Int): Boolean {
        if (position == pattern.size) return start == words.size
        val element = pattern[position]
        val candidates = when {
            element == "*" -> start..words.size
            start < words.size && (element == "#" || if (element.startsWith("@")) words[start] in groups[element.drop(1)].orEmpty() else element == words[start]) -> start + 1..start + 1
            else -> return false
        }
        for (end in candidates) {
            ends += end
            if (search(position + 1, end)) return true
            ends.removeAt(ends.lastIndex)
        }
        return false
    }
    if (!search(0, 0)) return null
    var start = 0
    val bindings = mutableListOf<List<String>>()
    for (index in pattern.indices) {
        if (isWildcard(pattern[index])) bindings += words.subList(start, ends[index]).toList()
        start = ends[index]
    }
    return bindings
}

fun patternCovers(earlier: List<String>, later: List<String>, groups: Map<String, Set<String>>): Boolean {
    fun elementCovers(element: String, other: String): Boolean = when {
        element == "#" -> other != "*"
        element.startsWith("@") -> if (other.startsWith("@")) groups.getValue(element.drop(1)).containsAll(groups.getValue(other.drop(1))) else other in groups.getValue(element.drop(1))
        else -> element == other
    }
    fun search(position: Int, start: Int): Boolean {
        if (position == earlier.size) return start == later.size
        if (earlier[position] == "*") return (start..later.size).any { search(position + 1, it) }
        return start < later.size && elementCovers(earlier[position], later[start]) && search(position + 1, start + 1)
    }
    return search(0, 0)
}
