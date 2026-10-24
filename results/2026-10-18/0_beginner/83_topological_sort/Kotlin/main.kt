fun courses(original: List<String>, edges: List<Pair<String,String>>, showCycle: Boolean) {
    val names = original.sorted()
    val n = names.size
    val degree = IntArray(n)
    val graph = Array(n) { BooleanArray(n) }
    for ((source,target) in edges) {
        val a = names.indexOf(source)
        val b = names.indexOf(target)
        graph[a][b] = true
        degree[b]++
    }
    val taken = BooleanArray(n)
    val order = mutableListOf<String>()
    while (true) {
        val next = names.indices.firstOrNull { !taken[it] && degree[it] == 0 } ?: break
        taken[next] = true
        order.add(names[next])
        for (i in names.indices) {
            if (graph[next][i]) degree[i]--
        }
    }
    println("order: ${order.joinToString(" -> ")}")
    if (showCycle) {
        val remaining = names.filterIndexed { i,_ -> !taken[i] }
        println("cycle: ${remaining.joinToString(" ")}")
    }
}
fun main() {
    courses(listOf("physics","algebra","graphics","programming","statistics","calculus","databases","algorithms"), listOf("calculus" to "physics",
        "algebra" to "calculus",
        "programming" to "algorithms",
        "algebra" to "statistics",
        "algorithms" to "databases",
        "statistics" to "databases",
        "calculus" to "graphics",
        "algorithms" to "graphics",
        "physics" to "graphics"),false)
    courses(listOf("music","ecology","art","geology","biology","chemistry"), listOf("music" to "art",
        "art" to "ecology",
        "biology" to "chemistry",
        "chemistry" to "ecology",
        "ecology" to "geology",
        "geology" to "chemistry"),true)
}
