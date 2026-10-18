fun determinant(matrix: List<List<Int>>): Int {
    if (matrix.size == 1) return matrix[0][0]
    var result = 0
    for (column in matrix.indices) {
        val minor = matrix.drop(1).map { row -> row.filterIndexed { c,_ -> c != column } }
        val term = matrix[0][column] * determinant(minor)
        result += if (column % 2 == 0) term else -term
    }
    return result
}
fun main() {
    val matrices = listOf(listOf(listOf(2,-3,1),listOf(5,4,-2),listOf(-1,6,3)),listOf(listOf(3,0,-2,5),listOf(1,4,7,-3),listOf(-6,2,1,8),listOf(9,-5,3,2)),listOf(listOf(4,-1,7,0,-3),listOf(2,8,-5,6,1),listOf(-9,3,2,-4,5),listOf(6,0,-7,3,-2),listOf(1,-6,4,9,8)))
    for (matrix in matrices) println("det(${matrix.size}x${matrix.size}) = ${determinant(matrix)}")
}
