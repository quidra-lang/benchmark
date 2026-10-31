fun main() {
    val rows = listOf(
        "#############",
        "#S..#.......#",
        "#.#.#.###.#.#",
        "#.#...#...#.#",
        "#.###.#.###.#",
        "#...#...#...#",
        "###.#####.#.#",
        "#.......#..G#",
        "#############",
    )
    val maze = rows.map { it.toCharArray() }
    var start = -1
    var goal = -1
    for (r in 0 until 9) {
        for (c in 0 until 13) {
            if (maze[r][c] == 'S') start = r * 13 + c
            if (maze[r][c] == 'G') goal = r * 13 + c
        }
    }
    val parent = IntArray(117) { -1 }
    parent[start] = start
    val queue = ArrayDeque<Int>()
    queue.addLast(start)
    val dr = intArrayOf(-1, 1, 0, 0)
    val dc = intArrayOf(0, 0, -1, 1)
    while (queue.isNotEmpty()) {
        val cell = queue.removeFirst()
        val r = cell / 13
        val c = cell % 13
        if (cell == goal) break
        for (d in 0 until 4) {
            val nr = r + dr[d]
            val nc = c + dc[d]
            if (nr !in 0 until 9 || nc !in 0 until 13) continue
            val next = nr * 13 + nc
            if (maze[nr][nc] != '#' && parent[next] < 0) {
                parent[next] = cell
                queue.addLast(next)
            }
        }
    }
    var steps = 0
    var cell = goal
    while (cell != start) {
        if (cell != goal) maze[cell / 13][cell % 13] = '*'
        steps++
        cell = parent[cell]
    }
    println("steps: $steps")
    for (row in maze) println(row.concatToString())
}
