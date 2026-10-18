import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    val groups = linkedMapOf<String,MutableList<String>>()
    for (word in listOf("listen","stone","night","silent","notes","apple","thing","enlist","earth","onset","heart","tones")) groups.getOrPut(word.toCharArray().sorted().joinToString("")) { mutableListOf() }.add(word)
    for (group in groups.values) println(group.joinToString(" "))
}
