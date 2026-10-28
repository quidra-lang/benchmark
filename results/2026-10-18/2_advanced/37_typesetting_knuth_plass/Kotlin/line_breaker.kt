import kotlin.math.abs
object LineBreaker {
    data class Result(val breaks: List<Int>, val cost: Int)
    fun fitness(slack: Int, last: Boolean) = if (last) 1 else if (slack <= 1) 0 else if (slack <= 3) 1 else if (slack <= 6) 2 else 3
    fun cost(metrics: Metrics, start: Int, end: Int, previous: Int, params: Map<String,Int>): Int {
        val slack = metrics.slack(start,end);
        var total = params.getValue("line_penalty");
        val current = fitness(slack,end == metrics.end());
        if (slack < 0) total += params.getValue("overfull_penalty") else if (end != metrics.end()) total += slack * slack;
        if (metrics.breaks[end].mid) {
            total += params.getValue("hyphen_penalty");
            if (metrics.breaks[start].mid) total += params.getValue("double_hyphen_demerit")
        };
        if (end == metrics.end() && metrics.breaks[start].mid) total += params.getValue("final_hyphen_demerit");
        if (abs(current - previous) >= 2) total += params.getValue("fitness_demerit");
        return total
    }
    fun split(metrics: Metrics, optimal: Boolean, params: Map<String,Int>): Result {
        val end = metrics.end();
        val breaking = mutableListOf<Int>()
        if (!optimal) {
            var start = 0;
            var total = 0;
            var previous = 1;
            while (start < end) {
                var chosen = start + 1;
                if (metrics.slack(start,chosen) >= 0) for (b in chosen + 1..end) {
                    if (metrics.slack(start,b) < 0) break;
                    chosen = b
                };
                total += cost(metrics,start,chosen,previous,params);
                previous = fitness(metrics.slack(start,chosen),chosen == end);
                breaking.add(chosen);
                start = chosen
            };
            return Result(breaking,total)
        }
        val costs = Array(end + 1) {
            IntArray(4) {
                -1
            }
        };
        val parents = Array(end + 1) {
            IntArray(4)
        };
        val classes = Array(end + 1) {
            IntArray(4)
        };
        costs[0][1] = 0
        for (b in 1..end) for (a in b - 1 downTo 0) {
            val slack = metrics.slack(a,b);
            if (slack < 0 && b != a + 1) break;
            val c = fitness(slack,b == end);
            for (previous in 0..3) if (costs[a][previous] >= 0) {
                val candidate = costs[a][previous] + cost(metrics,a,b,previous,params);
                if (costs[b][c] < 0 || candidate < costs[b][c] || candidate == costs[b][c] && (a < parents[b][c] || a == parents[b][c] && previous < classes[b][c])) {
                    costs[b][c] = candidate;
                    parents[b][c] = a;
                    classes[b][c] = previous
                }
            }
        }
        var position = end;
        var c = 1;
        while (position > 0) {
            breaking.add(position);
            val previous = classes[position][c];
            position = parents[position][c];
            c = previous
        };
        breaking.reverse();
        return Result(breaking,costs[end][1])
    }
}
