sealed interface Value {
    data class Integer(val value: Long) : Value
    data class BooleanValue(val value: Boolean) : Value
    data class StringValue(val value: String) : Value
    data class PairValue(val first: Value, val second: Value) : Value
    data class ListValue(val values: List<Value>) : Value
    data class Closure(val parameter: Parameter, val body: Expr, val environment: Map<String, Value>) : Value
    data class Builtin(val name: String) : Value
}
typealias ValueEnvironment = Map<String, Value>
class RuntimeError(val position: Position, val reason: String) : Exception(reason)
fun checkedInteger(value: Long, position: Position): Value {
    if (value !in -2147483648L..2147483647L) throw RuntimeError(position, "integer overflow"); return Value.Integer(value)
}
fun compareValues(a: Value, b: Value, position: Position): Int = when {
    a is Value.Integer && b is Value.Integer -> a.value.compareTo(b.value)
    a is Value.BooleanValue && b is Value.BooleanValue -> a.value.compareTo(b.value)
    a is Value.StringValue && b is Value.StringValue -> a.value.compareTo(b.value)
    a is Value.PairValue && b is Value.PairValue -> {
        val first = compareValues(a.first, b.first, position); if (first == 0) compareValues(a.second, b.second, position) else first
    }
    a is Value.ListValue && b is Value.ListValue -> {
        var order = 0; for ((x, y) in a.values.zip(b.values)) {
            order = compareValues(x, y, position); if (order != 0) break
        }; if (order != 0) order else a.values.size.compareTo(b.values.size)
    }
    else -> throw RuntimeError(position, "functional value compared")
}
fun matchPattern(pattern: Pattern, value: Value, bindings: MutableMap<String, Value>): Boolean = when (pattern) {
    is WildPattern -> true
    is NamePattern -> {
        bindings[pattern.name] = value; true
    }
    is IntPattern -> value is Value.Integer && pattern.value == value.value
    is BoolPattern -> value is Value.BooleanValue && pattern.value == value.value
    is StringPattern -> value is Value.StringValue && pattern.value == value.value
    is ConsPattern -> value is Value.ListValue && value.values.isNotEmpty() && matchPattern(pattern.head, value.values[0], bindings) && matchPattern(pattern.tail, Value.ListValue(value.values.drop(1)), bindings)
    is ListPattern -> value is Value.ListValue && pattern.elements.size == value.values.size && pattern.elements.zip(value.values).all {
        (p, v) -> matchPattern(p, v, bindings)
    }
    is PairPattern -> value is Value.PairValue && matchPattern(pattern.first, value.first, bindings) && matchPattern(pattern.second, value.second, bindings)
}
class Evaluator {
    var calls = 0
    fun group(group: Group, environment: ValueEnvironment): Pair<ValueEnvironment, List<Value>> {
        if (group.recursive != null) {
            val shared = environment.toMutableMap(); val values = group.bindings.map {
                binding -> val function = binding.expression as Lambda; Value.Closure(function.parameter, function.body, shared)
            }
            for ((binding, value) in group.bindings.zip(values)) shared[binding.name] = value
            return Pair(shared.toMap(), values)
        }
        val values = group.bindings.map {
            expression(it.expression, environment)
        }; val result = environment.toMutableMap(); for ((binding, value) in group.bindings.zip(values)) result[binding.name] = value
        return Pair(result, values)
    }
    fun apply(function: Value, argument: Value, position: Position): Value {
        calls++
        return when (function) {
            is Value.Closure -> {
                val inner = function.environment.toMutableMap(); function.parameter.name?.let {
                    inner[it] = argument
                }; expression(function.body, inner)
            }; is Value.Builtin -> applyBuiltin(function.name, argument, position); else -> error("not a function")
        }
    }
    fun expression(e: Expr, environment: ValueEnvironment): Value = when (e) {
        is IntExpr -> Value.Integer(e.value)
        is BoolExpr -> Value.BooleanValue(e.value)
        is StringExpr -> Value.StringValue(e.value)
        is NameExpr -> environment.getValue(e.name)
        is Lambda -> Value.Closure(e.parameter, e.body, environment.toMap())
        is Apply -> {
            val function = expression(e.function, environment); val argument = expression(e.argument, environment); apply(function, argument, e.position)
        }
        is Negate -> checkedInteger(-(expression(e.operand, environment) as Value.Integer).value, e.position)
        is Binary -> {
            val left = expression(e.left, environment)
            if (e.op == "&&") {
                if ((left as Value.BooleanValue).value) expression(e.right, environment) else Value.BooleanValue(false)
            }
            else if (e.op == "||") {
                if ((left as Value.BooleanValue).value) Value.BooleanValue(true) else expression(e.right, environment)
            }
            else {
                val right = expression(e.right, environment)
                when (e.op) {
                    "+", "-", "*", "/", "mod" -> {
                        val a = (left as Value.Integer).value; val b = (right as Value.Integer).value; if (e.op in listOf("/", "mod") && b == 0L) throw RuntimeError(e.operatorPosition, "division by zero"); val value = when (e.op) {
                            "+" -> a + b; "-" -> a - b; "*" -> a * b; "/" -> a / b; else -> a - b * (a / b)
                        }; checkedInteger(value, e.operatorPosition)
                    }
                    "^" -> Value.StringValue((left as Value.StringValue).value + (right as Value.StringValue).value)
                    "::" -> Value.ListValue(listOf(left) + (right as Value.ListValue).values)
                    else -> {
                        val order = compareValues(left, right, e.operatorPosition); Value.BooleanValue(when (e.op) {
                            "=" -> order == 0; "<>" -> order != 0; "<" -> order < 0; ">" -> order > 0; "<=" -> order <= 0; else -> order >= 0
                        })
                    }
                }
            }
        }
        is Conditional -> expression(if ((expression(e.condition, environment) as Value.BooleanValue).value) e.yes else e.no, environment)
        is PairExpr -> {
            val first = expression(e.first, environment); val second = expression(e.second, environment); Value.PairValue(first, second)
        }
        is ListExpr -> Value.ListValue(e.elements.map {
            expression(it, environment)
        })
        is Match -> {
            val matched = expression(e.value, environment); var result: Value? = null; for ((pattern, body) in e.arms) {
                val bindings = mutableMapOf<String, Value>(); if (matchPattern(pattern, matched, bindings)) {
                    result = expression(body, environment + bindings); break
                }
            }; result ?: throw RuntimeError(e.position, "match failure")
        }
        is LetIn -> {
            val (inner, _) = group(e.group, environment); expression(e.body, inner)
        }
    }
}
