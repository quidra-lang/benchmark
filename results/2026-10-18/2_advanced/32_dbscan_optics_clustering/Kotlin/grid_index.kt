data class Cell(val x: Int, val y: Int)
data class Neighborhood(val points: IntArray, val candidates: Int)
class GridIndex(val points: List<Point>, val radius: Int) {
    val cells = mutableMapOf<Cell, MutableList<Int>>()
    init {
        for ((i, point) in points.withIndex()) cells.getOrPut(Cell(point.x / radius, point.y / radius)) {
            mutableListOf()
        }.add(i)
    }
    fun neighborhood(index: Int): Neighborhood {
        val point = points[index];
        val x = point.x / radius;
        val y = point.y / radius;
        var candidates = 0;
        val neighbors = mutableListOf<Int>()
        for (row in y - 1..y + 1) for (column in x - 1..x + 1) for (other in cells[Cell(column, row)].orEmpty()) {
            candidates++;
            if (distance(point, points[other]) <= radius * radius) neighbors.add(other)
        }
        return Neighborhood(neighbors.toIntArray(), candidates)
    }
    fun busiest(): Cell = cells.keys.minWith(compareByDescending<Cell> {
        cells.getValue(it).size
    }.thenBy {
        it.y
    }.thenBy {
        it.x
    })
    fun bruteCounts(): IntArray = IntArray(points.size) {
        i -> points.count {
            distance(points[i], it) <= radius * radius
        }
    }
    companion object {
        fun distance(a: Point, b: Point): Int {
            val x = a.x - b.x;
            val y = a.y - b.y;
            return x * x + y * y
        }
    }
}
