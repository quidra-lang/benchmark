fun main() {
    val matches = listOf("Lions 0-3 Bears",
        "Tigers 2-2 Wolves",
        "Eagles 4-0 Sharks",
        "Bears 0-1 Sharks",
        "Wolves 2-1 Eagles",
        "Lions 0-1 Tigers",
        "Tigers 3-3 Bears",
        "Eagles 2-2 Lions",
        "Sharks 2-2 Wolves",
        "Bears 3-1 Wolves",
        "Lions 2-0 Sharks",
        "Tigers 2-1 Eagles",
        "Eagles 1-0 Bears",
        "Sharks 2-0 Tigers",
        "Wolves 2-1 Lions")
    val names = listOf("Lions","Tigers","Eagles","Sharks","Wolves","Bears")
    val stats = Array(6) { IntArray(6) }
    for (match in matches) {
        val parts = match.split(' ')
        val goals = parts[1].split('-').map { it.toInt() }
        val home = names.indexOf(parts[0])
        val away = names.indexOf(parts[2])
        val (h,a) = goals
        stats[home][0]++
        stats[away][0]++
        stats[home][4] += h
        stats[home][5] += a
        stats[away][4] += a
        stats[away][5] += h
        if (h == a) {
            stats[home][2]++
            stats[away][2]++
        } else {
            stats[if (h > a) home else away][1]++
            stats[if (h > a) away else home][3]++
        }
    }
    val order = names.indices.sortedWith(compareByDescending<Int> { 3 * stats[it][1] + stats[it][2] }
        .thenByDescending { stats[it][4] - stats[it][5] }.thenByDescending { stats[it][4] }.thenBy { names[it] })
    for ((position,i) in order.withIndex()) {
        val gd = stats[i][4] - stats[i][5]
        val difference = (if (gd > 0) "+" else "") + gd
        println("${position + 1}. ${names[i]} P=${stats[i][0]} W=${stats[i][1]} D=${stats[i][2]} " +
            "L=${stats[i][3]} GF=${stats[i][4]} GA=${stats[i][5]} GD=$difference Pts=${3 * stats[i][1] + stats[i][2]}")
    }
}
