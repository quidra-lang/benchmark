data class LetterKey(val length: Int, val position: Int, val letter: Char)
class WordIndex(val scores: Map<String, Int>) {
    val ranked = scores.keys.sortedWith(compareByDescending<String> { scores.getValue(it) }.thenBy { it })
    val byLength = sortedMapOf<Int, MutableList<String>>()
    val byLetter = mutableMapOf<LetterKey, MutableList<String>>()
    init {
        for (word in ranked) {
            byLength.getOrPut(word.length) { mutableListOf() }.add(word)
            for (position in word.indices) byLetter.getOrPut(LetterKey(word.length, position, word[position])) { mutableListOf() }.add(word)
        }
    }
    fun candidates(pattern: String, minimum: Int, used: Set<String>): List<String> {
        var pool: List<String> = byLength[pattern.length] ?: emptyList()
        for (position in pattern.indices) if (pattern[position] != '.') {
            val bucket = byLetter[LetterKey(pattern.length, position, pattern[position])] ?: emptyList()
            if (bucket.size < pool.size) pool = bucket
        }
        val candidates = mutableListOf<String>()
        for (word in pool) {
            if (scores.getValue(word) < minimum) break
            if (word !in used && matches(word, pattern)) candidates.add(word)
        }
        return candidates
    }
    companion object {
        fun validWord(text: String) = text.length in 3..15 && text.all { it in 'A'..'Z' }
        fun validInteger(text: String, low: Int, high: Int): Boolean {
            if (text.isEmpty() || text[0] == '0' || text.length > high.toString().length || !text.all { it in '0'..'9' }) return false
            return text.toInt() in low..high
        }
        fun wordError(line: String): String? {
            if (line.count { it == ' ' } != 1) return "bad format"
            val split = line.indexOf(' ')
            if (!validWord(line.substring(0, split))) return "bad word"
            return if (validInteger(line.substring(split + 1), 1, 100)) null else "bad score"
        }
        fun clueError(line: String): String? {
            if (line.count { it == '|' } != 1) return "bad format"
            val split = line.indexOf('|')
            val word = line.substring(0, split)
            val clue = line.substring(split + 1)
            if (!validWord(word)) return "bad word"
            return if (clue.isEmpty() || clue.length > 60 || clue.first() == ' ' || clue.last() == ' ') "bad clue" else null
        }
        fun matches(word: String, pattern: String): Boolean {
            for (position in pattern.indices) if (pattern[position] != '.' && pattern[position] != word[position]) return false
            return true
        }
    }
}
