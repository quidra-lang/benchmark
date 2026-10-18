fun main() {
    val counts = IntArray(26)
    val sentence = "Peter Piper picked a peck of pickled peppers!"
    for (ch in sentence.lowercase()) if (ch in 'a'..'z') counts[ch - 'a']++
    for (i in counts.indices) if (counts[i] > 0) println("${'a' + i}: ${counts[i]}")
}
