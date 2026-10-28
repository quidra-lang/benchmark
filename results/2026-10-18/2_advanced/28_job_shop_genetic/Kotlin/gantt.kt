data class Interval(val start: Int, val end: Int, val mark: Char)
object Gantt {
    fun scale(makespan: Int, width: Int): Pair<Int, Int> {
        var magnitude = 1
        while (true) {
            for (step in intArrayOf(1, 2, 5)) {
                val scale = magnitude * step;
                val columns = (makespan + scale - 1) / scale;
                if (columns <= width) return scale to columns
            };
            magnitude *= 10
        }
    }
    fun time(scale: Int, columns: Int): String {
        val row = StringBuilder("time");
        for (c in 0 until columns step 10) {
            while (row.length < 6 + c) row.append(' ');
            row.append(c * scale)
        };
        return row.toString()
    }
    fun rule(columns: Int): String = "      " + (0 until columns).joinToString("") {
        if (it % 10 == 0) "+" else "-"
    }
    fun frame(label: String, marks: String): String = label.padEnd(4) + " |$marks|"
    fun row(label: String, intervals: List<Interval>, scale: Int, columns: Int): String {
        val ordered = intervals.sortedBy {
            it.start
        }
        val marks = (0 until columns).map {
            c ->
            var widest = 0;
            var mark = '.'
            for (interval in ordered) {
                val overlap = minOf(interval.end, (c + 1) * scale) - maxOf(interval.start, c * scale);
                if (overlap > widest) {
                    widest = overlap;
                    mark = interval.mark
                }
            }
            mark
        }.joinToString("")
        return frame(label, marks)
    }
    fun busy(machines: List<List<Interval>>, scale: Int, columns: Int): String = frame("busy", (0 until columns).joinToString("") {
        c -> val count = machines.count {
            intervals -> intervals.any {
                it.start <= c * scale && c * scale < it.end
            }
        };
        if (count == 10) "X" else count.toString()
    })
}
