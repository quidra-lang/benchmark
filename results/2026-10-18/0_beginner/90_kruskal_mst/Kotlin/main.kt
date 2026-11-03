fun find(parent: IntArray, v: Int): Int {
    if (parent[v] != v) parent[v] = find(parent, parent[v])
    return parent[v]
}

fun main() {
    val edges = listOf(
        Triple(0, 1, 7), Triple(2, 0, 4), Triple(1, 2, 9), Triple(1, 3, 14), Triple(3, 2, 6), Triple(2, 4, 3),
        Triple(4, 3, 5), Triple(5, 3, 11), Triple(4, 6, 16), Triple(6, 5, 8), Triple(7, 5, 12), Triple(6, 7, 2),
        Triple(7, 4, 10),
    )
    val parent = IntArray(8) { it }
    var accepted = 0
    var skipped = 0
    var total = 0
    for ((u, v, weight) in edges.sortedBy { it.third }) {
        val a = find(parent, u)
        val b = find(parent, v)
        if (a == b) {
            skipped++
            continue
        }
        parent[a] = b
        accepted++
        total += weight
        println("${'A' + minOf(u, v)}-${'A' + maxOf(u, v)} $weight")
        if (accepted == 7) break
    }
    println("total weight: $total")
    println("skipped: $skipped")
}
