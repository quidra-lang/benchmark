import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    val lines = listOf(
        "date,region,product,quantity,unit_price",
        "2026-04-01,north,notebook,10,200",
        "2026-04-01,east,marker,6,150",
        "2026-04-01,south,eraser,25,80",
        "2026-04-02,west,stapler,4,600",
        "2026-04-02,north,marker,8,150",
        "2026-04-02,east,notebook,9,200",
        "2026-04-03,south,stapler,3,600",
        "2026-04-03,west,eraser,15,80",
        "2026-04-03,north,eraser,20,80",
        "2026-04-04,east,stapler,5,600",
        "2026-04-04,south,notebook,6,200",
        "2026-04-04,west,marker,8,150")
    val regions = mutableMapOf<String,Int>()
    val products = sortedMapOf<String,Int>()
    val days = sortedMapOf<String,Int>()
    var total = 0
    for (line in lines.drop(1)) {
        val fields = line.split(',')
        val quantity = fields[3].toInt()
        val amount = quantity * fields[4].toInt()
        total += amount
        regions[fields[1]] = regions.getOrDefault(fields[1],0) + amount
        products[fields[2]] = products.getOrDefault(fields[2],0) + quantity
        days[fields[0]] = days.getOrDefault(fields[0],0) + amount
    }
    println("total: $total")
    val names = regions.keys.sortedWith(compareByDescending<String> { regions.getValue(it) }.thenBy { it })
    for (name in names) println("$name: ${regions.getValue(name)}")
    for ((name,quantity) in products) println("$name: $quantity")
    val best = days.keys.sortedWith(compareByDescending<String> { days.getValue(it) }.thenBy { it }).first()
    println("best day: $best (${days.getValue(best)})")
}
