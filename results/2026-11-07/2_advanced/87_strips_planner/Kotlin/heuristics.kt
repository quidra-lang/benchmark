data class Relaxed(val value: Long, val plan: List<Int>, val helpful: List<Int>)
object Heuristics {
    const val INFINITY = 1_000_000_000_000L
    fun aggregate(values: List<Long>, maximum: Boolean): Long =
    if (values.any {
        it >= INFINITY
    }) INFINITY else if (maximum) values.maxOrNull() ?: 0L else values.sum()
    fun costs(g: Grounding, state: State, maximum: Boolean): LongArray {
        val costs = LongArray(g.facts.size) {
            INFINITY
        }
        for (fact in state) costs[fact] = 0
        while (true) {
            var changed = false
            for (action in g.actions) {
                val previous = aggregate(action.pre.map {
                    costs[it]
                }, maximum)
                if (previous >= INFINITY) continue
                val value = previous + action.cost
                for (fact in action.add) if (value < costs[fact]) {
                    costs[fact] = value; changed = true
                }
            }
            if (!changed) return costs
        }
    }
    fun relaxed(g: Grounding, state: State): Relaxed {
        val costs = costs(g, state, false)
        if (g.goals.any {
            costs[it] >= INFINITY
        }) return Relaxed(INFINITY, emptyList(), emptyList())
        fun achiever(fact: Int): Int = g.actions.indices.filter {
            i ->
            fact in g.actions[i].add && g.actions[i].pre.all {
                costs[it] < INFINITY
            }
        }.minWithOrNull(compareBy<Int> {
            i -> g.actions[i].cost + g.actions[i].pre.sumOf {
                costs[it]
            }
        }.thenBy {
            it
        })!!
        val chosen = mutableSetOf<Int>()
        val pending = (g.goals - state).sorted().toMutableList()
        while (pending.isNotEmpty()) {
            val action = achiever(pending.removeAt(pending.lastIndex))
            if (chosen.add(action)) pending.addAll((g.actions[action].pre - state).sorted())
        }
        val plan = chosen.sorted()
        return Relaxed(plan.sumOf {
            g.actions[it].cost.toLong()
        }, plan, plan.filter {
            Search.applicable(g.actions[it], state)
        })
    }
    fun landmarks(g: Grounding, state: State): State? {
        val factLevel = IntArray(g.facts.size) {
            Int.MAX_VALUE
        }
        val actionLevel = IntArray(g.actions.size) {
            Int.MAX_VALUE
        }
        for (fact in state) factLevel[fact] = 0
        var k = 0
        while (true) {
            var added = false
            for ((i, action) in g.actions.withIndex()) if (actionLevel[i] == Int.MAX_VALUE && action.pre.all {
                factLevel[it] <= k
            }) {
                actionLevel[i] = k
                for (fact in action.add) if (factLevel[fact] == Int.MAX_VALUE) {
                    factLevel[fact] = k + 1; added = true
                }
            }
            if (!added) break
            k++
        }
        if (g.goals.any {
            factLevel[it] == Int.MAX_VALUE
        }) return null
        val landmarks = (g.goals - state).toMutableSet()
        while (true) {
            val before = landmarks.size
            for (fact in landmarks.sorted()) {
                val achievers = g.actions.indices.filter {
                    actionLevel[it] != Int.MAX_VALUE && actionLevel[it] + 1 == factLevel[fact] && fact in g.actions[it].add
                }
                val candidates = g.actions[achievers[0]].pre.toMutableSet()
                for (i in achievers.drop(1)) candidates.retainAll(g.actions[i].pre)
                for (candidate in (candidates - state).sorted()) if (candidate !in landmarks) {
                    val reachable = state.toMutableSet()
                    while (true) {
                        val old = reachable.size
                        for (action in g.actions) if (candidate !in action.add && reachable.containsAll(action.pre)) reachable.addAll(action.add)
                        if (old == reachable.size) break
                    }
                    if (!reachable.containsAll(g.goals)) landmarks.add(candidate)
                }
            }
            if (before == landmarks.size) return landmarks
        }
    }
    fun value(g: Grounding, state: State, name: String): Long = when (name) {
        "none" -> 0L
        "goalcount" -> (g.goals - state).size.toLong()
        "hmax", "hadd" -> {
            val maximum = name == "hmax"; val c = costs(g, state, maximum); aggregate(g.goals.map {
                c[it]
            }, maximum)
        }
        "ff" -> relaxed(g, state).value
        else -> landmarks(g, state)?.size?.toLong() ?: INFINITY
    }
    fun values(g: Grounding, state: State): List<Long> = listOf("goalcount", "hmax", "hadd", "ff", "lmcount").map {
        value(g, state, it)
    }
}
