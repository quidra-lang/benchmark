import kotlin.math.abs
object Encoders {
    fun queens(n: Int): CnfIo.Formula {
        val clauses = mutableListOf<IntArray>();
        for (r in 0 until n) clauses.add(IntArray(n) {
            r * n + it + 1
        });
        for (a in 1..n * n) for (b in a + 1..n * n) {
            val ar = (a - 1) / n;
            val ac = (a - 1) % n;
            val br = (b - 1) / n;
            val bc = (b - 1) % n;
            if (ar == br || ac == bc || abs(ar - br) == abs(ac - bc)) clauses.add(intArrayOf(-a,-b))
        };
        return CnfIo.Formula(n * n,clauses)
    }
    fun pigeon(p: Int, h: Int): CnfIo.Formula {
        val clauses = mutableListOf<IntArray>();
        for (i in 0 until p) clauses.add(IntArray(h) {
            i * h + it + 1
        });
        for (i in 0 until p) for (a in 1..h) for (b in a + 1..h) clauses.add(intArrayOf(-(i * h + a),-(i * h + b)));
        for (j in 1..h) for (a in 0 until p) for (b in a + 1 until p) clauses.add(intArrayOf(-(a * h + j),-(b * h + j)));
        return CnfIo.Formula(p * h,clauses)
    }
    fun coloring(vertices: Int, edges: List<IntArray>, k: Int): CnfIo.Formula {
        val clauses = mutableListOf<IntArray>();
        for (x in 0 until vertices) clauses.add(IntArray(k) {
            x * k + it + 1
        });
        for (x in 0 until vertices) for (a in 1..k) for (b in a + 1..k) clauses.add(intArrayOf(-(x * k + a),-(x * k + b)));
        for (edge in edges) for (c in 1..k) clauses.add(intArrayOf(-((edge[0] - 1) * k + c),-((edge[1] - 1) * k + c)));
        return CnfIo.Formula(vertices * k,clauses)
    }
    fun positions(model: BooleanArray, rows: Int, width: Int): IntArray {
        val positions = IntArray(rows);
        for (r in 0 until rows) for (c in 1..width) if (model[r * width + c]) positions[r] = c;
        return positions
    }
}
