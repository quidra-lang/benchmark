import java.math.BigDecimal
import java.math.RoundingMode

data class Task(val name: String, val priority: Int, val sequence: Int)
fun main() {
    val operations = listOf("add email 3", "add backup 5", "add deploy 1", "run", "add report 3", "add test 2",
        "add lint 3", "run", "run", "add cleanup 5", "add review 2", "run", "add build 1",
        "add docs 4", "run", "run")
    val queue = java.util.PriorityQueue<Task>(compareBy<Task> { it.priority }.thenBy { it.sequence })
    var sequence = 0
    for (operation in operations) {
        val parts = operation.split(' ')
        if (parts[0] == "add") queue.add(Task(parts[1],parts[2].toInt(),sequence++))
        else {
            val task = queue.remove()
            println("run: ${task.name} (priority ${task.priority})")
        }
    }
    val remaining = mutableListOf<String>()
    while (queue.isNotEmpty()) remaining.add(queue.remove().name)
    println("remaining: ${remaining.joinToString(" ")}")
}
