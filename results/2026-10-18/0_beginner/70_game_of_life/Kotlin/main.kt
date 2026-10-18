fun main() {
    val initial = listOf(".#......", "..#.....", "###.....", "........",
        "........", "........", ".....###", "........")
    var board = Array(8) { r -> BooleanArray(8) { c -> initial[r][c] == '#' } }
    for (generation in 0..4) {
        println("generation $generation")
        for (row in board) println(row.joinToString("") { if (it) "#" else "." })
        if (generation == 4) break
        val next = Array(8) { BooleanArray(8) }
        for (r in 0 until 8) {
            for (c in 0 until 8) {
                var neighbors = 0
                for (dr in -1..1) {
                    for (dc in -1..1) {
                        if (dr == 0 && dc == 0) continue
                        val nr = r + dr
                        val nc = c + dc
                        if (nr in 0 until 8 && nc in 0 until 8 && board[nr][nc]) neighbors++
                    }
                }
                next[r][c] = neighbors == 3 || (board[r][c] && neighbors == 2)
            }
        }
        board = next
    }
    println("alive: ${board.sumOf { row -> row.count { it } }}")
}
