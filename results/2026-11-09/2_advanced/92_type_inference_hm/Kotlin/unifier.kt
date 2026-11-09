sealed interface MLType {
    data object IntType : MLType
    data object BoolType : MLType
    data object StringType : MLType
    data class Variable(val id: Int) : MLType
    data class ListType(val element: MLType) : MLType
    data class PairType(val first: MLType, val second: MLType) : MLType
    data class Function(val argument: MLType, val result: MLType) : MLType
}
data class Scheme(val type: MLType, val quantified: Set<Int> = emptySet())
typealias TypeEnvironment = Map<String, Scheme>
class UnifyFailure(val expected: MLType, val found: MLType, val occurs: Boolean, val nested: Boolean) : Exception()
class Unifier {
    val bindings = mutableListOf<MLType?>()
    fun fresh(): MLType.Variable {
        val id = bindings.size; bindings.add(null); return MLType.Variable(id)
    }
    fun resolve(type: MLType): MLType = when (type) {
        is MLType.Variable -> bindings[type.id]?.let {
            resolve(it)
        } ?: type
        is MLType.ListType -> MLType.ListType(resolve(type.element))
        is MLType.PairType -> MLType.PairType(resolve(type.first), resolve(type.second))
        is MLType.Function -> MLType.Function(resolve(type.argument), resolve(type.result))
        else -> type
    }
    fun variables(type: MLType): Set<Int> = when (val t = resolve(type)) {
        is MLType.Variable -> setOf(t.id)
        is MLType.ListType -> variables(t.element)
        is MLType.PairType -> variables(t.first) + variables(t.second)
        is MLType.Function -> variables(t.argument) + variables(t.result)
        else -> emptySet()
    }
    fun bind(id: Int, type: MLType) {
        bindings[id] = type
    }
    fun unify(expected: MLType, found: MLType, nested: Boolean = false) {
        val e = resolve(expected); val f = resolve(found)
        if (e == f) return
        if (e is MLType.Variable) {
            if (e.id in variables(f)) throw UnifyFailure(e, f, true, nested); bind(e.id, f); return
        }
        if (f is MLType.Variable) {
            if (f.id in variables(e)) throw UnifyFailure(e, f, true, nested); bind(f.id, e); return
        }
        when {
            e is MLType.ListType && f is MLType.ListType -> unify(e.element, f.element, true)
            e is MLType.PairType && f is MLType.PairType -> {
                unify(e.first, f.first, true); unify(e.second, f.second, true)
            }
            e is MLType.Function && f is MLType.Function -> {
                unify(e.argument, f.argument, true); unify(e.result, f.result, true)
            }
            else -> throw UnifyFailure(e, f, false, nested)
        }
    }
    fun generalize(type: MLType, environment: TypeEnvironment): Scheme {
        val variables = variables(type).toMutableSet()
        for (scheme in environment.values) variables.removeAll(this.variables(scheme.type) - scheme.quantified)
        return Scheme(type, variables)
    }
    fun instantiate(scheme: Scheme): MLType {
        val replacements = scheme.quantified.sorted().associateWith {
            fresh()
        }
        fun replace(type: MLType): MLType = when (type) {
            is MLType.Variable -> replacements[type.id] ?: type
            is MLType.ListType -> MLType.ListType(replace(type.element))
            is MLType.PairType -> MLType.PairType(replace(type.first), replace(type.second))
            is MLType.Function -> MLType.Function(replace(type.argument), replace(type.result))
            else -> type
        }
        return replace(resolve(scheme.type))
    }
}
