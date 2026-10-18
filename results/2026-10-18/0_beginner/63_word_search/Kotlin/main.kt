import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    val board = listOf("MMONKENBIR", "PMTIGERJPL", "TGREJEDUZI", "SPYUTEJDEC", "WKAPSIDLBN",
        "KUVNGSBPRO", "RIBSDACBAM", "YWVAUAPKAH", "KYCGTHHESR", "OCCALAOKKR")
    val directions = listOf("E", "SE", "S", "SW", "W", "NW", "N", "NE")
    val dr = intArrayOf(0,1,1,1,0,-1,-1,-1)
    val dc = intArrayOf(1,1,0,-1,-1,-1,0,1)
    for (word in listOf("TIGER", "ZEBRA", "MONKEY", "PANDA", "KOALA", "RABBIT")) {
        var result = "not found"
        search@ for (r in 0 until 10) {
            for (c in 0 until 10) {
                for (d in 0 until 8) {
                    var match = true
                    for (k in word.indices) {
                        val nr = r + k * dr[d]
                        val nc = c + k * dc[d]
                        if (nr !in 0 until 10 || nc !in 0 until 10 || board[nr][nc] != word[k]) {
                            match = false
                            break
                        }
                    }
                    if (match) {
                        result = "($r, $c) ${directions[d]}"
                        break@search
                    }
                }
            }
        }
        println("$word: $result")
    }
}
