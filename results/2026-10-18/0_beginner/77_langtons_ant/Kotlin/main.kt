import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    val black = Array(11) { BooleanArray(11) }
    var r = 5
    var c = 5
    var direction = 0
    val dr = intArrayOf(-1,0,1,0)
    val dc = intArrayOf(0,1,0,-1)
    repeat(300) {
        direction = (direction + if (black[r][c]) 3 else 1) % 4
        black[r][c] = !black[r][c]
        r = (r + dr[direction] + 11) % 11
        c = (c + dc[direction] + 11) % 11
    }
    var count = 0
    for (row in 0 until 11) {
        val line = buildString {
            for (column in 0 until 11) {
                if (black[row][column]) count++
                append(if (row == r && column == c) 'A' else if (black[row][column]) '#' else '.')
            }
        }
        println(line)
    }
    println("black: $count")
}
