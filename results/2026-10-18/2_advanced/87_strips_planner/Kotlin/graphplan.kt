data class MutexPair private constructor(val a: Int, val b: Int) {
    companion object {
        fun of(a: Int, b: Int): MutexPair = MutexPair(minOf(a, b), maxOf(a, b))
    }
}
typealias Mutex = Set<MutexPair>
data class GraphElement(val action: Int?, val pre: State, val add: State, val del: State)
data class GraphLevel(val elements: List<GraphElement>, val mutex: Mutex)
data class MemoKey(val level: Int, val goals: List<Int>)
class Extractor {
    val levels = mutableListOf<GraphLevel>()
    val memo = mutableSetOf<MemoKey>()
    var searched = 0
    var hits = 0
    var tried = 0
    fun extract(level: Int, goals: List<Int>): List<List<Int>>? {
        if (level == 0) return emptyList()
        val key = MemoKey(level, goals)
        if (key in memo) {
            hits++; return null
        }
        searched++
        val result = assign(level, goals, 0, emptyList())
        if (result == null) memo.add(key)
        return result
    }
    fun assign(j: Int, goals: List<Int>, position: Int, chosen: List<Int>): List<List<Int>>? {
        val level = levels[j - 1]
        var k = position
        while (k < goals.size && chosen.any {
            goals[k] in level.elements[it].add
        }) k++
        if (k == goals.size) {
            val previous = chosen.flatMap {
                level.elements[it].pre
            }.toSet().sorted()
            val plan = extract(j - 1, previous) ?: return null
            return plan + listOf(chosen.mapNotNull {
                level.elements[it].action
            }.sorted())
        }
        val goal = goals[k]
        val achievers = level.elements.indices.filter {
            goal in level.elements[it].add
        }.sortedWith(compareBy<Int> {
            if (level.elements[it].action == null) 0 else 1
        }.thenBy {
            level.elements[it].action ?: 0
        })
        for (x in achievers) if (chosen.all {
            x == it || MutexPair.of(x, it) !in level.mutex
        }) {
            tried++
            val plan = assign(j, goals, k + 1, chosen + x)
            if (plan != null) return plan
        }
        return null
    }
}
data class GraphResult(val search: SearchResult, val layers: List<List<Int>>, val records: List<String>, val hits: Int)
object GraphPlan {
    fun compatible(pre: State, mutex: Mutex): Boolean = pre.all {
        p -> pre.all {
            q -> p == q || MutexPair.of(p, q) !in mutex
        }
    }
    fun run(actions: List<Action>, initial: State, goals: State, limit: Int): GraphResult {
        val extractor = Extractor()
        var facts = initial
        var mutex: Mutex = emptySet()
        var previous: Pair<Int, Int>? = null
        val records = mutableListOf<String>()
        var answer = emptyList<List<Int>>()
        var status = "level limit"
        for (i in 0..limit) {
            records.add("fact level $i: facts=${facts.size} mutexes=${mutex.size}")
            val extract = facts.containsAll(goals) && compatible(goals, mutex)
            if (extract) {
                val before = extractor.searched
                val hits = extractor.hits
                val result = extractor.extract(i, goals.sorted())
                records.add("extract level $i: ${if (result == null) "fail" else "success"} searched=${extractor.searched - before} memo_hits=${extractor.hits - hits}")
                if (result != null) {
                    answer = result; status = "solved"; break
                }
            } else if (previous == Pair(facts.size, mutex.size)) {
                status = "unreachable"; break
            }
            if (i == limit) break
            previous = Pair(facts.size, mutex.size)
            val elements = actions.mapIndexedNotNull {
                index, action ->
                if (facts.containsAll(action.pre) && compatible(action.pre, mutex)) GraphElement(index, action.pre, action.add, action.del) else null
            }.toMutableList()
            val real = elements.size
            for (fact in facts.sorted()) elements.add(GraphElement(null, setOf(fact), setOf(fact), emptySet()))
            val actionMutex = mutableSetOf<MutexPair>()
            for (x in elements.indices) for (y in x + 1 until elements.size) {
                val a = elements[x]
                val b = elements[y]
                val interference = a.del.any {
                    it in b.pre || it in b.add
                } || b.del.any {
                    it in a.pre || it in a.add
                }
                val competing = a.pre.any {
                    p -> b.pre.any {
                        q -> p != q && MutexPair.of(p, q) in mutex
                    }
                }
                if (interference || competing) actionMutex.add(MutexPair.of(x, y))
            }
            records.add("action level $i: actions=$real noops=${facts.size} mutexes=${actionMutex.size}")
            val next = elements.flatMap {
                it.add
            }.toSet()
            val values = next.sorted()
            val nextMutex = mutableSetOf<MutexPair>()
            for (x in values.indices) for (y in x + 1 until values.size) {
                val p = values[x]
                val q = values[y]
                val impossible = elements.indices.filter {
                    p in elements[it].add
                }.all {
                    a ->
                    elements.indices.filter {
                        q in elements[it].add
                    }.all {
                        b -> a != b && MutexPair.of(a, b) in actionMutex
                    }
                }
                if (impossible) nextMutex.add(MutexPair.of(p, q))
            }
            extractor.levels.add(GraphLevel(elements, actionMutex))
            facts = next; mutex = nextMutex
        }
        return GraphResult(SearchResult(status, answer.flatten(), extractor.searched, extractor.tried), answer, records, extractor.hits)
    }
}
