fun main() {
    val groups = listOf(
        "listen", "stone", "night", "silent", "notes", "apple", "thing", "enlist", "earth", "onset",
        "heart", "tones",
    )
        .groupBy { it.toCharArray().sorted().joinToString("") }
    for (group in groups.values) println(group.joinToString(" "))
}
