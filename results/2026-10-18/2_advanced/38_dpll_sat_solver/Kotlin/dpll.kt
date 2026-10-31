import kotlin.math.abs
object Dpll {
    class Stats {
        var decisions = 0;
        var propagations = 0;
        var conflicts = 0;
        var maxDepth = 0;
        fun add(other: Stats) {
            decisions += other.decisions;
            propagations += other.propagations;
            conflicts += other.conflicts;
            maxDepth = maxOf(maxDepth,other.maxDepth)
        }
    }
    data class Entry(val literal: Int, val kind: Int)
    data class Result(val model: BooleanArray?, val trace: List<String>, val stats: Stats)
    class State(variables: Int, original: List<IntArray>) {
        val clauses = original.map {
            it.copyOf()
        };
        val assignment = IntArray(variables + 1);
        val watches = List(2 * (variables + 1)) {
            mutableListOf<Int>()
        };
        val trail = mutableListOf<Entry>();
        val trace = mutableListOf<String>();
        val stats = Stats();
        var head = 0
        init {
            for (i in clauses.indices) {
                val clause = clauses[i];
                if (clause.size >= 2) {
                    watch(clause[0]).add(i);
                    watch(clause[1]).add(i)
                }
            }
        }
        fun watch(literal: Int) = watches[2 * abs(literal) + if (literal < 0) 1 else 0]
        fun value(literal: Int) = assignment[abs(literal)] * if (literal > 0) 1 else -1
        fun assign(literal: Int, kind: Int) {
            assignment[abs(literal)] = if (literal > 0) 1 else -1;
            trail.add(Entry(literal,kind));
            trace.add(listOf("D","F","P")[kind] + literal)
        }
        fun conflict() {
            stats.conflicts++;
            trace.add("C")
        }
        fun result(satisfied: Boolean) = Result(if (satisfied) BooleanArray(assignment.size) {
            assignment[it] == 1
        } else null,trace,stats)
        fun run(): Result {
            for (clause in clauses) {
                if (clause.isEmpty() || clause.size == 1 && value(clause[0]) < 0) {
                    conflict();
                    return result(false)
                };
                if (clause.size == 1 && value(clause[0]) == 0) {
                    assign(clause[0],2);
                    stats.propagations++
                }
            }
            while (true) {
                var foundConflict = false
                while (head < trail.size) {
                    val falseLiteral = -trail[head++].literal;
                    val watched = watch(falseLiteral);
                    var index = 0
                    while (index < watched.size) {
                        val id = watched[index];
                        val clause = clauses[id];
                        if (clause[0] == falseLiteral) {
                            val swap = clause[0];
                            clause[0] = clause[1];
                            clause[1] = swap
                        };
                        val other = clause[0];
                        if (value(other) > 0) {
                            index++;
                            continue
                        };
                        var replacement = -1;
                        for (j in 2 until clause.size) if (value(clause[j]) >= 0) {
                            replacement = j;
                            break
                        };
                        if (replacement >= 0) {
                            val swap = clause[1];
                            clause[1] = clause[replacement];
                            clause[replacement] = swap;
                            watched.removeAt(index);
                            watch(clause[1]).add(id);
                            continue
                        };
                        if (value(other) < 0) {
                            conflict();
                            foundConflict = true;
                            break
                        };
                        if (value(other) == 0) {
                            assign(other,2);
                            stats.propagations++
                        };
                        index++
                    }
                    if (foundConflict) break
                }
                if (foundConflict) {
                    while (trail.isNotEmpty() && trail.last().kind != 0) {
                        val entry = trail.removeAt(trail.lastIndex);
                        assignment[abs(entry.literal)] = 0
                    };
                    if (trail.isEmpty()) return result(false);
                    val decision = trail.removeAt(trail.lastIndex);
                    assignment[abs(decision.literal)] = 0;
                    assign(-decision.literal,1);
                    head = trail.size - 1;
                    continue
                }
                val positive = IntArray(assignment.size);
                val negative = IntArray(assignment.size);
                for (clause in clauses) {
                    if (clause.any {
                        value(it) > 0
                    }) continue;
                    for (literal in clause) if (value(literal) == 0) {
                        if (literal > 0) positive[literal]++ else negative[-literal]++
                    }
                };
                var best = 0;
                var count = 0;
                for (x in 1 until assignment.size) {
                    if (positive[x] > count) {
                        count = positive[x];
                        best = x
                    };
                    if (negative[x] > count) {
                        count = negative[x];
                        best = -x
                    }
                };
                if (best == 0) return result(true);
                assign(best,0);
                stats.decisions++;
                stats.maxDepth = maxOf(stats.maxDepth,trail.count {
                    it.kind != 2
                })
            }
        }
    }
    fun run(variables: Int, clauses: List<IntArray>) = State(variables,clauses).run()
}
