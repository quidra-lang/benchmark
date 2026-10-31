import java.util.TreeMap
import java.util.Locale
class Hyphenation(lines: List<String>, additions: List<String>, val left: Int, val right: Int) {
    val dictionary = mutableMapOf<String,List<Int>>()
    companion object {
        fun letter(c: Char) = c in 'A'..'Z' || c in 'a'..'z'
    }
    init {
        for (word in lines) register(word);
        for (word in additions) register(word)
    }
    fun register(spelling: String) {
        val word = StringBuilder();
        val points = mutableListOf<Int>();
        for (c in spelling) if (c == '-') points.add(word.length) else word.append(c);
        dictionary[word.toString()] = points
    }
    fun points(word: String): Map<Int,Boolean> {
        val points = TreeMap<Int,Boolean>();
        var first = 0;
        var last = word.length;
        while (first < word.length && !letter(word[first])) first++;
        while (last > first && !letter(word[last - 1])) last--;
        val core = word.substring(first,last);
        if (core.isNotEmpty() && core.all {
            letter(it)
        }) for (position in dictionary[core.lowercase(Locale.ROOT)] ?: emptyList()) if (position >= left && core.length - position >= right) points[first + position] = true;
        for (i in 1 until word.length - 1) if (word[i] == '-' && letter(word[i - 1]) && letter(word[i + 1])) points[i + 1] = false;
        return points
    }
}
