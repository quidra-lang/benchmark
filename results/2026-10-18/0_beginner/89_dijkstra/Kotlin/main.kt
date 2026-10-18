fun main() {
    val edges = listOf(Triple(0,1,7),
        Triple(0,2,3),
        Triple(0,3,9),
        Triple(1,2,2),
        Triple(2,4,6),
        Triple(1,3,3),
        Triple(3,4,4),
        Triple(3,5,5),
        Triple(4,5,3),
        Triple(4,6,8),
        Triple(5,6,4))
    val weight = Array(7) { IntArray(7) }
    for ((a,b,w) in edges) {
        weight[a][b] = w
        weight[b][a] = w
    }
    val distance = IntArray(7) { Int.MAX_VALUE }
    val previous = IntArray(7) { -1 }
    distance[0] = 0
    val done = BooleanArray(7)
    repeat(7) {
        val u = (0 until 7).filter { !done[it] }.minBy { distance[it] }
        done[u] = true
        for (v in 0 until 7) {
            if (weight[u][v] > 0 && distance[u] + weight[u][v] < distance[v]) {
                distance[v] = distance[u] + weight[u][v]
                previous[v] = u
            }
        }
    }
    for (v in 0 until 7) {
        val path = mutableListOf<Char>()
        var u = v
        while (u >= 0) {
            path.add('A' + u)
            u = previous[u]
        }
        println("${'A' + v}: distance=${distance[v]} path=${path.reversed().joinToString("-")}")
    }
}
