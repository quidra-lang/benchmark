data class BomRow(val parent: String, val child: String, val quantity: Long, val scrap: Long) {
    fun need(parentQuantity: Long) = (parentQuantity * quantity * (100L + scrap) + 99L) / 100L
}

class Bom(items: Map<String, Item>) {
    val children = items.keys.associateWith { mutableListOf<BomRow>() }
    val parents = items.keys.associateWith { mutableListOf<BomRow>() }
    fun manufactured(id: String) = children.getValue(id).isNotEmpty()
    fun add(row: BomRow) {
        children.getValue(row.parent).add(row)
        children.getValue(row.parent).sortBy { it.child }
        parents.getValue(row.child).add(row)
        parents.getValue(row.child).sortBy { it.parent }
    }
    fun path(start: String, target: String): List<String>? {
        val visited = mutableSetOf<String>()
        fun search(id: String): List<String>? {
            if (id == target) return listOf(id)
            visited += id
            for (row in children.getValue(id)) if (row.child !in visited) {
                val rest = search(row.child)
                if (rest != null) return listOf(id) + rest
            }
            return null
        }
        return search(start)
    }
    fun lowLevelCodes(): Map<String, Int> {
        val codes = mutableMapOf<String, Int>()
        fun code(id: String): Int {
            codes[id]?.let { return it }
            val value = parents.getValue(id).maxOfOrNull { code(it.parent) + 1 } ?: 0
            codes[id] = value
            return value
        }
        for (id in children.keys) code(id)
        return codes
    }
    fun cumulativeLeadTimes(items: Map<String, Item>): Map<String, Int> {
        val times = mutableMapOf<String, Int>()
        fun time(id: String): Int {
            times[id]?.let { return it }
            val value = items.getValue(id).leadTime + (children.getValue(id).maxOfOrNull { time(it.child) } ?: 0)
            times[id] = value
            return value
        }
        for (id in children.keys) time(id)
        return times
    }
}

fun readBom(items: Map<String, Item>, errors: MutableList<String>): Bom {
    val bom = Bom(items)
    for ((line, fields) in csvRows("bom.csv")) {
        val parent = fields[0]
        val child = fields[1]
        val quantity = fields[2].toLong()
        val scrap = fields[3].toLong()
        var reason = when { parent !in items -> "unknown item $parent"; child !in items -> "unknown item $child"; quantity < 1 -> "bad quantity $quantity"; scrap > 50 -> "bad scrap $scrap"; parent == child -> "cycle $parent -> $parent"; bom.children.getValue(parent).any { it.child == child } -> "duplicate $parent -> $child"; else -> null }
        if (reason == null) bom.path(child, parent)?.let { reason = "cycle $parent -> ${it.joinToString(" -> ")}" }
        if (reason != null) errors += "bom.csv line $line: $reason"
        else bom.add(BomRow(parent, child, quantity, scrap))
    }
    return bom
}
