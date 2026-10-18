import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    val boards = listOf(listOf("XXX","OO.","O.X"),listOf("X.O",".X.","O.."),
        listOf("XO.",".OX","XO."),listOf("XOX","XOO","OXX"),
        listOf("X.O","XO.","O.X"),listOf("XOX","OXO","OXX"))
    val lines = listOf(listOf(0,1,2),listOf(3,4,5),listOf(6,7,8),listOf(0,3,6),
        listOf(1,4,7),listOf(2,5,8),listOf(0,4,8),listOf(2,4,6))
    for ((i,board) in boards.withIndex()) {
        val cells = board.joinToString("")
        var result = if ('.' in cells) "in progress" else "draw"
        for (line in lines) {
            val mark = cells[line[0]]
            if (mark != '.' && mark == cells[line[1]] && mark == cells[line[2]]) {
                result = "$mark wins"
                break
            }
        }
        println("board ${i + 1}: $result")
    }
}
