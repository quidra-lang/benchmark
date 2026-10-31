typealias State = Set<Int>
data class Action(val source: Int, val name: String, val args: List<String>, val cost: Int,
val pre: State, val neg: State, val add: State, val del: State) {
    val text: String get() = Atom(name, args).text
}
data class Grounding(val facts: List<Atom>, val actions: List<Action>, val initial: State, val goals: State,
val unreachable: List<Atom>, val stats: Array<IntArray>, val fluent: Set<String>, val staticCount: Int)
data class GroundCandidate(val source: Int, val args: List<String>, val pre: MutableSet<Atom> = mutableSetOf(),
val neg: MutableSet<Atom> = mutableSetOf(), val add: MutableSet<Atom> = mutableSetOf(), val del: MutableSet<Atom> = mutableSetOf())
fun lexCompare(a: List<Int>, b: List<Int>): Int {
    for (i in 0 until minOf(a.size, b.size)) if (a[i] != b[i]) return a[i].compareTo(b[i])
    return a.size.compareTo(b.size)
}
object Grounder {
    fun subtype(domain: Domain, type: String, expected: String): Boolean {
        var current = type
        while (true) {
            if (current == expected) return true
            current = domain.parents[current] ?: return false
        }
    }
    fun fluents(domain: Domain): Set<String> = domain.actions.flatMap {
        a -> a.effects.map {
            it.atom.predicate
        }
    }.toSet()
    fun ground(domain: Domain, problem: Problem): Grounding {
        val fluent = fluents(domain)
        val initial = problem.initial.toSet()
        val stats = Array(domain.actions.size) {
            IntArray(3)
        }
        val candidates = mutableListOf<GroundCandidate>()
        for ((source, action) in domain.actions.withIndex()) {
            val choices = action.parameters.map {
                p -> problem.objects.filter {
                    subtype(domain, it.type, p.type)
                }.map {
                    it.name
                }
            }
            val all = mutableListOf<List<String>>()
            val current = mutableListOf<String>()
            fun combinations(i: Int) {
                if (i == choices.size) {
                    all.add(current.toList()); return
                }
                for (obj in choices[i]) {
                    current.add(obj); combinations(i + 1); current.removeAt(current.lastIndex)
                }
            }
            combinations(0)
            stats[source][0] = all.size
            for (args in all) {
                val values = action.parameters.map {
                    it.name
                }.zip(args).toMap()
                val candidate = GroundCandidate(source, args)
                var valid = true
                for (literal in action.pre) {
                    val atom = literal.atom.replace(values)
                    if (atom.predicate == "=" || atom.predicate !in fluent) {
                        val truth = if (atom.predicate == "=") atom.terms[0] == atom.terms[1] else atom in initial
                        if (truth == literal.negative) {
                            valid = false; break
                        }
                    } else if (literal.negative) candidate.neg.add(atom) else candidate.pre.add(atom)
                }
                if (!valid) continue
                for (literal in action.effects) {
                    val atom = literal.atom.replace(values)
                    if (literal.negative) candidate.del.add(atom) else candidate.add.add(atom)
                }
                candidate.del.removeAll(candidate.add)
                stats[source][1]++
                candidates.add(candidate)
            }
        }
        val reachable = initial.filter {
            it.predicate in fluent
        }.toMutableSet()
        val kept = mutableSetOf<Int>()
        while (true) {
            val before = kept.size
            for ((i, candidate) in candidates.withIndex()) if (reachable.containsAll(candidate.pre)) {
                kept.add(i); reachable.addAll(candidate.add)
            }
            if (kept.size == before) break
        }
        val predicates = domain.predicates.withIndex().associate {
            it.value.name to it.index
        }
        val objects = problem.objects.withIndex().associate {
            it.value.name to it.index
        }
        val facts = reachable.sortedWith(Comparator {
            a, b ->
            val order = predicates.getValue(a.predicate).compareTo(predicates.getValue(b.predicate))
            if (order != 0) order else lexCompare(a.terms.map {
                objects.getValue(it)
            }, b.terms.map {
                objects.getValue(it)
            })
        })
        val numbering = facts.withIndex().associate {
            it.value to it.index
        }
        fun numbers(atoms: Set<Atom>): State = atoms.mapNotNull {
            numbering[it]
        }.toSet()
        val actions = kept.sorted().map {
            i ->
            val candidate = candidates[i]
            val action = domain.actions[candidate.source]
            stats[candidate.source][2]++
            Action(candidate.source, action.name, candidate.args, action.cost, numbers(candidate.pre), numbers(candidate.neg), numbers(candidate.add), numbers(candidate.del))
        }
        val goals = mutableSetOf<Int>()
        val unreachable = mutableListOf<Atom>()
        for (atom in problem.goals) {
            val i = numbering[atom]
            if (i != null) goals.add(i) else if (atom.predicate in fluent || atom !in initial) unreachable.add(atom)
        }
        return Grounding(facts, actions, numbers(initial), goals, unreachable, stats, fluent, problem.initial.count {
            it.predicate !in fluent
        })
    }
}
