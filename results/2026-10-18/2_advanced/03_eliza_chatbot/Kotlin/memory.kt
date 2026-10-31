class MemoryQueue(val capacity: Int, val texts: MutableList<String> = mutableListOf(), val log: MutableList<String> = mutableListOf()) {
    fun copy() = MemoryQueue(capacity, texts.toMutableList(), log.toMutableList())
    fun store(prefix: String, keyword: String, text: String): Boolean {
        if (text in texts) { log += "$prefix SKIP $keyword $text"; return false }
        if (texts.size == capacity) log += "$prefix DROP ${texts.removeAt(0)}"
        texts += text
        log += "$prefix STORE $keyword $text"
        return true
    }
    fun recall(prefix: String): String {
        val text = texts.removeAt(0)
        log += "$prefix RECALL $text"
        return text
    }
    fun clear(prefix: String) {
        if (texts.isNotEmpty()) { log += "$prefix CLEAR ${texts.size}"; texts.clear() }
    }
}
