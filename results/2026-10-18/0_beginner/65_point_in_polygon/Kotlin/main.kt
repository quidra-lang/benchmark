fun main() {
    val polygon = listOf(1 to 1,11 to 2,13 to 9,9 to 7,7 to 12,5 to 6,2 to 10,3 to 5)
    for ((px,py) in listOf(4 to 8,6 to 4,10 to 8,7 to 11,14 to 3,12 to 8)) {
        var inside = false
        for (i in polygon.indices) {
            val (x1,y1) = polygon[i]
            val (x2,y2) = polygon[(i + 1) % polygon.size]
            if ((y1 > py) != (y2 > py)) {
                val intersection = x1 + (x2 - x1) * (py - y1) / (y2 - y1).toDouble()
                if (intersection > px) inside = !inside
            }
        }
        println("($px, $py): ${if (inside) "inside" else "outside"}")
    }
}
