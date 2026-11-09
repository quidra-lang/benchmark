data class Clause(val head: Term, val body: Term?, val file: String, val line: Int)
data class Predicate(val indicator: Indicator, val clauses: MutableList<Clause> = mutableListOf())
class Database {
    val predicates = mutableListOf<Predicate>()
    fun find(key: Indicator): Int? = predicates.indexOfFirst {
        it.indicator == key
    }.takeIf {
        it >= 0
    }
    fun candidates(index: Int, goal: Term, store: Store): List<Int> = predicates[index].clauses.indices.filter {
        goal.arguments.isEmpty() || sameKind(goal.arguments[0], predicates[index].clauses[it].head.arguments[0], store)
    }
    fun copy(predicate: Int, clause: Int, store: Store): Pair<Term, Term?> {
        val source = predicates[predicate].clauses[clause]
        val copies = store.copyMany(listOfNotNull(source.head, source.body))
        return copies[0] to copies.getOrNull(1)
    }
}
