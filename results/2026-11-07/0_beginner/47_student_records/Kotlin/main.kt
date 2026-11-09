import java.util.Locale

data class Student(val name: String, val total: Int)

fun main() {
    val names = listOf("Tanaka", "Suzuki", "Yamada", "Ito", "Kato", "Mori")
    val scores = listOf(
        listOf(78, 85, 94), listOf(88, 74, 82), listOf(65, 90, 71), listOf(80, 79, 85),
        listOf(92, 88, 95), listOf(70, 62, 78),
    )
    val students = names.zip(scores) { name, row -> Student(name, row.sum()) }
        .sortedWith(compareByDescending<Student> { it.total }.thenBy { it.name })
    var rank = 0
    var previous = -1
    for ((position, student) in students.withIndex()) {
        if (student.total != previous) rank = position + 1
        previous = student.total
        println("%d. %s total=%d average=%.2f".format(Locale.ROOT, rank, student.name, student.total, student.total / 3.0))
    }
}
