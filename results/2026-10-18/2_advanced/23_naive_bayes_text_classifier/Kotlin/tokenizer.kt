import java.util.Locale

class Tokenizer(text: String, stopwords: Set<String>) {
    val words = mutableListOf<String>()
    val bigrams = mutableListOf<String>()
    val bigramTerms: List<String>
    var rawCount = 0
        private set
    var stopwordCount = 0
        private set
    var shortCount = 0
        private set

    init {
        for (match in Regex("[A-Za-z0-9]+").findAll(text)) {
            val word = match.value.lowercase(Locale.ROOT)
            rawCount++
            if (word in stopwords) stopwordCount++
            else if (word.length == 1) shortCount++
            else words.add(word)
        }
        for (i in 1 until words.size) bigrams.add(words[i - 1] + "_" + words[i])
        bigramTerms = words + bigrams
    }

    fun terms(useBigrams: Boolean): List<String> = if (useBigrams) bigramTerms else words
}
