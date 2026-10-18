fun main() {
    val names = listOf("Sato","Suzuki","Takahashi","Tanaka","Ito","Watanabe")
    val usages = intArrayOf(85,120,254,300,438,176)
    var total = 0
    for (i in names.indices) {
        val u = usages[i]
        val bill = 900 + minOf(u,120) * 30 + (u - 120).coerceIn(0,180) * 36 + maxOf(u - 300,0) * 40
        total += bill
        println("${names[i]}: $u kWh, $bill yen")
    }
    println("total: $total yen")
}
