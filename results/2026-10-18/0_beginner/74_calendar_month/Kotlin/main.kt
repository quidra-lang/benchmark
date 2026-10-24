fun main() {
    val names = listOf("January","February","March","April","May","June",
        "July","August","September","October","November","December")
    val offsets = intArrayOf(0,3,2,5,0,3,5,1,4,6,2,4)
    for ((index,pair) in listOf(2024 to 2,2026 to 8,2026 to 11).withIndex()) {
        if (index > 0) println()
        val (year,month) = pair
        val y = if (month < 3) year - 1 else year
        val weekday = (y + y / 4 - y / 100 + y / 400 + offsets[month - 1] + 1) % 7
        val lengths = intArrayOf(31,28,31,30,31,30,31,31,30,31,30,31)
        if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) lengths[1] = 29
        println("${names[month - 1]} $year")
        println("Su Mo Tu We Th Fr Sa")
        val week = MutableList(weekday) { "  " }
        for (day in 1..lengths[month - 1]) {
            week.add(day.toString().padStart(2))
            if (week.size == 7) {
                println(week.joinToString(" "))
                week.clear()
            }
        }
        if (week.isNotEmpty()) println(week.joinToString(" "))
    }
}
