fun main() {
    val a = setOf(12,5,8,21,5,17,3,12,9)
    val b = setOf(8,14,21,6,14,3,25,6)
    val results = listOf(a union b, a intersect b, a subtract b, (a union b) subtract (a intersect b))
    val labels = listOf("union", "intersection", "difference", "symmetric difference")
    for (i in labels.indices) println("${labels[i]}: ${results[i].sorted().joinToString(" ")}")
}
