fun smallestMultiple(quantity: Long, multiple: Long) = (quantity + multiple - 1) / multiple * multiple

fun lotSize(item: Item, week: Int, projected: Long, receipts: LongArray, gross: LongArray, horizon: Int): Long {
    val net = item.safety - projected
    return when (item.rule) {
        "LFL" -> net
        "FOQ" -> smallestMultiple(net, item.parameters[0])
        "MIN" -> smallestMultiple(maxOf(net, item.parameters[0]), item.parameters[1])
        else -> {
            var quantity = net
            var available = projected
            for (later in week + 1..minOf(week + item.parameters[0].toInt() - 1, horizon)) {
                available += receipts[later] - gross[later]
                quantity = maxOf(quantity, item.safety - available)
            }
            quantity
        }
    }
}
