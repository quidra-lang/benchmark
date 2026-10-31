data class WorkCenter(val id: String, val minutes: Long, val efficiency: Long, val description: String) { val available get() = minutes * efficiency / 100L }
data class Operation(val item: String, val number: Int, val center: String, val setup: Long, val run: Long) { fun minutes(quantity: Long) = setup + quantity * run }

fun readCenters(errors: MutableList<String>): Map<String, WorkCenter> {
    val centers = sortedMapOf<String, WorkCenter>()
    for ((line, fields) in csvRows("workcenters.csv")) {
        val id = fields[0]
        val efficiency = fields[2].toLong()
        val reason = when { id in centers -> "duplicate center $id"; efficiency !in 50L..150L -> "bad efficiency $efficiency"; else -> null }
        if (reason != null) errors += "workcenters.csv line $line: $reason"
        else centers[id] = WorkCenter(id, fields[1].toLong(), efficiency, fields[3])
    }
    return centers
}

fun readRoutings(items: Map<String, Item>, centers: Map<String, WorkCenter>, bom: Bom, errors: MutableList<String>): Map<String, List<Operation>> {
    val routings = mutableMapOf<String, MutableList<Operation>>()
    for ((line, fields) in csvRows("routings.csv")) {
        val id = fields[0]
        val number = fields[1].toInt()
        val center = fields[2]
        val run = fields[4].toLong()
        val reason = when { id !in items -> "unknown item $id"; center !in centers -> "unknown center $center"; !bom.manufactured(id) -> "purchased item $id"; run < 1 -> "bad run time $run"; routings[id].orEmpty().any { it.number == number } -> "duplicate $id operation $number"; else -> null }
        if (reason != null) errors += "routings.csv line $line: $reason"
        else routings.getOrPut(id) { mutableListOf() }.add(Operation(id, number, center, fields[3].toLong(), run))
    }
    return routings.mapValues { it.value.sortedBy { operation -> operation.number } }
}

fun operationWeek(receipt: Int, leadTime: Int, index: Int, count: Int) = maxOf(1, receipt - leadTime + index * leadTime / count)
fun leveledLoads(loads: LongArray, available: Long): LongArray {
    val result = LongArray(loads.size)
    var carry = 0L
    for (week in loads.lastIndex downTo 2) {
        val total = loads[week] + carry
        result[week] = minOf(total, available)
        carry = total - result[week]
    }
    result[1] = loads[1] + carry
    return result
}
