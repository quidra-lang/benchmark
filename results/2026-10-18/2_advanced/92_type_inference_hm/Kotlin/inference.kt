sealed interface TypeErrorKind {
    data class Message(val text: String) : TypeErrorKind
    data class Function(val type: MLType) : TypeErrorKind
    data class Check(val expected: MLType, val found: MLType, val failure: UnifyFailure) : TypeErrorKind
}
class TypeError(val position: Position, val kind: TypeErrorKind) : Exception()
data class Local(val name: String, val position: Position, val scheme: Scheme)
class Inference {
    val unifier = Unifier()
    val locals = mutableListOf<Local>()
    val matches = mutableMapOf<Position, Pair<MLType, List<Pattern>>>()
    fun clear() {
        locals.clear(); matches.clear()
    }
    fun message(position: Position, message: String): TypeError = TypeError(position, TypeErrorKind.Message(message))
    fun check(expected: MLType, found: MLType, position: Position) {
        try {
            unifier.unify(expected, found)
        } catch (failure: UnifyFailure) {
            throw TypeError(position, TypeErrorKind.Check(expected, found, failure))
        }
    }
    fun group(group: Group, environment: TypeEnvironment, local: Boolean): Pair<TypeEnvironment, List<Scheme>> {
        val names = mutableSetOf<String>()
        for (binding in group.bindings) {
            if (!names.add(binding.name)) throw message(binding.position, "variable '${binding.name}' is bound twice in this let")
            if (group.recursive != null && binding.expression !is Lambda) throw message(binding.position, "'${binding.name}' in let rec must be a function")
        }
        val recursive = environment.toMutableMap(); val types = mutableListOf<MLType>()
        if (group.recursive != null) {
            for (binding in group.bindings) {
                val type = unifier.fresh(); recursive[binding.name] = Scheme(type); types.add(type)
            }
            for ((i, binding) in group.bindings.withIndex()) {
                val found = expression(binding.expression, recursive); check(types[i], found, binding.position)
            }
        } else {
            for (binding in group.bindings) types.add(expression(binding.expression, environment))
        }
        val schemes = types.map {
            unifier.generalize(it, environment)
        }; val result = environment.toMutableMap()
        for ((binding, scheme) in group.bindings.zip(schemes)) {
            result[binding.name] = scheme; if (local) locals.add(Local(binding.name, binding.position, scheme))
        }
        return Pair(result, schemes)
    }
    fun expression(e: Expr, environment: TypeEnvironment): MLType = when (e) {
        is IntExpr -> MLType.IntType
        is BoolExpr -> MLType.BoolType
        is StringExpr -> MLType.StringType
        is NameExpr -> {
            val scheme = environment[e.name]
            if (scheme != null) unifier.instantiate(scheme)
            else {
                val candidate = environment.keys.map {
                    Pair(editDistance(e.name, it), it)
                }.filter {
                    it.first <= 2 && it.first < e.name.length
                }.minWithOrNull(compareBy<Pair<Int, String>> {
                    it.first
                }.thenBy {
                    it.second
                }); throw message(e.position, "unbound variable '${e.name}'" + (candidate?.let {
                    " (did you mean '${it.second}'?)"
                } ?: ""))
            }
        }
        is Lambda -> {
            val argument = unifier.fresh(); val inner = environment.toMutableMap(); e.parameter.name?.let {
                inner[it] = Scheme(argument)
            }; val result = expression(e.body, inner); MLType.Function(argument, result)
        }
        is Apply -> {
            val function = unifier.resolve(expression(e.function, environment)); val expected: MLType; val result: MLType
            when (function) {
                is MLType.Variable -> {
                    expected = unifier.fresh(); result = unifier.fresh(); unifier.bind(function.id, MLType.Function(expected, result))
                }; is MLType.Function -> {
                    expected = function.argument; result = function.result
                }; else -> throw TypeError(e.function.position, TypeErrorKind.Function(function))
            }
            val found = expression(e.argument, environment); check(expected, found, e.argument.position); result
        }
        is Binary -> {
            val a: MLType; val b: MLType; val result: MLType
            when (e.op) {
                "+", "-", "*", "/", "mod" -> {
                    a = MLType.IntType; b = a; result = a
                }; "^" -> {
                    a = MLType.StringType; b = a; result = a
                }; "&&", "||" -> {
                    a = MLType.BoolType; b = a; result = a
                }; "::" -> {
                    a = unifier.fresh(); b = MLType.ListType(a); result = b
                }; else -> {
                    a = unifier.fresh(); b = a; result = MLType.BoolType
                }
            }
            val first = expression(e.left, environment); check(a, first, e.left.position); val second = expression(e.right, environment); check(b, second, e.right.position); result
        }
        is Negate -> {
            val found = expression(e.operand, environment); check(MLType.IntType, found, e.operand.position); MLType.IntType
        }
        is Conditional -> {
            val found = expression(e.condition, environment); check(MLType.BoolType, found, e.condition.position); val a = expression(e.yes, environment); val b = expression(e.no, environment); check(a, b, e.no.position); a
        }
        is PairExpr -> {
            val first = expression(e.first, environment); val second = expression(e.second, environment); MLType.PairType(first, second)
        }
        is ListExpr -> {
            val type = unifier.fresh(); for (element in e.elements) {
                val found = expression(element, environment); check(type, found, element.position)
            }; MLType.ListType(type)
        }
        is Match -> {
            val type = expression(e.value, environment); val result = unifier.fresh()
            for ((pattern, body) in e.arms) {
                val bindings = mutableMapOf<String, MLType>(); val found = this.pattern(pattern, bindings); check(type, found, pattern.position); val inner = environment.toMutableMap(); bindings.forEach {
                    (name, type) -> inner[name] = Scheme(type)
                }; val bodyType = expression(body, inner); check(result, bodyType, body.position)
            }
            matches[e.position] = Pair(type, e.arms.map {
                it.first
            }); result
        }
        is LetIn -> {
            val (inner, _) = group(e.group, environment, true); expression(e.body, inner)
        }
    }
    fun pattern(p: Pattern, bindings: MutableMap<String, MLType>): MLType = when (p) {
        is WildPattern -> unifier.fresh()
        is NamePattern -> {
            if (p.name in bindings) throw message(p.position, "variable '${p.name}' is bound twice in this pattern"); val type = unifier.fresh(); bindings[p.name] = type; type
        }
        is IntPattern -> MLType.IntType
        is BoolPattern -> MLType.BoolType
        is StringPattern -> MLType.StringType
        is ConsPattern -> {
            val type = unifier.fresh(); val head = pattern(p.head, bindings); check(type, head, p.head.position); val tail = pattern(p.tail, bindings); val list = MLType.ListType(type); check(list, tail, p.tail.position); list
        }
        is ListPattern -> {
            val type = unifier.fresh(); for (element in p.elements) {
                val found = pattern(element, bindings); check(type, found, element.position)
            }; MLType.ListType(type)
        }
        is PairPattern -> {
            val first = pattern(p.first, bindings); val second = pattern(p.second, bindings); MLType.PairType(first, second)
        }
    }
}
