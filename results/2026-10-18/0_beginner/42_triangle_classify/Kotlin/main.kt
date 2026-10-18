fun main() {
    for (sides in listOf(listOf(3,8,5),listOf(6,6,6),listOf(5,8,5),listOf(13,5,12),listOf(2,9,4),listOf(7,4,7),listOf(8,6,7),listOf(4,9,6))) {
        val prefix = sides.joinToString(" ") + ": "
        val (a,b,c) = sides.sorted()
        if (a + b <= c) {
            println(prefix + "not a triangle")
            continue
        }
        val side = if (a == c) "equilateral" else if (a == b || b == c) "isosceles" else "scalene"
        val difference = c * c - a * a - b * b
        val angle = if (difference < 0) "acute" else if (difference == 0) "right" else "obtuse"
        println(prefix + "$side $angle")
    }
}
