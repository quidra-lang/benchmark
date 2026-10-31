data class StandardCost(val material: Long, val labor: Long) { val total get() = material + labor }

fun standardCosts(items: Map<String, Item>, bom: Bom, order: List<String>): Map<String, StandardCost> {
    val costs = mutableMapOf<String, StandardCost>()
    for (id in order.reversed()) {
        var material = items.getValue(id).material
        var labor = items.getValue(id).labor
        for (row in bom.children.getValue(id)) {
            val child = costs.getValue(row.child)
            material += (row.quantity * (100L + row.scrap) * child.material + 50L) / 100L
            labor += (row.quantity * (100L + row.scrap) * child.labor + 50L) / 100L
        }
        costs[id] = StandardCost(material, labor)
    }
    return costs
}

fun abcClasses(values: Map<String, Long>): Map<String, String> {
    val total = values.values.sum()
    val classes = mutableMapOf<String, String>()
    var before = 0L
    for (id in values.keys.sortedWith(compareByDescending<String> { values.getValue(it) }.thenBy { it })) {
        val value = values.getValue(id)
        classes[id] = when { value == 0L -> "C"; 100L * before < 80L * total -> "A"; 100L * before < 95L * total -> "B"; else -> "C" }
        before += value
    }
    return classes
}
