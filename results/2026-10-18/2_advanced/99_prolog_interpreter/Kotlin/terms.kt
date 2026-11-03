data class Indicator(val name: String, val arity: Int)
sealed interface Term {
    data class Integer(val value: Long) : Term
    data class Atom(val name: String) : Term
    data class Variable(val id: Int) : Term
    data class Compound(val name: String, val args: List<Term>) : Term
    val indicator: Indicator? get() = when (this) {
        is Atom -> Indicator(name, 0)
        is Compound -> Indicator(name, args.size)
        else -> null
    }
    val arguments: List<Term> get() = (this as? Compound)?.args ?: emptyList()
    val variableID: Int? get() = (this as? Variable)?.id
}
class Store {
    val bindings = mutableListOf<Term?>()
    fun clone(): Store = Store().also {
        it.bindings.addAll(bindings)
    }
    fun fresh(): Term {
        val result = Term.Variable(bindings.size)
        bindings.add(null)
        return result
    }
    fun dereference(term: Term): Term {
        var result = term
        while (result is Term.Variable) {
            result = bindings[result.id] ?: break
        }
        return result
    }
    fun copy(term: Term): Term = copy(term, mutableMapOf())
    fun copyMany(terms: List<Term>): List<Term> {
        val names = mutableMapOf<Int, Term>()
        return terms.map {
            copy(it, names)
        }
    }
    private fun copy(term: Term, names: MutableMap<Int, Term>): Term = when (val value = dereference(term)) {
        is Term.Variable -> names.getOrPut(value.id) {
            fresh()
        }
        is Term.Compound -> Term.Compound(value.name, value.args.map {
            copy(it, names)
        })
        else -> value
    }
    fun parts(term: Term): Pair<List<Term>, Term> {
        val elements = mutableListOf<Term>()
        var tail = dereference(term)
        while (tail is Term.Compound && tail.name == "." && tail.args.size == 2) {
            elements.add(tail.args[0])
            tail = dereference(tail.args[1])
        }
        return elements to tail
    }
    fun variables(terms: List<Term>): List<Int> {
        val pending = terms.asReversed().toMutableList()
        val result = mutableListOf<Int>()
        while (pending.isNotEmpty()) {
            when (val term = dereference(pending.removeAt(pending.lastIndex))) {
                is Term.Variable -> result.add(term.id)
                is Term.Compound -> pending.addAll(term.args.asReversed())
                else -> Unit
            }
        }
        return result
    }
}
fun list(elements: List<Term>, tail: Term = Term.Atom("[]")): Term = elements.asReversed().fold(tail) {
    rest, element -> Term.Compound(".", listOf(element, rest))
}
fun indicatorTerm(key: Indicator): Term = Term.Compound("/", listOf(Term.Atom(key.name), Term.Integer(key.arity.toLong())))
fun typeError(kind: String, term: Term): Term = Term.Compound("type_error", listOf(Term.Atom(kind), term))
fun domainError(kind: String, term: Term): Term = Term.Compound("domain_error", listOf(Term.Atom(kind), term))
fun errorBall(error: Term, key: Indicator): Term = Term.Compound("error", listOf(error, indicatorTerm(key)))
class PrologError(val term: Term) : Exception()
fun sameKind(a: Term, b: Term, store: Store): Boolean {
    val x = store.dereference(a)
    val y = store.dereference(b)
    if (x is Term.Variable || y is Term.Variable) return true
    return when {
        x is Term.Integer && y is Term.Integer -> x.value == y.value
        x is Term.Atom && y is Term.Atom -> x.name == y.name
        x is Term.Compound && y is Term.Compound -> x.name == y.name && x.args.size == y.args.size
        else -> false
    }
}
